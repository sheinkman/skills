# 2D and isometric

Load this reference when working on 2D content or an isometric game. Isometric in Unity 6 splits into two distinct approaches that share little code; the section "3D with iso camera vs pure 2D iso" below covers the choice. Most modern isometric indie titles take the **3D-with-iso-camera** route — it's easier to scale, plays better with Unity's systems, and visually looks identical to "real 2D iso" when handled well.

## 3D with iso camera vs pure 2D iso

The choice matters because it changes which APIs apply.

### Approach A — 3D with isometric camera (recommended for most projects)

- World is built from **3D meshes** (or 3D-rendered sprites on quads).
- Camera is **orthographic**, rotated to a fixed iso angle (typically `(30, 45, 0)` for classic iso, or `(60, 45, 0)` for a flatter "Diablo" angle).
- **Real 3D physics** (`Rigidbody`, `Collider`).
- **Unity AI Navigation works natively** — see `references/ai-and-navmesh.md`.
- **URP Forward+** is fine; everything from 3D shaders to post-processing works.
- Animation can be 3D skeletal, sprite-based on planes, or hybrid (3D environments + 2D sprite characters on billboards or angled planes).

This is the path most modern Unity isometric games take (think Hades-style 2.5D, Bastion-style stylized iso). Easier to maintain, future-proof, and the tooling is mature.

### Approach B — Pure 2D iso (Sprite Renderer + Isometric Tilemap)

- World is **sprites** (`SpriteRenderer`, `Tilemap` with isometric orientation).
- Camera is orthographic and **un-rotated** (looking straight down the Z axis).
- **2D physics** (`Rigidbody2D`, `Collider2D`).
- Pathfinding needs **NavMeshPlus** or **A* Pathfinding Project** — Unity AI Navigation doesn't apply.
- Sprite sorting is the central problem (see below).
- Classic look (Diablo 2, modern indie pixel-art iso).

Pick this if your art is purely pixel art / 2D illustration and you want a flat, painterly look that 3D can't easily fake. Otherwise the 3D path is more productive.

The rest of this reference covers both; sections are labeled.

## 2D project setup (both approaches)

Either approach uses Unity's 2D feature set. Key packages and settings:

- **2D Sprite** package — installed by default in a 2D template. Provides Sprite Editor.
- **2D Tilemap Editor** package — tilemap workflow.
- **2D Animation** package — bone-based sprite animation (skeletal sprites).
- **2D PSDImporter** package — keeps Photoshop layer structure intact through import.

For URP-based 2D lighting:

- Renderer Asset must be a **2D Renderer** (or a Universal Renderer that supports 2D, depending on URP version). Set this in the URP Asset → Renderer List.
- Sprites use the **`Sprite-Lit-Default`** material to receive 2D lights, or **`Sprite-Unlit-Default`** to render at full brightness.
- Add **Light 2D** components (Freeform, Point, Spot, Sprite, Global) for lighting.

## Sprite import settings

For every sprite:

- **Pixels Per Unit (PPU)** — defines world-to-pixel scale. **Pick one PPU for your project and stick to it.** 100 is the default; pixel-art games often use 16, 32, or 64 to align with their native sprite resolution.
- **Filter Mode**:
  - **Point (no filter)** for crisp pixel art. Anything else blurs.
  - **Bilinear** for smooth, painterly, or high-resolution art.
- **Compression** — None for pixel art (preserves crisp pixels), Quality (BC7/ASTC) for everything else.
- **Mip Maps Enabled** — off for UI sprites and pixel art (saves memory, prevents shimmer); on for sprites that change apparent size dramatically.
- **Mesh Type** — Tight reduces overdraw at the cost of slightly more vertices. Useful for sprites with lots of transparent pixels.

Enforce these via `AssetPostprocessor` (`references/editor-tooling.md`) — saves enormous time as the art folder grows.

## Sprite atlases

Always atlas your sprites. An atlas combines many sprites into one texture, drastically reducing draw calls — the difference between batched and unbatched can be 10× on busy 2D scenes.

Create via Assets → Create → 2D → Sprite Atlas. Drag sprites or folders into the **Objects for Packing**. Atlases support variants (high-res master, lower-res variant for low-end devices).

Include in Build: on. The atlas is what ships; the source sprites are repacked into it.

## Sprite sorting (the hard part of pure 2D iso)

For Approach A (3D iso), sorting is the normal 3D depth buffer — no special work. For **Approach B (pure 2D iso)**, sprites need to sort by "back-to-front" along the iso axis. Unity's options:

### Sorting Group + Transparency Sort Axis

In Project Settings → Graphics → Camera Settings → Transparency Sort Mode = **Custom Axis**, then set Sort Axis to `(0, 1, 0)` for top-down or a tweaked vector for iso (often `(0, 1, -0.5)` to factor in the iso projection).

Every sprite's world Y position then determines its draw order. A character standing in front of a tree draws on top automatically.

For **multi-piece characters** (separate head/body/arm sprites), put them in a **`SortingGroup`** component. The group sorts as one unit relative to the world, internal pieces sort within themselves by order.

### Tilemap-specific sorting

Isometric tilemaps need a **Tilemap Renderer → Mode → Individual**, then **Sort Order = Top Right** (or whatever matches your camera angle). This makes each tile sort by its world position, not all-at-once as one mesh. The cost is more draw calls; the alternative is wrong sorting.

## Tilemaps for isometric

Create via GameObject → 2D Object → Tilemap → Isometric (or Hexagonal). The Grid component on the parent defines cell layout; the Tilemap component holds the tiles.

Tile types:

- **Tile** — a single sprite per cell.
- **Animated Tile** — frame animation per cell.
- **Rule Tile** — selects sprite based on neighbors (auto-tiling, smart walls).

Rule Tiles are the biggest productivity multiplier — author once, paint anywhere, the right sprite appears based on neighbors. Pre-made rule tile sets ship with the 2D Extras GitHub repo (free).

### Z-order layers vs tilemap layers

Multiple tilemaps stacked vertically (one per "floor" or content layer) lets you separate ground, walls, decorations, and roof. Each tilemap can have its own renderer settings (sort order, color, material). Wire them under one Grid parent so they share cell layout.

## Sprite animation

Two paths:

### Frame-based (Sprite Renderer + Animator)

Classic approach. Author a sprite sheet, slice it in the Sprite Editor, drag frames into an Animation clip. Animator controls which clip plays. Works the same as 3D animation otherwise.

For lots of frame-based characters with similar animation sets, **Animator Override Controllers** let one animator graph drive many characters with different clips:

```csharp
var overrideController = new AnimatorOverrideController(_baseController);
overrideController["Idle"] = _myIdleClip;
overrideController["Run"] = _myRunClip;
_animator.runtimeAnimatorController = overrideController;
```

### Skeletal 2D (2D Animation package)

Rig a sprite with bones, animate via keyframes on bone transforms. Smaller memory footprint than frame-based for large characters, smoother motion. PSDImporter preserves the layered art so you can rig from Photoshop straight into Unity.

For an isometric game with many enemy variants, **frame-based** is often the practical choice — easier to swap art per enemy, no rigging.

## 2D lighting

In URP with the 2D Renderer:

- **Global Light 2D** — base ambient light, one per scene.
- **Point Light 2D** — radial light (torches, magic).
- **Spot Light 2D** — cone, useful for flashlights or directional accents.
- **Sprite Light 2D** — light shaped like a sprite (useful for flame-shaped lights).
- **Freeform Light 2D** — author a polygon shape for the light.

Sprites need **Sprite-Lit-Default** material to receive light. Normal maps via the secondary texture slot in the Sprite Editor add depth.

For **shadow casters**, add a **Shadow Caster 2D** component to objects that should block light. Light 2D has a **Shadow Intensity** slider; tune per light.

Performance: 2D lights are post-processing, not deferred — many lights touching the same pixel adds cost. A scene with 30+ moving Light 2D components on screen is a perf wall on integrated GPUs.

## Iso-specific gameplay patterns

### Input → world direction

In a 3D-iso world, WASD should move the character along world axes, not screen axes. With a 45°-rotated camera:

```csharp
Vector3 ScreenInputToWorld(Vector2 input)
{
    var camForward = _cam.transform.forward; camForward.y = 0; camForward.Normalize();
    var camRight = _cam.transform.right;    camRight.y = 0;   camRight.Normalize();
    return camForward * input.y + camRight * input.x;
}
```

For pure-2D iso, the conversion is different — multiply by an iso projection matrix to convert screen WASD to grid movement. Often easier to just remap inputs: W = up-right, A = up-left, S = down-left, D = down-right.

### Click-to-move (mouse-driven iso)

```csharp
void Update()
{
    if (Mouse.current.leftButton.wasPressedThisFrame)
    {
        var ray = _cam.ScreenPointToRay(Mouse.current.position.ReadValue());
        if (Physics.Raycast(ray, out var hit, 100f, _groundMask))
            _agent.SetDestination(hit.point);   // Approach A
        // OR for 2D:
        // var world = _cam.ScreenToWorldPoint(Mouse.current.position.ReadValue());
        // _pathfinder.MoveTo(world);
    }
}
```

In Approach A this works trivially with a 3D ground collider. In Approach B you typically have a flat plane at z=0 and use `Camera.ScreenToWorldPoint`.

### Y-sorting cheat for "depth"

In Approach B, you may want a character partly behind a pillar to be hidden. The sprite sort axis trick handles the "in front / behind" case automatically. For partial occlusion (the pillar fading where the character is behind it), use a **stencil-based shader** that writes a stencil bit when the character renders, and the pillar samples its own stencil to fade pixels behind the character. Niche; only worth it if the art design demands it.

## Performance for 2D / iso

- **Atlasing is non-negotiable** at any scale. Unatlased sprite-heavy scenes hit the draw call ceiling fast.
- **TileMap Renderer batching**: leave on (Chunk mode) for static layers; switch to Individual only for layers that need per-tile sorting.
- **Avoid `SortingGroup` nesting beyond two levels** — each level adds a sort op.
- **Light 2D count**: budget ~20 simultaneously visible for integrated GPUs, more for desktop. Cull off-screen Light 2D components.
- **2D physics broadphase**: 2D physics uses a sweep-and-prune broadphase. Lots of small triggers (pickups) are cheap; many overlapping Rigidbody2D bodies are expensive.

See `references/performance.md` for the general performance treatment.

## Common pitfalls

- **Mixed PPU across sprites.** A 100-PPU sprite next to a 32-PPU sprite renders at very different physical sizes. Pick one PPU per project, treat exceptions (UI) as separate.
- **Filter Mode Bilinear on pixel art.** Blurs the art. Always Point for pixel-art sprites.
- **Choosing pure-2D iso for a project that should be 3D-iso.** If you have any 3D characters, any complex lighting, or want NavMesh, you've made life harder. Switch before you have 200 sprites in place.
- **Unsorted sprites in pure-2D iso.** Set up Transparency Sort Axis early; retrofitting at scene #20 is painful.
- **Sprite Atlas not in build.** "Include in Build" defaults to on but easy to disable by accident. Result: source sprites ship un-atlased and draw calls 10×.
- **TileMap collider not refreshing.** A `TilemapCollider2D` doesn't update automatically when you change tiles at runtime. Call `_collider.ProcessTilemapChanges()` (or composite + `_composite.GenerateGeometry()`) after edits.
- **3D physics in a pure-2D iso project.** Mixing `Collider` and `Collider2D` doesn't interact — `Physics.Raycast` and `Physics2D.Raycast` are different systems entirely. Pick one per project.
- **Trying to use Unity AI Navigation in pure-2D iso.** Doesn't work; the package is 3D. Use NavMeshPlus, A* Pathfinding Project, or roll your own grid A*.
