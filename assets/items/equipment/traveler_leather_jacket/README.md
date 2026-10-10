# Traveler leather jacket

Project-owned full-sleeve chest garment. The two fits target the **regular adult human male and female** bodies. It does not supply gloves, replace anatomy, or hide body meshes. Existing whole-arm hands-slot garments are not compatible layering partners.

## Edit

Open `source/traveler_leather_jacket.blend` in Blender. The active `TravelerJacket_Studio` scene contains the fit references, studio and two fitted meshes:

- `Male_Traveler_Leather_Jacket`, bound to `Male_Fit_Rig`.
- `Female_Traveler_Leather_Jacket`, bound to `Female_Fit_Rig`.

Both use the original production bone names and rest coordinates. The female reference and jacket are hidden initially because both fits share the same origin. Toggle the corresponding objects in the Outliner to work on one fit at a time. Keep rig transforms and rest bones unchanged. The named `Jacket · ...` materials expose leather, reinforced panels, edging, stitching, lining and brass. Texture images are packed into the Blender file.

Each fit has packed 2048-pixel `<Male|Female>_Traveler_Leather_Color`, `_Normal`, and `_ORM` images painted onto its existing UVs. The leather includes fine hide grain, gentle panel variation, and warmer wear along cuffs, hem, collar and shoulder tops. Materials ending in **Male** or **Female** expose that fit's painted leather. Adjust **Normal Map → Strength** (currently `0.65`) for more or less grain; **Leather roughness and metal** owns highlight variation through the ORM image's green channel. Stitching, rolled edges and brass retain solid materials so their small details remain crisp.

The male mesh has a localized rear-armhole fit correction; its topology, skin weights, UVs and textures remain unchanged. Adjust that area directly on `Male_Traveler_Leather_Jacket` if further fitting is needed. Inspect **Idle** while orbiting between the rear and side views: a narrow skin sliver there can be invisible from straight behind. The female fit is unchanged.

Export only one jacket and its matching rig from the active scene. Use GLB, selected objects, +Y up, skinning enabled, animations disabled. Triangulate an export copy, not the editable mesh. Never export the fit-reference body or unrelated scene objects. The GLB importer embeds the texture images and uses named skin binds.

## Inspect

Run `tools/outfitter/outfitter.tscn`, choose **Human**, a human body, **Chest**, and search **Traveler Leather Jacket**. Keep **Hands → None**: the old hands-slot pieces include their own full sleeves. The asset is a visual candidate; no starting loadouts, vendors, loot pools, stats, or existing clothing are replaced. Heroic/teen bodies, other races, combinations with underlayers or full-arm hands items, and large-battle performance are not established by the regular-body fit review.

## Provenance

The fitting shell and skin weights are derived from copies of the project's Quaternius Universal Base Characters `Regular_Male_FullBody.gltf` and `Regular_Female_FullBody.gltf`. That pack is already listed in `ATTRIBUTION.md`. The shell is reshaped for garment ease and clipped at the neckline, waist and wrists. Collar, reinforcing panels, pockets, closures, stitching, trim and leather maps are project-authored. Original vendor files are unchanged.

The `source/.gdignore` prevents automatic Blender import. The two GLBs are the runtime exports; the item definition lives at `features/inventory/resources/items/traveler_leather_jacket.tres`.
