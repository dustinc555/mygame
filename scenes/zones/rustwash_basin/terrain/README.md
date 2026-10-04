# Rustwash Basin — Canyon landscape

## Layout

Canyon remains at its authored location near X -18, Z -300. Its buildings,
furniture, residents, farms, camp, and resource placements are unchanged.
The terrain provides a broad town floor, tall broken rock walls, a winding
north/south canyon, western ravines, an ascending northeastern side passage,
and a southern wash opening into flatter country.

These are clear terrain sites for future authored gameplay, **not populated
scrap fields or new resource spawners**:

| Site | Approximate center (X, Y, Z), meters | Intended use |
| --- | --- | --- |
| West salvage basin | (-840, 3, -200) | Sheltered scrap field, reached through the western ravine |
| South dry lake | (-5, -1.5, 910) | Large open salvage/encounter ground and travel crossroads |
| East hardpan | (885, 5, 70) | Broad flat site beyond the southeastern passage |
| North overlook | (615, 36, -1000) | Elevated encounter/camp site reached by an ascending ravine |
| Southwest camp flat | (-970, 3, 445) | Smaller camp/building site along the southern bypass |

## Editing in Godot

Open `scenes/zones/rustwash_basin/rustwash_basin.tscn`, select **Terrain**, and
use the normal Terrain3D sculpt, smooth, and texture-paint brushes. Nothing
regenerates or overwrites brush edits at runtime.

- Active region data: `terrain/data_canyon/` (110 native Terrain3D regions).
- Original terrain: `terrain/data/`, retained unchanged for rollback.
- Texture slot **0**: the original Soil & Stones material, unchanged.
- Texture slot **1**: Canyon - weathered stratified rock.
- Rock appearance: edit `textures/canyon_cliff/canyon_cliff_texture.tres`.
  `uv_scale` controls the repeat size, `normal_depth` surface relief, and
  `albedo_color` the tint. Keep rotation detiling off to keep strata aligned.
- Rock/dirt blending and steep-slope projection:
  `rustwash_basin_terrain3d_material.tres`.

The rock is slope-painted with extra exposure on high ledges. This is saved
paint, not a live automatic slope rule; repaint after subsequent major sculpts.
The initial shape was authored offline, with shaped drainages and clearings,
then saved into editable native height/control/color maps. Existing low
building/farm support pads were retained; old high dirt ridges between or
intersecting buildings were removed.

The packed rock textures are 4096² RGBA8 with mipmaps, matching the existing
Terrain3D dirt array. RGB albedo carries displacement in alpha; OpenGL normal
RGB carries roughness in alpha. Original CC0 scan maps and provenance live in
`assets/vendor/polyhaven/cliff_side/`. They are excluded from Godot importing
with `.gdignore`; runtime uses the packed `.res` textures.

## Navigation and rollback

Terrain changes require a fresh navigation bake. Both entrypoints have their
own caches; the normal game launches World1. Use the existing **Bake World
Nav** editor tool on the relevant scene, or run from the project root:

```sh
godot --headless --path . --script res://tools/bake_world_navcache.gd -- res://scenes/worlds/world1/world1.tscn
godot --headless --path . --script res://tools/bake_world_navcache.gd -- res://scenes/zones/rustwash_basin/rustwash_basin.tscn
```

To restore the original terrain, change the Terrain3D `data_directory` in
`rustwash_basin_terrain.tscn` from `data_canyon` to `data`, then rebake both
navigation caches. Do not save stale terrain data from an editor session that
was already open during an external update; reload the scene first, preserving
any unrelated unsaved work.
