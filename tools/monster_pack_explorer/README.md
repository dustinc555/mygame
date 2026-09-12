# Monster Pack Explorer

Open `res://tools/monster_pack_explorer/monster_pack_explorer.tscn` in Godot and press **F6** (Run Current Scene). This does not change the project's main scene or launch gameplay.

- Select or search for a monster in the left panel.
- Skeleton A/B share one **Skeleton** entry: they have the same body and rig. Its equipment selectors offer both weapons and both helmets, with independent armor choices and **None** to remove gear. Choices survive switching to another monster and back.
- Drag in the preview to orbit; use the mouse wheel to zoom. **Reset view** frames the selected model again.
- Select an animation from the project's UAL1 Pro and UAL2 libraries. It plays automatically on a loop; changing monsters keeps the selected animation. There are no playback buttons or progress bars.
- The original monster GLBs contain rigs, not clips. The explorer transfers the existing UAL animations with rest-pose correction and preserves each monster's bone proportions. Animation names identify their source library. No animation assets are invented or written into the vendor GLBs.

The explorer discovers GLBs in `assets/vendor/quaternius/bestiary_dungeon_monsters/glb/`, with display names and equipment-only aliases from `equipment_manifest.json`. All seven source exports are preserved, but the list contains six distinct bodies. Only the selected model is instantiated. Preview animation changes are made on resource copies, never on the imported assets.

No combat, AI, encounters, or gameplay actor registrations are added by this tool.

## Registered Puglin body

Puglin is authored through the existing resources, shared with gameplay:

- Race: `features/actors/resources/character_races/puglin.tres`
- Body: `features/actors/resources/character_body_archetypes/puglin.tres`
- Grip profile, referenced only by that body: `features/actors/resources/humanoid_grip_socket_profiles/puglin.tres`

Open the race in Godot's FileSystem/Inspector, expand either default body reference,
then its **Grip Socket Profile**. Both defaults currently use the same supplied
body. There is no separate race-authoring dock. The explorer's manifest references
the race; it does not redefine Puglin's body, equipment slots, or grip.

The body scene hides the vendor's bundled stick; equipped weapons are real items.
Puglin currently supports weapon/offhand slots only, because no fitted wearable
models have been authored. Bronze Sword is available in the explorer for inspecting
the shared one-handed grip. No population profile, faction, or spawn list is changed.
