# Addressables

Load this reference when designing the asset loading and content strategy. For a small team shipping a roguelike-scale game on Steam, Addressables is the right answer the moment your loose-load asset budget exceeds ~50 MB or you want content that can be patched/downloaded post-ship.

## Why Addressables

The three options for loading assets at runtime in Unity:

| Approach          | Cost                                                         | When to use                                              |
|-------------------|--------------------------------------------------------------|----------------------------------------------------------|
| **Direct references** (`[SerializeField] GameObject _prefab`) | Loaded with the scene/prefab that references them; always in memory while that scene is loaded. | Anything tightly coupled to a specific scene or prefab. |
| **`Resources.Load`** | Everything in `Resources/` ships in the build, in one big asset bundle, **always**. Can't tree-shake. | Don't use for new code. Listed for completeness — and so you can recognize and migrate it. |
| **Addressables**     | Lazy-loaded, ref-counted, can be patched post-ship, supports remote content. Comes with build pipeline complexity. | Anything that's optional or content-bag-shaped: enemy variants, levels, weapons, audio cues, language packs. |

For an isometric RPG with many enemy types, item icons, weapon sprites, level chunks — Addressables is the default. Small games (game jam scope) can skip it.

## Setup

1. Install via Package Manager: **Addressables** (`com.unity.addressables`).
2. Window → Asset Management → Addressables → Groups. Click "Create Addressables Settings" if first time.
3. The Groups window shows asset groups (default groups: `Built In Data`, `Default Local Group`).

To make an asset addressable, check the **Addressable** checkbox in its inspector. An address is assigned (defaults to the asset path; rename it to something stable like `enemies/skeleton`).

## Loading addressables in code

Async, returns an `AsyncOperationHandle<T>`:

```csharp
using UnityEngine.AddressableAssets;
using UnityEngine.ResourceManagement.AsyncOperations;

public class EnemySpawner : MonoBehaviour
{
    [SerializeField] AssetReferenceGameObject _enemyRef;

    async Awaitable<GameObject> SpawnEnemy(Vector3 position)
    {
        var handle = _enemyRef.LoadAssetAsync<GameObject>();
        await handle.Task;   // or yield in a coroutine

        if (handle.Status != AsyncOperationStatus.Succeeded)
        {
            Debug.LogError($"Failed to load {_enemyRef}");
            return null;
        }

        var instance = Instantiate(handle.Result, position, Quaternion.identity);
        // Release the handle when we're done with all instances — usually on scene unload.
        // For now, hold the handle until we Release().
        return instance;
    }
}
```

Two reference types:

- **`AssetReference`** / **`AssetReferenceT<T>`** — typed handle authored in the inspector. Drag the asset to assign. Cleanest pattern; gives compile-time type safety on `_enemyRef.LoadAssetAsync<GameObject>()`.
- **String address** — `Addressables.LoadAssetAsync<GameObject>("enemies/skeleton")`. Works but loses type safety; typos fail at runtime.

Always prefer `AssetReference` for things known at edit time. Reserve string addresses for genuinely data-driven loads (e.g., a save file says `"weapon_iron_sword"`).

## Instantiation shortcut

`Addressables.InstantiateAsync(...)` loads-and-instantiates in one call, and the handle owns both:

```csharp
var handle = _enemyRef.InstantiateAsync(position, Quaternion.identity);
await handle.Task;
var enemyInstance = handle.Result;

// Later, to despawn (releases the asset too if it's the last instance):
Addressables.ReleaseInstance(enemyInstance);
```

For frequently-spawned objects (bullets, hit effects), pre-load the asset once and then `Instantiate` the cached `GameObject` directly — `InstantiateAsync` per shot is unnecessary overhead.

## Reference counting — the part most people get wrong

Every `LoadAssetAsync` / `InstantiateAsync` **increments** an internal ref count. Every `Release(handle)` or `ReleaseInstance(go)` **decrements** it. When the count hits zero, the asset (and its bundle) is unloaded.

**You must release.** Otherwise:
- Memory grows forever.
- The asset bundle stays mapped; switching scenes doesn't free it.

Common safe pattern:

```csharp
public class AddressablePrefab<T> where T : Object
{
    AsyncOperationHandle<T> _handle;
    public T Asset => _handle.IsValid() ? _handle.Result : null;

    public async Awaitable Load(AssetReferenceT<T> reference)
    {
        _handle = reference.LoadAssetAsync<T>();
        await _handle.Task;
    }

    public void Release()
    {
        if (_handle.IsValid()) Addressables.Release(_handle);
    }
}
```

Hold the handle for the life of the system that uses the asset. Release in `OnDestroy` or when changing levels. **Don't release while you still hold instantiated GameObjects** — the asset will unload while they're alive (visible as missing references after a few seconds).

## Groups, labels, and bundles

In the Addressables Groups window:

- **Group** — a logical bundle. Default schema: each group builds to one `.bundle` file. Right-click a group → Schema → Content Packing & Loading to inspect/edit.
- **Label** — a tag on an asset. One asset can have many labels (`"enemy"`, `"forest_biome"`, `"hard_difficulty"`).
- **Address** — the lookup key.

Useful patterns:

- **Group by load timing**: "Always Loaded" (UI atlases, fonts), "Per Biome" (enemies + props), "Per Level" (specific scene assets).
- **Labels for queries**: load all assets labeled `"forest_biome"` when the forest level starts:
  ```csharp
  var handle = Addressables.LoadAssetsAsync<GameObject>("forest_biome", null);
  await handle.Task;
  foreach (var go in handle.Result) { /* register, instantiate, etc. */ }
  ```
- **Bundle granularity**: too few large bundles → long load times, can't unload partial content. Too many small bundles → bundle-overhead bloat. ~5-50 MB per bundle is a good target.

## Build profiles

Addressables has its own build profile system (separate from Unity 6 Build Profiles, confusingly):

- **Default Local Build Path** — `[BuildTarget]/StreamingAssets/aa` by default. Files built here ship with the player.
- **Default Remote Build Path** — for content you'll host on a server (CDN, S3). Files are downloaded at runtime.

For a small Steam game, **all-local** is the simplest and recommended starting point. Remote opens up patching without a full Steam build, but adds backend infrastructure complexity. Don't reach for it until you have a reason.

## Content updates (post-ship patching)

The pitch: ship the base game, push content updates via your CDN without a full re-release. Useful for Steam (lets you push small content updates without re-downloading 5 GB) and mandatory for live-service games.

Workflow:
1. Build a player build (snapshot the addressables state).
2. To patch later, "Update a Previous Build" in the Addressables window — only changed assets repack.
3. Players' game downloads the updated catalog at startup, fetches changed bundles.

For a small Steam game, this is often unnecessary — Steam's own delta updates handle binary diffing. Skip the remote pipeline.

## Synchronous APIs — when you must

Most Addressables APIs are async. There's a synchronous escape hatch: `handle.WaitForCompletion()` blocks until the load completes.

```csharp
var prefab = _enemyRef.LoadAssetAsync<GameObject>().WaitForCompletion();
```

**Stalls the main thread.** Hitches are visible to the player. Only use during loading screens or for tiny assets where the load is genuinely instant. The async path is right by default.

## Migration from Resources/

If an existing project leans on `Resources/`:

1. Mark each Resources-loaded asset as Addressable. Address it with its old path (e.g., `Resources/UI/Cursor.png` → address `UI/Cursor`).
2. Find every `Resources.Load<T>("UI/Cursor")` and replace with `Addressables.LoadAssetAsync<T>("UI/Cursor")`, accepting the async signature change.
3. Move the asset out of any `Resources/` folder so it stops getting bulk-bundled.

Do it module-by-module. The middle state (some Resources, some Addressables) works fine.

## Catalog and runtime cost

At startup, Addressables loads a small catalog file listing every addressable asset. For a project with 10,000 addressables, the catalog is ~1 MB — fine. For very large projects (50,000+), shard the catalog by group.

Runtime overhead per `LoadAsync` is minimal — the bottleneck is the actual disk read, not the API. For sub-frame loads of small assets, the async machinery is a tiny constant added on top.

## Common pitfalls

- **Forgetting to Release.** Memory leaks; assets stay loaded across scene changes. Always pair `Load` with `Release`, `Instantiate` with `ReleaseInstance`.
- **Releasing while instances are alive.** "My prefab has missing scripts" after some delay — the asset unloaded while a child of the live instance still references it. Hold the handle until *all* instances are gone.
- **Loading the same asset N times via `LoadAssetAsync`.** Each call ref-counts; you need N releases. Often you want a single load + cached result.
- **`AssetReference` not assigned.** Inspector shows "None". The runtime call returns a failed handle. Check `handle.Status` before using `handle.Result`.
- **Bundles too coarse-grained.** One 2 GB bundle blocks load for everything inside it. Split by load timing.
- **Bundles too fine-grained.** 5,000 tiny bundles each with one asset — each load is an I/O hit. Aggregate related assets.
- **Forgetting to rebuild Addressables before a player build.** Stale bundles ship; new content doesn't appear in builds. Add to the build pipeline (`IPreprocessBuildWithReport`) or check the "Build Addressables on Player Build" toggle.
- **Sync `WaitForCompletion` in `Update`.** Frame hitches. Async or pre-load during loading screens.
- **String-based addresses everywhere.** Typos fail at runtime. Use `AssetReference` where the asset is known at edit time; reserve strings for genuinely dynamic lookups from data.

## When *not* to use Addressables

- Tiny games (game jam, ≤ 100 MB total).
- Prototypes where iteration speed beats correctness.
- Cases where Direct references work (a prefab references its own animator clip; doesn't need to be addressable).

You can mix: some assets direct, some addressable. The whole project doesn't need to convert. Pick the boundary where loading lazily wins (variable content, post-load assets, biome-specific stuff) and leave the always-loaded stuff direct.
