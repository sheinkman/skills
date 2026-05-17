# Animation and cameras

Load this reference when working with the Animator, blend trees, animation events, or Cinemachine. Cinemachine 3 (which ships with Unity 6) is a significant rename of the 2.x API — pre-Unity-6 examples and AI training data may use stale names.

## Animator — the state machine

An Animator component plays animations from an **Animator Controller** asset. The Controller is a state machine: states are clips, transitions are conditions on parameters.

### Parameters

Four types: `Float`, `Int`, `Bool`, `Trigger`. Set from code:

```csharp
[SerializeField] Animator _anim;

// String API — convenient, allocates a string lookup each call.
_anim.SetFloat("Speed", v);
_anim.SetBool("IsGrounded", g);
_anim.SetTrigger("Jump");

// Hashed API — cache once, zero per-call lookups. Use for hot paths.
static readonly int s_Speed = Animator.StringToHash("Speed");
static readonly int s_Jump  = Animator.StringToHash("Jump");
void Update() { _anim.SetFloat(s_Speed, v); }
```

Always hash parameters used every frame. The string overhead is small per call but accumulates fast across many animated characters.

### Transitions and exit times

Transitions have a duration (blend time) and conditions. The defaults that bite new users:

- **"Has Exit Time"** is on by default. The transition waits for the source clip's exit time before evaluating conditions. For responsive gameplay transitions (jump, attack), **turn it off** — you want the transition to fire the moment the condition is true.
- **Transition Duration** is in seconds when "Fixed Duration" is on, in source-clip normalized time when off. Mixed-source projects often want Fixed Duration on.
- **Interruption Sources** — by default, transitions can't be interrupted mid-blend. For "press attack again to chain", set the source state's Interruption Source to "Current State" or "Next State" so a new transition can interrupt.

### Layers

The Animator can have multiple layers, each with its own state machine and weight. Use cases:

- **Override layer at weight 1** with an Avatar Mask — upper-body actions (aim, throw) while the base layer drives locomotion.
- **Additive layer** — sums onto the base for subtle modulation (lean, breathe).

Layer transitions don't affect other layers; each is independent.

### Animation events

A clip can fire events at specific times. Author them in the Animation window's timeline (small marker buttons), then implement matching methods on any component on the same GameObject:

```csharp
public class Footstep : MonoBehaviour
{
    public void OnFootstep()  // Called by animation event at the foot-plant frame.
    {
        AudioSource.PlayClipAtPoint(_step, transform.position);
    }
}
```

Use animation events for "this exact frame is when the sword hits", "this is when the foot lands", etc. The alternative — polling normalized time — drifts and is harder to tune.

### Root motion

If "Apply Root Motion" is checked on the Animator, the clip moves the GameObject directly via its baked motion. Good for cinematic walks, getup animations, attacks with built-in lunges. Bad for free-form gameplay movement where input drives position.

Common pattern: root motion on for cutscenes and special moves, off for normal locomotion. Toggle with `_anim.applyRootMotion = false;` or react in `OnAnimatorMove()` to integrate the delta yourself.

### State machine behaviors

Subclass `StateMachineBehaviour` for per-state callbacks (`OnStateEnter`, `OnStateExit`, `OnStateUpdate`). Attach as a behavior on a state in the Animator. Useful for hooking entry/exit logic to specific states without polluting the controller's parameter wiring.

## Blend trees

A state can play a blend tree instead of a single clip. The tree blends several clips based on parameter values — perfect for locomotion blending walk/run/sprint by speed.

Types:
- **1D** — one parameter, e.g. `Speed`. Each child clip has a threshold.
- **2D Freeform/Simple Directional** — two parameters, e.g. `MoveX` / `MoveY` for 8-way movement. Each clip is positioned in the 2D space.
- **Direct** — set each child's weight explicitly. Used for facial expression mixing, etc.

Blend trees are why locomotion looks smooth without dozens of states + transitions. Use them.

## Animation Rigging package

For runtime constraints (look at target, two-bone IK, multi-position constraints), install the **Animation Rigging** package. It adds a rig with constraint components and lets you blend rig weights at runtime. Standard for aiming, foot IK on slopes, look-at behaviors.

## Cinemachine 3 (Unity 6)

Cinemachine 3 ships with Unity 6 and is a major rewrite. **The API is renamed across the board.** If you see `CinemachineVirtualCamera` or `Cinemachine` namespaces in code, that's the old 2.x API — won't compile against the 3.x package shipped with Unity 6.

### What changed — 2.x → 3 rename table

| Cinemachine 2.x | Cinemachine 3 (Unity 6) |
|---|---|
| `Cinemachine` namespace | `Unity.Cinemachine` |
| `CinemachineVirtualCamera` | `CinemachineCamera` |
| `CinemachineFreeLook` | `CinemachineCamera` + `CinemachineOrbitalFollow` (or `CinemachineThirdPersonFollow`) |
| `m_Lens`, `m_Priority`, etc. (`m_`-prefixed fields) | `Lens`, `Priority` (no prefix) |
| Hidden child "cm" GameObject | Components attach directly to the camera GameObject |
| `CinemachineTransposer` | `CinemachineFollow` (basic follow) |
| `CinemachineFramingTransposer` | `CinemachinePositionComposer` |
| `CinemachineComposer` | `CinemachineRotationComposer` |
| `CinemachinePOV` | `CinemachinePanTilt` |
| `CinemachineCollider` | `CinemachineDeoccluder` |
| `Cinemachine3rdPersonFollow` | `CinemachineThirdPersonFollow` |
| `CinemachineConfiner` | `CinemachineConfiner2D` / `CinemachineConfiner3D` |
| `CinemachineCore.Instance.X()` | `CinemachineCore.X()` (direct static) |

Don't hand-edit prefabs and scenes that reference 2.x types — run **Window → Cinemachine → Upgrade** to convert assets with proper GUID handling.

### Setup in code

```csharp
using Unity.Cinemachine;
using UnityEngine;

public class CameraTargetSetter : MonoBehaviour
{
    [SerializeField] CinemachineCamera _cam;
    [SerializeField] Transform _player;

    void Start()
    {
        _cam.Follow = _player;
        _cam.LookAt = _player;
        _cam.Priority = 10;  // higher wins when multiple cameras are active
    }
}
```

Switching cameras is by priority: the active `CinemachineCamera` with the highest `Priority` wins. The `CinemachineBrain` (on the actual Unity Camera) blends between them per its blend settings.

### Camera shake — Impulse

For hit reactions, explosions, footsteps:

1. Add a **CinemachineImpulseSource** to anything that can shake the camera (an explosion prefab, the player on landing).
2. Add a **CinemachineBasicMultiChannelPerlin** component or use the Impulse Listener Extension on the camera.
3. Call `_impulseSource.GenerateImpulse(Vector3.up * 0.5f)` at the moment of impact.

Distance-based falloff and signal channels keep impulses from globally affecting every camera.

### Common patterns

**Third-person camera:**
- One `CinemachineCamera` with `CinemachineThirdPersonFollow` + `CinemachineRotationComposer` (or `CinemachinePanTilt` for direct mouse control).
- `Follow` and `LookAt` set to the player.
- `CinemachineDeoccluder` on the camera to push it forward when something gets between camera and player.

**First-person camera:**
- A simple `CinemachineCamera` parented under the player's head bone, no follow/lookat.
- Mouse-driven rotation via `CinemachinePanTilt`.

**Cutscene camera:**
- `CinemachineCamera` with high priority during the cutscene. Set its priority to 0 (or destroy it) when done; the gameplay camera takes over.
- For paths: `CinemachineSplineDolly` follows a `SplineContainer`.

### Pitfalls

- **Mixing 2.x and 3.x.** If your project has any Cinemachine 2.x assets (prefabs, animations referencing `CinemachineVirtualCamera`), the Cinemachine Upgrader (Window → Cinemachine → Upgrade) converts them. Don't hand-edit — the upgrader handles GUIDs and references.
- **Stale tutorials.** Anything pre-Unity-6 uses the old API. The Unity manual for the version of Cinemachine bundled with Unity 6.4 is correct; older blog posts are not.
- **`Camera.main` and Cinemachine.** The Unity Camera with the `CinemachineBrain` on it is the actual camera. Cinemachine cameras are not real cameras; they instruct the brain. `Camera.main` returns the brain camera; don't try to find Cinemachine cameras with it.

## Timeline

For scripted sequences (cutscenes, choreographed events), **Timeline** lets you author tracks (animation, audio, activation, custom signals) on a timeline asset and play it via `PlayableDirector`. Cinemachine has a `CinemachineShot` track type that switches between cameras on a Timeline.

Timeline is overkill for a 2-second hit-pause but the right tool for full cutscenes or scripted intros.

## Common pitfalls

- **String parameter calls in `Update`.** Use hashes (`Animator.StringToHash`) for parameters set every frame.
- **Forgetting to turn off "Has Exit Time".** Causes gameplay transitions to feel laggy or weirdly delayed.
- **Mixing root motion and code-driven movement.** Decide per-state which owns position. If both write, the result is unpredictable.
- **Animator transitions interrupting things you didn't intend.** Check Interruption Sources on the source state — "None" is the strictest, anything else allows interruption.
- **Cinemachine 2.x patterns in 6.4.** The renames are mechanical but easy to get wrong if you cargo-cult from old code. Verify component names against the Unity 6.4 package docs.
- **Authoring an Animator graph that's effectively procedural.** If your transitions need 10 conditions and 5 layers to model a state machine, consider a code state machine driving the Animator with parameters, not the Animator graph itself.
