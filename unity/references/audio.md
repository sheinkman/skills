# Audio

Load this reference when adding sound to a Unity project — sound effects, music, ambience, voice. The Unity audio system is small in API surface but the patterns are non-obvious, and most projects re-implement them badly.

## The two building blocks

- **`AudioClip`** — the imported audio asset.
- **`AudioSource`** — a component that plays a clip. Has 3D position, volume, pitch, spatial blend.
- **`AudioListener`** — usually on the main camera. There's only one active per scene. Don't put multiple, the second is silently ignored.

The whole rest of the system (mixer, snapshots, 3D, occlusion) is layered on top.

## Import settings that matter

Unity's audio import defaults are conservative. For a tight ship, set these per category:

- **Short SFX (footsteps, gun fires, UI clicks)** — Load Type: Decompress On Load. Compression Format: Vorbis (small, fast). Quality ~70%. Force To Mono if the original is mono. Always Force To Mono for any 3D-spatialized sound (stereo defeats spatialization).
- **Long ambient loops / music** — Load Type: Streaming. Compression Format: Vorbis. Don't load these into memory; stream from disk.
- **One-shot voice lines** — Load Type: Compressed In Memory. Decompresses on play; saves RAM at the cost of a small CPU hit per play.

Setting these consistently via `AssetPostprocessor` (see `references/editor-tooling.md`) is what teams do once the project grows past 20 audio files.

## AudioSource basics

```csharp
[SerializeField] AudioSource _source;
[SerializeField] AudioClip _hitClip;

void OnHit()
{
    _source.PlayOneShot(_hitClip, volumeScale: 1f);
}
```

`PlayOneShot` vs `Play`:
- **`Play()`** — replaces whatever the source is currently playing. Use for music tracks, looping ambience.
- **`PlayOneShot(clip)`** — overlays the clip on top of whatever's playing. Allocates an internal voice. Use for SFX that should layer.

**Pitch variation cheap trick** for repeated SFX (footsteps, gunfire, hits):

```csharp
_source.pitch = Random.Range(0.92f, 1.08f);
_source.PlayOneShot(_clip);
```

Three lines, instantly less robotic. The cost-to-quality ratio of pitch randomization is unmatched.

## SFX pooling

`AudioSource.PlayClipAtPoint(clip, position)` is convenient and creates a one-shot GameObject that destroys itself when done. **Don't use it in hot paths** — it allocates a GameObject + AudioSource every call, then destroys them. GC churn and Awake costs.

Better: a small pool of AudioSources you can grab, play, and release:

```csharp
public class AudioPool : MonoBehaviour
{
    [SerializeField] AudioMixerGroup _sfxGroup;
    [SerializeField] int _voiceCount = 16;

    AudioSource[] _sources;
    int _next;

    void Awake()
    {
        _sources = new AudioSource[_voiceCount];
        for (int i = 0; i < _voiceCount; i++)
        {
            var go = new GameObject($"Voice_{i}");
            go.transform.SetParent(transform);
            var s = go.AddComponent<AudioSource>();
            s.outputAudioMixerGroup = _sfxGroup;
            s.playOnAwake = false;
            _sources[i] = s;
        }
    }

    public void PlayAt(AudioClip clip, Vector3 position,
                       float volume = 1f, float minPitch = 0.95f, float maxPitch = 1.05f)
    {
        var s = _sources[_next];
        _next = (_next + 1) % _sources.Length;

        s.transform.position = position;
        s.clip = clip;
        s.volume = volume;
        s.pitch = Random.Range(minPitch, maxPitch);
        s.spatialBlend = 1f;
        s.Play();
    }
}
```

Round-robin reuse means a new SFX may interrupt a still-playing one when you exceed voice count — usually fine for short SFX. For long sounds (voice lines), find a free source or grow the pool.

## 3D audio

Spatial Blend on an AudioSource: 0 = pure 2D (UI sounds, music), 1 = pure 3D (positioned in world). Anything between mixes — 0.3 is a common value for "mostly 2D with a hint of positional feel" used for first-person weapons.

3D audio falloff is controlled by the **Volume Rolloff curve** (Logarithmic Rolloff by default). Custom rolloff lets you author exactly how distance affects loudness — important for an isometric game where the camera is fixed at a distance from sources. Default settings often make sounds too quiet at gameplay distances; tune the rolloff curve.

For isometric games specifically: set the **AudioListener** on a child of the main camera positioned at the *player's* location, not the camera's. Otherwise everything sounds distant. Common pattern:

```csharp
public class PlayerListener : MonoBehaviour
{
    void Awake()
    {
        // Move the listener from the camera to here on game start.
        var oldListener = FindAnyObjectByType<AudioListener>();
        if (oldListener != null && oldListener.gameObject != gameObject)
            Destroy(oldListener);
        gameObject.AddComponent<AudioListener>();
    }
}
```

## AudioMixer — the routing system

The AudioMixer asset is where mixing, ducking, and bussing happen. Create it via Assets → Create → Audio Mixer. The default setup gives you a Master group; add child groups for Music, SFX, Voice, UI, Ambience, etc.

Every AudioSource in your project routes to a Mixer Group via its `Output` field. Without this, audio is unmixed and you can't control category volume.

### Exposed parameters — programmable mix

In the Mixer, right-click any parameter (volume, pitch, send) and choose **Expose to Script**. Then in code:

```csharp
[SerializeField] AudioMixer _mixer;

public void SetMusicVolume(float linear01)
{
    // Mixer expects dB. Convert linear 0..1 to dB (-80..0).
    float db = linear01 > 0.0001f ? Mathf.Log10(linear01) * 20f : -80f;
    _mixer.SetFloat("MusicVolume", db);
}
```

The `Mathf.Log10(x) * 20` conversion is essential — a linear slider feels right only when fed to a logarithmic dB scale. Without it, the bottom 80% of the slider does nothing perceptible.

Bind these exposed parameters to UI sliders for the settings menu. Persist via `PlayerPrefs` (see `references/saves-and-data.md`).

### Snapshots — instant mix states

A **snapshot** is a complete mix state (all volumes, pitches, sends). You can blend between snapshots smoothly:

```csharp
[SerializeField] AudioMixerSnapshot _calmSnapshot;
[SerializeField] AudioMixerSnapshot _combatSnapshot;

public void EnterCombat()  => _combatSnapshot.TransitionTo(0.5f);
public void ExitCombat()   => _calmSnapshot.TransitionTo(2.0f);
```

Snapshots are the right tool for music states, paused-game muffling, underwater filtering, "you got hit hard" momentary deafening. Author the mix once in the inspector, trigger transitions in code.

### Ducking — music gets quieter when dialogue plays

Set up via the Mixer:
1. On the Music group, add a **Send** effect targeting the Voice group's input (or use a Duck Volume effect).
2. On the Music group, add a **Duck Volume** effect; set its sidechain to the Voice group.
3. Tune Threshold, Ratio, Attack, Release in the inspector.

Now when anything plays through Voice, Music automatically drops. No code required.

## Music systems for an isometric game

Common pattern for action-RPG-style games: **layered music**.

- One AudioSource per layer (e.g., "drums", "lead", "tension"), all playing in sync from the start, each at its own volume.
- Combat starts → fade the "tension" layer up, others stay.
- Boss → fade in a separate "boss melody" track, fade out tension.

Implementation:

```csharp
public class MusicLayer : MonoBehaviour
{
    [SerializeField] AudioSource _source;
    [SerializeField] float _fadeSeconds = 1f;

    Coroutine _fade;

    public void FadeTo(float targetVolume)
    {
        if (_fade != null) StopCoroutine(_fade);
        _fade = StartCoroutine(FadeRoutine(targetVolume));
    }

    IEnumerator FadeRoutine(float target)
    {
        float start = _source.volume;
        float t = 0;
        while (t < _fadeSeconds)
        {
            t += Time.deltaTime;
            _source.volume = Mathf.Lerp(start, target, t / _fadeSeconds);
            yield return null;
        }
        _source.volume = target;
    }
}
```

For richer needs (cue-based transitions on musical bars, stinger overlays), middleware like FMOD or Wwise is the answer — both have Unity integrations and are standard for AAA. For small teams shipping on Steam, native Unity audio + snapshots covers most cases without the dependency.

## Audio occlusion (simple)

For isometric, walls between camera and sound source aren't usually a concern, but for first-person you may want sounds to be muffled when blocked. Simple version:

```csharp
void Update()
{
    bool occluded = Physics.Linecast(transform.position, _listener.position, _wallMask);
    _lowpass.cutoffFrequency = occluded ? 800f : 22000f;
    _source.volume = occluded ? 0.5f : 1f;
}
```

`AudioLowPassFilter` is a built-in component you add alongside the AudioSource. Real occlusion (per-portal, multi-path) is much more complex and usually deferred to middleware.

## Common pitfalls

- **Stereo SFX with 3D spatialization.** Audio gets mixed to mono for spatialization but the import keeps stereo channels — wastes memory and disables spatial effects. Force To Mono on import.
- **Linear volume on dB sliders.** A 50% volume slider should feel like "half as loud", not "1/10000th as loud". Convert linear to dB with `Log10(x) * 20`.
- **`PlayClipAtPoint` in hot paths.** Allocates a GameObject every call. Pool instead.
- **Forgetting to assign Mixer Group on every AudioSource.** Sounds that bypass the mixer can't be category-muted by the settings menu.
- **AudioListener on the camera in an isometric game.** Distance falloff is calculated from the listener; if it's 15 meters above the scene, every sound is "far". Move the listener to the player.
- **Long uncompressed music loaded into memory.** A 3-minute uncompressed stereo track is ~30 MB in RAM. Stream it; don't load it.
- **`AudioSource.isPlaying` polling every frame to chain logic.** Use an `Awaitable` that waits for `clip.length` seconds, or a coroutine, instead.
- **Music that doesn't loop seamlessly.** Loop points need to be sample-accurate. Use a DAW to author seamless loops; pure Unity doesn't have a great loop-point editor.
