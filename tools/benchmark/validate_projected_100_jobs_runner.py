#!/usr/bin/env python3
"""Run and parse the default 100-actor projected Jobs benchmark."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MARKER = "PROJECTED_100_JOBS_BENCHMARK_RESULT "
RUNNER = "res://tools/benchmark/projected_100_jobs_benchmark_runner.gd"


def main() -> int:
    godot = shutil.which("godot")
    if godot is None:
        print("PROJECTED_100_JOBS_RUNNER_FAILED godot-not-found")
        return 1
    command = [
        godot,
        "--headless",
        "--path",
        str(ROOT),
        "--script",
        RUNNER,
        "--",
        "--benchmark-mode=jobs",
        "--benchmark-warmup=1",
        "--benchmark-sample=2",
    ]
    completed = subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=300,
        check=False,
    )
    result_lines = [line for line in completed.stdout.splitlines() if line.startswith(MARKER)]
    if completed.returncode != 0 or len(result_lines) != 1:
        print(completed.stdout)
        print(
            "PROJECTED_100_JOBS_RUNNER_FAILED "
            f"exit={completed.returncode} result_lines={len(result_lines)}"
        )
        return 1
    report = json.loads(result_lines[0][len(MARKER) :])
    end = report.get("end", {})
    failures: list[str] = []
    if report.get("actor_count") != 100:
        failures.append("runner did not use its default 100 actors")
    if end.get("actor_count") != 100 or end.get("projected_count") != 100:
        failures.append("not every default actor remained projected")
    if end.get("jobs_enabled_count") != 100 or end.get("alive_count") != 100:
        failures.append("not every default actor remained alive and Jobs-enabled")
    if report.get("sample_frames", 0) <= 0:
        failures.append("runner sampled no frames")
    if not end.get("farm_plot_id"):
        failures.append("runner had no authoritative farm")
    active_work = max(report.get("peak_active_work", 0), end.get("active_work_count", 0))
    advanced_work = report.get("distance_delta", 0.0) > 1.0 or report.get("completed_work_delta", 0) > 0
    if active_work <= 0 or not advanced_work:
        failures.append("runner produced no active farm claim plus movement or completion")
    if report.get("failures"):
        failures.append(f"runner reported failures: {report['failures']}")
    if failures:
        for failure in failures:
            print(f"ERROR: {failure}")
        print("PROJECTED_100_JOBS_RUNNER_FAILED")
        return 1
    print(
        "PROJECTED_100_JOBS_RUNNER_OK "
        f"avg_fps={report['avg_fps']:.2f} "
        f"p99_ms={report['frame_msec']['p99']:.2f} "
        f"active={end['active_work_count']}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
