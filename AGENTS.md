# Benchmark Validations

- Treat benchmark scripts and their `MIN_AVERAGE_FPS` thresholds as validation gates.
- All required benchmark validations for the task must pass before reporting success.
- Treat each FPS benchmark script's original measured FPS as a regression baseline in addition to its minimum threshold.
- Future FPS benchmark results must stay within 10 FPS of their original benchmark baseline.
- Always run the CombatBeat 30v30 golden benchmark before reporting success for any code change in this repo: `godot --headless --path . --script scripts/validation/benchmark_combat_beat_30v30_frame_rate.gd`.
- The CombatBeat 30v30 golden floor raised 2026-06-09 is `average_fps=39.75` over 420 sample frames. 30v30 must never drop below `39.75`; there is no 10 FPS allowance for this golden benchmark.
- If a benchmark validation fails, do not lower or change `MIN_AVERAGE_FPS` to make it pass.
- If a benchmark is more than 10 FPS below its original baseline, alert the user that a performance degradation/regression has occurred and report the benchmark script, original baseline, allowed floor, and measured FPS.
- Instead of lowering thresholds or baselines, alert the user that an inefficiency has been introduced and report the failing benchmark and measured FPS.
