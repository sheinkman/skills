# Testing and debugging

Load this reference when writing automated tests for Unity code, or when investigating bugs that aren't obvious from reading the code. Unity has its own quirks for both — debugging a coroutine that "stops working" or testing a MonoBehaviour both require Unity-specific patterns.

## Unity Test Framework

Unity ships the Test Framework as a package (`com.unity.test-framework`). Add it via Package Manager; tests live in special assemblies.

### Test assembly setup

Tests need their own `.asmdef` files with the `Test Assemblies` flag and references to NUnit + the runtime code they test:

```
Assets/_Project/Tests/
├── EditMode/
│   ├── HealthTests.cs
│   └── <Game>.EditModeTests.asmdef     # platforms: Editor only
└── PlayMode/
    ├── PlayerControllerTests.cs
    └── <Game>.PlayModeTests.asmdef     # platforms: any
```

In the asmdef inspector, check **Test Assemblies** and add references to `nunit.framework.dll`, `UnityEngine.TestRunner`, `UnityEditor.TestRunner` (Edit Mode only), and your runtime assemblies under test.

Open Window → General → Test Runner to run tests. Two tabs:
- **EditMode** — runs in the editor without entering play mode. Fast. For pure C# logic.
- **PlayMode** — runs with the engine and scene loaded. Slower. For MonoBehaviour interactions and physics.

### Edit Mode tests

For anything that doesn't need the Unity loop running:

```csharp
using NUnit.Framework;
using UnityEngine;

public class HealthTests
{
    [Test]
    public void TakeDamage_ReducesCurrent()
    {
        var go = new GameObject();
        var h = go.AddComponent<Health>();

        // If _max is [SerializeField], default is what's in code; for tests
        // either expose an init method or use SerializedObject in editor tests.

        h.TakeDamage(new DamageInfo { Amount = 30f });

        Assert.That(h.Current, Is.EqualTo(70f).Within(0.01f));

        Object.DestroyImmediate(go);
    }
}
```

Notes:
- `new GameObject()` + `AddComponent<T>()` works in Edit Mode tests, but `Awake` is called immediately.
- Use `DestroyImmediate` in Edit Mode; `Destroy` is deferred and won't actually fire without the Unity loop.
- Tests run in alphabetical order by default. Don't depend on order — make each test self-contained.

### Play Mode tests with `[UnityTest]`

For code that needs the engine running (coroutines, physics steps, `Update` calls), use the `[UnityTest]` attribute and return an `IEnumerator`:

```csharp
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;
using System.Collections;

public class PlayerControllerTests
{
    [UnityTest]
    public IEnumerator Player_FallsUnderGravity()
    {
        var go = new GameObject("Player");
        var rb = go.AddComponent<Rigidbody>();
        go.transform.position = Vector3.up * 5f;

        yield return new WaitForSeconds(0.5f);  // physics steps run

        Assert.Less(go.transform.position.y, 5f);

        Object.Destroy(go);
    }
}
```

`yield return null` advances one frame; `yield return new WaitForSeconds(t)` advances time; `yield return new WaitForFixedUpdate()` advances one physics step.

### Setup and teardown

```csharp
public class FooTests
{
    GameObject _go;

    [SetUp]
    public void SetUp() => _go = new GameObject("test");

    [TearDown]
    public void TearDown()
    {
        if (_go != null) Object.DestroyImmediate(_go);
    }

    [Test] public void Foo1() { /* uses _go */ }
    [Test] public void Foo2() { /* uses _go */ }
}
```

`[OneTimeSetUp]` / `[OneTimeTearDown]` run once per class. `[SetUp]` / `[TearDown]` run per test.

### Mocking MonoBehaviours

This is the hard part of Unity testing. You can't easily mock a MonoBehaviour because `new TestableHealth(...)` doesn't give you a real component. Patterns:

1. **Extract logic from MonoBehaviour into plain C# classes.** Test those. The MonoBehaviour becomes a thin "wires up serialized fields, calls the logic" shell — barely worth testing.
2. **Interfaces for dependencies.** Inject through serialized fields with `[SerializeReference]` or initializer methods. Tests pass fakes.
3. **Test the full thing in PlayMode.** Slow but realistic.

For complex projects, the first pattern (logic in POCOs) pays back tenfold. MonoBehaviours become thin enough that you trust them by inspection.

### Test scenes

For PlayMode tests that need a specific scene setup, create a scene under `Assets/Tests/Scenes/` and load it:

```csharp
[UnityTest]
public IEnumerator Level_LoadsAndPlayerSpawns()
{
    yield return SceneManager.LoadSceneAsync("TestArena", LoadSceneMode.Single);
    var player = Object.FindAnyObjectByType<Player>();
    Assert.IsNotNull(player);
}
```

Tests scenes must be in **Build Settings** (or use `EditorSceneManager.LoadSceneInPlayMode` from an editor test) to load. Test scenes don't usually ship in the player build — strip them via a build hook or a separate addressable.

## Debugging tools

### `Debug.Log` and friends

`Debug.Log`, `Debug.LogWarning`, `Debug.LogError`. The last two pause Play Mode if "Error Pause" is enabled in the Console — useful for catching the moment a problem starts.

**Conditional compilation** keeps logs out of release builds:

```csharp
public static class Log
{
    [System.Diagnostics.Conditional("UNITY_EDITOR")]
    [System.Diagnostics.Conditional("DEVELOPMENT_BUILD")]
    public static void Dev(string msg) => Debug.Log(msg);
}
```

`[Conditional]` makes the *call site* compile out when the symbol isn't defined — better than `#if UNITY_EDITOR` blocks around every log because the arguments aren't evaluated either (no string concatenation cost).

`UNITY_EDITOR` is set in the editor; `DEVELOPMENT_BUILD` when "Development Build" is checked in Build Profiles.

### `Debug.Assert` and `Debug.AssertFormat`

```csharp
Debug.Assert(_target != null, $"Target was null on {name}");
```

Stripped in release builds via `[Conditional]`. Use for invariants you want to catch in development but can't afford in release. **Don't use `Assert` for things that can legitimately fail at runtime** (file I/O, network) — those need real handling.

### `Debug.DrawLine` and `Debug.DrawRay`

Visual debug in the scene view:

```csharp
void Update()
{
    Debug.DrawRay(transform.position, transform.forward * 2f, Color.red, 0f, true);
}
```

Only visible in the editor and only when "Gizmos" is on in the Game view. Free; use liberally.

### Gizmos

Persistent visual aids. `OnDrawGizmos` runs in edit mode and play mode; `OnDrawGizmosSelected` only when selected. See `references/editor-tooling.md` for examples.

### Stepping through code

Attach a debugger from your IDE (Rider, Visual Studio, VS Code with C# Dev Kit). All have "Attach to Unity" buttons. Breakpoints work in both Editor and a Development Build with "Script Debugging" enabled.

If breakpoints aren't being hit:
- Verify "Script Debugging" is on in Build Profiles (or that you're attached to the editor).
- For Development Builds, verify "Wait For Managed Debugger" if the issue is early-game code.
- The script must be in a non-optimized build configuration.

### `Application.logCallback` and log files

Logs are written to a file on every platform:

| Platform   | Log location                                                         |
|------------|----------------------------------------------------------------------|
| Windows    | `%LOCALAPPDATA%\<Company>\<Product>\Player.log` (and `Player-prev.log`) |
| macOS      | `~/Library/Logs/<Company>/<Product>/Player.log`                       |
| Linux      | `~/.config/unity3d/<Company>/<Product>/Player.log`                    |
| Android    | `adb logcat -s Unity DEBUG`                                          |
| iOS        | Xcode device console                                                 |

For runtime error reporting, hook `Application.logMessageReceived`:

```csharp
void OnEnable() => Application.logMessageReceived += OnLog;
void OnDisable() => Application.logMessageReceived -= OnLog;

void OnLog(string condition, string stackTrace, LogType type)
{
    if (type == LogType.Exception)
        SendToCrashReporter(condition, stackTrace);
}
```

## Common debugging scenarios

### "My coroutine stopped"

Coroutines are killed when the host GameObject is disabled. Even a one-frame disable kills them. Use `Awaitable` with a `CancellationTokenSource` you own, or start coroutines on a long-lived persistent object.

### "My OnTriggerEnter doesn't fire"

- One of the two colliders needs a Rigidbody.
- Both layers need to collide per the Layer Collision Matrix.
- The trigger isn't actually a trigger (`isTrigger` checkbox).
- The other object's collider isn't actually overlapping yours (scale, offset, hidden child).

The fastest check: temporarily add a `OnTriggerEnter(Collider other) => Debug.Log($"Hit by {other.name}");` and see what fires.

### "It works in the editor but not in builds"

Usual suspects:
- A scene not in Build Settings.
- A `Resources` asset that got tree-shaken because nothing references it directly (Resources.Load with a typo'd path).
- Code-stripping (IL2CPP) removing types only referenced via reflection. Add to `link.xml` to preserve.
- `UNITY_EDITOR` guards around code that should run in the build.
- A reference assigned in the editor that didn't survive scene serialization.

Make a Development Build with "Autoconnect Profiler" and "Script Debugging" on, then compare logs to the editor run.

### "Why is this null?"

- Inspector reference never assigned (the field is grey-with-None in the inspector).
- Component not on the GameObject you expected (you wrote `GetComponent<X>` on the wrong object).
- Object was destroyed earlier in the frame; the `!=` check actually passes because Unity overloads `==` to check for the "destroyed sentinel" — but reading the field after destroy still throws.
- The object exists but isn't part of the scene yet (prefab not instantiated).

Add a one-line `Debug.Log($"_thing on {name} = {_thing}", this);` at the failing point. The clickable `this` jumps to the offending GameObject in the hierarchy.

### Editor freezes / hangs

- Infinite loop in `Update`, `OnGUI`, or `OnDrawGizmos`. The editor calls these constantly; an infinite loop in `OnDrawGizmos` is particularly nasty because it fires per repaint.
- Modal `EditorUtility.DisplayDialog` that never returns because something behind it is also waiting.
- Stuck synchronous import (huge model). The editor reloads after import finishes; just wait.

Kill the editor, look at the log file for the last stack trace before the hang.

## Common pitfalls

- **Tests that depend on order.** Each test must set up its own state.
- **`Destroy` in Edit Mode tests** — silently does nothing. Use `DestroyImmediate`.
- **Logs as flow control.** `Debug.Log` is for humans, not for production code paths. Don't conditionally take a branch based on whether logging is enabled.
- **`Debug.Log` in tight loops.** Even with `[Conditional]`, a stray log inside `Update` ships and floods the console. Prefer custom verbose levels gated by editor flags.
- **No teardown.** Tests that leak GameObjects, static state, or `DontDestroyOnLoad` objects break the next test. Clean up in `[TearDown]`.
- **Mixing UnityTest and Task.** Async tests via `[UnityTest]` returning `IEnumerator` is the supported path. `async Task` tests work in newer NUnit versions but interact awkwardly with the Unity loop. Prefer the IEnumerator pattern.
