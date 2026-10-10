# Packed bandages

Two completely wound linen rolls secured by a closed paper sleeve. No unrolled cloth tail. The mesh, label and paper material are project-authored; the cloth surface derives from Poly Haven's **Rough Linen**, credited in `ATTRIBUTION.md`.

## Game wiring and tuning

- Item: `features/inventory/resources/items/bandage.tres`. In Godot's Inspector, **Grid Size** is `2 × 2`; **Bandage Max Uses** is `5`; healing power and weight are unchanged.
- Dropped visual: `features/world/projection/items/bandage_world.tscn` loads `packed_bandage.glb`.
- **World Visual Height Meters** is `0.04`, the bundle's thickness: approximately a 9 × 9 × 4 cm packet. `WorldItem` derives its collision from the same scaled visual bounds.
- Inventory image: `assets/items/icons/bandage.png`, a transparent 512-pixel PNG rendered from the actual runtime mesh and materials. There is no per-slot 3D renderer.
- These saved resource changes apply when resources are reloaded; restart an existing game to see the replacement.

## Editable source

`source/packed_bandage.blend` retains the detailed editable model and packed images, with portable `//textures/` references. Its 46,848 triangles are the untouched modeling source. `source/` is ignored by Godot.

The runtime GLB has 12,000 triangles, made from that detailed export using the existing `tools/asset_pipeline/decimate_static_glb.py`. This is conservative decimation, not retopology. Embedded image payloads and materials were checked against the original export, and matching front/rear views were inspected. Godot-generated LODs remain enabled.

`linen_*` maps are the ivory cloth derivative; `binding_*` maps are the authored paper sleeve. Runtime PNG imports use VRAM compression and mipmaps; the OpenGL normal map is imported as a normal map. Keep maps, sidecars and model together.

For a future art edit, work from the Blender source, export the detailed mesh to a separate file, derive any lower-detail candidate from that untouched export, inspect matching native Godot views, and regenerate the PNG from the accepted runtime mesh. Do not repeatedly decimate the production GLB or overwrite the detailed source with it. Render/inspection helpers for this one-off pass are not game dependencies.

Original scanned maps and publisher metadata are preserved under `assets/vendor/polyhaven/rough_linen/`.
