# Turns and Resolution

The combat loop: whose turn it is, what an action is, how it resolves, and the discipline that keeps resolution pure. This is where the skill's spine lives.

## Contents

- [Initiative and the action economy](#initiative-and-the-action-economy)
- [Round and turn flow](#round-and-turn-flow)
- [The resolution pipeline](#the-resolution-pipeline)
- [Actions as data: the action/effect model](#actions-as-data-the-actioneffect-model)
- [The damage roll](#the-damage-roll)
- [Status effects](#status-effects)
- [Victory and defeat](#victory-and-defeat)
- [Resolution vs. presentation, in depth](#resolution-vs-presentation-in-depth)

## Initiative and the action economy

⚠️ **Anime 5E specifics are unverified** (see SKILL.md). The assumed model is 5e-derived: roll `d20 + DEX mod` once per combatant at encounter start, sort descending into a turn order reused each round; per turn a unit gets an action + bonus action + movement + a reaction.

The tutorials use a simpler model worth knowing as the fallback shape:
- **Two-flag economy** per unit: `canMove` and `canAct`, both set true at turn start, each cleared when spent. Command availability is gated on the flags.
- **Faction alternation** instead of an initiative queue: a player force and an enemy force, each a list of units; the active force acts, hands off when exhausted, and a round advances when both sides are done.
- A **round manager** holds the roster (units self-register), counts rounds, and re-grants turns to everyone on `NextRound`.

For the CRPG, replace faction alternation with the initiative queue if Anime 5E calls for individual initiative, and layer the reaction (opportunity attacks, readied/overwatch actions) on top of the two-flag base. All of this is grid-free already — initiative and action economy never depended on tiles.

## Round and turn flow

Keep the loop as **pure state transitions**, with the active unit, remaining action economy, and round number all living in the combat state object (not in scene components):

1. Determine active unit from the initiative order.
2. Accept a validated action (player intent or AI choice).
3. Resolve it → new state + `ActionResult`; hand the result to presentation.
4. When the unit's economy is spent (or it ends its turn), advance to the next unit; wrap to a new round at the end of the order.

"Whose turn it is" and "who may act" are **state**, not input flags. The tutorials toggle the player's mouse-input component on the enemy turn; instead, derive input-enabled from turn-ownership state and let the input layer react. Turn advance fires on a logical "action resolved" signal — never on an animation finishing (see the final section).

## The resolution pipeline

One function is the whole game's rules surface:

```csharp
// Pure: no UnityEngine, no coroutine, no animation, no waiting.
ActionResult Resolve(CombatState state, GameAction action);
```

It validates the action against the current state (in range? in budget? has LoS? economy available?), applies the outcome to the state, and returns an **`ActionResult`** — a plain-data record of everything that happened:

```csharp
public sealed class ActionResult
{
    public bool Legal;                 // false → rejected, state unchanged
    public ActorId Actor;
    public Vector3 FromPos, ToPos;     // for a move: the resolved path endpoints
    public IReadOnlyList<Vector3> Path; // resolved corners, for the walk animation
    public IReadOnlyList<HitOutcome> Hits; // per-target: hit/miss, crit, damage, lethal
    public IReadOnlyList<StatusChange> Statuses;
    public EncounterOutcome Encounter; // ongoing / victory / defeat
    // ...purely descriptive. Presentation reads this; it never recomputes.
}
```

Two design choices keep this honest:
- **State in, state + result out.** Either mutate a passed-in mutable state and emit the result, or (cleaner for AI/replay) treat `CombatState` as immutable and return a new state. Immutable-with-structural-sharing makes "clone and simulate" free for the AI.
- **No engine types leak in.** The pipeline shouldn't import `UnityEngine`. Pathing/LoS, which need Unity, sit behind injected interfaces so the resolver stays testable. (The dedicated treatment is `engine-independent-core.md` once added; this reference establishes *why* the boundary exists.)

## Actions as data: the action/effect model

The strongest pattern in the source material (from the jam-tactics and XCOM-in-25-hours videos): **every player or AI intent is an Action, and actions are composed of reusable Effects.**

- A **GameAction** carries: the actor, a **target-selection strategy** (point / unit / line / cone / radius), a range/budget, and an ordered list of **Effects**.
- An **Effect** is one atomic outcome: deal damage, apply a status, move the actor, spend a resource, heal. Compose them to get new abilities without bespoke code per ability.
- A single **resolver** ("given a chosen action + target, run its effects against the state") centralizes execution, so player and AI share one pipeline.

Borrow the *target-selection strategy* idea directly, but make the strategies world-space shapes (see `movement-and-targeting.md`), not "single cell / line of cells". One honest lesson from the jam post-mortem: don't model each Effect as a separate authored asset that must be duplicated per ability — define effects in code and instantiate them as data at runtime, or you drown in near-identical asset variants.

The command-pattern plumbing in the tutorials (an input layer gathers intent → produces a `Command` → a manager executes it) is a fine **dispatch shape**. Adopt the shape, **reject the execution model**: in the tutorials `Command.Execute` *is* the movement coroutine/animation. Here, a command produces a validated `GameAction`, the resolver returns an `ActionResult`, and presentation plays it.

## The damage roll

The tutorials converge on a clean, pure damage model — emulate it (it has almost no animation coupling, unlike the attack *flow* around it):

1. **Hit:** roll against accuracy vs. the target's dodge; apply cover as a hit-chance penalty (partial/full from `movement-and-targeting.md`).
2. **Crit:** on hit, roll against crit chance; multiply on success.
3. **Mitigation by damage type:** a `DamageType` (e.g. Physical/Magical) selects Armor or Resistance to subtract.
4. **Floor:** clamp to a minimum (the tutorials use 1) so every hit does something.

Derive offense/defense from attributes through single-source getters (`GetDamage(type)`, `GetDefense(type)`) rather than scattering formulas. Keep the **RNG injectable and seeded** (passed in, stored in state) — never `UnityEngine.Random` static — so the same encounter replays identically and tests are deterministic. The detailed determinism rationale belongs in `testing-and-determinism.md` once added; the rule to follow now is: *all randomness flows through a seed held in the combat state.*

## Status effects

Not covered by the tutorials — design them as data on the state: a list of active statuses per unit, each with a type, magnitude, and remaining duration. Resolve their ticks at defined points (turn start/end) as ordinary state transitions that emit `StatusChange` entries in an `ActionResult`. Keep them pure: a poison tick is resolution, the floating "-3" is presentation.

## Victory and defeat

Evaluate the encounter outcome **synchronously, inside resolution, immediately after HP is applied** — as a pure function of who is still alive (e.g. "all enemies defeated" → victory; "all players defeated" → defeat). The tutorials check victory when an attack command's *animation* completes; that's the entanglement to avoid. Emit the outcome on the `ActionResult` (`Encounter = Victory/Defeat/Ongoing`); the victory panel, input lock, and scene transition are presentation reactions to that field, not part of the check.

## Resolution vs. presentation, in depth

This is the rule from SKILL.md, made concrete. The tutorials repeatedly entangle the two; here is each trap and its fix.

| Tutorial anti-pattern | Why it breaks | Fix |
|---|---|---|
| Damage applied by an animation event mid-attack | Outcome depends on playback speed; untestable; AI can't simulate | Resolve damage into `ActionResult` at decision time; impact frame *shows* the pre-resolved number |
| Turn advance gated on an `isMoving` / "not animated" flag (often polled in `LateUpdate`) | Rules block on the view; can't fast-forward, sim, or test | Advance on a logical "resolved" signal; presentation drains an animation queue the rules never wait on |
| Movement executed by the command's coroutine (`Execute` *is* the walk) | State change and animation are the same code | Resolve final position + path synchronously; a separate locomotion layer animates the path from the result |
| Victory checked on attack-animation completion | Outcome timing tied to a clip | Evaluate victory in resolution right after HP applied |
| Health/status UI polled every `Update` | Wasteful; view becomes a second source of truth | Refresh from `ActionResult` / change events |
| Reading Animator state back into logic (`Has Exit Time`, clip progress) | Two-way coupling; "animator catching up" lag drives state | One-way seam only: resolved outcome → Animator bools/triggers |

The payoff of holding this line: the same `Resolve` function powers the live game, the unit tests, the enemy AI's look-ahead (resolve against a cloned state, read the `ActionResult`, score it — see `enemy-ai.md`), and save/replay (a sequence of actions + a seed reproduces a battle). Presentation becomes a pure function of the result stream and can be sped up, skipped, or re-skinned without touching a rule.
