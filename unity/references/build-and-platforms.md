# Build and platforms

Load this reference when configuring builds, adding platform-specific code, debugging "works in editor not in build" issues, or preparing to ship. The mechanics are stable; the pitfalls are universal and small teams hit all of them at least once.

## Build Profiles (Unity 6 replaced Build Settings)

In Unity 6, **File → Build Profiles** replaces the old Build Settings window. Profiles are saved as `.asset` files in the project (commit them; they're shared config, not personal).

Two types:

- **Platform profiles** — one per installed platform (Windows, Mac, Linux, Android, iOS, etc.). Shared settings across all build profiles for that platform.
- **Build profiles** — multiple per platform, for different configurations (e.g., `Windows-Demo`, `Windows-Release`, `Windows-Steam`). Override Player Settings, Graphics Settings, Quality Settings, Scripting Define Symbols, and Asset Import Overrides per profile.

Typical setup for a small team:

```
Assets/Settings/BuildProfiles/
├── Windows-Dev.asset       # Development Build on, Script Debugging on, Profiler autoconnect
├── Windows-Release.asset   # Optimized, Development Build off, IL2CPP
├── Mac-Release.asset
└── Linux-Release.asset
```

Activate a profile, click **Build**. The profile remembers its scenes, defines, and overrides.

### Scripting Define Symbols per profile

Build Profiles let you set scripting defines per-profile. Useful for gating debug features:

```csharp
#if RELEASE_BUILD
    // Strip debug menus, telemetry, etc.
#endif

#if STEAM_BUILD
    SteamAPI.Init();
#endif
```

Per-profile defines beat per-file `#if UNITY_EDITOR` for cross-cutting features. Commit the build profiles so teammates building "Steam" get the same defines you set up.

## Scripting backend — IL2CPP vs Mono

Project Settings → Player → Scripting Backend (or override per build profile).

- **Mono** — JIT-compiled at runtime. Faster builds, easier iteration. Smaller player size on some platforms. Cannot ship to iOS, console platforms, or WebGL — those require IL2CPP.
- **IL2CPP** — AOT-compiles C# to C++ to native. Slower builds (much slower on first build per platform), larger player sizes, **significantly better runtime performance**, smaller memory footprint, **strips unused code**.

Recommended default for a small team shipping to Steam: **Mono for daily dev builds, IL2CPP for release builds**. Set this per build profile.

### Managed code stripping (IL2CPP)

IL2CPP strips types and methods that aren't directly referenced. Anything used via **reflection** (JSON deserialization into a polymorphic type, `Type.GetType("...")`, `Activator.CreateInstance`) is at risk of being stripped.

Two protections:

- **`[Preserve]`** attribute on the type or method:
  ```csharp
  [UnityEngine.Scripting.Preserve]
  public class SwordItem : Item { /* ... */ }
  ```
- **`link.xml`** in your project root:
  ```xml
  <linker>
    <assembly fullname="MyGame">
      <type fullname="MyGame.Items.*" preserve="all"/>
    </assembly>
    <assembly fullname="Newtonsoft.Json" preserve="all"/>
  </linker>
  ```

Test a Development IL2CPP build before shipping. The first time stripping bites you, it's the moment you wish you had.

## API Compatibility Level

Project Settings → Player → API Compatibility Level. Recommended: **.NET Standard 2.1** for new projects (the default in Unity 6). Faster startup, smaller builds, modern API. Pick **.NET Framework** only if a third-party DLL specifically requires it.

## Platform-specific code

Three patterns, in order of preference:

### `#if UNITY_*` conditionals

```csharp
#if UNITY_STANDALONE_WIN
    Application.OpenURL("file://" + path);
#elif UNITY_STANDALONE_OSX
    System.Diagnostics.Process.Start("open", path);
#elif UNITY_STANDALONE_LINUX
    System.Diagnostics.Process.Start("xdg-open", path);
#endif
```

Common symbols: `UNITY_EDITOR`, `UNITY_STANDALONE`, `UNITY_STANDALONE_WIN/OSX/LINUX`, `UNITY_ANDROID`, `UNITY_IOS`, `UNITY_WEBGL`, `UNITY_SERVER`. `UNITY_64` indicates a 64-bit build.

Use `#if` for short branches. For more than a few lines, prefer one of the next two.

### Platform-specific assembly with asmdef

In the `.asmdef` inspector, set **Include Platforms** to specific targets (Windows, macOS, Linux). Code in that assembly only compiles for those platforms. Cleaner than `#if` for large platform-specific subsystems (Steam integration, Switch porting layer, etc.).

### Runtime platform check

```csharp
if (Application.platform == RuntimePlatform.WindowsPlayer) { /* ... */ }
```

Useful when the code must exist on all platforms but behave differently. Doesn't help with stripping — both branches compile. Prefer compile-time checks when possible.

## Build size reduction

For a Steam-bound isometric game, build size isn't usually a blocker, but discipline pays off:

1. **Profile build size** — Window → Analysis → Build Profiler (Unity 6.4 built in). Shows what's taking space.
2. **Texture compression** — ASTC for mobile, BC7 for desktop. Don't ship uncompressed unless you really need the quality.
3. **Audio compression** — Vorbis for everything, Streaming for long clips, low quality for incidental SFX.
4. **Strip unused shader variants** — Project Settings → Graphics → Shader Stripping. Major savings on URP projects.
5. **Mesh compression** — per-import setting. "Low" or "Medium" is usually fine; visually indistinguishable.
6. **Remove the Resources folder** for shipped builds. `Resources/` is included whole; tree-shaking only works for Addressables and direct references. See `references/addressables.md`.
7. **Strip debug symbols** in release builds (Build Profile → Diagnostics).

Default project from Unity 6 + URP + TMP comes in at ~150-250 MB for a small game. If you're well above that, look at textures and audio first.

## Development Build flag

Build Profile → "Development Build" enables:
- Profiler autoconnect (for `Connect to Player` from the editor)
- Debug log overlay (top-left in-game errors)
- Script Debugging (if also enabled)
- Faster builds (less stripping)

**Ship release builds with Development Build OFF.** Players don't need the overlay and the profiler attach surface is a small security exposure.

## Headless / dedicated server builds

For multiplayer (not your case, but worth knowing): Build Profile → Server Build = on. Strips the rendering pipeline, gives you `UNITY_SERVER` define symbol. Half the build size, runs without a GPU.

For single-player isometric, ignore this.

## Performance settings to verify before shipping

Easy to ship wrong; check each release build:

- **Graphics → Lightmap Encoding** = Normal Quality (not High) unless you specifically need HDR lightmaps.
- **Graphics → HDR Cubemap Encoding** — same idea.
- **Quality → V Sync Count** = "Every V Blank" (60 Hz) unless your game has a reason to uncap.
- **Player → Resolution → Run In Background** = on (for desktop; players alt-tab and back).
- **Player → Resolution → Default Is Native Resolution** = on, with a fullscreen mode appropriate to genre. For desktop isometric, Borderless Window is the safe default.
- **Player → Other Settings → Color Space** = Linear (not Gamma). Gamma is a legacy choice; URP looks correct in Linear.
- **Player → Other Settings → Static Batching / Dynamic Batching** = on.
- **Player → Other Settings → Lightmap Streaming** = on, with priority tuned.

## Build pipeline automation

For "build all three platforms with one click", a build script + a CI runner (GitHub Actions, GameCI) is the small-team standard. The minimum pure-Unity version:

```csharp
public static class BuildAll
{
    [MenuItem("Build/All Release")]
    public static void All()
    {
        BuildOne(BuildTarget.StandaloneWindows64, "Build/Windows/Game.exe");
        BuildOne(BuildTarget.StandaloneOSX,       "Build/Mac/Game.app");
        BuildOne(BuildTarget.StandaloneLinux64,   "Build/Linux/Game");
    }

    static void BuildOne(BuildTarget target, string path)
    {
        var opts = new BuildPlayerOptions
        {
            scenes = EditorBuildSettings.scenes
                .Where(s => s.enabled).Select(s => s.path).ToArray(),
            locationPathName = path,
            target = target,
            options = BuildOptions.None,  // Release build.
        };
        var report = BuildPipeline.BuildPlayer(opts);
        if (report.summary.result != BuildResult.Succeeded)
            throw new Exception($"{target} build failed: {report.summary.result}");
    }
}
```

Put this in an editor assembly. For CI, invoke via `unity -batchmode -executeMethod BuildAll.All -quit`.

### `IPreprocessBuildWithReport` for per-build setup

```csharp
public class IncrementBuildNumber : IPreprocessBuildWithReport
{
    public int callbackOrder => 0;
    public void OnPreprocessBuild(BuildReport report)
    {
        PlayerSettings.bundleVersion = ComputeVersion();
    }
}
```

Hooks run for both manual and CI builds.

## Shipping checklist (small team, Steam-bound)

The minimum I'd check before any public release:

1. Release build with IL2CPP, Mono stripping = High, in Release configuration.
2. Test on a clean machine (no Unity installed). Catches "missing C++ runtime" issues.
3. Run with `--force-low-end` and other relevant launch args to verify quality scaling.
4. Audio works with a separate USB headset plugged in / unplugged mid-game.
5. Resolution/windowed/fullscreen toggles correctly and persists in PlayerPrefs.
6. Save/load round-trips on a fresh save and on an existing one (see `references/saves-and-data.md`).
7. Controller and keyboard both work, including pause-menu navigation.
8. Game runs without errors with the Console open in the editor for 30 minutes.
9. Build size is roughly what you expected (Build Profiler shows nothing weird).
10. `Player.log` (or platform equivalent) is free of red errors during a normal play session.

Steam-specific (the absolute minimum): launch via Steam (so Steamworks API initializes), test cloud saves toggle, verify the Steam overlay opens (Shift+Tab).

## Common pitfalls

- **"It works in the editor but not in builds."** Usually: a scene not in the build profile's scene list, a Resources asset that got tree-shaken, IL2CPP stripping a reflection-loaded type, or a `UNITY_EDITOR` guard around code the build needs.
- **First IL2CPP build of the day takes 20 minutes.** Normal. Subsequent builds are much faster. CI caches the IL2CPP cache directory between runs.
- **Code that compiles in editor but not in build.** Editor-only API used outside an editor assembly. The first build catches this; the editor doesn't.
- **`Resources` folder bloat.** Everything in `Resources/` is in the build, even if unreferenced. Move to Addressables (see `references/addressables.md`) once the project has more than ~50 MB of "loaded by string" assets.
- **Hard-coded paths.** `C:\Users\...` in code breaks on other machines. Always use `Application.persistentDataPath` for runtime files, `Application.streamingAssetsPath` for read-only shipped data.
- **Different defines in editor vs build.** `UNITY_EDITOR` is editor-only; "Development Build" is `DEVELOPMENT_BUILD`. They're not the same — code under one isn't necessarily under the other.
- **Missing visual C++ runtime on Windows.** Unity now bundles it via the installer, but verify on a clean test machine.
- **macOS notarization** — required for distributing outside the Mac App Store. Notarize the `.app` with Apple before shipping. Unity Cloud Build can handle this; manual is one command (`xcrun notarytool`) plus an Apple Developer account.
- **Linux desktop entry / icon.** Unity doesn't generate a `.desktop` file. Ship one alongside the build or expect the user to make their own.
