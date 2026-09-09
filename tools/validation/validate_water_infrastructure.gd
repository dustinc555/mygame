extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_water_infrastructure.gd

const WELL_SCENE_PATH := "res://features/settlements/bridge/settlement_well_1.tscn"
const WELL_FACILITY_PATH := "res://features/settlements/resources/facilities/well_1.tres"
const TANK_SCENE_PATH := "res://features/world/projection/props/furniture/tank.tscn"
const TANK_FACILITY_SCENE_PATH := "res://features/settlements/bridge/settlement_tank.tscn"
const TANK_FACILITY_PATH := "res://features/settlements/resources/facilities/tank.tres"
const WELL_MODEL_PATH := "res://assets/world/props/water/well_1/well_1.glb"
const TANK_MODEL_PATH := "res://assets/world/props/water/tank/tank.glb"
const FACILITY_TOOLS_PATH := "res://addons/world_authoring/facility_tools.gd"
const FACILITY_DOCK_PATH := "res://addons/world_authoring/facility_dock.gd"

var failures: Array[String] = []
var _ecs_placeholder: Node


func _initialize() -> void:
	if not Engine.has_singleton("ECS"):
		_ecs_placeholder = Node.new()
		Engine.register_singleton("ECS", _ecs_placeholder)
	call_deferred("_run")


func _run() -> void:
	var tools_source := FileAccess.get_file_as_string(FACILITY_TOOLS_PATH)
	var dock_source := FileAccess.get_file_as_string(FACILITY_DOCK_PATH)
	_expect(tools_source.contains("node is LiquidContainer") and tools_source.contains("func set_liquid_container_assignment"), "Facility authoring recognizes Tanks and exposes a guarded liquid-assignment action")
	_expect(dock_source.contains("assigned_liquid_id") and dock_source.contains("Liquid Type") and dock_source.contains("Unassigned"), "Facility container UI can assign a Tank's liquid type")
	_expect(ResourceLoader.exists(WELL_MODEL_PATH), "Well 1 model is imported under its canonical name")
	_expect(ResourceLoader.exists(TANK_MODEL_PATH), "Tank model is imported")
	_expect(ResourceLoader.exists(WELL_SCENE_PATH), "Well 1 facility scene exists")
	_expect(ResourceLoader.exists(WELL_FACILITY_PATH), "Well 1 facility definition exists")
	_expect(ResourceLoader.exists(TANK_SCENE_PATH), "Tank furniture scene exists")
	_expect(ResourceLoader.exists(TANK_FACILITY_SCENE_PATH), "standalone Tank facility scene exists")
	_expect(ResourceLoader.exists(TANK_FACILITY_PATH), "standalone Tank facility definition exists")
	_expect(not _furnishing_rules_include_tank(), "Tank is never included in automatic FacilityFurnisher rules")
	var facility_tools := (load(FACILITY_TOOLS_PATH) as Script).new(null) as RefCounted
	var tank_in_furniture_catalog := false
	for entry_value in facility_tools.call("get_furniture_catalog"):
		var entry := entry_value as Dictionary
		if str(entry.get("path", "")) == TANK_SCENE_PATH:
			tank_in_furniture_catalog = true
			break
	_expect(tank_in_furniture_catalog, "Tank appears in the building Furniture browser for indoor liquid storage")
	facility_tools.call("teardown")
	if ResourceLoader.exists(WELL_SCENE_PATH):
		var well := (load(WELL_SCENE_PATH) as PackedScene).instantiate()
		root.add_child(well)
		await process_frame
		_expect(str(well.get("display_name")) == "Well 1", "well player-facing name is Well 1")
		var source: Node = _find_water_source(well)
		_expect(source != null, "Well 1 owns a durable water source")
		if source != null:
			_expect(source.is_in_group("farm_water_source"), "Well 1 registers as a live water source")
			_expect(str(source.get("source_kind")) == "well", "Well 1 is classified as a well")
			_expect(not bool(source.get("renewable")), "Well 1 uses a finite draw buffer")
			_expect(float(source.get("recharge_per_world_hour")) > 0.0, "Well 1 recharges from authored groundwater yield")
			_expect(source.has_method("get_interaction_position"), "haulers can approach Well 1")
		_expect(_has_collision_shape(well), "Well 1 has runtime collision")
		well.queue_free()
		await process_frame
	if ResourceLoader.exists(TANK_SCENE_PATH):
		var tank := (load(TANK_SCENE_PATH) as PackedScene).instantiate()
		root.add_child(tank)
		await process_frame
		_expect(str(tank.get("display_name")) == "Tank", "tank player-facing name is generic Tank")
		_expect(tank.is_in_group("furniture"), "Tank participates in the shared furniture contract")
		_expect(int(tank.get("furniture_type")) == FurnitureRules.Type.CONTAINER, "Tank uses the shared container furniture category")
		_expect(tank.is_in_group("liquid_container"), "Tank registers as a generic liquid container")
		_expect(not tank.is_in_group("farm_water_source"), "Tank is not a farming water-source subclass")
		_expect(str(tank.get("assigned_liquid_id")) == "", "Tank starts empty and unassigned")
		_expect(tank.has_method("assign_liquid"), "Tank exposes liquid assignment")
		_expect(tank.has_method("deposit_liquid_for_actor"), "Tank accepts exact actor-carried liquid deposits")
		_expect(tank.find_children("*", "Label3D", true, false).is_empty(), "water infrastructure has no world-space metrics")
		_expect(_has_collision_shape(tank), "Tank has runtime collision")
		_expect(_uses_current_glb_textures(tank), "Tank uses textures embedded in its current GLB instead of stale extracted textures")
		tank.queue_free()
		await process_frame
	if ResourceLoader.exists(TANK_FACILITY_SCENE_PATH):
		var facility := (load(TANK_FACILITY_SCENE_PATH) as PackedScene).instantiate()
		root.add_child(facility)
		await process_frame
		_expect(str(facility.get("display_name")) == "Tank", "standalone Tank uses the generic player-facing name")
		var function_resource := facility.get("facility_function") as Resource
		_expect(function_resource != null and str(function_resource.get("function_id")) == "tank", "standalone Tank carries its Tank facility function")
		_expect(_find_liquid_container(facility) != null, "standalone Tank facility wraps the same liquid-container implementation")
		facility.queue_free()
		await process_frame
	_finish()


func _find_water_source(node: Node) -> Node:
	if node != null and node.get_script() != null and node.get_script().get_global_name() == "FarmWaterSource":
		return node
	for child in node.get_children(true) if node != null else []:
		var found = _find_water_source(child)
		if found != null:
			return found
	return null


func _find_liquid_container(node: Node) -> Node:
	if node != null and node.is_in_group("liquid_container"):
		return node
	for child in node.get_children(true) if node != null else []:
		var found = _find_liquid_container(child)
		if found != null:
			return found
	return null


func _has_collision_shape(node: Node) -> bool:
	for candidate in node.find_children("*", "CollisionShape3D", true, false):
		if candidate is CollisionShape3D and (candidate as CollisionShape3D).shape != null:
			return true
	return false


func _uses_current_glb_textures(node: Node) -> bool:
	for candidate in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := candidate as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		for surface_index in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface_index) as BaseMaterial3D
			if material == null or material.albedo_texture == null:
				continue
			return material.albedo_texture.resource_path.begins_with(TANK_MODEL_PATH + "::")
	return false


func _furnishing_rules_include_tank() -> bool:
	var directory := DirAccess.open("res://features/settlements/resources/furnishing")
	if directory == null:
		return false
	for file_name in directory.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var rules := load("res://features/settlements/resources/furnishing/%s" % file_name) as FurnishRules
		if rules == null:
			continue
		for property_name in [
			"counter_scenes", "required_cluster_scenes", "cluster_scenes", "shelf_scenes",
			"light_scenes", "utility_scenes", "container_scenes", "bed_scenes", "pallet_scenes",
		]:
			for scene_value in rules.get(property_name) as Array:
				var scene := scene_value as PackedScene
				if scene != null and scene.resource_path == TANK_SCENE_PATH:
					return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if _ecs_placeholder != null:
		Engine.unregister_singleton("ECS")
		_ecs_placeholder.free()
	if failures.is_empty():
		print("WATER_INFRASTRUCTURE_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("WATER_INFRASTRUCTURE_FAILED count=%d" % failures.size())
	quit(1)
