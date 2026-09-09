"""Blender-side conservative decimation for one static GLB candidate.

This implementation is intentionally small and single-purpose. It imports an
untouched GLB, applies one proportional Collapse Decimate modifier to each mesh,
and exports a different file. The orchestrator independently rejects changed
image payloads, material bindings, or a missed triangle target before the result
can reach production.

This is geometry reduction, not true retopology. It preserves existing UVs and
materials but does not rebuild edge flow, unwrap UVs, or bake high-poly detail.
Use real retopology plus baking when conservative decimation visibly damages a
manufactured edge, fitting, or silhouette.

Invoke through Blender:
    blender --background --python tools/asset_pipeline/decimate_static_glb.py -- \
        --source SOURCE.glb --output CANDIDATE.glb --target-triangles 500000
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import bpy  # type: ignore[import-not-found]


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--target-triangles", required=True, type=int)
    return parser.parse_args(argv)


def triangle_count(objects: list[bpy.types.Object]) -> int:
    return sum(len(polygon.vertices) - 2 for obj in objects for polygon in obj.data.polygons)


def main() -> None:
    """Build one candidate without ever overwriting the supplied source."""
    args = parse_args()
    source = args.source.expanduser().resolve()
    output = args.output.expanduser().resolve()
    if source == output:
        raise ValueError("Source and output must differ; the source is immutable.")
    if not source.is_file() or source.stat().st_size == 0:
        raise FileNotFoundError(f"Missing or empty source GLB: {source}")
    if args.target_triangles <= 0:
        raise ValueError("Target triangle count must be positive.")

    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not meshes:
        raise ValueError("Source GLB contains no mesh objects.")

    source_triangles = triangle_count(meshes)
    if args.target_triangles >= source_triangles:
        raise ValueError(
            f"Target {args.target_triangles} must be below source count {source_triangles}."
        )
    ratio = args.target_triangles / source_triangles

    for obj in meshes:
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        modifier = obj.modifiers.new(name="ConservativeDecimate", type="DECIMATE")
        modifier.decimate_type = "COLLAPSE"
        modifier.ratio = ratio
        modifier.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.select_set(False)

    bpy.ops.export_scene.gltf(
        filepath=str(output),
        export_format="GLB",
        export_apply=True,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
    )

    result = {
        "source": str(source),
        "output": str(output),
        "source_triangles": source_triangles,
        "candidate_triangles": triangle_count(meshes),
        "mesh_objects": len(meshes),
        "ratio": ratio,
    }
    print("STATIC_GLB_DECIMATE_OK=" + json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
