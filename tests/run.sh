#!/usr/bin/env bash
# Select a suite; GUT and the existing validator runner own test execution.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
suite="${1:-unit}"
if (($#)); then shift; fi
cd "$root"

case "$suite" in
    unit)
        output="$root/.test-results/unit"
        mkdir -p "$output"
        data="$(mktemp -d "$output/userdata.XXXXXX")"
        trap 'rm -rf -- "$data"' EXIT
        export XDG_DATA_HOME="$data/data"
        export XDG_CONFIG_HOME="$data/config"
        export XDG_CACHE_HOME="$data/cache"
        "${GODOT:-godot}" --headless --path "$root" \
            --log-file "$output/engine.log" \
            -s res://addons/gut/gut_cmdln.gd \
            -gconfig=res://tests/unit/gutconfig.json "$@"
        ;;
    validation)
        exec "${PYTHON:-python3}" "$root/tests/run_validation.py" "$@"
        ;;
    benchmarks)
        exec "${PYTHON:-python3}" "$root/tests/run_validation.py" --benchmarks "$@"
        ;;
    -h|--help|help)
        printf '%s\n' \
            'Usage: ./tests/run.sh [unit|validation|benchmarks] [suite options]' \
            '  unit         Fast GUT tests only (default); forwards GUT CLI options.' \
            '  validation   Existing gameplay validators; forwards --filter, --jobs, --list, etc.' \
            '  benchmarks   Opt-in performance workloads; forwards validator runner options.' \
            'Guide: tests/TESTING.md'
        ;;
    *)
        printf 'Unknown suite: %s. Use ./tests/run.sh --help.\n' "$suite" >&2
        exit 2
        ;;
esac
