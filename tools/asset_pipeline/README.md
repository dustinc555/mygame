# Static GLB Asset Pipeline

## Purpose

This directory contains a developer-only safety harness for replacing or optimizing a dense static GLB prop without blindly overwriting the production asset.

It exists because a successful GLB import is not enough. A replacement can silently reuse stale extracted textures, lose PBR bindings, miss its geometry budget, render differently through the real wrapper, change grounding, or break placement collision. The harness makes those failures visible before installation and restores the previous production GLB if a checked step fails.

This code is not loaded by gameplay, shipped as an autoload, or run per asset instance. It adds zero runtime cost to Tank instances and does not change how towns load or simulate.

## Scope

Use this workflow for one static GLB whose production scene already references a stable canonical asset path. The current production case is:

- canonical GLB: `assets/world/props/water/tank/tank.glb`
- production wrapper: `features/world/projection/props/furniture/tank.tscn`
- production ceiling: 500,000 triangles
- required maps: base color, normal, and metallic/roughness

Do not use this workflow for rigged characters, animation libraries, blend shapes, procedural runtime meshes, or assets that need real topology reconstruction and texture baking.

## What each file does

### `static_glb_pipeline.py`

The orchestrator and public command-line interface. It has three commands:

- `inspect` parses a GLB 2 file and reports its hash, size, triangle count, mesh/material/image counts, embedded image hashes, and PBR map bindings.
- `prepare` creates a candidate from an untouched source, checks it, renders baseline and candidate through the exact production wrapper, compares those renders, restores production, and writes a review manifest.
- `install` verifies the manifest and candidate hash, backs up production, installs the reviewed candidate, reimports it, verifies import policy, renders the installed wrapper, and rolls back on failure.

The orchestrator uses only the Python standard library. Blender and Godot are external executables because they own geometry conversion and production rendering respectively.

### `decimate_static_glb.py`

Runs inside Blender. It imports one source GLB, applies proportional Collapse Decimate modifiers, and exports one candidate GLB at a different path.

This is conservative global decimation, not true retopology. It does not rebuild edge flow, create a new UV layout, or bake high-poly detail. If the desired triangle budget visibly damages manufactured edges, fittings, corrugations, or silhouette, retain more geometry or use an artist/Smart Topology workflow with texture baking.

### `render_static_prop_review.gd`

Runs in Godot Forward+ as a temporary `SceneTree`. It loads the exact production wrapper, measures its visible mesh bounds, adds neutral lighting and ground, places a 1.8 m reference, and captures front-oblique, rear-oblique, side, and high views.

The script does not modify or save the production scene. Using the same wrapper, stage, cameras, and lighting for baseline and candidate makes the geometry swap the intended image variable.

### `compare_static_prop_renders.gd`

Runs in Godot and compares the four baseline/candidate PNG pairs. It reports:

- mean absolute RGB-channel error on a 0–255 scale;
- RMS RGB-channel error;
- percentage of RGB channels with an absolute difference of at least 16.

The default gate rejects mean error above `1/255` or more than `1%` high-delta channels. This catches broad visual drift without adding Pillow or another Python dependency. It cannot judge artistic quality or guarantee that a small fitting survived, so direct visual inspection remains mandatory.

### `../validation/validate_static_glb_pipeline.py`

A fast production regression guard. It checks the installed Tank's triangle ceiling, embedded PBR maps, safe Godot import settings, canonical wrapper reference, and the immutable-source refusal. It does not rerun Blender or claim visual approval.

## Data flow

`prepare` follows this sequence:

1. Resolve and validate the project, untouched source, canonical GLB, and production wrapper.
2. Create a new isolated review directory under `/tmp/mygame-static-glb-review/` unless an explicit directory is supplied.
3. Copy the source and current production GLB into that review directory.
4. Inspect and hash the preserved source.
5. Run Blender to generate `candidate.glb` from the preserved source.
6. Inspect the candidate and require its geometry/material/texture contract to match.
7. Temporarily place the preserved source at the canonical path, target-reimport, and render the baseline through the production wrapper.
8. Temporarily place the candidate at the same canonical path, target-reimport, and render the candidate through the same wrapper.
9. Run the Godot-native pixel-drift gate.
10. Restore and reimport the exact pre-review production GLB in a `finally` block.
11. Write `manifest.json` with hashes, metrics, thresholds, and render paths.

`install` follows this sequence:

1. Require `--confirm-visual-pass` and a manifest still marked `awaiting_visual_review`.
2. Re-hash the candidate and reject any post-review change.
3. Recheck geometry, materials, image payloads, and required map bindings.
4. Copy the current canonical GLB to a timestamped backup in the review directory.
5. Install and reimport the candidate at the stable canonical path.
6. Recheck embedded-image and generated-LOD import policy.
7. Render the installed production wrapper.
8. If any checked step fails, restore and reimport the backup before returning an error.
9. Mark the manifest `installed` and record the installed hash, backup, and final render paths.

## Safety invariants

- The source and canonical paths must differ. The immutable source cannot be used as the production destination.
- Every candidate starts from the preserved source, never from a previously decimated candidate.
- The requested triangle target must be positive and below the source count.
- Candidate triangle count must land within 2% of target, with a minimum tolerance of 100 triangles.
- Material count, image count, embedded-image count, image payload hashes, and PBR texture bindings must match the source.
- Required base-color, normal, and metallic/roughness maps must remain bound by default.
- Embedded-image GLBs must use `gltf/embedded_image_handling=2`. This prevents generic names such as `base_color` or `normal` from resolving to stale files extracted by an older GLB.
- Static production GLBs must keep `meshes/generate_lods=true` in their Godot import sidecar.
- Baseline and candidate use the same canonical path and production wrapper.
- Production is restored after `prepare`, including when preparation fails.
- Installation accepts only the hash recorded by `prepare`.
- Installation takes a backup before replacement and rolls back on import, policy, or final-render failure.
- Review artifacts stay in `/tmp`; source copies, candidates, manifests, backups, and screenshots are not project assets.

## Normal commands

Run from `/home/dustin/mygame`.

Inspect without changing production:

```bash
python3 tools/asset_pipeline/static_glb_pipeline.py inspect /absolute/path/to/model.glb
```

Prepare a Tank candidate:

```bash
python3 tools/asset_pipeline/static_glb_pipeline.py prepare \
  --source /absolute/path/to/untouched-tank.glb \
  --canonical assets/world/props/water/tank/tank.glb \
  --wrapper res://features/world/projection/props/furniture/tank.tscn \
  --target-triangles 500000
```

`prepare` prints the manifest path and candidate render paths. Inspect all four candidate views before installation. Reject new faceting, softened edges, collapsed fittings, UV stretch, stale textures, floating, or altered grounding.

Install the exact reviewed candidate:

```bash
python3 tools/asset_pipeline/static_glb_pipeline.py install \
  --manifest /tmp/mygame-static-glb-review/<review>/manifest.json \
  --confirm-visual-pass
```

Run the fast production guard:

```bash
python3 tests/validate_static_glb_pipeline.py
```

Compare an existing render set directly:

```bash
godot --headless --path . \
  --script res://tools/asset_pipeline/compare_static_prop_renders.gd -- \
  --baseline-dir=/tmp/review/renders \
  --candidate-dir=/tmp/review/renders \
  --baseline-prefix=baseline \
  --candidate-prefix=candidate
```

## Review artifacts

A review directory contains:

- `source.glb`: preserved copy of the untouched input;
- `candidate.glb`: Blender's generated candidate;
- `canonical_before.glb`: production as it existed before review;
- `renders/baseline_*.png`: untouched source through the production wrapper;
- `renders/candidate_*.png`: candidate through the same wrapper;
- `manifest.json`: hashes, metrics, thresholds, state, and paths;
- `canonical_preinstall_<timestamp>.glb`: installation backup, created only by `install`;
- `renders/installed_*.png`: final production evidence, created only by `install`.

The manifest states `awaiting_visual_review` after preparation and `installed` after successful installation. A manifest is evidence for one exact candidate, not reusable approval for later output.

## Failure and recovery behavior

- Invalid GLB header, missing paths, missing programs, changed texture payloads, missing maps, bad import settings, render drift, or a failed child process stops the workflow with `STATIC_GLB_PIPELINE_ERROR`.
- `prepare` restores `canonical_before.glb` and reimports it from `finally`.
- `install` restores its timestamped backup and reimports it if installation checks fail.
- If the host process is forcibly killed during the short temporary-swap window, rerun the fast validator before doing anything else. Restore `canonical_before.glb` from that review directory only if the canonical hash or validator proves production was not restored.
- Never delete Godot's whole import cache to fix one GLB. Reimport the canonical asset and verify the loaded material/hash boundary instead.

## Limitations

- Pixel drift is a broad regression signal, not an aesthetic verdict.
- Fixed review views do not prove the Add Facility placement route, collisions, navigation, or live-world lighting.
- Blender Decimate can preserve texture payloads while still harming edge flow or tiny geometry.
- The pipeline does not generate hand-authored LOD meshes. Godot's generated mesh LODs remain required, but unusually important props may still need authored LODs later.
- The pipeline temporarily swaps the canonical file during `prepare`; do not run two prepares for the same canonical asset concurrently.
- Force-killing the process can interrupt restoration. The preserved `canonical_before.glb`, hashes, and fast validator provide recovery evidence.
- Human visual approval is still the final artistic gate. Agent inspection can reject obvious damage but cannot declare Dustin's preferred look user-confirmed.

## Tank incident this prevents

The expensive Tank and the previous cheaper Tank both used generic embedded image names. Extracting the replacement's images beside the canonical GLB allowed Godot to reuse the previous Tank's files, making the new mesh render with the wrong surface. Keeping the replacement images embedded and enforcing `gltf/embedded_image_handling=2` fixed that class of stale-texture collision.

The expensive source has 966,516 triangles and three embedded 2048 PBR maps. The installed conservative candidate has 500,000 triangles, preserves those image payloads byte-for-byte, and passed identical-wrapper render comparison. The placement-camera bug was separate: the placement ray could hit the preview's own nested `StaticBody3D`; that behavior has its own physics regression test.

## Definition of done

A static GLB replacement is complete only when:

1. the source remains untouched;
2. the candidate satisfies geometry and PBR guards;
3. fixed-angle baseline/candidate comparison passes;
4. a human reviews the candidate images;
5. the exact candidate hash is installed with rollback protection;
6. the installed production wrapper is rendered and inspected;
7. authored collision is checked when visible bounds changed;
8. affected gameplay behavior has a focused regression when needed;
9. temporary review files remain outside the repository;
10. project notes record any newly discovered failure mode.
