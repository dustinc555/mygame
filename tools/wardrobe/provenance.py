"""Content-addressed source graph (including glTF buffers and native imports)."""
from pathlib import Path
import hashlib
import json
import re
import struct
from urllib.parse import unquote, urlsplit


def digest_json(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()).hexdigest()


def file_digest(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def project_path(root, resource_path):
    if not isinstance(resource_path, str) or not resource_path.startswith("res://"):
        raise ValueError(f"expected res:// path, got {resource_path!r}")
    relative = resource_path[6:]
    if not relative or ".." in Path(relative).parts:
        raise ValueError(f"unsafe resource path {resource_path!r}")
    result = (Path(root) / relative).resolve()
    if not result.is_relative_to(Path(root).resolve()):
        raise ValueError(f"resource escapes project: {resource_path}")
    return result


def gltf_document(raw):
    if raw.startswith(b"version https://git-lfs"):
        raise ValueError("unhydrated Git LFS asset")
    if raw[:4] != b"glTF":
        return json.loads(raw)
    if len(raw) < 20:
        raise ValueError("truncated GLB")
    _, version, length = struct.unpack_from("<4sII", raw)
    if version != 2 or length != len(raw):
        raise ValueError("invalid GLB version/length")
    offset = 12
    document = None
    while offset < length:
        if offset + 8 > length:
            raise ValueError("truncated GLB chunk header")
        size, kind = struct.unpack_from("<II", raw, offset)
        offset += 8
        if offset + size > length:
            raise ValueError("truncated GLB chunk")
        if kind == 0x4E4F534A:
            document = json.loads(raw[offset:offset+size])
        offset += size
    if document is None:
        raise ValueError("GLB has no JSON document")
    return document


def dependencies(root, resource_path):
    """Return every local byte dependency; cycles are visited only once."""
    root = Path(root).resolve()
    found = {}

    def visit(path):
        path = path.resolve()
        if not path.is_relative_to(root):
            raise ValueError(f"dependency escapes project: {path}")
        key = path.relative_to(root).as_posix()
        if key in found:
            return
        if not path.is_file():
            raise ValueError(f"missing source dependency: {key}")
        found[key] = file_digest(path)
        suffix = path.suffix.lower()
        if suffix in (".gltf", ".glb"):
            doc = gltf_document(path.read_bytes())
            for entry in doc.get("buffers", []) + doc.get("images", []):
                uri = entry.get("uri", "")
                if not uri or uri.startswith("data:"):
                    continue
                parsed = urlsplit(uri)
                if parsed.scheme or parsed.netloc or parsed.query or parsed.fragment:
                    raise ValueError(f"non-local glTF URI: {uri}")
                visit(path.parent / unquote(parsed.path))
        elif suffix in (".tscn", ".tres", ".import"):
            # Includes .godot/imported geometry, textures, wrappers and scripts.
            for dependency in re.findall(r'"(res://[^"\n]+)"', path.read_text()):
                visit(project_path(root, dependency))
        sidecar = path.with_name(path.name + ".import")
        if suffix != ".import" and sidecar.is_file():
            visit(sidecar)

    visit(project_path(root, resource_path))
    return dict(sorted(found.items()))


def source_fingerprint(root, resource_path):
    return digest_json(dependencies(root, resource_path))


def artifact_is_current(root, path, fingerprint, record):
    artifact = project_path(root, path)
    return bool(record and record.get("source_digest") == fingerprint and
                artifact.is_file() and record.get("artifact_sha256") == file_digest(artifact))
