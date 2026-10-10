extends GutTest

const SHELLS := "res://features/world/projection/buildings/shells/modular/"
const MODULES := "res://features/world/projection/buildings/pieces/plaster/"


func test_tower_partitions_are_new_closed_flat_modules_without_timber() -> void:
	var shell := (load(SHELLS + "medium_brick_round_tower.tscn") as PackedScene).instantiate()
	autofree(shell)
	var count := 0
	for piece in shell.get_node("Pieces").get_children():
		if not str(piece.name).begins_with("WallPlasterStraight"):
			continue
		count += 1
		assert_true(piece.scene_file_path.begins_with(MODULES), "Divider must use an additional project-owned module")
		for mesh_node: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
			assert_eq(mesh_node.mesh.get_surface_count(), 1, "No inherited timber frame or braces")
			for surface in mesh_node.mesh.get_surface_count():
				assert_true(mesh_node.get_active_material(surface).resource_path.begins_with("res://assets/buildings/earthen/materials/"))
	assert_eq(count, 4)


func test_jail_divider_opening_has_no_detached_timber_posts() -> void:
	var shell := (load(SHELLS + "medium_brick_round_tower.tscn") as PackedScene).instantiate()
	autofree(shell)
	var pieces := shell.get_node("Pieces")
	for post_name: String in ["CornerInteriorBig", "CornerInteriorBig2"]:
		assert_null(pieces.get_node_or_null(post_name), "Remove the redundant post and its collision, not just its rendering")
	assert_not_null(pieces.get_node_or_null("GroundFrontDoorFrame"), "The exterior stone doorway remains")
	assert_not_null(pieces.get_node_or_null("GroundFrontDoorLeaf"), "The exterior door remains")
	assert_not_null(pieces.get_node_or_null("WallPlasterStraight2"), "Keep the new right plaster reveal")
	assert_not_null(pieces.get_node_or_null("WallPlasterStraight222"), "Keep the new left plaster reveal")


func test_original_fittings_materials_are_not_repainted() -> void:
	var shell := (load(SHELLS + "small_wood_cottage.tscn") as PackedScene).instantiate()
	autofree(shell)
	var inspected := 0
	for piece in shell.get_node("Pieces").get_children():
		if piece.get("category") not in ["window", "door", "door_frame", "roof", "stairs", "prop"]:
			continue
		var original := (load(piece.scene_file_path) as PackedScene).instantiate()
		autofree(original)
		for mesh_node: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
			var counterpart := original.get_node_or_null(piece.get_path_to(mesh_node)) as MeshInstance3D
			assert_not_null(counterpart)
			if counterpart == null:
				continue
			inspected += 1
			assert_eq(mesh_node.mesh.get_surface_count(), counterpart.mesh.get_surface_count())
			for surface in mini(mesh_node.mesh.get_surface_count(), counterpart.mesh.get_surface_count()):
				_assert_same_material(mesh_node.get_active_material(surface), counterpart.get_active_material(surface), str(piece.name))
	assert_gt(inspected, 10)


func test_fresh_wall_and_floor_maps_have_real_4k_surface_detail() -> void:
	for file: String in ["lime_plaster.tres", "clay_plaster.tres", "terracotta.tres"]:
		var path := "res://assets/buildings/earthen/materials/" + file
		assert_true(ResourceLoader.exists(path), path)
		if not ResourceLoader.exists(path):
			continue
		var material := load(path) as Material
		var maps: Array[Texture2D] = []
		if material is ShaderMaterial:
			assert_gt(float(material.get_shader_parameter("normal_strength")), 0.0)
			for key: String in ["albedo_texture", "normal_texture", "roughness_texture"]:
				maps.append(material.get_shader_parameter(key))
		else:
			assert_true(material is StandardMaterial3D)
			assert_true(material.normal_enabled)
			maps.assign([material.albedo_texture, material.normal_texture, material.roughness_texture])
		for texture: Texture2D in maps:
			assert_not_null(texture)
			if texture != null:
				assert_gte(texture.get_width(), 4096)
				assert_gte(texture.get_height(), 4096)


func _assert_same_material(actual: Material, original: Material, label: String) -> void:
	# ResourceSaver embeds imported submaterials when saving a fitted mesh.
	# Different resource identity is allowed; every persisted material value is not.
	assert_eq(actual.get_class(), original.get_class(), label)
	for property in original.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_STORAGE == 0:
			continue
		assert_eq(actual.get(property.name), original.get(property.name), label + ": " + str(property.name))


func test_door_and_window_openings_are_clear_in_mesh_and_collision() -> void:
	var cases := {
		"wall_door_flat": Vector2(0, 1),
		"wall_door_round": Vector2(0, 2.3),
		"wall_window_wide_flat": Vector2(0, 1.7),
		"wall_window_wide_round": Vector2(0, 2.5),
		"wall_window_thin_round": Vector2(0, 2.4),
	}
	for id: String in cases:
		var piece := (load(MODULES + id + ".tscn") as PackedScene).instantiate()
		autofree(piece)
		var mesh: Mesh = piece.get_node("Model").mesh
		var shape: ConcavePolygonShape3D = piece.get_node("Model/Body/Shape").shape
		for faces: PackedVector3Array in [mesh.get_faces(), shape.get_faces()]:
			var opening: Vector2 = cases[id]
			assert_false(_ray_hits(faces, Vector3(opening.x, opening.y, 1)), id + " opening is actually empty")
			assert_true(_ray_hits(faces, Vector3(0.95, 1.5, 1)), id + " jamb remains solid")
			assert_true(_ray_hits(faces, Vector3(0, 3, 1)), id + " lintel remains solid")


func test_partition_run_has_no_overlap_or_gap() -> void:
	var shell := (load(SHELLS + "medium_brick_round_tower.tscn") as PackedScene).instantiate()
	autofree(shell)
	var pieces := shell.get_node("Pieces")
	var inner: Node3D = pieces.get_node("WallPlasterStraight222")
	var outer: Node3D = pieces.get_node("WallPlasterStraight2222")
	var a: AABB = inner.transform * inner.get_node("Model").mesh.get_aabb()
	var b: AABB = outer.transform * outer.get_node("Model").mesh.get_aabb()
	assert_almost_eq(b.end.x, a.position.x, 0.001, "New fitted end touches instead of overlapping by 40 cm")
	assert_almost_eq(a.position.z, b.position.z, 0.001)
	assert_almost_eq(a.end.z, b.end.z, 0.001)


func _ray_hits(faces: PackedVector3Array, origin: Vector3) -> bool:
	for i in range(0, faces.size(), 3):
		if Geometry3D.ray_intersects_triangle(origin, Vector3.FORWARD, faces[i], faces[i + 1], faces[i + 2]) != null:
			return true
	return false


func test_new_door_wall_allows_a_body_through_but_blocks_the_solid_jamb() -> void:
	var wall := (load(MODULES + "wall_door_flat.tscn") as PackedScene).instantiate()
	add_child_autofree(wall)
	var body := CharacterBody3D.new()
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.25
	capsule.height = 1.8
	collision.shape = capsule
	body.add_child(collision)
	body.position = Vector3(0, 0.91, 1)
	add_child_autofree(body)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hit := body.move_and_collide(Vector3(0, 0, -2))
	assert_null(hit, "A person-sized body crosses the real doorway collider")
	assert_lt(body.position.z, -0.9)
	body.position = Vector3(0.95, 0.91, 1)
	await get_tree().physics_frame
	hit = body.move_and_collide(Vector3(0, 0, -2))
	assert_not_null(hit, "The same body cannot cross the adjacent solid wall")


func test_editor_catalog_loads_both_real_material_variants() -> void:
	var catalog := load("res://features/world/resources/building_pieces/plaster/catalog.tres") as ModularBuildingPieceCatalog
	var identifiers := {}
	for definition in catalog.pieces:
		assert_false(identifiers.has(definition.piece_id))
		identifiers[definition.piece_id] = true
		var piece: Node = definition.scene.instantiate()
		autofree(piece)
		assert_eq(piece.piece_id, definition.piece_id)
		assert_gt(piece.get_snap_markers().size(), 0)
		if definition.piece_id.begins_with("clay_"):
			var model := piece.get_node("Model") as MeshInstance3D
			assert_eq(model.get_active_material(0), load("res://assets/buildings/earthen/materials/clay_plaster.tres"))
	assert_true(identifiers.has("plaster_wall_straight"))
	assert_true(identifiers.has("clay_wall_straight"))


func test_l_hall_upper_floor_does_not_protrude_through_rear_wall() -> void:
	var shell := (load(SHELLS + "medium_wood_l_hall.tscn") as PackedScene).instantiate()
	autofree(shell)
	var inspected := 0
	var rear_edge := INF
	for piece: Node3D in shell.get_node("Pieces").get_children():
		if not piece.scene_file_path.begins_with(MODULES) or piece.get("category") != "floor":
			continue
		if not is_equal_approx(piece.position.y, 3.0):
			continue
		inspected += 1
		var model := piece.get_node("Model") as MeshInstance3D
		for point: Vector3 in model.mesh.get_faces():
			rear_edge = minf(rear_edge, (piece.transform * model.transform * point).z)
	assert_gt(inspected, 20, "Exercise the raised floor, not only the ground-floor perimeter")
	assert_gte(rear_edge, -5.001, "The floor at y=3 must remain inside the rear facade even though the upper walls start at y=3.122689")


func test_lime_distance_detail_keeps_original_close_surface_maps() -> void:
	var material := load("res://assets/buildings/earthen/materials/lime_plaster.tres") as ShaderMaterial
	assert_not_null(material)
	if material == null:
		return
	for key: String in ["albedo", "normal", "roughness", "ao"]:
		var original := load("res://assets/buildings/earthen/textures/lime_" + key + ".png") as Texture2D
		assert_eq(material.get_shader_parameter(key + "_texture"), original, "Keep the accepted photographed fine maps")
	assert_eq(float(material.get_shader_parameter("grain_repeat_meters")), 2.0, "No enlarged close grain")
	assert_eq(float(material.get_shader_parameter("normal_strength")), 0.7, "Keep accepted relief strength")
	var start := float(material.get_shader_parameter("detail_start_distance"))
	var full := float(material.get_shader_parameter("detail_full_distance"))
	assert_gte(start, 3.0, "Close inspection remains the original surface")
	assert_gt(full, start, "Blend smoothly instead of switching a material abruptly")
	assert_gt(float(material.get_shader_parameter("distance_detail_strength")), 0.0)
	var detail := material.get_shader_parameter("variation_texture") as Texture2D
	assert_not_null(detail)
	if detail != null:
		assert_gte(detail.get_width(), 2048)
		assert_gte(detail.get_height(), 2048)
