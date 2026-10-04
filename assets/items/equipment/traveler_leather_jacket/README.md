# Traveler leather jacket

The current item uses **one source jacket**, `body_fits/male_regular.glb`, with `assets/items/equipment/wardrobe_bindings/traveler_leather_jacket.res`. The shared wardrobe adapts it to the six registered human male/female regular, heroic and teen bodies; there are no selected per-body garment overrides. Other GLBs remain historical references despite the `body_fits/` directory name. The warm brown worked hide has darker reinforcement, restrained grain, localized edge wear and a subtle leather sheen. No anatomy is hidden.

**Current editable source and clothing-addition workflow:** `../traveler_outfit/README.md`. Open that family's **`source/male_regular.blend`** and edit `Traveler_Hide_Jacket`, then export that one source and regenerate its binding. Do not maintain separate sex/build jackets. The files described below are preserved earlier artwork, not the current source.

## Earlier jacket artwork (preserved)

Open `source/traveler_leather_jacket.blend` in Blender. The active `TravelerJacket_Studio` scene contains the fit references, studio and two fitted meshes:

- `Male_Traveler_Leather_Jacket`, bound to `Male_Fit_Rig`.
- `Female_Traveler_Leather_Jacket`, bound to `Female_Fit_Rig`.

Both use the original production bone names and rest coordinates. The female reference and jacket are hidden initially because both fits share the same origin. Toggle the corresponding objects in the Outliner to work on one fit at a time. Keep rig transforms and rest bones unchanged. The named `Jacket · ...` materials expose leather, reinforced panels, edging, stitching, lining and brass. Texture images are packed into the Blender file.

Each fit has packed 2048-pixel `<Male|Female>_Traveler_Leather_Color`, `_Normal`, and `_ORM` images painted onto its existing UVs. The leather includes fine hide grain, gentle panel variation, and warmer wear along cuffs, hem, collar and shoulder tops. Materials ending in **Male** or **Female** expose that fit's painted leather. Adjust **Normal Map → Strength** (currently `0.65`) for more or less grain; **Leather roughness and metal** owns highlight variation through the ORM image's green channel. Stitching, rolled edges and brass retain solid materials so their small details remain crisp.

The male mesh has a localized rear-armhole fit correction; its topology, skin weights, UVs and textures remain unchanged. Adjust that area directly on `Male_Traveler_Leather_Jacket` if further fitting is needed. Inspect **Idle** while orbiting between the rear and side views: a narrow skin sliver there can be invisible from straight behind. The female fit is unchanged.

Export only one jacket and its matching rig from the active scene. Use GLB, selected objects, +Y up, skinning enabled, animations disabled. Triangulate an export copy, not the editable mesh. Never export the fit-reference body or unrelated scene objects. The GLB importer embeds the texture images and uses named skin binds.

## Inspect the current outfit

Run `godot --path /home/dustin/mygame res://tools/outfitter/outfitter.tscn`, choose **Human → Sex / body → Build**, select **Chest**, and search **Traveler Leather Jacket**. Add **Traveler Hide Trousers**, **Traveler Hide Boots**, and **Traveler Hide Gloves** in their separate slots. The short gloves are compatible; legacy whole-arm hands-slot pieces are not. Check the source cut, Idle/Walk, bends and the right-side body sliders across builds. Minor finger, boot and layering clipping remains; technical tests are not visual approval. No starting loadouts, vendors or loot pools are changed. Other races, arbitrary clothing combinations and large-battle performance are not established by this outfit.

## Provenance

The fitting shell and skin weights are derived from copies of the project's Quaternius Universal Base Characters `Regular_Male_FullBody.gltf` and `Regular_Female_FullBody.gltf`. That pack is already listed in `ATTRIBUTION.md`. The shell is reshaped for garment ease and clipped at the neckline, waist and wrists. Collar, reinforcing panels, pockets, closures, stitching, trim and leather maps are project-authored. Original vendor files are unchanged.

The `source/.gdignore` prevents automatic Blender import. The current item definition at `features/inventory/resources/items/traveler_leather_jacket.tres` selects only `body_fits/male_regular.glb` through `visual_scene`, plus `clothing_binding`; it does not use the legacy `body_fits` field. Preserve the older source files and exports.
