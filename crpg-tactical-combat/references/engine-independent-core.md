# The Engine-Independent Core

The architecture beneath the combat design. The resolution-vs-presentation rule (SKILL.md, `turn-and-resolution.md`) says rules are pure and synchronous; this reference makes that structural and **compiler-enforced**: the combat rules live in their own assembly that cannot reference `UnityEngine` at all. If a rule tries to call a Unity API, it won't compile. That is the strongest form of the spine — not a discipline you have to remember, but a boundary the build enforces.

## Contents

- [The asmdef boundary](#the-asmdef-boundary)
- [What lives where](#what-lives-where)
- [CombatState as a plain-data graph](#combatstate-as-a-plain-data-graph)
- [Crossing the boundary: ports for engine services](#crossing-the-boundary-ports-for-engine-services)
- [Serialization and world state](#serialization-and-world-state)

## The asmdef boundary

Put the rules in a dedicated assembly definition — e.g. `Game.Combat.Core.asmdef` — with **no reference to any Unity assembly** (no `UnityEngine`, no `UnityEngine.AI`, nothing). It's a plain C# library that happens to live in the project. The Unity-facing code (MonoBehaviours, presentation, input, NavMesh access) lives in a separate assembly — `Game.Combat.Unity.asmdef` — that *does* reference both Unity and the core.

```
Game.Combat.Core.asmdef     // pure C#: state, resolution, RNG, rules. NO UnityEngine.
Game.Combat.Unity.asmdef    // references Core + UnityEngine: MonoBehaviours, views, NavMesh, input
Game.Combat.Tests.asmdef    // references Core only: Edit Mode tests (see testing-and-determinism.md)
```

The dependency arrows point **one way**: Unity → Core, Tests → Core. The core never depends on the engine. The moment someone writes `using UnityEngine;` in the core, the project stops compiling — which is exactly the feedback you want. This is the asmdef pattern applied to enforce the rules/engine split, not just to speed up compiles.

## What lives where

| In the **Core** assembly (pure C#) | In the **Unity** assembly |
|---|---|
| `CombatState` and all runtime instances (units, slots, statuses) | `MonoBehaviour` controllers and lifecycle |
| `Resolve(state, action) → ActionResult` and all rules | Animation, VFX, camera, audio, UI |
| The damage roll, status ticks, victory check | Input gathering (raycasts, the pointer source-of-truth) |
| The seeded RNG (see `testing-and-determinism.md`) | NavMesh queries, `Physics.Linecast` LoS |
| Initiative, action economy, the action/effect model | ScriptableObject assets and the scene graph |
| Plain-data DTOs for save/load | The save *file* I/O (`persistentDataPath`) |

Note that **NavMesh pathing and raycast line-of-sight are engine services** — they can't live in the pure core. They are consulted through interfaces (next section), so the rules stay testable while still using Unity's spatial systems at runtime.

## CombatState as a plain-data graph

`CombatState` is an ordinary C# object graph: lists of unit instances, their HP/AP/position/cooldowns/status lists, the initiative order, the round number, and the RNG state. It uses the **core's own math types**, not Unity's — a small `Vec3` struct or `System.Numerics.Vector3`, never `UnityEngine.Vector3` (which would drag in the engine). The Unity layer converts between the two at the boundary (`new UnityEngine.Vector3(v.X, v.Y, v.Z)` and back).

> The `Vector3` shown in the `ActionResult` example in `turn-and-resolution.md` is this core `Vec3`, not the Unity type — the conversion happens in the presentation layer that reads the result.

The flow is the same one-liner the whole skill is built on, now with a hard assembly boundary around the left side:

```
chosen action ──▶ [Core] Resolve(state, action) ──▶ (new state, ActionResult) ──▶ [Unity] play it back
```

State only ever changes inside `Resolve`. Presentation receives the `ActionResult` and animates; input produces the next action. The core has no idea Unity exists.

## Crossing the boundary: ports for engine services

When a rule genuinely needs an engine service (path length for a move budget, LoS for a hit check), define the dependency as an **interface in the core** and implement it in the Unity assembly (a "port and adapter"):

```csharp
// In Core — no UnityEngine.
public interface IPathOracle  { bool TryPathCost(Vec3 from, Vec3 to, float budget, out float cost); }
public interface ILineOfSight { bool Clear(Vec3 eye, Vec3 target); }
```

`Resolve` (or the candidate-generation it calls) takes these interfaces as inputs. At runtime the Unity layer injects NavMesh- and `Physics`-backed implementations; in tests you inject deterministic fakes (a flat-ground path oracle, an always-clear LoS) so rules tests never need the engine. This keeps the asmdef boundary intact *and* lets the rules use real spatial queries in the live game.

## Serialization and world state

Because `CombatState` is already plain data with no engine references, **saving combat is just serializing that graph** (see `encounter-and-data.md` for the JSON + stable-ID mechanics). There's no untangling MonoBehaviours from data at save time — the data was never entangled.

This is what lets combat state slot into the project's larger **LLM-generated, permadeath world state**: an encounter is a serializable value that the world layer can store, hand back to resume, or discard on death. The same plain-data property underpins three capabilities at once — **save/load**, **AI simulation** (clone the state and resolve hypotheticals, `enemy-ai.md`), and **deterministic replay** (`testing-and-determinism.md`). They are not three features to build; they are three uses of one architectural choice.
