# Movement and Targeting (no grid)

How units move and pick targets in continuous space. Everything here is the world-space replacement for tile logic. Code is illustrative scaffolding — minimal, shows the pattern, not drop-in.

## Contents

- [Movement as a NavMesh path-length budget](#movement-as-a-navmesh-path-length-budget)
- [Reachability and its visualization](#reachability-and-its-visualization)
- [Range and area targeting](#range-and-area-targeting)
- [Line-of-sight](#line-of-sight)
- [Cover](#cover)
- [Elevation and climb limits](#elevation-and-climb-limits)
- [Selection and pointer input](#selection-and-pointer-input)

## Movement as a NavMesh path-length budget

The grid tutorials compute movement range with BFS/Dijkstra over cells, accumulating per-cell move points (clear = 10, forest = 20). The continuous equivalent is **path length in meters against a move budget**, with the NavMesh doing the graph work the hand-rolled A* used to do.

A unit can reach a destination if a NavMesh path exists to it *and* the path's length is within budget:

```csharp
// Pure query — wraps NavMesh statics, no MonoBehaviour, no animation.
public static bool CanReach(Vector3 from, Vector3 dest, float budgetMeters, out float cost)
{
    cost = float.PositiveInfinity;
    var path = new NavMeshPath();
    if (!NavMesh.CalculatePath(from, dest, NavMesh.AllAreas, path)) return false;
    if (path.status != NavMeshPathStatus.PathComplete) return false; // partial = unreachable

    float len = 0f;
    for (int i = 1; i < path.corners.Length; i++)
        len += Vector3.Distance(path.corners[i - 1], path.corners[i]);
    cost = len;
    return len <= budgetMeters;
}
```

Notes:
- **Difficult terrain** (the tutorials' forest = 2× cost) maps to **NavMesh area costs** (`NavMesh.SetAreaCost` / per-area cost in the agent settings). The path length already reflects them, so the budget check stays the same.
- Keep this as a plain service, not a `MonoBehaviour`, so the pure rules layer can call it. (See `engine-independent-core.md` — pathing is one of the few places the "pure core" legitimately consults a Unity service; isolate it behind an injected interface.)
- "Snap a clicked point onto the walkable surface" is `NavMesh.SamplePosition(worldPoint, out hit, maxDist, areaMask)` — the replacement for "world hit → grid cell".

## Reachability and its visualization

The tutorials precompute the reachable set once when a unit is selected, then validate a click by **set membership** (cheap). Keep that two-phase shape, but the "set" is now a region, not a list of cells:

- **Decal / projector** (Unity 6 URP Decal Projector is the clean choice) for a reachable-area footprint, or a radius ring for the simple case.
- **Sampled NavMesh points** if you want discrete move candidates (e.g. for AI): sample a disc of points around the unit, keep those that pass `CanReach`.

Whatever the form, the reachable region is a **pure consumer of the budget query** — the rules own "is this destination legal", the view only renders it. Pool the visual instances rather than instantiate/destroy each turn (the tutorials pool highlight quads; pool decals/markers the same way). Recompute when the unit is selected and again after it moves.

⚠️ The grid tutorials draw highlights with a hacky URP depth-override pass so markers aren't occluded by terrain. On Unity 6, prefer **Decal Projectors**, which conform to the surface and avoid the depth hack entirely.

## Range and area targeting

Range is a world-space test, optionally constrained to a shape:

```csharp
bool InRange(Vector3 origin, Vector3 target, float range) =>
    Vector3.Distance(origin, target) <= range;

// Cone (e.g. a breath/cleave): within range AND within half-angle of facing.
bool InCone(Vector3 origin, Vector3 fwd, Vector3 target, float range, float halfAngleDeg) =>
    InRange(origin, target, range) &&
    Vector3.Angle(fwd, target - origin) <= halfAngleDeg;
```

To gather candidates, don't iterate cells — query the world or a unit registry:
- `Physics.OverlapSphere(center, radius, unitLayer)` for "everyone near the impact point" (area of effect).
- A maintained **unit registry** (list/dictionary of live combatants) filtered by distance is cheaper and rules-friendly when you already track all units.

Then filter candidates by the same predicates the tutorials use — **distance, team/faction, and (add this) line-of-sight** — collecting survivors into a reused list. Area of effect resolves by running the effect against every unit returned by the overlap query at the impact point.

## Line-of-sight

**The grid tutorials never implement true line-of-sight** — they rely on tile blocking. A no-grid CRPG must add it explicitly. It is a ray from shooter to target against an occluder layer:

```csharp
bool HasLineOfSight(Vector3 eye, Vector3 targetPoint, LayerMask occluders) =>
    !Physics.Linecast(eye, targetPoint, occluders);
```

Use eye/chest height, not foot position, so units aren't blocked by the ground or their own capsule. Cast to a few sample points on the target (center + shoulders) if you want graded visibility rather than binary. LoS is a **resolution input** (it gates legality and hit chance) — compute it in the rules layer, not in the animation.

## Cover

Cover generalizes line-of-sight from binary to graded. Cast from the shooter to the target's body points; if some are occluded by a cover collider but the target is still partially visible, that's **partial cover**; fully occluded is **full cover** (no shot). Feed the result into the hit roll as a modifier (the XCOM-style sources use half/full cover to lower hit chance) — see the damage roll in `turn-and-resolution.md`. Cover is therefore *derived from world geometry by raycast*, never from adjacency to a "cover tile".

## Elevation and climb limits

Two separate concerns:

1. **Sampling height.** To place a unit or read ground elevation at a world XZ, raycast straight down against the terrain layer and read `hit.point.y` (the tutorials' reusable trick), or use `NavMesh.SamplePosition`. Do this on demand; don't store a per-cell elevation table.

2. **Climbability.** The tutorials gate each step on `abs(elevationTo - elevationFrom) > characterClimb`, which has a known bug — a single tall step passes if its height fits. In continuous space, gate on **grade** along the path instead: `abs(ΔY) / horizontalDistance` per path segment, rejecting segments steeper than the unit's limit. Better still, bake climbability into the NavMesh itself via **max slope** and **step height**, and use **Off-Mesh Links** for ladders/jumps. Express the unit's climb stat as a max grade (degrees) or step height (meters).

## Selection and pointer input

- **Centralize pointer state.** One component raycasts the cursor into the world each frame and exposes the hit (`point`, hit collider, a valid/`active` flag when the ray misses the walkable surface). Every consumer reads that single source of truth — the tutorials' best input lesson. Don't scatter raycasts across systems.
- **Select by collider, not coordinate.** Raycast the unit's own collider and read its `Character`/combatant component. No quantization, no per-cell occupancy lookup.
- **Opt-in selectability.** A marker component on selectable units keeps the raycast from selecting scenery.
- **Change-detection.** Only recompute hover/selection when the hit object actually changes (compare collider identity), not every frame.

Keep all of this on the presentation/input side. It produces *intent* (which unit, which destination, which target); the rules layer turns intent into a validated action and resolves it.
