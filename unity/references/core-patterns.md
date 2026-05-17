# Core C# patterns for Unity

Load this reference when writing or reviewing Unity gameplay code. These rules are evergreen — they predate 6.4 and apply to any Unity project. For deeper architectural patterns (state machines, ScriptableObject channels, DI, `Awaitable` deep dives), see `scripting-patterns.md`.

## Cache lookups

Never call `GetComponent`, `Find*ByType`, or `transform.Find` inside `Update` / `FixedUpdate`. Cache in `Awake` or `OnEnable`.

```csharp
Rigidbody _rb;
void Awake() => _rb = GetComponent<Rigidbody>();
void FixedUpdate() => _rb.AddForce(_input);
```

The cost is small per call but compounds across many instances and frames.

## Prefer `[SerializeField] private` over `public`

```csharp
[SerializeField] float _speed = 5f;
```

Exposes the field to the inspector without exposing it to other scripts. Public fields are a much weaker encapsulation than people realize — anything in the assembly can mutate them silently.

## `Awake` for self-init, `Start` for cross-object init

`Awake` runs before any `Start`. Anything other scripts will reach for in *their* `Start` must be set up in your `Awake`. Anything that depends on other components being ready goes in `Start`.

## Strings are cheap to write, expensive at runtime

- Use `gameObject.CompareTag("Enemy")`, not `gameObject.tag == "Enemy"` — the `tag` getter allocates.
- Cache `Animator.StringToHash("Jump")` once at startup; the hashed animator overloads skip the string lookup.
- Avoid string concatenation on hot paths. `$"..."` is fine when the value changes; cache the rendered string when it doesn't.

## Physics in `FixedUpdate`, input in `Update`

Apply forces and impulses via `Rigidbody`, never direct `transform` writes on a physics body — you'll fight the solver and get jitter. Read input in `Update` (sample at display rate); apply it as a force in `FixedUpdate` (consistent physics timestep).

## Coroutines do not survive `SetActive(false)`

Disabling the GameObject kills the coroutine even if you re-enable it later. This is a common source of "why did my logic stop?" bugs.

For longer-lived async work that should survive disable, use `Awaitable` tied to a `CancellationToken` you own, or run the coroutine on a persistent manager object. See `scripting-patterns.md` for `Awaitable` patterns.

## Don't allocate in `Update` without measurement

`new List<T>()` per frame is a GC spike. Pool a `List<T>` field cleared with `.Clear()` each frame, or use `Span<T>` / `stackalloc` where applicable. For deeper GC investigation, see `performance.md`.

## See also

- `scripting-patterns.md` — architectural patterns, ScriptableObject channels, DI, `Awaitable` deep dive.
- `performance.md` — Profiler workflow and GC investigation.
- `physics.md` — Rigidbody types, NonAlloc query variants, CharacterController vs Rigidbody.
