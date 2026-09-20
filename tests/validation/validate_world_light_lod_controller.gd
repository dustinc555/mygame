extends SceneTree

const CONTROLLER_SCRIPT := preload("res://features/world/projection/lighting/world_light_lod_controller.gd")

var _failures: Array[String] = []


class FakeRealizationController:
	extends Node

	var anchors: Array[Vector3] = [Vector3.ZERO]
	var radius := 10.0

	func get_realization_anchor_positions() -> Array[Vector3]:
		return anchors

	func get_visible_radius() -> float:
		return radius


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene_root := Node3D.new()
	root.add_child(scene_root)
	var realization := FakeRealizationController.new()
	scene_root.add_child(realization)
	var context := BootstrapContext.new(scene_root)
	context.register(&"population_realization", realization)
	var controller := CONTROLLER_SCRIPT.new()
	scene_root.add_child(controller)
	controller.initialize(context)

	var light := OmniLight3D.new()
	light.position = Vector3(8.0, 40.0, 0.0)
	light.distance_fade_enabled = true
	light.visible = false
	scene_root.add_child(light)
	controller.register_light(light)
	controller._process(0.0)
	_expect(not light.distance_fade_enabled, "A light inside flat LOD range should remain fully active regardless of camera height")
	_expect(not light.visible, "Light LOD must not override day/night visibility")

	realization.anchors = [Vector3(100.0, 0.0, 0.0)]
	controller._process(0.21)
	_expect(light.distance_fade_enabled, "A light outside LOD should restore its authored fade")

	realization.anchors = [Vector3(100.0, 0.0, 0.0), Vector3(8.0, 0.0, 0.0)]
	controller._process(0.21)
	_expect(not light.distance_fade_enabled, "Any supplied camera detail anchor should keep a nearby light fully active")

	controller.unregister_light(light)
	_expect(light.distance_fade_enabled, "Unregister restores authored fade")
	controller.register_light(light)
	controller._process(0.21)
	var freed_id := light.get_instance_id()
	light.free()
	controller._process(0.21)
	_expect(not controller._records.has(freed_id) and not controller._active_light_ids.has(freed_id), "Freed active light is removed safely from indexes")
	var boundary := OmniLight3D.new()
	boundary.distance_fade_enabled = true
	boundary.position = Vector3(realization.radius + WorldLightLodController.ACTIVATION_MARGIN, 40, 0)
	scene_root.add_child(boundary)
	realization.anchors = [Vector3.ZERO]
	controller.register_light(boundary)
	controller._process(0.21)
	_expect(not boundary.distance_fade_enabled, "Exact radius plus activation margin is included")
	realization.anchors = [Vector3(-0.01, 0, 0)]
	controller._process(0.21)
	_expect(boundary.distance_fade_enabled, "Outside activation margin restores fade")
	realization.anchors = [Vector3.ZERO]
	controller._process(0.21)
	controller.free()
	_expect(boundary.distance_fade_enabled, "Controller teardown restores remaining authored fades")
	scene_root.free()
	if _failures.is_empty():
		print("WORLD_LIGHT_LOD_CONTROLLER_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
