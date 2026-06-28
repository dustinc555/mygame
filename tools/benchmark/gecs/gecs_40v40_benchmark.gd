extends Node3D

class_name GecsFortyVsFortyBenchmark

const FACTION_HUMANOID_SCRIPT = preload("res://features/actors/projection/humanoid/faction_humanoid.gd")
const C_ACTOR = preload("res://tools/benchmark/gecs/components/c_benchmark_actor.gd")
const C_TRANSFORM = preload("res://tools/benchmark/gecs/components/c_benchmark_transform.gd")
const C_AGENT = preload("res://tools/benchmark/gecs/components/c_benchmark_agent.gd")
const C_VITALS = preload("res://tools/benchmark/gecs/components/c_benchmark_vitals.gd")
const TACTICAL_SYSTEM_SCRIPT = preload("res://tools/benchmark/gecs/systems/gecs_benchmark_tactical_system.gd")
const MOVEMENT_SYSTEM_SCRIPT = preload("res://tools/benchmark/gecs/systems/gecs_benchmark_movement_system.gd")

const FARMER_FACTION := "Farmers"
const RAIDER_FACTION := "Raiders"
const FARMER_TEAM := 0
const RAIDER_TEAM := 1
const BENCHMARK_Y := 0.6
const TOWN_CENTER_X := 10.0

@export_range(1, 400, 1) var farmer_count := 40
@export_range(1, 400, 1) var raider_count := 40
@export_range(0, 600, 1) var warmup_frames := 60
@export_range(1, 3600, 1) var sample_frames := 600
@export var auto_quit := true
@export var disable_humanoid_loops := true
@export var show_visual_context := true

var _world: World
var _tactical_system: GecsBenchmarkTacticalSystem
var _movement_system: GecsBenchmarkMovementSystem
var _running := false
var _frame_index := 0
var _sample_count := 0
var _sample_delta_sum := 0.0
var _sample_frame_cpu_usec := 0
var _sample_ecs_usec := 0
var _sample_query_usec := 0
var _max_delta := 0.0
var _entity_count := 0
var _live_actor_count := 0
var _last_alive_count := 0


func _ready() -> void:
	set_process(false)
	call_deferred("_start")


func _start() -> void:
	_parse_cli_overrides()
	if show_visual_context:
		_build_visual_context()
	_setup_ecs_world()
	if _world == null:
		return
	_spawn_population(FARMER_FACTION, FARMER_TEAM, farmer_count, Vector3(-TOWN_CENTER_X, BENCHMARK_Y, 0.0), Color(0.46, 0.72, 0.34, 1.0), RAIDER_FACTION, "Farmer")
	_spawn_population(RAIDER_FACTION, RAIDER_TEAM, raider_count, Vector3(TOWN_CENTER_X, BENCHMARK_Y, 0.0), Color(0.82, 0.22, 0.16, 1.0), FARMER_FACTION, "Raider")
	_entity_count = farmer_count + raider_count
	_last_alive_count = _entity_count
	_running = true
	set_process(true)
	print("BENCHMARK_40V40_GECS_START farmers=%d raiders=%d entities=%d warmup_frames=%d sample_frames=%d" % [farmer_count, raider_count, _entity_count, warmup_frames, sample_frames])


func _process(delta: float) -> void:
	if not _running:
		return
	var frame_start_usec := Time.get_ticks_usec()
	var ecs_start_usec := Time.get_ticks_usec()
	_world.process(delta)
	var ecs_usec := Time.get_ticks_usec() - ecs_start_usec
	var query_start_usec := Time.get_ticks_usec()
	var matched_entities: Array = _world.query.with_all([C_AGENT, C_VITALS]).execute()
	var query_usec := Time.get_ticks_usec() - query_start_usec
	var frame_cpu_usec := Time.get_ticks_usec() - frame_start_usec
	if _frame_index >= warmup_frames:
		_sample_count += 1
		_sample_delta_sum += delta
		_sample_frame_cpu_usec += frame_cpu_usec
		_sample_ecs_usec += ecs_usec
		_sample_query_usec += query_usec
		_max_delta = maxf(_max_delta, delta)
		_last_alive_count = _count_alive(matched_entities)
	_frame_index += 1
	if _sample_count >= sample_frames:
		_finish()


func _setup_ecs_world() -> void:
	var ecs_node := get_node_or_null("/root/ECS")
	if ecs_node == null:
		push_error("GECS benchmark requires the /root/ECS autoload. Enable the GECS plugin/autoload before running.")
		if auto_quit:
			get_tree().quit(1)
		return
	_world = World.new()
	_world.name = "GecsBenchmarkWorld"
	add_child(_world)
	_tactical_system = TACTICAL_SYSTEM_SCRIPT.new() as GecsBenchmarkTacticalSystem
	_tactical_system.name = "BenchmarkTacticalSystem"
	_movement_system = MOVEMENT_SYSTEM_SCRIPT.new() as GecsBenchmarkMovementSystem
	_movement_system.name = "BenchmarkMovementSystem"
	_world.add_system(_tactical_system)
	_world.add_system(_movement_system)
	ecs_node.set("world", _world)
	_world.finalize_system_setup()


func _spawn_population(faction_id: String, team: int, count: int, center: Vector3, base_color: Color, hostile_faction_id: String, label: String) -> void:
	var actors_root := _ensure_node3d("BenchmarkActors", self)
	var team_root := _ensure_node3d("%sActors" % label, actors_root)
	for index in range(count):
		var display_name := "%s %02d" % [label, index + 1]
		var stable_id := "benchmark.%s.%02d" % [label.to_lower(), index + 1]
		var actor := _create_actor("%s%02d" % [label, index + 1], display_name, stable_id, faction_id, hostile_faction_id, base_color)
		team_root.add_child(actor)
		actor.global_position = _spawn_position(center, index, count)
		if disable_humanoid_loops:
			_disable_actor_builtin_loops(actor)
		var entity := Entity.new()
		entity.name = "%sEntity%02d" % [label, index + 1]
		entity.id = stable_id
		var actor_component := C_ACTOR.new() as CBenchmarkActor
		actor_component.actor_path = actor.get_path()
		actor_component.stable_id = stable_id
		actor_component.display_name = display_name
		var transform_component := C_TRANSFORM.new() as CBenchmarkTransform
		transform_component.position = actor.global_position
		transform_component.facing = Vector3.RIGHT if team == FARMER_TEAM else Vector3.LEFT
		var agent_component := C_AGENT.new() as CBenchmarkAgent
		agent_component.faction_id = faction_id
		agent_component.team = team
		agent_component.speed = 3.4 if team == RAIDER_TEAM else 3.05
		agent_component.attack_range = 1.45
		agent_component.attack_cooldown_seconds = 1.05 if team == RAIDER_TEAM else 1.2
		agent_component.target_position = _initial_target_position(team, index)
		agent_component.retarget_remaining = float(index % 17) * 0.02
		var vitals_component := C_VITALS.new() as CBenchmarkVitals
		vitals_component.max_hp = 100.0
		vitals_component.hp = 100.0
		_world.add_entity(entity, [actor_component, transform_component, agent_component, vitals_component])
		_live_actor_count += 1


func _create_actor(node_name: String, display_name: String, stable_id: String, faction_id: String, hostile_faction_id: String, base_color: Color) -> Node3D:
	var actor := CharacterBody3D.new()
	actor.name = node_name
	actor.set_script(FACTION_HUMANOID_SCRIPT)
	actor.set("member_name", display_name)
	actor.set("stable_id", stable_id)
	actor.set("faction_name", faction_id)
	actor.set("squad_name", "%sBenchmark" % faction_id)
	actor.set("hostile_factions", PackedStringArray([hostile_faction_id]))
	actor.set("base_color", base_color)
	actor.set("show_nameplate", false)
	actor.set("visual_body_type", 1)
	actor.set("hunger_enabled", false)
	actor.set("fatigue_enabled", false)
	actor.set("auto_heal_enabled", false)
	actor.set("use_navigation_pathing", false)
	actor.set("navigation_avoidance_enabled", false)
	actor.set("starting_items", [])
	actor.set("starting_equipment", [])
	_add_basic_humanoid_children(actor, base_color)
	return actor


func _add_basic_humanoid_children(actor: Node, base_color: Color) -> void:
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.transform = Transform3D(Basis(), Vector3(0.0, 0.95, 0.0))
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = 0.45
	capsule_shape.height = 1.1
	collision.shape = capsule_shape
	actor.add_child(collision)

	var body := MeshInstance3D.new()
	body.name = "BodyMesh"
	body.transform = Transform3D(Basis(), Vector3(0.0, 0.95, 0.0))
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = 0.45
	body.mesh = capsule_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = base_color
	material.roughness = 0.9
	body.material_override = material
	actor.add_child(body)


func _disable_actor_builtin_loops(actor: Node) -> void:
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.set_process(false)
	actor.set_physics_process(false)


func _spawn_position(center: Vector3, index: int, count: int) -> Vector3:
	var columns := 8
	var rows := int(ceil(float(count) / float(columns)))
	var row := index / columns
	var column := index % columns
	var x_offset := (float(column) - float(columns - 1) * 0.5) * 1.55
	var z_offset := (float(row) - float(rows - 1) * 0.5) * 1.55
	return center + Vector3(x_offset, 0.0, z_offset)


func _initial_target_position(team: int, index: int) -> Vector3:
	var opposing_center := Vector3(TOWN_CENTER_X, BENCHMARK_Y, 0.0) if team == FARMER_TEAM else Vector3(-TOWN_CENTER_X, BENCHMARK_Y, 0.0)
	var spread := Vector3(0.0, 0.0, (float(index % 9) - 4.0) * 0.8)
	return opposing_center + spread


func _build_visual_context() -> void:
	var light := DirectionalLight3D.new()
	light.name = "BenchmarkSun"
	light.rotation_degrees = Vector3(-52.0, 35.0, 0.0)
	light.light_energy = 1.5
	add_child(light)

	var camera := Camera3D.new()
	camera.name = "BenchmarkCamera"
	camera.position = Vector3(0.0, 34.0, 30.0)
	camera.rotation_degrees = Vector3(-47.0, 0.0, 0.0)
	camera.current = true
	add_child(camera)

	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "BenchmarkFloor"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(64.0, 0.1, 32.0)
	floor_mesh.mesh = mesh
	floor_mesh.position = Vector3(0.0, -0.05, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.24, 0.22, 0.18, 1.0)
	material.roughness = 0.95
	floor_mesh.material_override = material
	add_child(floor_mesh)


func _finish() -> void:
	_running = false
	set_process(false)
	var safe_samples: int = maxi(1, _sample_count)
	var avg_fps: float = float(safe_samples) / maxf(_sample_delta_sum, 0.0001)
	var min_fps: float = 1.0 / maxf(_max_delta, 0.0001)
	var avg_delta_ms: float = (_sample_delta_sum / float(safe_samples)) * 1000.0
	var avg_frame_cpu_ms: float = float(_sample_frame_cpu_usec) / float(safe_samples) / 1000.0
	var avg_ecs_ms: float = float(_sample_ecs_usec) / float(safe_samples) / 1000.0
	var avg_query_ms: float = float(_sample_query_usec) / float(safe_samples) / 1000.0
	var node_count: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var resource_count: int = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	var memory_static_kb: int = int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1024.0)
	var engagements: int = _tactical_system.total_engagements if _tactical_system != null else 0
	var target_updates: int = _tactical_system.total_target_updates if _tactical_system != null else 0
	var distance_moved: float = _movement_system.total_distance_moved if _movement_system != null else 0.0
	print("BENCHMARK_40V40_GECS_RESULT mode=gecs farmers=%d raiders=%d live_actors=%d entities=%d alive=%d frames=%d avg_fps=%.2f min_fps=%.2f avg_frame_delta_ms=%.3f avg_benchmark_cpu_ms=%.3f avg_ecs_ms=%.3f avg_query_ms=%.3f engagements=%d target_updates=%d distance_moved=%.2f node_count=%d scene_nodes=%d resource_count=%d memory_static_kb=%d" % [farmer_count, raider_count, _live_actor_count, _entity_count, _last_alive_count, _sample_count, avg_fps, min_fps, avg_delta_ms, avg_frame_cpu_ms, avg_ecs_ms, avg_query_ms, engagements, target_updates, distance_moved, node_count, _count_scene_nodes(get_tree().root), resource_count, memory_static_kb])
	if auto_quit:
		get_tree().quit(0)


func _count_alive(entities: Array) -> int:
	var alive := 0
	for entity in entities:
		var vitals := entity.get_component(C_VITALS) as CBenchmarkVitals
		if vitals != null and vitals.hp > 0.0:
			alive += 1
	return alive


func _count_scene_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _count_scene_nodes(child)
	return count


func _ensure_node3d(node_name: String, parent: Node) -> Node3D:
	var existing := parent.get_node_or_null(node_name) as Node3D
	if existing != null:
		return existing
	var node := Node3D.new()
	node.name = node_name
	parent.add_child(node)
	return node


func _parse_cli_overrides() -> void:
	for arg_value in OS.get_cmdline_args():
		var arg := str(arg_value)
		if arg.begins_with("--benchmark-frames="):
			sample_frames = max(1, int(arg.get_slice("=", 1)))
		elif arg.begins_with("--benchmark-warmup="):
			warmup_frames = max(0, int(arg.get_slice("=", 1)))
		elif arg == "--benchmark-no-quit":
			auto_quit = false
