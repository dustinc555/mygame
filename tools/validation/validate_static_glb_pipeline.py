#!/usr/bin/env python3
"""Validate the reusable static-GLB harness and Tank's production contract.

This fast regression check does not optimize or replace an asset. It proves that
the installed Tank stays within its agreed triangle ceiling, carries embedded PBR
maps, uses safe Godot import settings, remains referenced by the production
wrapper, and cannot be passed as both immutable source and canonical destination.
The slower end-to-end review and visual inspection remain separate gates.
"""

from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path
from typing import NoReturn

PROJECT_ROOT = Path(__file__).resolve().parents[2]
PIPELINE_PATH = PROJECT_ROOT / "tools/asset_pipeline/static_glb_pipeline.py"
TANK_GLB = PROJECT_ROOT / "assets/world/props/water/tank/tank.glb"
TANK_IMPORT = Path(str(TANK_GLB) + ".import")
TANK_WRAPPER = (
    PROJECT_ROOT / "features/world/projection/props/furniture/tank.tscn"
)
MAX_TANK_TRIANGLES = 500_000


def fail(message: str) -> NoReturn:
    raise AssertionError(message)


def load_pipeline():
    specification = importlib.util.spec_from_file_location("static_glb_pipeline", PIPELINE_PATH)
    if specification is None or specification.loader is None:
        fail("Could not load static GLB pipeline module.")
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


def main() -> None:
    pipeline = load_pipeline()
    metrics = pipeline.inspect_glb(TANK_GLB)
    if metrics["triangles"] > MAX_TANK_TRIANGLES:
        fail(
            f"Tank exceeds {MAX_TANK_TRIANGLES} triangles: {metrics['triangles']}"
        )
    if metrics["images"] < 3 or metrics["embedded_images"] != metrics["images"]:
        fail("Tank must contain its full embedded PBR image set.")
    missing_maps = [
        name for name, present in metrics["material_maps"].items() if not present
    ]
    if missing_maps:
        fail("Tank is missing PBR maps: " + ", ".join(missing_maps))

    pipeline.verify_import_policy(TANK_GLB, metrics)
    wrapper_text = TANK_WRAPPER.read_text(encoding="utf-8")
    if "res://assets/world/props/water/tank/tank.glb" not in wrapper_text:
        fail("Production tank wrapper does not reference the canonical GLB.")

    refusal = subprocess.run(
        [
            sys.executable,
            str(PIPELINE_PATH),
            "--project-root",
            str(PROJECT_ROOT),
            "prepare",
            "--source",
            str(TANK_GLB),
            "--canonical",
            str(TANK_GLB),
            "--wrapper",
            "res://features/world/projection/props/furniture/tank.tscn",
            "--target-triangles",
            "1000",
        ],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if refusal.returncode == 0 or "Source and canonical paths must differ" not in refusal.stdout:
        fail("Pipeline no longer protects the immutable source from canonical overwrite.")

    print("STATIC_GLB_PIPELINE_OK")


if __name__ == "__main__":
    main()
