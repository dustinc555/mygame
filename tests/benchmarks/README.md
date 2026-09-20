# Opt-in benchmarks

Performance and optimization workloads live here, separate from fast unit tests and gameplay validation. Neither `./tests/run.sh` nor `./tests/run.sh validation` launches this folder, even through `--filter` or `--rerun-failed`; benchmarks require explicit selection.

From the project root:

```bash
./tests/run.sh benchmarks
./tests/run.sh benchmarks --list
./tests/run.sh benchmarks --filter combat_skirmish
```

The existing runner executes benchmarks serially with isolated project/user-data copies and unchanged error detection. Output replaces `.test-results/benchmarks/latest/index.html` plus its sibling JSON/logs, not the validation report. Generated output is hidden and Git-ignored. `./tests/run.sh benchmarks --rerun-failed` reads only the benchmark pointer. See [TESTING.md](../TESTING.md) for deadlines, saved reports and runner options.

## 20v20 combat

`validate_combat_skirmish_engagement.gd` runs the authored armory scene with all 40 actors, real physics and normal autoload startup. It records average/minimum process-frame FPS and worst frame time, and retains combat, animation, retreat, carry/drop, grounding and order-completion checks so a broken or missing workload cannot masquerade as an optimization.

The top-level constants `WARMUP_SECONDS`, `SAMPLE_SECONDS` and `FPS_FLOOR` own the timing settings: five-second warmup, 32-second sample, 40-FPS minimum target. Changes apply on the next run. Hold workload and these settings fixed when comparing optimizations; changing a target is not improving performance. The companion `.tscn` and script UID move with the benchmark.

A performance miss or gameplay error remains a failed benchmark, not an expected pass. This is headless process-frame timing, **not rendered gameplay FPS**. Other open Godot/editor processes may contend with a run; the runner serializes its own benchmarks but cannot establish machine-wide isolation.
