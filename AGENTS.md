# Benchmark Validations

- Treat benchmark scripts and their `MIN_AVERAGE_FPS` thresholds as validation gates.
- All required benchmark validations for the task must pass before reporting success.
- Treat each FPS benchmark script's original measured FPS as a regression baseline in addition to its minimum threshold.
- Future FPS benchmark results must stay within 10 FPS of their original benchmark baseline.
- If a benchmark validation fails, do not lower or change `MIN_AVERAGE_FPS` to make it pass.
- If a benchmark is more than 10 FPS below its original baseline, alert the user that a performance degradation/regression has occurred and report the benchmark script, original baseline, allowed floor, and measured FPS.
- Instead of lowering thresholds or baselines, alert the user that an inefficiency has been introduced and report the failing benchmark and measured FPS.
