# Testing and Determinism

The payoff of the engine-independent core (`engine-independent-core.md`): because the rules are pure C# over a plain-data state, they can be tested in milliseconds, replayed exactly, and simulated by the AI. This reference covers the randomness model that makes that reproducible, how far to take determinism (and where to stop), the Edit-Mode testing loop, and the AI-simulation property.

## Contents

- [The seeded RNG lives in the state](#the-seeded-rng-lives-in-the-state)
- [How much determinism — and where to stop](#how-much-determinism--and-where-to-stop)
- [Edit Mode tests against the core](#edit-mode-tests-against-the-core)
- [AI simulation rests on the same property](#ai-simulation-rests-on-the-same-property)

## The seeded RNG lives in the state

All combat randomness flows through **one seeded pseudo-random generator whose state is stored inside `CombatState`** — not a static, not the engine's RNG. Use a small, fully-owned generator (xorshift or PCG are a dozen lines and have no hidden global state); advance it explicitly as the resolver consumes rolls.

Do **not** use:
- **`UnityEngine.Random`** — it's a global, lives in the engine assembly (so the pure core can't call it anyway), and isn't snapshot/restored with your state.
- **`System.Random`** — also global if shared, its algorithm isn't guaranteed stable across .NET/runtime versions, and its internal state isn't cleanly serializable.

An owned generator means the RNG's position is part of the save (`encounter-and-data.md`), so a loaded battle continues the exact roll sequence, and a battle replays identically from `(initial state + seed + action list)`. Seed it deterministically per encounter (e.g. from a world seed + encounter id) so the same situation is reproducible.

```csharp
// In Core. State carries the RNG; rolls mutate it deterministically.
public struct Pcg32 { ulong state, inc; public uint Next() { /* ...standard PCG... */ } }
// CombatState holds a Pcg32; Resolve advances it for each hit/crit roll, in a fixed order.
```

## How much determinism — and where to stop

There are two levels, and **you only need the first.**

1. **Reproducible within a build (the target).** A seeded PRNG plus **ordered evaluation** (resolve effects/targets in a stable, defined order — e.g. by unit id, not by hash-set iteration or scene order) gives identical results every run of the same build. This is everything a single-player CRPG needs for save/resume, replay, debugging, and tests.

2. **Cross-platform lockstep (do NOT build this now).** Bit-identical results across CPUs/platforms additionally requires **fixed-point math** (or extreme care with float order) and a lockstep model. This is only worth it for **deterministic multiplayer**. 

⚠️ Unless and until the project adds deterministic multiplayer, **do not introduce fixed-point arithmetic or lockstep.** Floats are fine; ordered evaluation + a seeded PRNG are enough. Adding fixed-point preemptively is over-engineering that complicates every formula for a guarantee nothing currently needs. State this assumption explicitly if someone reaches for it.

## Edit Mode tests against the core

Because the core never touches Unity, test it with **Edit Mode** tests (NUnit, the Unity Test Framework) — no Play mode, no scene, no frame loop. They run in milliseconds, so the whole rules suite executes on every change.

- Put tests in a `Game.Combat.Tests.asmdef` that references **only the core** (and NUnit). No `UnityEngine`.
- Build a small `CombatState`, call `Resolve`, assert on the returned `ActionResult` and the new state. Inject deterministic fakes for the path/LoS ports (`engine-independent-core.md`) so spatial behavior is fixed.
- **Golden tests keyed on a seed:** fix the seed, run a scripted sequence of actions, and assert the resulting state/`ActionResult` stream matches a recorded baseline. Any unintended rules change shows up as a golden diff. (This is the same `initial state + seed + actions → outcome` property as replay.)
- **Test-first loop:** write the failing rules test, implement until green. Since the suite is fast and engine-free, this is genuinely tight — the reason to pay for the asmdef boundary is that it makes this loop possible at all.

Keep Play Mode tests for the Unity layer (does the view play the `ActionResult`? does input produce the right action?) — but the *rules* are covered far more cheaply in Edit Mode.

## AI simulation rests on the same property

The utility AI in `enemy-ai.md` scores a candidate action by **cloning `CombatState`, resolving the action against the clone, and reading the resulting `ActionResult`** — then throwing the clone away. This is only possible because resolution is pure and the state is plain data:

- If `CombatState` is **mutable**, `Clone()` must deep-copy it before each simulation.
- If it's **immutable with structural sharing**, "cloning" is free — `Resolve` returns a new state and the original is untouched, so the AI can fan out over many candidates cheaply. For an AI that evaluates many actions (or looks ahead a ply), immutable-with-sharing is the better model.

Either way, the AI uses the **same `Resolve`** the live game and the tests use — never a parallel "predict damage" function that could drift from the real rules. Determinism makes the AI's choices reproducible too, so its behavior can itself be golden-tested. The single architectural choice — pure rules over cloneable, seeded, plain-data state — is what makes testing, replay, save/load, and look-ahead AI all fall out together.
