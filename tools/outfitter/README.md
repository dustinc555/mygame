# Outfitter

Run `godot --path /home/dustin/mygame res://tools/outfitter/outfitter.tscn`, or open this scene and press F6. It does not change the project's main scene or write gameplay/save data.

Choose a race, an authored sex/body, an equipment slot, then an item. Search covers **all equippable ItemDefinition resources**, including incompatible items; gray rows explain refusal when clicked/hovered. None removes the selected slot. Compatible loadout choices survive body/race changes; incompatible retained choices are not forcibly equipped. One shared body is presented once, not as invented male/female anatomy.

The large isolated viewport has drag orbit, wheel zoom, full-body and tracked left/right-hand views. Selecting a production animation loops it automatically. Its name survives equipment rebuilds and actor changes; clips absent from another actor are explicitly marked unavailable rather than silently replaced.

Race/body changes retain camera focus, orbit, zoom and FOV. In hand view only the focus follows the replacement body's socket; missing sockets stop tracking at the last view and report the existing warning. Equipment rebuilds also retain the camera. The first body auto-frames; **Full body** explicitly reframes whenever requested.

The **Height ruler** toggle shows a narrow, separate strip beside the viewport; it cannot cover the character. Its ticks project actual world heights at the body's center through the current camera, so they follow orbit and zoom without a distant ruler's perspective mismatch. Feet use exactly 0.3048 meters. Zero and the studio floor use the unequipped body's foot-level bounds, captured before retained equipment is applied. Bounds set only the reference level and coverage, not an asserted exact actor height. Toggling it changes available viewport width without changing camera position, zoom, or FOV. No ruler geometry exists in the 3D world.

## Authority and bounded integration

- `outfitter_catalog.gd` discovers races through `PopulationAppearanceProfile._get_available_races()` and recursively discovers the same item resource directory used by world authoring. No hand-maintained item/race list or copied model/grip settings.
- Actor scripts come from matching saved population appearance profiles, preserving Rustdead and QuadBot specialized classes. Canonical humanoid bodies without a specialized population profile (currently Puglin) use the general production `HumanoidCharacter` actuator. Unsupported non-humanoid bodies fail closed. This is body-family selection, not race-specific equipment configuration.
- Script-created humanoid scaffolding delegates to `PopulationCharacterRealizer._ensure_projection_bootstrap()`. These existing helper methods are callable in GDScript; no shared code had to change.
- Saved race/body/grip resources are used by identity, with normal `EquipmentCapability` equip/unequip and actual production `BodyProjection` visuals. No monster-pack preview mounting or parallel retargeter.
- `outfitter_stage.gd` is a small isolated studio component. The monster viewer has no extracted reusable stage; the tool does not subclass/copy its large content viewer or alter its dirty files.

**Existing production limitation:** QuadBot accepts its authored equipment slots, but `QuadBotBodyProjection` does not project held equipment or provide hand sockets. The tool explicitly reports this and does not invent mounts. Its real body and embedded animations work. Item fit/orientation is exactly the current saved production fit; visual acceptance belongs to live QA.

## Runtime interfaces for live inspection

Root: `/root/Outfitter`.

- `catalog.races`, `catalog.items`, `catalog.bodies(race)` expose discovered saved resources.
- `select_race(index)`, `select_body(index)` rebuild real actor.
- `select_slot("weapon")`, `filter_equipment("stick")` drive sidebar.
- `equip_item(load("res://features/inventory/resources/items/bestiary_puglin_stick.tres"), "weapon")`; `equip_item(null, "weapon")` removes.
- `select_animation("Idle")` / `select_animation("Mining")` return availability.
- `set_view_mode("Full body")`, `set_view_mode("Right hand")`, `set_view_mode("Left hand")`.
- `stage.set_view(yaw_radians, pitch_radians, distance_meters)`; `stage.camera`, `stage.focus`, `stage.tracking` are exposed.
- `ruler_toggle.button_pressed` controls visibility. `stage.ruler` is a sibling Control outside the 3D viewport; `.ground_y`, `.upper_extent`, and `.project_height(meters)` expose its reference and projected scale.
- `actor.get_body_projection().get_primary_animation_player()` gives the **current** player; equipment wearables can replace it. Reacquire it after each equip. For a frozen screenshot, pause it and seek after choosing the clip.

## Focused proof

`godot --headless --path /home/dustin/mygame --script res://tools/outfitter/validate_outfitter.gd`

The deferred runtime validator loads the scene with normal autoloads and exercises every discovered race/body against every discovered equippable item, actual allowed/denied transactions, None removal, production weapon mounting, saved canonical identity, empty/search-cleared enumeration, looping and selection retention. No broad import or validation sweep is required.
