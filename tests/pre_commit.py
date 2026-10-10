#!/usr/bin/env python3
"""Run the unit suite on the index, never on a stashed/modified working tree."""
from __future__ import annotations

import argparse
import filecmp
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET

from run_validation import ANSI, Test, copy_file, editor_plugin_settings

# Wall-clock safety limits, not gameplay/performance assertions.
IMPORT_TIMEOUT_SECONDS = 120
UNIT_TIMEOUT_SECONDS = 120
ROOT = Path(__file__).resolve().parent.parent


def git(root: Path, *args: str, env=None) -> bytes:
    return subprocess.run(["git", "-C", str(root), *args], env=env,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          check=True).stdout


def clean_git_environment(root: Path) -> dict:
    env = os.environ.copy()
    for name in git(root, "rev-parse", "--local-env-vars").decode().splitlines():
        env.pop(name, None)
    return env


def export_index(root: Path, destination: Path, index: Path, env: dict) -> None:
    """Export a private index, including gitlinks at their recorded commits."""
    local = {**env, "GIT_INDEX_FILE": str(index), "GIT_LFS_SKIP_SMUDGE": "1"}
    entries = git(root, "ls-files", "--stage", "-z", env=local).split(b"\0")
    if any(entry.split(b"\t", 1)[0].split()[-1] != b"0" for entry in entries if entry):
        raise RuntimeError("Resolve staged merge conflicts before committing.")
    destination.mkdir()
    git(root, "checkout-index", "--all", "--ignore-skip-worktree-bits",
        f"--prefix={destination}/", env=local)
    for entry in filter(None, entries):
        metadata, name = entry.split(b"\t", 1)
        mode, oid, _stage = metadata.split()
        path = Path(os.fsdecode(name))
        if mode == b"160000":
            # Never use a dirty submodule checkout or move its HEAD.
            submodule = root / path
            if not (submodule / ".git").exists():
                raise RuntimeError(f"Initialize submodule {path} before committing.")
            with tempfile.TemporaryDirectory(dir=index.parent, prefix="submodule-") as temporary:
                sub_index = Path(temporary) / "index"
                git(submodule, "read-tree", oid.decode(),
                    env={**env, "GIT_INDEX_FILE": str(sub_index)})
                target = destination / path
                if target.exists():
                    target.rmdir()  # checkout-index may create an empty gitlink directory.
                target.parent.mkdir(parents=True, exist_ok=True)
                export_index(submodule, target, sub_index, env)
        elif mode in (b"100644", b"100755"):
            target = destination / path
            if target.stat().st_size > 1024:
                continue
            pointer = re.fullmatch(
                rb"version https://git-lfs.github.com/spec/v1\noid sha256:([0-9a-f]{64})\nsize ([0-9]+)\n?",
                target.read_bytes())
            if pointer is None:
                continue
            digest = pointer[1].decode()
            storage = Path(os.fsdecode(git(root, "rev-parse", "--path-format=absolute",
                                         "--git-path", "lfs/objects", env=env).strip()))
            source = storage / digest[:2] / digest[2:4] / digest
            if not source.is_file():
                raise RuntimeError(f"LFS object for {path} is not local; fetch LFS assets first.")
            with source.open("rb") as stream:
                valid = hashlib.file_digest(stream, "sha256").hexdigest() == digest
            if not valid or source.stat().st_size != int(pointer[2]):
                raise RuntimeError(f"Local LFS object for {path} is damaged.")
            copy_file(source, target)


def run_logged(command: list[str], project: Path, log: Path, env: dict, timeout: int) -> int:
    """Bound the whole process group; preserve output on failure or interruption."""
    with log.open("wb") as stream:
        process = subprocess.Popen(command, cwd=project, env=env, stdout=stream,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            return process.wait(timeout=timeout)
        except (subprocess.TimeoutExpired, KeyboardInterrupt):
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            raise


def reuse_import_cache(root: Path, project: Path) -> None:
    """Seed native import caches; still let Godot rescan the staged project."""
    # A checkout changes every mtime. Preserve times only for byte-identical
    # files, otherwise the editor needlessly reimports every unchanged asset.
    for path in project.rglob("*"):
        source = root / path.relative_to(project)
        if (path.is_file() and not path.is_symlink() and source.is_file()
                and not source.is_symlink() and filecmp.cmp(path, source, shallow=False)):
            stamp = source.stat()
            os.utime(path, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
    imported = root / ".godot/imported"
    if imported.is_dir():
        shutil.copytree(imported, project / ".godot/imported", copy_function=copy_file)
    cache = root / ".godot"
    metadata = [cache / name for name in ("uid_cache.bin", "global_script_class_cache.cfg",
                                         "extension_list.cfg")]
    metadata.extend((cache / "editor").glob("filesystem_cache*"))
    for source in metadata:
        if source.is_file():
            target = project / ".godot" / source.relative_to(cache)
            target.parent.mkdir(parents=True, exist_ok=True)
            copy_file(source, target)


def check_staged(root: Path) -> int:
    output = root / ".test-results/pre-commit"
    output.mkdir(parents=True, exist_ok=True)
    with (output / "lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("Another pre-commit unit run is already active.")
        for name in ("import.log", "output.log", "engine.log", "results.xml"):
            (output / name).unlink(missing_ok=True)
        started = time.monotonic()
        env = clean_git_environment(root)
        with tempfile.TemporaryDirectory(prefix="snapshot-", dir=output) as temporary:
            workspace = Path(temporary)
            index = workspace / "index"
            source_index = Path(os.fsdecode(git(root, "rev-parse", "--path-format=absolute",
                                               "--git-path", "index").strip()))
            if not source_index.is_file():
                raise RuntimeError("Nothing is staged; add the project and unit tests first.")
            copy_file(source_index, index)
            project = workspace / "project"
            print("Pre-commit: running all unit tests on staged contents…", flush=True)
            export_index(root, project, index, env)
            for name in ("project.godot", "tests/run.sh", "tests/unit/gutconfig.json",
                         "addons/gut/gut_cmdln.gd"):
                if not (project / name).is_file():
                    raise RuntimeError(f"Missing staged {name}. Stage the test setup with the project.")
            config = json.loads((project / "tests/unit/gutconfig.json").read_text())
            if not isinstance(config, dict) or any(config.get(name) for name in
                                                 ("selected", "unit_test_name", "inner_class")):
                raise RuntimeError("The commit gate must be unfiltered; clear selection filters in gutconfig.json.")
            # Native import refreshes registries for staged additions/deletions
            # and changed source. Never skip that scan based on a previous pass.
            reuse_import_cache(root, project)
            limboai = root / "addons/limboai"
            if limboai.is_dir() and not (project / "addons/limboai").exists():
                shutil.copytree(limboai, project / "addons/limboai", copy_function=copy_file)
            env.update(XDG_DATA_HOME=str(workspace / "data"),
                       XDG_CONFIG_HOME=str(workspace / "config"),
                       XDG_CACHE_HOME=str(workspace / "cache"))
            engine = os.environ.get("GODOT", "godot")
            # Editor tools must not start services during this private import.
            # Restore the exact staged project settings before running GUT.
            with editor_plugin_settings(Test("pre-commit", "editor", "", editor_plugins=False), project):
                code = run_logged([engine, "--headless", "--editor", "--path", str(project),
                                   "--import"], project, output / "import.log", env,
                                  IMPORT_TIMEOUT_SECONDS)
            if code:
                raise RuntimeError(f"Staged project import failed; see {output / 'import.log'}")
            try:
                code = run_logged(["bash", str(project / "tests/run.sh"), "unit"], project,
                                  output / "output.log", env, UNIT_TIMEOUT_SECONDS)
            finally:
                for name in ("engine.log", "results.xml"):
                    source = project / ".test-results/unit" / name
                    if source.is_file():
                        copy_file(source, output / name)
            text = (output / "output.log").read_text(errors="replace")
            print(text, end="" if text.endswith("\n") else "\n")
            if code:
                return code if code > 0 else 1
            # GUT owns assertions and exit status, but an unloadable script can
            # be ignored before its error tracker starts. Never accept that as
            # a complete run. Expected errors asserted by GUT remain valid.
            diagnostic = re.search(
                r"SCRIPT ERROR:|ERROR: Failed to (?:load|instantiate)|"
                r"Ignoring (?:script|Inner Class) .*because it does not extend GutTest|"
                r"!!! .* could not be loaded", ANSI.sub("", text))
            if diagnostic:
                raise RuntimeError(f"Unit startup/discovery error; see {output / 'output.log'}")
            try:
                ET.parse(output / "results.xml")
            except (OSError, ET.ParseError) as error:
                raise RuntimeError("GUT did not produce a valid fresh results.xml.") from error
            print(f"Pre-commit: unit suite passed ({time.monotonic() - started:.1f}s including snapshot/import).")
            return 0


def install(root: Path) -> None:
    configured = subprocess.run(["git", "-C", str(root), "config", "--get", "core.hooksPath"],
                                capture_output=True, text=True)
    if configured.returncode == 0:
        raise RuntimeError("core.hooksPath is already configured; refusing to replace your hook setup.")
    hooks = Path(os.fsdecode(git(root, "rev-parse", "--path-format=absolute", "--git-path", "hooks").strip()))
    source = root / "tests/hooks/pre-commit"
    target = hooks / "pre-commit"
    if target.is_symlink() and target.resolve() == source:
        print(f"Already installed: {target}")
        return
    if target.exists() or target.is_symlink():
        raise RuntimeError(f"Existing hook left untouched: {target}")
    source.chmod(source.stat().st_mode | 0o111)
    hooks.mkdir(parents=True, exist_ok=True)
    target.symlink_to(os.path.relpath(source, hooks))
    print(f"Installed: {target} -> {source}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--install", action="store_true", help="Install this checkout's local pre-commit hook")
    args = parser.parse_args()
    def cancel(_signum, _frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, cancel)
    try:
        if args.install:
            install(ROOT)
            return 0
        return check_staged(ROOT)
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print(f"Pre-commit blocked: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr.decode(errors="replace"), file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("Pre-commit cancelled.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
