# Testing

## Everyday command

```bash
./tests/run.sh
```

This runs **only GUT unit tests**. No world scenarios or benchmarks are included.
The starter suite protects existing production rules with small, independent
fixtures. Run the same tests from the editor's GUT panel using the shared settings
below.

The launcher works from any working directory when invoked by its full path.
Set `GODOT=/path/to/godot` to select an engine; validation also accepts `--godot`.

## Required testing policy

Run the **complete, unfiltered GUT suite after every project change before handing
work back**. Filtered runs are development feedback, not the final regression gate.
Keep unit tests fast, granular and behaviorally meaningful; add and maintain them
with features and fixes. They are the project's primary regression protection.

Continue writing and maintaining validation scripts for **whole feature workflows**
and their participating systems, rather than one script per small rule. Run the
relevant feature validations when behavior warrants them and benchmarks for
performance-sensitive work, without waiting for an extra request. These specialized
suites may be long; they supplement the always-run units. The authoritative agent
policy is in `../AGENT.md` under Validation.

## Layout

- `unit/`: fast `test_*.gd` scripts extending `GutTest`, plus `gutconfig.json`.
- `validation/`: existing gameplay validators, scenes, helpers and fixtures.
- `benchmarks/`: explicitly requested performance workloads.
- `run.sh`: thin suite selector; delegates to GUT or the existing Python runner.
- `run_validation.py`: isolated-process validation/benchmark runner.
- `pre_commit.py` and `hooks/pre-commit`: staged-content Git unit gate and installer.
- `tooling/`: fast Python selfchecks for the Git hook.
- `validation/suite.json`: validator discovery, launch modes, workers and timeouts.
- `../addons/gut/`: unmodified, vendored GUT addon and MIT license.

Unit tests must exercise real production rules, with controlled time/random inputs
and independent state. Avoid real-time sleeps, town startup and moving characters
when the question is a calculation or transaction. Include refusal and interruption
behavior, not just successful calls. The initial whole-unit-suite target is under
ten seconds on the development machine, to be measured as cases are added.

### Starter coverage

- `unit/test_inventory_transactions.gd`: conserved transfers, refused-operation
  rollback, exact stack identity/metadata, atomic recipe exchanges and notifications.
- `unit/test_farm_simulation.gd`: water-limited growth, dry-time boundaries and
  single-use harvest results that preserve cultivated ground.
- `unit/test_liquid_storage.gd`: reserved capacity, ownership changes, liquid
  compatibility and rejected persistence writes. Only the persistence port is a
  dictionary-backed double; production controller rules and indexes are exercised.
- `unit/test_combat_math.gd`: mixed damage channels and bounded hit probabilities.
- `unit/test_vitals_math.gd`: life-state boundaries, terminal death and healing limits.
- `unit/test_service_lifecycle.gd`: freed/retiring services, replacement and duplicate
  registration. The duplicate-registration test intentionally asserts its error
  with GUT's native `assert_push_error`; unexpected errors remain failures.

Keep adding focused regressions here as features change, rather than importing
whole validation scripts or copying gameplay logic into fixtures. These tests do
not prove physical movement, world wiring, full job dispatch or disk save/load.
Those remain the responsibility of the relevant validation scenarios.

When adding tests, verify that GUT actually discovers the new cases and check for
parse errors or ignored scripts, not only a green exit code. An unloadable script
can be skipped while the other tests pass. An intentionally empty selection keeps
GUT's native successful exit; it is not gameplay coverage.

## GUT

GUT **v9.6.1** is pinned to upstream commit
`c80954f47bed74a0a2c471d472c0389f98e0a8f6`. Only its `addons/gut/` directory is
vendored, not upstream's tests or documentation tree. No package manager is needed.
Let the editor finish importing after a fresh checkout or addon upgrade.

Enable/view it at **Project → Project Settings → Plugins → Gut**. The **GUT**
bottom panel runs tests inside the editor. Its settings have import/export buttons;
import `res://tests/unit/gutconfig.json` on a new machine. GUT stores the editor's
working preferences in `user://gut_temp_directory/`, not in project source.
The CLI always reads the checked-in configuration. After intentionally changing
shared editor settings, export them to that same file to keep the CLI consistent.

```bash
# Only scripts whose names contain inventory.
./tests/run.sh unit -gselect=inventory
# Only individual test names containing refuses.
./tests/run.sh unit -gunit_test_name=refuses
# Native GUT CLI help (also works before any cases exist).
godot --headless --path . -s addons/gut/gut_cmdln.gd -gh
```

GUT owns discovery, assertions, per-test output, lifecycle and exit status. Engine,
GUT and `push_error` diagnostics remain failure sources. Do not disable error
tracking or retry until green. CLI runs use a disposable, automatically cleaned
Godot user-data directory, so tests do not read or write normal game saves.

## Commit hook

Install once per checkout:

```bash
python3 tests/pre_commit.py --install
```

The local `.git/hooks/pre-commit` symlink calls `tests/pre_commit.py`. Each normal
Git commit runs the complete unit suite through the **staged** `tests/run.sh unit`
in a disposable project. Failed tests, unloadable/ignored test scripts, missing
setup and missing reports block the commit. Shared selection filters are rejected;
use command-line filters for development instead. GUT remains unmodified and owns
assertions and test results, including its intentionally empty-suite behavior.

Unstaged edits and untracked files are not tested or changed. The hook never
stashes, stages, resets or commits your work. Include `tests/` and `addons/gut/`
when committing the test setup; unstaged setup cannot satisfy a staged-content
gate. Submodules are exported at their indexed commits, not their dirty checkout
or current HEAD. LFS content comes from verified local objects; missing objects
block rather than silently falling back to working files or downloading assets.

Godot refreshes the private import/class caches before running GUT. Byte-identical
files retain their timestamps and imported assets are copied without writable
hard links. The import does not enable editor plugins; the exact staged project
settings are restored before the unit run. This preparation adds time beyond the
unit suite itself; the hook reports its total duration. `GODOT` selects the engine.
Safety limits are named at the top of `pre_commit.py` (import: 120 seconds; units:
60 seconds). Timeouts and cancellation terminate the test process group.

Logs and XML replace the same files in `.test-results/pre-commit/`; temporary
snapshots and user data are cleaned automatically. There is no file-save watcher,
CI setup, validation run or benchmark run in this hook. Existing hooks, including
Git LFS's pre-push hook, are left alone. The installer refuses an existing
pre-commit hook or a configured `core.hooksPath` rather than overwriting it.

Run the installed gate without making a commit with `git hook run pre-commit`.
Run its selfchecks with `python3 -m unittest discover -s tests/tooling -v`.
Git's explicit `git commit --no-verify` bypass remains available. To disable this
local installation, remove only the `.git/hooks/pre-commit` symlink; reinstall
with the command above. Hooks are local and are not automatically installed by
cloning the repository.

## Longer checks, on demand

```bash
./tests/run.sh validation --list
./tests/run.sh validation --filter inventory --jobs 1
./tests/run.sh validation                      # Explicit full validation run.
./tests/run.sh validation --rerun-failed
./tests/run.sh benchmarks --list
./tests/run.sh benchmarks --filter combat_skirmish
python3 -m unittest discover -s tests/validation -v  # Tooling selfchecks.
```

Scenarios and benchmarks may be long. Run the relevant ones when changing physical
movement, persistence, complete gameplay flows or measured performance; neither is
an automatic commit/push gate. The validation runner retains its launch modes,
timeouts, isolation, strict error detection and serial timing-sensitive cases.
`--jobs`, `--timeout`, `--filter`, `--rerun-failed` and `--report-dir` still work.
The benchmark retains its existing 40-FPS requirement and sample duration.

Relocation does not repair known failures. Historical reports remain evidence of
the source/run they actually tested. Old reports use old paths; rerun current
validators by filename with `--filter`, rather than editing old receipts.

## Output and scope

- Units: `.test-results/unit/engine.log` and `results.xml`.
- Validation: `.test-results/validation/latest/index.html` and `report.json`.
- Benchmarks: `.test-results/benchmarks/latest/index.html` and `report.json`.

These paths are project-relative, hidden and Git-ignored. Normal runs replace the
same output instead of creating numbered histories. Explicit validation report
archives must be empty destinations and never overwrite unrelated data. Previous
root audit documents/data have been archived as local evidence, not maintained
source. Unrelated tool configurations are left alone.

A successful unit run is not proof that all gameplay scenarios pass. Name the suite
and selection in every report, and disclose failures, timeouts and unrun coverage.
The optional local unit hook is described above; no CI workflows or production
behavior changes are part of the test tooling.
