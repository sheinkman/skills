# Scripting patterns

Load this reference when writing non-trivial gameplay C# in a Unity 6.4 project. Covers lifecycle, ScriptableObject patterns, async, events, and how to avoid the architectural tarpits that haunt long-lived Unity projects.

## MonoBehaviour lifecycle in depth

The order Unity calls these methods matters more than people remember:

1. **`Awake`** — once per object, before any `Start`. Use for self-init: caching `GetComponent` references, allocating buffers, computing constants. Don't reach into other objects here; they may not have run their `Awake` yet (execution order is not guaranteed across objects).
2. **`OnEnable`** — every time the component (or its GameObject) is enabled. Use for **subscribing to events**. Pair every `OnEnable` subscription with an `OnDisable` unsubscription — leaks here are silent and survive scene reloads in domain-reload-disabled projects.
3. **`Start`** — once, before the first `Update`, after all `Awake` calls. Use for cross-object init: looking up another component or service that's now guaranteed to exist.
4. **`Update`** — per frame, variable delta time. Game logic, input reading, animation polling.
5. **`FixedUpdate`** — fixed delta time (default 0.02s). Physics writes belong here. Reading `Time.fixedDeltaTime` is correct here, not `Time.deltaTime`.
6. **`LateUpdate`** — after all `Update`s. Camera following, IK touch-ups, anything that needs everything else already moved.
7. **`OnDisable`** — pair with `OnEnable`.
8. **`OnDestroy`** — final cleanup. Be careful: in builds with domain reload disabled (the modern default for fast iteration), static state survives Play Mode exits — clean it up here or in a `[RuntimeInitializeOnLoadMethod]` reset.

A subtle one: `Awake` runs on inactive objects too (as long as they were instantiated). `OnEnable`/`Start` do not run until the object is actually enabled.

### Execution order

Unity gives no guarantee about the order of `Awake` between different scripts on different objects. If you need ordering:

- `[DefaultExecutionOrder(-100)]` on a class moves it earlier. Use sparingly; it's a smell.
- Better: structure the code so `Awake` doesn't reach across objects, and use `Start` (or explicit init calls) for cross-object setup.
- Best: don't depend on order — use events, ScriptableObject channels, or explicit `Initialize(...)` calls from a bootstrap script.

## `Awake` is not a constructor

A MonoBehaviour's actual constructor runs on a serialization thread during deserialization. **Don't put logic in the constructor** — it'll run at strange times (editor reloads, prefab inspector previews) and `transform`, `gameObject`, and serialized fields aren't reliably available. `Awake` is the right place.

## `[SerializeField]` and serialization rules

Unity's serialization has its own rules, separate from `System.Runtime.Serialization`:

- Public fields are serialized by default. Private fields need `[SerializeField]`.
- Only certain types serialize: primitives, `string`, `UnityEngine.Object` references, enums, structs with `[Serializable]`, classes with `[Serializable]` (one level — no inheritance), and `List<T>`/arrays of any of the above.
- `Dictionary<K,V>` does **not** serialize. Use a `List<Pair>` with `[Serializable]` `Pair` struct, or `SerializedDictionary` from a package, or build the dict in `Awake` from a list.
- Auto-properties don't serialize. Use a backing field with `[SerializeField]` and a property.
- `readonly` fields don't serialize even if marked `[SerializeField]`.
- Polymorphism is opt-in: mark the field with `[SerializeReference]` to allow subclass instances. Without it, the runtime type is collapsed to the field's declared type.

When a serialized field changes shape (rename, type change), use `[FormerlySerializedAs("oldName")]` to preserve data already saved in scenes and prefabs.

## ScriptableObject patterns

ScriptableObjects are serializable Unity objects that exist as **project assets**, not on GameObjects. Unity itself heavily promotes them; their main strengths are designer-editability via the inspector, deduplication of shared data, and decoupling.

### As shared data

The canonical use case. Define stats, item descriptors, level layouts, audio cues as ScriptableObject assets:

```csharp
[CreateAssetMenu(menuName = "Game/Enemy Stats")]
public class EnemyStats : ScriptableObject
{
    public string displayName;
    public float maxHealth;
    public float moveSpeed;
    public DamageType damageType;
}
```

Then reference them from MonoBehaviours: `[SerializeField] private EnemyStats _stats;` and drag the asset in. Designers can tweak balance without code changes; multiple enemies share one definition.

### As event channels

A ScriptableObject that exposes a delegate and a `Raise` method. Subscribers find each other through the shared asset rather than direct references, which decouples scenes and systems:

```csharp
[CreateAssetMenu(menuName = "Game/Events/Void Event")]
public class VoidEventChannel : ScriptableObject
{
    public event System.Action OnEventRaised;
    public void Raise() => OnEventRaised?.Invoke();
}
```

Subscribers do `_channel.OnEventRaised += Handler` in `OnEnable` and `-=` in `OnDisable`. Broadcasters call `_channel.Raise()`. The asset is the rendezvous point. Works well for cross-scene events, decoupled UI updates, and "thing happened" signals.

The cost: indirection. If you over-channel everything, it gets hard to trace flow. Use channels for genuinely cross-cutting events, direct calls for tight coupling.

### As runtime sets

A ScriptableObject that holds a `List<T>` of active instances:

```csharp
[CreateAssetMenu(menuName = "Game/Sets/Enemy Set")]
public class EnemySet : ScriptableObject
{
    public readonly List<Enemy> items = new();
    public void Add(Enemy e) => items.Add(e);
    public void Remove(Enemy e) => items.Remove(e);
}
```

Enemies register on `OnEnable` and unregister on `OnDisable`. Anyone who wants "all enemies" reads from the set instead of doing `FindObjectsByType`. Same decoupling benefits. **Reset the list on play mode entry** if domain reload is disabled (use `[RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]`).

### Pitfalls

ScriptableObject state **persists across Play Mode in the editor**. If you mutate a SO at runtime, those changes stick in the asset file. Either don't mutate them, or copy to a runtime instance (`Instantiate(_template)`) before mutating. This is the #1 cause of "my game state is wrong on the second play" bugs in SO-heavy projects.

## `Awaitable` vs coroutines

Both let you sequence work across frames. Pick by the situation, not by ideology.

### Coroutines — `IEnumerator` + `StartCoroutine`

Strengths: trivially cheap, tied to the MonoBehaviour's enabled state (auto-cancelled when the object is disabled), readable for simple "wait then do" flows. `yield return new WaitForSeconds(2f)` says exactly what it means.

Weaknesses: can't return values, can't easily compose, exceptions in nested coroutines are awkward, cancellation requires `StopCoroutine` with a stored reference. **Coroutines die when the GameObject is disabled — even momentarily — and don't restart.**

### `Awaitable` — Unity 6.0+

A Unity-aware `Task`-like type. Integrates with `async`/`await`, supports `CancellationToken`, plays nicely with the main thread.

```csharp
async Awaitable Reload(CancellationToken ct)
{
    PlayReloadAnim();
    await Awaitable.WaitForSecondsAsync(1.5f, ct);
    _ammo = _magSize;
}

CancellationTokenSource _reloadCts;

void OnEnable()  => _reloadCts = new CancellationTokenSource();
void OnDisable() { _reloadCts.Cancel(); _reloadCts.Dispose(); }
```

Strengths: returns values, real cancellation, composable, exceptions propagate. You can `await` from inside another `await`.

Weaknesses: a tiny bit more boilerplate (`CancellationTokenSource` lifecycle); easier to leak if you forget to cancel; the mental model of `async` in a game loop trips people up at first.

### UniTask

If the project uses UniTask (`Cysharp.Threading.Tasks`), it's the third option — predates `Awaitable`, is zero-allocation, has a richer API. Conform to it if it's already in the codebase. Don't introduce it alongside `Awaitable` for new code in a 6.4 project unless there's a real reason; pick one per subsystem.

### Picking

- Simple "wait, then do something on this object" → coroutine.
- Anything with cancellation, return values, or composition → `Awaitable`.
- Project already on UniTask → UniTask.

## Events without a framework

For decoupled cross-system signals, you have three native options:

1. **C# events on a static class or singleton** — `public static event Action<int> OnScoreChanged;`. Fast, type-safe, no asset needed. Risk: anyone can subscribe; statics survive scene reload; easy to leak if you forget to `-=`.
2. **ScriptableObject event channels** — discussed above. Editor-friendly, asset-as-rendezvous.
3. **`UnityEvent` on a MonoBehaviour** — serializable in the inspector, designers can wire targets without code. Allocates on invoke (a few bytes); avoid in tight loops. Best for UI buttons and inspector-driven hookups.

For new code in a fresh project, ScriptableObject channels and C# events cover 90% of needs. Reach for a DI container only when the project's complexity actually demands it.

## Dependency injection without a framework

You don't need Zenject or VContainer to write clean Unity code. Patterns that work:

- **Serialized references.** A MonoBehaviour exposes a `[SerializeField] private IDamageable _target;` (use `[SerializeReference]` if `IDamageable` is an interface) and the designer wires it. Zero runtime cost, totally explicit.
- **Initializer methods.** `public void Initialize(GameContext ctx) { _ctx = ctx; }` called from a bootstrap script. Replaces `Awake`'s implicit "find my dependencies" with explicit injection.
- **ScriptableObject services.** Define an `IPlayerService` interface, implement it as a ScriptableObject, drag it into wherever it's needed. Swap implementations by swapping the asset.

Reach for a real DI framework only when you have many services with deep object graphs and lots of test setup. For most indie/small-team projects, the patterns above are simpler and faster.

## Don't do this

- `void Update() { var enemies = FindObjectsByType<Enemy>(...); }` — runs a full scan every frame.
- `Instantiate(prefab)` in `Update` without pooling — GC + Awake costs add up fast.
- `transform.position += velocity * Time.deltaTime` on a Rigidbody body — bypass the physics solver. Use `Rigidbody.MovePosition` or apply forces.
- Long `async void` methods on MonoBehaviours — unhandled exceptions vanish. Prefer `async Awaitable` and observe the result, or wrap in try/catch.
- Mutating a ScriptableObject asset at runtime and expecting it to reset on Play exit. It won't.
- Calling `gameObject.AddComponent<T>()` at runtime in a hot path — slow, allocates. Add components in the prefab or at spawn time.
