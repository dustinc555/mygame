# Copper wire

Project-authored bare copper coil. One continuous tube has lightly uneven winding,
a tucked starting end and a loose cut end. The mesh is authored in meters and the
GLB embeds its copper color texture and metallic/roughness material.

- Editable source: `source/copper_wire.blend` (excluded from Godot import).
- Runtime model: `copper_wire.glb`, imported with embedded textures.
- World wrapper: `features/world/projection/items/copper_wire_world.tscn`.
- Item definition: `features/inventory/resources/items/copper_wire.tres`.
- Model-rendered picture: `assets/items/icons/copper_wire.png`.

Open the item definition in Godot's Inspector to edit **Icon**, **World Scene**,
**World Visual Long Axis Meters** (0.2 m) or **Grid Size** (2 by 2 cells).
These are ordinary saved item properties, not a copper-specific runtime system.
The grid size reserves bag capacity; it is independent of the picture's pixels.

For mesh/material edits, open the retained Blender source and export the selected
coil as glTF Binary with +Y Up and meters. Keep image data embedded. Re-render the
picture from the saved Godot wrapper when the appearance changes; use the shared
instructions in `assets/items/icons/README.md`.
