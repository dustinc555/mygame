extends SceneTree

const WORLD_BUILDING_SCRIPT := "res://features/world/projection/buildings/world_building.gd"
const ACTIVE_SCENES := [
	"res://scenes/zones/rustwash_basin/rustwash_basin.tscn",
	"res://scenes/zones/demo_zone/towns/surf_city.tscn",
	"res://scenes/zones/demo_zone/towns/east_raiders_camp.tscn",
	"res://scenes/zones/demo_zone/towns/paradise_hills.tscn",
	"res://scenes/test_levels/two_towns_road_test.tscn",
	"res://scenes/test_levels/jail_law_demo.tscn",
]

var _failures: Array[String] = []


func _initialize() -> void:
	var source := FileAccess.get_file_as_string(WORLD_BUILDING_SCRIPT)
	_expect(not source.contains("_derive_stable_building_id"), "WorldBuilding must not derive identity from scene paths")
	_expect(not source.contains("get_path()).trim_prefix"), "WorldBuilding must not use scene paths as identity")
	for scene_path in ACTIVE_SCENES:
		var text := FileAccess.get_file_as_string(scene_path)
		_expect(text.contains("building_id ="), "%s has no authored building IDs" % scene_path)
		_expect(not text.contains("population_capacity_id ="), "%s still carries legacy capacity identity" % scene_path)
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("BUILDING_AUTHORED_IDS_VALIDATION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)
