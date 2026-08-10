extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_farming_visual_assets.gd

const HOE_ICON_PATH := "res://assets/items/farming/hoe.svg"
const CISTERN_SCENE_PATH := "res://features/farming/projection/farm_water_cistern.tscn"
const FARMING_TEST_PATH := "res://scenes/test_levels/farming_test.tscn"
const WATERING_CAN_SCENE_PATH := "res://features/world/projection/equipment/watering_can_model.tscn"

var failures: Array[String] = []


func _initialize() -> void:
	var file := FileAccess.open(HOE_ICON_PATH, FileAccess.READ)
	_expect(file != null, "hoe icon exists")
	if file != null:
		var svg := file.get_as_text()
		_expect(not svg.contains("<circle"), "hoe icon does not use a fruit-like circle")
		_expect(not svg.contains("<text"), "hoe icon uses a visual silhouette instead of a text label")
		_expect(svg.contains("Hoe tool silhouette"), "hoe icon identifies its recognizable silhouette")
	_expect(ResourceLoader.exists(CISTERN_SCENE_PATH), "authored farming water cistern scene exists")
	if ResourceLoader.exists(CISTERN_SCENE_PATH):
		var cistern_source := FileAccess.get_file_as_string(CISTERN_SCENE_PATH)
		_expect(cistern_source.contains("Barrel_Holder.gltf"), "water cistern uses the authored barrel-holder asset")
		_expect(cistern_source.contains("Bucket_Wooden_1.gltf"), "water cistern includes an authored wooden bucket")
	var test_source := FileAccess.get_file_as_string(FARMING_TEST_PATH)
	_expect(test_source.contains("farm_water_cistern.tscn"), "farming test instances the authored water cistern")
	_expect(not test_source.contains("mesh = SubResource(\"WaterMesh\")"), "farming test has no primitive water-source mesh")
	var can_source := FileAccess.get_file_as_string(WATERING_CAN_SCENE_PATH)
	_expect(can_source.contains("type=\"TorusMesh\" id=\"Handle\""), "watering can has a visible handle")
	_expect(can_source.contains("position = Vector3(0, 0.46, 0)"), "watering-can grip point sits on top of its handle")
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FARMING_VISUAL_ASSETS_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FARMING_VISUAL_ASSETS_FAILED count=%d" % failures.size())
	quit(1)
