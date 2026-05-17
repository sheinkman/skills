---
name: unity
description: Use this skill for any work in a Unity 6.4 + URP project — writing or reviewing C# gameplay code, scaffolding projects, debugging Unity issues, editor tools, shaders and Render Graph passes, audio, AI/NavMesh, 2D/isometric, Addressables, performance, or shipping builds. Trigger on Unity, `.unity` / `.meta` / `.prefab` / `.asmdef` files, MonoBehaviour, ScriptableObject, GameObject, URP, HDRP, Shader Graph, Render Graph, EditorWindow, Input System, UI Toolkit, Job System, ECS / Entities, Cinemachine, Animator, Rigidbody, raycast, NavMesh, AudioSource, AudioMixer, Tilemap, Addressables, Build Profiles, IL2CPP, or Unity APIs (`Awaitable`, `FindAnyObjectByType`, `[SerializeField]`, `OnTriggerEnter`, `CinemachineCamera`, `NavMeshAgent`, `AssetReference`). Also trigger on casual asks like "write a player controller", "why is my scene laggy", "save system", "build for Steam", or Play Mode / Edit Mode tests. Targets Unity 6.4 with URP and Forward+. Load `references/` files on demand.
---

# Unity 6.4 + URP

This skill is for working in Unity 6.4 projects using URP as the render pipeline. Forward+ is the default rendering path; assume it unless the project says otherwise.

A version note worth knowing: **Unity 6.4 is a "Supported" release**, not LTS. The current LTS is Unity 6.3 (Dec 2025, supported through Dec 2027). Supported releases get the same bug-fix support as LTS, but only until the next release ships — so a 6.4 project will eventually need to upgrade to 6.5 or move back to 6.3 LTS. If the user is choosing between them and doesn't have a specific reason to be on 6.4, mention this.

## Before you write anything

- **Read the project first.** Per-project conventions (namespace style, prefab locations, ScriptableObjects vs JSON vs Addressables, frameworks like UniTask, Zenject, VContainer) trump generic advice — new code should look like it belongs.
- **Verify the Unity version.** Check `ProjectSettings/ProjectVersion.txt`. If it's not `6000.4.x`, flag the mismatch — some 6.4 APIs won't compile on earlier 6.x.
- **Check assembly definitions.** New scripts must live in the right `.asmdef` or they won't see their dependencies. Match the folder.
- **Don't assume a package is installed.** Check `Packages/manifest.json` before reaching for Input System, Cinemachine, Addressables, UniTask, Netcode, Localization. (In 6.4, ECS and Mathematics ship as Core — already there.)
- **Never edit `.meta` files by hand.** Unity owns them. Rewriting one reassigns the GUID and silently breaks every prefab and scene that referenced the asset.

## The Unity 6.4 mental model

A few things changed in Unity 6 / 6.4 that date code immediately or break compilation if you get them wrong.

### Finding objects

`FindObjectOfType` / `FindObjectsOfType` were deprecated in 6.0; in 6.4, even `FindFirstObjectByType` is soft-deprecated (relies on instance-ID ordering). Canonical APIs:

- `Object.FindAnyObjectByType<T>()` — fastest, no ordering guarantees. **Default to this.**
- `Object.FindObjectsByType<T>(FindObjectsSortMode.None)` for all instances. Always pass `None` unless you genuinely need sorting. Add `FindObjectsInactive.Include` for disabled objects.

In gameplay code, prefer serialized inspector references. `Find*ByType` is for editor tools and one-time bootstrapping, not per-frame.

### Async work

Unity 6.0 added `Awaitable`, a Unity-aware async primitive with main-thread integration and `CancellationToken` support. Prefer `Awaitable` over coroutines when you need a return value, clean cancellation, or chained over-time operations.

Coroutines are still fine for simple "wait, then do" — don't rewrite working ones. If the project uses **UniTask** (`Cysharp.Threading.Tasks`), follow that convention; don't mix `Awaitable` and UniTask in the same subsystem.

### URP rendering — Render Graph only

The biggest 6.4 change: **URP Compatibility Mode was removed.** The old `ScriptableRenderPass.Execute(ScriptableRenderContext, ref RenderingData)` no longer compiles. All custom passes must implement `RecordRenderGraph(RenderGraph, ContextContainer)`. Porting is non-trivial — see `references/urp-rendering.md`.

The **Volume system** owns post-processing. Global volumes apply everywhere, local volumes blend by proximity. Cameras pick them up via their `Volume Mask`.

### ECS is built in

In 6.4, Entities, Collections, Mathematics, and Entities Graphics ship as Core packages — no separate install. Expect ECS code mixed into traditional GameObject projects.

Related: `InstanceID` is being replaced by `EntityId`. `EntityId` cannot be safely cast to/from `int` — drop that assumption in any new code touching object IDs.

### Input — new Input System is the default

If you see `[SerializeField] InputActionReference` or generated wrapper classes from a `.inputactions` asset, that's the new system. Legacy `Input.GetKey` still works for prototypes but isn't where new code should land. See `references/input-and-ui.md`.

### UI — UI Toolkit is preferred for new UI

UI Toolkit (UXML + USS, runtime + editor) is the modern framework. UGUI is still the right choice for world-space UI, particle-driven UI, or projects already standardized on it. Don't migrate working UGUI without a reason. See `references/input-and-ui.md`.

## Project conventions

- **Namespaces.** `CompanyName.GameName.Subsystem`. Avoid the global namespace — refactoring becomes painful and you'll collide with package names.
- **One MonoBehaviour per file**, file named after the class.
- **Prefab variants over duplication.** If two prefabs share 90% of structure, the second should be a variant of the first.
- **ScriptableObjects for static data.** Enemy stats, item definitions, level configs, audio cue tables. See `references/scripting-patterns.md`.
- **Don't ship singleton MonoBehaviours lightly.** Edit-mode, scene reload, execution order, and domain reload all bite. If you must, gate with `[DefaultExecutionOrder(-100)]` and a `[RuntimeInitializeOnLoadMethod]` bootstrap.

## When to load a reference

The references in `references/` are intentionally narrow. Load only what the current task needs.

| Reference | Load when working on… |
|---|---|
| `core-patterns.md` | Evergreen Unity C# rules: caching `GetComponent`, `[SerializeField] private`, `Awake` vs `Start`, `CompareTag`, physics in `FixedUpdate`, avoiding `Update` allocations. Load before writing any gameplay code. |
| `scripting-patterns.md` | Non-trivial gameplay code: MonoBehaviour lifecycle, ScriptableObject patterns (event channels, runtime sets), `Awaitable` vs coroutines, DI without a framework. |
| `gameplay-patterns.md` | State machines (enum and class-based), player controllers (Rigidbody / CharacterController), health/damage with `IDamageable`, spawning, raycasting, triggers, interactions. |
| `physics.md` | Rigidbody types and timing, the `linearVelocity` rename, raycasts and shape queries with NonAlloc variants, layers and the collision matrix, CharacterController vs Rigidbody, 2D physics (Box2D v3). |
| `animation-and-cinemachine.md` | Animator (states, parameters, blend trees, layers, root motion, animation events) and Cinemachine 3 — anything pre-Unity-6 uses stale names. |
| `audio.md` | AudioSource patterns, AudioMixer + snapshots, exposed parameters with linear-to-dB conversion, 3D spatialization (listener placement for isometric), SFX pooling, music layering, ducking. |
| `ai-and-navmesh.md` | AI Navigation (`NavMeshSurface`, `NavMeshAgent`, `NavMeshLink`, `NavMeshModifier`), runtime baking, enemy AI state machines with sight/sound. Also 2D pathfinding (NavMeshPlus, A*). |
| `urp-rendering.md` | Shaders, custom render passes, post-processing, Render Graph. Critical for 6.4 because Compatibility Mode is removed and `RecordRenderGraph` is the only API. |
| `performance.md` | Profiler workflow, GC allocations, draw call batching, GPU Resident Drawer, Project Auditor, DirectStorage, Burst + Job System. |
| `input-and-ui.md` | Input System (actions, bindings, generated wrappers, control schemes) and UI Toolkit vs UGUI tradeoffs. |
| `editor-tooling.md` | Custom inspectors (UI Toolkit first), property drawers, `EditorWindow`, asset post-processors, menu items, gizmos, build hooks, `SerializedObject` / `SerializedProperty`. |
| `saves-and-data.md` | Persistence: `persistentDataPath`, `PlayerPrefs` vs JSON, JsonUtility limits, Newtonsoft.Json, atomic writes, save versioning and migrations. |
| `testing-and-debugging.md` | Unity Test Framework (Edit Mode, Play Mode, `[UnityTest]`), `[Conditional]` logging, gizmos, log file locations, common bug patterns. |
| `two-d-and-isometric.md` | 2D fundamentals (sprite import, atlases, sorting, 2D lighting in URP, Tilemap) and isometric. Key first decision: "3D with iso camera" vs "pure 2D iso". |
| `addressables.md` | Addressables: `AssetReference`, async loading, groups and labels, reference counting (the part most people get wrong), build profiles, content updates. |
| `project-setup.md` | New Unity 6.4 + URP project scaffolding: folder layout, `.asmdef` strategy, standard packages, `.gitignore` rules, editor settings, first build configuration. |
| `build-and-platforms.md` | Unity 6 Build Profiles, IL2CPP vs Mono, scripting define symbols, platform-specific code, build size reduction, automation, Steam shipping checklist. |
| `api-migrations.md` | Unity 6.0 / 6.4 deprecations with modern replacements: `FindObjectOfType` family, URP Compatibility Mode, `InstanceID` → `EntityId`, `Rigidbody.velocity` → `linearVelocity`, Cinemachine 2 → 3. |

## Things to avoid

- `GameObject.Find("name")` — fragile, slow, breaks the moment someone renames the object.
- `SendMessage` / `BroadcastMessage` — string-based, no compile-time safety, slow.
- `Debug.Log` in shipped builds. Wrap in `#if UNITY_EDITOR` or use a logger that gets stripped via conditional compilation.
- Allocating in `Update` without a measured reason.
- Public serialized fields when `[SerializeField] private` would do.
- Singletons of MonoBehaviours, unless you've thought through scene reload, edit-mode, and domain reload.
- Mixing editor and runtime code in one file (it won't compile in a player build).
- Using the legacy Input Manager (`Input.GetKey`, `Input.GetAxis`) for anything beyond a quick prototype, if the project has the Input System available.
- Casting `EntityId` to `int` in 6.4 — it's not a single int anymore.

## Symptom → reference lookup

A fast index for common Unity 6.4 problems. Match the symptom, then load the reference.

| Symptom | Where to look |
|---|---|
| Custom render pass won't compile, `Execute(...)` missing | `urp-rendering.md` (Render Graph migration) |
| `FindObjectOfType` / `FindFirstObjectByType` deprecation warnings | `api-migrations.md` |
| `Rigidbody.velocity` deprecation, jittery physics | `physics.md`, `api-migrations.md` |
| `CinemachineVirtualCamera` doesn't exist, namespace errors | `animation-and-cinemachine.md` (Cinemachine 3) |
| Coroutine stopped firing after `SetActive(false)` | `testing-and-debugging.md`, `scripting-patterns.md` |
| Works in the editor, broken in a build | `testing-and-debugging.md`, `build-and-platforms.md` (IL2CPP stripping, `link.xml`) |
| Scene laggy, GC spikes in the Profiler | `performance.md` |
| Save corrupts after a crash | `saves-and-data.md` (atomic writes) |
| `OnTriggerEnter` not firing | `testing-and-debugging.md`, `physics.md` (collision matrix, Rigidbody required) |
| UI clicks don't register | `input-and-ui.md` (EventSystem + `InputSystemUIInputModule`) |
| `Addressables` works once, fails after a scene reload | `addressables.md` (reference counting) |
| Magenta materials in URP scene | `urp-rendering.md` (legacy shader conversion) |
| Animator transitions feel laggy or delayed | `animation-and-cinemachine.md` ("Has Exit Time") |
| ECS / `InstanceID` cast errors after upgrade | `api-migrations.md` (`InstanceID` → `EntityId`) |
