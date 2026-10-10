# Lockpick art

Project-authored models, authored in meters. The standard hook is approximately
16 cm long; the variants preserve its working tip and common grasp point.

- `lockpick.glb`: steel hook with brown wrapped grip.
- `lockpick_fine.glb`: steel hook with green wrapped grip and brass fittings.
- `lockpick_flimsy.glb`: one bare rusted metal strip. No separate handle, wrap,
  collar or pin. `lockpick_rust.png` is the authored rust texture.
- `source/`: editable Blender files with packed textures, excluded from Godot
  imports by `.gdignore`.

Export GLB with materials and textures embedded. The flimsy GLB's Godot Import
setting **glTF / Embedded Image Handling = Embed as Uncompressed** deliberately
keeps its small rust texture inside the imported scene. Keep the `.import`
sidecars; do not publish only a cached scene that depends on an untracked
extracted texture.

Ground wrappers: `features/world/projection/items/lockpick*_world.tscn`.
Held wrappers: `features/world/projection/equipment/lockpick*_model.tscn`.
Calibrate the wrapper's `GripPoint_Primary` and `ToolTip` markers, not shared
body grip sockets. Gameplay art references live in the corresponding
`features/inventory/resources/items/lockpick*.tres` files.

Icons are transparent Godot renders of the saved models. Re-render all affected
pictures after editing geometry or material; follow `assets/items/icons/README.md`.
