# Flat plaster walls and fired-clay floors

These are additional project-owned modules, not repainted or edited vendor wall meshes.
The live building shells use lime plaster and terracotta. The original Quaternius doors,
window/door frames, roof timber, balconies, stairs and chimney materials remain unchanged.

## Authoring

Select a WorldBuilding in Godot, then **Building Pieces → Walls / Door Walls /
Window Walls / Corners / Floors**. The new entries start with **Plaster**, **Clay Plaster**
or **Fired Clay**. The original pieces remain in the same drawer.

- Scenes: `features/world/projection/buildings/pieces/plaster/`.
- Catalog: `features/world/resources/building_pieces/plaster/catalog.tres`.
- Shared materials: `assets/buildings/earthen/materials/`.
  - `lime_plaster.tres`: photographed mineral plaster, used by current shells.
  - `clay_plaster.tres`: a separate earth-plaster photograph/normal/roughness set,
    used by the selectable Clay Plaster variants, not a tint of lime or stone.
  - `terracotta.tres`: fired-clay floor tiles. Floor undersides use plaster.

Open `lime_plaster.tres` in the Inspector → **Shader Parameters**:

- **Distance Detail Strength** (0.8): contrast of the larger photographed plaster marks.
- **Marks Repeat Meters** (5): the separate distance-reading scale, not the fine grain size.
- **Detail Start Distance / Detail Full Distance** (4 / 16 m): smoothly blend in that
  reading scale as the camera moves away. At close range the additional layer is absent.
- **Grain Repeat Meters / Normal Strength** (2 m / 0.7): the accepted close surface.

The original 4K albedo, normal, roughness and AO are retained without modification.
The additional layer modulates albedo only, around a neutral mean; it adds no coarse
normal bumps, emission, light override or blanket tint. Ordinary sunlight, shadows and
local lights still shade the same rough plaster. World-space mapping stays continuous
across modules, independent of their local scales. No per-frame scripts are involved.
Clay plaster and terracotta still use their StandardMaterial3D Inspector controls;
floor mapping repeats at 2.1 metres.
Changes to a shared material affect every piece using it. To vary one module, use its
Model → Material Override or the separate Clay Plaster scene. Reload a running game
after saved scene/material changes; an already-open editor scene can retain a cached copy.

## Geometry and preserved details

The new meshes are built from planar closed polygons, with actual doorway/window holes,
flat reveals and solid matching collision. Dimensions use the existing two-metre grid;
wall height is 3.122689 m and thickness is 0.2 m. Existing per-storey scale is retained.
The door/window-center and edge snap sockets support the existing fittings. Door modules
use their own open-aperture collision rather than the old disabled vendor collider and
separate approximation boxes. Door scripts, ownership, opening behavior and frames are not changed.

`floor_fitted_*.tscn` are saved perimeter/notch cuts used by the shells, not runtime
geometry generators. Their visible polygons and collision agree; stair openings remain
open. Common full, half and clipped-corner tiles are exposed in the authoring drawer.
The tower divider's left run is two metres plus 1.6 metres, without the previous 0.4 m overlap.
Corner modules are aligned to the adjoining flat wall planes rather than the former timber rims.

`meshes/chimney_fitted.res` is the sole derived non-wall/floor asset: it retains the
previously requested roof-contact correction while restoring every original chimney
material value. Its original vendor source remains unchanged.

## Texture sources

Unmodified 4K source PNGs and exact download metadata/checksums are retained under:

- `assets/vendor/polyhaven/plastered_wall/` — Amal Kumar, Poly Haven, CC0.
- `assets/vendor/polyhaven/clay_plaster/` — Amal Kumar, Poly Haven, CC0.
- `assets/vendor/polyhaven/terracotta_floor_tiles/` — Dimitrios Savva, Poly Haven, CC0.

Runtime copies keep 4096×4096 resolution, convert to ordinary game-ready RGB/grayscale,
and use high-quality GPU compression, mipmaps and anisotropic filtering. No stone atlas,
recolored rock, or generated low-resolution noise is used. See `ATTRIBUTION.md` for sources.

`textures/lime_distance_detail.png` is a 2048² grayscale derivative of the same CC0
`lime_albedo.png`, not a new texture source. Its RGB-average photograph is downsampled
with Lanczos and lightly filtered (Gaussian radius 0.7 pixels); values are centered as
`clamp(0.5 + 6.5 * (gray - mean(gray)), 0, 1)` and saved to 8-bit PNG. This retains the
photographed trowel marks rather than inventing random clouds. It is sampled as linear
data with high-quality GPU compression, mipmaps and anisotropic filtering. The centered
map is multiplied into the original albedo by the editable distance-detail strength.

## Verification

`./tests/run.sh` includes native resource/material, opening/collision, real body passage,
partition overlap, ceiling-fit, chimney/roof-contact and catalog checks. Visual acceptance
also requires the production world in Forward+, including its torch-lit interior;
passing resource tests alone is not an art-quality verdict.
