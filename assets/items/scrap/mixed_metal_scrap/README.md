# Mixed Metal Scrap

Project-authored salvage: torn sheet steel, broken angle bracket, hollow pipe,
twisted strap, washer and bolt. No third-party source or runtime generator.

- Editable source: `source/mixed_metal_scrap.blend` (meters, Z-up in Blender).
- Runtime: `mixed_metal_scrap.glb`, exported selected meshes, Y-up for Godot.
- Source color and packed roughness/metallic textures are retained in `source/`
  and packed in the Blender file. The GLB embeds them; import uses **Embed as
  Basis Universal**, not external texture extraction.
- World wrapper: `res://features/world/projection/items/scrap_metal_world.tscn`.
- Item: `res://features/inventory/resources/items/scrap_metal.tres`.
- Picture: `res://assets/items/icons/scrap_metal.png`, a transparent Godot render
  of this exact model. Regenerate it after changing the source appearance.

Open the item resource in Godot's FileSystem/Inspector to edit **Display Name**,
**Grid Size**, **Icon**, **World Scene** and **World Visual Long Axis Meters**.
The authored drop is 0.36 m across; the inventory footprint is 2×2. Weight,
stacking and scavenging rules remain independent of the art.
