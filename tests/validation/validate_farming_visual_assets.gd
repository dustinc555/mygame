extends "res://tests/validation/test_case.gd"
## Run: godot --headless --path . --script res://tests/validation/validate_farming_visual_assets.gd

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
		var icon := load(HOE_ICON_PATH) as Texture2D
		_expect(icon != null and icon.get_width() > 0 and icon.get_height() > 0, "hoe SVG actually loads as a nonempty icon texture; recognizability needs visual review")
	_expect(ResourceLoader.exists(CISTERN_SCENE_PATH), "authored farming water cistern scene exists")
	if ResourceLoader.exists(CISTERN_SCENE_PATH):
		var cistern_source := FileAccess.get_file_as_string(CISTERN_SCENE_PATH)
		_expect(cistern_source.contains("Barrel_Holder.gltf"), "water cistern uses the authored barrel-holder asset")
		_expect(not cistern_source.contains("Bucket_Wooden_1.gltf"), "water barrels contain no decorative fake bucket")
	var test_source := FileAccess.get_file_as_string(FARMING_TEST_PATH)
	_expect(test_source.contains("farm_water_cistern.tscn"), "farming test instances the authored water cistern")
	_expect(not test_source.contains("mesh = SubResource(\"WaterMesh\")"), "farming test has no primitive water-source mesh")
	var can_source := FileAccess.get_file_as_string(WATERING_CAN_SCENE_PATH)
	_expect(can_source.contains("watering_can.glb"), "watering can uses the authored medieval model")
	_expect(can_source.contains("[node name=\"GripPoint_Primary\" type=\"Marker3D\""), "watering can keeps its authored primary grip marker")
	var can := (load(WATERING_CAN_SCENE_PATH) as PackedScene).instantiate()
	_expect(can.get_node_or_null("GripPoint_Primary") is Marker3D and can.get_node("GripPoint_Primary").transform.is_finite(), "loaded can exposes a finite primary grip transform")
	_expect(_mesh_surface_count(can) > 0, "authored watering can contains real mesh surfaces")
	can.free()
	var cistern := (load(CISTERN_SCENE_PATH) as PackedScene).instantiate()
	_expect(_mesh_surface_count(cistern) > 0 and cistern.get_node_or_null("AuthoredBarrelHolder") != null, "authored cistern instantiates barrel geometry")
	_expect(cistern.get_node("CollisionShape3D").shape != null and cistern.has_method("get_world_context_actions") and cistern.has_method("get_interaction_position"), "cistern keeps physical shape and actor interaction surface")
	cistern.free()
	_finish()


func _mesh_surface_count(node: Node) -> int:
	var count := 0
	for child in node.find_children("*", "MeshInstance3D", true, false):
		if child.mesh != null: count += child.mesh.get_surface_count()
	return count

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
