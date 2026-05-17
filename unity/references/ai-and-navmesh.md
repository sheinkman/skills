# AI and NavMesh

Load this reference when implementing enemy behavior, pathfinding, or any "thing decides where to move" logic. Unity's AI Navigation package + a small state machine covers the AI for most action-RPG-style games; the patterns here scale from a single skeleton to hundreds of enemies on screen.

## The AI Navigation package

In modern Unity (2022+ and all of Unity 6), NavMesh ships as a package: **`com.unity.ai.navigation`**. Install via Package Manager → Unity Registry → "AI Navigation". The package replaces the old "Static" checkbox + Window → Navigation workflow.

The four components:

- **`NavMeshSurface`** — added to a parent of the geometry you want walkable. Bakes the navmesh at edit time or runtime.
- **`NavMeshAgent`** — added to a moving character. Handles pathfinding, steering, avoidance.
- **`NavMeshLink`** — connects two points on the navmesh that aren't directly connected (jumping a gap, climbing a ladder). Replaces the older `OffMeshLink`; more flexible, less overhead.
- **`NavMeshModifier`** / **`NavMeshModifierVolume`** — per-object or per-volume overrides (exclude this from the bake, mark this as the "Lava" area, etc.).

## Baking a navmesh

For a static level:

1. Add a `NavMeshSurface` component to the level root (or a dedicated empty GameObject).
2. Set the **Agent Type** — defines radius, height, max slope, step height that the bake is sized for. For multiple agent sizes (small rats, big golems), bake multiple surfaces, one per agent type.
3. Set **Include Layers** to limit which colliders contribute (typically just the "Environment" layer).
4. Click **Bake**.

The bake produces a `.asset` next to your scene. Commit it. The `NavMeshSurface` references this asset; without it, agents have nothing to walk on at runtime.

For procedurally generated levels (roguelikes, hub levels), bake at runtime:

```csharp
public class RuntimeNavmesh : MonoBehaviour
{
    [SerializeField] NavMeshSurface _surface;

    public void RebuildAfterGeneration()
    {
        _surface.BuildNavMesh();  // synchronous
        // or surface.UpdateNavMesh(surface.navMeshData) for incremental updates
    }
}
```

`BuildNavMesh` is synchronous and can hitch on large levels — call it during a loading screen, not in `Update`. For continuous updates while the world changes (destructible terrain, opening doors that should change pathing), use `UpdateNavMesh(navMeshData)` with a smaller modified region.

## Agents — the actual movement

A `NavMeshAgent` handles pathfinding, steering, and obstacle avoidance for one character:

```csharp
[RequireComponent(typeof(NavMeshAgent))]
public class EnemyMover : MonoBehaviour
{
    NavMeshAgent _agent;

    void Awake()
    {
        _agent = GetComponent<NavMeshAgent>();
        _agent.speed = 3.5f;
        _agent.angularSpeed = 360f;
        _agent.acceleration = 12f;
        _agent.stoppingDistance = 1.5f;
    }

    public void MoveTo(Vector3 worldPoint)
    {
        if (NavMesh.SamplePosition(worldPoint, out var hit, 2f, NavMesh.AllAreas))
            _agent.SetDestination(hit.position);
    }
}
```

`NavMesh.SamplePosition` snaps a world point to the nearest valid point on the navmesh within a radius — necessary because a click on a wall or off-mesh position would otherwise fail silently. Always sample before `SetDestination` if the target comes from input or the player position.

### Reaching the destination

`_agent.remainingDistance` is unreliable until `_agent.pathPending` is false. The robust check:

```csharp
bool HasArrived() =>
    !_agent.pathPending
    && _agent.remainingDistance <= _agent.stoppingDistance
    && (!_agent.hasPath || _agent.velocity.sqrMagnitude < 0.01f);
```

The combination handles "we're close enough" and "we're stuck against an obstacle and the path doesn't go further".

### Common agent settings to tune

- **Stopping Distance** — radius at which the agent considers itself "there". Set this to roughly your attack range for enemies.
- **Auto Braking** — slows on approach. Off for enemies that should slam into the target (chargers); on for everyone else.
- **Obstacle Avoidance Type** — None / Low Quality / Medium / High / Good. Higher quality costs CPU and helps avoid agent congestion. For many agents (50+), drop to Low and accept some clipping.
- **Priority** — 0-99, lower = higher priority. When two agents collide in avoidance, the lower-priority one yields. Useful for "boss never yields to minions".

## NavMeshLinks — gaps, ladders, jumps

A `NavMeshLink` connects two points. Agents will path through it as if it were a direct connection:

```csharp
// Set up in inspector typically. Two endpoints, a width, a direction.
// At runtime, you can check if an agent is currently traversing a link:
if (_agent.isOnOffMeshLink)
{
    var data = _agent.currentOffMeshLinkData;
    // Animate the jump from data.startPos to data.endPos manually.
}
```

For an isometric game with platforms or pits, NavMeshLinks let you wire up traversal without baking ramps into the geometry. The Auto Generate option finds plausible jumps from edges; review what it produces, it errs toward generous.

## NavMesh Modifiers

- **`NavMeshModifier`** on a GameObject: marks that object's contribution as a specific area type (e.g., "Slow Mud"), or excludes it from the bake entirely.
- **`NavMeshModifierVolume`**: same idea but applied within a box volume, regardless of what geometry is inside.

Area types have **costs** in the Navigation window. Setting "Mud" to cost 5x makes agents prefer Walkable (cost 1) routes around mud unless the mud route is much shorter. Useful for AI "preferring roads" or "avoiding traps."

## Enemy AI architecture

For an action RPG / roguelike, most enemies follow this rhythm: **idle → notice player → chase → attack → return**. The cleanest implementation for a small team is a per-enemy state machine on top of the NavMeshAgent.

Use the class-based state pattern from `references/gameplay-patterns.md`:

```csharp
public abstract class EnemyState
{
    protected readonly EnemyBrain Brain;
    protected EnemyState(EnemyBrain b) => Brain = b;
    public virtual void OnEnter() {}
    public virtual void OnExit()  {}
    public virtual void Tick(float dt) {}
}

public class EnemyBrain : MonoBehaviour
{
    public NavMeshAgent Agent;
    public Transform Target;
    public float SightRange = 8f, AttackRange = 1.8f, LoseRange = 12f;

    EnemyState _state;
    public IdleState Idle;
    public ChaseState Chase;
    public AttackState Attack;

    void Awake()
    {
        Agent  = GetComponent<NavMeshAgent>();
        Idle   = new IdleState(this);
        Chase  = new ChaseState(this);
        Attack = new AttackState(this);
        Transition(Idle);
    }

    public void Transition(EnemyState next)
    {
        _state?.OnExit();
        _state = next;
        _state.OnEnter();
    }

    void Update() => _state.Tick(Time.deltaTime);

    public bool CanSeeTarget()
    {
        if (Target == null) return false;
        var dir = Target.position - transform.position;
        if (dir.sqrMagnitude > SightRange * SightRange) return false;
        // Optional: line-of-sight raycast against walls.
        return !Physics.Raycast(transform.position + Vector3.up,
                                dir.normalized, dir.magnitude,
                                LayerMask.GetMask("Wall"));
    }
}

public class IdleState : EnemyState
{
    public IdleState(EnemyBrain b) : base(b) {}
    public override void Tick(float dt)
    {
        if (Brain.CanSeeTarget()) Brain.Transition(Brain.Chase);
    }
}

public class ChaseState : EnemyState
{
    public ChaseState(EnemyBrain b) : base(b) {}
    public override void OnEnter() => Brain.Agent.isStopped = false;
    public override void Tick(float dt)
    {
        Brain.Agent.SetDestination(Brain.Target.position);
        float d = Vector3.Distance(Brain.transform.position, Brain.Target.position);
        if (d <= Brain.AttackRange) Brain.Transition(Brain.Attack);
        else if (d >= Brain.LoseRange) Brain.Transition(Brain.Idle);
    }
}
```

This scales: 30 enemies × a 4-state machine = ~120 trivial updates per frame, well under the budget. For 200+ enemies, you'd start centralizing into a manager pattern (one `Update` ticks all enemies), but you almost never need to until you measure.

### Behavior trees and utility AI

For richer enemies (decision-tree boss fights, complex schedules), **behavior trees** scale better than state machines past 8-ish states. Unity doesn't ship a built-in BT framework, but several free packages exist (NodeCanvas, Behavior Designer, AI Tree). Don't reach for a BT framework before you need it — most enemies don't.

**Utility AI** (each behavior scored, highest wins) is a third option, popular for sims (The Sims, Dwarf Fortress style). Implement as a list of `Considerations` per action, each returning 0-1, multiply for a final score. Useful for autonomous NPCs; overkill for "monster chases player".

## Aggro / target selection

For "many enemies, one player", just reference the player directly. For "many enemies, many possible targets" (party-based combat, swarms with different factions):

```csharp
public class TargetPicker : MonoBehaviour
{
    [SerializeField] LayerMask _targetMask;
    [SerializeField] float _scanRadius = 10f;
    static readonly Collider[] s_Buffer = new Collider[32];

    public Transform FindBestTarget(Vector3 from)
    {
        int n = Physics.OverlapSphereNonAlloc(from, _scanRadius, s_Buffer, _targetMask);
        Transform best = null;
        float bestScore = float.NegativeInfinity;
        for (int i = 0; i < n; i++)
        {
            float d = Vector3.Distance(from, s_Buffer[i].transform.position);
            float score = -d;  // closer is better; extend with threat, type, etc.
            if (score > bestScore) { bestScore = score; best = s_Buffer[i].transform; }
        }
        return best;
    }
}
```

A static buffer (`s_Buffer`) and `OverlapSphereNonAlloc` avoid GC. Re-scan once per second or on a relevant event, not every frame.

## Senses — sight, sound, sharing

For "did the enemy notice me":

```csharp
public bool CanSee(Transform target)
{
    var origin = transform.position + Vector3.up * 1.6f;       // eye height
    var toTarget = target.position - origin;
    if (toTarget.sqrMagnitude > _sightRange * _sightRange) return false;
    if (Vector3.Angle(transform.forward, toTarget) > _fovHalfAngle) return false;
    return !Physics.Linecast(origin, target.position + Vector3.up, _wallMask);
}
```

Three checks: distance, cone, line-of-sight. Tune the cone (typically 60-90° half-angle) per enemy archetype.

For **hearing**, give the player or noise sources a `MakeNoise(position, loudness)` method that broadcasts; enemies in range register the noise and may pivot to investigate. Don't use Unity colliders for hearing — it's noisier (no pun intended) and harder to tune than a manual broadcast.

For **squad sharing** (one enemy sees you, all nearby enemies aggro), use the ScriptableObject event channel pattern from `references/scripting-patterns.md`: an enemy emits `OnPlayerSpotted(position)` on a channel, every enemy listens.

## Pure 2D pathfinding

The Unity AI Navigation package is fundamentally 3D. For a **pure 2D** game (using `Collider2D`/`Rigidbody2D`):

- **NavMeshPlus** (community package, free, MIT) — adapts the NavMesh system to 2D. Recommended starting point.
- **A* Pathfinding Project** (Aron Granberg) — free version works well for 2D; pro version has more features.
- Roll your own grid A* if your map is tile-based. Surprisingly small (~150 lines for a clean A* implementation) and gives you total control.

If your isometric game is **3D with an iso camera** (covered in `references/two-d-and-isometric.md`), use Unity AI Navigation directly — agents path through the 3D world even though the camera makes it look 2D. This is the easier and more flexible path for most isometric projects.

## Common pitfalls

- **Agent walks off the edge of the navmesh.** Either the navmesh wasn't baked there, or `Agent Type → Max Slope` is too steep. Visualize the navmesh in Scene view to see what's actually walkable.
- **Agents bunching up and shoving each other.** Set different `priority` values, or use `agent.radius` tuned so they have personal space.
- **`SetDestination(player.position)` every frame.** Unnecessary recompute. Set when the target moves significantly or on a timer.
- **`remainingDistance == 0` to detect arrival.** Unreliable while `pathPending`. Use the combined check shown above.
- **Path failing silently when target is off-mesh.** Always `NavMesh.SamplePosition` first if the target can be arbitrary.
- **One huge `NavMeshSurface` covering a 1km world.** Splits poorly across cores during bake; runtime memory bloats. Tile the world and bake per-tile.
- **Building runtime navmesh every frame for "dynamic" obstacles.** Use `NavMeshObstacle` components instead (they carve the navmesh in real time, much cheaper). Reserve `BuildNavMesh()` for structural changes.
- **Reaching for behavior trees before you need them.** A state machine + good architecture is enough for almost every indie game. BT frameworks add complexity; only pay for it when state count actually demands it.
