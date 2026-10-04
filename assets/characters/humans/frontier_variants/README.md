# Frontier heroic and teen humans

Project-owned adaptations of Quaternius Universal Base Characters. Covers **male heroic, female heroic, male teen and female teen**. These accepted models are the canonical human age/build variants, selected by `features/actors/resources/character_body_archetypes/human_male.tres` and `human_female.tres`. Vendor sources remain untouched for reference.

## Art direction

- Male: carry the approved regular's connected waist/pelvis/upper-thigh balance and fuller, rounded posterior into both builds. Heroic retains its larger muscle masses; teen retains a leaner, younger build. The adjustments are adapted to each source's skeletal scale, not a uniform body inflation.
- Female: ease the pinched waist-to-hip contrast while retaining the existing hourglass silhouette and limb forms. No chest enlargement and no muscle-definition reduction.
- Heroic faces: use the approved regular facial surface, eye shape and fitted brows/lashes for the corresponding sex. Head/upper-neck skin weights are transferred with the facial surface so the same animation does not pull the face into a different expression. The original heroic topology and UV layout remain; this is a saved surface/binding transfer, not a runtime shared-head system.
- Teen faces: restrained eye apertures, fitted eyebrows/lashes and a small female cheek refinement, retaining youthful features. No adult face replacement or jaw lengthening.
- **All four original body base-color and normal maps, roughness pixels and normal strength are unchanged.** No regular-male abdominal softening is carried to these builds. Original eye maps are also retained; brows use the approved regular brow material.

## Files and editing

Runtime models are `male_heroic.glb`, `female_heroic.glb`, `male_teen.glb`, and `female_teen.glb` beside this file. Packed editable sources are under `source/` with matching `.blend` names. `source/.gdignore` excludes authoring files from Godot import.

In Blender, select the main body and open **Object Data Properties → Shape Keys**:

| Source | Body object | Controls and defaults |
| --- | --- | --- |
| `source/male_heroic.blend` | `SuperHero_Male` | `01 - Connected waist pelvis and upper thighs` = 1.0; `02 - Balanced posterior and thigh transition` = 0.9; `03 - Approved regular facial identity` = 1.0 |
| `source/female_heroic.blend` | `Superhero_Female` | `01 - Natural waist and hip balance` = 1.0; `03 - Approved regular facial identity` = 1.0 |
| `source/male_teen.blend` | `Teen_Male` | `01 - Connected waist pelvis and upper thighs` = 1.0; `02 - Balanced posterior and thigh transition` = 0.76; `03 - Natural youthful face proportions` = 1.0 |
| `source/female_teen.blend` | `Teen_Female` | `01 - Natural waist and hip balance` = 1.0; `03 - Natural youthful face proportions` = 1.0 |

Controls span 0.0–1.5 and scale the named adjustment, not the entire body region. Each retains `Original Quaternius` as its untouched geometry Basis. Eye and brow/lash layers are on `Eyes` and `BrowDetail`; keep them synchronized with their matching face layer. Heroic facial binding follows the approved regular and is not reverted by setting the facial shape key to zero; use the untouched vendor file for a completely original rig-weight comparison.

These are **authoring controls**, not in-game character-creator sliders. GLBs contain the evaluated shapes without morph targets or embedded animation clips. Export only the active scene armature and its three mesh objects, freeze the evaluated shape in a disposable export session, and keep named skins. All source images are packed.

## Verified scope

Each saved source was reopened before export. Original Basis, topology, all UV layers, bone rests and hand/foot geometry were checked against that variant's vendor import. Teen skin weights remain exact. Heroic body weights outside the head/upper-neck transition remain exact; the head, eyes and brows deliberately use the approved regular binding. No skeletal rest edits were made.

Saved GLBs were checked against vendor materials: body base-color and normal image pixels match exactly, roughness channel and normal-map strength match, and named bones remain intact. Godot imports embed textures, retain named skins and do not import animations.

All four were inspected through the real Forward+ Outfitter using original/revised full-body front, side, rear, rear-oblique and face views, plus folded-arm profiles and sampled existing walking poses before their acceptance. Body approval does not establish compatibility with every garment.

Use the normal `tools/outfitter/outfitter.tscn`: **Human → Sex / body → Build: Heroic or Teen**. Build changes use production age/toughness rules and preserve compatible equipped items, the selected animation and camera. Default eyebrow styles reuse the fitted `BrowDetail` mesh through the shared actor/editor appearance assembly. No replacement preview catalog or temporary body resource is required.

## Shared wardrobe registration

Each variant is registered once in `tools/wardrobe/manifest.json`. The canonical human archetypes map its exact scene path through `wardrobe_profiles` to `assets/characters/wardrobe/<body-id>.res`. The traveler outfit and migrated vendor clothing each supply one source scene and `clothing_binding`; `ClothingFitter` generates the wearer mesh. Do not author or maintain a heroic/teen garment copy.

After changing an exported body surface, targeted-reimport it, rebuild the affected registration with `python3 tools/wardrobe/author.py build --body <id>`, and check `plan` for other stale dependencies. See `tools/wardrobe/README.md` for verification and body registration. Generated resources are not editable garment fits. Body changes still require live outfit review.

The current Height, Shoulders, Arm Length and Neck Length sliders deform the live skeleton, including its clothing, without per-frame fitting. They are separate from the Blender shape keys above. Future live mesh morphs require body-owned deformed cage input and fitting-cache invalidation; arbitrary morph fitting is not implemented.

## Provenance

Original meshes, skeletons, UVs and body/eye maps: **Quaternius Universal Base Characters**, recorded as CC0 1.0 Universal in `/home/dustin/mygame/ATTRIBUTION.md`. These are adaptations, not wholly original human meshes.

Sources remain under `/home/dustin/mygame/assets/vendor/quaternius/universal_base_characters/base_characters/`:

- `Superhero_Male_FullBody.gltf`
- `Superhero_Female_FullBody.gltf`
- `Teen_Male_FullBody.gltf`
- `Teen_Female_FullBody.gltf`
