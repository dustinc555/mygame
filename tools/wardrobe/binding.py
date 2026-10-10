"""Bind imported surface vertices, without reordering or changing source geometry."""
import numpy as np
from scipy.spatial import cKDTree


def points_array(value, label):
    array = np.asarray(value, dtype=np.float64)
    if array.ndim != 2 or array.shape[1] != 3 or not len(array) or not np.isfinite(array).all():
        raise ValueError(f"{label}: expected nonempty finite Nx3 coordinates")
    return array


def matrix(value, label="transform"):
    result = np.asarray(value, dtype=np.float64)
    if result.shape != (4, 4) or not np.isfinite(result).all():
        raise ValueError(f"{label}: expected finite 4x4 transform")
    if not np.allclose(result[3], [0, 0, 0, 1], atol=1e-8, rtol=0) or abs(np.linalg.det(result[:3, :3])) < 1e-12:
        raise ValueError(f"{label}: singular or non-affine transform")
    return result


def mesh_to_reference(binds, reference_rests, used_binds, tolerance=1e-5):
    """Validate every positively weighted bind; never hide missing anatomy."""
    result = None
    for index in sorted(used_binds):
        if index < 0 or index >= len(binds):
            raise ValueError(f"invalid used bind index {index}")
        bind = binds[index]
        name = bind["name"]
        if name not in reference_rests:
            raise ValueError(f"missing weighted joint {name}")
        transform = matrix(reference_rests[name], name) @ matrix(bind["pose"], name)
        if result is not None and not np.allclose(result, transform, atol=tolerance, rtol=0):
            raise ValueError(f"inconsistent mesh-to-reference transform at {name}: {np.max(np.abs(result-transform))}")
        result = transform
    if result is None:
        raise ValueError("surface has no positively weighted binds")
    return result


def binding_weights(vertices, cage, influences=12, squared_distance_epsilon=1e-6,
                    vertex_skin=None, cage_skin=None, skin_weight_penalty=0.0):
    """Interpolate displacement locally, keeping adjacent anatomy distinct.

    Named skin coordinates guide neighbor selection only. Garment animation
    weights, cut and retained surface offsets are never replaced by body weights.
    """
    vertices = points_array(vertices, "vertices")
    cage = points_array(cage, "cage")
    if type(influences) is not int or not 1 <= influences <= len(cage):
        raise ValueError("influences must be an integer in [1, cage size]")
    if not np.isfinite(squared_distance_epsilon) or squared_distance_epsilon <= 0:
        raise ValueError("squared-distance epsilon must be positive and finite")
    if not np.isfinite(skin_weight_penalty) or skin_weight_penalty < 0:
        raise ValueError("skin weight penalty must be finite and nonnegative")
    query, controls = vertices, cage
    if vertex_skin is not None or cage_skin is not None:
        vs, cs = np.asarray(vertex_skin, dtype=float), np.asarray(cage_skin, dtype=float)
        if (vs.ndim != 2 or cs.ndim != 2 or len(vs) != len(vertices) or len(cs) != len(cage)
                or not vs.shape[1] or vs.shape[1] != cs.shape[1]
                or not np.isfinite(vs).all() or not np.isfinite(cs).all()
                or np.any(vs < 0) or np.any(cs < 0)
                or not np.allclose(vs.sum(axis=1), 1, atol=0.001, rtol=0)
                or not np.allclose(cs.sum(axis=1), 1, atol=0.001, rtol=0)):
            raise ValueError("skin coordinates must be normalized matching vertex/cage arrays")
        scale = np.sqrt(skin_weight_penalty)
        query = np.concatenate([vertices, vs * scale], axis=1)
        controls = np.concatenate([cage, cs * scale], axis=1)
    elif skin_weight_penalty:
        raise ValueError("skin coordinates are required with a skin weight penalty")
    distances, indices = cKDTree(controls).query(query, k=influences)
    distances = distances.reshape(len(vertices), influences)
    indices = indices.reshape(len(vertices), influences)
    weights = 1.0 / np.maximum(distances * distances, squared_distance_epsilon) ** 1.5
    weights /= weights.sum(axis=1, keepdims=True)
    return indices.astype(np.int32), weights.astype(np.float32)


def bind_scene(native, reference_rests, cage, clearance, settings, cage_skin=None, cage_bone_names=None):
    """One record for every imported surface, retaining its exact vertex order."""
    if not np.isfinite(clearance) or clearance < 0:
        raise ValueError("clearance must be finite and nonnegative")
    output, signatures, used_names = [], [], set()
    for mesh in native["meshes"]:
        if not mesh["skin"]:
            raise ValueError(f"unskinned garment mesh {mesh['mesh_path']}; separate held props from clothing")
        for surface in mesh["surfaces"]:
            vertices = points_array(surface["vertices"], "imported vertices")
            normals = points_array(surface["normals"], "imported normals")
            if normals.shape != vertices.shape:
                raise ValueError("source normal/vertex counts differ")
            indices = np.asarray(surface["indices"], dtype=np.int64)
            if surface["primitive"] != 3 or len(indices) % 3 or (len(indices) and (indices.min() < 0 or indices.max() >= len(vertices))):
                raise ValueError("source surface must contain valid triangles")
            weights = np.asarray(surface["weights"], dtype=np.float64)
            bones = np.asarray(surface["bones"], dtype=np.int64)
            if len(weights) not in (len(vertices)*4, len(vertices)*8) or len(bones) != len(weights):
                raise ValueError("source skin influence arrays have invalid lengths")
            if not np.isfinite(weights).all() or np.any(weights < 0) or not np.allclose(weights.reshape(len(vertices), -1).sum(axis=1), 1, atol=0.001, rtol=0):
                raise ValueError("invalid source skin weights")
            used = set(int(value) for value in bones[weights > 0])
            transform = mesh_to_reference(mesh["skin"], reference_rests, used, settings["bind_transform_tolerance"])
            # Quantize precisely as Godot's native Transform3D/Vector3 storage.
            transform = transform.astype(np.float32).astype(np.float64)
            points = (vertices + normals * clearance) @ transform[:3, :3].T + transform[:3, 3]
            vertex_skin = None
            if cage_skin is not None:
                if cage_bone_names is None or len(set(cage_bone_names)) != len(cage_bone_names):
                    raise ValueError("cage skin requires unique named bone coordinates")
                columns = {name: i for i, name in enumerate(cage_bone_names)}
                vertex_skin = np.zeros((len(vertices), len(columns)))
                per_vertex_bones = bones.reshape(len(vertices), -1)
                per_vertex_weights = weights.reshape(len(vertices), -1)
                for index in used:
                    name = mesh["skin"][index]["name"]
                    if name not in columns:
                        raise ValueError(f"cage skin is missing weighted joint {name}")
                    vertex_skin[:, columns[name]] += np.sum(
                        per_vertex_weights * (per_vertex_bones == index), axis=1)
            cage_ids, cage_weights = binding_weights(points, cage, settings["influences"], settings["squared_distance_epsilon"],
                vertex_skin, cage_skin, settings.get("skin_weight_penalty", 0.0))
            output.append({"mesh_path": mesh["mesh_path"], "surface_index": surface["surface_index"],
                           "vertex_count": len(vertices), "mesh_to_reference": transform.tolist(),
                           "influences": settings["influences"], "cage_indices": cage_ids.ravel().tolist(),
                           "cage_weights": cage_weights.ravel().tolist()})
            signatures.append({"mesh_path": mesh["mesh_path"], "surface_index": surface["surface_index"],
                               "vertex_count": len(vertices), "arrays_sha256": surface["arrays_sha256"]})
            used_names.update(mesh["skin"][i]["name"] for i in used)
    if not output:
        raise ValueError("garment has no imported surfaces")
    return output, {"imported_surfaces": signatures, "used_joint_names": sorted(used_names),
                    "vertices": sum(surface["vertex_count"] for surface in output)}
