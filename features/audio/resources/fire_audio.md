# Fire furniture audio

## Human tuning

Open `features/world/projection/props/lighting/wall_torch.tscn`,
`features/camps/projection/fire_pit.tscn`, `features/camps/projection/campfire_tripod.tscn`,
or `features/world/bridge/props/body_furnace.tscn`. Select **FireAudio** in the scene tree.
For an instance, enable **Editable Children** to override that child and save the containing scene.

- **Fire Kind**: Silent, Small Flame, or Campfire. Silent disables only audio, never light/fire rules.
- **Fire Level Db**: a per-instance offset, -40 to +6 dB. Zero retains the shared mix.
- Child position is the actual sound origin; keep it at the flame, not a building's root.

Open `features/audio/resources/fire_audio_settings.tres` in FileSystem/Inspector for shared tuning:
Small Flame/Campfire cue resources hold recordings, base volume and pitch range.
Wall torches (the currently authored Small Flame fixtures) use -11.9382 dB: 80% of the
previous -10 dB linear gain. Their cutoff is 6 m, half the previous range. They retain
one linear distance fade without the native muffling filter; no stacked inverse-distance loss.
Distance is measured from the audio listener/camera, not from the selected character.
Campfires/furnace burns retain -10 dB, a 33 m cutoff, inverse-distance attenuation with a
1 m unit size, and the native -24 dB filter. **Unit Size M** affects that campfire mix only.
These are measured playback settings, not a claim of subjective audition. The `SFX` bus
falls back to Master if absent. Raise/lower **Small Flame → Volume Db** for all torches,
or **FireAudio → Fire Level Db** for one instance; range is **Small Flame Distance M**.

**Voice Budget** defaults to eight simultaneous fire loops per viewport, reconsidered every
0.25 real seconds. Only explicitly registered, lit fixtures participate; no world/node scan or
per-frame script runs. An already-playing fire gets a small distance-ranking preference so
similar-distance fixtures do not repeatedly exchange voices. No listener, disabled viewport audio,
or a listener beyond the cutoff means no playback. Current AudioListener3D takes priority;
otherwise the viewport's current Camera3D supplies listener position.

Saved edits apply on the next scene launch/realization. In the Remote Inspector, level, radius,
and budget edits apply at the next budget refresh without restarting an existing loop. Kind
changes reselect the cue. Recording/pitch/loop-preparation edits require re-realizing the fixture;
changing source imports requires reimporting and reloading, not an automatic live file watcher.

## Ownership and scope

`LightFixture._set_lit` emits its actual semantic state, preserving WorldTimeController's night
window and Always On override. `BodyFurnace._set_burn_effect_active` emits only during its existing
body-burn effect. The audio child subscribes to those transitions; visual LOD, glow visibility,
building cutaways and model names are never treated as fire-state authority. Extinguishing/daytime
stops immediately. Tree exit unregisters/stops; re-entry binds once to current state. Scene pause
uses native stream pause/resume, not repeated replay. Audio neither consumes fuel nor creates fire.

The reusable child accepts only parents with `is_fire_active()` and `fire_active_changed(bool)`.
A first child creates one disposable `FireAudioVoices` helper in its Viewport; this contains no
persistent simulation state and its timer stops when no lit emitters remain. The helper is local
projection voice ownership, not a bootstrap service or new world simulation controller.

The authored scope is the stationary wall torch, both canonical campfire wrappers, and the body
furnace while actually burning. This checkout has no separately authored lantern/hearth/fireplace
scene; do not add audio to a raw lantern-shaped model without a real activation owner. A future
lit lantern can reuse Small Flame under LightFixture. Existing candles are deliberately unchanged.
There are no lighting/extinguishing one-shots, equipment torches, footsteps, forest ambience,
fauna, weather or unrelated furniture sounds.

## Exact local licensed recordings and loop contract

Under `assets/vendor/gfxsounds-studios/fantasy-game-bundle/audio/`:

- `Foley Interactions/Lanterns Torches/FIRETrch_Torch fire crackle_GfxSounds_FantasyGameBundle.wav`
- `Environment Ambience/Dragon Crater Ambience/FIREBurn_Quiet campfire burn_GfxSounds_FantasyGameBundle.wav`
- `Environment Ambience/Dragon Crater Ambience/FIREBurn_Quiet campfire burn 2_GfxSounds_FantasyGameBundle.wav`

Keep originals unchanged. Import as mono, uncompressed 16-bit PCM, trim silence, and set the importer
**Edit / Loop Mode = Disabled** (`edit/loop_mode = 1`, distinct from the stream's runtime enum).
Missing licensed files and unsupported compressed formats are silent rather than resource errors.
No sidecars are hand-edited by the runtime component.

`fire_loop_cue.gd` caches a prepared duplicate of each decoded recording, strips 0.5 s from both
ends, and crossfades the last 80 ms into the first 80 ms. Playback begins at a randomized interior
position. The duplicate's actual `AudioStreamWAV.loop_mode` is `LOOP_FORWARD`; its begin/end points
exclude the discarded edges and avoid replaying the head twice. The original source and shared
GameSoundCue stream remain unchanged. Tune **Edge Trim Seconds** and **Crossfade Seconds** on each
fire cue, then re-realize. Mechanical seam continuity is tested; perceptual loop/mix approval still
requires listening in gameplay.

## Verification

`./tests/run.sh unit -gselect=fire_audio` exercises native AudioStreamPlayer3D playback, production
scene children and semantic clock/burn transitions with test-owned PCM, including source immutability,
loop points, pause, tree re-entry, missing files, listener changes, kind/level tuning and the voice cap.
The small-flame regression captures actual mixed audio at near, 4 m, 5.5 m and the 6 m cutoff;
an AudioStreamPlayer3D merely reporting `playing` cannot pass this audibility regression.
This is not rendered performance proof or subjective audition. Licensed import validation is separate.
