extends SceneTree

const CATALOG_PATH := "res://features/world/resources/building_pieces/quaternius/medieval_village_woodbrick/starter_woodbrick_catalog.tres"
const ROOF_IDS := [
	"roof_modular_flattiles_6_l",
	"roof_modular_flattiles_6_mid",
	"roof_modular_flattiles_6_r",
	"roof_modular_flattiles_8_l",
	"roof_modular_flattiles_8_mid",
	"roof_modular_flattiles_8_r",
]

var _failures: Array[String] = []


func _init() -> void:
	var catalog := load(CATALOG_PATH) as Resource
	_expect(catalog != null, "Missing modular piece catalog.")
	if catalog == null:
		_finish()
		return
	_expect(catalog.get("pieces").size() == 30, "Catalog should contain the reviewed starter set, roof modules, and three shop pieces.")
	for piece_id in ROOF_IDS:
		var definition := catalog.call("get_piece", piece_id) as Resource
		_expect(definition != null, "Catalog missing %s." % piece_id)
		if definition == null:
			continue
		_expect(str(definition.get("category")) == "roof", "%s must be a roof piece." % piece_id)
		var snap_points: Array = definition.get("snap_points")
		_expect(snap_points.size() == 4, "%s must define two eaves and two directional run/end snap points." % piece_id)
		var snap_ids: Array[String] = []
		for snap_point in snap_points:
			snap_ids.append(str(snap_point.get("snap_id")))
		_expect(snap_ids.has("eave_west") and snap_ids.has("eave_east"), "%s missing eave markers." % piece_id)
		if piece_id.ends_with("_l"):
			_expect(snap_ids.has("run_positive_z") and snap_ids.has("gable_negative_z"), "%s missing L run/gable markers." % piece_id)
		elif piece_id.ends_with("_mid"):
			_expect(snap_ids.has("run_negative_z") and snap_ids.has("run_positive_z"), "%s missing Mid run markers." % piece_id)
		else:
			_expect(snap_ids.has("run_negative_z") and snap_ids.has("gable_positive_z"), "%s missing R run/gable markers." % piece_id)
		var source := definition.get("source_scene") as PackedScene
		_expect(source != null, "%s missing raw source link." % piece_id)
		var scene := definition.get("scene") as PackedScene
		_expect(scene != null, "%s missing wrapper scene." % piece_id)
		if scene == null:
			continue
		var wrapper := scene.instantiate() as Node3D
		_expect(wrapper != null, "%s wrapper did not instantiate." % piece_id)
		if wrapper == null:
			continue
		_expect(wrapper.get_piece_id() == piece_id, "%s wrapper ID mismatch." % piece_id)
		_expect(wrapper.get_snap_markers().size() == 4, "%s wrapper must expose four snap markers." % piece_id)
		_expect(wrapper.get_node_or_null("Model") != null, "%s wrapper must keep the raw model beneath Model." % piece_id)
		wrapper.free()
	_finish(catalog.get("pieces").size())


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish(catalog_size := 0) -> void:
	if _failures.is_empty():
		print("MEDIEVAL_ROOF_MODULES_OK count=%d catalog=%d" % [ROOF_IDS.size(), catalog_size])
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)
