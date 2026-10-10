# Iron ore and vein

Project-authored fractured ironstone geometry and mineral bedding, with a
desaturated **Rock Face** scan from Poly Haven providing the host-rock grain
and surface relief. Greg Zaal (photography), Dario Barresi (processing); CC0.
Original maps and license/download records are in
`assets/vendor/polyhaven/rock_face/`. The two models are independent of copper
and use the existing mining system.

- `iron_ore.glb`: loose inventory/world ore chunk.
- `iron_vein.glb`: fractured ground-level outcrop, approximately 4.28 m wide;
  20,156 triangles, one material, automatic Godot LODs.
- `iron_ore.glb`: 4,258 triangles, one material, automatic Godot LODs.
- `source/iron_ore.blend`: editable source; separate **Iron Ore Item** and
  **Iron Vein** collections. Toggle the collection/object visibility to edit each.
  Export only the selected model as GLB, +Y up, with materials included.
- `source/*_albedo.png`, `*_normal.png`, `*_roughness.png`, `*_metallic.png`:
  baked PBR maps, also packed in the Blender file. The vein uses 4K color/normal
  and 2K surface masks; the item uses 2K maps. Runtime glTF packs roughness and
  metallic into one texture. Do not simplify topology after baking normals.
- Godot's extracted runtime textures and `.import` files accompany the GLBs.
- `assets/items/icons/iron_ore.png`: transparent render of the actual ore model.

## Edit the artwork

The source opens with **Iron Vein** visible and **Iron Ore Item** hidden at its
authored origin. Toggle the two objects' viewport/render visibility to isolate
the item. Edit mesh vertices normally; keep the vein's base slightly buried so
it meets the ground without a floating rim. Refit the collision box if the
silhouette changes.

The packed `iron_vein_AUTHORING` and `iron_ore_AUTHORING` materials retain the
editable scan/bedding graph. Named nodes **Bedding diagonal**, **Uneven mineral
bedding**, **Thick dark iron beds**, **Slate host color**, and **Restrained iron
oxide** control the direction, irregularity, coverage and color. Export uses
the baked `*_Ironstone` material; rebake changed channels before exporting.
Use continuous spatial deformation for the narrow fracture ridges: large
per-normal displacement can fold bevels through themselves.

## Place and tune

Select a zone root, then **Zone → Resources → Iron Vein → Place in Zone**.
Reload the World Authoring plugin or restart the editor if its cached catalog
predates this content. Placement assigns persistent independent deposit IDs.
No deposits are automatically added to existing maps.

**Resources → Type Defaults** edits the shared stock and in-game-week refill
settings in `features/world/resources/resource_deposits/iron.tres`. These edits
do not reset existing stock or an already scheduled refill deadline.

Open `features/world/bridge/resource_nodes/iron_node.tscn` to edit mining level,
speed, approach slots, geometry or collision in the Inspector. It reuses
`MiningResourceNode`; there is no iron-specific gameplay script.

Open `features/inventory/resources/items/iron_ore.tres` to tune **Grid Size**,
**Unit Weight**, **Icon**, or **World Visual Height Meters**. The initial values
match copper's 3×2 footprint, 4 kg weight and 0.14 m dropped height. Material
storage includes iron through `BulkStoragePlatform.MATERIAL_ITEM_PATHS`.
