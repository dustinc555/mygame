# Demo World Optimization Log

This log tracks benchmark-driven performance work for `res://scenes/worlds/demo_world/demo_world.tscn`.

The purpose is to preserve what was changed, what failed, and why. These are real efficiency issues, and future passes should use this log to avoid re-testing failed ideas without new evidence.

## Ground Rules

- Preserve fully realized NPC nodes. Do not use unrealized or unloaded actor fallback as the main optimization for this scene.
- Preserve gameplay semantics, public identifiers, groups, paths, selection/inspect UX, and ring visuals.
- Do not edit `addons/gecs/`; it is a git submodule.
- Optimize by measurement. Keep changes only when whole-scene benchmarks improve.
- Use 300-frame benchmark runs for screening only.
- Use 600-frame benchmark runs for acceptance.
- Run benchmarks sequentially. Parallel Godot runs contaminate timing.
- Revert neutral or worse experiments even when the code looks cheaper in isolation.

## Benchmark Command

Primary benchmark:

```sh
godot --headless --script res://scripts/benchmark/demo_world_benchmark.gd --demo-bench-samples=600
```

Useful profiling/isolation flags:

```sh
godot --headless --script res://scripts/benchmark/demo_world_benchmark.gd --demo-bench-samples=360 --humanoid-profile --utility-profile
godot --headless --script res://scripts/benchmark/demo_world_benchmark.gd --demo-bench-samples=300 --demo-bench-disable-idle-process=humanoid_character
godot --headless --script res://scripts/benchmark/demo_world_benchmark.gd --demo-bench-samples=300 --demo-bench-disable-physics-process=humanoid_character
```

## Accepted Benchmark Ledger

| State | Result | Notes |
| --- | ---: | --- |
| Historical initial baseline | `8.41 FPS / 118.84 ms` | Pre-optimization reference. |
| Rollback checkpoint `194da7a Optimize demo world humanoid AI and physics` | `33.67 FPS / 29.697 ms` | Stable baseline before the current pass. |
| Accepted GECS job-provider upsert state | `39.19 FPS / 25.514 ms` | Best accepted whole-scene 600-frame result from this pass. |
| Latest verification under current run variance | `38.19 FPS / 26.184 ms` | Same accepted code shape, slower run conditions. Kept as variance context, not a new accepted regression. |

## Accepted Changes

### GECS Job Provider Slot/Worker Upserts

File: `scripts/controllers/gecs_world_controller.gd`

Changed:

- `_sync_job_provider_slots()` now updates existing provider-slot entities when the slot ID is still present.
- `_sync_job_worker_records()` now updates existing worker-record entities when the worker record ID is still present.
- Stale slot and worker record entities are still removed when no longer expected.

Why it helped:

- The old code removed and recreated all provider-slot and worker-record ECS entities every sync.
- That caused entity churn, cache churn, node churn, and extra GECS query pressure.
- After upsert, ECS cache hit rate in accepted 600-frame runs rose to about `0.92`.
- Disabling `job_system_controller` after this change no longer showed the earlier large win, which indicates the job-system churn was mostly removed.

Accepted evidence:

- Before this change: `33.67 FPS / 29.697 ms`
- After this change: `39.19 FPS / 25.514 ms`
- Improvement: about `+5.52 FPS`, `-4.18 ms/frame`

### Benchmark Harness Idle/Physics Isolation Flags

File: `scripts/benchmark/demo_world_benchmark.gd`

Added:

- `--demo-bench-disable-idle-process=<group,...>` disables only `_process` for nodes in matching groups.
- `--demo-bench-disable-physics-process=<group,...>` disables only `_physics_process` for nodes in matching groups.

Why it helped:

- Separates idle `_process` cost from `_physics_process` cost.
- Confirmed `humanoid_character` idle `_process` is still the largest remaining bucket.

Isolation results after GECS upsert:

- Disable humanoid idle `_process`: about `50 FPS / 20 ms`
- Disable humanoid `_physics_process`: about `40 FPS / 25 ms`
- Conclusion: humanoid idle `_process` dominates remaining realized-NPC cost.

## Rejected Experiments

These were tested and reverted. Reattempt only if the surrounding code or benchmark evidence changes.

### Utility Context Reuse

Files tested:

- `scripts/ai/utility/ai_utility_adapter.gd`

Idea:

- Reuse one `AiUtilityContext` per adapter instead of allocating a new context every utility decision.

Why it seemed plausible:

- `UTILITY_PROFILE build_context` was the dominant utility section, around `1450-1550 us` per decision in profile runs.
- Reusing the context could reduce allocation churn.

Result:

- Initial 600-frame run looked slightly positive: `39.39 FPS / 25.385 ms`.
- Re-verification contradicted it: `37.49 FPS / 26.672 ms`.
- Reverted-context comparison under the same slower conditions was better: `38.19 FPS / 26.184 ms`.

Decision:

- Rejected as unstable and reverted.

### Utility Target/Work Copy Reduction

Files tested:

- `scripts/ai/utility/ai_utility_adapter.gd`
- `scripts/ai/utility/ai_utility_goal_selector.gd`
- `scripts/ai/utility/ai_utility_target_selector.gd`

Idea:

- Avoid duplicate dictionaries for target data, contracts, and work status during utility decision construction.

Why it seemed plausible:

- Utility decisions allocate and copy several nested dictionaries.
- The ECS goal-intent component eventually stores its own copy, so intermediate copies looked redundant.

Result:

- Validation passed.
- 300-frame screen: `38.98 FPS / 25.652 ms`.
- 600-frame acceptance: `39.16 FPS / 25.538 ms`, below the accepted `39.39 FPS / 25.385 ms` context-reuse screen and below the main accepted upsert ledger.

Decision:

- Rejected and reverted.

### Goal-Intent Debug Copy Reduction

File tested:

- `scripts/ai/utility/ai_utility_decision_result.gd`

Idea:

- Avoid deep-copying debug dictionaries in `AiUtilityDecisionResult.to_dictionary(true)` because `CGameGoalIntent.apply_decision()` deep-copies them again.

Why it seemed plausible:

- The existing path deep-copied debug data twice before storage.

Result:

- Validation passed.
- 300-frame screen: `38.91 FPS / 25.702 ms`.
- 600-frame acceptance failed badly: `38.32 FPS / 26.097 ms`.

Decision:

- Rejected and reverted.

### Direct Horizontal Speed Calculation

File tested:

- `scripts/characters/humanoid_character.gd`

Idea:

- Replace `Vector2(velocity.x, velocity.z).length()` with direct `sqrt(x*x + z*z)` in `_get_horizontal_speed()`.

Why it seemed plausible:

- Avoids constructing a `Vector2` in a function used by movement, animation, and needs.

Result:

- Behavior validations passed.
- 300-frame screen regressed: `36.88 FPS / 27.112 ms`.

Decision:

- Rejected and reverted.

### Utility Goal Intent Shallow/Fast Path

Files tested:

- `scripts/ai/utility/ai_utility_adapter.gd`

Idea:

- Use `get_actor_goal_intent(..., false)` and avoid or reduce cooldown/debug copies.

Result:

- Reverted after whole-scene timing did not improve.

Decision:

- Rejected.

### GECS Contract Indexing

Files tested:

- `scripts/controllers/gecs_world_controller.gd`

Idea:

- Index job contracts to reduce repeated contract queries.

Result:

- Reverted after whole-scene timing did not improve.

Decision:

- Rejected.

### Ground Marker Raycast Skips/Caches

Files tested:

- `scripts/characters/humanoid_character.gd`

Ideas:

- Skip marker raycasts when markers were invisible.
- Cache selection-ring lookups.
- Share marker raycast/cache results.

Why it seemed plausible:

- `HUMANOID_PROFILE ground_markers` was a top recurring `_process` bucket, usually around `16 us` per process.

Result:

- Reverted after whole-scene timing did not improve or regressed.

Decision:

- Rejected.

### Bone Offset Precomputation/Caches

Files tested:

- `scripts/characters/humanoid_character.gd`

Ideas:

- Precompute bone offset entries.
- Cache visual root and foot-correction lookups.

Why it seemed plausible:

- `HUMANOID_PROFILE bone_offsets` is the second-largest humanoid process bucket, around `27-29 us` per process.

Result:

- Reverted after whole-scene timing did not improve or regressed.

Decision:

- Rejected.

### Active Job Tick GECS Lookup Caches

Files tested:

- `scripts/characters/humanoid_character.gd`

Ideas:

- Cache GECS lookup in active job ticking.
- Cache or short-circuit GECS-driven active-job tick checks.

Why it seemed plausible:

- `HUMANOID_AI_PROFILE tick_active_job` was consistently a meaningful AI sub-bucket, around `10-11 us` per AI process.

Result:

- Reverted after whole-scene timing did not improve.

Decision:

- Rejected.

### Idle Animation Cadence Throttle

Files tested:

- `scripts/characters/humanoid_character.gd`

Idea:

- Reduce frequency of idle animation updates.

Why it seemed plausible:

- `HUMANOID_PROFILE character_animation` was around `13-14 us` per process.

Result:

- Reverted after whole-scene timing did not improve or regressed.

Decision:

- Rejected.

### Background Needs Cadence Split

Files tested:

- `scripts/characters/humanoid_character.gd`

Idea:

- Process background needs less often or split cadence for cheaper NPC updates.

Why it seemed plausible:

- `HUMANOID_PROFILE needs` was around `9-10 us` per process.

Result:

- Reverted after whole-scene timing did not improve.

Decision:

- Rejected.

### AI Job Validation Fast Path

Files tested:

- `scripts/characters/humanoid_character.gd`

Idea:

- Reduce repeated AI job validation work.

Result:

- Produced invalid benchmark runs with population failures.
- Error observed:

```text
SCRIPT ERROR: Invalid call. Nonexistent 'Array' constructor.
At PopulationController._merge_actor_state_into_record (res://scripts/controllers/population_controller.gd:458)
```

Decision:

- Invalid runs discarded.
- Experiment reverted.
- Population recovered to 36 humanoids after reverting.

## Current Hotspots

Latest stable profile shape after accepted GECS upsert:

| Section | Approx Cost |
| --- | ---: |
| `HUMANOID_PROFILE ai` | `49-52 us/process` |
| `HUMANOID_PROFILE bone_offsets` | `27-29 us/process` |
| `HUMANOID_PROFILE ground_markers` | `16 us/process` |
| `HUMANOID_PROFILE character_animation` | `13-14 us/process` |
| `HUMANOID_PROFILE needs` | `9-10 us/process` |
| `UTILITY_PROFILE build_context` | `1450-1550 us/decision` |
| `HUMANOID_AI_PROFILE tick_active_job` | `10-11 us/AI process` |

Interpretation:

- Humanoid idle `_process` remains the largest bucket.
- AI decision context building is the largest utility-AI sub-bucket.
- Bone offsets and ground markers are real costs, but multiple straightforward cache attempts failed whole-scene benchmarks.
- Do not assume less allocation or fewer method calls improves this workload. Godot/GDScript timing and scene behavior must be measured end to end.

## Validation Commands Run

```sh
godot --headless --script res://scripts/validation/validate_utility_ai_architecture.gd
godot --headless --script res://scripts/validation/validate_ai_population_architecture.gd
godot --headless --script res://scripts/validation/validate_fatigue_and_group_control.gd
godot --headless --script res://scripts/validation/validate_ragdoll_pyramid_smoke.gd
```

Latest final validation results:

```text
UTILITY_AI_ARCHITECTURE_OK
AI_POPULATION_ARCHITECTURE_OK
FATIGUE_GROUP_VALIDATION_OK
RAGDOLL_PYRAMID_SMOKE_OK
```

## Lessons Learned

- The largest accepted gain came from removing ECS entity churn, not from humanoid micro-optimizations.
- Benchmark harness improvements are valuable when they isolate real costs without changing gameplay.
- Short screens can lie. A change that wins once at 300 frames or even one 600-frame run can fail re-verification.
- Rejected experiments should stay rejected unless code shape, workload, or profiling evidence changes.
- Keep full population count in benchmark output. Runs with missing realized humanoids are invalid.
- Keep NPC nodes fully realized for this benchmark. Do not improve FPS by removing the workload under test.
