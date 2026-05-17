# Physics

Load this reference when working on physics-driven gameplay — movement, collisions, raycasts, triggers, ragdolls, or any "why is my object behaving weirdly" debugging. Unity physics is a thin C# wrapper over PhysX (3D) and Box2D (2D); understanding what's actually happening underneath fixes most issues.

## The update loop and timing

Three update callbacks, used differently:

- **`Update`** — variable delta time, runs once per render frame. Reading input, animation polling, non-physics gameplay logic.
- **`FixedUpdate`** — fixed delta time (`Time.fixedDeltaTime`, default 0.02s = 50 Hz), runs in physics steps. **All Rigidbody writes go here.** Multiple `FixedUpdate`s can run per render frame; zero can run if the frame is short.
- **`LateUpdate`** — after all `Update`s, before rendering. Camera follow, IK touch-ups.

Common mistake: writing to a Rigidbody in `Update`. The physics step then runs and immediately overwrites your change. Always `FixedUpdate` for physics writes.

Read inputs in `Update`, buffer them, apply in `FixedUpdate`:

```csharp
bool _wantsJump;
void Update()      => _wantsJump |= Input.GetButtonDown("Jump");
void FixedUpdate() { if (_wantsJump) { Jump(); _wantsJump = false; } }
```

If your physics looks jittery, check Project Settings → Time. The default fixed timestep (0.02) is fine; raising the physics rate costs CPU and rarely fixes the underlying issue.

## Rigidbody types

Set via Rigidbody inspector (3D) or per script.

- **Dynamic** (`isKinematic = false`) — full physics simulation. Forces apply, gravity acts, collisions resolve. The default.
- **Kinematic** (`isKinematic = true`) — moved only by script via `MovePosition` / `MoveRotation`. Doesn't respond to forces or gravity. Still detects collisions; doesn't bounce off them. Use for moving platforms, enemy bodies in hit-flash, anything you script directly.
- **Static** — no Rigidbody at all, just a Collider. Cheapest. Anything that never moves (walls, terrain).

**Don't mutate `transform.position` on a dynamic Rigidbody.** That bypasses the solver, causes interpenetration, and breaks contact callbacks. Use `Rigidbody.MovePosition` (which sweeps and respects collision) or apply forces and let physics do its job.

### `velocity` → `linearVelocity` (Unity 6)

`Rigidbody.velocity` is obsolete. Use `linearVelocity`. Same for `Rigidbody.angularVelocity` (no rename needed there, but Unity 6 cleaned up the linear name for consistency with 2D and to avoid the ambiguity with rotational velocity).

```csharp
// Unity 6.x
_rb.linearVelocity = new Vector3(x, _rb.linearVelocity.y, z);
```

### Mass, drag, gravity

- **Mass** affects acceleration under force (`a = F/m`) and momentum exchange in collisions. Keep masses within a reasonable range (rule of thumb: keep the ratio between any two masses under ~10:1). Crazy mass ratios cause solver instability.
- **Linear/Angular Drag** are damping. Drag = 0 means no air friction; high drag makes things stop quickly without explicit force. Use sparingly; it's not a substitute for friction.
- **Gravity** is global (Project Settings → Physics) but can be disabled per-Rigidbody via `useGravity`.

### Continuous Collision Detection

For fast-moving objects (bullets, projectiles), the default Discrete collision detection can let them tunnel through thin walls between physics steps. Switch the Rigidbody's Collision Detection to:
- **Continuous** — sweeps the collider's path each step. Costs more, prevents tunneling for dynamic-vs-static.
- **Continuous Dynamic** — also handles dynamic-vs-dynamic. Most expensive; use when needed.
- **Continuous Speculative** — newer option (Unity 6 default for "Continuous"). Predictive, good general balance.

Or skip a real collider and use a raycast-driven projectile (most bullets in games are raycasts, not physics objects).

## Colliders

Cheapest to most expensive (for the solver):

1. **Sphere** — fastest. Use whenever a sphere approximates the shape.
2. **Box / Capsule** — fast. Capsule is the standard for humanoid characters.
3. **Mesh Collider with Convex** — moderate. The mesh is reduced to a convex hull (max ~255 verts).
4. **Mesh Collider without Convex** — only valid on static (no Rigidbody) objects. Expensive, exact-mesh.
5. **Compound** — multiple primitives parented under one Rigidbody. Behaves as one body; cheaper than a mesh.

**Compound colliders are the right answer most of the time** for complex shapes. A handful of boxes/spheres parented under the Rigidbody gives near-mesh fidelity at primitive cost.

## Triggers vs collisions (the callback matrix)

A collider can be a normal collider or a **trigger** (`isTrigger = true`). The callbacks differ:

- Both non-trigger → `OnCollisionEnter/Stay/Exit(Collision other)`. Physics resolves (objects stop, bounce).
- Either is a trigger → `OnTriggerEnter/Stay/Exit(Collider other)`. No physics resolution; just a notification.

For *any* of these callbacks to fire, **at least one of the two participants must have a Rigidbody** (or a `Rigidbody2D` in 2D). This catches everyone at least once.

Kinematic Rigidbodies do receive trigger callbacks. They do *not* receive collision callbacks against other kinematic or static colliders by default — flip "Use Full Kinematic Contacts" in Project Settings → Physics if you need them.

## Layers and the collision matrix

Project Settings → Tags and Layers → Layers (32 slots, 8 reserved). Then Project Settings → Physics → Layer Collision Matrix — a grid that controls which layers collide with which. Disabling unnecessary pairs is a major performance win in scenes with many bodies.

Typical layout for a small game:

| Layer       | Used for                            |
|-------------|-------------------------------------|
| Default     | Static world geometry               |
| Player      | The player's body                   |
| Enemy       | Enemy bodies                        |
| EnemyHitbox | Damage receivers (capsule trigger)  |
| Projectile  | Bullets, arrows                     |
| Pickup      | Triggers for "you walked over this" |
| Ignore Raycast | Visual-only objects              |

In matrix: Projectile collides with Default + Enemy + EnemyHitbox + Player (depending on team), but not with itself or with Pickup. Pickup collides with nothing — it's pure trigger overlap.

LayerMasks in script:

```csharp
[SerializeField] LayerMask _hitMask;     // Set in inspector.
Physics.Raycast(origin, dir, out var hit, range, _hitMask);

// Building a mask programmatically:
int mask = LayerMask.GetMask("Enemy", "Default");
```

## Raycasts and queries

3D queries on `UnityEngine.Physics`:

```csharp
Physics.Raycast(origin, dir, out hit, maxDist, mask);
Physics.SphereCast(origin, radius, dir, out hit, maxDist, mask);
Physics.CapsuleCast(p1, p2, radius, dir, out hit, maxDist, mask);
Physics.BoxCast(center, halfExtents, dir, Quaternion.identity, out hit, maxDist, mask);

Physics.OverlapSphere(center, radius, mask);
Physics.OverlapBox(center, halfExtents, Quaternion.identity, mask);
Physics.OverlapCapsule(p1, p2, radius, mask);
```

Each has:
- A regular version that allocates an array (`Raycast`, `OverlapSphere`).
- A `*NonAlloc` / `*NonAlloc` version that writes into a buffer you pass in. **Use these in hot paths.**
- A version returning bool for "did anything hit at all".

Always pass a `LayerMask`. Always include `QueryTriggerInteraction.Ignore` (or `.Collide`) explicitly when triggers matter — the default is determined by Project Settings.

### Common raycast patterns

```csharp
// "Is something in front of me within 2m?"
bool blocked = Physics.Raycast(transform.position, transform.forward, 2f, _wallMask);

// "Find ground point below my feet."
if (Physics.Raycast(transform.position + Vector3.up * 0.1f, Vector3.down,
                    out var ground, 1f, _groundMask))
    _isGrounded = true;

// "All enemies in a 5m sphere."
int count = Physics.OverlapSphereNonAlloc(transform.position, 5f, _enemyBuffer, _enemyMask);
for (int i = 0; i < count; i++) { /* _enemyBuffer[i] */ }
```

## CharacterController vs Rigidbody (revisited)

Covered in `references/gameplay-patterns.md` from the gameplay angle; from the physics angle:

- **CharacterController** is a built-in component that performs its own capsule sweep test on `Move(...)`. It doesn't go through the physics solver at all — it can't receive forces, isn't pushed by Rigidbodies, doesn't appear in `OnCollisionEnter` callbacks (it fires `OnControllerColliderHit` instead). Predictable, deterministic-ish, great for arcade movement.
- **Rigidbody-driven player** participates fully in physics. Slower, harder to tune, but interacts naturally with the world.

There's no third "official" character controller in Unity — for fancy needs, projects often ship a custom kinematic-Rigidbody controller (e.g., Kinematic Character Controller asset, or rolling their own with `Rigidbody.MovePosition` + manual sweep tests).

## 2D physics

Unity 2D uses Box2D under the hood. The API is mirrored on `Physics2D`, `Rigidbody2D`, `Collider2D`, etc.

Key differences from 3D:
- `Rigidbody2D` has `bodyType`: Dynamic, Kinematic, Static. Same idea.
- `linearVelocity` is the property in 2D too (was `velocity` previously).
- Triggers and collisions use `OnCollision2D` / `OnTrigger2D` callback names.
- Effectors (`AreaEffector2D`, `PointEffector2D`, `PlatformEffector2D`) handle wind, gravity wells, one-way platforms without custom code.

### Box2D v3 (Unity 6.3+)

Unity 6.3 introduced a new low-level Box2D v3 API alongside the classic 2D physics. It's a parallel system, not a replacement yet — you can keep using `Rigidbody2D` / `Collider2D` exactly as before. The new API is opt-in and aimed at projects needing massive numbers of bodies with deterministic simulation. Most gameplay code won't touch it directly.

## Joints and articulations

Joints attach two Rigidbodies (or one to the world). The common 3D joints:

- **FixedJoint** — rigid link. Two bodies move as one.
- **HingeJoint** — rotation around one axis (doors, levers, wheels).
- **SpringJoint** — soft pull toward an anchor.
- **ConfigurableJoint** — does anything. Powerful, complex inspector.

For ragdolls and articulated characters, prefer the **Articulation system** (`ArticulationBody`) over `Rigidbody` + chained joints. Articulations are designed for kinematic chains, solve more stably, and avoid joint chatter. Standard for robotics/sim work in Unity; works for ragdolls too.

## Common pitfalls

- **Writing to `transform.position` on a dynamic Rigidbody.** Use `MovePosition`. Direct `transform` writes bypass the solver, cause interpenetration, and miss collision callbacks.
- **High-mass-ratio bodies in contact** (a 0.001-mass object pushing a 1000-mass object). Solver instability and jitter. Keep ratios reasonable.
- **Scaled colliders.** Non-uniform scale on a parent of a primitive collider (sphere/capsule) gives wrong behavior — the solver ignores non-uniform scale on those. Use mesh colliders for non-uniformly-scaled shapes, or restructure.
- **Forgetting Rigidbody for triggers.** "Why isn't my OnTriggerEnter firing?" — one of the participants needs a Rigidbody. The static collider + static collider case fires no callbacks.
- **Raycasts hitting the firing object's own collider.** Either start the ray slightly forward of the firing point, or use `Physics.queriesHitBackfaces = false` and tune mesh, or use `Physics.IgnoreCollision` between the projectile and shooter.
- **`Time.deltaTime` in `FixedUpdate`.** Use `Time.fixedDeltaTime`. They're equal in practice for default settings but conceptually different; mixing them up bites when the timestep changes.
- **Lots of trigger-only objects in a scene.** Each trigger pair still costs broadphase work. Consider `OverlapSphereNonAlloc` polling for pickups rather than dozens of trigger callbacks.
