# Input and UI

Load this reference when wiring up player input or building UI in a Unity 6.4 + URP project. The two topics are bundled because they interact: UI consumes input, and the Input System ↔ UI Toolkit integration has its own quirks.

## Input System — the modern path

The Input System package is the default for new Unity 6 projects. If `Packages/manifest.json` shows `com.unity.inputsystem`, that's what you're working with. Confirm Project Settings → Player → Active Input Handling = "Input System Package" (or "Both" during a migration).

### The pieces

1. **`.inputactions` asset** — defines Action Maps (e.g. "Player", "UI"), Actions (e.g. "Move", "Jump"), and Bindings (which physical input → which action). Edit in the dedicated editor window.
2. **Generated wrapper C# class** — tick "Generate C# Class" on the asset, and Unity creates a strongly-typed wrapper. This is the recommended way to access actions from code in any non-trivial project.
3. **`PlayerInput` component** — high-level wrapper for hooking actions to MonoBehaviour methods via `UnityEvent`s or `SendMessage`-style callbacks. Useful for prototypes and designer-driven setups.

### The patterns

**Pattern A — Generated wrapper class (recommended for code-driven projects):**

```csharp
public class PlayerController : MonoBehaviour
{
    GameInput _input;            // The generated wrapper.
    Rigidbody _rb;
    Vector2   _moveInput;

    void Awake()
    {
        _rb = GetComponent<Rigidbody>();
        _input = new GameInput();
    }

    void OnEnable()
    {
        _input.Player.Enable();
        _input.Player.Move.performed += OnMove;
        _input.Player.Move.canceled  += OnMove;
        _input.Player.Jump.performed += OnJump;
    }

    void OnDisable()
    {
        _input.Player.Move.performed -= OnMove;
        _input.Player.Move.canceled  -= OnMove;
        _input.Player.Jump.performed -= OnJump;
        _input.Player.Disable();
    }

    void OnMove(InputAction.CallbackContext ctx) => _moveInput = ctx.ReadValue<Vector2>();
    void OnJump(InputAction.CallbackContext ctx) { /* ... */ }

    void FixedUpdate()
    {
        var move = new Vector3(_moveInput.x, 0, _moveInput.y);
        _rb.AddForce(move * _speed);
    }
}
```

Notes:
- `Enable()` / `Disable()` the action map (or the whole asset) to gate input — much cleaner than per-frame `if (isPaused) return`.
- **Subscribe in `OnEnable`, unsubscribe in `OnDisable`.** Every project leaks input event subscriptions at some point; this pattern prevents it.
- `performed` fires once when the binding is satisfied; `canceled` fires when it's released. Reading `Vector2`/axis values, listen to both — `canceled` resets the input to zero.

**Pattern B — `PlayerInput` component (designer-driven):**

Drop a `PlayerInput` component on the player, set the Actions asset and Behavior = "Invoke Unity Events". Wire `OnMove`, `OnJump` etc. directly to methods in the inspector. Simpler for prototypes; harder to refactor later. Good for game jams, prototypes, and small projects.

### Control schemes and devices

Action maps support multiple control schemes (Keyboard&Mouse, Gamepad, Touch). The same action ("Jump") can bind to space, the A button, and a screen button — `PlayerInput` switches schemes automatically based on which device sends the last input.

For local multiplayer, use `PlayerInputManager` — instantiates a player prefab per joined device.

### Pitfalls

- **Don't read `Input.GetKey` from the same project.** Mixing legacy and new makes input ordering unpredictable. Pick one.
- **Don't poll an `InputAction` value in `Update` when you could subscribe to `performed`.** Polling burns work; events are essentially free.
- **Forgetting to `Enable()`.** If your action seems dead, check that the action map is enabled. Generated wrappers default to disabled.

## UI Toolkit vs UGUI

Both are fully supported. Pick by use case, not by trend.

### UI Toolkit (UXML + USS, `UnityEngine.UIElements`)

The newer, retained-mode framework. Authoring is web-inspired: UXML for structure, USS for styling, C# for behavior. Renders via a custom optimized path.

Strengths:
- Designer-friendly markup and styling — UXML/USS feel familiar to anyone who has touched HTML/CSS.
- Better at responsive layouts (Flexbox-like).
- Editor inspectors and tool windows use the same system — one mental model for runtime UI and tooling.
- Strong data binding story in 6.x (`SetBinding(...)` with ScriptableObject sources).
- Generally lower draw call cost for complex menus.

Weaknesses / caveats:
- **World-space UI** (UI attached to a 3D object) is still UGUI-only or requires custom integration. Health bars over enemies, in-world signage — use UGUI.
- Particle effects and animations *inside* UI panels are easier in UGUI.
- The runtime feature set is still catching up to UGUI for some niche cases (custom shaders on UI elements, masking with shape, etc.).
- Existing assets and tutorials are predominantly UGUI; the ecosystem is leaner.

Reach for UI Toolkit for: main menus, HUDs (non-world-space), settings panels, in-game inventories, and **all editor tooling** in new projects.

### UGUI (Canvas-based, `UnityEngine.UI`)

The mature, immediate-mode-ish framework. Canvas → Image/Text/Button hierarchy, rendered via the standard URP pipeline.

Strengths:
- World-space canvases attached to 3D objects.
- Particle systems and 3D models inside UI panels.
- Mature, well-documented, every tutorial uses it.
- Easy to apply custom URP shaders to UI elements.

Weaknesses:
- Canvas rebuilds are expensive when content changes — split static and dynamic content across separate Canvases. A single Canvas with dynamic text rebuilds the whole canvas on every change.
- More draw calls for complex menus than the equivalent UI Toolkit setup.

Reach for UGUI for: world-space UI, particle-heavy UI, projects that already standardized on it. Don't migrate working UGUI to UI Toolkit without a real reason.

### Mixed usage

A project can use both. A common pattern in 6.4: UI Toolkit for menus, HUDs, and tooling; UGUI for world-space callouts and damage numbers. Don't try to do the same screen in both — pick per screen.

## UI Toolkit basics

**UXML** — structure:

```xml
<ui:UXML xmlns:ui="UnityEngine.UIElements">
    <ui:VisualElement name="root" class="screen">
        <ui:Label text="Pause" class="title" />
        <ui:Button name="resume" text="Resume" />
        <ui:Button name="quit"   text="Quit" />
    </ui:VisualElement>
</ui:UXML>
```

**USS** — styling:

```css
.screen   { flex-grow: 1; justify-content: center; align-items: center; }
.title    { font-size: 48px; color: white; margin-bottom: 24px; }
Button    { width: 200px; height: 48px; margin: 8px; }
Button:hover { background-color: rgba(255,255,255,0.1); }
```

**C# behavior**:

```csharp
public class PauseMenu : MonoBehaviour
{
    [SerializeField] UIDocument _doc;

    void OnEnable()
    {
        var root = _doc.rootVisualElement;
        root.Q<Button>("resume").clicked += Resume;
        root.Q<Button>("quit").clicked   += Quit;
    }

    void Resume() { /* ... */ }
    void Quit()   { /* ... */ }
}
```

The `UIDocument` component on a GameObject references a UXML asset and a `PanelSettings` asset (controlling scale, theme, input handling). One `UIDocument` per screen is the usual organization.

## UI Toolkit in practice

### Querying the visual tree

`UQuery` is how you find elements after the tree is built. Cache queried elements in `OnEnable`; don't re-query every frame.

```csharp
var root = _doc.rootVisualElement;

// By `name` attribute in UXML:
var resumeBtn = root.Q<Button>("resume");

// By USS class name:
var dangerLabels = root.Query<Label>(className: "danger").ToList();

// Iterate all of a type:
root.Query<Button>().ForEach(b => b.SetEnabled(false));

// Combined — by type + name + class:
var primaryAction = root.Q<Button>(name: "confirm", className: "primary");
```

`Q<T>` returns the first match (or `null`); `Query<T>` returns a builder supporting `.ToList()`, `.ForEach(...)`, `.First()`.

### Events and callbacks

UI Toolkit uses a typed event model. `Button` exposes the convenient `clicked` shorthand; everything else goes through `RegisterCallback<T>`:

```csharp
resumeBtn.clicked += Resume;                                     // Button-only shorthand
resumeBtn.RegisterCallback<PointerEnterEvent>(_ => resumeBtn.AddToClassList("hover"));
resumeBtn.RegisterCallback<PointerLeaveEvent>(_ => resumeBtn.RemoveFromClassList("hover"));
root.RegisterCallback<KeyDownEvent>(OnKey);
```

Events propagate from the element up the tree (bubble phase). To handle on the way down, register with `TrickleDown.TrickleDown`:

```csharp
root.RegisterCallback<PointerDownEvent>(OnPointerDown, TrickleDown.TrickleDown);
```

Inside a handler, `evt.StopPropagation()` halts bubbling/trickling. Always pair `RegisterCallback` with `UnregisterCallback` (or attach in `OnEnable` / detach in `OnDisable`) to avoid leaks across domain reloads.

### UIDocument lifecycle

- **`rootVisualElement` is null in `Awake`.** UI Toolkit builds the tree later. Wire up in `OnEnable` or `Start`.
- **UXML/USS hot reload rebuilds the tree.** Programmatically attached callbacks must be re-registered; guard with `-=` before `+=`, or do all wiring in `OnEnable` (Unity re-fires it after the rebuild).
- **Layered UI** — multiple `UIDocument`s on separate GameObjects with different `Sort Order` values stack correctly (HUD beneath pause menu, etc.).

### PanelSettings

The `PanelSettings` asset referenced by the `UIDocument` controls how the UI scales and routes input:

- **Scale Mode** — usually "Scale With Screen Size" for HUDs and menus that should adapt to resolution.
- **Reference Resolution** — the design resolution; UI scales relative to this.
- **Theme Style Sheet (`.tss`)** — base theme. Inherit from `UnityDefaultRuntimeTheme.tss` or author your own.
- **Sort Order** — higher renders on top across multiple panels.
- **Input Source** — "Input System" if the project uses the Input System package; otherwise "Default" (legacy Input Manager). Wrong setting silently breaks UI navigation.

### Manipulators

Reusable interaction handlers attached to elements. `Clickable` is built in; you can subclass `Manipulator` for custom drag/resize/etc. logic:

```csharp
var clickable = new Clickable(() => Debug.Log("clicked"));
myElement.AddManipulator(clickable);
```

Manipulators let you reuse interaction code across many elements without duplicating callback wiring.

### Scheduling periodic work

For ticking UI (timers, polled values, animations), use the element's `schedule` API instead of a MonoBehaviour `Update`:

```csharp
healthBar.schedule.Execute(() => healthBar.value = _player.HealthPercent)
                  .Every(100);  // ms
```

Chain `.Until(predicate)` to stop conditionally, or `.StartingIn(delayMs)` for an initial delay. The scheduler stops automatically when the element is removed from the tree — no manual teardown.

### Reactive data flow

For most game UI, a simple "observe a model, update the view in a callback" pattern is enough — no framework needed:

```csharp
public class HUD : MonoBehaviour
{
    [SerializeField] UIDocument _doc;
    [SerializeField] PlayerStats _stats;   // ScriptableObject or model

    Label _hp;

    void OnEnable()
    {
        _hp = _doc.rootVisualElement.Q<Label>("hp");
        _stats.OnHealthChanged += UpdateHp;
        UpdateHp(_stats.Health);  // seed initial value
    }

    void OnDisable() => _stats.OnHealthChanged -= UpdateHp;

    void UpdateHp(int v) => _hp.text = $"HP {v}";
}
```

Unity 6.x ships a richer declarative `DataBinding` / `SetBinding` API on top of UI Toolkit — useful for forms-heavy UI. Check the Unity 6.4 manual for the exact API surface before using it; the manual pattern above is fine for most game UI and easier to step through in a debugger.

## Input ↔ UI Toolkit integration

By default, UI Toolkit at runtime uses its own event system and reads from the **legacy Input Manager** for navigation (arrow keys, gamepad). To make it work with the new Input System for navigation:

1. Install the package `com.unity.inputsystem.uitoolkit` (the bridge package) — or in newer Input System versions, this is already integrated.
2. On the `PanelSettings` asset, set the Input System provider.
3. UI navigation actions (Up/Down/Submit/Cancel) come from your Input Actions asset's UI action map.

This integration is finicky — many projects ship with UGUI's `EventSystem` + `InputSystemUIInputModule` because that combination is the most battle-tested.

### Cursor and pointer events

UI Toolkit handles pointer events through `RegisterCallback<PointerEnterEvent>` / `PointerLeaveEvent` / `ClickEvent`. For drag-and-drop, register the manipulator pattern (`DragManipulator`, etc.) or implement via `PointerDown`/`PointerMove`/`PointerUp`.

## Common pitfalls

- **Text rendering in UI Toolkit ≠ TextMeshPro.** UI Toolkit uses its own text engine. If you need TMP-specific features (rich text effects, SDF outlines/glows), either use UGUI for that screen, or check that UI Toolkit's text engine covers what you need.
- **UGUI Canvas rebuilds.** A label that updates every frame on a Canvas with 100 static elements rebuilds the whole canvas every frame. Split into a "static" Canvas and a "dynamic" Canvas, each with its own `Canvas Scaler`.
- **Forgetting `EventSystem`.** UGUI requires an `EventSystem` component in the scene for clicks/drags to work. New scenes via "UI → Canvas" auto-create one; programmatically built UI doesn't.
- **Input System ↔ UI conflicts.** If clicks don't register in UGUI, check that the `EventSystem` uses `InputSystemUIInputModule` (not the legacy `StandaloneInputModule`).
- **UI Toolkit hot reload.** UXML/USS changes hot-reload in Play Mode — but if you've programmatically wired callbacks in `OnEnable`, those handlers may double-register on reload. Defensive `-=` before `+=` helps.

## When to step out

For very complex UI (in-game web-style content, complex flowing layouts), some projects use a third-party UI framework (e.g. NoesisGUI, web views) or just embed a web view. These are valid choices but outside the scope of this skill — use them when UI Toolkit + UGUI together don't cover the need, not as a default.
