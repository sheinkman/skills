# Performance

Load this reference when investigating performance issues, working in a GC-sensitive hot path, or doing a performance pass on a Unity 6.4 + URP project. The order here matches a reasonable workflow: profile first, then look at specific categories.

## Profile before changing anything

The single most common performance mistake is optimizing the wrong thing. **Always profile first**, and profile on the target device, not just in the editor.

### Profiler basics

Window → Analysis → Profiler. Things to know:

- The first few frames after entering Play Mode are not representative — they include scene load, AOT warmup, and one-off allocations. Look at steady-state frames.
- **Deep Profile** captures every C# method call but slows execution dramatically — use it for finding allocations and call tree shape, never for absolute timings.
- Use **Profiler markers** (`using (new ProfilerMarker("MySystem").Auto())`) to label your own code. Custom markers show up in the CPU module and make hot paths searchable.
- Attach the profiler to a running build on the target device (Editor → Profiler → connection dropdown) for real numbers. Editor numbers are roughly 2-3× slower than build numbers on the same machine; relative comparisons are valid, absolute numbers are not.

### Frame Debugger

Window → Analysis → Frame Debugger. Captures one frame's draw calls in order, lets you step through. Use it for:

- Confirming what's actually being drawn (the answer is often more than you think).
- Diagnosing batching: identical materials that aren't batching, hidden shader variants, etc.
- Inspecting render targets at each pass — useful for custom render graph passes that aren't producing the expected output.

### Project Auditor (built into 6.4)

Window → Analysis → Project Auditor (now an editor module in 6.4, no separate package install). Scans the project for:

- Shaders that won't strip and will bloat builds.
- Settings that hurt performance (texture import settings, audio compression).
- Code patterns that allocate (`Camera.main` per frame, `string.Format` in `Update`, etc.).

Run it before any major build. The reports are noisy at first — work through high-severity items first, mark the rest as known/ignored.

## GC allocations — the most common villain

Per-frame allocations cause GC spikes that show up as frame hitches. The Unity GC is non-generational and stops the world; even 1 KB allocated per frame can add up to a noticeable freeze every few seconds.

### How to find allocations

1. Open Profiler → CPU Usage module, find a representative frame.
2. Switch view to **GC Alloc** column.
3. Sort descending. Anything > 0 B per frame in `Update`-equivalent code is suspect.

### Common allocation sources

- **`new` of any reference type in `Update`** — `new List<T>()`, `new Vector3[...]`, `new StringBuilder()`. Pre-allocate fields, clear/reuse them.
- **`string` concatenation and `string.Format`** — `"Score: " + score` allocates. Use a cached `StringBuilder` or text-mesh-style number formatting.
- **LINQ in hot paths** — `.Where(...).ToList()` allocates on every call. Replace with manual loops.
- **Closures capturing locals** — `() => DoThing(x)` allocates a delegate + closure. Pre-build the delegate and cache.
- **Boxing** — passing a struct where an `object` is expected (string formatting, dictionaries keyed on enums in older .NET). Use generic overloads or value-type-aware containers.
- **`tag` comparisons** — `gameObject.tag == "Enemy"` allocates a string accessor. Use `gameObject.CompareTag("Enemy")` (no alloc).
- **`GetComponent` returning array** — `GetComponents<T>()` allocates a new array. Use the overload that takes a `List<T>` and reuses it.
- **`foreach` over some collection types** in older Unity versions — modern .NET Standard 2.1 handles most cases without boxing, but still verify on the target with the profiler.
- **String-based animator parameters** — every call to `animator.SetTrigger("Jump")` looks up the string. Use `Animator.StringToHash("Jump")` once, cache the int, call `SetTrigger(_jumpHash)`.

### `Object.Instantiate` and `Destroy`

Instantiating prefabs allocates the GameObject, all its components, and any data they hold. `Destroy` queues for the GC. Both are slow at scale.

**Pool anything spawned/despawned more than a handful of times per second:** bullets, hit effects, enemies in a wave-based game. A simple pool:

```csharp
public class Pool<T> where T : Component
{
    readonly T _prefab;
    readonly Transform _parent;
    readonly Stack<T> _free = new();

    public Pool(T prefab, Transform parent, int prewarm = 0)
    {
        _prefab = prefab;
        _parent = parent;
        for (int i = 0; i < prewarm; i++) Release(Instantiate());
    }

    T Instantiate() => Object.Instantiate(_prefab, _parent);

    public T Get()
    {
        var item = _free.Count > 0 ? _free.Pop() : Instantiate();
        item.gameObject.SetActive(true);
        return item;
    }

    public void Release(T item)
    {
        item.gameObject.SetActive(false);
        _free.Push(item);
    }
}
```

Unity also ships `UnityEngine.Pool.ObjectPool<T>` and `CollectionPool<T>` in the runtime — use them for non-Component types (lists, dictionaries, hash sets).

## Draw calls and batching

The CPU cost of submitting a draw call is non-trivial — getting from thousands of draws to hundreds is usually a meaningful win.

### What batches in URP

- **SRP Batcher**: groups draws by shader variant. Materials sharing the same shader (even with different parameters) batch together if the shader is SRP Batcher-compatible (per-material data in a `CBUFFER_START(UnityPerMaterial)` block).
- **Static batching**: combines static meshes sharing the same material into one big mesh at build time. Mark renderers as Static (top of inspector). Increases build size; doesn't help with shadows or instances that move.
- **Dynamic batching**: combines small dynamic meshes sharing material at runtime. Limited to small meshes; SRP Batcher usually beats it.
- **GPU Instancing**: identical mesh + material rendered many times (`Graphics.RenderMeshInstanced`). Different per-instance data via `MaterialPropertyBlock` or instanced properties.

### GPU Resident Drawer (URP 6.0+)

In URP Asset → Rendering → GPU Resident Drawer = "Instanced Drawing" enables a system that hoists draw-call generation to the GPU via BatchRendererGroup. Big wins on scenes with many static meshes; works with both static and dynamic mesh renderers tagged for the system. Note: not compatible with every shader feature (per-renderer overrides on legacy material properties may fall back). Profile before and after to confirm gains.

### How to investigate draws

- **Stats overlay** in the Game view (top-right of viewport, "Stats" toggle): shows draw call count, set-pass calls, triangles, vertices.
- **Frame Debugger**: see every draw, grouped if batched. The "Batch breaking" tooltip explains why a batch ended — different material, different keywords, etc. Most batching issues live here.

## Render-side bottlenecks

- **Overdraw**: pixels being shaded by multiple transparent or alpha-blended objects. Scene view → Draw Mode → Overdraw shows it visually. Particles are the usual culprit. Fix: use opaque or alpha-test where possible, reduce particle count or size, use simpler shaders for particles.
- **Shadow casters**: each cascade is a render of the scene from the light's POV. Cull what doesn't need shadows (Mesh Renderer → Cast Shadows = Off). Reduce shadow distance.
- **Post-processing**: each Volume override adds passes. Bloom is the heaviest common one. Disable individual overrides per quality level.
- **Texture sampling**: streaming + texture compression matter. Use **Mipmap Streaming** to keep VRAM in check on large worlds. Compress with ASTC on mobile, BC7 on desktop, BC1 if you can tolerate the artifacts.

## Burst, Job System, ECS — when

The Job System lets you parallelize work across cores. **Burst** is an AOT compiler that turns C# job code into highly optimized SIMD native code — often 10×+ faster than the equivalent managed code.

When to reach for them:

- Per-frame work over thousands of items (particles, agents, voxels, procedural generation).
- Math-heavy code with no managed dependencies.
- Anything you can express purely in terms of `NativeArray`, `Native*` containers, and `float`/`int` math.

When **not** to:

- Code that touches the Unity main-thread API (`transform.position` writes, `GetComponent`, etc.) — jobs can't.
- Code that's not actually a hot path on the profiler.
- Code that mutates managed reference types — Burst won't compile it.

In 6.4, Burst gained multithreading support on the Web platform too — worth knowing if you ship to WebGL.

## DirectStorage (Windows Standalone, 6.4+)

Unity 6.4 added support for Microsoft DirectStorage on Windows Standalone, enabled in Player Settings → "Enable Direct Storage". It speeds up loading of textures, meshes, and (in DOTS projects) entities asset data by bypassing CPU staging buffers and streaming directly from NVMe SSDs to the GPU.

Currently:
- It's used automatically for the listed asset types — you don't need to change your loading code.
- It doesn't yet handle compression/decompression — that's coming.
- Biggest wins on machines with NVMe SSDs and large asset loads (level loads, streaming worlds).

If you target Windows desktop and load lots of asset data, flip the toggle and remeasure load times.

## Mobile / WebGL specifics in brief

- **Mobile**: prefer Forward (not Forward+) on low-end devices if you have many lights but each object only needs 1-2. Use ASTC textures, audio in Vorbis at 22 kHz mono for SFX. Cap framerate to 60 (or 30 for battery) via `Application.targetFrameRate`. Watch garbage like a hawk — GC spikes on mobile show up as visible stutters.
- **WebGL**: builds are large; use Brotli compression on the server. Avoid threading-dependent code unless you've tested the SharedArrayBuffer/cross-origin-isolation setup; with Unity 6.4's Burst-on-Web you can multithread Burst jobs if the host serves the right headers. Audio latency is worse on web than native — design around it.

## A general optimization checklist

Run through this once per project, then again before milestones:

1. Build a representative scene, profile a steady-state frame on the target device.
2. Top CPU consumer per frame? (often: physics, rendering, scripts — in that order, but verify)
3. Any GC allocations per frame in `Update`-equivalent code? Fix the largest first.
4. Draw call count + Frame Debugger pass: anything obviously unbatched?
5. Overdraw view: any window of bright red?
6. Shadow draw count: any unnecessary casters?
7. Texture memory: anything way too large for its on-screen size?
8. Build with Development Build + Autoconnect Profiler and re-profile, the editor's numbers lie.
