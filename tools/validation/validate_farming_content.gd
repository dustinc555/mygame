extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_farming_content.gd

const CROP_PATHS := [
	"res://features/farming/resources/crops/tomato.tres",
	"res://features/farming/resources/crops/french_beans.tres",
	"res://features/farming/resources/crops/bell_pepper.tres",
	"res://features/farming/resources/crops/eggplant.tres",
	"res://features/farming/resources/crops/chili_pepper.tres",
	"res://features/farming/resources/crops/wheat.tres",
]
const TOOL_PATHS := {
	"res://features/inventory/resources/items/hoe.tres": "tool.hoe",
	"res://features/inventory/resources/items/bucket.tres": "tool.water_container",
	"res://features/inventory/resources/items/watering_can.tres": "tool.water_container",
	"res://features/inventory/resources/items/scythe.tres": "tool.scythe",
}


func _initialize() -> void:
	var failures: Array[String] = []
	for path in CROP_PATHS:
		var crop = load(path)
		_expect(failures, "%s loads" % path, crop != null)
		if crop == null:
			continue
		_expect(failures, "%s has an id" % path, not str(crop.get("crop_id")).is_empty())
		_expect(failures, "%s has produce" % path, crop.get("produce_item") != null)
		_expect(failures, "%s has seeds" % path, crop.get("seed_item") != null)
		_expect(failures, "%s exposes nine stages" % path, int(crop.call("get_visual_stage_count")) == 9)
	var wheat = load(CROP_PATHS[5])
	_expect(failures, "wheat requires a scythe", wheat != null and str(wheat.get("required_harvest_tool_tag")) == "tool.scythe")
	var tomato = load(CROP_PATHS[0])
	_expect(failures, "tomatoes are hand harvested", tomato != null and str(tomato.get("required_harvest_tool_tag")).is_empty())
	for path in TOOL_PATHS:
		var tool = load(path)
		_expect(failures, "%s loads" % path, tool != null)
		_expect(failures, "%s has %s" % [path, TOOL_PATHS[path]], tool != null and tool.call("has_tool_tag", TOOL_PATHS[path]))
	_expect(failures, "licensed crop source exists", ResourceLoader.exists("res://assets/vendor/luceed-studio/farm-crops-01/crops01.glb"))
	_finish(failures)


func _expect(failures: Array[String], label: String, condition: bool) -> void:
	if not condition:
		failures.append(label)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("FARMING_CONTENT_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FARMING_CONTENT_FAILED count=%d" % failures.size())
	quit(1)
