#!/usr/bin/env python3
"""Review and install a conservatively optimized static GLB without blind swaps.

This is a developer-only safety harness, not a Godot runtime importer. ``prepare``
preserves the source, asks Blender to create a candidate, verifies the candidate's
geometry/material contract, and renders source and candidate through the same
production wrapper. The canonical asset is temporarily swapped only for those
renders and is restored in ``finally``. ``install`` accepts only the exact
hash-recorded candidate from a completed review, backs up production, reimports,
and rolls production back if import or rendering fails.

The helper deliberately performs conservative global decimation. It does not
claim to create artist-authored topology, rebuild UVs, or bake new maps. See
``tools/asset_pipeline/README.md`` for the data flow, safety invariants, commands,
limits, and recovery behavior.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942
GLB_MAGIC = b"glTF"
RENDER_SCRIPT = "res://tools/asset_pipeline/render_static_prop_review.gd"
COMPARE_SCRIPT = "res://tools/asset_pipeline/compare_static_prop_renders.gd"


class PipelineError(RuntimeError):
    """Expected validation or tool failure with a user-readable reason."""

    pass


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_glb(path: Path) -> tuple[dict[str, Any], bytes]:
    data = path.read_bytes()
    if len(data) < 20:
        raise PipelineError(f"GLB is too small: {path}")
    magic, version, declared_length = struct.unpack_from("<4sII", data, 0)
    if magic != GLB_MAGIC or version != 2 or declared_length != len(data):
        raise PipelineError(f"Invalid GLB 2 header: {path}")
    document: dict[str, Any] | None = None
    binary = b""
    offset = 12
    while offset + 8 <= len(data):
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        offset += 8
        chunk = data[offset : offset + chunk_length]
        offset += chunk_length
        if chunk_type == JSON_CHUNK:
            document = json.loads(chunk.rstrip(b"\x00 \t\r\n"))
        elif chunk_type == BIN_CHUNK:
            binary = chunk
    if document is None:
        raise PipelineError(f"GLB has no JSON chunk: {path}")
    return document, binary


def accessor_count(document: dict[str, Any], index: int) -> int:
    return int(document.get("accessors", [])[index].get("count", 0))


def primitive_triangles(document: dict[str, Any], primitive: dict[str, Any]) -> int:
    mode = int(primitive.get("mode", 4))
    if "indices" in primitive:
        count = accessor_count(document, int(primitive["indices"]))
    else:
        position = primitive.get("attributes", {}).get("POSITION")
        count = accessor_count(document, int(position)) if position is not None else 0
    if mode == 4:
        return count // 3
    if mode in (5, 6):
        return max(0, count - 2)
    return 0


def image_hashes(document: dict[str, Any], binary: bytes) -> list[str]:
    hashes: list[str] = []
    views = document.get("bufferViews", [])
    for image in document.get("images", []):
        if "bufferView" not in image:
            hashes.append("external:" + str(image.get("uri", "missing")))
            continue
        view = views[int(image["bufferView"])]
        start = int(view.get("byteOffset", 0))
        end = start + int(view["byteLength"])
        hashes.append(hashlib.sha256(binary[start:end]).hexdigest())
    return hashes


def material_maps(document: dict[str, Any]) -> dict[str, bool]:
    maps = {"base_color": False, "normal": False, "metallic_roughness": False}
    for material in document.get("materials", []):
        pbr = material.get("pbrMetallicRoughness", {})
        maps["base_color"] = maps["base_color"] or "baseColorTexture" in pbr
        maps["metallic_roughness"] = (
            maps["metallic_roughness"] or "metallicRoughnessTexture" in pbr
        )
        maps["normal"] = maps["normal"] or "normalTexture" in material
    return maps


def inspect_glb(path: Path) -> dict[str, Any]:
    document, binary = load_glb(path)
    triangles = sum(
        primitive_triangles(document, primitive)
        for mesh in document.get("meshes", [])
        for primitive in mesh.get("primitives", [])
    )
    images = document.get("images", [])
    embedded_images = sum("bufferView" in image for image in images)
    return {
        "path": str(path),
        "sha256": sha256(path),
        "bytes": path.stat().st_size,
        "triangles": triangles,
        "meshes": len(document.get("meshes", [])),
        "materials": len(document.get("materials", [])),
        "images": len(images),
        "embedded_images": embedded_images,
        "image_hashes": image_hashes(document, binary),
        "material_maps": material_maps(document),
    }


def run_checked(command: list[str], cwd: Path, marker: str | None = None) -> str:
    completed = subprocess.run(
        command,
        cwd=cwd,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=600,
    )
    output = completed.stdout
    if completed.returncode != 0 or (marker and marker not in output):
        excerpt = "\n".join(output.splitlines()[-30:])
        raise PipelineError(
            f"Command failed ({completed.returncode}): {' '.join(command)}\n{excerpt}"
        )
    return output


def find_program(name: str, override_env: str) -> str:
    override = os.environ.get(override_env)
    program = override or shutil.which(name)
    if not program:
        raise PipelineError(f"Could not find {name}; set {override_env}.")
    return program


def reimport(project_root: Path, godot: str) -> None:
    run_checked(
        [godot, "--headless", "--editor", "--path", str(project_root), "--quit-after", "120"],
        project_root,
    )


def verify_import_policy(canonical: Path, metrics: dict[str, Any]) -> None:
    sidecar = Path(str(canonical) + ".import")
    if not sidecar.is_file():
        raise PipelineError(f"Godot import sidecar is missing: {sidecar}")
    text = sidecar.read_text(encoding="utf-8")
    if metrics["embedded_images"] and "gltf/embedded_image_handling=2" not in text:
        raise PipelineError(
            "Embedded-image GLB must keep gltf/embedded_image_handling=2 to prevent stale texture reuse."
        )
    if "meshes/generate_lods=true" not in text:
        raise PipelineError("Static production GLB must keep Godot mesh LOD generation enabled.")


def render(
    project_root: Path,
    godot: str,
    wrapper: str,
    output_dir: Path,
    prefix: str,
) -> list[str]:
    output_dir.mkdir(parents=True, exist_ok=True)
    output = run_checked(
        [
            godot,
            "--path",
            str(project_root),
            "--script",
            RENDER_SCRIPT,
            "--",
            f"--scene={wrapper}",
            f"--output-dir={output_dir}",
            f"--prefix={prefix}",
        ],
        project_root,
        "STATIC_PROP_REVIEW_OK",
    )
    return [
        line.split("=", 1)[1]
        for line in output.splitlines()
        if line.startswith("STATIC_PROP_REVIEW_RENDER=")
    ]


def compare_renders(
    project_root: Path,
    godot: str,
    baseline_paths: list[str],
    candidate_paths: list[str],
    max_mae: float,
    max_high_delta_percent: float,
) -> dict[str, dict[str, float]]:
    if len(baseline_paths) != len(candidate_paths) or not baseline_paths:
        raise PipelineError("Baseline and candidate render sets do not match.")
    baseline_directory = str(Path(baseline_paths[0]).parent)
    candidate_directory = str(Path(candidate_paths[0]).parent)
    output = run_checked(
        [
            godot,
            "--headless",
            "--path",
            str(project_root),
            "--script",
            COMPARE_SCRIPT,
            "--",
            f"--baseline-dir={baseline_directory}",
            f"--candidate-dir={candidate_directory}",
            "--baseline-prefix=baseline",
            "--candidate-prefix=candidate",
            f"--max-mae={max_mae}",
            f"--max-high-delta-percent={max_high_delta_percent}",
        ],
        project_root,
        "STATIC_PROP_COMPARE_OK",
    )
    for line in output.splitlines():
        if line.startswith("STATIC_PROP_COMPARE_JSON="):
            result = json.loads(line.split("=", 1)[1])
            return result
    raise PipelineError("Godot comparison did not emit metrics.")


def require_compatible_source_and_candidate(
    source: dict[str, Any],
    candidate: dict[str, Any],
    target: int,
    required_maps: set[str],
) -> None:
    if not candidate["triangles"]:
        raise PipelineError("Candidate has no triangle primitives.")
    tolerance = max(100, int(target * 0.02))
    if abs(candidate["triangles"] - target) > tolerance:
        raise PipelineError(
            f"Candidate triangle count {candidate['triangles']} missed target {target}."
        )
    for key in ("materials", "images", "embedded_images"):
        if candidate[key] != source[key]:
            raise PipelineError(
                f"Candidate changed {key}: {source[key]} -> {candidate[key]}."
            )
    if candidate["image_hashes"] != source["image_hashes"]:
        raise PipelineError("Candidate did not preserve the source image payloads byte-for-byte.")
    if candidate["material_maps"] != source["material_maps"]:
        raise PipelineError("Candidate changed material texture bindings.")
    missing = sorted(name for name in required_maps if not candidate["material_maps"].get(name))
    if missing:
        raise PipelineError("Candidate is missing required material maps: " + ", ".join(missing))


def project_path(project_root: Path, value: str) -> Path:
    path = Path(value).expanduser()
    return path.resolve() if path.is_absolute() else (project_root / path).resolve()


def prepare(args: argparse.Namespace) -> None:
    """Create and compare a candidate while guaranteeing production restoration."""
    project_root = args.project_root.resolve()
    source = project_path(project_root, args.source)
    canonical = project_path(project_root, args.canonical)
    if not (project_root / "project.godot").is_file():
        raise PipelineError(f"Not a Godot project: {project_root}")
    if source == canonical:
        raise PipelineError("Source and canonical paths must differ; preserve an untouched source.")
    if not source.is_file() or not canonical.is_file():
        raise PipelineError("Source and canonical GLBs must both exist.")
    if not args.wrapper.startswith("res://"):
        raise PipelineError("Wrapper must be an exact res:// production scene path.")

    review_dir = (
        project_path(project_root, args.review_dir)
        if args.review_dir
        else Path(tempfile.gettempdir())
        / "mygame-static-glb-review"
        / f"{canonical.stem}-{int(time.time())}"
    )
    review_dir.mkdir(parents=True, exist_ok=False)
    preserved_source = review_dir / "source.glb"
    candidate = review_dir / "candidate.glb"
    canonical_before = review_dir / "canonical_before.glb"
    shutil.copy2(source, preserved_source)
    shutil.copy2(canonical, canonical_before)

    source_metrics = inspect_glb(preserved_source)
    blender = find_program("blender", "BLENDER_BIN")
    godot = find_program("godot", "GODOT_BIN")
    decimator = project_root / "tools/asset_pipeline/decimate_static_glb.py"
    run_checked(
        [
            blender,
            "--background",
            "--python",
            str(decimator),
            "--",
            "--source",
            str(preserved_source),
            "--output",
            str(candidate),
            "--target-triangles",
            str(args.target_triangles),
        ],
        project_root,
        "STATIC_GLB_DECIMATE_OK=",
    )
    candidate_metrics = inspect_glb(candidate)
    required_maps = {value for value in args.require_maps.split(",") if value}
    require_compatible_source_and_candidate(
        source_metrics, candidate_metrics, args.target_triangles, required_maps
    )

    renders_dir = review_dir / "renders"
    try:
        shutil.copy2(preserved_source, canonical)
        reimport(project_root, godot)
        verify_import_policy(canonical, source_metrics)
        baseline_renders = render(
            project_root, godot, args.wrapper, renders_dir, "baseline"
        )

        shutil.copy2(candidate, canonical)
        reimport(project_root, godot)
        verify_import_policy(canonical, candidate_metrics)
        candidate_renders = render(
            project_root, godot, args.wrapper, renders_dir, "candidate"
        )
        render_comparison = compare_renders(
            project_root,
            godot,
            baseline_renders,
            candidate_renders,
            args.max_render_mae,
            args.max_high_delta_percent,
        )
    finally:
        shutil.copy2(canonical_before, canonical)
        reimport(project_root, godot)

    manifest = {
        "version": 1,
        "status": "awaiting_visual_review",
        "project_root": str(project_root),
        "canonical": str(canonical),
        "wrapper": args.wrapper,
        "candidate": str(candidate),
        "candidate_sha256": candidate_metrics["sha256"],
        "source": str(preserved_source),
        "source_metrics": source_metrics,
        "candidate_metrics": candidate_metrics,
        "required_maps": sorted(required_maps),
        "baseline_renders": baseline_renders,
        "candidate_renders": candidate_renders,
        "render_comparison": render_comparison,
        "render_thresholds": {
            "max_mae_255": args.max_render_mae,
            "max_delta_ge_16_percent": args.max_high_delta_percent,
        },
    }
    manifest_path = review_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(f"STATIC_GLB_REVIEW_READY={manifest_path}")
    for path in candidate_renders:
        print(f"CANDIDATE_RENDER={path}")


def install(args: argparse.Namespace) -> None:
    """Install the exact reviewed candidate, rolling back on any failed check."""
    if not args.confirm_visual_pass:
        raise PipelineError("Install requires --confirm-visual-pass after reviewing fixed-angle renders.")
    manifest_path = args.manifest.expanduser().resolve()
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("status") != "awaiting_visual_review":
        raise PipelineError("Manifest is not awaiting visual review.")
    project_root = Path(manifest["project_root"])
    canonical = Path(manifest["canonical"])
    candidate = Path(manifest["candidate"])
    if sha256(candidate) != manifest["candidate_sha256"]:
        raise PipelineError("Candidate changed after review; refusing installation.")

    current_metrics = inspect_glb(canonical)
    candidate_metrics = inspect_glb(candidate)
    required_maps = set(manifest["required_maps"])
    require_compatible_source_and_candidate(
        manifest["source_metrics"],
        candidate_metrics,
        candidate_metrics["triangles"],
        required_maps,
    )
    backup = manifest_path.parent / f"canonical_preinstall_{int(time.time())}.glb"
    shutil.copy2(canonical, backup)
    godot = find_program("godot", "GODOT_BIN")
    try:
        shutil.copy2(candidate, canonical)
        reimport(project_root, godot)
        verify_import_policy(canonical, candidate_metrics)
        final_renders = render(
            project_root,
            godot,
            manifest["wrapper"],
            manifest_path.parent / "renders",
            "installed",
        )
    except Exception:
        shutil.copy2(backup, canonical)
        reimport(project_root, godot)
        raise

    manifest["status"] = "installed"
    manifest["installed_sha256"] = sha256(canonical)
    manifest["replaced_metrics"] = current_metrics
    manifest["backup"] = str(backup)
    manifest["final_renders"] = final_renders
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(f"STATIC_GLB_INSTALL_OK={canonical}")
    for path in final_renders:
        print(f"INSTALLED_RENDER={path}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parents[2],
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    inspect_parser = subparsers.add_parser("inspect")
    inspect_parser.add_argument("glb", type=Path)

    prepare_parser = subparsers.add_parser("prepare")
    prepare_parser.add_argument("--source", required=True)
    prepare_parser.add_argument("--canonical", required=True)
    prepare_parser.add_argument("--wrapper", required=True)
    prepare_parser.add_argument("--target-triangles", required=True, type=int)
    prepare_parser.add_argument(
        "--require-maps",
        default="base_color,normal,metallic_roughness",
    )
    prepare_parser.add_argument("--review-dir")
    prepare_parser.add_argument("--max-render-mae", type=float, default=1.0)
    prepare_parser.add_argument("--max-high-delta-percent", type=float, default=1.0)

    install_parser = subparsers.add_parser("install")
    install_parser.add_argument("--manifest", required=True, type=Path)
    install_parser.add_argument("--confirm-visual-pass", action="store_true")

    args = parser.parse_args()
    if args.command == "inspect":
        print(json.dumps(inspect_glb(args.glb.expanduser().resolve()), indent=2, sort_keys=True))
    elif args.command == "prepare":
        prepare(args)
    else:
        install(args)


if __name__ == "__main__":
    try:
        main()
    except (PipelineError, OSError, subprocess.SubprocessError, json.JSONDecodeError) as error:
        print(f"STATIC_GLB_PIPELINE_ERROR={error}", file=sys.stderr)
        raise SystemExit(1) from error
