extends SceneTree
## Imports the Quaternius medieval_village_megakit gltf pieces as modular
## building pieces: a wrapper scene (ModularBuildingPiece / WorldDoor), a
## ModularBuildingPieceDefinition resource, and a full-kit catalog.
##
## Usage:
##   godot --headless --path . --script res://tools/importers/import_medieval_village_modular_pieces.gd -- verify
##   godot --headless --path . --script res://tools/importers/import_medieval_village_modular_pieces.gd -- generate
##
## verify:   recompute every already-imported piece from its source gltf and
##           diff bounds/snap points against the checked-in definition. Proves
##           the formulas below reproduce the hand-authored conventions.
## generate: write wrapper scenes + definitions for every megakit gltf that has
##           no definition yet, then write the full catalog.

const SOURCE_DIR := "res://assets/vendor/quaternius/medieval_village_megakit/gltf_godot"
const DEFINITIONS_ROOT := "res://features/world/resources/building_pieces/quaternius"
const NEW_DEFINITION_DIR := "res://features/world/resources/building_pieces/quaternius/medieval_village"
const NEW_SCENE_DIR := "res://scenes/building_pieces/quaternius/medieval_village"
const DOOR_DEFINITION_DIR := "res://features/doors/resources"
const CATALOG_PATH := "res://features/world/resources/building_pieces/quaternius/medieval_village_full_catalog.tres"

const PIECE_SCRIPT := preload("res://features/world/projection/buildings/modular_building_piece.gd")
const WORLD_DOOR_SCRIPT := preload("res://features/doors/projection/world_door.gd")
const SNAP_MARKER_SCRIPT := preload("res://features/world/projection/buildings/modular_building_snap_marker.gd")
const SNAP_POINT_SCRIPT := preload("res://features/world/resources/building_pieces/modular_building_snap_point.gd")
const DEFINITION_SCRIPT := preload("res://features/world/resources/building_pieces/modular_building_piece_definition.gd")
const CATALOG_SCRIPT := preload("res://features/world/resources/building_pieces/modular_building_piece_catalog.gd")
const DOOR_DEFINITION_SCRIPT := preload("res://features/doors/resources/door_definition.gd")

## Opening sockets sit at kit-calibrated heights, not at any AABB feature
## (measured from the hand-authored woodbrick pieces; uniform across families).
## Flat and round openings differ: round doors/arches are taller.
const DOOR_SOCKET_HEIGHT_FLAT := 1.1182
const DOOR_SOCKET_HEIGHT_ROUND := 1.2241
const WINDOW_SOCKET_HEIGHT_WIDE_FLAT := 1.7105
const WINDOW_SOCKET_HEIGHT_WIDE_ROUND := 1.8882
const WINDOW_SOCKET_HEIGHT_THIN := 1.8206
## Door wrappers are calibrated to the kit wall plane, not the door mesh: the
## insert snap, blocker, and click panel all sit on the wall's local Z plane so
## the art hangs slightly proud of the wall once snapped (Door_1 convention).
const DOOR_PLANE_Z := -0.110794306
## The wall opening is wider than any door panel (Door_1: 1.38 blocker).
const DOOR_OPENING_WIDTH := 1.38
const WALL_THICKNESS := 0.406482
const AUTO_OPEN_DEPTH := 2.4
const INTERACTION_DISTANCE := 0.9
## Balcony rails wrap a 2m floor cell (origin at cell center); the rail mesh
## overhangs the cell edge by a ~0.1m lip, which is how rail sides are detected.
const BALCONY_CELL_HALF := 1.0
const BALCONY_LIP_EPSILON := 0.05

## Snap marker bases, matched to the hand-authored pieces (column vectors).
const BASIS_IDENTITY := Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
## Sits on the piece's -X face / left edge (also floors' west edge).
const BASIS_SIDE_MIN_X := Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))
## Sits on the piece's +X face / right edge (also floors' east edge).
const BASIS_SIDE_MAX_X := Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0))
const BASIS_Y_180 := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1))
const BASIS_FACE_DOWN := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
const BASIS_FACE_UP := Basis(Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(0, -1, 0))

const POSITION_EPSILON := 0.002
const BASIS_EPSILON := 0.002
const BOUNDS_EPSILON := 0.002

var _errors: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var mode := "verify"
	var user_args := OS.get_cmdline_user_args()
	if not user_args.is_empty():
		mode = user_args[0]
	var exit_code := 0
	match mode:
		"verify":
			exit_code = _run_verify()
		"generate":
			exit_code = _run_generate()
		_:
			push_error("Unknown mode '%s' (expected verify or generate)" % mode)
			exit_code = 2
	quit(exit_code)


## ---------------------------------------------------------------- discovery


func _list_source_scene_names() -> PackedStringArray:
	var names := PackedStringArray()
	var dir := DirAccess.open(SOURCE_DIR)
	if dir == null:
		_fail("Cannot open source dir %s" % SOURCE_DIR)
		return names
	for file in dir.get_files():
		if file.ends_with(".gltf"):
			var piece_name := file.get_basename()
			if not piece_name.begins_with("SampleScene"):
				names.append(piece_name)
	names.sort()
	return names


## Maps source gltf path -> existing definition resource path.
func _collect_existing_definitions() -> Dictionary:
	var result: Dictionary = {}
	_scan_definitions_dir(DEFINITIONS_ROOT, result)
	return result


func _scan_definitions_dir(dir_path: String, result: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for subdir in dir.get_directories():
		_scan_definitions_dir(dir_path.path_join(subdir), result)
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var resource := load(dir_path.path_join(file))
		if resource == null or resource.get_script() != DEFINITION_SCRIPT:
			continue
		var source: PackedScene = resource.source_scene
		if source != null:
			result[source.resource_path] = dir_path.path_join(file)


## ------------------------------------------------------------ classification


func _classify(piece_name: String) -> Dictionary:
	var category := ""
	if piece_name.begins_with("DoorFrame"):
		category = "door_frame"
	elif piece_name.begins_with("Door_"):
		category = "door"
	elif piece_name.begins_with("WindowShutters"):
		category = "shutter"
	elif piece_name.begins_with("Window"):
		category = "window"
	elif piece_name.begins_with("Wall_"):
		if piece_name.contains("_Door"):
			category = "wall_door"
		elif piece_name.contains("_Window"):
			category = "wall_window"
		else:
			category = "wall"
	elif piece_name.begins_with("Corner"):
		category = "corner"
	elif piece_name.begins_with("Floor"):
		category = "floor"
	elif piece_name.begins_with("Roof_Front"):
		category = "roof_front"
	elif piece_name.begins_with("Roof"):
		category = "roof"
	elif piece_name.begins_with("Stair"):
		category = "stairs"
	elif piece_name.begins_with("HoleCover"):
		category = "hole_cover"
	elif piece_name.begins_with("Overhang"):
		category = "overhang"
	elif piece_name.begins_with("Balcony"):
		category = "balcony"
	elif piece_name.begins_with("Prop"):
		category = "prop"
	else:
		category = "prop"
	return {
		"name": piece_name,
		"category": category,
		"piece_id": piece_name.to_snake_case(),
		"display_name": piece_name.replace("_", " "),
		"tags": _tags_for(piece_name, category),
	}


func _tags_for(piece_name: String, category: String) -> PackedStringArray:
	var tags := PackedStringArray()
	for part in piece_name.split("_", false):
		var tag := part.to_snake_case()
		if not tag.is_empty() and not tags.has(tag):
			tags.append(tag)
	if not tags.has(category):
		tags.append(category)
	return tags


## ------------------------------------------------------------------ geometry


func _compute_aabb(instance: Node3D) -> AABB:
	var found: Array[AABB] = []
	_collect_mesh_aabbs(instance, Transform3D.IDENTITY, found)
	if found.is_empty():
		return AABB()
	var merged: AABB = found[0]
	for index in range(1, found.size()):
		merged = merged.merge(found[index])
	return merged


func _collect_mesh_aabbs(node: Node, parent_transform: Transform3D, result: Array[AABB]) -> void:
	var node_transform := parent_transform
	if node is Node3D:
		node_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			result.append(node_transform * mesh.get_aabb())
	for child in node.get_children():
		_collect_mesh_aabbs(child, node_transform, result)


func _grid_size_for(bounds: Vector3, cell_size: float) -> Vector3i:
	return Vector3i(
		maxi(1, ceili(bounds.x / cell_size)),
		maxi(1, ceili(bounds.y / cell_size)),
		maxi(1, ceili(bounds.z / cell_size))
	)


## ---------------------------------------------------------------- snap plans
## Each snap is {snap_id, display_name, connector_type, accepts, transform}.


func _build_snap_plan(category: String, piece_name: String, aabb: AABB) -> Array:
	var center := aabb.get_center()
	var min_point := aabb.position
	var max_point := aabb.end
	match category:
		"wall", "wall_door", "wall_window":
			var snaps := [
				_snap("left", "Left", "wall_side", ["wall_side", "corner_side"], BASIS_SIDE_MIN_X, Vector3(min_point.x, center.y, center.z)),
				_snap("right", "Right", "wall_side", ["wall_side", "corner_side"], BASIS_SIDE_MAX_X, Vector3(max_point.x, center.y, center.z)),
				_snap("bottom", "Bottom", "wall_bottom", ["floor_edge"], BASIS_FACE_DOWN, Vector3(center.x, min_point.y, center.z)),
				_snap("top", "Top", "wall_top", ["roof_wall_top", "wall_bottom"], BASIS_FACE_UP, Vector3(center.x, max_point.y, center.z)),
			]
			if category == "wall_door":
				snaps.append(_snap("center", "Door Center", "door_socket", ["door_insert"], BASIS_IDENTITY, Vector3(center.x, _door_socket_height(piece_name), center.z)))
			elif category == "wall_window":
				snaps.append(_snap("center", "Window Center", "window_socket", ["window_insert"], BASIS_IDENTITY, Vector3(center.x, _window_socket_height(piece_name), center.z)))
			return snaps
		"corner":
			return [
				_snap("wall_a", "Wall A", "corner_side", ["wall_side"], BASIS_SIDE_MAX_X, Vector3(max_point.x, center.y, center.z)),
				_snap("wall_b", "Wall B", "corner_side", ["wall_side"], BASIS_Y_180, Vector3(center.x, center.y, max_point.z)),
				_snap("bottom", "Bottom", "wall_bottom", ["floor_edge"], BASIS_FACE_DOWN, Vector3(center.x, min_point.y, center.z)),
				_snap("top", "Top", "wall_top", ["roof_wall_top", "wall_bottom"], BASIS_FACE_UP, Vector3(center.x, max_point.y, center.z)),
			]
		"floor", "hole_cover":
			return [
				_snap("north", "North", "floor_edge", ["floor_edge", "wall_bottom"], BASIS_IDENTITY, Vector3(center.x, center.y, min_point.z)),
				_snap("south", "South", "floor_edge", ["floor_edge", "wall_bottom"], BASIS_Y_180, Vector3(center.x, center.y, max_point.z)),
				_snap("east", "East", "floor_edge", ["floor_edge", "wall_bottom"], BASIS_SIDE_MAX_X, Vector3(max_point.x, center.y, center.z)),
				_snap("west", "West", "floor_edge", ["floor_edge", "wall_bottom"], BASIS_SIDE_MIN_X, Vector3(min_point.x, center.y, center.z)),
				_snap("up", "Up", "floor_up", ["wall_bottom", "stairs_bottom"], BASIS_FACE_UP, Vector3(center.x, max_point.y, center.z)),
			]
		"roof":
			var roof_z := _roof_family_plane_z(piece_name, center.z)
			return [
				_snap("left", "Left", "roof_side", ["roof_side"], BASIS_SIDE_MIN_X, Vector3(min_point.x, center.y, roof_z)),
				_snap("right", "Right", "roof_side", ["roof_side"], BASIS_SIDE_MAX_X, Vector3(max_point.x, center.y, roof_z)),
				_snap("wall_top", "Wall Top", "roof_wall_top", ["wall_top"], BASIS_FACE_DOWN, Vector3(center.x, min_point.y, roof_z)),
				_snap("ridge", "Ridge", "roof_ridge", ["roof_ridge"], BASIS_FACE_UP, Vector3(center.x, max_point.y, roof_z)),
			]
		"roof_front":
			return [
				_snap("left", "Left", "roof_front_side", ["roof_side"], BASIS_SIDE_MIN_X, Vector3(min_point.x, center.y, center.z)),
				_snap("right", "Right", "roof_front_side", ["roof_side"], BASIS_SIDE_MAX_X, Vector3(max_point.x, center.y, center.z)),
				_snap("wall_top", "Wall Top", "roof_wall_top", ["wall_top"], BASIS_FACE_DOWN, Vector3(center.x, min_point.y, center.z)),
			]
		"stairs":
			return [
				_snap("bottom", "Bottom", "stairs_bottom", ["floor_up"], BASIS_Y_180, Vector3(center.x, min_point.y, max_point.z)),
				_snap("top", "Top", "stairs_top", ["floor_edge", "floor_up"], BASIS_IDENTITY, Vector3(center.x, max_point.y, min_point.z)),
			]
		"window", "shutter":
			# Frame/shutter inserts land on the wall socket, so they carry the
			# socket's calibrated height and wall plane, not their own center.
			return [_snap("center", "Center", "window_insert", ["window_socket"], BASIS_IDENTITY, Vector3(center.x, _window_socket_height(piece_name), DOOR_PLANE_Z))]
		"door_frame":
			return [_snap("center", "Center", "door_insert", ["door_socket"], BASIS_IDENTITY, center)]
		"door":
			return [_snap("center", "Center", "door_insert", ["door_socket"], BASIS_IDENTITY, Vector3(center.x, _door_socket_height(piece_name), DOOR_PLANE_Z))]
		"overhang":
			return [
				_snap("bottom", "Bottom", "wall_bottom", ["wall_top"], BASIS_FACE_DOWN, Vector3(center.x, min_point.y, center.z)),
				_snap("top", "Top", "wall_top", ["roof_wall_top", "wall_bottom"], BASIS_FACE_UP, Vector3(center.x, max_point.y, center.z)),
			]
		"balcony":
			return _build_balcony_snap_plan(aabb)
		_:
			# prop: free placement.
			return []
	return []


## Balcony pieces are railing strips wrapping a 2m floor cell with the origin
## at the CELL CENTER, not on the mesh: a rail exists on each side whose AABB
## lip sticks out past the cell edge. Each rail carries three connector kinds:
## - balcony_rail (edge midpoint): binds the floor edge it wraps; its basis
##   matches that edge's basis so the designer can require the rail to lie
##   ALONG its edge, never across it.
## - balcony_rail_end (rail ends at the cell corners): rails chain end-to-end
##   like wall sides, so a ring keeps building even across deck holes. Ends
##   where two rails of the same piece meet (corner pieces) are omitted.
## - balcony_rail_bottom (edge midpoint): binds a wall_top, so a rail can sit
##   on the wall below when there is no floor cell at all.
func _build_balcony_snap_plan(aabb: AABB) -> Array:
	var sides: Array[String] = []
	if aabb.end.z > BALCONY_CELL_HALF + BALCONY_LIP_EPSILON:
		sides.append("south")
	if aabb.position.z < -BALCONY_CELL_HALF - BALCONY_LIP_EPSILON:
		sides.append("north")
	if aabb.end.x > BALCONY_CELL_HALF + BALCONY_LIP_EPSILON:
		sides.append("east")
	if aabb.position.x < -BALCONY_CELL_HALF - BALCONY_LIP_EPSILON:
		sides.append("west")
	var side_data := {
		"south": {"mid": Vector3(0, 0, BALCONY_CELL_HALF), "basis": BASIS_Y_180, "corners": ["southwest", "southeast"]},
		"north": {"mid": Vector3(0, 0, -BALCONY_CELL_HALF), "basis": BASIS_IDENTITY, "corners": ["northwest", "northeast"]},
		"east": {"mid": Vector3(BALCONY_CELL_HALF, 0, 0), "basis": BASIS_SIDE_MAX_X, "corners": ["northeast", "southeast"]},
		"west": {"mid": Vector3(-BALCONY_CELL_HALF, 0, 0), "basis": BASIS_SIDE_MIN_X, "corners": ["northwest", "southwest"]},
	}
	var corner_positions := {
		"northwest": Vector3(-BALCONY_CELL_HALF, 0, -BALCONY_CELL_HALF),
		"northeast": Vector3(BALCONY_CELL_HALF, 0, -BALCONY_CELL_HALF),
		"southeast": Vector3(BALCONY_CELL_HALF, 0, BALCONY_CELL_HALF),
		"southwest": Vector3(-BALCONY_CELL_HALF, 0, BALCONY_CELL_HALF),
	}
	var corner_use := {}
	for side in sides:
		for corner in side_data[side]["corners"]:
			corner_use[corner] = int(corner_use.get(corner, 0)) + 1
	var plan := []
	for side in sides:
		var mid: Vector3 = side_data[side]["mid"]
		var side_basis: Basis = side_data[side]["basis"]
		plan.append(_snap(side, side.capitalize(), "balcony_rail", ["floor_edge"], side_basis, mid))
		plan.append(_snap(side + "_bottom", side.capitalize() + " Bottom", "balcony_rail_bottom", ["wall_top"], BASIS_FACE_DOWN, mid))
		for corner in side_data[side]["corners"]:
			# Ends where two rails of this piece meet stay closed: another
			# piece chaining there would overlap this piece's other rail.
			if int(corner_use[corner]) > 1:
				continue
			var corner_position: Vector3 = corner_positions[corner]
			# End basis Z points back along the rail toward its midpoint,
			# mirroring the wall left/right convention.
			var inward: Vector3 = (mid - corner_position).normalized()
			var end_basis := BASIS_IDENTITY
			if inward.z > 0.5:
				end_basis = BASIS_IDENTITY
			elif inward.z < -0.5:
				end_basis = BASIS_Y_180
			elif inward.x > 0.5:
				end_basis = BASIS_SIDE_MIN_X
			else:
				end_basis = BASIS_SIDE_MAX_X
			plan.append(_snap(side + "_end_" + corner, side.capitalize() + " End " + corner.capitalize(), "balcony_rail_end", ["balcony_rail_end"], end_basis, corner_position))
	return plan


func _door_socket_height(piece_name: String) -> float:
	return DOOR_SOCKET_HEIGHT_ROUND if piece_name.contains("Round") else DOOR_SOCKET_HEIGHT_FLAT


func _window_socket_height(piece_name: String) -> float:
	if piece_name.contains("Thin"):
		return WINDOW_SOCKET_HEIGHT_THIN
	if piece_name.contains("Round"):
		return WINDOW_SOCKET_HEIGHT_WIDE_ROUND
	return WINDOW_SOCKET_HEIGHT_WIDE_FLAT


## Modular roof L/R segments carry asymmetric eave trim that skews their own
## AABB center Z, but the whole L/mid/R run must interlock on one plane, so
## every segment takes its snap Z from its _Mid sibling.
func _roof_family_plane_z(piece_name: String, own_center_z: float) -> float:
	if not piece_name.begins_with("Roof_Modular_"):
		return own_center_z
	if not (piece_name.ends_with("_L") or piece_name.ends_with("_R")):
		return own_center_z
	var mid_name := piece_name.rsplit("_", false, 1)[0] + "_Mid"
	var mid_path := SOURCE_DIR.path_join(mid_name + ".gltf")
	if not ResourceLoader.exists(mid_path):
		return own_center_z
	var mid_aabb := _instantiate_and_measure(mid_path)
	if mid_aabb == AABB():
		return own_center_z
	return mid_aabb.get_center().z


func _snap(snap_id: String, display_name: String, connector_type: String, accepts: Array, basis: Basis, origin: Vector3) -> Dictionary:
	return {
		"snap_id": snap_id,
		"display_name": display_name,
		"connector_type": connector_type,
		"accepts": PackedStringArray(accepts),
		"transform": Transform3D(basis, origin),
	}


## -------------------------------------------------------------------- verify


func _run_verify() -> int:
	var existing := _collect_existing_definitions()
	var checked := 0
	var clean := 0
	for source_path in existing.keys():
		var definition := load(existing[source_path])
		var piece_name: String = String(source_path).get_file().get_basename()
		var spec := _classify(piece_name)
		var aabb := _instantiate_and_measure(source_path)
		if aabb == AABB():
			_fail("%s: no meshes found" % piece_name)
			continue
		checked += 1
		var diffs := PackedStringArray()
		# Door and window-frame bounds were hand-calibrated to the wall opening,
		# not the mesh AABB; only their snap points are formula-reproducible.
		if spec.category != "door" and spec.category != "window" and not _vectors_close(definition.bounds_size_meters, aabb.size, BOUNDS_EPSILON):
			diffs.append("bounds stored %s vs computed %s" % [definition.bounds_size_meters, aabb.size])
		if definition.category != spec.category:
			diffs.append("category stored '%s' vs classified '%s'" % [definition.category, spec.category])
		var plan := _build_snap_plan(spec.category, piece_name, aabb)
		var stored_ids := PackedStringArray()
		for stored in definition.snap_points:
			stored_ids.append(stored.snap_id)
			var planned := _plan_entry(plan, stored.snap_id)
			if planned.is_empty():
				diffs.append("snap '%s' missing from computed plan" % stored.snap_id)
				continue
			var planned_transform: Transform3D = planned.transform
			if not _vectors_close(stored.local_transform.origin, planned_transform.origin, POSITION_EPSILON):
				diffs.append("snap '%s' origin stored %s vs computed %s" % [stored.snap_id, stored.local_transform.origin, planned_transform.origin])
			if not _bases_close(stored.local_transform.basis, planned_transform.basis):
				diffs.append("snap '%s' basis stored %s vs computed %s" % [stored.snap_id, stored.local_transform.basis, planned_transform.basis])
			if stored.connector_type != planned.connector_type:
				diffs.append("snap '%s' connector stored '%s' vs computed '%s'" % [stored.snap_id, stored.connector_type, planned.connector_type])
		for planned in plan:
			if not stored_ids.has(planned.snap_id):
				diffs.append("computed snap '%s' absent from stored definition" % planned.snap_id)
		if diffs.is_empty():
			clean += 1
			print("OK   %s" % piece_name)
		else:
			print("DIFF %s" % piece_name)
			for diff in diffs:
				print("     - %s" % diff)
	print("VERIFY: %d/%d existing pieces reproduced exactly" % [clean, checked])
	if not _errors.is_empty():
		return 1
	return 0 if clean == checked else 1


func _plan_entry(plan: Array, snap_id: String) -> Dictionary:
	for entry in plan:
		if entry.snap_id == snap_id:
			return entry
	return {}


func _vectors_close(a: Vector3, b: Vector3, epsilon: float) -> bool:
	return absf(a.x - b.x) <= epsilon and absf(a.y - b.y) <= epsilon and absf(a.z - b.z) <= epsilon


func _bases_close(a: Basis, b: Basis) -> bool:
	return _vectors_close(a.x, b.x, BASIS_EPSILON) and _vectors_close(a.y, b.y, BASIS_EPSILON) and _vectors_close(a.z, b.z, BASIS_EPSILON)


func _instantiate_and_measure(source_path: String) -> AABB:
	var packed: PackedScene = load(source_path)
	if packed == null:
		_fail("Cannot load %s" % source_path)
		return AABB()
	var instance := packed.instantiate() as Node3D
	if instance == null:
		_fail("Root of %s is not Node3D" % source_path)
		return AABB()
	var aabb := _compute_aabb(instance)
	instance.free()
	return aabb


## ------------------------------------------------------------------ generate


func _run_generate() -> int:
	var existing := _collect_existing_definitions()
	var names := _list_source_scene_names()
	DirAccess.make_dir_recursive_absolute(NEW_SCENE_DIR)
	DirAccess.make_dir_recursive_absolute(NEW_DEFINITION_DIR)
	var all_definition_paths: Array[String] = []
	for path in existing.values():
		all_definition_paths.append(path)
	var generated := 0
	for piece_name in names:
		var source_path := SOURCE_DIR.path_join(piece_name + ".gltf")
		if existing.has(source_path):
			continue
		var definition_path := _generate_piece(piece_name, source_path)
		if definition_path.is_empty():
			continue
		all_definition_paths.append(definition_path)
		generated += 1
	_write_catalog(all_definition_paths)
	print("GENERATE: %d new pieces, catalog has %d entries" % [generated, all_definition_paths.size()])
	if not _errors.is_empty():
		for error in _errors:
			printerr("ERROR: %s" % error)
		return 1
	return 0


func _generate_piece(piece_name: String, source_path: String) -> String:
	var spec := _classify(piece_name)
	var aabb := _instantiate_and_measure(source_path)
	if aabb == AABB() or aabb.size == Vector3.ZERO:
		_fail("%s: no measurable meshes, skipped" % piece_name)
		return ""
	var plan := _build_snap_plan(spec.category, piece_name, aabb)
	var scene_path: String = NEW_SCENE_DIR.path_join(String(spec.piece_id) + ".tscn")
	var definition_path: String = NEW_DEFINITION_DIR.path_join(String(spec.piece_id) + ".tres")
	var wrapper_error := ""
	if spec.category == "door":
		wrapper_error = _save_door_wrapper(spec, source_path, aabb, plan, scene_path)
	else:
		wrapper_error = _save_piece_wrapper(spec, source_path, aabb, plan, scene_path)
	if not wrapper_error.is_empty():
		_fail("%s: %s" % [piece_name, wrapper_error])
		return ""
	var definition_error := _save_definition(spec, source_path, scene_path, aabb, plan, definition_path)
	if not definition_error.is_empty():
		_fail("%s: %s" % [piece_name, definition_error])
		return ""
	return definition_path


func _apply_piece_exports(root: Node3D, spec: Dictionary, aabb: AABB) -> void:
	root.name = String(spec.piece_id).to_pascal_case()
	root.piece_id = spec.piece_id
	root.display_name = spec.display_name
	root.category = spec.category
	root.grid_size_cells = _grid_size_for(aabb.size, root.grid_cell_size_meters)
	root.bounds_size_meters = aabb.size


func _add_snap_markers(root: Node3D, plan: Array) -> void:
	var snap_root := Node3D.new()
	snap_root.name = "SnapPoints"
	root.add_child(snap_root)
	snap_root.owner = root
	for entry in plan:
		var marker := Marker3D.new()
		marker.name = String(entry.display_name).to_pascal_case()
		marker.set_script(SNAP_MARKER_SCRIPT)
		marker.transform = entry.transform
		marker.snap_id = entry.snap_id
		marker.display_name = entry.display_name
		marker.connector_type = entry.connector_type
		marker.accepts_types = entry.accepts
		snap_root.add_child(marker)
		marker.owner = root


func _instance_model(source_path: String) -> Node3D:
	var packed: PackedScene = load(source_path)
	var model := packed.instantiate() as Node3D
	model.name = "Model"
	return model


func _save_piece_wrapper(spec: Dictionary, source_path: String, aabb: AABB, plan: Array, scene_path: String) -> String:
	var root := Node3D.new()
	root.set_script(PIECE_SCRIPT)
	_apply_piece_exports(root, spec, aabb)
	var model := _instance_model(source_path)
	root.add_child(model)
	model.owner = root
	_add_snap_markers(root, plan)
	return _pack_and_save(root, scene_path)


func _save_door_wrapper(spec: Dictionary, source_path: String, aabb: AABB, plan: Array, scene_path: String) -> String:
	var center := aabb.get_center()
	var size := aabb.size
	var door_definition_path: String = DOOR_DEFINITION_DIR.path_join(String(spec.piece_id) + ".tres")
	if not ResourceLoader.exists(door_definition_path):
		var door_definition: Resource = DOOR_DEFINITION_SCRIPT.new()
		var door_definition_error := ResourceSaver.save(door_definition, door_definition_path)
		if door_definition_error != OK:
			return "cannot save door definition (%d)" % door_definition_error

	var root := Node3D.new()
	root.set_script(WORLD_DOOR_SCRIPT)
	_apply_piece_exports(root, spec, aabb)
	root.disable_model_collision = true
	root.strip_model_collision_shapes = true
	root.door_definition = load(door_definition_path)

	var hinge := Node3D.new()
	hinge.name = "HingePivot"
	hinge.position = Vector3(aabb.position.x, 0.0, DOOR_PLANE_Z)
	root.add_child(hinge)
	hinge.owner = root

	var model := _instance_model(source_path)
	model.position = -hinge.position
	hinge.add_child(model)
	model.owner = root

	var panel := StaticBody3D.new()
	panel.name = "PanelClickTarget"
	panel.collision_layer = 16
	panel.collision_mask = 0
	panel.add_to_group("navigation_bake_excluded", true)
	hinge.add_child(panel)
	panel.owner = root
	var panel_shape := BoxShape3D.new()
	panel_shape.size = size
	_add_collision_shape(panel, panel_shape, Vector3(center.x, size.y * 0.5, DOOR_PLANE_Z) - hinge.position, root)

	var blocker := StaticBody3D.new()
	blocker.name = "ClosedBlocker"
	blocker.collision_layer = 8
	blocker.add_to_group("navigation_bake_excluded", true)
	root.add_child(blocker)
	blocker.owner = root
	var blocker_shape := BoxShape3D.new()
	blocker_shape.size = Vector3(maxf(DOOR_OPENING_WIDTH, size.x), size.y, WALL_THICKNESS)
	_add_collision_shape(blocker, blocker_shape, Vector3(center.x, size.y * 0.5, DOOR_PLANE_Z), root)

	var side_a := Marker3D.new()
	side_a.name = "InteractionSideA"
	side_a.position = Vector3(center.x, 0.0, DOOR_PLANE_Z - INTERACTION_DISTANCE)
	root.add_child(side_a)
	side_a.owner = root
	var side_b := Marker3D.new()
	side_b.name = "InteractionSideB"
	side_b.position = Vector3(center.x, 0.0, DOOR_PLANE_Z + INTERACTION_DISTANCE)
	root.add_child(side_b)
	side_b.owner = root

	var auto_open := Area3D.new()
	auto_open.name = "AutoOpenArea"
	auto_open.collision_layer = 0
	auto_open.collision_mask = 2
	root.add_child(auto_open)
	auto_open.owner = root
	var auto_open_shape := BoxShape3D.new()
	auto_open_shape.size = Vector3(maxf(DOOR_OPENING_WIDTH, size.x), size.y, AUTO_OPEN_DEPTH)
	_add_collision_shape(auto_open, auto_open_shape, Vector3(center.x, size.y * 0.5, DOOR_PLANE_Z), root)

	_add_snap_markers(root, plan)
	return _pack_and_save(root, scene_path)


func _add_collision_shape(parent: CollisionObject3D, shape: Shape3D, shape_position: Vector3, owner_root: Node3D) -> void:
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = shape
	collision.position = shape_position
	parent.add_child(collision)
	collision.owner = owner_root


func _pack_and_save(root: Node3D, scene_path: String) -> String:
	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	if pack_error != OK:
		root.free()
		return "pack failed (%d)" % pack_error
	var save_error := ResourceSaver.save(packed, scene_path)
	root.free()
	if save_error != OK:
		return "scene save failed (%d)" % save_error
	return ""


func _save_definition(spec: Dictionary, source_path: String, scene_path: String, aabb: AABB, plan: Array, definition_path: String) -> String:
	var definition: Resource = DEFINITION_SCRIPT.new()
	definition.piece_id = spec.piece_id
	definition.display_name = spec.display_name
	definition.category = spec.category
	definition.scene = load(scene_path)
	definition.source_scene = load(source_path)
	definition.grid_size_cells = _grid_size_for(aabb.size, definition.grid_cell_size_meters)
	definition.bounds_size_meters = aabb.size
	definition.tags = spec.tags
	var snap_points: Array = []
	for entry in plan:
		var snap_point: Resource = SNAP_POINT_SCRIPT.new()
		snap_point.snap_id = entry.snap_id
		snap_point.display_name = entry.display_name
		snap_point.connector_type = entry.connector_type
		snap_point.accepts_types = entry.accepts
		snap_point.local_transform = entry.transform
		snap_points.append(snap_point)
	definition.snap_points = snap_points
	var save_error := ResourceSaver.save(definition, definition_path)
	if save_error != OK:
		return "definition save failed (%d)" % save_error
	return ""


func _write_catalog(definition_paths: Array[String]) -> void:
	definition_paths.sort()
	var catalog: Resource = CATALOG_SCRIPT.new()
	catalog.catalog_id = "medieval_village_full"
	catalog.display_name = "Medieval Village Megakit"
	var pieces: Array = []
	for path in definition_paths:
		var definition := load(path)
		if definition != null:
			pieces.append(definition)
	catalog.pieces = pieces
	var save_error := ResourceSaver.save(catalog, CATALOG_PATH)
	if save_error != OK:
		_fail("catalog save failed (%d)" % save_error)


func _fail(message: String) -> void:
	_errors.append(message)
	printerr(message)
