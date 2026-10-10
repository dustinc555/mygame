# Combat audio

## Authoring

In Godot's FileSystem, open `features/combat/resources/audio/default_combat_audio_settings.tres` in the Inspector. `Enabled`, `Volume Db`, `Critical Gain Db`, `Max Distance M`, `Unit Size M`, and `Max Voices` control combat mixing and cost. The defaults are a 35 m camera-distance admission limit, 5 m attenuation unit, 24 voices, -4 dB overall gain and +1.5 dB critical contact emphasis. Gain is added to each cue's own gain. Runtime resource edits apply to the next event; shrinking the pool removes excess voices on the next playable cue. Pause discards playing combat sounds rather than resuming stale impacts. These projection settings are not save-game state.

Open `default_combat_sound_bank.tres` to edit ordinary shared **GameSoundCue** subresources: recording paths, gain, and bounded pitch variation. Paths are strings, not WAV preloads. Missing licensed files are silent, so a fresh checkout still loads. No raw audio is copied by these scripts. The vendor asset family's `README.md` and `metadata/SELECTED_AUDIO.json` describe licensed rehydration and source hashes.

## Production path and ownership

`GameCombatResolutionSystem._try_start_slot_action` emits the **swing** start edge immediately after the accepted `_start_action`; audio uses this edge only for the retained armed-Rustdead vocal, never whooshes or natural bite/scratch sounds. `_resolve_action_impact` emits **dodge** only for a delivered `dodged` outcome, or **contact** for a delivered hit/block. Its existing action flag guarantees one resolved edge, including zero-damage blocks. Lost targets, physical obstruction, rejected reception, cancellation and out-of-leash resolution never produce a whoosh or contact. An armed creature attack can retain its vocal if its later impact is refused. No combat timings, RNG draws, damage or defense rules were changed.

The registered system forwards an immutable value-only event through `GecsWorldController.combat_audio_event`. `CombatAudioController` receives that service from the injected BootstrapContext and reads live equipment only on those edges. It never scans actors per frame or subscribes to the legacy node-side attack path. `features/combat/combat_module.gd` declares the projection service, installed by `GameBootstrap`.

Each event carries stable IDs, source projection instance ID, action sequence, actual attack ID, critical/outcome/shield flags, and captured GECS positions. The controller resolves disposable actors synchronously and immediately converts traits to values. Players retain only streams and positions. A bounded 256-event history handles duplicate deliveries; instance IDs distinguish a re-realized actor whose action sequence restarts. Reinitialization disconnects the old service and clears players/history; tree exit does likewise. The 3D pool lazily allocates up to the configured cap and replaces the oldest active voice at saturation. Finished streams are released, variants avoid immediate repetition, and distance is checked before stream loading.

## Material and Rustdead rules

- Weapon whooshes play only when the opponent's dodge resolves, not at attack start, on hits/blocks, or for other failures to connect. There is no generic unarmed whoosh. Armed Rustdead using weapon animations retain their existing female/male vocal at action start; it is not replayed on dodge.
- Natural Rustdead attacks follow the explicit IDs in `rustdead_combat_animation_set.tres`: `claw` is **Zombie_Scratch**, `bite` is **Zombie_Bite**. Neither starts a vocal, punch, or movement sound. Scratch plays only its resolved contact, or the existing non-punch `swing_blade` whoosh on the opponent's actual dodge. Bite plays **Zombie infected bite 2/3/5/6** only on flesh contact; armor/guards get only their own material contact, and a dodged bite stays silent. Cloth/leather bite contact is silent because no separate soft-armor bite recording is approved; do not invent flesh penetration. Natural attack identity takes precedence over equipment changed during windup, so teeth/claws cannot become axe strikes or metal/metal parries.
- A block reads offhand **guard_surface** when authoritative `has_shield` is true, otherwise weapon **guard_surface**. A steel/steel weapon parry requires a metallic attacker **strike_surface** too; a wooden spear shaft is not confused with its metal tip. Shields use the armor-impact family rather than sword-parry recordings.
- Ordinary body hits use the first classified item in `chest`, then `undershirt`, then the configured body surface. Boots, helmets, gloves and leggings never turn torso hits metallic. This is an explicit torso approximation, not invented hit-location or armor-penetration simulation.
- Plate/metal, chainmail and wood retain their material contacts, including when struck by an unarmed attacker. Cutting soft contacts use slash/stab or axe families; scratch retains the existing `impact_slash` flesh-contact family, not a new claw recording. Cloth/leather share cutting soft-contact families rather than bespoke recordings; the flesh-only bite exception is above. Generic unarmed soft contact, blunt/tool soft contact and exposed bone/stone contact are silent: their former punch proxies were removed without replacement. Metal and chain recordings are reused across attack families where the library lacks a dedicated matchup; no claim of an auditioned perfect match is made.
- Generic unarmed sounds are outside the approved scope. Do not restore punch swings or impacts as creature, weapon, bone or stone fallbacks. `FGHTImpt_Hard punch impact 3_GfxSounds_FantasyGameBundle .wav` was auditioned and rejected by Dustin as cartoonish and is banned game-wide. Preserve vendor originals; exclusion is from gameplay and the active selection manifest.
- Criticals add only the configured modest gain to the same contact cue. They do not bypass armor, substitute flesh for metal, or invent a second penetration layer.
- `Stab Attack Ids` is an exact-ID authoring list, not filename matching. Default humanoid attacks currently use `one_hand_light_a/b` (slash family). The authored stab bank is available for configured thrust actions; this feature does not add new attack animations or projectile simulation.

## Selection evidence and limitations

The source archive is `/home/dustin/.hermes/attachments/Fantasy Game Bundle-2.zip`. The exact adopted subset is recorded in `assets/vendor/gfxsounds-studios/fantasy-game-bundle/metadata/SELECTED_AUDIO.json`. The table below records source WAV durations measured as frame count / sample rate, rounded to milliseconds; imported silence-trimmed durations are in that manifest. Imported paths preserve the archive member after removing `Fantasy Game Bundle/`, underneath `res://assets/vendor/gfxsounds-studios/fantasy-game-bundle/audio/`.

Selection used archive names and measured duration. **These clips were not auditioned**: this is not a sound-quality or subjective mix approval. Named combos, double clashes, ambience, doors, feeding/eating, and long vocal sequences were excluded. Synthetic WAV tests exercise actual native AudioStreamPlayer3D playback, natural completion, layering, limits, pause and teardown without needing licensed source files. Composition-root integration is separately covered by `test_audio_integration.gd`. These checks do not establish an audible production-world mix, spatial balance in a large fight or rendered performance.

| Cue | Archive member (under `Fantasy Game Bundle/`) | Seconds |
|---|---|---:|
| `swing_blade` | `Combat Weapons/Swords/Sword Swings Unsheathes/WEAPSwrd_Sword swing accent_GfxSounds_FantasyGameBundle.wav` | 0.334 |
| `swing_blade` | `Combat Weapons/Swords/Sword Swings Unsheathes/WEAPSwrd_Sword swing accent 2_GfxSounds_FantasyGameBundle.wav` | 0.200 |
| `swing_heavy` | `Combat Weapons/Battle Axes/Axe Swings/WEAPAxe_Battle axe swing_GfxSounds_FantasyGameBundle.wav` | 0.400 |
| `swing_heavy` | `Combat Weapons/Battle Axes/Axe Swings/WEAPAxe_Battle axe swing 2_GfxSounds_FantasyGameBundle.wav` | 0.367 |
| `swing_heavy` | `Combat Weapons/Battle Axes/Axe Swings/WEAPAxe_Battle axe swing 3_GfxSounds_FantasyGameBundle.wav` | 0.367 |
| `clash_metal` | `Combat Weapons/Swords/Sword Clashes Parries/WEAPSwrd_Single sword clash_GfxSounds_FantasyGameBundle.wav` | 0.601 |
| `clash_metal` | `Combat Weapons/Swords/Sword Clashes Parries/WEAPSwrd_Single sword clash 2_GfxSounds_FantasyGameBundle.wav` | 0.367 |
| `clash_metal` | `Combat Weapons/Swords/Sword Clashes Parries/WEAPSwrd_Single sword clash 3_GfxSounds_FantasyGameBundle.wav` | 0.567 |
| `clash_metal` | `Combat Weapons/Swords/Sword Clashes Parries/WEAPSwrd_Single sword clash 4_GfxSounds_FantasyGameBundle.wav` | 0.901 |
| `impact_metal` | `Combat Weapons/Swords/Sword Scrapes Shields/WEAPSwrd_Sword armor shield hit_GfxSounds_FantasyGameBundle.wav` | 0.801 |
| `impact_metal` | `Combat Weapons/Swords/Sword Scrapes Shields/WEAPSwrd_Sword armor shield hit 3_GfxSounds_FantasyGameBundle.wav` | 1.235 |
| `impact_metal` | `Combat Weapons/Swords/Sword Scrapes Shields/WEAPSwrd_Sword armor shield hit 4_GfxSounds_FantasyGameBundle.wav` | 0.968 |
| `impact_chain` | `Combat Weapons/Battle Axes/Axe Impacts/WEAPAxe_Battle axe chain armor hit_GfxSounds_FantasyGameBundle.wav` | 0.834 |
| `impact_chain` | `Combat Weapons/Battle Axes/Axe Impacts/WEAPAxe_Battle axe chain armor hit 2_GfxSounds_FantasyGameBundle.wav` | 0.834 |
| `impact_wood` | `Combat Weapons/Battle Axes/Axe Impacts/WEAPAxe_Battle axe wood impact_GfxSounds_FantasyGameBundle.wav` | 1.535 |
| `impact_wood` | `Combat Weapons/Battle Axes/Axe Impacts/WEAPAxe_Battle axe wood impact 2_GfxSounds_FantasyGameBundle.wav` | 1.535 |
| `impact_slash` | `Combat Weapons/Swords/Sword Impacts Gore/WEAPSwrd_Sword body hit swipe_GfxSounds_FantasyGameBundle.wav` | 1.068 |
| `impact_slash` | `Combat Weapons/Swords/Sword Impacts Gore/WEAPSwrd_Sword body hit swipe 3_GfxSounds_FantasyGameBundle.wav` | 1.401 |
| `impact_slash` | `Combat Weapons/Swords/Sword Impacts Gore/WEAPSwrd_Sword body hit swipe 4_GfxSounds_FantasyGameBundle.wav` | 0.934 |
| `impact_stab` | `Combat Weapons/Swords/Sword Impacts Gore/WEAPSwrd_Sword stab gore 2_GfxSounds_FantasyGameBundle.wav` | 1.368 |
| `impact_stab` | `Combat Weapons/Swords/Sword Impacts Gore/WEAPSwrd_Sword stab gore 3_GfxSounds_FantasyGameBundle.wav` | 1.401 |
| `impact_axe` | `Combat Weapons/Battle Axes/Axe Impacts/WEAPAxe_Battle axe body impact_GfxSounds_FantasyGameBundle.wav` | 0.567 |
| `impact_axe` | `Combat Weapons/Battle Axes/Axe Impacts/WEAPAxe_Battle axe body impact 3_GfxSounds_FantasyGameBundle.wav` | 0.934 |
| `zombie_male` | `Creatures And Monsters/Undead/Zombie/Attacks/CREAHmn_Male zombie attack_GfxSounds_FantasyGameBundle.wav` | 1.235 |
| `zombie_male` | `Creatures And Monsters/Undead/Zombie/Attacks/CREAHmn_Male zombie attack 2_GfxSounds_FantasyGameBundle.wav` | 0.934 |
| `zombie_male` | `Creatures And Monsters/Undead/Zombie/Attacks/CREAHmn_Male zombie attack 3_GfxSounds_FantasyGameBundle.wav` | 0.901 |
| `zombie_female` | `Creatures And Monsters/Undead/Zombie/Attacks/CREAHmn_Female zombie attack_GfxSounds_FantasyGameBundle.wav` | 1.401 |
| `zombie_female` | `Creatures And Monsters/Undead/Zombie/Attacks/CREAHmn_Female zombie attack 3_GfxSounds_FantasyGameBundle.wav` | 1.101 |
| `zombie_female` | `Creatures And Monsters/Undead/Zombie/Attacks/CREAHmn_Female zombie attack 5_GfxSounds_FantasyGameBundle.wav` | 1.168 |
| `zombie_bite` | `Creatures And Monsters/Undead/Zombie/Bites and Feeding/CREAHmn_Zombie infected bite 2_GfxSounds_FantasyGameBundle.wav` | 0.868 |
| `zombie_bite` | `Creatures And Monsters/Undead/Zombie/Bites and Feeding/CREAHmn_Zombie infected bite 3_GfxSounds_FantasyGameBundle.wav` | 1.068 |
| `zombie_bite` | `Creatures And Monsters/Undead/Zombie/Bites and Feeding/CREAHmn_Zombie infected bite 5_GfxSounds_FantasyGameBundle.wav` | 0.801 |
| `zombie_bite` | `Creatures And Monsters/Undead/Zombie/Bites and Feeding/CREAHmn_Zombie infected bite 6_GfxSounds_FantasyGameBundle.wav` | 0.868 |

## Focused regression command

Serialize engine work with the shared audio lock:

```sh
flock -w 120 /home/dustin/.hermes/cache/scratch/mygame-godot-audio.lock timeout 120 ./tests/run.sh unit -gselect=combat_audio
```

Run the complete unfiltered unit suite before handoff. Native licensed-stream loading/playback and production-world listening/performance checks are distinct from a focused synthetic-stream regression run.
