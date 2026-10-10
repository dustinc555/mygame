"""Editable authoring contract and read-only catalog discovery."""
from pathlib import Path
import json
import math
import re
from provenance import project_path

BODY_ROOT = "res://assets/characters/wardrobe/"
BINDING_ROOT = "res://assets/items/equipment/wardrobe_bindings/"
VENDOR_ROOT = "res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/"
DEFAULT_REGISTRATION = {"weld_decimals": 6, "stiffness": [12.0, 6.0, 3.0, 1.0, 0.3],
                        "iterations_per_stage": 3, "candidate_triangles": 32,
                        "skin_weight_penalty": 0.004, "opposed_normal_penalty": 0.01}
DEFAULT_BINDING = {"influences": 12, "squared_distance_epsilon": 1e-6,
                   "bind_transform_tolerance": 1e-5, "skin_weight_penalty": 0.004}


def discover(root):
    """Discover existing male visual references, not unreferenced vendor files.

    Emits suggestions only. Does not rewrite the manifest or gameplay resources.
    The explicit manifest remains authoritative after catalog migration.
    """
    found = {}
    for path in sorted((Path(root) / "features/inventory/resources/items").glob("*.tres")):
        text = path.read_text()
        external = {}
        for header in re.findall(r'^\[ext_resource (.+)\]$', text, re.M):
            attrs = dict(re.findall(r'(\w+)="([^"]*)"', header))
            external[attrs.get("id")] = attrs.get("path", "")
        used_visuals = set()
        resource_section = text.rsplit("[resource]", 1)[-1]
        equipped = re.search(r'^equipped_visuals\s*=\s*(.*)$', resource_section, re.M)
        if equipped:
            used_visuals = set(re.findall(r'SubResource\("([^"]+)"\)', equipped[1]))
        for header, fields in re.findall(r'\[sub_resource ([^\]]+)\]\s*([^\[]*)', text):
            attributes = dict(re.findall(r'(\w+)="([^"]*)"', header))
            if attributes.get("id") not in used_visuals:
                continue
            ref = re.search(r'^visual_scene\s*=\s*ExtResource\("([^"]+)"\)', fields, re.M)
            body = re.search(r'^body_archetype\s*=\s*ExtResource\("([^"]+)"\)', fields, re.M)
            if not ref:
                continue
            source = external.get(ref[1], "")
            body_path = external.get(body[1], "") if body else ""
            male = body_path.endswith("/human_male.tres") or 'body_archetype_id = "human_male"' in fields
            if not male:
                continue
            vendor = source.startswith(VENDOR_ROOT) and Path(source).name.startswith("Male_")
            leather = source.startswith("res://assets/items/equipment/") and Path(source).name == "male_regular.glb"
            if not vendor and not leather:
                continue
            offset = re.search(r'^surface_offset_ratio\s*=\s*([\d.eE+-]+)', fields, re.M)
            ratio = float(offset[1]) if offset else 0.0
            transform = re.search(r'^equipped_transform\s*=\s*(.*)', fields, re.M)
            item_path = "res://" + path.relative_to(root).as_posix()
            if source in found:
                if found[source]["clearance_ratio"] != ratio:
                    raise ValueError(f"shared source has conflicting clearance: {source}")
                found[source]["item_resource_paths"].append(item_path)
                continue
            found[source] = {"id": path.stem, "enabled": True, "source_scene_path": source,
                             "reference_body_id": "original_male_regular" if vendor else "male_regular",
                             "clearance_ratio": ratio, "item_resource_paths": [item_path],
                             "notes": "Preserve source cut and skin weights; no per-body garment meshes."}
            if transform:
                found[source]["legacy_equipped_transform"] = transform[1].strip()
    return sorted(found.values(), key=lambda item: item["id"])


def _keys(data, allowed, label):
    unknown = set(data) - set(allowed)
    if unknown:
        raise ValueError(f"{label}: unknown fields {sorted(unknown)} (possible typo)")


def _number(value, minimum, maximum, label, integer=False):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not minimum <= value <= maximum:
        raise ValueError(f"{label}: expected finite value in [{minimum}, {maximum}]")
    if integer and type(value) is not int:
        raise ValueError(f"{label}: expected integer")


def validate(data, root):
    _keys(data, ["schema_version", "cage_id", "cage_source_body_id", "registration", "binding", "bodies", "garments", "notes"], "manifest")
    if data.get("schema_version") != 1 or not isinstance(data.get("cage_id"), str) or not data["cage_id"]:
        raise ValueError("invalid manifest schema_version/cage_id")
    registration = data["registration"]
    binding = data["binding"]
    if set(registration) != set(DEFAULT_REGISTRATION) or set(binding) != set(DEFAULT_BINDING):
        raise ValueError("registration/binding settings must have exactly the documented keys")
    _number(registration["weld_decimals"], 0, 9, "weld_decimals", True)
    _number(registration["iterations_per_stage"], 1, 20, "iterations_per_stage", True)
    _number(registration["candidate_triangles"], 1, 256, "candidate_triangles", True)
    if not registration["stiffness"] or len(registration["stiffness"]) > 20:
        raise ValueError("stiffness must contain 1..20 stages")
    for value in registration["stiffness"]:
        _number(value, 0, 1000, "stiffness")
    for key in ["skin_weight_penalty", "opposed_normal_penalty"]:
        _number(registration[key], 0, 10, key)
    _number(binding["influences"], 1, 32, "influences", True)
    _number(binding["squared_distance_epsilon"], 1e-15, 1, "squared_distance_epsilon")
    _number(binding["bind_transform_tolerance"], 1e-8, 0.001, "bind_transform_tolerance")
    _number(binding["skin_weight_penalty"], 0, 1, "binding skin_weight_penalty")
    ids = {"bodies": set(), "garments": set()}
    scenes = {"bodies": set(), "garments": set()}
    for group in ids:
        if not isinstance(data[group], list) or not data[group]:
            raise ValueError(f"{group} must be a nonempty list")
        for entry in data[group]:
            common = ["id", "enabled", "notes"]
            extra = (["body_scene_path", "registration_source_path", "registration_mesh", "preserve_foot_shape"] if group == "bodies" else
                     ["source_scene_path", "reference_body_id", "clearance_ratio", "item_resource_paths", "legacy_equipped_transform"])
            _keys(entry, common + extra, group)
            identity = entry.get("id", "")
            if not re.fullmatch(r"[a-z][a-z0-9_]*", identity) or identity in ids[group]:
                raise ValueError(f"duplicate or unsafe {group} id {identity!r}")
            ids[group].add(identity)
            if type(entry.get("enabled", True)) is not bool:
                raise ValueError("enabled must be a boolean")
            source_key = "body_scene_path" if group == "bodies" else "source_scene_path"
            scene = entry[source_key]
            if scene in scenes[group]:
                raise ValueError(f"duplicate source scene in {group}: {scene}")
            scenes[group].add(scene)
            project_path(root, scene)
            if group == "bodies":
                project_path(root, entry["registration_source_path"])
                if not entry["registration_mesh"]:
                    raise ValueError("registration_mesh is required")
                if type(entry.get("preserve_foot_shape", False)) is not bool:
                    raise ValueError("preserve_foot_shape must be a boolean")

            else:
                _number(entry["clearance_ratio"], 0, 0.08, "clearance_ratio")
                for path in entry.get("item_resource_paths", []):
                    project_path(root, path)
    enabled = {entry["id"] for entry in data["bodies"] if entry.get("enabled", True)}
    if data["cage_source_body_id"] not in enabled:
        raise ValueError("cage source body must be enabled")
    for item in data["garments"]:
        if item.get("enabled", True) and item["reference_body_id"] not in enabled:
            raise ValueError(f"missing or disabled reference body for {item['id']}")
    return data


def load(path, root):
    return validate(json.loads(Path(path).read_text()), root)
