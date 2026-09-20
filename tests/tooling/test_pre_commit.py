"""Hook contracts against real disposable Git indexes; no game or user repo edits."""
from pathlib import Path
import hashlib
import json
import os
import signal
import shutil
import subprocess
import sys
import tempfile
import time
import unittest


TOOLS = Path(__file__).resolve().parents[1]


class PreCommitTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="mygame-hook-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "repo with spaces"
        self.root.mkdir()
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith("GIT_")}
        self.env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
        self.git("init", "-q")
        (self.root / "tests").mkdir()
        (self.root / "tests/unit").mkdir()
        (self.root / "tests/unit/gutconfig.json").write_text("{}\n")
        (self.root / "addons/gut").mkdir(parents=True)
        (self.root / "addons/gut/gut_cmdln.gd").write_text("extends SceneTree\n")
        for name in ("pre_commit.py", "run_validation.py"):
            source = TOOLS / name
            if source.exists():
                shutil.copy2(source, self.root / "tests" / name)
        shutil.copytree(TOOLS / "hooks", self.root / "tests/hooks")
        (self.root / "project.godot").write_text('[application]\nconfig/name="Hook fixture"\n')
        (self.root / ".gitignore").write_text(".test-results/\n.godot/\n")
        (self.root / "rule.txt").write_text("good\n")
        # This fixture replaces only the process boundary. Separate acceptance
        # runs exercise the same hook with the real project's native GUT suite.
        (self.root / "tests/run.sh").write_text(
            '#!/bin/sh\nset -eu\n'
            'test "$#" -eq 1 && test "$1" = unit\n'
            'test ! -e unstaged-only.txt\n'
            'mkdir -p .test-results/unit\n'
            'printf \'<testsuites tests="1"/>\' > .test-results/unit/results.xml\n'
            'IFS= read -r value < rule.txt; test "$value" = good\n'
            'printf "STAGED_RULE_PASSED\\n"\n'
        )
        # Stub only Godot's import process, not Git/index materialization.
        importer = self.root / "importer"
        importer.write_text('#!/bin/sh\nexit 0\n')
        importer.chmod(0o755)
        self.env["GODOT"] = str(importer)
        self.git("add", ".")

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.root, env=self.env,
                              capture_output=True, check=True).stdout

    def invoke(self):
        hook = self.root / "tests/pre_commit.py"
        self.assertTrue(hook.is_file(), "Staged-snapshot pre-commit adapter is not implemented")
        index = Path(self.env.get("GIT_INDEX_FILE", self.root / ".git/index"))
        before = index.read_bytes()
        result = subprocess.run([sys.executable, str(hook)], cwd=self.root,
                                env=self.env, text=True, capture_output=True, timeout=30)
        self.assertEqual(index.read_bytes(), before,
                         "Hook must not modify the real index")
        self.assertFalse(list((self.root / ".test-results/pre-commit").glob("snapshot-*")),
                         "Disposable snapshots must be cleaned")
        return result

    def test_staged_success_ignores_unstaged_breakage_and_untracked_files(self):
        (self.root / "rule.txt").write_text("bad\n")
        (self.root / "unstaged-only.txt").write_text("not committed\n")
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("STAGED_RULE_PASSED", result.stdout)
        self.assertEqual((self.root / "rule.txt").read_text(), "bad\n")
        self.assertTrue((self.root / "unstaged-only.txt").exists())

    def test_staged_failure_cannot_be_hidden_by_unstaged_rule_or_runner_fixes(self):
        (self.root / "rule.txt").write_text("bad\n")
        self.git("add", "rule.txt")
        (self.root / "rule.txt").write_text("good\n")
        (self.root / "tests/run.sh").write_text("#!/bin/sh\nexit 0\n")
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("unit suite passed", result.stdout)
        self.assertEqual((self.root / "rule.txt").read_text(), "good\n")

    def test_parse_error_cannot_pass_when_gut_returns_zero(self):
        with (self.root / "tests/run.sh").open("a") as stream:
            stream.write("printf 'SCRIPT ERROR: Parse Error: broken test\\n'\n")
        self.git("add", "tests/run.sh")
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("unit suite passed", result.stdout)

    def test_asserted_native_push_error_is_not_mistaken_for_a_parse_error(self):
        with (self.root / "tests/run.sh").open("a") as stream:
            stream.write("printf 'ERROR: expected push_error, asserted by GUT\\n'\n")
        self.git("add", "tests/run.sh")
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_alternate_index_is_used_without_changing_the_default_index(self):
        default_index = self.root / ".git/index"
        before = default_index.read_bytes()
        alternate = self.root / ".git/alternate-index"
        shutil.copy2(default_index, alternate)
        self.env["GIT_INDEX_FILE"] = str(alternate)
        (self.root / "rule.txt").write_text("bad\n")
        self.git("add", "rule.txt")
        (self.root / "rule.txt").write_text("good\n")
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(default_index.read_bytes(), before)

    def test_missing_staged_setup_blocks_even_when_it_exists_in_worktree(self):
        self.git("rm", "--cached", "tests/unit/gutconfig.json")
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing staged tests/unit/gutconfig.json", result.stderr)

    def test_install_is_idempotent_and_preserves_other_hooks(self):
        push = self.root / ".git/hooks/pre-push"
        push.write_text("existing LFS hook\n")
        command = [sys.executable, str(self.root / "tests/pre_commit.py"), "--install"]
        for _ in range(2):
            result = subprocess.run(command, env=self.env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        hook = self.root / ".git/hooks/pre-commit"
        self.assertTrue(hook.is_symlink())
        self.assertTrue(os.access(hook, os.X_OK))
        self.assertEqual(push.read_text(), "existing LFS hook\n")
        hook.unlink()
        hook.write_text("existing user hook\n")
        result = subprocess.run(command, env=self.env, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(hook.read_text(), "existing user hook\n")

    def test_shared_selection_filter_cannot_turn_commit_gate_into_subset(self):
        (self.root / "tests/unit/gutconfig.json").write_text(json.dumps({"selected": "inventory"}))
        self.git("add", "tests/unit/gutconfig.json")
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("unfiltered", result.stderr)

    def test_missing_new_report_cannot_reuse_old_success(self):
        output = self.root / ".test-results/pre-commit"
        output.mkdir(parents=True)
        (output / "results.xml").write_text('<testsuites tests="1"/>')
        with (self.root / "tests/run.sh").open("a") as stream:
            stream.write("rm .test-results/unit/results.xml\n")
        self.git("add", "tests/run.sh")
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((output / "results.xml").exists())

    def test_submodule_uses_indexed_commit_not_its_head_or_dirty_worktree(self):
        submodule = self.root / "addons/vendor"
        self.git("init", "-q", str(submodule))
        value = submodule / "value.txt"
        value.write_text("pinned\n")
        self.git("-C", str(submodule), "add", ".")
        self.git("-C", str(submodule), "-c", "user.name=Fixture", "-c",
                 "user.email=fixture@example.invalid", "commit", "-qm", "pinned")
        self.git("add", "addons/vendor")
        value.write_text("wrong HEAD\n")
        self.git("-C", str(submodule), "-c", "user.name=Fixture", "-c",
                 "user.email=fixture@example.invalid", "commit", "-qam", "not in parent index")
        head = self.git("-C", str(submodule), "rev-parse", "HEAD")
        value.write_text("dirty\n")
        with (self.root / "tests/run.sh").open("a") as stream:
            stream.write('IFS= read -r value < addons/vendor/value.txt; test "$value" = pinned\n')
        self.git("add", "tests/run.sh")
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.git("-C", str(submodule), "rev-parse", "HEAD"), head)
        self.assertEqual(value.read_text(), "dirty\n")

    def test_lfs_uses_verified_local_object_not_worktree_bytes(self):
        data = b"indexed asset content\n"
        digest = hashlib.sha256(data).hexdigest()
        asset = self.root / "asset.txt"
        asset.write_text(f"version https://git-lfs.github.com/spec/v1\noid sha256:{digest}\nsize {len(data)}\n")
        cached = self.root / ".git/lfs/objects" / digest[:2] / digest[2:4] / digest
        cached.parent.mkdir(parents=True)
        cached.write_bytes(data)
        with (self.root / "tests/run.sh").open("a") as stream:
            stream.write('IFS= read -r value < asset.txt; test "$value" = "indexed asset content"\n')
        self.git("add", "asset.txt", "tests/run.sh")
        asset.write_text("unstaged wrong content\n")
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        cached.write_bytes(b"damaged\n")
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("damaged", result.stderr)

    def test_sigterm_cleans_snapshot_and_stops_import_process(self):
        ready = Path(self.temporary.name) / "import-pid"
        importer = self.root / "importer"
        importer.write_text(f"#!/bin/sh\nprintf '%s' \"$$\" > '{ready}'\nexec sleep 60\n")
        process = subprocess.Popen([sys.executable, str(self.root / "tests/pre_commit.py")],
                                   cwd=self.root, env=self.env, text=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 5
            while not ready.exists() and process.poll() is None and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(ready.exists(), "Import process did not start")
            child = int(ready.read_text())
            process.send_signal(signal.SIGTERM)
            stdout, stderr = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 130, stdout + stderr)
            with self.assertRaises(ProcessLookupError):
                os.kill(child, 0)
            self.assertFalse(list((self.root / ".test-results/pre-commit").glob("snapshot-*")))
        finally:
            if process.poll() is None:
                process.kill()
            process.communicate()


if __name__ == "__main__":
    unittest.main()
