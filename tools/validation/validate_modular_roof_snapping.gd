extends SceneTree

const SOLVER_PATH := "res://addons/world_authoring/building_snap_solver.gd"
const ROOF_L := "res://scenes/building_pieces/quaternius/medieval_village/roof_modular_round_tiles_6_l.tscn"
const ROOF_MID := "res://scenes/building_pieces/quaternius/medieval_village/roof_modular_round_tiles_6_mid.tscn"
const ROOF_R := "res://scenes/building_pieces/quaternius/medieval_village/roof_modular_round_tiles_6_r.tscn"
const GABLE := "res://scenes/building_pieces/quaternius/medieval_village/roof_front_wood_8.tscn"
const WALL := "res://scenes/building_pieces/quaternius/medieval_village_woodbrick/wall_woodbrick_straight.tscn"
const DEFINITIONS := [
	"res://features/world/resources/building_pieces/quaternius/medieval_village/roof_modular_round_tiles_6_l.tres",
	"res://features/world/resources/building_pieces/quaternius/medieval_village/roof_modular_round_tiles_6_mid.tres",
	"res://features/world/resources/building_pieces/quaternius/medieval_village/roof_modular_round_tiles_6_r.tres",
	"res://features/world/resources/building_pieces/quaternius/medieval_village/roof_front_wood_8.tres",
]

var _failures: Array[String] = []
var _solver


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_solver = load(SOLVER_PATH)
	var left := _instance(ROOF_L)
	var middle := _instance(ROOF_MID)
	var right := _instance(ROOF_R)
	left.global_position = Vector3(0, 3.904816, -2)
	middle.global_transform = _solver.piece_snap_transform(middle, _marker(middle, "run_negative_z"), _marker(left, "run_positive_z"))
	right.global_transform = _solver.piece_snap_transform(right, _marker(right, "run_negative_z"), _marker(middle, "run_positive_z"))
	_expect_transform(middle.global_transform, Transform3D(Basis.IDENTITY, Vector3(0, 3.866244, 0)), "L to Mid")
	_expect_transform(right.global_transform, Transform3D(Basis.IDENTITY, Vector3(0, 3.904816, 2)), "Mid to R")

	var front := _instance(GABLE)
	front.global_transform = _solver.piece_snap_transform(front, _marker(front, "roof_insert"), _marker(right, "gable_positive_z"))
	_expect_transform(front.global_transform, Transform3D(Basis.IDENTITY, Vector3(0, 3.254491, 2.05)), "front gable")
	var back := _instance(GABLE)
	back.global_transform = _solver.piece_snap_transform(back, _marker(back, "roof_insert"), _marker(left, "gable_negative_z"))
	_expect_transform(back.global_transform, Transform3D(Basis(Vector3.UP, PI), Vector3(0, 3.254491, -2.05)), "back gable")

	for index in range(4):
		var wall := _instance(WALL)
		wall.global_position = Vector3(-3 + index * 2, 0, 3)
		var gap := (_marker(front, "wall_%d" % index) as Node3D).global_position.distance_to((_marker(wall, "top") as Node3D).global_position)
		_expect(gap <= 0.002, "front gable wall marker %d misses by %.6f m" % [index, gap])

	_expect(not _solver.markers_compatible(_marker(middle, "run_negative_z"), _marker(right, "run_negative_z")), "same roof ends must not connect")
	_expect(not _solver.markers_compatible(_marker(left, "run_positive_z"), _marker(middle, "run_positive_z")), "same roof ends must not connect")
	_expect(_marker(left, "ridge") == null and _marker(middle, "ridge") == null and _marker(right, "ridge") == null, "full roof modules must not expose fake ridge connectors")

	for definition_path in DEFINITIONS:
		_validate_definition_parity(definition_path)
	_finish()


func _instance(path: String) -> Node3D:
	var node := (load(path) as PackedScene).instantiate() as Node3D
	root.add_child(node)
	return node


func _marker(piece: Node3D, snap_id: String) -> Node:
	for marker in piece.call("get_snap_markers"):
		if str(marker.get("snap_id")) == snap_id:
			return marker
	return null


func _expect_transform(actual: Transform3D, expected: Transform3D, label: String) -> void:
	_expect(actual.origin.distance_to(expected.origin) <= 0.002, "%s origin %s != %s" % [label, actual.origin, expected.origin])
	_expect(actual.basis.is_equal_approx(expected.basis), "%s rotation does not match" % label)


func _validate_definition_parity(path: String) -> void:
	var definition := load(path) as Resource
	var wrapper := (definition.get("scene") as PackedScene).instantiate() as Node3D
	root.add_child(wrapper)
	var markers: Array = wrapper.call("get_snap_markers")
	var points: Array = definition.get("snap_points")
	_expect(markers.size() == points.size(), "%s marker count mismatch" % path.get_file())
	for point in points:
		var marker := _marker(wrapper, str(point.get("snap_id")))
		_expect(marker != null, "%s missing marker %s" % [path.get_file(), point.get("snap_id")])
		if marker == null:
			continue
		_expect(str(marker.get("connector_type")) == str(point.get("connector_type")), "%s connector mismatch" % point.get("snap_id"))
		_expect(marker.get("accepts_types") == point.get("accepts_types"), "%s accepts mismatch" % point.get("snap_id"))
		_expect((marker as Node3D).transform.is_equal_approx(point.get("local_transform")), "%s transform mismatch" % point.get("snap_id"))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("MODULAR_ROOF_SNAPPING_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("MODULAR_ROOF_SNAPPING_FAILED count=%d" % _failures.size())
	quit(1)
