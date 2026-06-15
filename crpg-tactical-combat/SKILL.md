---
name: crpg-tactical-combat
description: Use this skill to build turn-based tactical combat with NO grid — free positioning in continuous 3D space — for a Unity 6 CRPG on the Anime 5E ruleset. Covers movement as NavMesh path-length budgets, world-space range/area targeting, raycast line-of-sight and cover, elevation, initiative and action economy, the pure ActionResult resolution pipeline, status effects, enemy AI that simulates outcomes, combat forecast UI, encounter setup, save/load, and architecting the rules as a deterministic, engine-independent C# core (own .asmdef, no UnityEngine) so combat is unit-testable and replayable. Trigger on tactical/turn-based combat, initiative, action economy, movement range, line of sight, cover, area of effect, ability resolution, damage roll, enemy AI, NavMesh movement budget, ActionResult, combat forecast, XCOM-like, Fire Emblem-like, adapting grid/tile tactics tutorials to free movement, combat architecture, determinism, seeded RNG, Edit Mode tests, and combat save/load. Targets Unity 6 + URP.
---

# No-Grid Tactical Combat (Unity 6, Anime 5E)

This skill is for building **turn-based tactical combat with no grid** — units stand and move at arbitrary world positions in continuous 3D space, not on tiles. The target is a Unity 6 CRPG using the **Anime 5E** ruleset.

Most tactics tutorials (Fire Emblem / Final Fantasy Tactics / XCOM clones) are tile-based: a `Tile[,]`, BFS/Dijkstra over cells, integer coordinates, adjacency. **None of that applies here.** The continuous-space equivalents — NavMesh path-length budgets, world-space distance and shape checks, and raycast line-of-sight — are the spine of this skill. When you read a grid tutorial, translate; don't transcribe (see the translation table below).

## The one rule that governs everything

**Resolution is pure and synchronous, and completely separate from presentation.**

An action is resolved by a function that takes the current combat state plus a chosen action and returns *(new state, `ActionResult`)* — with no `UnityEngine` calls, no coroutines, no animation, no waiting. The `ActionResult` is a plain-data record of what happened (who moved where, hit/miss, damage per target, who died, status applied). Presentation — animation, VFX, camera, UI — *reads* the `ActionResult` and plays it back. Presentation never computes outcomes, and game state never advances because an animation finished.

This is the single most important thing the grid tutorials get wrong. Across the source material, damage is applied from inside an attack animation, turn flow is gated on an `isMoving` flag flipped by a movement coroutine, and victory is checked when an attack command's animation completes. **Invert all of it:** resolve first, synchronously, into an `ActionResult`; animate as a consequence. This rule makes combat unit-testable, lets enemy AI simulate outcomes by resolving against a cloned state, and makes save/replay possible. `references/turn-and-resolution.md` is the deep treatment.

The strongest form of this rule is structural: put the rules in their own assembly (`.asmdef`) that **cannot reference `UnityEngine`**, so the compiler — not your discipline — enforces the boundary. The `CombatState` is then a plain-data graph (its own `Vec3`, not `UnityEngine.Vector3`); engine services it genuinely needs (NavMesh path cost, raycast LoS) come in through injected interfaces. That single choice is what makes testing, AI simulation, and deterministic save/replay all fall out at once — see `references/engine-independent-core.md` and `references/testing-and-determinism.md`.

## The no-grid mental model

| Concern | Grid answer (don't use) | No-grid answer (use this) |
|---|---|---|
| Where can a unit stand? | walkable cells in a `Node[,]` | any point on the baked **NavMesh** (`NavMesh.SamplePosition`) |
| How far can it move? | BFS/Dijkstra cell count within move points | **NavMesh path length in meters** vs a move budget — sum `Vector3.Distance` over `NavMeshPath.corners` |
| Is a target in range? | cell distance ≤ N | `Vector3.Distance ≤ range`, optionally constrained to a **cone/sphere/line** shape |
| Area of effect | center cell + neighbor cells | `Physics.OverlapSphere` (or shape query) from the impact point |
| Can A see/hit B? | tile blocking / adjacency | **`Physics.Linecast` / raycast** against occluder colliders |
| Cover | adjacency to a cover tile | partial vs full **ray occlusion** between shooter and target |
| Elevation | scalar stored per cell | sample ground Y on demand (downward ray / `NavMesh.SamplePosition`); climb = grade limit |
| Reachable-area display | highlighted cells | projected **decal / ring / sampled NavMesh points** |
| Occupancy / selection | one unit per cell, cell lookup | raycast the unit's collider; a unit registry keyed by reference, not coordinate |

The detailed treatment of the movement/targeting half lives in `references/movement-and-targeting.md`.

## Anime 5E assumptions — confirm before building rules

The ruleset is "Anime 5E", which the source material does **not** define. This skill assumes a **D&D 5e-derived** model until told otherwise:

- **Initiative:** each combatant rolls `d20 + DEX modifier` once at encounter start; turns run in descending order, re-used each round. (Alternative: a speed-sorted or faction-alternating order — also grid-free; the tutorials use simple faction alternation.)
- **Action economy:** one **action** + one **bonus action** + **movement** + one **reaction** per turn. The tutorials instead use a simpler two-flag economy (`canMove` / `canAct`); 5e's reaction (e.g. opportunity attacks, overwatch-style readied actions) is an addition.

⚠️ **These are assumptions, not verified facts.** Before implementing initiative or the action economy, confirm the Anime 5E specifics with the project owner. The rest of the architecture (resolution purity, NavMesh budgets, raycast LoS) is independent of which exact numbers win.

## Where to go next

The references are narrow on purpose. Load only what the task needs.

| Reference | Load when working on… |
|---|---|
| `references/movement-and-targeting.md` | Movement as NavMesh path-length budgets, reachability visualization, world-space range/area targeting (sphere/cone/line), raycast line-of-sight and cover, elevation/height and climb limits, unit selection by raycast. |
| `references/turn-and-resolution.md` | Initiative and the action economy, round/turn flow, the pure resolution pipeline and `ActionResult`, the action/effect model, the damage roll (hit/crit/armor/resistance), status effects, victory/defeat conditions, and the resolution-vs-presentation discipline in depth. |
| `references/enemy-ai.md` | Enemy turn processing, utility/scoring AI that **simulates** candidate actions by resolving them against a cloned combat state, target selection, and difficulty knobs. Depends on the cloneable pure state from `turn-and-resolution.md`. |
| `references/encounter-and-data.md` | Encounter/scene setup, additive scene flow (persistent systems + swappable battlefield), ScriptableObject data definitions vs runtime instances, items/equipment/consumables, and save/load via JSON + stable GUIDs. |
| `references/engine-independent-core.md` | Architecting the rules as a pure C# core in its own `.asmdef` with no `UnityEngine` dependency: what lives in the core vs the Unity layer, `CombatState` as a plain-data graph, ports for engine services (NavMesh/LoS), and how this makes save/load fall out for free. |
| `references/testing-and-determinism.md` | The owned seeded PRNG stored in state, how much determinism to build (reproducible-within-a-build, not lockstep), Edit Mode/NUnit tests and golden tests against the core, and the cloneable-state property the enemy AI's simulation depends on. |

## Things to avoid

These are the concrete anti-patterns the source tutorials fall into. Each one violates the spine.

- **Applying damage from inside an animation.** An animation event that "deals the hit" couples outcomes to playback speed and makes the result untestable. Resolve damage synchronously; let an impact frame merely *show* a pre-resolved number.
- **Advancing turn state on animation completion.** Gating the next action on an `isMoving` / `notAnimated` flag set by a movement coroutine, or polling it in `LateUpdate`. Advance on a logical "action resolved" signal; let presentation drain a queue the rules layer never blocks on.
- **Reading state back from the Animator.** Bools/triggers are a one-way seam (resolved outcome → presentation). State must never wait on `Has Exit Time` or read clip progress.
- **Polling UI every frame.** Refresh health bars / status panels from `ActionResult` or change events, not from `Update`.
- **Porting tile logic literally.** `Node[,]`, BFS over cells, integer coordinates, per-cell occupancy — all of it has a continuous-space replacement. Copying it in is the core mistake.
- **Mutable global ScriptableObjects as live combat state.** Fine as authored data or a scene-decoupling channel, but snapshot into immutable combat state at encounter start; a live mutable SO read mid-resolution breaks determinism and replay.

## Changelog

- **2026-06-15** — Initial skill. Authored from a distillation of ~50 Unity/Godot tactics, combat, inventory, and environment tutorials (see `references/SOURCES.md`). Established the resolution-vs-presentation spine, the grid→no-grid translation model, and the four reference files. Anime 5E initiative/action-economy specifics flagged as unverified assumptions.
- **2026-06-15** — Added the engine-independent core layer: new `references/engine-independent-core.md` (rules in a `UnityEngine`-free `.asmdef`, plain-data `CombatState`, ports for engine services) and `references/testing-and-determinism.md` (seeded in-state PRNG, reproducible-within-a-build determinism without over-engineering to lockstep, Edit Mode/golden tests, AI-sim-by-clone). Folded a structural note into the resolution principle and extended the `description` to trigger on combat architecture, determinism, testing, and saves. Sources: see the "Engine-independent core" section of `SOURCES.md` (the 9 reference web pages were unreachable from the build environment and distilled from canonical knowledge; the git-amend / Code Monkey TBS videos were not yet ingested as captions).
