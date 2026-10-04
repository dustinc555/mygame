#!/usr/bin/env python3
"""Reproducible, CPU-only body registration and native garment binding authoring."""
from pathlib import Path
import argparse
import fcntl
import hashlib
import json
import math
import os
import subprocess
import sys
import tempfile
import time
import numpy as np
import scipy

from binding import bind_scene, points_array
from body_source import mesh_data, world_to_skeleton
from manifest import BODY_ROOT, BINDING_ROOT, discover, load
from provenance import artifact_is_current, dependencies, digest_json, file_digest, project_path
from registration import register, transform

HERE = Path(__file__).resolve().parent
DEFAULT_ROOT = HERE.parents[1]
DEFAULT_LOCK = Path.home() / ".hermes/cache/scratch/mygame-godot.lock"
BODY_INDEX = BODY_ROOT + "index.json"
BINDING_INDEX = BINDING_ROOT + "index.json"


def atomic_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    encoded = json.dumps(data, indent=2, sort_keys=True, allow_nan=False) + "\n"
    temporary = path.with_name(path.name + ".building")
    temporary.write_text(encoded)
    os.replace(temporary, path)


def read_index(root, path):
    local = project_path(root, path)
    if not local.exists():
        return {"schema_version": 1, "artifacts": {}}
    value = json.loads(local.read_text())
    if value.get("schema_version") != 1 or not isinstance(value.get("artifacts"), dict):
        raise ValueError(f"invalid artifact index: {path}")
    return value


def select_entries(manifest, body_ids, garment_ids):
    bodies = {entry["id"]: entry for entry in manifest["bodies"] if entry.get("enabled", True)}
    garments = {entry["id"]: entry for entry in manifest["garments"] if entry.get("enabled", True)}
    all_requested = not body_ids and not garment_ids
    selected_bodies = set(bodies) if all_requested or "all" in body_ids else set(body_ids)
    selected_garments = set(garments) if all_requested or "all" in garment_ids else set(garment_ids)
    if selected_bodies - bodies.keys() or selected_garments - garments.keys():
        raise ValueError("unknown or disabled requested body/garment id")
    selected_bodies.update(garments[key]["reference_body_id"] for key in selected_garments)
    selected_bodies.add(manifest["cage_source_body_id"])
    return ([entry for entry in bodies.values() if entry["id"] in selected_bodies],
            [entry for entry in garments.values() if entry["id"] in selected_garments])


class Author:
    def __init__(self, args):
        self.args = args
        self.root = args.project.resolve()
        self.manifest = load(args.manifest, self.root)
        self.cache = args.cache_dir.resolve() / hashlib.sha256(str(self.root).encode()).hexdigest()[:12]
        self.cache.mkdir(parents=True, exist_ok=True)
        self.engine = self.command(["--headless", "--version"]).strip()
        self.implementation = digest_json({path.name: file_digest(path) for path in sorted(HERE.iterdir()) if path.suffix in (".py", ".gd")})
        self.toolchain = {"engine": self.engine, "numpy": np.__version__, "scipy": scipy.__version__,
                          "implementation": self.implementation}
        self.body_index = read_index(self.root, BODY_INDEX)
        self.binding_index = read_index(self.root, BINDING_INDEX)
        self.sources = {}
        self.native = {}
        self.raw_bodies = {}
        self.profiles = {}
        self.fingerprints = {}

    def command(self, arguments):
        self.args.lock.parent.mkdir(parents=True, exist_ok=True)
        with self.args.lock.open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            completed = subprocess.run([self.args.godot, *arguments], cwd=self.root, text=True,
                                       capture_output=True, timeout=self.args.timeout)
        text = completed.stdout + completed.stderr
        if completed.returncode != 0 or "SCRIPT ERROR:" in text or "ERROR:" in text:
            raise RuntimeError(f"Godot authoring failed ({completed.returncode}):\n{text}")
        return text

    def bridge(self, operation, **values):
        with tempfile.TemporaryDirectory(prefix="native-", dir=self.cache) as temporary:
            request = Path(temporary) / "request.json"
            output = Path(temporary) / "response.json"
            atomic_json(request, {"operation": operation, "output": str(output), **values})
            text = self.command(["--headless", "--path", str(self.root), "--script",
                                 "res://tools/wardrobe/native_bridge.gd", "--", str(request)])
            if "WARDROBE_NATIVE_OK" not in text or not output.is_file():
                raise RuntimeError(f"native authoring returned no success/result:\n{text}")
            return json.loads(output.read_text())["results"]

    def source(self, path):
        if path not in self.sources:
            self.sources[path] = dependencies(self.root, path)
        return self.sources[path]

    def body_fingerprint(self, entry):
        key = entry["id"]
        if key not in self.fingerprints:
            canonical = next(body for body in self.manifest["bodies"] if body["id"] == self.manifest["cage_source_body_id"])
            controls = {k: v for k, v in entry.items() if k not in ("notes", "enabled")}
            inputs = {"toolchain": self.toolchain, "cage_id": self.manifest["cage_id"],
                      "settings": self.manifest["registration"], "body": controls,
                      "scene_dependencies": self.source(entry["body_scene_path"]),
                      "registration_dependencies": self.source(entry["registration_source_path"]),
                      "canonical_source": self.source(canonical["registration_source_path"]),
                      "canonical_mesh": canonical["registration_mesh"]}
            self.fingerprints[key] = (digest_json(inputs), inputs)
        return self.fingerprints[key]

    def garment_fingerprint(self, entry):
        body = next(body for body in self.manifest["bodies"] if body["id"] == entry["reference_body_id"])
        controls = {key: entry[key] for key in ("source_scene_path", "reference_body_id", "clearance_ratio")}
        inputs = {"toolchain": self.toolchain, "settings": self.manifest["binding"], "garment": controls,
                  "reference_digest": self.body_fingerprint(body)[0],
                  "scene_dependencies": self.source(entry["source_scene_path"])}
        return digest_json(inputs), inputs

    def plan(self, bodies, garments):
        jobs = []
        for kind, entries, base, index, fingerprint in [
            ("body", bodies, BODY_ROOT, self.body_index, self.body_fingerprint),
            ("binding", garments, BINDING_ROOT, self.binding_index, self.garment_fingerprint)]:
            for entry in entries:
                path = base + entry["id"] + ".res"
                source_digest, inputs = fingerprint(entry)
                current = artifact_is_current(self.root, path, source_digest, index["artifacts"].get(entry["id"]))
                jobs.append({"kind": kind, "id": entry["id"], "path": path, "source_digest": source_digest,
                             "rebuild": bool(self.args.force or not current), "inputs": inputs})
        return jobs

    def export_sources(self, paths):
        missing = []
        for path in sorted(set(paths)):
            if path in self.native:
                continue
            key = digest_json({"source": self.source(path), "bridge": self.implementation, "engine": self.engine})
            cache_file = self.cache / ("scene-" + key + ".json")
            if cache_file.is_file() and not self.args.fresh_native:
                cached = json.loads(cache_file.read_text())
                if cached.get("sha256") == digest_json(cached.get("data")):
                    self.native[path] = cached["data"]
                    continue
            missing.append((path, cache_file))
        if missing:
            results = self.bridge("export", scenes=[path for path, _ in missing])
            if len(results) != len(missing):
                raise RuntimeError("native export count mismatch")
            for (path, cache_file), value in zip(missing, results):
                if value["scene_path"] != path:
                    raise RuntimeError("native export scene order mismatch")
                self.native[path] = value
                atomic_json(cache_file, {"sha256": digest_json(value), "data": value})

    def raw_body(self, entry):
        key = entry["id"]
        if key not in self.raw_bodies:
            self.raw_bodies[key] = mesh_data(project_path(self.root, entry["registration_source_path"]),
                                             entry["registration_mesh"], self.manifest["registration"]["weld_decimals"])
        return self.raw_bodies[key]

    def skeleton(self, entry):
        native = self.native[entry["body_scene_path"]]
        matching = [mesh for mesh in native["meshes"] if mesh["mesh_path"].split("/")[-1] == entry["registration_mesh"]]
        if len(matching) != 1:
            raise ValueError(f"{entry['id']}: imported registration mesh is ambiguous/missing")
        candidates = [skeleton for skeleton in native["skeletons"] if skeleton["path"] == matching[0]["skeleton_path"]]
        if len(candidates) != 1:
            raise ValueError(f"{entry['id']}: imported body skeleton is ambiguous/missing")
        return candidates[0]["rests"]

    def check_sources_unchanged(self, inputs):
        for path, files in self.sources.items():
            # Revalidate the known graph, including external glTF buffers.
            for relative, digest in files.items():
                if file_digest(self.root / relative) != digest:
                    raise RuntimeError(f"source changed during authoring: {path} ({relative}); retry")

    def save(self, job, data, details):
        self.check_sources_unchanged(job["inputs"])
        index, index_path = ((self.body_index, BODY_INDEX) if job["kind"] == "body" else (self.binding_index, BINDING_INDEX))
        previous = index["artifacts"].get(job["id"], {})
        saved = self.bridge("save", jobs=[{"kind": job["kind"], "path": job["path"], "data": data,
                                          "preserve_uid": previous.get("uid", "")}])
        if len(saved) != 1 or not saved[0].get("verified"):
            raise RuntimeError("native artifact verification failed")
        index["artifacts"][job["id"]] = {"path": job["path"], "source_digest": job["source_digest"],
            "artifact_sha256": file_digest(project_path(self.root, job["path"])), "uid": saved[0]["uid"],
            "inputs": job["inputs"], **details}
        atomic_json(project_path(self.root, index_path), index)
        print(f"BUILT {job['kind']} {job['id']} -> {job['path']}", flush=True)

    def build_body(self, job, entry, source):
        target = self.raw_body(entry)
        settings = dict(self.manifest["registration"], preserve_foot_shape=entry.get("preserve_foot_shape", False))
        points, metrics = register(source, target, settings)
        normalization = world_to_skeleton(target[4], self.skeleton(entry), self.manifest["binding"]["bind_transform_tolerance"])
        points = transform(normalization, points).astype(np.float32)
        points_array(points, "registered cage")
        data = {"cage_id": self.manifest["cage_id"], "body_scene_path": entry["body_scene_path"],
                "source_digest": job["source_digest"], "points": points.tolist(), "bone_aliases": {}}
        height = float(np.ptp(transform(normalization, target[0])[:, 1]))
        self.save(job, data, {"point_count": len(points), "height_m": height,
                             "points_sha256": hashlib.sha256(points.astype("<f4").tobytes()).hexdigest(),
                             "registration_metrics": metrics, "bone_names": sorted(target[4]),
                             "runtime_bone_aliases": {}, "visual_acceptance": "not established by authoring metrics"})
        self.profiles[entry["id"]] = data

    def read_profiles(self, bodies):
        missing = [body for body in bodies if body["id"] not in self.profiles]
        if missing:
            paths = [BODY_ROOT + body["id"] + ".res" for body in missing]
            for body, result in zip(missing, self.bridge("read", paths=paths)):
                self.profiles[body["id"]] = result["data"]

    def binding_data(self, entry, source_digest):
        reference_id = entry["reference_body_id"]
        body = next(body for body in self.manifest["bodies"] if body["id"] == reference_id)
        reference = self.profiles[reference_id]
        clearance = float(entry["clearance_ratio"] * self.body_index["artifacts"][reference_id]["height_m"])
        canonical = next(body for body in self.manifest["bodies"] if body["id"] == self.manifest["cage_source_body_id"])
        cage_source = self.raw_body(canonical)
        surfaces, details = bind_scene(self.native[entry["source_scene_path"]], self.skeleton(body),
                                       reference["points"], clearance, self.manifest["binding"],
                                       cage_source[2], cage_source[3])
        data = {"reference_profile": BODY_ROOT + reference_id + ".res", "source_scene_path": entry["source_scene_path"],
                "source_digest": source_digest, "clearance_meters": clearance, "surfaces": surfaces}
        details.update({"clearance_ratio": entry["clearance_ratio"], "clearance_meters": clearance,
                        "reference_body_id": reference_id, "item_resource_paths": entry.get("item_resource_paths", []),
                        "legacy_equipped_transform": entry.get("legacy_equipped_transform", "identity"),
                        "visual_acceptance": "not established by binding generation"})
        return data, details

    def build(self, bodies, garments, jobs):
        pending = [job for job in jobs if job["rebuild"]]
        if not pending:
            return {"built": 0, "skipped": len(jobs), "artifacts": [job["path"] for job in jobs]}
        canonical = next(body for body in self.manifest["bodies"] if body["id"] == self.manifest["cage_source_body_id"])
        entries = {entry["id"]: entry for entry in bodies + garments}
        body_jobs = [job for job in pending if job["kind"] == "body"]
        garment_jobs = [job for job in pending if job["kind"] == "binding"]
        needed_bodies = {job["id"] for job in body_jobs} | {entries[job["id"]]["reference_body_id"] for job in garment_jobs}
        self.export_sources([body["body_scene_path"] for body in bodies if body["id"] in needed_bodies])
        source = self.raw_body(canonical)
        for job in body_jobs:
            self.build_body(job, entries[job["id"]], source)
        if garment_jobs:
            references = {entries[job["id"]]["reference_body_id"] for job in garment_jobs}
            self.read_profiles([body for body in bodies if body["id"] in references])
            self.export_sources([entries[job["id"]]["source_scene_path"] for job in garment_jobs])
            for job in garment_jobs:
                data, details = self.binding_data(entries[job["id"]], job["source_digest"])
                self.save(job, data, details)
        return {"built": len(pending), "skipped": len(jobs)-len(pending), "artifacts": [job["path"] for job in jobs]}

    def verify(self, bodies, garments, jobs):
        stale = [job["id"] for job in jobs if job["rebuild"]]
        if stale:
            raise ValueError(f"missing, stale, or tampered artifacts; build first: {stale}")
        self.export_sources([body["body_scene_path"] for body in bodies] + [item["source_scene_path"] for item in garments])
        values = {entry["path"]: entry["data"] for entry in self.bridge("read", paths=[job["path"] for job in jobs])}
        counts = set()
        for body in bodies:
            profile = values[BODY_ROOT + body["id"] + ".res"]
            points = points_array(profile["points"], "native profile").astype("<f4")
            record = self.body_index["artifacts"][body["id"]]
            if hashlib.sha256(points.tobytes()).hexdigest() != record["points_sha256"]:
                raise ValueError("native body points differ from generated fingerprint")
            if profile["body_scene_path"] != body["body_scene_path"] or profile["cage_id"] != self.manifest["cage_id"] or profile["bone_aliases"]:
                raise ValueError("body metadata/anatomy alias mismatch")
            counts.add(len(points))
            self.profiles[body["id"]] = profile
        if len(counts) != 1:
            raise ValueError("profiles do not share cage topology")
        vertices = 0
        surfaces = 0
        for item in garments:
            path = BINDING_ROOT + item["id"] + ".res"
            actual = values[path]
            expected, _ = self.binding_data(item, self.garment_fingerprint(item)[0])
            if actual["source_scene_path"] != expected["source_scene_path"] or actual["reference_profile"] != expected["reference_profile"] or not math.isclose(actual["clearance_meters"], expected["clearance_meters"], rel_tol=0, abs_tol=1e-15):
                raise ValueError(f"binding metadata differs: {item['id']}")
            if len(actual["surfaces"]) != len(expected["surfaces"]):
                raise ValueError(f"native surface count differs: {item['id']}")
            for a, b in zip(actual["surfaces"], expected["surfaces"]):
                for key in ("mesh_path", "surface_index", "vertex_count", "influences"):
                    if a[key] != b[key]:
                        raise ValueError(f"imported surface order/count differs: {item['id']} {key}")
                for key in ("mesh_to_reference", "cage_indices", "cage_weights"):
                    dtype = np.int32 if key == "cage_indices" else np.float32
                    if not np.array_equal(np.asarray(a[key], dtype=dtype), np.asarray(b[key], dtype=dtype)):
                        raise ValueError(f"native surface payload differs: {item['id']} {key}")
                vertices += a["vertex_count"]
                surfaces += 1
        for job in jobs:
            if values[job["path"]]["source_digest"] != job["source_digest"]:
                raise ValueError(f"native source digest differs: {job['id']}")
        self.check_sources_unchanged({})
        return {"verified_profiles": len(bodies), "verified_bindings": len(garments),
                "cage_points": counts.pop(), "surfaces": surfaces, "vertices": vertices}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("discover", "plan", "build", "verify"))
    parser.add_argument("--project", type=Path, default=DEFAULT_ROOT)
    parser.add_argument("--manifest", type=Path, default=HERE / "manifest.json")
    parser.add_argument("--body", action="append", default=[], help="body id or all; repeatable")
    parser.add_argument("--garment", action="append", default=[], help="garment id or all; repeatable")
    parser.add_argument("--force", action="store_true", help="rebuild selected artifacts, preserving UIDs")
    parser.add_argument("--fresh-native", action="store_true", help="bypass disposable source export cache")
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    parser.add_argument("--lock", type=Path, default=DEFAULT_LOCK)
    parser.add_argument("--timeout", type=int, default=240)
    parser.add_argument("--cache-dir", type=Path, default=Path(os.environ.get("TMPDIR", str(Path.home()/".cache"))) / "wardrobe-authoring")
    parser.add_argument("--report", type=Path, help="optional JSON run report (outside source assets)")
    args = parser.parse_args(argv)
    if args.command == "discover":
        result = {"garments": discover(args.project.resolve())}
    else:
        start = time.monotonic()
        author = Author(args)
        # Prevent concurrent authoring from losing incremental index updates.
        with (author.cache / "authoring.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            author.body_index = read_index(author.root, BODY_INDEX)
            author.binding_index = read_index(author.root, BINDING_INDEX)
            bodies, garments = select_entries(author.manifest, args.body, args.garment)
            jobs = author.plan(bodies, garments)
            if args.command == "plan":
                result = {"rebuild": sum(job["rebuild"] for job in jobs), "current": sum(not job["rebuild"] for job in jobs),
                          "jobs": [{key: value for key, value in job.items() if key != "inputs"} for job in jobs]}
            elif args.command == "build":
                result = author.build(bodies, garments, jobs)
            else:
                result = author.verify(bodies, garments, jobs)
        result["elapsed_seconds"] = round(time.monotonic() - start, 3)
    if args.report:
        atomic_json(args.report, result)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, RuntimeError, OSError, KeyError, subprocess.TimeoutExpired) as error:
        print(f"WARDROBE_AUTHORING_ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
