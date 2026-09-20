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
	call_deferred("_run")


func _run() -> void:
	var source := FileAccess.get_file_as_string(WORLD_BUILDING_SCRIPT)
	_expect(not source.contains("_derive_stable_building_id"), "WorldBuilding must not derive identity from scene paths")
	_expect(not source.contains("get_path()).trim_prefix"), "WorldBuilding must not use scene paths as identity")
	for scene_path in ACTIVE_SCENES:
		var text := FileAccess.get_file_as_string(scene_path)
		var packed := load(scene_path) as PackedScene
		_expect(packed != null, "Authored scene must load: " + scene_path)
		if packed != null:
			var scene := packed.instantiate()
			_stamp_facilities(scene)
			var seen := {}
			_validate_building_ids(scene, scene_path, seen)
			_expect(not seen.is_empty(), "Authored scene must contain actual buildings: " + scene_path)
			scene.free()
		_expect(not text.contains("population_capacity_id ="), "%s still carries legacy capacity identity" % scene_path)
	_finish()


# Neutral shell IDs belong to their composed facility, exactly as at ready.
func _stamp_facilities(node: Node) -> void:
	if node.has_method("stamp_building_identity"):
		node.call("stamp_building_identity")
	for child in node.get_children(true):
		_stamp_facilities(child)

func _validate_building_ids(node: Node, scene_path: String, seen: Dictionary) -> void:
	if is_instance_of(node, load(WORLD_BUILDING_SCRIPT)):
		var id := str(node.get("building_id")).strip_edges()
		_expect(not id.is_empty(), "%s building %s has no authored durable ID" % [scene_path, node.name])
		_expect(not seen.has(id), "%s repeats durable building ID %s" % [scene_path, id])
		seen[id] = node.name
	for child in node.get_children(true):
		_validate_building_ids(child, scene_path, seen)

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
