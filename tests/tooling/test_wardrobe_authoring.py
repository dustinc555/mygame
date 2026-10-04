"""Focused, CPU-only tests for reproducible wardrobe authoring."""
from pathlib import Path
import importlib.util
import unittest
import tempfile
import json
import sys
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "wardrobe"))


def module(name):
    path = ROOT / "tools" / "wardrobe" / (name + ".py")
    if not path.exists():
        raise AssertionError(f"wardrobe authoring module is missing: {name}")
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class BindingMathTests(unittest.TestCase):
    def test_binding_keeps_close_fingers_on_their_own_anatomy(self):
        math = module("binding")
        cage = np.array([[0.001, 0, 0], [0.002, 0, 0], [0.004, 0, 0], [0.005, 0, 0]])
        skin = np.array([[0., 1], [0., 1], [1., 0], [1., 0]])
        ids, weights = math.binding_weights([[0., 0, 0]], cage, 2, 1e-6,
            vertex_skin=[[1., 0]], cage_skin=skin, skin_weight_penalty=0.004)
        np.testing.assert_array_equal(ids, [[2, 3]])
        self.assertAlmostEqual(float(weights.sum()), 1.0, places=6)

    def test_anatomical_binding_rejects_mismatched_skin_coordinates(self):
        math = module("binding")
        with self.assertRaisesRegex(ValueError, "skin"):
            math.binding_weights([[0., 0, 0]], np.eye(3), 2, 1e-6,
                vertex_skin=[[1., 0]], cage_skin=[[1., 0]], skin_weight_penalty=0.004)

    def test_surface_binding_matches_anatomy_by_name_not_bind_order(self):
        from copy import deepcopy
        math = module("binding")
        native = {"meshes": [{"mesh_path": "Rig/Glove",
            "skin": [{"name": name, "pose": np.eye(4).tolist()} for name in ["thumb", "index"]],
            "surfaces": [{"surface_index": 0, "vertices": [[0., 0, 0]] * 3,
                "normals": [[0, 0, 1]] * 3, "bones": [0, 0, 0, 0] * 3,
                "weights": [1, 0, 0, 0] * 3, "indices": [0, 1, 2],
                "primitive": 3, "arrays_sha256": "fixture"}]}]}
        unchanged = deepcopy(native)
        cage = [[0.001, 0, 0], [0.002, 0, 0], [0.004, 0, 0], [0.005, 0, 0]]
        # Body coordinates are deliberately the reverse of the garment binds.
        skin = [[1., 0], [1., 0], [0., 1], [0., 1]]
        settings = {"influences": 2, "squared_distance_epsilon": 1e-6,
                    "bind_transform_tolerance": 1e-5, "skin_weight_penalty": 0.004}
        surfaces, _ = math.bind_scene(native, {"thumb": np.eye(4), "index": np.eye(4)},
            cage, 0., settings, cage_skin=skin, cage_bone_names=["index", "thumb"])
        self.assertEqual(surfaces[0]["cage_indices"], [2, 3] * 3)
        self.assertEqual(native, unchanged, "binding must not overwrite animation weights")
        with self.assertRaisesRegex(ValueError, "missing weighted joint thumb"):
            math.bind_scene(native, {"thumb": np.eye(4), "index": np.eye(4)},
                cage, 0., settings, cage_skin=skin, cage_bone_names=["index", "missing"])

    def test_inverse_distance_cubed_preserves_vertex_order(self):
        math = module("binding")
        self.assertIsNotNone(math, "wardrobe binding implementation is missing")
        cage = np.array([[0., 0, 0], [2, 0, 0], [0, 3, 0]])
        vertices = np.array([[1.5, 0, 0], [0.5, 0, 0]])
        indices, weights = math.binding_weights(vertices, cage, 2, 1e-6)
        np.testing.assert_array_equal(indices, [[1, 0], [0, 1]])
        np.testing.assert_allclose(weights, [[27/28, 1/28], [27/28, 1/28]])
        np.testing.assert_allclose(weights.sum(axis=1), 1)

    def test_surface_binding_uses_native_order_and_source_clearance(self):
        math = module("binding")
        self.assertTrue(hasattr(math, "bind_scene"), "native surface binding is missing")
        vertices = [[0.2, 0., 0.], [0.1, 0., 0.], [0., 0.1, 0.]]
        native = {"meshes": [{"mesh_path": "Rig/Cloth", "skin": [{"name": "hip", "pose": np.eye(4).tolist()}],
            "surfaces": [{"surface_index": 0, "vertices": vertices, "normals": [[0, 0, 1]] * 3,
                          "weights": [1, 0, 0, 0] * 3, "bones": [0, 0, 0, 0] * 3,
                          "indices": [0, 1, 2], "primitive": 3, "arrays_sha256": "test"}]}]}
        cage = np.array([[0., 0, 0], [0, 0, 1], [1, 0, 0]])
        surfaces, report = math.bind_scene(native, {"hip": np.eye(4)}, cage, 0.75,
            {"influences": 2, "squared_distance_epsilon": 1e-6, "bind_transform_tolerance": 1e-5})
        self.assertEqual(surfaces[0]["vertex_count"], 3)
        self.assertEqual(surfaces[0]["mesh_path"], "Rig/Cloth")
        ids, weights = math.binding_weights(np.array(vertices) + [0, 0, 0.75], cage, 2, 1e-6)
        np.testing.assert_array_equal(surfaces[0]["cage_indices"], ids.ravel())
        np.testing.assert_array_equal(surfaces[0]["cage_weights"], weights.ravel())
        self.assertEqual(report["used_joint_names"], ["hip"])
        native["meshes"][0]["surfaces"][0]["bones"][0] = 17
        with self.assertRaisesRegex(ValueError, "bind"):
            math.bind_scene(native, {"hip": np.eye(4)}, cage, 0, {"influences": 2, "squared_distance_epsilon": 1e-6, "bind_transform_tolerance": 1e-5})

    def test_invalid_binding_inputs_are_rejected(self):
        math = module("binding")
        cage = np.eye(3)
        for points, controls, count, epsilon in [
            ([[float("nan"), 0, 0]], cage, 2, 1e-6),
            ([[0, 0]], cage, 2, 1e-6),
            ([[0, 0, 0]], cage, 4, 1e-6),
            ([[0, 0, 0]], cage, 0, 1e-6),
            ([[0, 0, 0]], cage, 2, 0),
        ]:
            with self.subTest(points=points, count=count, epsilon=epsilon):
                with self.assertRaisesRegex(ValueError, ".+"):
                    math.binding_weights(points, controls, count, epsilon)

    def test_used_binds_define_one_normalization_transform(self):
        math = module("binding")
        self.assertTrue(hasattr(math, "mesh_to_reference"), "normalization is missing")
        rests = {"hip": np.eye(4), "knee": np.eye(4)}
        rests["knee"][1, 3] = -1
        normalization = np.diag([0.01, 0.01, 0.01, 1.0])
        binds = [{"name": n, "pose": (np.linalg.inv(r) @ normalization).tolist()} for n, r in rests.items()]
        binds.append({"name": "absent_unused", "pose": np.eye(4).tolist()})
        actual = math.mesh_to_reference(binds, rests, {0, 1}, 1e-5)
        np.testing.assert_allclose(actual, normalization)
        with self.assertRaisesRegex(ValueError, "absent_unused"):
            math.mesh_to_reference(binds, rests, {0, 1, 2}, 1e-5)
        binds[1]["pose"][0][3] = 0.2
        with self.assertRaisesRegex(ValueError, "inconsistent"):
            math.mesh_to_reference(binds, rests, {0, 1}, 1e-5)


class RegistrationTests(unittest.TestCase):
    def test_foot_registration_preserves_heel_when_animation_weights_differ(self):
        reg = module("registration")
        body = module("body_source")
        DEFAULT_REGISTRATION = module("manifest").DEFAULT_REGISTRATION
        source = body.mesh_data(ROOT / "assets/characters/humans/frontier_regular/male_regular.glb", "RegularMale")
        target = body.mesh_data(ROOT / "assets/characters/humans/frontier_regular/female_regular.glb", "Female_Regular")
        settings = dict(DEFAULT_REGISTRATION, preserve_foot_shape=True)
        points, _ = reg.register(source, target, settings)
        source_points, _, weights, names, _ = source
        # Female heels have calf influence, unlike the male reference. Matching
        # individual animation weights must not drag those heel controls forward.
        for side, sign in [("l", 1), ("r", -1)]:
            foot_weights = weights[:, [names.index("foot_" + side), names.index("ball_" + side)]].sum(axis=1)
            heel = (foot_weights > .8) & (source_points[:, 2] < -.11) & (source_points[:, 1] < .08)
            target_heel = target[0][(target[0][:, 0] * sign > 0) & (target[0][:, 1] < .08), 2].min()
            self.assertLessEqual(float(points[heel, 2].min()), float(target_heel + .015), side + " heel collapsed toward instep")

    def test_identity_registration_keeps_common_cage_exact(self):
        reg = module("registration")
        self.assertIsNotNone(reg, "body registration implementation is missing")
        x = np.array([[0., 0, 0], [1, 0, 0], [0, 1, 0], [0, 0, 1]])
        faces = np.array([[0, 1, 2], [0, 3, 1], [0, 2, 3], [1, 3, 2]])
        rests = {"hip": np.eye(4), "head": np.eye(4)}
        rests["head"][1, 3] = 1
        weights = np.tile([1., 0], (4, 1))
        source = (x, faces, weights, ["hip", "head"], rests)
        points, report = reg.register(source, source)
        np.testing.assert_array_equal(points, x)
        self.assertTrue(report["identity"])

    def test_coherent_foot_fit_retains_target_width_and_leaves_upper_body_alone(self):
        reg = module("registration")
        body = module("body_source")
        source = body.mesh_data(ROOT / "assets/characters/humans/frontier_regular/male_regular.glb", "RegularMale")
        target = body.mesh_data(ROOT / "assets/characters/humans/frontier_regular/female_regular.glb", "Female_Regular")
        original = source[0].copy()
        fitted, _ = reg.preserve_foot_shape(source, target, original, module("manifest").DEFAULT_REGISTRATION)
        for side in ("l", "r"):
            chain = [name + "_" + side for name in ("calf", "foot", "ball")]
            source_core = ((source[2][:, [source[3].index(n) for n in chain]].sum(axis=1) > .9)
                           & (source[0][:, 1] < source[4]["foot_" + side][1, 3] * 1.4))
            target_core = ((target[2][:, [target[3].index(n) for n in chain]].sum(axis=1) > .9)
                           & (target[0][:, 1] < target[4]["foot_" + side][1, 3] * 1.4))
            np.testing.assert_allclose([fitted[source_core, 0].min(), fitted[source_core, 0].max()],
                [target[0][target_core, 0].min(), target[0][target_core, 0].max()], atol=1e-6)
        np.testing.assert_array_equal(fitted[original[:, 1] > .21], original[original[:, 1] > .21])
        np.testing.assert_array_equal(source[0], original)

    def test_triangle_projection_handles_degenerate_and_outside(self):
        reg = module("registration")
        self.assertIsNotNone(reg, "body registration implementation is missing")
        triangles = np.array([[[0., 0, 0], [1, 0, 0], [0, 1, 0]], [[0, 0, 0]] * 3])
        points, distances = reg.closest_triangle(np.array([[2., 0, 0], [0, 1, 0]]), triangles)
        np.testing.assert_allclose(points, [[1, 0, 0], [0, 0, 0]])
        np.testing.assert_allclose(distances, [1, 1])


class ProvenanceTests(unittest.TestCase):
    def test_external_buffer_changes_invalidate_only_its_source(self):
        provenance = module("provenance")
        self.assertIsNotNone(provenance, "source fingerprinting is missing")
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "data.bin").write_bytes(b"abcd")
            (root / "body.gltf").write_text(json.dumps({"asset": {"version": "2.0"}, "buffers": [{"uri": "data.bin", "byteLength": 4}]}))
            (root / "other.gltf").write_text('{"asset":{"version":"2.0"}}')
            before = provenance.source_fingerprint(root, "res://body.gltf")
            other = provenance.source_fingerprint(root, "res://other.gltf")
            (root / "data.bin").write_bytes(b"dcba")
            self.assertNotEqual(before, provenance.source_fingerprint(root, "res://body.gltf"))
            self.assertEqual(other, provenance.source_fingerprint(root, "res://other.gltf"))

    def test_dependencies_cannot_escape_project_or_use_network(self):
        provenance = module("provenance")
        self.assertIsNotNone(provenance, "source fingerprinting is missing")
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for uri in ["../outside.bin", "https://example.com/mesh.bin"]:
                (root / "body.gltf").write_text(json.dumps({"buffers": [{"uri": uri}]}))
                with self.assertRaises(ValueError):
                    provenance.source_fingerprint(root, "res://body.gltf")


class BodySourceTests(unittest.TestCase):
    def test_canonical_source_welding_matches_visually_checked_cage(self):
        body = module("body_source")
        self.assertIsNotNone(body, "body source decoder is missing")
        source = body.mesh_data(ROOT / "assets/characters/humans/frontier_regular/male_regular.glb", "RegularMale")
        points, faces, weights, names, rests = source
        self.assertEqual(points.shape[1], 3)
        self.assertEqual(faces.shape[1], 3)
        self.assertLessEqual(int(faces.max()), len(points)-1)
        np.testing.assert_allclose(weights.sum(axis=1), 1, atol=1e-5)
        self.assertEqual(set(names), set(rests))
        # Stable welded-6-decimal lexicographic order, not imported vertex order.
        np.testing.assert_array_equal(np.lexsort(np.round(points, 6).T[::-1]), np.arange(len(points)))
        with self.assertRaisesRegex(ValueError, "mesh"):
            body.mesh_data(ROOT / "assets/characters/humans/frontier_regular/male_regular.glb", "Absent")


class ManifestTests(unittest.TestCase):
    def test_discovery_reads_actual_male_visual_not_filename_id(self):
        manifest = module("manifest")
        self.assertIsNotNone(manifest, "manifest discovery is missing")
        fixture = '''[gd_resource type="Resource" format=3]
[ext_resource type="PackedScene" path="res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Male_Peasant_Legs.gltf" id="arbitrary"]
[ext_resource type="Resource" path="res://features/actors/resources/character_body_archetypes/human_male.tres" id="body"]
[sub_resource type="Resource" id="visual"]
body_archetype = ExtResource("body")
visual_scene = ExtResource("arbitrary")
surface_offset_ratio = 0.016
[resource]
equipped_visuals = Array[Resource]([SubResource("visual")])
'''
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            items = root / "features/inventory/resources/items"
            items.mkdir(parents=True)
            (items / "pants.tres").write_text(fixture)
            result = manifest.discover(root)
            self.assertEqual(len(result), 1)
            self.assertEqual(result[0]["clearance_ratio"], 0.016)
            self.assertEqual(result[0]["reference_body_id"], "original_male_regular")
            self.assertEqual(result[0]["id"], "pants")


class AuthoringControlTests(unittest.TestCase):
    def test_manifest_rejects_typo_and_invalid_solver_controls(self):
        manifest = module("manifest")
        from copy import deepcopy
        valid = json.loads((ROOT / "tools/wardrobe/manifest.json").read_text())
        cases = []
        bad = deepcopy(valid); bad["binding"]["influences"] = 0; cases.append(bad)
        bad = deepcopy(valid); bad["binding"]["squared_distance_epsilon"] = float("nan"); cases.append(bad)
        bad = deepcopy(valid); bad["garments"][0]["clearance_ratios"] = 0.02; cases.append(bad)
        bad = deepcopy(valid); bad["bodies"].append(deepcopy(bad["bodies"][0])); cases.append(bad)
        bad = deepcopy(valid); bad["bodies"][0]["preserve_foot_shape"] = "yes"; cases.append(bad)
        bad = deepcopy(valid); bad["garments"][0]["reference_body_id"] = "absent"; cases.append(bad)
        bad = deepcopy(valid); bad["garments"][0]["source_scene_path"] = "res://../escape.glb"; cases.append(bad)
        for value in cases:
            with self.subTest(value=value.get("binding")):
                with self.assertRaises(ValueError):
                    manifest.validate(value, ROOT)

    def test_selection_builds_reference_dependencies_not_other_garments(self):
        author = module("author")
        data = json.loads((ROOT / "tools/wardrobe/manifest.json").read_text())
        bodies, garments = author.select_entries(data, [], ["peasant_trousers"])
        self.assertEqual({b["id"] for b in bodies}, {"male_regular", "original_male_regular"})
        self.assertEqual([g["id"] for g in garments], ["peasant_trousers"])
        with self.assertRaises(ValueError):
            author.select_entries(data, [], ["misspelled"])

    def test_artifact_tampering_forces_rebuild(self):
        provenance = module("provenance")
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            artifact = root / "profile.res"
            artifact.write_bytes(b"original")
            record = {"source_digest": "inputs", "artifact_sha256": provenance.file_digest(artifact)}
            self.assertTrue(provenance.artifact_is_current(root, "res://profile.res", "inputs", record))
            self.assertFalse(provenance.artifact_is_current(root, "res://profile.res", "changed", record))
            artifact.write_bytes(b"tampered")
            self.assertFalse(provenance.artifact_is_current(root, "res://profile.res", "inputs", record))

    def test_imported_scene_bytes_are_part_of_fingerprint(self):
        provenance = module("provenance")
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "model.gltf").write_text('{"asset":{"version":"2.0"}}')
            (root / "model.gltf.import").write_text('path="res://imported.scn"\nsource_file="res://model.gltf"\n')
            (root / "imported.scn").write_bytes(b"native order A")
            first = provenance.source_fingerprint(root, "res://model.gltf")
            (root / "imported.scn").write_bytes(b"native order B")
            self.assertNotEqual(first, provenance.source_fingerprint(root, "res://model.gltf"))

    def test_world_to_skeleton_consistency_is_checked_on_every_joint(self):
        source = module("body_source")
        raw = {"root": np.eye(4), "hand": np.eye(4)}
        imported = {"root": np.eye(4), "hand": np.eye(4)}
        raw["hand"][0, 3] = 1
        imported["hand"][0, 3] = 1
        np.testing.assert_array_equal(source.world_to_skeleton(raw, imported), np.eye(4))
        imported["hand"][0, 3] += 0.1
        with self.assertRaisesRegex(ValueError, "consistent"):
            source.world_to_skeleton(raw, imported)

    def test_zero_distance_weights_are_finite_and_normalized(self):
        math = module("binding")
        indices, weights = math.binding_weights([[0, 0, 0]], [[0, 0, 0], [0.01, 0, 0]], 2, 1e-6)
        self.assertTrue(np.isfinite(weights).all())
        self.assertEqual(indices[0, 0], 0)
        self.assertAlmostEqual(float(weights.sum()), 1.0, places=6)

    def test_negative_skin_weights_are_rejected(self):
        math = module("binding")
        native = {"meshes": [{"mesh_path": "Cloth", "skin": [{"name": "hip", "pose": np.eye(4).tolist()}], "surfaces": [{
            "surface_index": 0, "vertices": [[0, 0, 0]] * 3, "normals": [[0, 1, 0]] * 3,
            "primitive": 3, "indices": [0, 1, 2], "bones": [0] * 12,
            "weights": [-0.1, 1.1, 0, 0] * 3, "arrays_sha256": "test"}]}]}
        with self.assertRaisesRegex(ValueError, "skin weights"):
            math.bind_scene(native, {"hip": np.eye(4)}, [[0, 0, 0]], 0,
                            {"influences": 1, "squared_distance_epsilon": 1e-6, "bind_transform_tolerance": 1e-5})


if __name__ == "__main__":
    unittest.main()
