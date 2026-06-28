extends SceneTree

const CATALOG_PATH := "res://resources/building_pieces/quaternius/medieval_village_woodbrick/starter_woodbrick_catalog.tres"
const EXPECTED_COUNT := 21
const ALLOWED_CATEGORIES := {
	"floor": true,
	"wall": true,
	"wall_door": true,
	"wall_window": true,
	"window": true,
	"door": true,
	"corner": true,
	"roof": true,
	"roof_front": true,
	"stairs": true,
}

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog := load(CATALOG_PATH)
	if catalog == null:
		_fail("Missing modular building starter catalog: %s" % CATALOG_PATH)
		_finish()
		return
	if catalog.pieces.size() != EXPECTED_COUNT:
		_fail("Expected %d starter pieces, found %d" % [EXPECTED_COUNT, catalog.pieces.size()])
	var seen_ids := {}
	for piece in catalog.pieces:
		_validate_piece(piece, seen_ids)
	_finish()


func _validate_piece(piece: Resource, seen_ids: Dictionary) -> void:
	if piece == null:
		_fail("Catalog contains null piece")
		return
	if piece.piece_id.is_empty():
		_fail("Piece has empty piece_id")
	elif seen_ids.has(piece.piece_id):
		_fail("Duplicate piece_id: %s" % piece.piece_id)
	else:
		seen_ids[piece.piece_id] = true
	if not ALLOWED_CATEGORIES.has(piece.category):
		_fail("Piece %s has invalid category %s" % [piece.piece_id, piece.category])
	if piece.piece_id.begins_with("prop_"):
		_fail("Starter catalog should not include loose prop piece: %s" % piece.piece_id)
	if piece.piece_id.begins_with("door_") and piece.category != "door":
		_fail("Door piece %s should use category door" % piece.piece_id)
	if piece.piece_id.begins_with("window_") and piece.category != "window":
		_fail("Window piece %s should use category window" % piece.piece_id)
	if piece.source_scene == null:
		_fail("Piece %s missing source_scene" % piece.piece_id)
	if piece.scene == null:
		_fail("Piece %s missing wrapper scene" % piece.piece_id)
	if piece.bounds_size_meters.length_squared() <= 0.0001:
		_fail("Piece %s missing measured bounds" % piece.piece_id)
	if piece.snap_points.is_empty():
		_fail("Piece %s has no snap points" % piece.piece_id)
	for snap_point in piece.snap_points:
		_validate_snap_point(piece, snap_point)
	_validate_floor_wall_snap_contract(piece)
	_validate_window_snap_contract(piece)
	_validate_door_snap_contract(piece)
	_validate_wrapper_scene(piece)


func _validate_snap_point(piece: Resource, snap_point: Resource) -> void:
	if snap_point == null:
		_fail("Piece %s has null snap point" % piece.piece_id)
		return
	if snap_point.snap_id.is_empty():
		_fail("Piece %s has snap point with empty id" % piece.piece_id)
	if snap_point.connector_type.is_empty():
		_fail("Piece %s snap %s has empty connector type" % [piece.piece_id, snap_point.snap_id])
	if snap_point.accepts_types.is_empty():
		_fail("Piece %s snap %s has no accepted connector types" % [piece.piece_id, snap_point.snap_id])


func _validate_floor_wall_snap_contract(piece: Resource) -> void:
	for snap_point in piece.snap_points:
		if snap_point == null:
			continue
		if snap_point.connector_type == "floor_edge" and not snap_point.accepts_types.has("wall_bottom"):
			_fail("Floor edge %s:%s should accept wall_bottom" % [piece.piece_id, snap_point.snap_id])
		if snap_point.connector_type == "wall_bottom":
			if not snap_point.accepts_types.has("floor_edge"):
				_fail("Wall bottom %s:%s should accept floor_edge" % [piece.piece_id, snap_point.snap_id])
			if snap_point.accepts_types.has("floor_up"):
				_fail("Wall bottom %s:%s should not snap to floor_up center" % [piece.piece_id, snap_point.snap_id])


func _validate_window_snap_contract(piece: Resource) -> void:
	if piece.category == "wall_window":
		var center: Resource = piece.get_snap_point("center")
		if center == null:
			_fail("Wall-window piece %s missing center window socket" % piece.piece_id)
		elif center.connector_type != "window_socket" or not center.accepts_types.has("window_insert"):
			_fail("Wall-window piece %s center should accept window inserts" % piece.piece_id)
	if piece.category == "window":
		var center: Resource = piece.get_snap_point("center")
		if center == null:
			_fail("Window insert %s missing center marker" % piece.piece_id)
		elif center.connector_type != "window_insert" or not center.accepts_types.has("window_socket"):
			_fail("Window insert %s center should snap to window sockets" % piece.piece_id)


func _validate_door_snap_contract(piece: Resource) -> void:
	if piece.category == "wall_door":
		var center: Resource = piece.get_snap_point("center")
		if center == null:
			_fail("Door-wall piece %s missing center door socket" % piece.piece_id)
		elif center.connector_type != "door_socket" or not center.accepts_types.has("door_insert"):
			_fail("Door-wall piece %s center should accept door inserts" % piece.piece_id)
	if piece.category == "door":
		var center: Resource = piece.get_snap_point("center")
		if center == null:
			_fail("Door insert %s missing center marker" % piece.piece_id)
		elif center.connector_type != "door_insert" or not center.accepts_types.has("door_socket"):
			_fail("Door insert %s center should snap to door sockets" % piece.piece_id)


func _validate_wrapper_scene(piece: Resource) -> void:
	var root: Node = piece.scene.instantiate()
	if root == null:
		_fail("Piece %s wrapper root should be ModularBuildingPiece" % piece.piece_id)
		return
	if root.piece_id != piece.piece_id:
		_fail("Piece %s wrapper piece_id mismatch: %s" % [piece.piece_id, root.piece_id])
	if root.get("auto_snap_enabled") != true:
		_fail("Piece %s wrapper should default auto_snap_enabled to true" % piece.piece_id)
	var model: Node = root.get_node_or_null("Model")
	if model == null:
		_fail("Piece %s wrapper missing Model child" % piece.piece_id)
	elif not _has_collision_node(model):
		_fail("Piece %s wrapper should inherit imported collision under Model" % piece.piece_id)
	var snap_root: Node = root.get_node_or_null("SnapPoints")
	if snap_root == null:
		_fail("Piece %s wrapper missing SnapPoints child" % piece.piece_id)
	var markers: Array = root.get_snap_markers()
	if markers.size() != piece.snap_points.size():
		_fail("Piece %s marker count %d does not match definition snap count %d" % [piece.piece_id, markers.size(), piece.snap_points.size()])
	var marker_ids := {}
	for marker in markers:
		if marker.snap_id.is_empty():
			_fail("Piece %s has marker with empty snap_id" % piece.piece_id)
		marker_ids[marker.snap_id] = true
		if marker.connector_type.is_empty():
			_fail("Piece %s marker %s has empty connector type" % [piece.piece_id, marker.snap_id])
		if not marker.editor_show_visual:
			_fail("Piece %s marker %s should show editor visual" % [piece.piece_id, marker.snap_id])
	for snap_point in piece.snap_points:
		if snap_point != null and not marker_ids.has(snap_point.snap_id):
			_fail("Piece %s definition snap %s missing wrapper marker" % [piece.piece_id, snap_point.snap_id])
	root.free()


func _has_collision_node(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D:
		return true
	for child in node.get_children():
		if _has_collision_node(child):
			return true
	return false


func _finish() -> void:
	if _failures.is_empty():
		print("MODULAR_BUILDING_STARTER_CATALOG_OK pieces=%d" % EXPECTED_COUNT)
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("MODULAR_BUILDING_STARTER_CATALOG_FAILED count=%d" % _failures.size())
	quit(1)


func _fail(message: String) -> void:
	_failures.append(message)
