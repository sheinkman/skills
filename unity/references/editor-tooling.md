# Editor tooling

Load this reference when writing tools that live in the Unity Editor — custom inspectors, property drawers, asset post-processors, build hooks, or standalone editor windows. The patterns here apply equally to gameplay-team conveniences and full-fledged level/data editors.

## The cardinal rule

**Editor code goes in an Editor assembly.** That means either a folder literally named `Editor` (anywhere in `Assets/`), or an `.asmdef` with `includePlatforms` set to `Editor` only. Anything that references `UnityEditor.*` outside an editor assembly breaks the player build.

A clean structure:

```
Assets/_Project/Scripts/
├── Runtime/
│   ├── Player.cs
│   └── <Game>.Runtime.asmdef     # platforms: any
└── Editor/
    ├── PlayerEditor.cs
    └── <Game>.Editor.asmdef      # platforms: Editor; references <Game>.Runtime
```

The editor asmdef references the runtime asmdef. The reverse is forbidden — runtime code cannot reference editor code (it wouldn't exist in a build).

## Custom inspectors — UI Toolkit first in 6.4

Two ways to author an inspector: UI Toolkit (modern, preferred for new code) and IMGUI (legacy, still works). UI Toolkit is what Unity itself ships for new inspectors and what you'll find in the engine's own tools.

### UI Toolkit inspector

Subclass `Editor`, mark with `[CustomEditor(typeof(YourComponent))]`, override `CreateInspectorGUI()`:

```csharp
using UnityEngine;
using UnityEditor;
using UnityEditor.UIElements;
using UnityEngine.UIElements;

[CustomEditor(typeof(Health))]
public class HealthEditor : Editor
{
    public override VisualElement CreateInspectorGUI()
    {
        var root = new VisualElement();

        var maxField = new PropertyField(serializedObject.FindProperty("_max"));
        root.Add(maxField);

        var currentLabel = new Label();
        root.Add(currentLabel);

        // Update at runtime when playing.
        root.schedule.Execute(() =>
        {
            var h = (Health)target;
            currentLabel.text = $"Current: {h.Current:0.0} / {h.Max:0.0}";
        }).Every(100);

        return root;
    }
}
```

For more complex layouts, author the structure in a `.uxml` file and styling in `.uss`, then load with:

```csharp
public override VisualElement CreateInspectorGUI()
{
    var tree = Resources.Load<VisualTreeAsset>("HealthEditor");  // or AssetDatabase
    var root = tree.CloneTree();
    root.Bind(serializedObject);  // auto-wires fields with binding-path
    return root;
}
```

The `Bind(serializedObject)` call wires every element with a `binding-path` attribute matching a serialized property name. That's where UI Toolkit shines for inspectors — declarative, no per-field plumbing.

### IMGUI inspector (still common)

```csharp
[CustomEditor(typeof(Health))]
public class HealthEditorIMGUI : Editor
{
    SerializedProperty _max;

    void OnEnable() => _max = serializedObject.FindProperty("_max");

    public override void OnInspectorGUI()
    {
        serializedObject.Update();
        EditorGUILayout.PropertyField(_max);

        if (Application.isPlaying)
        {
            var h = (Health)target;
            EditorGUILayout.LabelField("Current", $"{h.Current:0.0} / {h.Max:0.0}");
            Repaint();  // 30Hz redraw while playing
        }

        serializedObject.ApplyModifiedProperties();
    }
}
```

IMGUI is fine for one-off inspectors with a few fields. Past that, UI Toolkit is less code and less fragile.

### Showing default + extra

If you only want to *add* to the default inspector (not replace it), in IMGUI call `DrawDefaultInspector()` then your extras. In UI Toolkit, add `new InspectorElement(serializedObject)` as a child — that renders the default inspector inside your custom layout.

## Property drawers — reusable per-field UI

When the same custom UI applies to a *type* (a struct, a `[Serializable]` class) or to fields with a custom attribute, use a property drawer instead of a per-component inspector:

```csharp
public class MinMaxRangeAttribute : PropertyAttribute
{
    public float Min, Max;
    public MinMaxRangeAttribute(float min, float max) { Min = min; Max = max; }
}

[CustomPropertyDrawer(typeof(MinMaxRangeAttribute))]
public class MinMaxRangeDrawer : PropertyDrawer
{
    public override VisualElement CreatePropertyGUI(SerializedProperty property)
    {
        var attr = (MinMaxRangeAttribute)attribute;
        var slider = new Slider(property.displayName, attr.Min, attr.Max)
        {
            bindingPath = property.propertyPath,
            showInputField = true
        };
        return slider;
    }
}
```

Then in any component:
```csharp
[MinMaxRange(0, 100)] public float health;
```

Same pattern for serializable structs — `[CustomPropertyDrawer(typeof(YourStruct))]` and the drawer kicks in everywhere that struct appears in any inspector.

## EditorWindow — standalone tool windows

For larger tools (level editors, asset audits, build tools), open a window from a menu:

```csharp
public class HealthAuditor : EditorWindow
{
    [MenuItem("Tools/Audit/Health Components")]
    public static void Open() => GetWindow<HealthAuditor>("Health Audit");

    void CreateGUI()
    {
        var refresh = new Button(Refresh) { text = "Refresh" };
        rootVisualElement.Add(refresh);

        _list = new ListView();
        _list.makeItem = () => new Label();
        _list.bindItem = (el, i) => ((Label)el).text =
            $"{_results[i].name}: {_results[i].max} HP";
        rootVisualElement.Add(_list);
    }

    ListView _list;
    System.Collections.Generic.List<Health> _results = new();

    void Refresh()
    {
        _results.Clear();
        foreach (var h in Object.FindObjectsByType<Health>(FindObjectsSortMode.None))
            _results.Add(h);
        _list.itemsSource = _results;
        _list.Rebuild();
    }
}
```

For IMGUI EditorWindow, override `OnGUI` instead of `CreateGUI`. Same `[MenuItem]` and `GetWindow<T>` pattern.

## `[MenuItem]` — quick utilities

Drop any static method into an editor assembly with `[MenuItem("Tools/Reset All Health")]` and it appears in the menu. Useful for one-shot project-wide operations. Add a validator method to grey it out when not applicable:

```csharp
[MenuItem("Tools/Reset Selected Health")]
static void ResetSelected()
{
    foreach (var go in Selection.gameObjects)
        if (go.TryGetComponent<Health>(out var h))
            { /* ... */ EditorUtility.SetDirty(h); }
}

[MenuItem("Tools/Reset Selected Health", validate = true)]
static bool ResetSelectedValid() => Selection.gameObjects.Length > 0;
```

`EditorUtility.SetDirty(obj)` marks an asset as modified so Unity saves the change. Without it, your edit is forgotten on the next domain reload.

## Asset post-processors — automate import settings

`AssetPostprocessor` runs during asset import. Use it to enforce conventions (every sprite under `Assets/Art/UI/` gets the same import settings, etc.):

```csharp
public class TextureRules : AssetPostprocessor
{
    void OnPreprocessTexture()
    {
        if (!assetPath.Contains("/UI/")) return;
        var importer = (TextureImporter)assetImporter;
        importer.textureType = TextureImporterType.Sprite;
        importer.spritePixelsPerUnit = 100;
        importer.filterMode = FilterMode.Bilinear;
        importer.mipmapEnabled = false;
    }

    void OnPreprocessModel()
    {
        if (!assetPath.Contains("/Characters/")) return;
        var importer = (ModelImporter)assetImporter;
        importer.isReadable = false;
        importer.importNormals = ModelImporterNormals.Calculate;
    }
}
```

Saves dragging artists through settings dialogs and silently fixes new assets that land in the project.

## Gizmos — visual debug in the scene view

`OnDrawGizmos` runs for every selected scene object in the editor; `OnDrawGizmosSelected` only when this object (or a parent) is selected.

```csharp
void OnDrawGizmosSelected()
{
    Gizmos.color = Color.yellow;
    Gizmos.DrawWireSphere(transform.position, _detectionRange);

    Gizmos.color = Color.red;
    Gizmos.DrawRay(transform.position, transform.forward * 2f);
}
```

For richer drawing (text labels, handles, dragging), use `Handles` inside an editor script's `OnSceneGUI`:

```csharp
[CustomEditor(typeof(PatrolPath))]
public class PatrolPathEditor : Editor
{
    void OnSceneGUI()
    {
        var path = (PatrolPath)target;
        for (int i = 0; i < path.Points.Count; i++)
        {
            EditorGUI.BeginChangeCheck();
            var newPos = Handles.PositionHandle(path.Points[i], Quaternion.identity);
            if (EditorGUI.EndChangeCheck())
            {
                Undo.RecordObject(path, "Move patrol point");
                path.Points[i] = newPos;
            }
        }
    }
}
```

The `Undo.RecordObject` call before the change is what makes Ctrl-Z work. Forgetting it is the most common editor-tool bug.

## Build pipeline hooks

For pre/post-build automation (stripping debug data, packing addressables, signing, etc.), implement `IPreprocessBuildWithReport` or `IPostprocessBuildWithReport`:

```csharp
public class StripDebugLogs : IPreprocessBuildWithReport
{
    public int callbackOrder => 0;

    public void OnPreprocessBuild(BuildReport report)
    {
        // Set a scripting define, generate a manifest, copy files, etc.
        PlayerSettings.SetScriptingDefineSymbolsForGroup(
            BuildTargetGroup.Standalone, "RELEASE_BUILD");
    }
}
```

The build system finds and runs these automatically. `callbackOrder` lets you sequence multiple hooks deterministically.

## SerializedObject and SerializedProperty

When writing editor scripts, **don't mutate target fields directly**. Use the `SerializedObject` / `SerializedProperty` API instead:

```csharp
// In an Editor subclass:
serializedObject.Update();                             // pull from data
_someProp.intValue = 5;                                // edit
serializedObject.ApplyModifiedProperties();            // push back (with Undo)
```

This gives you free undo support, multi-object editing, and prefab override tracking. Direct field writes bypass all of that.

## Conditional code with `#if UNITY_EDITOR`

For runtime classes that have small editor-only helpers, wrap with `#if UNITY_EDITOR`:

```csharp
public class Health : MonoBehaviour
{
    [SerializeField] float _max = 100f;

#if UNITY_EDITOR
    [ContextMenu("Reset to Max")]
    void EditorResetToMax() { Current = _max; }
#endif
}
```

`[ContextMenu("...")]` adds an entry to the component's gear menu — a quick way to add per-component utilities without writing a full editor script. The `#if UNITY_EDITOR` ensures it doesn't ship.

## Common pitfalls

- **Editor code in the runtime assembly.** Build will fail with `UnityEditor` not found. Move the file under `Editor/`.
- **Mutating an asset without `SetDirty`.** Your change vanishes on reload. Always `EditorUtility.SetDirty(obj)` or use `SerializedObject.ApplyModifiedProperties()`.
- **Forgetting `Undo.RecordObject` before changes.** No undo. The user's first reaction is to hit Ctrl-Z and lose work.
- **Doing slow work in `OnInspectorGUI` every repaint.** IMGUI inspectors repaint at ~30 Hz. Cache expensive lookups in `OnEnable` and update only on change.
- **Editor-time `FindObjectByType` in `Update`-equivalent paths** (the EditorApplication update loop). It's slow and scans the scene every tick. Cache it.
- **Property drawers that don't track `serializedObject` for undo.** If you skip the SerializedProperty API, you skip the undo. Always go through properties.
