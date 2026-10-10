# Hardtack tin

Project-authored sealed food tin, displayed in-game as **Dry Biscuits**.
No third-party models, textures or asset licenses are used.

- Editable model: `source/hardtack_tin.blend` (metres, Z-up in Blender).
- Runtime model: `hardtack_tin.glb` (exported Y-up; approximately 20 cm wide).
- Editable paint, label and steel textures are in `source/` and packed into the
  Blender file. The accompanying `hardtack_tin_*.png` files are Godot's extracted
  GLB textures; regenerate them by reimporting the exported GLB rather than
  editing them independently.
- World wrapper: `features/world/projection/items/hardtack_tin_world.tscn`.
- Item: `features/inventory/resources/items/food.tres`. Its Inspector owns the
  display name, **Grid Size** (2×2), **Icon**, **World Scene**, and
  **World Visual Long Axis Meters** (0.202). The existing `food.generic` ID and
  food balance are retained.
- Inventory picture: `assets/items/icons/hardtack_tin.png`, a transparent render
  of this actual model. Re-render it after changing the model or textures.

Edit the named parts in the Blender source, select only the nine mesh objects,
then export glTF Binary with materials and +Y up. Do not export cameras, lights
or animations. `source/.gdignore` keeps the authoring file out of Godot's import
scan. Use the existing model-picture instructions in `assets/items/icons/README.md`
for lighting, framing and PNG settings; no runtime icon generator is required.
