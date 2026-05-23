extends Node

class_name WorldSquadController

const FACTION_HUMANOID_SCRIPT = preload("res://scripts/characters/faction_humanoid.gd")
const PHASE_TRAVEL := "travel"
const PHASE_PLANNING := "planning"
const PHASE_BATTLE := "battle"
const PHASE_RESOLVED := "resolved"

var root_scene: Node
var settlement_controller: Node
var road_controller: Node
var world_event_choice_controller: Node
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
	var operation_profile: Resource = template.get("operation_profile") as Resource
	var encamp_position := _get_encamp_position(spawn_position, target_anchor, route_waypoints, operation_profile)
	var travel_waypoints := _get_safe_travel_waypoints(route_waypoints, target_anchor, encamp_position)
	var actors := _spawn_squad_members(squad_id, template, spawn_position, encamp_position, travel_waypoints)
	var squad_state := {
		"squad_id": squad_id,
		"action": action_record.duplicate(true),
		"source_settlement_id": source_id,
		"target_settlement_id": target_id,
		"template_id": _resource_id(template),
		"template_resource": template,
		"operation_profile": operation_profile,
		"phase_id": _operation_start_phase_id(operation_profile),
		"phase_elapsed": 0.0,
		"phase_entered": false,
		"cargo_capacity": _resource_float(template, "food_capacity", 0.0),
		"alarm_raised": false,
		"combat_engaged": false,
		"resolved": false,
		"encamp_position": encamp_position,
		"target_position": target_position,
		"route_waypoints": travel_waypoints,
		"route_index": 0,
		"leader_actor_path": actors[0].get_path() if not actors.is_empty() and actors[0] is Node else NodePath(""),
		"actor_paths": _actor_paths(actors),
		"event_created": false,
	}
	active_squads[squad_id] = squad_state
	return squad_state.duplicate(true)


func serialize_state() -> Dictionary:
	return active_squads.duplicate(true)


func get_squad_state(squad_id: String) -> Dictionary:
	var state: Dictionary = active_squads.get(squad_id, {})
	return state.duplicate(true)


func cancel_operation(squad_id: String, reason := "cancelled") -> void:
	if not active_squads.has(squad_id):
		return
	var squad_state: Dictionary = active_squads[squad_id]
	_clear_planning_conversation(squad_state)
	squad_state["resolved"] = true
	squad_state["resolution"] = reason
	squad_state["phase_id"] = PHASE_RESOLVED
	_assign_squad_move_targets(squad_state, _source_retreat_position(squad_state))
	active_squads[squad_id] = squad_state


func start_battle(squad_id: String) -> void:
	if not active_squads.has(squad_id):
		return
	var squad_state: Dictionary = active_squads[squad_id]
	_transition_squad_phase(squad_state, PHASE_BATTLE)
	_enter_current_phase(squad_state)
	active_squads[squad_id] = squad_state


func debug_force_phase(squad_id: String, phase_id: String) -> void:
	if not active_squads.has(squad_id):
		return
	var squad_state: Dictionary = active_squads[squad_id]
	_transition_squad_phase(squad_state, phase_id)
	_enter_current_phase(squad_state)
	active_squads[squad_id] = squad_state


func _try_initialize() -> void:
	if _initialized or root_scene == null or not is_inside_tree():
		return
	settlement_controller = get_parent().get_node_or_null("SettlementController")
	road_controller = get_parent().get_node_or_null("RoadController")
	world_event_choice_controller = get_parent().get_node_or_null("WorldEventChoiceController")
	if settlement_controller == null:
		return
	_initialized = true


func _create_raid_conflict_event(squad_state: Dictionary, actors: Array, target_anchor: Node3D, target_position: Vector3, template: Resource) -> void:
	if template == null:
		return
	if world_event_choice_controller == null:
		world_event_choice_controller = get_parent().get_node_or_null("WorldEventChoiceController")
	if world_event_choice_controller == null or not world_event_choice_controller.has_method("create_conflict_event"):
		return
	var action: Dictionary = squad_state.get("action", {})
	var source_faction := _resource_faction_id(template)
	var target_faction := _target_faction_id(target_anchor)
	if source_faction.is_empty() or target_faction.is_empty():
		return
	var source_label := _resource_string(template, "display_name", source_faction)
	var target_label := _target_display_name(target_anchor, target_faction)
	var event_id := str(action.get("action_id", squad_state.get("squad_id", "raid")))
	var operation_profile: Resource = squad_state.get("operation_profile", null) as Resource
	world_event_choice_controller.call("create_conflict_event", {
		"event_id": event_id,
		"title": "Raid Underway",
		"description": "%s has started attacking %s. Choose a side or ignore it." % [source_label, target_label],
		"side_a_faction_id": source_faction,
		"side_a_label": source_label,
		"side_b_faction_id": target_faction,
		"side_b_label": target_label,
		"world_position": target_position,
		"event_radius": _operation_float(operation_profile, "conflict_event_radius", 35.0),
		"participation_seconds_required": _operation_float(operation_profile, "conflict_participation_seconds_required", 20.0),
		"side_a_actor_paths": _absolute_actor_paths(actors),
		"side_b_actor_paths": _absolute_actor_paths(_target_residents(target_anchor)),
	})


func _spawn_squad_members(squad_id: String, template: Resource, spawn_position: Vector3, target_position: Vector3, route_waypoints: Array[Vector3]) -> Array:
	var actors: Array = []
	var actor_root := _ensure_actor_root()
	var count: int = max(1, _resource_int(template, "member_count", 1))
	var initial_target := target_position if route_waypoints.is_empty() else route_waypoints[0]
	var hostile_factions = template.get("hostile_faction_ids")
	var faction_id: String = _resource_faction_id(template)
	var member_prefix := _resource_string(template, "member_name_prefix", "Squad Member")
	var used_names := {}
	for index in range(count):
		var actor := CharacterBody3D.new()
		actor.name = "%s_%02d" % [squad_id, index + 1]
		actor.set_script(FACTION_HUMANOID_SCRIPT)
		actor.set("member_name", "%s Leader" % member_prefix if index == 0 else "%s %d" % [member_prefix, index + 1])
		actor.set("stable_id", "world_squad.%s.%d" % [squad_id, index + 1])
		actor.set("faction_name", faction_id)
		actor.set("squad_name", squad_id)
		actor.set("world_squad_id", squad_id)
		actor.set("hostile_factions", hostile_factions)
		actor.set("combat_stance", _resource_int(template, "combat_stance", NpcRules.CombatStance.DEFENSIVE))
		actor.set("base_color", _resource_color(template, "base_color", Color(0.62, 0.62, 0.62, 1.0)))
		actor.set("max_hp", _resource_float(template, "max_hp", 100.0))
		actor.set("base_attack_damage", _resource_float(template, "base_attack_damage", 18.0))
		actor.set("starting_equipment", _resource_array(template, "starting_equipment"))
		_apply_population_generation_to_squad_actor(actor, template, index + 1, squad_id, used_names)
		var offset := _formation_offset(index, count)
		actor.position = spawn_position + offset + Vector3(0.0, 0.6, 0.0)
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
	return Vector3((float(column) - float(columns - 1) * 0.5) * 1.35, 0.0, float(row) * 1.35)


func _apply_population_generation_to_squad_actor(actor: Node, template: Resource, member_index: int, squad_id: String, used_names: Dictionary) -> void:
	if actor == null or template == null:
		return
	var appearance_profile: Resource = template.get("population_appearance_profile") as Resource
	if appearance_profile != null and appearance_profile.has_method("apply_to_actor"):
		appearance_profile.call("apply_to_actor", actor, _make_squad_member_rng(squad_id, member_index, "appearance"), true)
	var name_profile := _template_population_name_profile(template)
	if name_profile != null and name_profile.has_method("generate_name"):
		var appearance = actor.get("appearance_data")
		var body_type := int(appearance.visual_body_type) if appearance != null else int(actor.get("visual_body_type"))
		var generated_name := str(name_profile.call("generate_name", body_type, _make_squad_member_rng(squad_id, member_index, "name"), used_names)).strip_edges()
		if not generated_name.is_empty():
			actor.set("member_name", generated_name)
			used_names[generated_name.to_lower()] = true


func _template_population_name_profile(template: Resource) -> Resource:
	if template == null:
		return null
	var name_profile: Resource = template.get("population_name_profile") as Resource
	if name_profile != null:
		return name_profile
	var faction_definition: Resource = template.get("faction_definition") as Resource
	if faction_definition != null and faction_definition.has_method("get_population_name_profile"):
		return faction_definition.call("get_population_name_profile") as Resource
	return null


func _make_squad_member_rng(squad_id: String, member_index: int, purpose: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	var seed_key := "%s:%d:%s" % [squad_id, member_index, purpose]
	rng.seed = max(1, absi(seed_key.hash()))
	return rng


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
		if _is_squad_defeated(squad_state):
			_resolve_defeated_squad(squad_state)
			active_squads[squad_id] = squad_state
			continue
		var target_id := str(squad_state.get("target_settlement_id", ""))
		var target_anchor: Node3D = settlement_controller.call("get_settlement_anchor", target_id) as Node3D
		if target_anchor == null:
			continue
		if not bool(squad_state.get("phase_entered", false)):
			_enter_current_phase(squad_state)
		var phase := _current_phase_profile(squad_state)
		match _phase_type(phase, str(squad_state.get("phase_id", PHASE_BATTLE))):
			PHASE_TRAVEL:
				_process_travel_phase(squad_state, phase, target_anchor)
			PHASE_PLANNING:
				_process_planning_phase(squad_state, phase, target_anchor)
			PHASE_BATTLE:
				_process_battle_phase(squad_state, phase, target_anchor)
			PHASE_RESOLVED:
				squad_state["resolved"] = true
			_:
				_process_battle_phase(squad_state, phase, target_anchor)
		active_squads[squad_id] = squad_state


func _process_travel_phase(squad_state: Dictionary, phase: Resource, target_anchor: Node3D) -> void:
	var encamp_position: Vector3 = squad_state.get("encamp_position", target_anchor.global_position)
	if _advance_squad_route(squad_state, encamp_position):
		return
	if not _has_actor_reached_position(squad_state, encamp_position, 3.0):
		_ensure_squad_move_targets(squad_state, encamp_position)
		return
	_transition_squad_phase(squad_state, _phase_next_id(phase, PHASE_PLANNING))


func _process_planning_phase(squad_state: Dictionary, phase: Resource, _target_anchor: Node3D) -> void:
	var elapsed := float(squad_state.get("phase_elapsed", 0.0)) + 0.5
	squad_state["phase_elapsed"] = elapsed
	_process_planning_shouts(squad_state, phase)
	var duration := _phase_float(phase, "duration_seconds", 60.0)
	if duration > 0.0 and elapsed >= duration:
		_transition_squad_phase(squad_state, _phase_next_id(phase, PHASE_BATTLE))
		_enter_current_phase(squad_state)


func _process_battle_phase(squad_state: Dictionary, _phase: Resource, target_anchor: Node3D) -> void:
	var target_position: Vector3 = target_anchor.call("get_spawn_position", "defense") if target_anchor.has_method("get_spawn_position") else target_anchor.global_position
	if not bool(squad_state.get("alarm_raised", false)) and _has_actor_reached_town_alarm_range(squad_state, target_anchor):
		if _raise_settlement_alarm(squad_state, target_anchor):
			squad_state["combat_engaged"] = true
		squad_state["alarm_raised"] = true
	if not _has_actor_reached_position(squad_state, target_position, 7.5):
		_ensure_squad_move_targets(squad_state, target_position)
		return
	if not bool(squad_state.get("combat_engaged", false)):
		_assign_targets(_actors_from_paths(squad_state), target_anchor)
		squad_state["combat_engaged"] = true
	var source_id := str(squad_state.get("source_settlement_id", ""))
	var target_id := str(squad_state.get("target_settlement_id", ""))
	var stolen: float = float(settlement_controller.call("resolve_food_transfer", source_id, target_id, float(squad_state.get("cargo_capacity", 0.0)), "visible_food_raid"))
	squad_state["resolved"] = true
	squad_state["resolved_food"] = stolen
	squad_state["phase_id"] = PHASE_RESOLVED


func _enter_current_phase(squad_state: Dictionary) -> void:
	var target_anchor := settlement_controller.call("get_settlement_anchor", str(squad_state.get("target_settlement_id", ""))) as Node3D
	if target_anchor == null:
		return
	var phase := _current_phase_profile(squad_state)
	squad_state["phase_entered"] = true
	squad_state["phase_elapsed"] = 0.0
	match _phase_type(phase, str(squad_state.get("phase_id", PHASE_BATTLE))):
		PHASE_TRAVEL:
			_assign_squad_move_targets(squad_state, squad_state.get("encamp_position", target_anchor.global_position))
		PHASE_PLANNING:
			_assign_planning_conversation(squad_state, phase)
			_stop_squad_movement(squad_state)
			squad_state["next_shout_at"] = 0.0
			squad_state["shout_index"] = 0
			_process_planning_shouts(squad_state, phase)
		PHASE_BATTLE:
			_clear_planning_conversation(squad_state)
			squad_state["route_waypoints"] = []
			squad_state["route_index"] = 0
			var target_position: Vector3 = target_anchor.call("get_spawn_position", "defense") if target_anchor.has_method("get_spawn_position") else target_anchor.global_position
			_assign_squad_move_targets(squad_state, target_position)
			if _phase_bool(phase, "create_conflict_event_on_enter", true) and not bool(squad_state.get("event_created", false)):
				_create_raid_conflict_event(squad_state, _actors_from_paths(squad_state), target_anchor, target_position, squad_state.get("template_resource") as Resource)
				squad_state["event_created"] = true


func _transition_squad_phase(squad_state: Dictionary, phase_id: String) -> void:
	if phase_id.is_empty():
		phase_id = PHASE_RESOLVED
	if str(squad_state.get("phase_id", "")) == PHASE_PLANNING and phase_id != PHASE_PLANNING:
		_clear_planning_conversation(squad_state)
	squad_state["phase_id"] = phase_id
	squad_state["phase_elapsed"] = 0.0
	squad_state["phase_entered"] = false
	squad_state["route_index"] = 0


func _process_planning_shouts(squad_state: Dictionary, phase: Resource) -> void:
	var lines := _phase_string_array(phase, "leader_shout_lines")
	if lines.is_empty():
		return
	var elapsed := float(squad_state.get("phase_elapsed", 0.0))
	var next_shout_at := float(squad_state.get("next_shout_at", 0.0))
	if elapsed + 0.001 < next_shout_at:
		return
	var leader: Node = _leader_actor(squad_state)
	if leader == null or not leader.has_method("show_world_speech"):
		return
	var shout_index := int(squad_state.get("shout_index", 0))
	leader.call("show_world_speech", str(lines[shout_index % lines.size()]), 5.0)
	squad_state["shout_index"] = shout_index + 1
	squad_state["next_shout_at"] = elapsed + maxf(_phase_float(phase, "leader_shout_interval_seconds", 20.0), 1.0)


func _assign_planning_conversation(squad_state: Dictionary, phase: Resource) -> void:
	var leader: Node = _leader_actor(squad_state)
	if leader == null:
		return
	var conversation := _phase_resource(phase, "leader_conversation")
	if conversation == null:
		return
	if not squad_state.has("leader_previous_conversation"):
		squad_state["leader_previous_conversation"] = leader.get("conversation_definition")
	leader.set("conversation_definition", conversation)


func _clear_planning_conversation(squad_state: Dictionary) -> void:
	var leader: Node = _leader_actor(squad_state)
	if leader == null:
		return
	if squad_state.has("leader_previous_conversation"):
		leader.set("conversation_definition", squad_state.get("leader_previous_conversation"))
		squad_state.erase("leader_previous_conversation")


func _stop_squad_movement(squad_state: Dictionary) -> void:
	for actor in _actors_from_paths(squad_state):
		if actor != null and actor.has_method("_clear_actor_move_target"):
			actor.call("_clear_actor_move_target")


func _leader_actor(squad_state: Dictionary):
	var leader_path: NodePath = squad_state.get("leader_actor_path", NodePath(""))
	if not str(leader_path).is_empty():
		var leader := get_node_or_null(leader_path)
		if leader != null:
			return leader
	return _first_alive_actor(squad_state)


func _advance_squad_route(squad_state: Dictionary, target_position: Vector3) -> bool:
	var route_waypoints := _route_waypoints_from_state(squad_state)
	if route_waypoints.is_empty():
		return false
	var route_index := int(squad_state.get("route_index", 0))
	if route_index >= route_waypoints.size():
		return false
	if not _has_actor_reached_position(squad_state, route_waypoints[route_index], 3.0):
		_ensure_squad_move_targets(squad_state, route_waypoints[route_index])
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
		if actor != null and int(actor.get("life_state")) == NpcRules.LifeState.ALIVE and actor.has_method("set_move_target"):
			actor.call("set_move_target", target_position + _formation_offset(index, count), false)


func _ensure_squad_move_targets(squad_state: Dictionary, target_position: Vector3) -> void:
	var actors := _actors_from_paths(squad_state)
	var count := actors.size()
	for index in range(count):
		var actor = actors[index]
		if actor == null or int(actor.get("life_state")) != NpcRules.LifeState.ALIVE or not actor.has_method("set_move_target"):
			continue
		var desired_target := target_position + _formation_offset(index, count)
		var current_target = actor.get("_move_target")
		if bool(actor.get("_has_move_target")) and current_target is Vector3 and current_target.distance_squared_to(desired_target) <= 0.0025:
			continue
		actor.call("set_move_target", desired_target, false)


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


func _raise_settlement_alarm(squad_state: Dictionary, target_anchor: Node3D) -> bool:
	var attacker = _first_alive_actor(squad_state)
	if attacker == null:
		return false
	var combat_started := false
	for node in get_tree().get_nodes_in_group("npc_character"):
		if node == attacker or not (node is HumanoidCharacter) or not node.has_method("respond_to_settlement_alarm"):
			continue
		node.call("respond_to_settlement_alarm", attacker, target_anchor, null)
		if node.get("_current_attack_target") == attacker:
			combat_started = true
	return combat_started


func _is_squad_defeated(squad_state: Dictionary) -> bool:
	var paths: Array = squad_state.get("actor_paths", [])
	if paths.is_empty():
		return false
	for path in paths:
		var actor := get_node_or_null(path)
		if actor != null and int(actor.get("life_state")) == NpcRules.LifeState.ALIVE:
			return false
	return true


func _resolve_defeated_squad(squad_state: Dictionary) -> void:
	_clear_planning_conversation(squad_state)
	squad_state["resolved"] = true
	squad_state["resolution"] = "defeated"
	squad_state["resolved_food"] = 0.0
	squad_state["phase_id"] = PHASE_RESOLVED
	if bool(squad_state.get("alarm_raised", false)):
		squad_state["combat_engaged"] = true


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


func _absolute_actor_paths(actors: Array) -> Array[NodePath]:
	var paths: Array[NodePath] = []
	for actor in actors:
		if actor is Node:
			paths.append(actor.get_path())
	return paths


func _target_residents(target_anchor: Node) -> Array:
	if target_anchor != null and target_anchor.has_method("get_resident_characters"):
		return target_anchor.call("get_resident_characters")
	return []


func _target_faction_id(target_anchor: Node) -> String:
	if target_anchor == null:
		return ""
	var definition = target_anchor.get("settlement_definition")
	if definition != null and definition.has_method("get_faction_id"):
		return str(definition.call("get_faction_id"))
	return ""


func _target_display_name(target_anchor: Node, fallback: String) -> String:
	if target_anchor == null:
		return fallback
	var definition = target_anchor.get("settlement_definition")
	if definition != null:
		var display := str(definition.get("display_name"))
		if not display.is_empty():
			return display
	return fallback


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


func _get_encamp_position(spawn_position: Vector3, target_anchor: Node3D, route_waypoints: Array[Vector3], operation_profile: Resource) -> Vector3:
	if target_anchor == null:
		return spawn_position
	var target_center := target_anchor.global_position
	var approach_origin := spawn_position
	if route_waypoints.size() >= 2:
		approach_origin = route_waypoints[route_waypoints.size() - 2]
	elif not route_waypoints.is_empty():
		approach_origin = route_waypoints[0]
	var direction := Vector3(approach_origin.x - target_center.x, 0.0, approach_origin.z - target_center.z)
	if direction.length_squared() <= 0.001:
		direction = Vector3(spawn_position.x - target_center.x, 0.0, spawn_position.z - target_center.z)
	if direction.length_squared() <= 0.001:
		direction = Vector3.RIGHT
	direction = direction.normalized()
	var distance := _target_alarm_distance(target_anchor) + _operation_float(operation_profile, "encamp_distance_from_border", 10.0)
	return target_center + direction * distance


func _get_safe_travel_waypoints(route_waypoints: Array[Vector3], target_anchor: Node3D, encamp_position: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if target_anchor == null:
		return result
	var target_center := target_anchor.global_position
	var encamp_distance := _flat_distance(target_center, encamp_position)
	for waypoint in route_waypoints:
		if _flat_distance(target_center, waypoint) <= encamp_distance:
			break
		result.append(waypoint)
	return result


func _target_alarm_distance(target_anchor: Node3D) -> float:
	var border_radius := 0.0
	if target_anchor != null:
		var border_radius_value = target_anchor.get("town_border_radius")
		if border_radius_value != null:
			border_radius = maxf(float(border_radius_value), 0.0)
	return border_radius + NpcRules.RAID_ALARM_APPROACH_RANGE


func _flat_distance(left: Vector3, right: Vector3) -> float:
	return Vector2(left.x, left.z).distance_to(Vector2(right.x, right.z))


func _source_retreat_position(squad_state: Dictionary) -> Vector3:
	var source_anchor := settlement_controller.call("get_settlement_anchor", str(squad_state.get("source_settlement_id", ""))) as Node3D
	if source_anchor != null and source_anchor.has_method("get_spawn_position"):
		return source_anchor.call("get_spawn_position", "raid")
	return squad_state.get("encamp_position", Vector3.ZERO)


func _operation_start_phase_id(operation_profile: Resource) -> String:
	if operation_profile != null:
		var start_phase_id := str(operation_profile.get("start_phase_id"))
		if not start_phase_id.is_empty():
			return start_phase_id
	return PHASE_TRAVEL


func _current_phase_profile(squad_state: Dictionary) -> Resource:
	var operation_profile: Resource = squad_state.get("operation_profile", null) as Resource
	if operation_profile != null and operation_profile.has_method("get_phase"):
		return operation_profile.call("get_phase", str(squad_state.get("phase_id", ""))) as Resource
	return null


func _phase_type(phase: Resource, fallback: String) -> String:
	if phase == null:
		return fallback
	var value := str(phase.get("phase_type"))
	return fallback if value.is_empty() else value


func _phase_next_id(phase: Resource, fallback: String) -> String:
	if phase == null:
		return fallback
	var value := str(phase.get("next_phase_id"))
	return fallback if value.is_empty() else value


func _phase_float(phase: Resource, property_name: String, fallback: float) -> float:
	if phase == null:
		return fallback
	var value = phase.get(property_name)
	return fallback if value == null else float(value)


func _phase_bool(phase: Resource, property_name: String, fallback: bool) -> bool:
	if phase == null:
		return fallback
	var value = phase.get(property_name)
	return fallback if value == null else bool(value)


func _phase_resource(phase: Resource, property_name: String) -> Resource:
	return phase.get(property_name) as Resource if phase != null else null


func _phase_string_array(phase: Resource, property_name: String) -> PackedStringArray:
	if phase == null:
		return PackedStringArray()
	var value = phase.get(property_name)
	return PackedStringArray(value) if value != null else PackedStringArray()


func _operation_float(operation_profile: Resource, property_name: String, fallback: float) -> float:
	if operation_profile == null:
		return fallback
	var value = operation_profile.get(property_name)
	return fallback if value == null else float(value)


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


func _resource_array(resource: Resource, property_name: String) -> Array:
	if resource == null:
		return []
	var value = resource.get(property_name)
	return value.duplicate() if value is Array else []


func _resource_color(resource: Resource, property_name: String, fallback: Color) -> Color:
	if resource == null:
		return fallback
	var value = resource.get(property_name)
	return value if value is Color else fallback
