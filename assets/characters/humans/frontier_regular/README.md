# Frontier regular humans

Project-owned adaptations of the original **Quaternius Universal Base Characters** regular male and female. These accepted models are the canonical human defaults, selected by `features/actors/resources/character_body_archetypes/human_male.tres` and `human_female.tres`. Vendor originals remain unchanged for reference.

## Current changes

- Male: fuller posterior glute profile, plus a connected waist/pelvis/seat-width and upper-thigh proportion pass. The latest refinement halves the remaining abdominal color-map contrast and normal-map relief again, leaving roughly 17.5% of the original local detail strength. It leaves the geometry, face, other skin regions and female unchanged.
- Female: reduced lower-cheek fullness, slightly lengthened the lower face, and retained the cheekbones, jaw/chin width, and established hourglass body.
- Fitted, restrained brow geometry; eyebrows and eyelashes are treated as separate parts.
- Original Quaternius skin and eye materials are retained except for the localized male abdominal color/normal edits. Roughness and pixels outside the feathered abdominal mask remain unchanged. The earlier desaturated skin and donor-texture experiments are **not** used by these exports.

## Editable sources

- `source/male_regular.blend`: select `RegularMale`, open **Object Data Properties → Shape Keys**. **01 - Male glute volume and thigh transition** controls the earlier posterior correction; **03 - Male waist pelvis and upper-thigh balance** controls the connected lower-body proportion pass.
- `source/female_regular.blend`: select `Female_Regular`, open **Object Data Properties → Shape Keys**, and adjust **03 - Female cheek definition and adult lower face**.

The male glute control defaults to `0.9`, reducing the earlier posterior adjustment by 10%; the connected male waist/pelvis/upper-thigh control stays at `1.0`. The female cheek/lower-face control defaults to `0.7`, reducing that adjustment by 30% from its earlier review. These controls support `0.0–1.5` and change the named region without rebuilding the hands, feet or rig. Zero removes that individual change, not the other active shape layers. The `Original Quaternius` Basis is retained. All textures are packed into each Blender file; `source/.gdignore` prevents Godot from importing the authoring files.

The controls are **Blender authoring shape keys**, not character-creator sliders. The GLB files contain the evaluated default shapes and no exported morph controls. If changing the eye-aperture layers, update the matching eye and eyelash layers together.

For male abdominal definition, select material `MI_Regular_Male` in the Shader Editor. `Frontier_Male_Baseline_BaseColor` and `Frontier_Male_Baseline_Normal` reference the packed authored maps, also supplied as `source/textures/male_abdomen_basecolor.png` and `source/textures/male_abdomen_normal.png`. The feathered region is supplied as `source/textures/male_abdomen_mask.png` and packed as `Male_Abdomen_Definition_Mask`. The change retains 17.5% of the original abdominal contrast against broad local skin shading and tangent-normal relief within the mask; the central navel is protected. This is a **baked texture edit**, not a live definition slider. Edit these maps to tune that detail without changing the body shape; avoid lowering the whole material's normal strength, which also changes unrelated muscles.

## Preservation and review

Both saved Blender files were reopened and checked against fresh imports of their original vendor sources: the Basis positions, topology, UVs, bone rest matrices and skin weights match exactly. Hand and foot vertex positions remain unchanged by the active shape layers. Both saved GLBs were imported and captured through the production Outfitter, including full-body, side/rear and close-up views.

The abdominal refinement additionally preserves every exported mesh attribute and index, node transform and skin bind exactly against its pre-refinement male GLB. Exported authored image pixels match the supplied PNGs; other referenced images remain unchanged. The saved source was reopened before export, and matched front/oblique torso captures were inspected in the real Outfitter.

The actor and character editor both reuse the fitted `BrowDetail` mesh for the default eyebrow style, preserving its texture and allowing hair-matched recoloring without adding a second eyebrow mesh. Explicit external styles retain their existing fallback. Regular male skin-tone palettes use the softened authored abdominal albedo; heroic, teen, female and other-race palette sources are unchanged. After editing that source PNG, regenerate only its runtime palettes with `godot --headless --path . --script res://tools/generate_skin_tone_textures.gd -- --skin-race=human --skin-body=male --skin-variant=regular`.

Run the normal `tools/outfitter/outfitter.tscn`, choose **Human → Sex / body → Build: Regular**, and use the equipment and looping animation selectors. Heroic and teen defaults live in `../frontier_variants/`. The traveler outfit and migrated vendor clothing adapt one authored source per item to registered bodies; they no longer select separate saved garment fits. This does not promise compatibility with arbitrary combinations or other races. No comparison catalog is needed.

## Shared wardrobe registration

`human_male.tres` and `human_female.tres` map each actual body scene to a generated `WardrobeBodyProfile` through `wardrobe_profiles`. Registration belongs to the body and is shared by every garment; clothing owns a source scene and binding, not sex/build copies. The manifest has six canonical human profiles plus `original_male_regular` as the vendor garments' authoring reference. The traveler sources use canonical `male_regular`.

After changing a body GLB, targeted-reimport it and rebuild with `python3 tools/wardrobe/author.py build --body <id>`. Then run `plan` and rebuild stale dependencies: `male_regular` defines the common cage, so changing it can invalidate all profiles and bindings. See `tools/wardrobe/README.md` for the complete workflow. Do not edit generated profiles or compensate with per-body clothing models.

Outfitter's Height, Shoulders, Arm Length and Neck Length controls update live bones and attached clothes without per-frame fitting. The Blender shape keys above are not live morph sliders. Future mesh-morph customization needs body-owned deformed cage input and cache invalidation; it is not automatic. Review the source cut, motion, slider extremes and layering after body changes; technical checks alone are not visual approval.

## Provenance

The source meshes, rig, UV layout, and skin/eye maps are from Quaternius's Universal Base Characters, recorded as CC0 1.0 Universal in the project's root `ATTRIBUTION.md`.

Original files remain untouched under:

`assets/vendor/quaternius/universal_base_characters/base_characters/`

Source pack: https://quaternius.com/packs/universalbasecharacters.html

These are adaptations of Quaternius assets, not wholly original human meshes. The previous rejected `grounded_regular` family is unrelated and is not a source for these models.
