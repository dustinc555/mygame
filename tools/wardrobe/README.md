# Shared wardrobe authoring

**Author one garment; register each body once.** The current catalog has 27 shared-source items (four traveler garments and 23 vendor items), six canonical human body registrations and one original-male reference registration. Wearer meshes are generated views, not separately maintained race/sex/build clothing models.

This directory is the offline, CPU-only authoring tool, not another equipment runtime. It writes one native body registration per body and one native binding per authored garment. It never writes per-body garment meshes or modifies imported sources, ItemDefinitions, race slots, body archetypes, materials or runtime scripts. Production `ClothingFitter` performs the runtime adaptation.

## Human controls

Edit **`tools/wardrobe/manifest.json`**, then run `plan`, `build`, and `verify` below. Changes take effect when regenerated resources are reloaded; runtime fitting and mesh caches belong to the production fitter.

| Control | Meaning |
| --- | --- |
| `bodies[].id` | Stable output filename under `assets/characters/wardrobe/`. |
| `body_scene_path` | The actual PackedScene used by gameplay, including a body wrapper if applicable. |
| `registration_source_path`, `registration_mesh` | Original glTF/GLB and exact anatomy mesh node used for registration, not eyes, equipment or props. One triangle primitive is required. |
| `bodies[].preserve_foot_shape` | Optional, defaults to `false`. Enabled for the three female humans whose heel animation weights differ from the reference. Registers each complete calf/foot/ball region by geometry and preserves measured foot width, then blends into ordinary registration above the ankle. Male mappings and authored garments stay unchanged. Requires the named humanoid joints and a ground-aligned Y-up source. |
| `cage_source_body_id` | The body that defines shared cage point identities. Changing it requires a new correspondence review. |
| `enabled` | Include a manifest entry in normal authoring; disabling does not delete its existing resource or alter gameplay policy. |
| `garments[].source_scene_path` | The one maintained source scene. Every imported skinned surface is bound in its native Godot vertex order. |
| `reference_body_id` | The body for which that source garment was authored. Leather sources use canonical regular male; existing vendor sources use original regular male. |
| `clearance_ratio` | Source-reference normal offset, in addition to the garment's modeled ease. Generated `clearance_meters = ratio × reference height in skeleton units`; never multiply by target height. Traveler trousers use `0.002`; gauntlets, jacket and boots use `0.0`. The gauntlets have baked hand clearance and modeled guard room; extra normal inflation would also swell their fine trim. Peasant Trousers retain `0.016`. |
| `binding.influences` | Nearest cage controls per source vertex, default 12, range 1–32. |
| `binding.squared_distance_epsilon` | Squared-distance floor in the inverse-distance-cubed interpolation, default `1e-6`. |
| `binding.bind_transform_tolerance` | Maximum absolute disagreement between used rest × inverse-bind matrices, default `1e-5`. Inconsistent transforms or missing weighted joints fail. |
| `binding.skin_weight_penalty` | Default `0.004`. Append skin-weight coordinates, matched by named binds and scaled by the square root of this value, to the spatial neighbor metric. This discourages mixing nearby but different anatomy; it does not change garment animation weights. |
| `registration` | Advanced body-owned solver controls: six-decimal weld; stiffness stages 12, 6, 3, 1, 0.3; three iterations per stage; 32 candidate triangles; skin penalty 0.004; opposed-normal penalty 0.01. These defaults preserve the inspected algorithm. Changing them requires new visual proof. |

Unknown fields, duplicate IDs/source scenes, invalid numeric ranges, absent/disabled references, nonfinite data, invalid indices/weights, unsafe project paths and inconsistent bind frames are refused. Do not add an anatomy alias to make an incompatible glove appear supported.

`item_resource_paths` and `legacy_equipped_transform` record provenance only. The author never rewrites catalog resources or applies the legacy item transform. Noble Doublet's shared visual retains its nonidentity `equipped_transform`; its manifest clearance ratio is `0.01`. Knight Gambeson uses `0.0` to preserve its modeled under-armor fit. Peasant Shoes retain the original male source ratio `0.018`, not the historical female `0.012`.

## Add or change one item

1. Author one skinned source garment against a registered reference body. Preserve its cut, UVs, materials, named binds, rig rests and animation weights. Export only garment and rig; targeted-reimport the source before binding.
2. Add one `garments[]` entry to `manifest.json`: unique `id`, `enabled`, `source_scene_path`, `reference_body_id`, `clearance_ratio`, and the item's `item_resource_paths`. Do not create a garment entry per target body. For an existing garment, edit its existing entry/source.
3. Run `python3 tools/wardrobe/author.py build --garment <id>`, then `python3 tools/wardrobe/author.py verify --garment <id> --fresh-native`. Required reference/cage bodies are included automatically.
4. In the ItemDefinition's `equipped_visuals`, author one `EquipmentVisualDefinition`: set `visual_scene` to that source and `clothing_binding` to `assets/items/equipment/wardrobe_bindings/<id>.res`. Keep `surface_offset_ratio = 0.0`, leave `body_fits` empty, and do not hide anatomy through `replaces_body_slots`. Review item transforms and retain intended slot/race policy separately. The authoring command does not wire the item for you.
5. Reload the saved item in normal Outfitter and the character editor. Review materially different bodies, source-cut preservation, Idle/Walk, bends, slider extremes and independent slot removal/swaps. Regeneration and resource tests are not visual approval.

To add a body, add one `bodies[]` entry with its actual `body_scene_path`, `registration_source_path` and anatomy `registration_mesh`. Run `build --body <id>` and `verify --body <id> --fresh-native`, then map that exact scene path to `assets/characters/wardrobe/<id>.res` in the canonical `CharacterBodyArchetypeDefinition.wardrobe_profiles`. Check `plan` for stale dependencies after body edits. Registration does not itself grant equipment slots or establish anatomical compatibility. Never solve a missing profile with hand-maintained garment copies.

## Commands

From the repository root, with Python, NumPy, SciPy and the project Godot available:

```sh
# Legacy male-visual inventory suggestions; not the migrated catalog's source.
python3 tools/wardrobe/author.py discover

# Show missing/stale artifacts. Does not write asset outputs.
python3 tools/wardrobe/author.py plan

# Incremental build. Commits each successfully verified artifact to its index.
python3 tools/wardrobe/author.py build

# Load every native resource, re-export actual imported source arrays, and
# recompute/compare every binding's vertex order, transform, indices and weights.
python3 tools/wardrobe/author.py verify --fresh-native

# Bounded first proof: all enabled body profiles, just two source garments.
python3 tools/wardrobe/author.py build --body all \
  --garment traveler_trousers --garment peasant_trousers

# Rebuild only one source and its required body dependencies if stale.
python3 tools/wardrobe/author.py build --garment peasant_trousers

# Deliberate regeneration of selected resources, preserving existing UIDs.
python3 tools/wardrobe/author.py build --garment peasant_trousers --force

python3 -m unittest discover -s tests/tooling -p test_wardrobe_authoring.py -v
```

`--body`/`--garment` accept stable manifest IDs or `all` and are repeatable. No filters means all enabled entries. `--report <scratch-path.json>` saves machine-readable results; `--cache-dir` changes disposable intermediate storage; `--godot` selects the executable. Failed builds return nonzero. No implicit imports, GPU apps, network calls, credentials or project-wide tests are launched.

All Godot invocations, including version probes, use an exclusive `fcntl.flock` on **`/home/dustin/.hermes/cache/scratch/mygame-godot.lock`** by default. This is the same OS lock used by shell `flock` in other workers. A separate project-specific authoring lock prevents concurrent index updates. `--lock` exists for another checkout, not to bypass serialization on this checkout.

## Authoritative data flow

1. **`manifest.py`** validates explicit settings. `discover` only suggests entries from legacy male-archetype equipment visuals; migrated shared visuals have no such selector and can be omitted. It neither adds an item nor reconstructs the migrated catalog. Edit the explicit manifest for all new shared-source items.
2. **`provenance.py`** hashes source bytes, external glTF buffers/images, wrappers, import sidecars and imported scene data. Input fingerprints also include the solver settings, referenced body registration, authoring implementation and toolchain versions. Editing an unrelated garment does not invalidate its neighbors. Editing a body invalidates that body and bindings authored against that reference; changing the common cage source invalidates all profiles.
3. **`body_source.py` + `registration.py`** retain original glTF precision and the checked six-decimal weld/point order, named-rest alignment, skin-constrained surface ICP and Laplacian smoothing. Every final point is transformed into the imported target skeleton's rest coordinates; agreement is checked across every named rest. No garment participates in body registration.
4. **`native_bridge.gd`** loads the real imported PackedScene, exports actual surface arrays and named skin binds without reordering, and serializes JSON with full float precision. The body parser is **not** used to guess garment surface ordering.
5. **`binding.py`** validates all positively weighted binds against the reference body, normalizes mesh-to-skeleton coordinates, preserves source ease, and calculates 12-control inverse-distance-cubed displacement weights using spatial plus named skin-weight coordinates. These fitting weights are separate from the unchanged garment animation weights. Original mesh arrays/materials remain untouched.
6. Godot constructs the parent-owned resource classes and writes compressed native **`.res`** files through `ResourceSaver`. It validates and reloads the staged resource, preserves its existing UID, atomically replaces the target, and reloads the exact final path before reporting success.

Outputs and provenance:

- `assets/characters/wardrobe/<body-id>.res`
- `assets/characters/wardrobe/index.json` — input/byte fingerprints, UIDs, cage point hashes, source height, joints and registration diagnostics.
- `assets/items/equipment/wardrobe_bindings/<garment-id>.res`
- `assets/items/equipment/wardrobe_bindings/index.json` — source/reference fingerprints, exact imported surface hashes/counts, clearance and used joints.

Both indexes are generated, not human tuning files. Their artifact hashes reject modified or truncated outputs. A successful no-op build leaves resources and indexes untouched. The source graph is checked again before saving so concurrent source edits cannot silently publish mixed revisions. Interrupted work resumes per artifact. Existing resource UIDs are retained in the verified index because a fresh headless runtime may not know them from the editor's UID cache. If an existing artifact loses both that record and its editor-cache UID, the tool refuses to overwrite it: restore the index or scan the artifact in the editor first. It never silently replaces an unknown existing UID.

Godot imports must already be current: after editing a GLB/glTF **or any external buffer**, perform the project's targeted reimport before authoring. The tool deliberately does not start broad editor import scans or rewrite source sidecars. Imported-byte fingerprints and `--fresh-native` prevent using a stale authoring export cache; they do not perform the editor's import step for you.

Disposable JSON intermediates are under `$TMPDIR/wardrobe-authoring/<project-key>/`, never runtime dependencies. They may be deleted at any time. A clean build can regenerate every artifact without the original scratch experiment. Removing an entry does not automatically remove files, since integration might still reference them. Rollback means restoring the desired manifest and regenerating; remove obsolete artifacts only after their runtime references are deliberately migrated.

## Runtime ownership and limits

- `EquipmentVisualDefinition.visual_scene` + `clothing_binding` select one source. The 27 migrated items have no `body_fits` overrides; that field remains legacy support only. Historical GLBs/Blender files and vendor sources are preserved, not a list of fits to maintain.
- `CharacterBodyArchetypeDefinition.get_wardrobe_profile(body_scene_path)` resolves the body's `wardrobe_profiles` entry. `WardrobeBodyProfile.points` are corresponding cage points in skeleton-local rest space. Missing profiles, incompatible cages or missing positively weighted joints refuse fitting rather than silently selecting another anatomy.
- `ClothingFitter.fit(source, binding, target, skeleton)` is used by humanoid actor projection, character-editor preview and Bestiary equipment projection. It applies registered cage displacement to a copy of the source mesh, retains original skin weights/materials, and creates named skin binds for the target rests. Generated wearer meshes are disposable and are never hand-edited sources.
- Fitting is not a per-frame cloth/collision solver. Height, shoulder, arm and neck sliders use the live skeleton. Future mesh-morph sliders require body-owned deformed cage input plus fitting-cache invalidation; they are not automatically integrated.
- Runtime mesh reuse is bounded by `ClothingFitter`'s entry/byte limits; editor fitting bypasses that cache. Cache hits avoid recomputing the mesh, but cold fits still cost work. Do not infer instant first equip or large-crowd performance from source loading or cache reuse.
- Diagnose a visible hole in rest shape separately from animation weights. A small source-owned clearance can correct a millimeter-scale transfer overlap without remodeling the garment. Compare normal front/side/rear views, attached trim, full sampled walk/bend cycles and independent slot swaps before keeping it. More clearance is not a substitute for normal-looking clothes.

## Verification scope

All profiles retain 6,066 corresponding points after skeleton-coordinate normalization and native float32 storage. The male/reference point arrays remain unchanged. Female registrations correct the collapsed heel/instep region with `preserve_foot_shape`; points above the short ankle blend remain unchanged. This avoids matching different calf/foot animation-weight distributions as though they were anatomical correspondence. It does not alter the body mesh, garment source, animation weights or grounding. Registration diagnostics measure the solver, not attractive clothing or arbitrary-body compatibility.

Puglin is **deferred**, not assigned a glove fallback. The common cage has positive weights on missing `pinky_01/02/03_l/r` joints; absent toe and pinky leaf joints have zero cage weights. Registering the full cage faithfully needs an explicit body-owned anatomy decision. Puglin has no wardrobe profile and its current race slots are `weapon` and `offhand` only. No slot-policy change or runtime bone alias is authored here. QuadBot's unrelated rig is outside this humanoid contract.

Native authoring verification establishes data reproducibility, coordinate normalization, source ordering, exact stored arrays and resource loading. Runtime integration and catalog migration are implemented, but technical checks do not establish every garment's visual quality, cross-slot layering, animation clearance or gameplay performance. Minor finger, boot and layering clipping remains. Live source-cut/motion/slider review, the complete project unit suite and dependency-graph regeneration remain separate acceptance checks.
