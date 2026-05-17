# API migrations

Load this reference when porting older Unity code, when you see deprecation warnings, or when you want to verify "what's the current API for X?" in a Unity 6.4 project. The deprecations stack — things deprecated in 6.0 are still deprecated (or harder-obsolete) in 6.4.

## Finding objects

The whole `Object.FindObject*` family was reworked.

| Legacy (pre-6.0)                 | Status in 6.4         | Use instead                                                                                    |
|----------------------------------|-----------------------|------------------------------------------------------------------------------------------------|
| `FindObjectOfType<T>()`          | Obsolete              | `Object.FindAnyObjectByType<T>()` — fastest, no ordering guarantee.                            |
| `FindObjectsOfType<T>()`         | Obsolete              | `Object.FindObjectsByType<T>(FindObjectsSortMode.None)`                                        |
| `FindObjectOfType<T>(true)`      | Obsolete              | `Object.FindAnyObjectByType<T>(FindObjectsInactive.Include)`                                   |
| `FindObjectsOfType<T>(true)`     | Obsolete              | `Object.FindObjectsByType<T>(FindObjectsInactive.Include, FindObjectsSortMode.None)`           |
| `FindFirstObjectByType<T>()`     | **Obsolete in 6.4+**  | `Object.FindAnyObjectByType<T>()` (the ordering guarantee `FindFirstObjectByType` relied on is going away). |

Always pass `FindObjectsSortMode.None` to `FindObjectsByType` unless you specifically need the results sorted — sorting costs real time.

In gameplay code, prefer **serialized references in the inspector** over runtime lookups. `Find*ByType` is fine for editor tools and one-time bootstrapping; it's not for per-frame code.

## Coroutines and async

`Coroutine` and `StartCoroutine` are not deprecated — they're still the right tool for simple over-time logic.

What's new: `UnityEngine.Awaitable` (Unity 6.0+) is the modern async primitive. Use it when you need return values, cancellation tokens, or composition. See `references/scripting-patterns.md` for the deeper guide.

```csharp
// Then
IEnumerator WaitAndDo() { yield return new WaitForSeconds(1f); /* ... */ }

// Now (when you need cancellation / return values / composition)
async Awaitable WaitAndDo(CancellationToken ct)
{
    await Awaitable.WaitForSecondsAsync(1f, ct);
    /* ... */
}
```

## URP Compatibility Mode — removed in 6.4

This is the largest 6.4 breaking change. **Anything that depended on URP Compatibility Mode is now hard-obsolete and won't compile.**

| Removed in 6.4                                            | Use instead                                                                |
|-----------------------------------------------------------|----------------------------------------------------------------------------|
| `ScriptableRenderPass.Execute(ScriptableRenderContext, ref RenderingData)` | `ScriptableRenderPass.RecordRenderGraph(RenderGraph, ContextContainer)`     |
| `ScriptableRenderPass.OnCameraSetup(...)` / `Configure(...)` | The Render Graph builder pattern — declare resources via `builder.UseTexture` / `builder.SetRenderAttachment`. |
| Manual `CommandBuffer.GetTemporaryRT` for pass-local RTs  | `renderGraph.CreateTexture(desc)` or `UniversalRenderer.CreateRenderGraphTexture(...)` |

See `references/urp-rendering.md` for the full Render Graph pattern, including a worked example of porting an old `Execute`-based pass.

## `InstanceID` → `EntityId` (6.4)

Unity 6.4 introduces a new `EntityId` type for identifying objects, replacing `InstanceID` in many places. `InstanceID` methods are marked deprecated.

Watch out:
- `EntityId` cannot be cast to/from a single `int`. Old code like `int id = obj.GetInstanceID();` and using it as a dictionary key still compiles for now (`GetInstanceID()` is preserved), but new APIs return `EntityId`.
- If you serialize `int` IDs across saves or networking, this doesn't directly affect you — keep doing that.
- Touched mostly when working with ECS or low-level engine internals.

## Input — legacy vs new

Both still work in 6.4. Pick one per project.

| Legacy Input Manager                       | New Input System (package)                                |
|--------------------------------------------|-----------------------------------------------------------|
| `Input.GetKey(KeyCode.W)`                  | `_moveAction.action.ReadValue<Vector2>()`                 |
| `Input.GetAxis("Horizontal")`              | Same, via an Input Action of type Axis or Vector2.        |
| `Input.GetButtonDown("Fire1")`             | `_fireAction.action.WasPressedThisFrame()`                |

The new system is the default for new projects (Player Settings → Active Input Handling → Input System Package). If a project shows both, that's a transition state — finish the migration or pick one. See `references/input-and-ui.md`.

## UI — UGUI vs UI Toolkit

UGUI (`UnityEngine.UI.*`) is not deprecated. UI Toolkit (`UnityEngine.UIElements.*`) is the modern alternative. Pick by use case, not by recency. See `references/input-and-ui.md` for the comparison.

## Post-processing — Post-Process Stack v2 → Volume system

Post-Process Stack v2 (the legacy package) was removed long ago. URP uses the Volume system natively:

| Legacy PPv2                                       | URP Volume system                                            |
|--------------------------------------------------|--------------------------------------------------------------|
| `PostProcessVolume` component                    | `Volume` component referencing a `VolumeProfile` asset.       |
| `PostProcessLayer` on the camera                 | Camera → Rendering → Post Processing (toggle) + Volume Mask.  |
| `Bloom`, `Vignette`, etc. as PPv2 settings        | Same names as `VolumeComponent` overrides inside the profile. |

If you find PPv2 in an old project, migrate via Window → Rendering → Render Pipeline Converter.

## Rigidbody.velocity → Rigidbody.linearVelocity (Unity 6)

`Rigidbody.velocity` is obsolete in Unity 6 to disambiguate from angular velocity. Same in 2D.

| Legacy                              | Use instead                                |
|-------------------------------------|--------------------------------------------|
| `_rb.velocity = v;`                 | `_rb.linearVelocity = v;`                  |
| `_rb2d.velocity = v2;`              | `_rb2d.linearVelocity = v2;`               |

`angularVelocity` was already disambiguated, no rename needed.

## Cinemachine 2 → Cinemachine 3 (Unity 6)

Cinemachine 3 ships with Unity 6 and is a top-to-bottom rename. The Cinemachine Upgrader (Window → Cinemachine → Upgrade) handles asset/prefab migration; **scripts referencing old types must be updated by hand.**

| Cinemachine 2.x                              | Cinemachine 3.x (Unity.Cinemachine)              |
|----------------------------------------------|--------------------------------------------------|
| `using Cinemachine;`                         | `using Unity.Cinemachine;`                       |
| `CinemachineVirtualCamera`                   | `CinemachineCamera`                              |
| `CinemachineFreeLook`                        | `CinemachineCamera` + `CinemachineOrbitalFollow` |
| `CinemachineTransposer`                      | `CinemachineFollow`                              |
| `CinemachineFramingTransposer`               | `CinemachinePositionComposer`                    |
| `CinemachineComposer`                        | `CinemachineRotationComposer`                    |
| `CinemachinePOV`                             | `CinemachinePanTilt`                             |
| `CinemachineCollider`                        | `CinemachineDeoccluder`                          |
| `Cinemachine3rdPersonFollow`                 | `CinemachineThirdPersonFollow`                   |
| `CinemachineConfiner`                        | `CinemachineConfiner2D` / `CinemachineConfiner3D` |
| `m_Lens`, `m_Priority`, `m_Follow`, ...       | `Lens`, `Priority`, `Follow`, ... (no `m_`)      |
| `CinemachineCore.Instance.GetActiveBrain()`  | `CinemachineBrain.GetActiveBrain(...)` (static)  |

See `references/animation-and-cinemachine.md` for the full Cinemachine 3 setup.

## Older deprecations still worth knowing

- **`Resources.Load<T>(...)`** — not deprecated, but discouraged for new code. Resources gets included in builds whole and prevents tree-shaking of unused assets. Use **Addressables** for runtime asset loading in new projects.
- **`WWW`** — long obsolete. Use `UnityWebRequest`.
- **`AudioSource.minDistance` / `maxDistance` via the inspector only** — still works, but for dynamic mixing prefer the **Audio Mixer**.
- **`Animation`** (legacy component) — superseded by `Animator` / Mecanim. Don't add `Animation` to new objects.
- **`OnGUI` for game UI** — `OnGUI` is for editor tooling, not gameplay UI. Use UGUI or UI Toolkit.

## ECS — moved into the engine in 6.4

The Entities, Collections, Mathematics, and Entities Graphics packages now ship as Core packages in 6.4 — no separate Package Manager install needed. If you're upgrading an ECS project, remove the explicit entries from `Packages/manifest.json` for those four packages and let the engine version provide them.

## How to find what's deprecated in your project

- Look at the **Console** with "Clear on Recompile" off. Obsolete-API warnings show up after a clean compile.
- Run **Project Auditor** (Window → Analysis → Project Auditor in 6.4) — Code section flags obsolete API usage.
- For URP specifically: the Render Pipeline Converter (Window → Rendering → Render Pipeline Converter) handles legacy → URP conversions and flags incompatible material settings.
