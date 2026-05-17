# URP rendering

Load this reference when working on rendering, custom passes, post-processing, or shaders in a Unity 6.4 + URP project. The 6.4 changes here are significant — Compatibility Mode is gone, so anything that worked in earlier Unity 6.x versions may need migration.

## URP at a glance in Unity 6.4

- **Forward+** is the default rendering path. Clustered light culling lets a single object be lit by many lights without per-object light limits. There's no reason to switch away unless you specifically need Deferred or have a constrained mobile target where Forward (legacy) is measurably faster.
- **Render Graph** is the only API for custom rendering work in 6.4. The old immediate-mode `ScriptableRenderPass.Execute(ScriptableRenderContext, ref RenderingData)` is hard-obsolete and won't compile.
- **Volumes** own all post-processing. There is no separate post-process stack to install.
- **STP (Spatial Temporal Post-Processing)** is the modern upscaler. Available in URP Asset → Quality → Upscaling Filter.
- **GPU Resident Drawer** is available (URP Asset → Rendering) — pushes draw call work to the GPU via BatchRendererGroup, big wins on scenes with many static renderers.

## The URP asset and renderer

The render pipeline is configured via two asset types:

- **URP Asset** (the `.asset` file referenced from Graphics settings) — quality settings, shadows, HDR, post-processing toggle, upscaling.
- **Universal Renderer** (one or more, referenced from the URP Asset's Renderer List) — rendering path (Forward / Forward+ / Deferred), Renderer Features list, custom passes injected here.

Projects usually have multiple URP Assets, one per quality level (Low/Medium/High), each pointing at the same or different Renderers. Project Settings → Quality maps quality levels to URP Assets.

To attach a custom render pass at the asset level, write a **Renderer Feature** (a `ScriptableRendererFeature`) and add it to the renderer's feature list — that's the supported entry point, not direct `EnqueuePass` from gameplay code.

## Render Graph — how custom passes work in 6.4

A render pass in the Render Graph model declares its inputs and outputs to the graph compiler, which figures out scheduling, memory aliasing, and resource lifetimes. You no longer manage temporary render textures by hand.

The minimal shape of a custom pass:

```csharp
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.RenderGraphModule;
using UnityEngine.Rendering.Universal;

public class GrayscalePass : ScriptableRenderPass
{
    static readonly int _BlitTexId = Shader.PropertyToID("_BlitTexture");
    Material _material;

    public GrayscalePass(Material material)
    {
        _material = material;
        renderPassEvent = RenderPassEvent.AfterRenderingPostProcessing;
    }

    class PassData
    {
        public TextureHandle source;
        public Material material;
    }

    public override void RecordRenderGraph(RenderGraph renderGraph, ContextContainer frameData)
    {
        var resourceData = frameData.Get<UniversalResourceData>();
        var cameraData   = frameData.Get<UniversalCameraData>();

        // Create a temporary destination matching the camera color target.
        var desc = cameraData.cameraTargetDescriptor;
        desc.depthBufferBits = 0;
        var dest = UniversalRenderer.CreateRenderGraphTexture(
            renderGraph, desc, "_GrayscaleTemp", false);

        using (var builder = renderGraph.AddRasterRenderPass<PassData>(
                   "Grayscale", out var passData))
        {
            passData.source   = resourceData.activeColorTexture;
            passData.material = _material;

            builder.UseTexture(passData.source);
            builder.SetRenderAttachment(dest, 0);

            builder.SetRenderFunc((PassData data, RasterGraphContext ctx) =>
            {
                Blitter.BlitTexture(ctx.cmd, data.source,
                    new Vector4(1, 1, 0, 0), data.material, 0);
            });
        }

        // Swap the camera color target so subsequent passes see the result.
        resourceData.cameraColor = dest;
    }
}
```

Wrap that in a `ScriptableRendererFeature`:

```csharp
public class GrayscaleFeature : ScriptableRendererFeature
{
    [SerializeField] Material _material;
    GrayscalePass _pass;

    public override void Create()
    {
        if (_material == null) return;
        _pass = new GrayscalePass(_material);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer,
                                         ref RenderingData renderingData)
    {
        if (_pass != null) renderer.EnqueuePass(_pass);
    }
}
```

Add the feature to the Universal Renderer asset's Renderer Features list, drop in a material using a `FullScreenPassRenderer`-style shader (or your own with a blit shader), and you're rendering.

### Key Render Graph concepts

- **`TextureHandle`** is a graph-managed handle, not an actual texture. Resources are allocated lazily when the graph compiles.
- **`builder.UseTexture(...)`** declares a read; **`builder.SetRenderAttachment(...)`** declares a write. The compiler uses these to order passes and reuse memory.
- **`RasterRenderPass`** is for traditional rasterized work. There's also `UnsafeRenderPass` (escape hatch for arbitrary `CommandBuffer` work) and `ComputeRenderPass` for compute shaders.
- **`UniversalResourceData`** is the standard `frameData` slot containing `activeColorTexture`, `activeDepthTexture`, `cameraNormalsTexture`, etc. Read from these; write back by reassigning if your pass produces a new color target.
- **`ContextContainer frameData`** is a per-frame typed bag of slots. URP populates a handful by default; you can add your own with `frameData.Create<MyData>()` to pass state between your own passes.

### Migrating an old `Execute` pass

If you're porting a pre-6.4 pass:

1. Move the body of `Execute(ctx, ref renderingData)` into a `SetRenderFunc` lambda on a new `PassData` class.
2. Hoist all `CommandBuffer.GetTemporaryRT` calls to graph texture creation outside the lambda.
3. Replace direct `cmd.SetRenderTarget` with `builder.SetRenderAttachment`.
4. Replace direct `cmd.Blit(src, dst, mat)` with `Blitter.BlitTexture(...)` inside the render func.
5. Delete the `Configure` and `OnCameraSetup` overrides if you had them — those don't apply in the graph model.

This is genuinely more code for trivial passes, but the wins are real on complex setups: temporary memory is reused, passes can be culled if their outputs aren't read, and the graph viewer in the editor shows you exactly what's happening.

## Post-processing via the Volume system

Post effects are added via **Volume Profile** assets and applied through **Volume** components in scenes. There are three pieces:

1. **Volume Profile** (`.asset`) — a list of overrides (Bloom, Vignette, Color Adjustments, etc.).
2. **Volume** component on a GameObject — references the profile, marks itself Global or Local (with a collider).
3. **Camera's Volume Mask** — layer mask determining which volumes affect that camera.

To override at runtime: get the `Volume`, access `volume.profile.TryGet<Bloom>(out var bloom)`, and write to it. **`profile` returns a copy unique to this volume**; use `sharedProfile` only if you mean to mutate the asset (you usually don't).

Custom post effects are now first-class: subclass `VolumeComponent`, write a matching `ScriptableRendererFeature` + pass, and register via the renderer asset.

## Shaders — Shader Graph vs HLSL

For most surface, post, and stylized effects, **Shader Graph** is the right tool in URP. In 6.3+ it gained terrain shader support, UI lit shaders, and template browser. Open with the URP target selected so it generates URP-compatible variants (forward + GBuffer + shadowcaster + depthnormals etc.).

Reach for **handwritten HLSL** when:
- You need control over render state, multi-pass, or grab passes not exposed by Shader Graph.
- You're writing a compute shader (Shader Graph doesn't author those).
- You're porting an existing shader and a manual rewrite is faster than wiring nodes.

HLSL shaders in URP follow the URP shader library:

```hlsl
Shader "Custom/UnlitURP"
{
    Properties
    {
        _BaseMap("Base Map", 2D) = "white" {}
        _BaseColor("Base Color", Color) = (1,1,1,1)
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Tags { "LightMode"="UniversalForward" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4  _BaseColor;
            CBUFFER_END

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; };
            struct Varyings   { float4 positionHCS : SV_POSITION; float2 uv : TEXCOORD0; };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                return SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;
            }
            ENDHLSL
        }
    }
}
```

Key URP shader conventions:
- Always include the URP shader library `Core.hlsl` (and `Lighting.hlsl` for lit shaders).
- Use the SRP-compatible macros (`TEXTURE2D`, `SAMPLER`, `TRANSFORM_TEX`, `TransformObjectToHClip`) instead of legacy built-in macros.
- Put per-material properties inside `CBUFFER_START(UnityPerMaterial)` — required for SRP Batcher compatibility.
- `RenderPipeline=UniversalPipeline` tag identifies the shader to URP.

## Common pitfalls

- **Forgetting `UnityPerMaterial`.** Without it, the shader breaks SRP Batcher and you'll silently lose batching performance.
- **Mixing legacy and URP shaders.** A built-in pipeline shader (`Tags { "LightMode"="ForwardBase" }`) will render bright magenta in URP. Convert it or use the Render Pipeline Converter.
- **Using `Camera.main` in every script.** It's slow and breaks with multiple cameras. Cache it, or use a camera service.
- **Custom passes that don't read what they write.** If your pass writes to a `TextureHandle` nobody downstream uses, the graph compiler culls it and you'll see "my effect doesn't appear." Either reassign `resourceData.cameraColor` or have a follow-up pass that reads your output.
- **Modifying a `sharedProfile` at runtime.** Mutates the asset file. Use `profile` for per-volume tweaks.
- **Putting `Bloom` and other heavy effects in URP Asset's post-processing toggle but expecting them at runtime.** They also need to be in a Volume Profile applied to a Volume in the scene.

## Where to go from here

- Unity's URP manual: `docs.unity3d.com/Packages/com.unity.render-pipelines.universal@latest`.
- The Render Graph API docs and samples in the URP package's `Samples~` folder (importable via Package Manager → URP → Samples).
- For Shader Graph specifically, the included sample browsers (6.3+) ship with a template browser inside the Shader Graph window.
