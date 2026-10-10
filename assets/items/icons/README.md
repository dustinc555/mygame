# Item pictures

Inventory items with authored models use transparent PNG renders of their actual
textured models, following the traveler gear. These are saved art assets, not
runtime 3D previews. UI symbols such as buttons may still use SVGs.

## Assign or replace a picture

1. Open `features/inventory/resources/items/<item>.tres` in Godot's FileSystem.
2. Use its **World Scene**, or its equipment visual when it has no world model,
   as the picture's source. Keep the real geometry, materials and proportions.
3. Render the item alone against transparency. Frame the complete silhouette
   with a small clear border; orient tools naturally and arrange paired pieces
   compactly in the render scene only. Do not change the source equipment to
   compose its picture, add anatomy, or invent a different material.
4. Save `assets/items/icons/<item>.png` and assign it to the item's **Icon** field
   in the Inspector. Existing traveler pictures remain beside their source art.
5. Check the saved picture in the ordinary bag, equipment/drag presentation and
   merchant tile, not only enlarged. Re-render when the source appearance changes.

**Grid Size is gameplay capacity, not image padding.** Keep it unchanged for an
icon replacement. The shared inventory geometry fits the image proportionally
inside the existing cells; tightly cropped portrait images let long tools use
those cells without distortion.

## Image settings

- RGBA PNG with transparent padding on every edge; no baked background or shadow
  plane. Crop unused canvas while preserving proportions.
- Render at 1024 pixels, then downsample to at most 512 pixels on the longest
  side. Keep approximately 16 pixels of padding at that output size.
- Use neutral lighting with enough fill to read dark leather/metal. The catalog
  pass used Godot Forward+, orthographic views, 4× MSAA and AgX tonemapping.
- Import as a lossless 2D texture, with alpha-border fixing enabled and mipmaps
  disabled. Keep the PNG's `.import` sidecar with the source asset.

Models and their existing licenses remain in their original asset families;
these pictures are renders of those assets, not newly sourced third-party art.
An empty item model assignment does not mean its source mesh is missing. Check
the asset packs and their embedded meshes before requesting new art. Do not
claim an arbitrary placeholder is the item's finished model.

## Embedded crop and coin sources

The vegetable and seed pictures use
`assets/vendor/luceed-studio/farm-crops-01/crops01.glb`. Render only the named
subtree, preserving its original mesh, material and parent transforms:

| Item filename | Produce subtree | Seed subtree |
| --- | --- | --- |
| `bell_pepper` | `BellPepper` | `Crop_BellPepper_Stage01` |
| `chili_pepper` | `Chili` | `Crop_Chili_Stage01` |
| `eggplant` | `Eggplant` | `Crop_Eggplant_Stage01` |
| `french_beans` | `FrenchBeans` | `Crop_FrenchBeans_Stage01` |
| `tomato` | `Tomato` | `Crop_Tomato_Stage01` |

The seed pictures use the matching `<item>_seeds.png` names. Stage01 contains
actual seeds, not seedlings. `silver.png` uses the original textured model at
`assets/vendor/quaternius/fantasy_props_megakit/gltf/Coin.gltf`.
These picture assignments are independent of dropped-item model assignments.

## Lockpicks

`lockpick.png`, `lockpick_flimsy.png` and `lockpick_fine.png` are renders of the
corresponding saved wrappers in `features/world/projection/equipment/`. The
project-authored sources are in `assets/items/tools/lockpick/`: brown wrapped
steel, bare rusted metal without a handle, and green wrapped steel with brass
fittings. Keep the full hook and grip in each picture. These items deliberately
use a one-by-two inventory footprint; their pictures do not change bag capacity.

## Copper wire

`copper_wire.png` is a transparent render of the project-authored coil at
`features/world/projection/items/copper_wire_world.tscn`. Its GLB and editable
Blender source live in `assets/items/materials/copper_wire/`. Use the actual
copper material and keep the loose cut end inside the picture. This coil uses
an explicitly authored two-by-two inventory footprint.

`tests/unit/test_item_mesh_icons.gd` checks native loading, PNG assignment,
visible content and transparent padding for model-backed catalog items. Visual
review is still required to prove model fidelity and useful framing.
