# Enemy AI

How the enemy force takes its turn. The whole approach rests on one property from `turn-and-resolution.md`: **resolution is a pure function over a cloneable state.** Because of that, the AI can ask "what would happen if I did this?" by resolving a candidate action against a *copy* of the combat state and reading the resulting `ActionResult` — no side effects, no animation, no committing.

## The seam

The turn loop routes player units to interactive input and enemy units to the AI, but both produce the same thing: a validated `GameAction` handed to the same resolver. The AI is just an alternate **action source**. Keep it pure and synchronous — the AI chooses an action and returns it; it must not embed coroutine waits or drive animation. Between successive enemy units, the turn loop awaits the resolved result (and lets presentation play out) rather than the AI blocking on a clip.

## Plan → simulate → score → pick

Utility AI is the natural fit and the model the source material gestures at (a per-unit AI that selects an action). The loop:

1. **Enumerate candidate actions.** For the unit, generate plausible actions: reachable move destinations + each ability against each legal target. In no-grid space, candidates come from the same queries the player UI uses:
   - reachable positions: sample a disc of points around the unit, keep those passing the NavMesh budget check (`movement-and-targeting.md`);
   - targets: overlap/registry query filtered by range, faction, and **line-of-sight**.
   Sample, don't enumerate cells — a handful of well-chosen candidate positions (toward cover, toward/away from enemies, into ability range) beats a dense sweep.

2. **Simulate each candidate** by resolving it against a clone of the state:

   ```csharp
   float Best(CombatState state, IEnumerable<GameAction> candidates, out GameAction pick)
   {
       float best = float.NegativeInfinity; pick = null;
       foreach (var a in candidates)
       {
           var sim = state.Clone();          // cheap if state is immutable / structurally shared
           var result = Resolve(sim, a);     // the SAME pure resolver the live game uses
           if (!result.Legal) continue;
           float s = Score(sim, result);
           if (s > best) { best = s; pick = a; }
       }
       return best;
   }
   ```

3. **Score** the resulting state + result with a weighted utility function: damage dealt and kills (read from `result.Hits`), threat reduction, finishing low-HP targets, reaching cover or high ground, staying out of enemy range, objective progress. Tune the weights per archetype (a brute rushes; an archer kites; a healer weights ally HP).

4. **Pick** the highest-scoring action, return it to the turn loop, which resolves it for real.

Multi-step look-ahead is the same idea recursed (simulate my action, then the opponent's best reply), but one ply is usually enough for tactics AI and far cheaper. Cap the candidate count and ply depth for performance.

## Why this needs the pure core

If resolution were entangled with animation/coroutines (the tutorials' model), step 2 would be impossible — you can't "play the attack animation on a hypothetical copy" to find out the damage. The cloneable, synchronous resolver is precisely what makes simulation-based AI tractable. This dependency is why `testing-and-determinism.md` (once added) and this file are linked: the property that makes the rules unit-testable is the same one that makes the AI able to plan. Keep the AI's scoring deterministic given a seed, too, so enemy behavior is reproducible in tests and replays.

## Difficulty knobs

Tune difficulty without changing the rules:
- **Candidate breadth / look-ahead depth** — fewer candidates or shallower search plays weaker.
- **Score noise / ε-greedy** — occasionally pick a non-optimal action so the AI feels human and isn't exploitable.
- **Information limits** — restrict candidate targets to those the unit can actually see (LoS), so the AI doesn't act on hidden players.
- **Archetype weights** — the cleanest lever; reshape the `Score` weights rather than special-casing behavior.

All of these are inputs to the same plan→simulate→score→pick loop; none require touching `Resolve`.
