extends GutTest

const FIT_PATH := "res://features/actors/projection/appearance/clothing_fitter.gd"
const BODY_PATH := "res://features/actors/resources/wardrobe/wardrobe_body_profile.gd"
const BINDING_PATH := "res://features/inventory/resources/items/clothing_binding.gd"
const SURFACE_PATH := "res://features/inventory/resources/items/clothing_surface_binding.gd"
var fitter: GDScript

func before_each() -> void:
	fitter = load(FIT_PATH)
	if fitter != null: fitter.clear_cache()

func make_profile(points := PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])) -> Resource:
	var profile: Resource = load(BODY_PATH).new()
	profile.points = points
	profile.cage_id = "test_body"
	return profile

func make_fixture() -> Dictionary:
	var root := Node3D.new()
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	skeleton.add_bone("pelvis")
	skeleton.set_bone_rest(0, Transform3D.IDENTITY)
	root.add_child(skeleton)
	var mesh := MeshInstance3D.new()
	mesh.name = "Garment"
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0.1), Vector3(1, 0, 0.1), Vector3(0, 1, 0.1)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_TANGENT] = PackedFloat32Array([1,0,0,1, 1,0,0,1, 1,0,0,1])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.UP])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,2,1])
	arrays[Mesh.ARRAY_BONES] = PackedInt32Array([0,0,0,0, 0,0,0,0, 0,0,0,0])
	arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([1,0,0,0, 1,0,0,0, 1,0,0,0])
	mesh.mesh = ArrayMesh.new()
	mesh.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.mesh.surface_set_material(0, StandardMaterial3D.new())
	mesh.skin = Skin.new()
	mesh.skin.add_named_bind("pelvis", Transform3D.IDENTITY)
	root.add_child(mesh)
	mesh.skeleton = NodePath("../Skeleton3D")
	add_child_autofree(root)
	var source := make_profile()
	var binding: Resource = load(BINDING_PATH).new()
	binding.reference_profile = source
	var surface: Resource = load(SURFACE_PATH).new()
	surface.mesh_path = NodePath("Garment")
	surface.vertex_count = 3
	surface.influences = 1
	surface.cage_indices = PackedInt32Array([0,1,2])
	surface.cage_weights = PackedFloat32Array([1,1,1])
	binding.surfaces.append(surface)
	return {"root":root, "mesh":mesh, "skeleton":skeleton, "binding":binding, "profile":source, "surface":surface}

func fitted_mesh(result: Dictionary) -> MeshInstance3D:
	assert_eq(result.get("error", "missing"), "")
	if not result.has("visual"): return null
	add_child_autofree(result.visual)
	return result.visual.get_child(0)

func test_identity_preserves_authored_shape_attributes_and_source() -> void:
	var f := make_fixture()
	var original: Array = f.mesh.mesh.surface_get_arrays(0)
	var result: Dictionary = fitter.fit(f.root, f.binding, f.profile, f.skeleton)
	var mesh := fitted_mesh(result)
	if mesh == null: return
	var actual := mesh.mesh.surface_get_arrays(0)
	for slot in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_BONES,Mesh.ARRAY_WEIGHTS,Mesh.ARRAY_INDEX]:
		assert_eq(actual[slot], original[slot], "Unchanged body preserves authored surface array %d" % slot)
	assert_eq(mesh.mesh.surface_get_material(0), f.mesh.mesh.surface_get_material(0))
	assert_eq(f.mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], original[Mesh.ARRAY_VERTEX])

func test_body_change_preserves_cloth_ease_instead_of_projecting_to_skin() -> void:
	var f := make_fixture()
	var target := make_profile(PackedVector3Array([Vector3(0,0,0.5),Vector3(2,0,0.5),Vector3(0,2,0.5)]))
	var mesh := fitted_mesh(fitter.fit(f.root, f.binding, target, f.skeleton))
	if mesh == null: return
	var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_almost_eq(vertices[0], Vector3(0,0,0.6), Vector3.ONE * 0.00001)
	assert_almost_eq(vertices[1], Vector3(2,0,0.6), Vector3.ONE * 0.00001)
	assert_almost_eq(vertices[2], Vector3(0,2,0.6), Vector3.ONE * 0.00001)

func test_clearance_and_source_coordinates_applied_exactly_once() -> void:
	var f := make_fixture()
	f.surface.mesh_to_reference = Transform3D(Basis.IDENTITY, Vector3(0,0,0.25))
	f.binding.clearance_meters = 0.03
	var mesh := fitted_mesh(fitter.fit(f.root, f.binding, f.profile, f.skeleton))
	if mesh == null: return
	assert_almost_eq(mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX][0],Vector3(0,0,0.38),Vector3.ONE*0.00001)

func test_named_skin_remapping_uses_target_rest_not_source_bone_index() -> void:
	var f := make_fixture()
	var target := Skeleton3D.new()
	target.add_bone("unrelated")
	target.add_bone("pelvis")
	var rest := Transform3D(Basis(Vector3.UP, 0.4),Vector3(0,1,0))
	target.set_bone_rest(1, rest)
	add_child_autofree(target)
	var mesh := fitted_mesh(fitter.fit(f.root,f.binding,f.profile,target))
	if mesh == null: return
	assert_eq(mesh.skin.get_bind_name(0), &"pelvis")
	assert_true((rest * mesh.skin.get_bind_pose(0)).is_equal_approx(Transform3D.IDENTITY))
	assert_eq(target.get_bone_rest(1),rest,"Fitter does not modify actor skeleton")


func test_source_transform_rotates_tangent_and_normal_together() -> void:
	var f := make_fixture()
	var transform := Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(0.2, 0.3, 0.4))
	f.surface.mesh_to_reference = transform
	var mesh := fitted_mesh(fitter.fit(f.root, f.binding, f.profile, f.skeleton))
	if mesh == null: return
	var arrays := mesh.mesh.surface_get_arrays(0)
	var tangent := Vector3(arrays[Mesh.ARRAY_TANGENT][0], arrays[Mesh.ARRAY_TANGENT][1], arrays[Mesh.ARRAY_TANGENT][2])
	assert_almost_eq(arrays[Mesh.ARRAY_VERTEX][0], transform * Vector3(0, 0, 0.1), Vector3.ONE * 0.00001)
	assert_almost_eq(arrays[Mesh.ARRAY_NORMAL][0], Vector3.RIGHT, Vector3.ONE * 0.0001)
	assert_almost_eq(tangent, Vector3.FORWARD, Vector3.ONE * 0.0001)

func test_missing_weighted_joint_refuses_without_unfitted_fallback() -> void:
	var f := make_fixture()
	var skeleton := Skeleton3D.new()
	skeleton.add_bone("other")
	add_child_autofree(skeleton)
	var result: Dictionary = fitter.fit(f.root,f.binding,f.profile,skeleton)
	assert_string_contains(result.error,"pelvis")
	assert_false(result.has("visual"))

func test_malformed_and_stale_bindings_refuse_explicitly() -> void:
	var f := make_fixture()
	f.surface.cage_indices[1] = 999
	var result: Dictionary = fitter.fit(f.root,f.binding,f.profile,f.skeleton)
	assert_string_contains(result.error,"cage index")
	f.surface.cage_indices = PackedInt32Array([0,1,2])
	f.surface.vertex_count = 4
	result = fitter.fit(f.root,f.binding,f.profile,f.skeleton)
	assert_string_contains(result.error,"vertex count")

func test_incompatible_body_cage_is_not_silently_equipped() -> void:
	var f := make_fixture()
	var target := make_profile()
	target.cage_id = "robot"
	var result: Dictionary = fitter.fit(f.root,f.binding,target,f.skeleton)
	assert_string_contains(result.error,"cage")
	assert_false(result.has("visual"))

func test_cache_reuses_mesh_without_reusing_nodes_and_is_bounded() -> void:
	var f := make_fixture()
	var first := fitted_mesh(fitter.fit(f.root,f.binding,f.profile,f.skeleton))
	var second := fitted_mesh(fitter.fit(f.root,f.binding,f.profile,f.skeleton))
	if first == null or second == null: return
	assert_ne(first,second)
	assert_eq(first.mesh,second.mesh)
	assert_eq(fitter.cache_stats().hits,1)
	for i in fitter.CACHE_LIMIT + 2:
		var target := make_profile(PackedVector3Array([Vector3(0,0,i*.001),Vector3.RIGHT,Vector3.UP]))
		fitted_mesh(fitter.fit(f.root,f.binding,target,f.skeleton))
	assert_lte(fitter.cache_stats().entries,fitter.CACHE_LIMIT)


func test_cache_shares_geometry_but_not_source_instance_appearance() -> void:
	var f := make_fixture()
	var first := fitted_mesh(fitter.fit(f.root, f.binding, f.profile, f.skeleton))
	var tint := StandardMaterial3D.new()
	tint.albedo_color = Color.RED
	f.mesh.material_override = tint
	f.mesh.layers = 4
	f.mesh.visible = false
	var second := fitted_mesh(fitter.fit(f.root, f.binding, f.profile, f.skeleton))
	if first == null or second == null: return
	assert_eq(first.mesh, second.mesh)
	assert_null(first.material_override)
	assert_eq(second.material_override, tint)
	assert_eq(second.layers, 4)
	assert_false(second.visible)


func test_invalid_fitting_settings_refuse_before_building_a_mesh() -> void:
	var f := make_fixture()
	f.binding.clearance_meters = -0.1
	var result: Dictionary = fitter.fit(f.root, f.binding, f.profile, f.skeleton)
	assert_string_contains(result.error, "clearance")
	if result.has("visual"): result.visual.free()
	f.binding.clearance_meters = 0.0
	f.surface.mesh_to_reference = Transform3D(Basis.from_scale(Vector3(0, 1, 1)), Vector3.ZERO)
	result = fitter.fit(f.root, f.binding, f.profile, f.skeleton)
	assert_string_contains(result.error, "transform")
	if result.has("visual"): result.visual.free()


func test_source_mesh_edit_invalidates_cached_geometry() -> void:
	var f := make_fixture()
	var first := fitted_mesh(fitter.fit(f.root, f.binding, f.profile, f.skeleton))
	var arrays: Array = f.mesh.mesh.surface_get_arrays(0)
	arrays[Mesh.ARRAY_VERTEX][0] = Vector3(0, 0, 0.2)
	f.mesh.mesh.clear_surfaces()
	f.mesh.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var second := fitted_mesh(fitter.fit(f.root, f.binding, f.profile, f.skeleton))
	if first == null or second == null: return
	assert_ne(first.mesh, second.mesh)
	assert_almost_eq(second.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX][0], Vector3(0, 0, 0.2), Vector3.ONE * 0.00001)


func make_multi_influence_fixture(influences := 12) -> Dictionary:
	var f := make_fixture()
	f.surface.influences = influences
	var indices := PackedInt32Array()
	var weights := PackedFloat32Array()
	for vertex in f.surface.vertex_count:
		for influence in influences:
			indices.append(influence % f.profile.points.size())
			weights.append(1.0 / influences)
	f.surface.cage_indices = indices
	f.surface.cage_weights = weights
	return f


func test_supported_influence_counts_preserve_cold_cached_and_source_arrays() -> void:
	for influences in range(1, 33):
		var f := make_multi_influence_fixture(influences)
		var original: Array = f.mesh.mesh.surface_get_arrays(0)
		var target := make_profile(PackedVector3Array([Vector3(0, 0, 0.2), Vector3(1.2, 0, 0.1), Vector3(0, 1.3, 0.4)]))
		var result: Dictionary = fitter.fit(f.root, f.binding, target, f.skeleton)
		var cold := fitted_mesh(result)
		if cold == null: return
		assert_false(result.cache_hit)
		result = fitter.fit(f.root, f.binding, target, f.skeleton)
		var cached := fitted_mesh(result)
		if cached == null: return
		assert_true(result.cache_hit)
		assert_eq(cold.mesh, cached.mesh)
		var fitted := cold.mesh.surface_get_arrays(0)
		assert_ne(fitted[Mesh.ARRAY_VERTEX], original[Mesh.ARRAY_VERTEX])
		for channel in [Mesh.ARRAY_INDEX, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
			assert_eq(var_to_bytes(fitted[channel]), var_to_bytes(original[channel]), "Preserved channel %d with %d influences" % [channel, influences])
		assert_eq(var_to_bytes(f.mesh.mesh.surface_get_arrays(0)), var_to_bytes(original), "Source arrays remain untouched")


func test_cage_weight_nan_is_rejected_at_every_influence_position() -> void:
	var f := make_multi_influence_fixture()
	var arrays: Array = f.mesh.mesh.surface_get_arrays(0)
	var original: PackedFloat32Array = f.surface.cage_weights.duplicate()
	for index in original.size():
		f.surface.cage_weights = original.duplicate()
		f.surface.cage_weights[index] = NAN
		assert_eq(fitter._validate_surface(arrays, f.surface, f.profile.points.size()), "Invalid clothing cage weight", "NaN at influence %d cannot be hidden by range reductions" % index)


func test_invalid_cage_weight_ranges_are_rejected() -> void:
	var f := make_multi_influence_fixture()
	var arrays: Array = f.mesh.mesh.surface_get_arrays(0)
	var original: PackedFloat32Array = f.surface.cage_weights.duplicate()
	for weight in [-0.000001, -INF, INF]:
		for index in [0, original.size() / 2, original.size() - 1]:
			f.surface.cage_weights = original.duplicate()
			f.surface.cage_weights[index] = weight
			assert_eq(fitter._validate_surface(arrays, f.surface, f.profile.points.size()), "Invalid clothing cage weight")


func test_cage_index_range_includes_zero_and_excludes_cage_count() -> void:
	var f := make_multi_influence_fixture()
	var arrays: Array = f.mesh.mesh.surface_get_arrays(0)
	var original: PackedInt32Array = f.surface.cage_indices.duplicate()
	assert_eq(fitter._validate_surface(arrays, f.surface, f.profile.points.size()), "")
	for invalid in [-1, f.profile.points.size()]:
		for index in [0, original.size() / 2, original.size() - 1]:
			f.surface.cage_indices = original.duplicate()
			f.surface.cage_indices[index] = invalid
			assert_eq(fitter._validate_surface(arrays, f.surface, f.profile.points.size()), "Invalid clothing cage index")


func test_zero_cage_weights_and_normalization_tolerance_are_preserved() -> void:
	var f := make_multi_influence_fixture(4)
	var arrays: Array = f.mesh.mesh.surface_get_arrays(0)
	f.surface.cage_weights = PackedFloat32Array([0.0, -0.0, 0.5, 0.5, 0.0, 0.0, 0.5, 0.5, 0.0, 0.0, 0.5, 0.5])
	assert_eq(fitter._validate_surface(arrays, f.surface, f.profile.points.size()), "")
	f.surface.cage_weights[0] = 0.00009
	assert_eq(fitter._validate_surface(arrays, f.surface, f.profile.points.size()), "")
	f.surface.cage_weights[0] = 0.00011
	assert_eq(fitter._validate_surface(arrays, f.surface, f.profile.points.size()), "Clothing cage weights must sum to one")
	f.surface.cage_weights[0] = 0.0
	f.surface.cage_weights[2] = 0.49991
	assert_eq(fitter._validate_surface(arrays, f.surface, f.profile.points.size()), "")
	f.surface.cage_weights[2] = 0.49989
	assert_eq(fitter._validate_surface(arrays, f.surface, f.profile.points.size()), "Clothing cage weights must sum to one")


func test_invalid_binding_preserves_first_error_in_vertex_influence_order() -> void:
	var f := make_multi_influence_fixture()
	var arrays: Array = f.mesh.mesh.surface_get_arrays(0)
	f.surface.cage_weights[0] = -0.1
	f.surface.cage_indices[1] = -1
	assert_eq(fitter._validate_surface(arrays, f.surface, f.profile.points.size()), "Invalid clothing cage weight", "An earlier bad weight precedes a later bad index")
	f.surface.cage_indices[0] = -1
	assert_eq(fitter._validate_surface(arrays, f.surface, f.profile.points.size()), "Invalid clothing cage index", "An index precedes the weight at the same influence")
	arrays[Mesh.ARRAY_VERTEX][0] = Vector3(NAN, 0, 0)
	assert_eq(fitter._validate_surface(arrays, f.surface, f.profile.points.size()), "Invalid source garment vertex", "The vertex precedes its influence validation")


func test_earlier_vertex_normalization_precedes_later_invalid_influence() -> void:
	var f := make_multi_influence_fixture()
	var arrays: Array = f.mesh.mesh.surface_get_arrays(0)
	f.surface.cage_weights[0] = 0.5
	f.surface.cage_indices[f.surface.influences] = -1
	assert_eq(fitter._validate_surface(arrays, f.surface, f.profile.points.size()), "Clothing cage weights must sum to one")
	f.surface.cage_weights[0] = 1.0 / f.surface.influences
	arrays[Mesh.ARRAY_WEIGHTS][0] = 0.5
	assert_eq(fitter._validate_surface(arrays, f.surface, f.profile.points.size()), "Garment skin weights must sum to one")


func test_in_place_binding_edit_is_checked_after_cache_hit() -> void:
	var f := make_multi_influence_fixture()
	fitted_mesh(fitter.fit(f.root, f.binding, f.profile, f.skeleton))
	fitted_mesh(fitter.fit(f.root, f.binding, f.profile, f.skeleton))
	assert_eq(fitter.cache_stats().hits, 1)
	f.surface.cage_weights[5] = NAN
	var result: Dictionary = fitter.fit(f.root, f.binding, f.profile, f.skeleton)
	assert_string_contains(result.error, "Invalid clothing cage weight")
	assert_false(result.has("visual"))
	f.surface.cage_weights[5] = 1.0 / f.surface.influences
	f.surface.cage_indices[5] = f.profile.points.size()
	result = fitter.fit(f.root, f.binding, f.profile, f.skeleton)
	assert_string_contains(result.error, "Invalid clothing cage index")
	assert_false(result.has("visual"))
