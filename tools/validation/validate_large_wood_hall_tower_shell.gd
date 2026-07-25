extends SceneTree

const SHELL_PATH := "res://features/world/projection/buildings/shells/modular/large_wood_hall_tower.tscn"
const GRID_STEP := 2
const STAIR_ORIGIN := Vector3(5.225318, -0.024588373, -1.9967835)

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SHELL_PATH) as PackedScene
	if packed == null:
		_fail("Large wood hall tower shell must load")
		quit(1)
		return
	var shell := packed.instantiate() as Node3D
	shell.set("building_id", "validation.large_wood_hall_tower")
	get_root().add_child(shell)
	await process_frame
	if str(shell.get("building_type")) != "generic":
		_fail("Large wood hall tower shell must identify as building_type=generic")
	var pieces := shell.get_node_or_null("Pieces")
	if pieces == null:
		_fail("Large wood hall tower shell must have a Pieces root")
		_finish(shell)
		return
	_validate_tower_alignment(pieces)
	if OS.get_cmdline_user_args().has("--alignment-only"):
		_finish_alignment(shell)
		return

	_validate_grid(pieces, "Ground", _rect_cells(-8, 8, -4, 6), 0.0, "ground floor")
	var deck_cells := _rect_cells(-8, 8, -4, 6)
	deck_cells.erase(Vector2i(2, -2))
	deck_cells.erase(Vector2i(4, -2))
	deck_cells.erase(Vector2i(6, -2))
	_validate_grid(pieces, "Deck", deck_cells, 3.0, "hall roof deck")
	_validate_grid(pieces, "TowerRoof", _rect_cells(0, 8, -4, 4), 6.0, "tower roof")
	_validate_stairs(pieces)
	_validate_balconies(pieces)
	_validate_doors(shell)
	_validate_upstairs_door_visibility(shell, pieces)
	_validate_visibility_lookup_source()
	_finish(shell)


func _validate_visibility_lookup_source() -> void:
	var source := FileAccess.get_file_as_string("res://features/world/projection/building_visibility_controller.gd")
	var function_start := source.find("func _find_building_for_actor")
	var function_end := source.find("\n\nfunc ", function_start + 1)
	var function_source := source.substr(function_start, function_end - function_start)
	if function_source.contains("get_nodes_in_group"):
		_fail("Building visibility must not scan the scene-tree building group per frame")
	if not function_source.contains("is_visibility_candidate"):
		_fail("Building visibility must coarse-reject unrelated buildings before exact containment")


func _validate_tower_alignment(pieces: Node) -> void:
	var expected := {
		"TowerFrontFarWest": [Vector3(0, 3, 5), "front"],
		"TowerFrontFarWest2": [Vector3(2, 3, 5), "front"],
		"TowerFrontWestWindow": [Vector3(4, 3, 5), "front"],
		"TowerFrontDoor": [Vector3(6, 3, 5), "front"],
		"TowerFrontEastWindow": [Vector3(8, 3, 5), "front"],
		"TowerRearFarWest2": [Vector3(0, 3, -5), "rear"],
		"TowerRearFarWest": [Vector3(2, 3, -5), "rear"],
		"TowerRearWest": [Vector3(4, 3, -5), "rear"],
		"TowerRearMiddleWindow": [Vector3(6, 3, -5), "rear"],
		"TowerRearEast": [Vector3(8, 3, -5), "rear"],
		"TowerEastRear": [Vector3(9, 3, -4), "east"],
		"TowerEastMiddleWindow": [Vector3(9, 3, -2), "east"],
		"TowerEastFront": [Vector3(9, 3, 0), "east"],
		"TowerEastFront22": [Vector3(9, 3, 2), "east"],
		"TowerEastFront222": [Vector3(9, 3, 4), "east"],
		"TowerWestRear": [Vector3(-1, 3, -4), "west"],
		"TowerWestMiddleWindow": [Vector3(-1, 3, -2), "west"],
		"TowerWestFront": [Vector3(-1, 3, 0), "west"],
		"TowerWestFront2": [Vector3(-1, 3, 2), "west"],
		"TowerWestFront22": [Vector3(-1, 3, 4), "west"],
	}
	var found := 0
	for node_name in expected:
		var piece := pieces.get_node_or_null(str(node_name)) as Node3D
		if piece == null:
			_fail("Tower perimeter is missing %s" % node_name)
			continue
		found += 1
		var specification: Array = expected[node_name]
		if not piece.position.is_equal_approx(specification[0]):
			_fail("%s is at %s, expected %s" % [node_name, piece.position, specification[0]])
		var expected_basis := _tower_wall_basis(str(specification[1]))
		if not piece.basis.is_equal_approx(expected_basis):
			_fail("%s has basis %s, expected %s" % [node_name, piece.basis, expected_basis])
	var actual_wall_count := 0
	for child in pieces.get_children():
		if child is Node3D and str(child.name).begins_with("Tower") and str(child.get("piece_id")).begins_with("wall_woodbrick_"):
			actual_wall_count += 1
	if found != expected.size() or actual_wall_count != expected.size():
		_fail("Tower perimeter must contain exactly %d wall modules, found %d" % [expected.size(), actual_wall_count])
	var corners := {
		"TowerCornerFrontEast": Vector3(9, 3.0613, 5),
		"TowerCornerRearEast": Vector3(9, 3.0613, -5),
		"TowerCornerRearWest": Vector3(-1, 3.0613, -5),
		"TowerCornerFrontWest": Vector3(-1, 3.0613, 5),
	}
	for node_name in corners:
		var corner := pieces.get_node_or_null(str(node_name)) as Node3D
		if corner == null or not corner.position.is_equal_approx(corners[node_name]) or not corner.basis.is_equal_approx(Basis.IDENTITY):
			_fail("%s must use the normalized corner transform at %s" % [node_name, corners[node_name]])
	var frame := pieces.get_node_or_null("DoorFrameFlatBrick") as Node3D
	if frame == null or str(frame.get("piece_id")) != "door_frame_flat_brick" or not frame.position.is_equal_approx(Vector3(6.000902, 2.932063, 4.937176)):
		_fail("Upstairs flat door wall must use its matching aligned flat frame")
	var door := pieces.get_node_or_null("MainDoor2") as Node3D
	if door == null or not door.position.is_equal_approx(Vector3(5.4858, 3, 5)):
		_fail("Upstairs door leaf must align to the normalized flat wall socket")
	for child in pieces.get_children():
		if child is Node3D and str(child.name).begins_with("TowerRoof"):
			var roof := child as Node3D
			if not is_equal_approx(fmod(absf(roof.position.x), 2.0), 0.0) or not is_equal_approx(fmod(absf(roof.position.z), 2.0), 0.0):
				_fail("Tower roof tile %s is off the 2m grid at %s" % [child.name, roof.position])


func _tower_wall_basis(side: String) -> Basis:
	match side:
		"rear":
			return Basis(Vector3.UP, PI)
		"east":
			return Basis(Vector3.UP, PI * 0.5)
		"west":
			return Basis(Vector3.UP, -PI * 0.5)
	return Basis.IDENTITY


func _finish_alignment(shell: Node) -> void:
	shell.free()
	if _failed:
		quit(1)
		return
	print("LARGE_WOOD_HALL_TOWER_ALIGNMENT_OK walls=20 corners=4")
	quit()


func _validate_grid(pieces: Node, prefix: String, expected: Dictionary, expected_y: float, label: String) -> void:
	var actual := {}
	for child in pieces.get_children():
		if not str(child.name).begins_with(prefix) or not child is Node3D:
			continue
		if str(child.get("piece_id")) != "floor_wood_dark":
			continue
		var node := child as Node3D
		var cell := Vector2i(roundi(node.position.x), roundi(node.position.z))
		if actual.has(cell):
			_fail("%s has duplicate tile at %s" % [label, cell])
		actual[cell] = true
		if not is_equal_approx(node.position.y, expected_y):
			_fail("%s tile %s has y=%s, expected %s" % [label, child.name, node.position.y, expected_y])
	for cell in expected:
		if not actual.has(cell):
			_fail("%s has a gap at %s" % [label, cell])
	for cell in actual:
		if not expected.has(cell):
			_fail("%s has an off-grid tile at %s" % [label, cell])
	if actual.size() != expected.size():
		_fail("%s tile count is %d, expected %d" % [label, actual.size(), expected.size()])


func _validate_stairs(pieces: Node) -> void:
	var stairs := pieces.get_node_or_null("TowerStairs") as Node3D
	if stairs == null:
		_fail("Tower stair must exist")
		return
	if not stairs.position.is_equal_approx(STAIR_ORIGIN):
		_fail("Tower stair origin moved from measured placement: %s" % stairs.position)
	var model := stairs.get_node_or_null("Model/Stair_Interior_Simple") as MeshInstance3D
	if model == null:
		_fail("Tower stair model must exist")
		return
	var corners := _global_aabb_corners(model)
	for point in corners:
		if point.x < -1.0 - 0.01 or point.x > 9.0 + 0.01:
			_fail("Tower stair exceeds the x=-1..9 tower interior: %s" % point)
		if point.z < -3.0 - 0.01 or point.z > -1.0 + 0.01:
			_fail("Tower stair exceeds the z=-3..-1 shaft: %s" % point)
	var top_y := -INF
	for point in corners:
		top_y = maxf(top_y, point.y)
	if absf(top_y - 3.0) > 0.05:
		_fail("Tower stair top y=%s does not meet upper floor y=3" % top_y)


func _validate_balconies(pieces: Node) -> void:
	var floor_edges: Array[Marker3D] = []
	var wall_sides: Array[Marker3D] = []
	var rail_ends: Array[Marker3D] = []
	var balconies: Array[Node3D] = []
	for child in pieces.get_children():
		if not child is Node3D:
			continue
		var piece := child as Node3D
		var piece_id := str(piece.get("piece_id"))
		if piece_id == "floor_wood_dark":
			floor_edges.append_array(_markers_of_type(piece, "floor_edge"))
		elif piece_id == "balcony_simple_straight" or piece_id == "balcony_cross_corner":
			balconies.append(piece)
			rail_ends.append_array(_markers_of_type(piece, "balcony_rail_end"))
		wall_sides.append_array(_markers_of_type(piece, "wall_side"))
	if balconies.size() != 22:
		_fail("Expected 22 balcony pieces, found %d" % balconies.size())
	for balcony in balconies:
		var supports := _markers_of_type(balcony, "balcony_rail")
		var expected_supports := 2 if str(balcony.get("piece_id")) == "balcony_cross_corner" else 1
		if supports.size() != expected_supports:
			_fail("%s has %d support markers, expected %d" % [balcony.name, supports.size(), expected_supports])
		for support in supports:
			var nearest: Marker3D = null
			var nearest_distance := INF
			for edge in floor_edges:
				var distance := support.global_position.distance_to(edge.global_position)
				if distance < nearest_distance:
					nearest_distance = distance
					nearest = edge
			if nearest == null or nearest_distance > 0.01:
				_fail("%s support %s is %.3fm from the nearest floor edge" % [balcony.name, support.name, nearest_distance])
				continue
			var alignment := absf(support.global_basis.z.normalized().dot(nearest.global_basis.z.normalized()))
			if alignment < 0.99:
				_fail("%s support %s is not aligned to its floor edge" % [balcony.name, support.name])
	for rail_end in rail_ends:
		var connected := false
		for other_end in rail_ends:
			if other_end != rail_end and rail_end.global_position.distance_to(other_end.global_position) <= 0.01:
				connected = true
				break
		if not connected:
			for wall_side in wall_sides:
				var rail_xz := Vector2(rail_end.global_position.x, rail_end.global_position.z)
				var wall_xz := Vector2(wall_side.global_position.x, wall_side.global_position.z)
				# Woodbrick wall origins carry a 0.110794m model offset from the grid line.
				if rail_xz.distance_to(wall_xz) <= 0.12:
					connected = true
					break
		if not connected:
			_fail("Balcony rail end %s is not connected to another rail or terminating wall" % rail_end.get_path())


func _markers_of_type(piece: Node, connector_type: String) -> Array[Marker3D]:
	var markers: Array[Marker3D] = []
	var root := piece.get_node_or_null("SnapPoints")
	if root == null:
		return markers
	for child in root.get_children():
		if child is Marker3D and str(child.get("connector_type")) == connector_type:
			markers.append(child as Marker3D)
	return markers


func _validate_doors(shell: Node) -> void:
	var count := 0
	for door in get_nodes_in_group("world_door"):
		if shell.is_ancestor_of(door):
			count += 1
	if count != 2:
		_fail("Large wood hall tower shell must contain exactly two exterior doors, found %d" % count)


func _validate_upstairs_door_visibility(shell: Node3D, pieces: Node) -> void:
	var door := pieces.get_node_or_null("MainDoor2") as Node3D
	if door == null:
		_fail("Large wood hall tower must have an upstairs door leaf")
		return
	var modular_pieces: Array = shell.call("get_modular_pieces")
	if not modular_pieces.has(door):
		_fail("WorldDoor subclasses must participate in modular-piece visibility")
	var panel := door.get_node_or_null("HingePivot/PanelClickTarget")
	if shell.call("get_modular_piece_for_node", panel) != door:
		_fail("WorldDoor descendants must resolve to their modular piece")
	var camera_position := shell.to_global(Vector3(6.0, 9.0, 12.0))
	var ground_floor_focus := shell.to_global(Vector3(0.0, 0.2, 0.0))
	shell.call("_refresh_modular_piece_visibility", true, camera_position, -1, ground_floor_focus)
	if not bool(door.get_meta("world_building_hidden_by_camera", false)):
		_fail("Upstairs door leaf must hide while the focused actor is on the ground floor")
	shell.call("_refresh_modular_piece_visibility", false, camera_position, -1, null)


func _rect_cells(min_x: int, max_x: int, min_z: int, max_z: int) -> Dictionary:
	var cells := {}
	for x in range(min_x, max_x + 1, GRID_STEP):
		for z in range(min_z, max_z + 1, GRID_STEP):
			cells[Vector2i(x, z)] = true
	return cells


func _global_aabb_corners(mesh: MeshInstance3D) -> Array[Vector3]:
	var aabb := mesh.get_aabb()
	var corners: Array[Vector3] = []
	for x in [aabb.position.x, aabb.end.x]:
		for y in [aabb.position.y, aabb.end.y]:
			for z in [aabb.position.z, aabb.end.z]:
				corners.append(mesh.global_transform * Vector3(x, y, z))
	return corners


func _finish(shell: Node) -> void:
	shell.free()
	if _failed:
		quit(1)
		return
	print("LARGE_WOOD_HALL_TOWER_SHELL_OK ground=54 deck=51 tower_roof=25 balconies=22 doors=2")
	quit()


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
