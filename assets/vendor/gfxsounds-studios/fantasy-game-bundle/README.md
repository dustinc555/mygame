# Fantasy Game SFX Bundle

Purchased GfxSoundsStudios library from Sonniss. These are licensed vendor recordings, not project-authored audio.

## Adoption status

**Selective gameplay adoption.** `metadata/SELECTED_AUDIO.json` records the active combat/Rustdead, UI, merchant-trade, continuous fire, door and food-eating selections. Ordinary UI uses only the audition-approved Button click and Switch off 2 (menu close only), with no variation. Successful merchant trades replace the button click with Dustin's selected Coin pickup handling 2 when silver changes hands, or Inventory clothes shuffle for zero-silver barter; failed trades are silent. Doors use Dustin's selected Wooden door close recording for both opening and closing, at fixed pitch. Food-item consumption chooses among all eight `FOODEat` recordings at the eater's position, without immediate repeats; drinking clips are not included. The original vendor WAV bytes are preserved. Combat, runtime UI, explicitly authored fire furniture, doors and eating consume these selections; the rest of the library is not adopted. Previously imported punch and rejected UI variants remain as unused local files, but have no gameplay references and are excluded from the active manifest; do not rehydrate them as active sounds.

The complete purchased library remains outside the project. This selection was extracted from `/home/dustin/.hermes/attachments/Fantasy Game Bundle-2.zip`, byte-identical to the recorded original `Fantasy Game Bundle.zip`. Select and import only sounds actually needed for gameplay; do not restore the entire library into the Godot project.

Successful unlocking also uses the five recordings in
`Foley Interactions/Doors Locks Mechanisms/Locks Keys Chains` whose basenames
contain `unlock` or `open`, including `opening`. They were selected by Dustin's
filename rule, with source bytes unchanged and mono/trimmed/nonlooping Godot
imports. One random recording plays on confirmed unlocking, not ordinary opening
or state restoration. The shared Inspector resource is
`features/lockpicking/resources/unlock_success_sound.tres` (Paths, Volume Db and
Playback controls); see `features/lockpicking/README.md` for event ownership.

## Purchased archive contents

| Vendor category | WAV files |
| --- | ---: |
| Combat Weapons | 185 |
| Creatures And Monsters | 707 |
| Environment Ambience | 48 |
| Foley Interactions | 152 |
| Footsteps | 130 |
| Hero Voices | 39 |
| Magic Spells | 161 |
| Music Stingers | 36 |
| UI Feedback | 47 |
| **Total** | **1,505** |

- `metadata/MANIFEST.csv` inventories the complete purchased archive: original ZIP member paths, SHA-256, byte counts, categories, and source audio formats. Its `path` column describes possible destinations, not adoption of every listed file. Its folder has `.gdignore` so Godot does not mistake this inventory for CSV translations.
- `metadata/SELECTED_AUDIO.json` is the exact adopted subset, including ZIP members, unchanged source hashes, current source/destination format and duration, and the authored cue resources using each recording. Rehydrate this subset on the owner's licensed machine after a fresh checkout.
- `LICENSE_RECORD.md` records provenance, purchase price, and license obligations.
- Original audio: 1,439,915,020 bytes. The supplied ZIP contains only WAV files, with no bundled license document.

## Selective Godot use

For an approved gameplay sound, extract only the chosen WAV from the preserved ZIP into `res://assets/vendor/gfxsounds-studios/fantasy-game-bundle/audio/`, preserving its vendor category and filename. Verify its source hash against the manifest. Let Godot import that selected file, then assign its path to the relevant gameplay audio resource. Keep the selected manifest synchronized when changing adoption.

In Godot's **Import** dock, use original sample rate, 16-bit PCM (`Compress / Mode = Disabled`), **Trim** enabled, **Normalize** disabled, and **Edit / Loop Mode = Disabled**. Spatial combat/fire clips use **Force / Mono**; UI clips retain stereo. Fire cues prepare cached, crossfaded looping duplicates at runtime without changing shared source streams. A vendor filename containing `loop` is not proof that Godot looping is enabled.

## Gameplay authoring

- Combat volume, distance, critical emphasis and voice cap: `features/combat/resources/audio/default_combat_audio_settings.tres`.
- Combat recordings: `features/combat/resources/audio/default_combat_sound_bank.tres`.
- Equipment classification: open an item `.tres` in `features/inventory/resources/items/`, then **Inspector → Combat Audio**. Shared profiles separate striking, guarding and worn materials.
- UI recordings, volume and polyphony: `features/ui/resources/ui_audio_settings.tres`.
- Fire: select **FireAudio** in the authored fixture scene; shared recordings, ranges and budget are in `features/audio/resources/fire_audio_settings.tres`.
- Doors: select a door, then **Inspector → Door Audio → Movement Sound → Volume Db**. The default cue is `features/doors/resources/wooden_door_movement_sound.tres`; editing it changes all doors using that shared resource. Make it unique for a per-door override, or clear Movement Sound to silence that door. **Sound Max Distance M** and **Sound Unit Size M** tune listener cutoff and attenuation. Edits apply on the next transition; saved edits require reloading an already-running scene. Opening and closing start one positional voice; lock-only changes, failed commands, state restoration and editor previews are silent.
- Eating: open `features/inventory/resources/food_eating_sound.tres` for recordings and **Volume Db**; open `features/inventory/projection/food_eating_audio.tscn` for **Max Distance** and **Unit Size**. All successful food-item actions share this cue, including automatic meals. See `features/inventory/resources/food_eating_audio.md` for timing and lifecycle details.

See the READMEs beside those resources for ownership, timing and fallback rules. Combat/fire selections were inferred from vendor names and measured durations, not subjective audition; ordinary UI recordings were selected by Dustin after audition, and the two merchant-trade recordings were supplied by exact local path. Punch sounds and their blunt/bone/stone proxies have been removed from gameplay without replacement; armor contacts and the requested Rustdead sounds remain. `FGHTImpt_Hard punch impact 3_GfxSounds_FantasyGameBundle .wav` is specifically banned game-wide following Dustin's audition. Cloth/leather share soft-contact families. No magical UI, portrait-selection, inventory-drag, footsteps, loot sounds or general environmental ambience are wired.

## Local-only asset policy

The selected `audio/` directory and its `.import` sidecars are excluded from Git to prevent accidental uploads of licensed recordings. Godot's `.godot/` cache is also ignored. Only this documentation and the manifests are suitable for repository tracking; do not force-add the licensed recordings or upload the raw library.

A fresh checkout includes these records, not the purchased sounds. Rehydrate only the clips explicitly adopted by gameplay, not the entire bundle. Keep private proof of purchase outside the repository. See the license record before sharing assets or adding collaborators.
