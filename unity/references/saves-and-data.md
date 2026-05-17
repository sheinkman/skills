# Saves and data persistence

Load this reference when designing how the game persists state — player progress, settings, inventory, level data. Get the architecture right early; save format migrations after launch are painful.

## Where saves live

Use `Application.persistentDataPath`. It's writable on every platform Unity ships to:

| Platform        | Resolves to                                                                 |
|-----------------|------------------------------------------------------------------------------|
| Windows         | `%USERPROFILE%\AppData\LocalLow\<CompanyName>\<ProductName>\`               |
| macOS           | `~/Library/Application Support/<CompanyName>/<ProductName>/`                |
| Linux           | `~/.config/unity3d/<CompanyName>/<ProductName>/`                            |
| iOS             | App's Documents directory (cleared on uninstall, backed up by iCloud)        |
| Android         | `/storage/emulated/0/Android/data/<package>/files/` (or app-private storage) |
| WebGL           | IndexedDB (browser-managed, sync via `Application.ExternalCall` flush)       |

CompanyName and ProductName come from Project Settings → Player. Set them early — changing them later moves the save folder, orphaning existing saves.

**Never use `Application.dataPath` for writes.** That's the install/build location and is read-only on most platforms.

## Three persistence tiers

Pick by use case:

1. **`PlayerPrefs`** — key-value store for small settings (audio volume, last selected character). Survives reinstalls on some platforms; on others it doesn't. Don't use it for save data.
2. **File-based JSON** — proper save data. Strongly typed via `JsonUtility` or `Newtonsoft.Json`.
3. **Cloud / server** — multiplayer state, anti-cheat-relevant data. Out of scope here; uses your backend (Unity Cloud Save, Steam Cloud, custom REST).

## PlayerPrefs — for settings, not saves

```csharp
PlayerPrefs.SetFloat("MasterVolume", 0.8f);
PlayerPrefs.SetInt("Difficulty", 2);
PlayerPrefs.SetString("LastCharacter", "Knight");
PlayerPrefs.Save();   // forces a flush; Unity also flushes on app quit

var vol = PlayerPrefs.GetFloat("MasterVolume", 1f);  // default if missing
```

Limits:
- Stored unencrypted in plaintext (Windows registry, macOS plist, Android XML). A user with five minutes can edit anything.
- No transactional guarantees — partial writes are possible on a crash.
- WebGL stores in IndexedDB with size limits.

Use it for: graphics settings, audio mix, "have we shown the tutorial".
Don't use it for: anything you'd be mad to lose, anything game-design-relevant.

## JsonUtility — built in, fast, limited

`UnityEngine.JsonUtility` serializes Unity-style serialized fields (the same rules as inspector serialization: `[Serializable]` classes, `[SerializeField]` private fields, public fields). Fast and zero-dependency.

```csharp
[System.Serializable]
public class SaveData
{
    public int saveVersion = 1;
    public string playerName;
    public int level;
    public Vector3 lastPosition;
    public List<string> unlockedAbilities = new();
}

public static class SaveSystem
{
    static string Path => System.IO.Path.Combine(
        Application.persistentDataPath, "save.json");

    public static void Save(SaveData data)
    {
        var json = JsonUtility.ToJson(data, prettyPrint: true);
        System.IO.File.WriteAllText(Path, json);
    }

    public static SaveData Load()
    {
        if (!System.IO.File.Exists(Path)) return null;
        var json = System.IO.File.ReadAllText(Path);
        return JsonUtility.FromJson<SaveData>(json);
    }
}
```

Limits of `JsonUtility`:
- **No `Dictionary<K,V>`.** Same as Unity's serializer — use `List<Pair>` or hand-build dicts at runtime.
- **No polymorphism.** A field of type `Item` serializes only `Item` fields, even if the runtime value is a `Sword`. (Unity's `[SerializeReference]` doesn't help with `JsonUtility` either.)
- **No top-level collections.** `JsonUtility.ToJson(myList)` returns `{}`. Wrap in a class.
- **No nullables.** Default values appear instead.
- **No custom converters.** What you see is what you get.

These limits are why most non-trivial saves end up on Newtonsoft.Json.

## Newtonsoft.Json — for non-trivial saves

Unity ships `com.unity.nuget.newtonsoft-json` as an official package. Add it via Package Manager → "+" → "Add package by name" → `com.unity.nuget.newtonsoft-json`.

```csharp
using Newtonsoft.Json;

public class SaveData
{
    public int SaveVersion = 1;
    public string PlayerName;
    public int Level;
    public Dictionary<string, int> Inventory = new();   // works!
    public List<QuestProgress> Quests = new();
}

public static class JsonSaveSystem
{
    static readonly JsonSerializerSettings s_Settings = new()
    {
        Formatting = Formatting.Indented,
        TypeNameHandling = TypeNameHandling.Auto,  // for polymorphism
        NullValueHandling = NullValueHandling.Ignore,
    };

    public static void Save(SaveData data, string path)
        => System.IO.File.WriteAllText(path,
            JsonConvert.SerializeObject(data, s_Settings));

    public static SaveData Load(string path)
        => JsonConvert.DeserializeObject<SaveData>(
            System.IO.File.ReadAllText(path), s_Settings);
}
```

Newtonsoft gives you dictionaries, polymorphism (`TypeNameHandling.Auto`), custom converters, attribute control. Cost: an extra package dependency and slower than JsonUtility on huge saves.

**Polymorphism warning:** `TypeNameHandling` writes assembly-qualified type names into the JSON. If you rename the class or move it to another namespace, old saves don't load. Use `[JsonObject]` and a serialization binder for control, or use a tagged discriminator field of your own (e.g., `"type": "Sword"`) and a custom converter.

## Atomic writes — don't corrupt saves on crash

A naive `WriteAllText` truncates the file, then writes new contents. A crash mid-write leaves a truncated file. Atomic write pattern:

```csharp
public static void SaveAtomic(string path, string contents)
{
    var tmp = path + ".tmp";
    System.IO.File.WriteAllText(tmp, contents);

    // File.Replace handles the rename + overwrite atomically on most filesystems.
    if (System.IO.File.Exists(path))
        System.IO.File.Replace(tmp, path, path + ".bak");
    else
        System.IO.File.Move(tmp, path);
}
```

This guarantees that either the old save or the complete new save is present — never a half-written one. The `.bak` gives you one extra layer of recovery.

For mobile platforms where power loss mid-write is realistic, this pattern is essential. For desktop, still recommended.

## Save versioning

The single best thing you can do for a save system is **always include a version field and write migrations from day one.** When the save schema changes, old saves still load.

```csharp
public class SaveData
{
    public int SaveVersion = 4;  // bump when schema changes
    /* ... fields ... */
}

public static class SaveMigrations
{
    public static SaveData Migrate(string json)
    {
        // Read just the version first.
        var probe = JsonUtility.FromJson<VersionProbe>(json);
        int v = probe.SaveVersion;

        if (v == 1) json = MigrateV1ToV2(json);
        if (v <= 2) json = MigrateV2ToV3(json);
        if (v <= 3) json = MigrateV3ToV4(json);

        return JsonConvert.DeserializeObject<SaveData>(json);
    }

    static string MigrateV1ToV2(string json) { /* manipulate JObject, return new json */ }
    // ...

    [System.Serializable]
    class VersionProbe { public int SaveVersion; }
}
```

Migrate by reading the JSON as a generic `JObject` (Newtonsoft), modifying it, then deserializing into the new strong type. Keep the migrations as pure functions; test them with sample old saves.

Pure additive changes (a new optional field) don't need a migration — the field just defaults. Changes that rename, remove, or restructure data do.

## What to put in saves

A useful separation:

- **Persistent player state** — level progress, inventory, abilities, completed quests. Save it.
- **Transient state** — current scene contents, enemy positions, animation states. Don't save unless the design demands it (autosave during combat is a special case). For checkpoint-based games, the save is just "where the checkpoint is + player data" — recreate the scene from the level config.
- **Tunables** — enemy stats, weapon definitions. Ship as ScriptableObject assets, never in saves. Players shouldn't be able to edit them; designers should be able to tweak them without breaking saves.

The fewer things you save, the fewer migrations you write.

## Settings vs game saves

Keep them separate files:
- `settings.json` — audio, graphics, control bindings. Survives game-save deletion.
- `save_<slot>.json` — game progress, multiple slots if applicable.
- `profile.json` — player name, currency that crosses saves (if you have meta-progression).

A single mega-save file is tempting and a future-pain trap. The cost of three files vs one is zero.

## Encryption and tamper-resistance

For local single-player saves, **don't bother with encryption.** Determined players will always crack it; honest players won't try; the only victims are players who got locked out of their own save by a save corruption combined with a hash mismatch.

If the save is meaningful for anti-cheat (leaderboards, online play), validate on the server. Client-side encryption of a save file does ~nothing against a player with a hex editor.

A simple checksum is fine to detect *accidental* corruption (truncated writes, disk errors) — store an MD5 of the contents alongside, fail the load gracefully if it doesn't match, fall back to `.bak`.

## Common pitfalls

- **Using `Application.dataPath` for writes.** Read-only on most platforms. Use `persistentDataPath`.
- **Forgetting `PlayerPrefs.Save()` on important values.** Unity flushes on quit but not on crash. Call it after important writes.
- **Saving raw `MonoBehaviour` references.** A `GameObject` reference in JSON serializes its name or fails entirely — not the object. Serialize ID strings instead, look up on load.
- **Saving `Vector3` / `Quaternion` types with `JsonUtility`** — works fine. With Newtonsoft, you need a converter or you'll get four nested floats with annoying property names. Use `JsonUtility` for those or write a one-line converter.
- **No save versioning.** Future-you will hate present-you. Always start with `SaveVersion = 1`.
- **Polymorphic saves without a stable type discriminator.** Renaming a class breaks every save. Use string discriminators you control (`"type": "Sword"`) and a switch in the deserializer, not `TypeNameHandling` with assembly-qualified names.
- **Saves in `Resources/` or `StreamingAssets/`.** Those are read-only build artifacts. Saves go in `persistentDataPath`.
