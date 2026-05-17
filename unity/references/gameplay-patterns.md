# Gameplay patterns

Load this reference when writing concrete gameplay systems — controllers, AI, combat, spawning, interaction. The patterns here recur across genres; pick the ones that fit and resist over-architecting before you know what the game actually needs.

## State machines

Most gameplay code is a state machine in disguise. Making it explicit pays off the moment the system grows past "press space to jump."

### Enum-based (small systems)

Fine for 3-5 states with simple transitions:

```csharp
public class Door : MonoBehaviour
{
    enum State { Closed, Opening, Open, Closing }
    State _state = State.Closed;

    [SerializeField] float _openDuration = 0.5f;
    float _t;

    public void Interact()
    {
        if (_state == State.Closed) _state = State.Opening;
        else if (_state == State.Open) _state = State.Closing;
    }

    void Update()
    {
        switch (_state)
        {
            case State.Opening:
                _t += Time.deltaTime / _openDuration;
                if (_t >= 1f) { _t = 1f; _state = State.Open; }
                ApplyOpenAmount(_t);
                break;
            case State.Closing:
                _t -= Time.deltaTime / _openDuration;
                if (_t <= 0f) { _t = 0f; _state = State.Closed; }
                ApplyOpenAmount(_t);
                break;
        }
    }
}
```

Limits: a single `switch` blows up past ~5 states or when states have rich behavior of their own.

### Class-based (medium-to-large systems)

One class per state, a context that holds the current one:

```csharp
public abstract class PlayerState
{
    protected readonly Player Player;
    protected PlayerState(Player p) => Player = p;

    public virtual void OnEnter() {}
    public virtual void OnExit()  {}
    public virtual void Tick(float dt) {}
    public virtual void FixedTick(float dt) {}
}

public class Player : MonoBehaviour
{
    PlayerState _state;
    public PlayerIdleState Idle    { get; private set; }
    public PlayerRunState  Running { get; private set; }
    public PlayerJumpState Jumping { get; private set; }

    void Awake()
    {
        Idle    = new PlayerIdleState(this);
        Running = new PlayerRunState(this);
        Jumping = new PlayerJumpState(this);
        TransitionTo(Idle);
    }

    public void TransitionTo(PlayerState next)
    {
        _state?.OnExit();
        _state = next;
        _state.OnEnter();
    }

    void Update()      => _state?.Tick(Time.deltaTime);
    void FixedUpdate() => _state?.FixedTick(Time.fixedDeltaTime);
}
```

Each state lives in its own file, holds its own data, and triggers transitions by calling `Player.TransitionTo(...)`. Easy to extend, easy to test, no hidden coupling.

### Animator as the state machine

For animation-driven gameplay (most action games), the Animator's state machine *is* the gameplay state machine. Drive transitions via Animator parameters, listen to state events (`StateMachineBehaviour.OnStateEnter/Exit`) to fire gameplay logic. Avoid a parallel C# state machine that mirrors the Animator — they will drift.

## Player controllers

### Rigidbody-based (3D, physics-correct)

Use when the player should interact with the physics world (push objects, get pushed, ride moving platforms via friction):

```csharp
[RequireComponent(typeof(Rigidbody))]
public class RigidbodyPlayer : MonoBehaviour
{
    [SerializeField] float _moveSpeed = 5f;
    [SerializeField] float _jumpImpulse = 6f;

    Rigidbody _rb;
    Vector2 _input;
    bool _wantsJump;
    bool _grounded;

    void Awake() => _rb = GetComponent<Rigidbody>();

    // Hook these to your Input System actions.
    public void SetMoveInput(Vector2 v) => _input = v;
    public void RequestJump() => _wantsJump = true;

    void FixedUpdate()
    {
        // Preserve vertical velocity, control horizontal directly.
        var v = _rb.linearVelocity;
        var target = new Vector3(_input.x, 0, _input.y) * _moveSpeed;
        _rb.linearVelocity = new Vector3(target.x, v.y, target.z);

        if (_wantsJump && _grounded)
            _rb.AddForce(Vector3.up * _jumpImpulse, ForceMode.Impulse);
        _wantsJump = false;
    }

    void OnCollisionStay(Collision c)
    {
        // Cheap grounded check; use spherecast for robustness.
        foreach (var contact in c.contacts)
            if (Vector3.Dot(contact.normal, Vector3.up) > 0.7f)
            { _grounded = true; return; }
        _grounded = false;
    }
}
```

Note: in Unity 6, `Rigidbody.velocity` was renamed to `Rigidbody.linearVelocity` and the old name is obsolete. Use `linearVelocity`.

### CharacterController-based (3D, predictable)

Use when you want crisp, non-physics-y movement (most platformers, first-person shooters with arcade feel):

```csharp
[RequireComponent(typeof(CharacterController))]
public class CCPlayer : MonoBehaviour
{
    [SerializeField] float _moveSpeed = 5f;
    [SerializeField] float _gravity = -20f;
    [SerializeField] float _jumpSpeed = 7f;

    CharacterController _cc;
    Vector3 _velocity;
    Vector2 _input;
    bool _wantsJump;

    void Awake() => _cc = GetComponent<CharacterController>();

    public void SetMoveInput(Vector2 v) => _input = v;
    public void RequestJump() => _wantsJump = true;

    void Update()
    {
        var move = new Vector3(_input.x, 0, _input.y) * _moveSpeed;
        _velocity.x = move.x;
        _velocity.z = move.z;

        if (_cc.isGrounded)
        {
            if (_velocity.y < 0) _velocity.y = -2f; // stick to ground
            if (_wantsJump) _velocity.y = _jumpSpeed;
        }
        else _velocity.y += _gravity * Time.deltaTime;

        _wantsJump = false;
        _cc.Move(_velocity * Time.deltaTime);
    }
}
```

CharacterController doesn't use the physics solver — it does its own sweep tests. Cannot push Rigidbodies without manual code, and is not pushed by them.

### Picking

Rigidbody if physics interaction matters (pushing crates, rolling balls, ragdolls). CharacterController if responsiveness and predictability matter more (precise platforming, twitch FPS). Bespoke `transform`-based controllers are a third option for 2D and stylized games but lose collision robustness; only do this if you've thought through it.

## Health and damage

A simple `IDamageable` interface keeps damage sources unaware of the receiver's specifics:

```csharp
public interface IDamageable
{
    void TakeDamage(in DamageInfo info);
}

public struct DamageInfo
{
    public float Amount;
    public Vector3 HitPoint;
    public Vector3 HitNormal;
    public GameObject Source;
    public DamageType Type;
}

public class Health : MonoBehaviour, IDamageable
{
    [SerializeField] float _max = 100f;
    public float Max => _max;
    public float Current { get; private set; }

    public event System.Action<DamageInfo> Damaged;
    public event System.Action Died;

    void Awake() => Current = _max;

    public void TakeDamage(in DamageInfo info)
    {
        if (Current <= 0) return;
        Current = Mathf.Max(0, Current - info.Amount);
        Damaged?.Invoke(info);
        if (Current <= 0) Died?.Invoke();
    }
}
```

Anything that deals damage — bullets, swords, fire — does `target.GetComponent<IDamageable>()?.TakeDamage(info)`. Decoupled, testable, easy to extend (armor, resistances) by wrapping or substituting the `Health` implementation.

## Spawning and pooling

Spawning prefabs at runtime is everywhere: bullets, enemies, hit effects, pickups. The naive version (`Instantiate` on every spawn, `Destroy` on every despawn) burns CPU and GC. **Pool anything that spawns more than a few times per second.** See `references/performance.md` for the canonical pool implementation; Unity also ships `UnityEngine.Pool.ObjectPool<T>` as a built-in.

The pattern beyond pooling: a `Spawner` or `Factory` MonoBehaviour that owns the pool and exposes `Get()` / `Release()`. Gameplay code never calls `Instantiate` directly.

## Raycasts and physics queries

The right tool for "what's under the crosshair", "is there a wall in front of me", "find enemies within range":

```csharp
// Single hit.
if (Physics.Raycast(origin, direction, out var hit, maxDistance, _hitMask))
    hit.collider.GetComponent<IDamageable>()?.TakeDamage(info);

// Multiple hits — allocates an array; for hot paths use the non-alloc version.
var hits = new RaycastHit[16];
int count = Physics.RaycastNonAlloc(origin, direction, hits, maxDistance, _hitMask);

// Shape queries.
Physics.SphereCast(origin, radius, direction, out hit, maxDistance, _hitMask);
Physics.OverlapSphere(center, radius, _hitMask);            // allocates
Physics.OverlapSphereNonAlloc(center, radius, _buffer, _hitMask); // doesn't
```

Key points:
- **Always pass a `LayerMask`.** Without one, raycasts hit every collider — slow and full of false positives.
- **Use `*NonAlloc` variants in hot paths.** Allocating an array per shot adds up.
- **Triggers are ignored by default** unless you set `Physics.queriesHitTriggers = true` or pass `QueryTriggerInteraction.Collide`.
- **For 2D** the API mirror is `Physics2D.Raycast(...)` etc.

See `references/physics.md` for the deeper physics treatment.

## Triggers vs collisions

- **Collisions** — both colliders are non-trigger. Physics resolves the contact (objects stop, bounce, friction). `OnCollisionEnter/Stay/Exit`.
- **Triggers** — one collider has `isTrigger = true`. No physics resolution; just notification. `OnTriggerEnter/Stay/Exit`.

Rule of thumb: trigger for "did the player walk into a zone" or "did the bullet touch the enemy" (when the bullet shouldn't bounce). Collision for "object stops when it hits a wall."

Both require **at least one of the two participants to have a Rigidbody** for the callback to fire. Forgetting this is the most common "why isn't my trigger firing" issue.

## Event-driven gameplay

For decoupled cross-system signals, three options (also covered in `references/scripting-patterns.md`):

- **C# events on a static or singleton service** — fast, type-safe, but easy to leak if you forget to unsubscribe.
- **ScriptableObject event channels** — designer-friendly, asset-as-rendezvous.
- **`UnityEvent` on a MonoBehaviour** — inspector-wired, designer-friendly, allocates on invoke (don't use in tight loops).

Reach for events when the broadcaster shouldn't know who's listening. Use direct calls when coupling is justified (a Health calling its own `Damaged` event for the same prefab's effects, for instance, can just be a method call).

## Interaction systems

A common pattern for "press E to use":

```csharp
public interface IInteractable
{
    string Prompt { get; }
    void Interact(GameObject who);
}

public class PlayerInteractor : MonoBehaviour
{
    [SerializeField] float _range = 2.5f;
    [SerializeField] LayerMask _mask;
    Camera _cam;

    void Awake() => _cam = Camera.main;

    void Update()
    {
        var ray = _cam.ViewportPointToRay(new Vector3(0.5f, 0.5f));
        IInteractable target = null;
        if (Physics.Raycast(ray, out var hit, _range, _mask))
            target = hit.collider.GetComponent<IInteractable>();

        HUD.SetPrompt(target?.Prompt);
        if (target != null && Input.GetKeyDown(KeyCode.E))
            target.Interact(gameObject);
    }
}
```

Anything interactable implements `IInteractable`. The interactor doesn't care what it is — door, NPC, switch, item. Add new interactables without touching the interactor.

(For real code, use the Input System actions instead of `Input.GetKeyDown`. See `references/input-and-ui.md`.)

## What to keep out of your gameplay code

- **`Camera.main` in Update.** Walks the scene to find the tagged main camera. Cache it once.
- **`GameObject.Find` / `transform.Find` in Update.** String-based, slow, fragile.
- **`new`ing collections in hot paths.** Pre-allocate fields and `.Clear()` between uses.
- **`SendMessage` / `BroadcastMessage`.** String-typed, slow, anti-refactor.
- **Mixed control flow over null/empty/missing components.** Decide where invariants live and assert (`Debug.Assert`) once at init, not check defensively in every method.
