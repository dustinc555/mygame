# Outfitter

Run `godot --path /home/dustin/mygame res://tools/outfitter/outfitter.tscn`, or open this scene and press F6. It does not change the project's main scene or write gameplay/save data.

Choose a race, an authored sex/body, an equipment slot, then an item. **Only items for the selected slot appear; search stays within that slot.** Gray rows explain body/race incompatibility when clicked/hovered. None removes the selected slot. Compatible loadout choices survive body/race changes; incompatible retained choices are not forcibly equipped. The **Build** selector offers Regular / Heroic / Teen where saved variants exist. One shared body is presented once, not as invented male/female anatomy.

The large isolated viewport has drag orbit, wheel zoom, full-body and tracked left/right-hand views. Selecting a production animation loops it automatically. Its name survives equipment rebuilds and actor changes; clips absent from another actor are explicitly marked unavailable rather than silently replaced.

The right-side **Body proportions** panel has the character creator's **Height**, **Shoulders**, **Arm Length**, and **Neck Length** sliders, with the same -1 to 1 range. They update the live bones and attached clothing without replacing the actor, reloading equipment, or restarting animation. Values survive build/body changes for comparison; **Reset proportions** restores zero. These inspection values are not saved to gameplay characters. Controls are disabled for projections without humanoid bone customization.

## Shared clothing

The migrated wardrobe has 27 items: four traveler garments and 23 vendor items. Each uses one authored source `visual_scene` plus `clothing_binding`, not sex/build garment overrides. Six canonical human scenes select body-owned `wardrobe_profiles`; the seventh generated profile is the original male authoring reference. The production `ClothingFitter` generates and caches wearer meshes, while animation and the sliders above continue through the live skeleton without per-frame refitting. Future mesh-morph sliders need deformed cage input and cache invalidation; they are not automatic.

Authoring and single-item additions are documented in `tools/wardrobe/README.md`; the active traveler Blender source is `assets/items/equipment/traveler_outfit/source/male_regular.blend`. Older per-body exports are preserved references, not clothing models to maintain. Puglin has no wardrobe profile and currently exposes only weapon/offhand slots; QuadBot's unrelated rig is not human wardrobe support.

Review source-cut preservation, Idle/Walk, bends, slider extremes and independent slot swaps. Minor finger, boot and layering clipping remains; shared fitting is not a universal collision or layering guarantee. Technical checks do not replace visual approval. Cached reuse avoids recomputing a fit, but cold fitting still costs work; first equip is not guaranteed instant.

## Camera

Race/body changes retain camera focus, orbit, zoom and FOV. In hand view only the focus follows the replacement body's socket; missing sockets stop tracking at the last view and report the existing warning. Equipment rebuilds also retain the camera. The first body auto-frames; **Full body** explicitly reframes whenever requested.

The **Height ruler** toggle shows a narrow, separate strip beside the viewport; it cannot cover the character. Its ticks project actual world heights at the body's center through the current camera, so they follow orbit and zoom without a distant ruler's perspective mismatch. Feet use exactly 0.3048 meters. Zero and the studio floor use the unequipped body's foot-level bounds, captured before retained equipment is applied. Bounds set only the reference level and coverage, not an asserted exact actor height. Toggling it changes available viewport width without changing camera position, zoom, or FOV. No ruler geometry exists in the 3D world.

## Authority and bounded integration

- `outfitter_catalog.gd` discovers races through `PopulationAppearanceProfile._get_available_races()` and recursively discovers the same item resource directory used by world authoring. No hand-maintained item/race list or copied model/grip settings.
- Actor scripts come from matching saved population appearance profiles, preserving Rustdead and QuadBot specialized classes. Canonical humanoid bodies without a specialized population profile (currently Puglin) use the general production `HumanoidCharacter` actuator. Unsupported non-humanoid bodies fail closed. This is body-family selection, not race-specific equipment configuration.
- Script-created humanoid scaffolding delegates to `PopulationCharacterRealizer._ensure_projection_bootstrap()`. These existing helper methods are callable in GDScript; no shared code had to change.
- Saved race/body/grip resources are used by identity, with normal `EquipmentCapability` equip/unequip and actual production `BodyProjection` visuals. No monster-pack preview mounting or parallel retargeter.
- Clothing updates replace only the changed slot on the live skeleton, retaining the body, other garments and animation frame. Shared sources stay loaded with their item definitions; generated meshes use the bounded production fitting cache. Editor fitting bypasses that mesh cache.
- `outfitter_fit_loader.gd` prepares legacy `body_fits` scene paths for visible slot choices and the worn outfit's other builds, with at most two native loads at once. Pending native loads show **Loading clothing…** while the existing character remains visible. This loader is not proof of asynchronous shared mesh fitting: migrated items do not use `body_fits`, and cold generated fits can still cost frame time. A newer choice supersedes the old one; separate equipment slots do not cancel each other. Body replacement temporarily disables equipment actions until the selected body is ready. Closing cancels pending UI changes and drains started loads; remounting resumes the current body selection. Preparation failures retain the existing actor and restore its selectors.
- `outfitter_stage.gd` is a small isolated studio component. The monster viewer has no extracted reusable stage; the tool does not subclass/copy its large content viewer or alter its dirty files.

**Existing production limitation:** QuadBot accepts its authored equipment slots, but `QuadBotBodyProjection` does not project held equipment or provide hand sockets. The tool explicitly reports this and does not invent mounts. Its real body and embedded animations work. Item fit/orientation is exactly the current saved production fit; visual acceptance belongs to live QA.

## Runtime interfaces for live inspection

Root: `/root/Outfitter`.

- `catalog.races`, `catalog.items`, `catalog.bodies(race)` expose discovered saved resources.
- `select_race(index)`, `select_body(index)` request a real actor; wait until `_building` is false before inspecting the replacement. Build UI changes use the same preparation path.
- `select_slot("weapon")`, `filter_equipment("stick")` drive sidebar.
- `equip_item(load("res://features/inventory/resources/items/bestiary_puglin_stick.tres"), "weapon")`; `equip_item(null, "weapon")` removes. This synchronous inspection API can incur a cold fit. UI preparation covers legacy scene loads, not a guarantee of precomputed shared meshes. `select_build(index)` is the corresponding synchronous actor-creation API.
- `select_animation("Idle")` / `select_animation("Mining")` return availability.
- `set_view_mode("Full body")`, `set_view_mode("Right hand")`, `set_view_mode("Left hand")`.
- `stage.set_view(yaw_radians, pitch_radians, distance_meters)`; `stage.camera`, `stage.focus`, `stage.tracking` are exposed.
- `ruler_toggle.button_pressed` controls visibility. `stage.ruler` is a sibling Control outside the 3D viewport; `.ground_y`, `.upper_extent`, and `.project_height(meters)` expose its reference and projected scale.
- `bone_sliders["height_slider"].value` (also `shoulder_width_slider`, `arm_length_slider`, `neck_length_slider`) drives the same visible controls; `reset_body_proportions()` resets all four together. The projection's `refresh_body_proportions()` reuses `CharacterAppearanceData.get_body_pose_offsets`, including removal of old offsets when a slider returns to zero.
- `actor.get_body_projection().get_primary_animation_player()` gives the **current** player. Ordinary clothing keeps it and its paused frame; body/build changes replace it. Reacquire it after body changes or a projection fallback. For a frozen screenshot, pause it and seek after choosing the clip.

## Focused proof

`godot --headless --path /home/dustin/mygame --script res://tools/outfitter/validate_outfitter.gd`

The deferred runtime validator loads the scene with normal autoloads and exercises every discovered race/body against every discovered equippable item, actual allowed/denied transactions, None removal, production weapon mounting, saved canonical identity, slot-filtered enumeration, looping and selection retention. Granular loading, cancellation, remount and animation-preservation regressions live in `tests/unit/test_outfitter_body_context.gd`; these complement the complete `./tests/run.sh` unit gate.
