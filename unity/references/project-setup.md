# Project setup (new Unity 6.4 + URP project)

Load this reference when scaffolding a new Unity 6.4 + URP project, or when the project layout, `.asmdef` strategy, `.gitignore`, or editor settings need to be set up from scratch.

## Folder layout under `Assets/`

- **`_Project/`** (underscore sorts to top of the project window) — your code and data:
  - `Scripts/` — organize by feature (`Player/`, `Enemies/`, `UI/`), not by type (avoid `Managers/`, `Helpers/`).
  - `Prefabs/`
  - `ScriptableObjects/` or `Data/`
  - `Scenes/`
  - `Art/`, `Audio/`, etc. as needed.
- **`ThirdParty/`** or **`Plugins/`** for vendor code, kept separate so it's easy to update.

Don't put scripts at the root of `Assets/` — they fall into the default `Assembly-CSharp` if there's no `.asmdef` nearby.

## Assembly definitions

At minimum, create:

- `_Project/Scripts/<Game>.Runtime.asmdef`
- `_Project/Scripts/Editor/<Game>.Editor.asmdef` (`includePlatforms: Editor` only, references the Runtime one)

Add per-feature `.asmdef`s as the project grows — they speed up compile times dramatically. The boundary is usually one asmdef per `Scripts/<Feature>/`.

Editor-only code (custom inspectors, `EditorWindow`s, build hooks) must live behind an Editor-only `.asmdef` or under an `Editor/` folder, or it won't compile in a player build. See `editor-tooling.md`.

## Standard packages

Install via Package Manager (`Window → Package Manager → +`):

- **Input System** — and set Project Settings → Player → Active Input Handling = "Input System Package" (or "Both" during a migration).
- **Cinemachine** for cameras — note this is Cinemachine 3 in Unity 6.x; see `animation-and-cinemachine.md` for the 2.x → 3 renames.
- **TextMeshPro** is built in but the essentials must be imported once: Window → TextMeshPro → Import TMP Essential Resources.
- **Addressables** if you need streaming, DLC, or hot-reload of content; see `addressables.md`.
- **Test Framework** if you want unit tests; configure via Window → General → Test Runner. See `testing-and-debugging.md`.

In 6.4 the **Entities, Collections, Mathematics, and Entities Graphics** packages ship as Core — already there if you need ECS.

## `.gitignore`

Start from GitHub's official Unity `.gitignore` template.

**Ignore:**

- `Library/`, `Temp/`, `Logs/`, `Build/`, `MemoryCaptures/`
- `*.csproj`, `*.sln` (regenerated from `.asmdef`s)
- `UserSettings/` (per-user editor state)

**Do not ignore:**

- `Packages/manifest.json`, `Packages/packages-lock.json` (the package manifest — required for reproducible installs)
- `ProjectSettings/` (quality settings, input axes, layers, tags, etc.)
- `.meta` files anywhere — these are the asset GUIDs; losing them silently breaks every prefab and scene reference.

## Editor settings (set once)

- Project Settings → Editor → **Asset Serialization** = "Force Text" — makes assets diff-friendly and mergeable.
- Project Settings → Editor → **Version Control** = "Visible Meta Files" — ensures `.meta` files show up for VCS.
- Project Settings → Player → **API Compatibility Level** = ".NET Standard 2.1" — the modern default for new projects.

## First build settings pass

Open **Build Profiles** (Unity 6's replacement for the old Build Settings window), set the target platform, and add every scene that should ship to the active scene list. A surprising number of "it works in editor but not in build" bugs trace back to a scene missing from this list.

For shipping configuration (IL2CPP vs Mono, scripting defines, code stripping, platform-specific code), see `build-and-platforms.md`.

## See also

- `build-and-platforms.md` — Build Profiles, IL2CPP, shipping checklist.
- `editor-tooling.md` — custom inspectors, build hooks, asset post-processors.
- `addressables.md` — when to add Addressables to a project.
- `testing-and-debugging.md` — test framework setup.
