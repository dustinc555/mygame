extends Node

class_name WorldSquadController

const FACTION_HUMANOID_SCRIPT = preload("res://scripts/characters/faction_humanoid.gd")

var root_scene: Node
var settlement_controller: Node
var road_controller: Node
var active_squads: Dictionary = {}
var _squad_index := 0
var _check_remaining := 0.0
var _initialized := false


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	_try_initialize()


func _ready() -> void:
	add_to_group("world_squad_controller")
	_try_initialize()


func _process(delta: float) -> void:
	if not _initialized:
		return
	_check_remaining -= delta
	if _check_remaining > 0.0:
		return
	_check_remaining = 0.5
	_process_active_squads()


func start_action(action_record: Dictionary) -> Dictionary:
	if settlement_controller == null:
		return {}
	var source_id := str(action_record.get("source_settlement_id", ""))
	var target_id := str(action_record.get("target_settlement_id", ""))
	var template: Resource = settlement_controller.call("get_raid_squad_template", source_id) as Resource
	if template == null:
		return {}
	_squad_index += 1
	var squad_id := "squad_%04d" % _squad_index
	var source_anchor: Node3D = settlement_controller.call("get_settlement_anchor", source_id) as Node3D
	var target_anchor: Node3D = settlement_controller.call("get_settlement_anchor", target_id) as Node3D
	var spawn_position: Vector3 = source_anchor.call("get_spawn_position", "raid") if source_anchor != null and source_anchor.has_method("get_spawn_position") else Vector3.ZERO
	var target_position: Vector3 = target_anchor.call("get_spawn_position", "defense") if target_anchor != null and target_anchor.has_method("get_spawn_position") else spawn_position
	var route_waypoints := _get_route_waypoints(source_id, target_id)
	var actors := _spawn_squad_members(squad_id, template, spawn_position, target_position, route_waypoints)
	var squad_state := {
		"squad_id": squad_id,
		"action": action_record.duplicate(true),
		"source_settlement_id": source_id,
		"target_settlement_id": target_id,
		"template_id": _resource_id(template),
		"cargo_capacity": _resource_float(template, "food_capacity", 0.0),
		"alarm_raised": false,
		"combat_engaged": false,
		"resolved": false,
		"route_waypoints": route_waypoints,
		"route_index": 0,
		"actor_paths": _actor_paths(actors),
	}
	active_squads[squad_id] = squad_state
	return squad_state.duplicate(true)


func serialize_state() -> Dictionary:
	return active_squads.duplicate(true)


func _try_initialize() -> void:
	if _initialized or root_scene == null or not is_inside_tree():
		return
	settlement_controller = get_parent().get_node_or_null("SettlementController")
	road_controller = get_parent().get_node_or_null("RoadController")
	if settlement_controller == null:
		return
	_initialized = true


func _spawn_squad_members(squad_id: String, template: Resource, spawn_position: Vector3, target_position: Vector3, route_waypoints: Array[Vector3]) -> Array:
	var actors: Array = []
	var actor_root := _ensure_actor_root()
	var count: int = max(1, _resource_int(template, "member_count", 1))
	var initial_target := target_position if route_waypoints.is_empty() else route_waypoints[0]
	var hostile_factions = template.get("hostile_faction_ids")
	var faction_id: String = _resource_faction_id(template)
	for index in range(count):
		var actor := CharacterBody3D.new()
		actor.name = "%s_%02d" % [squad_id, index + 1]
		actor.set_script(FACTION_HUMANOID_SCRIPT)
		actor.set("member_name", "%s %d" % [_resource_string(template, "member_name_prefix", "Squad Member"), index + 1])
		actor.set("stable_id", "world_squad.%s.%d" % [squad_id, index + 1])
		actor.set("faction_name", faction_id)
		actor.set("squad_name", squad_id)
		actor.set("hostile_factions", hostile_factions)
		actor.set("combat_stance", _resource_int(template, "combat_stance", NpcRules.CombatStance.DEFENSIVE))
		actor.set("base_color", _resource_color(template, "base_color", Color(0.62, 0.62, 0.62, 1.0)))
		actor.set("max_hp", _resource_float(template, "max_hp", 100.0))
		actor.set("base_attack_damage", _resource_float(template, "base_attack_damage", 18.0))
		actor.set("starting_equipment", template.get("starting_equipment"))
		var offset := _formation_offset(index, count)
		actor.position = spawn_position + offset
		_add_basic_humanoid_children(actor)
		actor_root.add_child(actor)
		actors.append(actor)
		if actor.has_method("set_move_target"):
			actor.call("set_move_target", initial_target + offset, false)
	return actors


func _add_basic_humanoid_children(actor: Node) -> void:
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
	actor.add_child(body)


func _formation_offset(index: int, count: int) -> Vector3:
	var columns := ceili(sqrt(float(count)))
	var row := index / columns
	var column := index % columns
	return Vector3((float(column) - float(columns - 1) * 0.5) * 1.35, 0.6, float(row) * 1.35)


func _assign_targets(actors: Array, target_anchor: Node) -> void:
	if target_anchor == null:
		return
	var residents: Array = target_anchor.call("get_resident_characters") if target_anchor.has_method("get_resident_characters") else []
	if residents.is_empty():
		return
	for index in range(actors.size()):
		var actor = actors[index]
		var target = residents[index % residents.size()]
		if actor != null and target != null and actor.has_method("assign_attack_target"):
			actor.call("assign_attack_target", target, false)


func _process_active_squads() -> void:
	for squad_id in active_squads.keys():
		var squad_state: Dictionary = active_squads[squad_id]
		if bool(squad_state.get("resolved", false)):
			continue
		var target_id := str(squad_state.get("target_settlement_id", ""))
		var target_anchor: Node3D = settlement_controller.call("get_settlement_anchor", target_id) as Node3D
		if target_anchor == null:
			continue
		var target_position: Vector3 = target_anchor.call("get_spawn_position", "defense") if target_anchor.has_method("get_spawn_position") else target_anchor.global_position
		if not bool(squad_state.get("alarm_raised", false)) and _has_actor_reached_town_alarm_range(squad_state, target_anchor):
			_raise_settlement_alarm(squad_state, target_anchor)
			squad_state["alarm_raised"] = true
			active_squads[squad_id] = squad_state
		if _advance_squad_route(squad_state, target_position):
			active_squads[squad_id] = squad_state
			continue
		if not _has_actor_reached_position(squad_state, target_position, 7.5):
			continue
		if not bool(squad_state.get("combat_engaged", false)):
			_assign_targets(_actors_from_paths(squad_state), target_anchor)
			squad_state["combat_engaged"] = true
		var source_id := str(squad_state.get("source_settlement_id", ""))
		var stolen: float = float(settlement_controller.call("resolve_food_transfer", source_id, target_id, float(squad_state.get("cargo_capacity", 0.0)), "visible_food_raid"))
		squad_state["resolved"] = true
		squad_state["resolved_food"] = stolen
		active_squads[squad_id] = squad_state


func _advance_squad_route(squad_state: Dictionary, target_position: Vector3) -> bool:
	var route_waypoints := _route_waypoints_from_state(squad_state)
	if route_waypoints.is_empty():
		return false
	var route_index := int(squad_state.get("route_index", 0))
	if route_index >= route_waypoints.size():
		return false
	if not _has_actor_reached_position(squad_state, route_waypoints[route_index], 3.0):
		return true
	route_index += 1
	squad_state["route_index"] = route_index
	var next_target := target_position if route_index >= route_waypoints.size() else route_waypoints[route_index]
	_assign_squad_move_targets(squad_state, next_target)
	return route_index < route_waypoints.size()


func _assign_squad_move_targets(squad_state: Dictionary, target_position: Vector3) -> void:
	var actors := _actors_from_paths(squad_state)
	var count := actors.size()
	for index in range(count):
		var actor = actors[index]
		if actor != null and actor.has_method("set_move_target"):
			actor.call("set_move_target", target_position + _formation_offset(index, count), false)


func _has_actor_reached_position(squad_state: Dictionary, target_position: Vector3, arrival_distance: float) -> bool:
	for path in squad_state.get("actor_paths", []):
		var actor := get_node_or_null(path)
		if actor is Node3D and int(actor.get("life_state")) == NpcRules.LifeState.ALIVE:
			if actor.global_position.distance_to(target_position) <= arrival_distance:
				return true
	return false


func _has_actor_reached_town_alarm_range(squad_state: Dictionary, target_anchor: Node3D) -> bool:
	if target_anchor == null:
		return false
	var border_radius := 0.0
	var border_radius_value = target_anchor.get("town_border_radius")
	if border_radius_value != null:
		border_radius = maxf(float(border_radius_value), 0.0)
	var alarm_radius := border_radius + NpcRules.RAID_ALARM_APPROACH_RANGE
	for actor in _actors_from_paths(squad_state):
		if not (actor is Node3D) or int(actor.get("life_state")) != NpcRules.LifeState.ALIVE:
			continue
		if target_anchor.has_method("contains_town_border_position") and bool(target_anchor.call("contains_town_border_position", actor.global_position)):
			return true
		var center := Vector2(target_anchor.global_position.x, target_anchor.global_position.z)
		var position := Vector2(actor.global_position.x, actor.global_position.z)
		if center.distance_to(position) <= alarm_radius:
			return true
	return false


func _raise_settlement_alarm(squad_state: Dictionary, target_anchor: Node3D) -> void:
	var attacker = _first_alive_actor(squad_state)
	if attacker == null:
		return
	for node in get_tree().get_nodes_in_group("npc_character"):
		if node == attacker or not node.has_method("respond_to_settlement_alarm"):
			continue
		node.call("respond_to_settlement_alarm", attacker, target_anchor, null)


func _first_alive_actor(squad_state: Dictionary):
	for actor in _actors_from_paths(squad_state):
		if actor is Node3D and int(actor.get("life_state")) == NpcRules.LifeState.ALIVE:
			return actor
	return null


func _route_waypoints_from_state(squad_state: Dictionary) -> Array[Vector3]:
	var route_waypoints: Array[Vector3] = []
	for waypoint in squad_state.get("route_waypoints", []):
		if waypoint is Vector3:
			route_waypoints.append(waypoint)
	return route_waypoints


func _get_route_waypoints(source_settlement_id: String, target_settlement_id: String) -> Array[Vector3]:
	var route_waypoints: Array[Vector3] = []
	if road_controller == null or not road_controller.has_method("get_route_waypoints"):
		return route_waypoints
	for waypoint in road_controller.call("get_route_waypoints", source_settlement_id, target_settlement_id):
		if waypoint is Vector3:
			route_waypoints.append(waypoint)
	return route_waypoints


func _actor_paths(actors: Array) -> Array[NodePath]:
	var paths: Array[NodePath] = []
	for actor in actors:
		if actor != null:
			paths.append(get_path_to(actor))
	return paths


func _actors_from_paths(squad_state: Dictionary) -> Array:
	var actors: Array = []
	for path in squad_state.get("actor_paths", []):
		var actor := get_node_or_null(path)
		if actor != null:
			actors.append(actor)
	return actors


func _ensure_actor_root() -> Node3D:
	var actor_root := root_scene.get_node_or_null("WorldSquads") as Node3D
	if actor_root != null:
		return actor_root
	actor_root = Node3D.new()
	actor_root.name = "WorldSquads"
	root_scene.add_child(actor_root)
	return actor_root


func _resource_id(resource: Resource) -> String:
	if resource != null and resource.has_method("get_id"):
		return str(resource.call("get_id"))
	return ""


func _resource_faction_id(resource: Resource) -> String:
	if resource != null and resource.has_method("get_faction_id"):
		return str(resource.call("get_faction_id"))
	return _resource_id(resource.get("faction_definition") as Resource) if resource != null else ""


func _resource_string(resource: Resource, property_name: String, fallback: String) -> String:
	if resource == null:
		return fallback
	var value = resource.get(property_name)
	return fallback if value == null else str(value)


func _resource_int(resource: Resource, property_name: String, fallback: int) -> int:
	if resource == null:
		return fallback
	var value = resource.get(property_name)
	return fallback if value == null else int(value)


func _resource_float(resource: Resource, property_name: String, fallback: float) -> float:
	if resource == null:
		return fallback
	var value = resource.get(property_name)
	return fallback if value == null else float(value)


func _resource_color(resource: Resource, property_name: String, fallback: Color) -> Color:
	if resource == null:
		return fallback
	var value = resource.get(property_name)
	return value if value is Color else fallback
