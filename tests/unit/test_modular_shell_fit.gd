extends GutTest

const SHELL := preload("res://features/world/projection/buildings/shells/modular/medium_wood_hall.tscn")

func test_rear_entrance_is_replaced_by_matching_wall_without_door_fittings() -> void:
	var shell := SHELL.instantiate()
	autofree(shell)
	var pieces := shell.get_node("Pieces")
	var wall: Node3D = pieces.get_node("GroundBackEWall")
	var neighbor: Node3D = pieces.get_node("GroundBackD")
	assert_eq(wall.scene_file_path, neighbor.scene_file_path, "Use the existing solid plaster module")
	for removed: String in ["GroundBackEDoor", "DoorWoodFlat2", "DoorFrameFlatBrick22", "BackSteps"]:
		assert_null(pieces.get_node_or_null(removed), "No rear door, frame, or abandoned steps: " + removed)
	for retained: String in ["GroundFrontCWall", "GroundFrontCDoor", "DoorWoodFlat", "DoorFrameFlatBrick", "FrontSteps", "BackRoomStairs", "StairInteriorSimple"]:
		assert_not_null(pieces.get_node_or_null(retained), "Keep the front entrance and interior stairs: " + retained)
	for collision in [false, true]:
		var wall_box := _bounds(wall, Transform3D.IDENTITY, collision)
		var neighbor_box := _bounds(neighbor, Transform3D.IDENTITY, collision)
		assert_almost_eq(wall_box.position.x, neighbor_box.end.x, 0.001, "Rear wall modules meet without a gap")
		assert_almost_eq(wall_box.size, neighbor_box.size, Vector3.ONE * 0.001, "Matching mesh and collision dimensions")
		assert_almost_eq(wall_box.position.z, neighbor_box.position.z, 0.001, "Flush rear facade")

func test_replacement_rear_wall_blocks_a_person_from_both_sides() -> void:
	var shell := SHELL.instantiate()
	var wall: Node3D = shell.get_node("Pieces/GroundBackEWall")
	wall.get_parent().remove_child(wall)
	shell.free()
	add_child_autofree(wall)
	var body := CharacterBody3D.new()
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.25
	capsule.height = 1.8
	collision.shape = capsule
	body.add_child(collision)
	add_child_autofree(body)
	for side: float in [-1.0, 1.0]:
		body.position = wall.position + Vector3(0, 1, side)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var hit := body.move_and_collide(Vector3(0, 0, -side * 2.0))
		assert_not_null(hit, "A person cannot cross the former rear opening from either side")
		if hit != null:
			assert_true(wall.is_ancestor_of(hit.get_collider()), "The replacement wall itself stops the body")

func test_divider_wall_meshes_and_collision_fit_between_floor_slabs() -> void:
	_assert_dividers_fit("WallPlasterStraight", 5)

func test_divider_doorway_posts_do_not_protrude_through_upper_floor() -> void:
	_assert_dividers_fit("CornerInteriorSmall", 2)

func _assert_dividers_fit(prefix: String, expected_count: int) -> void:
	# This shell's storeys are 3 m apart; the source plaster walls are taller.
	# Check actual imported geometry, not nominal metadata or snap positions.
	var shell := SHELL.instantiate()
	var pieces := shell.get_node("Pieces")
	var lower := _bounds(pieces.get_node("Floor22"), Transform3D.IDENTITY, false)
	var upper := _bounds(pieces.get_node("Upper22"), Transform3D.IDENTITY, false)
	var count := 0
	for piece in pieces.get_children():
		if not str(piece.name).begins_with(prefix):
			continue
		count += 1
		for collision in [false, true]:
			var box := _bounds(piece, Transform3D.IDENTITY, collision)
			var label := str(piece.name) + (" collision" if collision else " mesh")
			assert_gt(box.size.y, 0.0, label + " exists")
			assert_gte(box.position.y, lower.position.y - 0.001, label + " stays above floor underside")
			assert_lte(box.position.y, lower.end.y + 0.001, label + " meets ground floor")
			# The imported solid collider excludes the decorative top trim.
			# The visible wall must meet the ceiling; neither may pierce its floor.
			if not collision:
				assert_gte(box.end.y, upper.position.y - 0.001, label + " meets ceiling")
			assert_lte(box.end.y, upper.end.y - 0.001, label + " stays below upper walking surface")
	assert_eq(count, expected_count)
	shell.free()

func _bounds(node: Node, parent_transform: Transform3D, collision: bool) -> AABB:
	var transform := parent_transform
	if node is Node3D:
		transform *= (node as Node3D).transform
	var box := AABB()
	if collision and node is CollisionShape3D and node.shape != null:
		box = transform * node.shape.get_debug_mesh().get_aabb()
	elif not collision and node is MeshInstance3D and node.mesh != null:
		box = transform * node.get_aabb()
	for child in node.get_children():
		var child_box := _bounds(child, transform, collision)
		if child_box.size != Vector3.ZERO:
			box = child_box if box.size == Vector3.ZERO else box.merge(child_box)
	return box
