#!/usr/bin/env python3
"""Exact negative expectation for the vacancy validator, not a suite allowlist.

Godot cannot remove its native logger; disabling error printing also disables
custom Logger callbacks. OS.execute with captured output keeps this supervisor
and its child in the suite's process group (execute_with_pipe detaches on Unix).
Only this fixture's child output is data: use the unchanged root scanner, retain
both raw logs, and require the one diagnostic at the actual terminal transition.
With no arguments this file runs its classifier regression tests, without Godot.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from run_validation import scan_log

CHILD_TIMEOUT_SECONDS = 30
CHILD_ENV = "MYGAME_VACANCY_RETRY_CHILD"
CASE = "res://tests/validation/validate_vacant_staff_realization_loading.gd"
OK = "VACANT_STAFF_REALIZATION_LOADING_OK"


def diagnostic(cap: int) -> str:
    return f"ERROR: Visible assignment realization failed after {cap} attempts: validation_settlement/employment/failed_occupied"


def check_output(path: Path, exit_code: int, cap: int) -> list[str]:
    errors, count = scan_log(path)
    problems = []
    if exit_code != 0:
        problems.append(f"child exit code was {exit_code}, expected zero")
    if count != 1 or errors != [diagnostic(cap)]:
        problems.append(f"expected exactly one terminal diagnostic; detected {count}: {errors!r}")
    lines = path.read_text(errors="replace").splitlines()
    if lines.count(OK) != 1:
        problems.append("child must complete all vacancy, residence, retry and stopped-retry assertions exactly once")
    # Progress is emitted after each real call. The terminal error must occur
    # after state cap-1, before state cap, and never during the three later cycles.
    observed = [line for line in lines if line.startswith("VACANCY_RETRY_STATE ") or line == diagnostic(cap)]
    expected = [f"VACANCY_RETRY_STATE attempts=0 failures=0 loading=false"]
    for attempt in range(1, cap + 1):
        if attempt == cap:
            expected.append(diagnostic(cap))
        expected.append(f"VACANCY_RETRY_STATE attempts={attempt} failures={attempt} loading={'true' if attempt < cap else 'false'}")
    expected.extend([f"VACANCY_RETRY_STATE attempts={cap} failures={cap} loading=false"] * 3)
    if observed != expected:
        problems.append("retry/loading/diagnostic sequence differs from zero through the cap and three stopped cycles")
    return problems


def run_child(executable: str, project: str, evidence: str, cap: int) -> int:
    folder = Path(evidence)
    folder.mkdir(parents=True, exist_ok=False)
    output_path = folder / "output.log"
    command = [executable, "--headless", "--path", project,
               "--log-file", str(folder / "engine.log"), "--scene",
               "res://tests/validation/test_host.tscn", "--", CASE]
    environment = dict(os.environ, **{CHILD_ENV: "1"})
    stopped = None
    exit_code = -1
    with output_path.open("wb") as output:
        try:
            # No new session/process group: root cancellation reaches both us
            # and Godot. run() kills and reaps its child on this local deadline.
            result = subprocess.run(command, cwd=project, env=environment,
                                    stdout=output, stderr=subprocess.STDOUT,
                                    timeout=CHILD_TIMEOUT_SECONDS, start_new_session=False)
            exit_code = result.returncode
        except subprocess.TimeoutExpired:
            stopped = "child_timeout"
        except OSError as error:
            stopped = f"launch_error: {error}"
    problems = check_output(output_path, exit_code, cap)
    if stopped is not None:
        problems.append(stopped)
    (folder / "result.json").write_text(json.dumps({
        "command": command, "exit_code": exit_code, "stop_reason": stopped,
        "cap": cap, "expected_diagnostic": diagnostic(cap),
        "problems": problems, "raw_output": str(output_path),
    }, indent=2) + "\n")
    if problems:
        print("VACANCY_RETRY_TERMINAL_FAILED: " + "; ".join(problems), flush=True)
        print(f"Raw child evidence: {folder}", flush=True)
        return 1
    print(f"VACANCY_RETRY_TERMINAL_OK attempts={cap} stopped_cycles=3 diagnostic_count=1 evidence={folder}", flush=True)
    return 0


class DiagnosticContractTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name) / "output.log"
        # Classifier unit data only; runtime proof always executes production.
        self.cap = 2
        self.lines = [
            "VACANCY_RETRY_STATE attempts=0 failures=0 loading=false",
            "VACANCY_RETRY_STATE attempts=1 failures=1 loading=true",
            diagnostic(self.cap),
            *["VACANCY_RETRY_STATE attempts=2 failures=2 loading=false"] * 4,
            OK,
        ]

    def check(self, lines=None, code=0):
        self.path.write_text("\n".join(self.lines if lines is None else lines) + "\n")
        return check_output(self.path, code, self.cap)

    def test_exact_terminal_diagnostic(self):
        self.assertEqual(self.check(), [])

    def test_missing_diagnostic(self):
        self.assertTrue(self.check([line for line in self.lines if line != diagnostic(self.cap)]))

    def test_duplicate_diagnostic(self):
        self.assertTrue(self.check(self.lines + [diagnostic(self.cap)]))

    def test_unrelated_diagnostic_even_after_success(self):
        self.assertTrue(self.check(self.lines + ["ERROR: unrelated engine error"]))

    def test_early_diagnostic(self):
        lines = self.lines.copy()
        lines[1], lines[2] = lines[2], lines[1]
        self.assertTrue(self.check(lines))

    def test_incomplete_and_nonzero_child(self):
        self.assertTrue(self.check(self.lines[:-1]))
        self.assertTrue(self.check(code=1))

    def test_missing_or_incorrect_transition(self):
        self.assertTrue(self.check(self.lines[1:]))
        self.assertTrue(self.check(self.lines[:-2] + [OK]))
        self.assertTrue(self.check([line.replace("failures=1", "failures=0") for line in self.lines]))


if __name__ == "__main__":
    if len(sys.argv) == 6 and sys.argv[1] == "--child":
        sys.exit(run_child(sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5])))
    unittest.main()
