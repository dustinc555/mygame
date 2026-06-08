extends Node

class_name WorldMapCombatSimController

const WORLD_MAP_COMBAT_SIM_ENTITY_ID := "world_map_combat_sim:state"
const WORLD_SQUAD_ENTITY_ID := "world_squad:state"
const WORLD_ENCOUNTER_ENTITY_ID := "world_encounter:state"
const MAX_COMMAND_LOG_ENTRIES := 40
const MAX_ENCOUNTER_LOG_ENTRIES := 40
const DEFAULT_SQUAD_SPEED := 85.0
const DEFAULT_ARRIVAL_THRESHOLD := 2.0
const DEFAULT_ENCOUNTER_RANGE := 30.0
const DEFAULT_SPATIAL_BIN_SIZE := 60.0
const DEFAULT_HOSTILE_THRESHOLD := -50
const DEFAULT_RESOLUTION_TICKS := 1
const DEFAULT_ENCOUNTER_REPEAT_COOLDOWN_TICKS := 30
const MORALE_PERCENT_SENTINEL := 1.5
const GECS_WORLD_SCRIPT := preload("res://addons/gecs/ecs/world.gd")
const GECS_ENTITY_SCRIPT := preload("res://addons/gecs/ecs/entity.gd")
const DEMO_SIM_STATE_SCRIPT := preload("res://scripts/ecs/components/c_game_demo_sim_state.gd")
const WORLD_SQUAD_STATE_SCRIPT := preload("res://scripts/ecs/components/c_game_world_squad_state.gd")
const WORLD_ENCOUNTER_STATE_SCRIPT := preload("res://scripts/ecs/components/c_game_world_encounter_state.gd")
const POPULATION_RECORD_SCRIPT := preload("res://scripts/ecs/components/c_game_population_record.gd")
const BATTLE_SIM_SCRIPT := preload("res://scripts/sim/battle/battle_sim.gd")
const COMBAT_PROJECTION_CONTINUITY_BUILDER_SCRIPT := preload("res://scripts/sim/battle/combat_projection_continuity_builder.gd")
const LIFE_STATE_ALIVE := 0
const LIFE_STATE_DYING := 5
const ATTRIBUTE_STRENGTH := "attribute.strength"
const ATTRIBUTE_PERCEPTION := "attribute.perception"
const ATTRIBUTE_DEXTERITY := "attribute.dexterity"
const ATTRIBUTE_TOUGHNESS := "attribute.toughness"
const ATTRIBUTE_ENDURANCE := "attribute.endurance"
const COMBAT_SWORDS_ONE_HANDED := "combat.swords_one_handed"
const COMBAT_AXES_ONE_HANDED := "combat.axes_one_handed"
const COMBAT_DAGGERS := "combat.daggers"
const COMBAT_UNARMED := "combat.unarmed"
const COMBAT_SHIELDS := "combat.shields"

@export var world_definition: Resource
@export var use_isolated_ecs_world := false
@export var process_ecs_world_on_fixed_tick := false
@export var squad_id_prefix := "world_squad"
@export var member_id_prefix := "world_squad_member"
@export var population_generation_source := "world_squad"

var root_scene: Node
var _ecs_world
var _gecs_world_controller: Node
var _sim_state_entity
var _sim_state_component
var _world_squad_state_entity
var _world_squad_state_component
var _world_encounter_state_entity
var _world_encounter_state_component
var _sim_runner: Node
var _initialized := false


func _ready() -> void:
	add_to_group("world_map_combat_sim_controller")
	add_to_group("world_map_combat_sim_source")
	_ensure_initialized()


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	_ensure_initialized()


func _ensure_initialized() -> void:
	if _initialized:
		return
	if world_definition == null:
		world_definition = _find_world_definition()
	_ensure_world()
	if _ecs_world == null:
		return
	_ensure_state_entity()
	_ensure_world_squad_state_entity()
	_ensure_world_squad_population_records()
	_ensure_world_encounter_state_entity()
	_sim_runner = _find_sim_runner()
	_initialized = true


func _exit_tree() -> void:
	if not use_isolated_ecs_world:
		return
	var ecs_singleton := get_node_or_null("/root/ECS")
	if ecs_singleton != null and ecs_singleton.get("world") == _ecs_world:
		ecs_singleton.set("world", null)


func get_sim_state() -> Dictionary:
	_ensure_state_entity()
	_ensure_world_squad_state_entity()
	_ensure_world_encounter_state_entity()
	var state := {}
	if _sim_state_component != null and _sim_state_component.has_method("to_state"):
		state = _sim_state_component.call("to_state")
	state["world_squad_state"] = get_world_squad_state()
	state["world_encounter_state"] = get_world_encounter_state()
	return state


func get_world_squad_state() -> Dictionary:
	_ensure_world_squad_state_entity()
	if _world_squad_state_component != null and _world_squad_state_component.has_method("to_state"):
		return _world_squad_state_component.call("to_state")
	return {}


func get_world_encounter_state() -> Dictionary:
	_ensure_world_encounter_state_entity()
	if _world_encounter_state_component != null and _world_encounter_state_component.has_method("to_state"):
		return _world_encounter_state_component.call("to_state")
	return {}


func apply_sim_commands(commands: Array[Dictionary]) -> void:
	_ensure_world_squad_state_entity()
	_ensure_world_encounter_state_entity()
	if _world_squad_state_component == null or not _world_squad_state_component.has_method("apply_state"):
		return
	var state := get_world_squad_state()
	var active_squads: Dictionary = state.get("active_squads", {})
	var command_log := _command_log_from_state(state)
	var should_reset_encounters := false
	for command in commands:
		_apply_sim_command(command, active_squads, command_log)
		if _command_resets_world_squads(command):
			should_reset_encounters = true
	state["active_squads"] = active_squads
	state["command_log"] = command_log
	_world_squad_state_component.call("apply_state", state)
	if should_reset_encounters:
		_reset_world_encounter_state()


func update_sim(fixed_delta: float) -> void:
	_ensure_state_entity()
	_ensure_world_squad_state_entity()
	_ensure_world_encounter_state_entity()
	if process_ecs_world_on_fixed_tick and _ecs_world != null and _ecs_world.has_method("process"):
		_ecs_world.call("process", fixed_delta)
	_advance_squad_objectives(fixed_delta)
	_resolve_squad_encounters()
	_detect_squad_encounters()


func get_sim_metrics() -> Dictionary:
	var metrics := {}
	var runner := _get_sim_runner()
	if runner != null and runner.has_method("get_metrics"):
		metrics = runner.call("get_metrics")
	metrics["state"] = get_sim_state()
	return metrics


func _ensure_world() -> void:
	if _ecs_world != null and is_instance_valid(_ecs_world):
		if use_isolated_ecs_world:
			_set_active_ecs_world()
		return
	if not use_isolated_ecs_world:
		_gecs_world_controller = _find_gecs_world_controller()
		if _gecs_world_controller == null:
			return
		_ecs_world = _gecs_world_controller.get("world")
		return
	_ecs_world = get_node_or_null("DemoSimECSWorld")
	if _ecs_world == null:
		_ecs_world = GECS_WORLD_SCRIPT.new()
		_ecs_world.name = "DemoSimECSWorld"
		add_child(_ecs_world)
	if _ecs_world.has_method("initialize"):
		_ecs_world.call("initialize")
	_set_active_ecs_world()


func _ensure_state_entity() -> void:
	_ensure_world()
	if _ecs_world == null:
		return
	if _sim_state_entity == null or not is_instance_valid(_sim_state_entity):
		_sim_state_entity = _find_entity_by_id(WORLD_MAP_COMBAT_SIM_ENTITY_ID)
	if _sim_state_entity == null:
		_sim_state_entity = GECS_ENTITY_SCRIPT.new()
		_sim_state_entity.name = "WorldMapCombatSimState"
		_sim_state_entity.id = WORLD_MAP_COMBAT_SIM_ENTITY_ID
		_ecs_world.call("add_entity", _sim_state_entity, [DEMO_SIM_STATE_SCRIPT.new()])
		_sim_state_component = _sim_state_entity.call("get_component", DEMO_SIM_STATE_SCRIPT)
		if _sim_state_component != null and _sim_state_component.has_method("apply_state"):
			_sim_state_component.call("apply_state", _initial_state())
		return
	_sim_state_component = _sim_state_entity.call("get_component", DEMO_SIM_STATE_SCRIPT)


func _ensure_world_squad_state_entity() -> void:
	_ensure_world()
	if _ecs_world == null:
		return
	var created := false
	if _world_squad_state_entity == null or not is_instance_valid(_world_squad_state_entity):
		_world_squad_state_entity = _find_entity_by_id(WORLD_SQUAD_ENTITY_ID)
	if _world_squad_state_entity == null:
		_world_squad_state_entity = GECS_ENTITY_SCRIPT.new()
		_world_squad_state_entity.name = "WorldSquadState"
		_world_squad_state_entity.id = WORLD_SQUAD_ENTITY_ID
		_ecs_world.call("add_entity", _world_squad_state_entity, [WORLD_SQUAD_STATE_SCRIPT.new()])
		created = true
	_world_squad_state_component = _world_squad_state_entity.call("get_component", WORLD_SQUAD_STATE_SCRIPT)
	if _world_squad_state_component == null or not _world_squad_state_component.has_method("apply_state"):
		return
	if created:
		_world_squad_state_component.call("apply_state", _initial_world_squad_state())


func _ensure_world_encounter_state_entity() -> void:
	_ensure_world()
	if _ecs_world == null:
		return
	if _world_encounter_state_entity == null or not is_instance_valid(_world_encounter_state_entity):
		_world_encounter_state_entity = _find_entity_by_id(WORLD_ENCOUNTER_ENTITY_ID)
	if _world_encounter_state_entity == null:
		_world_encounter_state_entity = GECS_ENTITY_SCRIPT.new()
		_world_encounter_state_entity.name = "WorldEncounterState"
		_world_encounter_state_entity.id = WORLD_ENCOUNTER_ENTITY_ID
		_ecs_world.call("add_entity", _world_encounter_state_entity, [WORLD_ENCOUNTER_STATE_SCRIPT.new()])
	_world_encounter_state_component = _world_encounter_state_entity.call("get_component", WORLD_ENCOUNTER_STATE_SCRIPT)


func _world_squad_state_is_empty() -> bool:
	if _world_squad_state_component == null:
		return true
	var active_squads = _world_squad_state_component.get("active_squads")
	return not (active_squads is Dictionary) or active_squads.is_empty()


func _reset_world_encounter_state() -> void:
	_ensure_world_encounter_state_entity()
	if _world_encounter_state_component != null and _world_encounter_state_component.has_method("apply_state"):
		_world_encounter_state_component.call("apply_state", _initial_world_encounter_state())


func _ensure_world_squad_population_records() -> void:
	_ensure_world_squad_state_entity()
	if _world_squad_state_component == null:
		return
	var state := get_world_squad_state()
	var active_squads = state.get("active_squads", {})
	if active_squads is Dictionary:
		_ensure_world_squad_population_records_for_squads(active_squads, false)


func _ensure_world_squad_population_records_for_squads(active_squads: Dictionary, overwrite_existing: bool) -> void:
	_ensure_world()
	if _ecs_world == null:
		return
	for squad_id in active_squads.keys():
		var record = active_squads[squad_id]
		if not (record is Dictionary):
			continue
		var squad_record: Dictionary = record
		var member_ids := _string_array(squad_record.get("member_ids", []))
		for member_index in range(member_ids.size()):
			_upsert_world_squad_population_record(squad_record, member_ids[member_index], member_index, overwrite_existing)


func _upsert_world_squad_population_record(squad_record: Dictionary, member_id: String, member_index: int, overwrite_existing: bool) -> void:
	var actor_id := member_id.strip_edges()
	if actor_id.is_empty():
		return
	var entity = _find_entity_by_id(_population_entity_id(actor_id))
	if entity == null:
		entity = GECS_ENTITY_SCRIPT.new()
		entity.name = _population_entity_node_name(actor_id)
		entity.id = _population_entity_id(actor_id)
		_ecs_world.call("add_entity", entity, [POPULATION_RECORD_SCRIPT.new()])
	elif not overwrite_existing:
		var existing_component = entity.call("get_component", POPULATION_RECORD_SCRIPT)
		if existing_component != null:
			return
	var component = entity.call("get_component", POPULATION_RECORD_SCRIPT)
	if component != null and component.has_method("apply_record"):
		component.call("apply_record", _world_squad_population_record(squad_record, actor_id, member_index))


func _world_squad_population_record(squad_record: Dictionary, member_id: String, member_index: int) -> Dictionary:
	var max_hp := maxf(float(squad_record.get("max_hp", 100.0)), 1.0)
	var max_blood := 5.0
	return {
		"actor_id": member_id,
		"stable_id": member_id,
		"settlement_id": "",
		"generation_source": population_generation_source,
		"generation_index": member_index,
		"member_name": "%s %02d" % [str(squad_record.get("member_name_prefix", "Squad Member")), member_index + 1],
		"projection_kind": "humanoid",
		"faction_id": str(squad_record.get("faction_id", "")),
		"squad_name": str(squad_record.get("squad_id", "")),
		"role_id": "squad_member",
		"hostile_faction_ids": _string_array(squad_record.get("hostile_faction_ids", [])),
		"combat_stance": int(squad_record.get("combat_stance", 1)),
		"base_color": squad_record.get("base_color", Color(0.62, 0.62, 0.62, 1.0)),
		"skill_levels": _world_squad_member_skill_levels(squad_record, member_index),
		"traits": {"world_squad_member": true},
		"personality": {},
		"life_state": LIFE_STATE_ALIVE,
		"hp": max_hp,
		"max_hp": max_hp,
		"blood": max_blood,
		"max_blood": max_blood,
		"base_attack_damage": maxf(float(squad_record.get("base_attack_damage", 0.0)), 0.0),
		"base_dodge_chance": 0.0,
		"base_block_chance": 0.0,
		"realization_state": "ledger",
		"ledger_activity_state": "squad_ready",
		"last_world_position": _record_location(squad_record),
		"last_world_position_initialized": true,
		"important": false,
	}


func _world_squad_member_skill_levels(squad_record: Dictionary, member_index: int) -> Dictionary:
	var base_attack := maxf(float(squad_record.get("base_attack_damage", 10.0)), 1.0)
	var base_level := maxi(1, int(round(base_attack * 0.55)))
	var variance := member_index % 3
	var stance_bonus := 1 if int(squad_record.get("combat_stance", 1)) == 0 else 0
	var weapon_level := base_level + variance + stance_bonus
	return {
		COMBAT_SWORDS_ONE_HANDED: weapon_level,
		COMBAT_AXES_ONE_HANDED: maxi(1, weapon_level - 2),
		COMBAT_DAGGERS: maxi(1, weapon_level - 3),
		COMBAT_UNARMED: maxi(1, base_level - 3),
		COMBAT_SHIELDS: maxi(1, base_level - 1),
		ATTRIBUTE_STRENGTH: base_level + stance_bonus,
		ATTRIBUTE_PERCEPTION: base_level + 1,
		ATTRIBUTE_DEXTERITY: base_level + variance,
		ATTRIBUTE_TOUGHNESS: base_level,
		ATTRIBUTE_ENDURANCE: base_level,
	}


func _population_entity_id(actor_id: String) -> String:
	return "population:%s" % actor_id


func _population_entity_node_name(actor_id: String) -> String:
	return "Population_%s" % _safe_node_name(actor_id)


func _find_entity_by_id(entity_id: String):
	var registry = _ecs_world.get("entity_id_registry")
	if registry is Dictionary:
		var entity = registry.get(entity_id)
		if entity != null and is_instance_valid(entity):
			return entity
	return null


func _initial_state() -> Dictionary:
	return {
		"state_id": "world_map_combat_sim",
		"world_id": _world_definition_id(),
		"world_definition_path": _world_definition_path(),
	}


func _initial_world_squad_state() -> Dictionary:
	var active_squads := {}
	var faction_locations := _settlement_locations_by_faction_id()
	var squad_templates := _world_squad_templates()
	for index in range(squad_templates.size()):
		var template := squad_templates[index]
		var squad_id := _squad_id_for_template(template, index)
		var faction_id := _template_faction_id(template)
		active_squads[squad_id] = _squad_record_from_template(
			squad_id,
			faction_id,
			template,
			faction_locations.get(faction_id, Vector3.ZERO)
		)
	return {
		"state_id": "world_squads",
		"squad_index": active_squads.size(),
		"active_squads": active_squads,
		"command_log": [],
	}


func _initial_world_encounter_state() -> Dictionary:
	return {
		"state_id": "world_encounters",
		"encounters_by_id": {},
		"active_pair_keys": {},
		"next_encounter_id": 1,
		"encounter_range": DEFAULT_ENCOUNTER_RANGE,
		"spatial_bin_size": DEFAULT_SPATIAL_BIN_SIZE,
		"hostile_threshold": DEFAULT_HOSTILE_THRESHOLD,
		"default_resolution_ticks": DEFAULT_RESOLUTION_TICKS,
		"encounter_repeat_cooldown_ticks": DEFAULT_ENCOUNTER_REPEAT_COOLDOWN_TICKS,
		"recent_pair_cooldowns": {},
		"encounter_log": [],
	}


func _squad_record_from_template(squad_id: String, faction_id: String, template: Resource, location: Vector3) -> Dictionary:
	var member_count := _resource_int(template, "member_count", 1)
	var base_strength := _resource_float(template, "base_strength", 0.0)
	var base_attack_damage := _resource_float(template, "base_attack_damage", 0.0)
	var member_ids := _member_ids_for_squad_template(squad_id, template, member_count)
	return {
		"squad_id": squad_id,
		"template_id": _resource_id(template),
		"faction_id": faction_id,
		"location": location,
		"objective_id": "hold_position",
		"objective_state": "idle",
		"target_location": location,
		"route": [location, location],
		"speed": DEFAULT_SQUAD_SPEED,
		"arrival_threshold": DEFAULT_ARRIVAL_THRESHOLD,
		"arrival_state": "idle",
		"home_location": location,
		"active_encounter_id": "",
		"last_encounter_id": "",
		"member_count": member_count,
		"member_ids": member_ids,
		"member_name_prefix": _resource_string(template, "member_name_prefix", "Squad Member"),
		"strength": base_strength + float(member_count) * base_attack_damage,
		"base_strength": base_strength,
		"base_attack_damage": base_attack_damage,
		"max_hp": _resource_float(template, "max_hp", 100.0),
		"combat_stance": _resource_int(template, "combat_stance", 1),
		"hostile_faction_ids": _resource_string_array(template, "hostile_faction_ids"),
		"base_color": template.get("base_color") if template != null else Color(0.62, 0.62, 0.62, 1.0),
		"morale": 1.0,
		"supplies": _resource_float(template, "food_capacity", 0.0),
		"state": "idle",
	}


func _apply_sim_command(command: Dictionary, active_squads: Dictionary, command_log: Array[Dictionary]) -> void:
	var action := str(command.get("action", "")).strip_edges()
	match action:
		"set_squad_objective":
			_apply_set_squad_objective(command, active_squads, command_log)
		"set_squads_objective":
			_apply_set_squads_objective(command, active_squads, command_log)
		"force_encounter":
			_apply_force_encounter_command(command, active_squads, command_log)
		"reset_demo_squads", "reset_world_squads":
			_apply_reset_world_squads_command(command, active_squads, command_log)
		_:
			_append_command_log(command_log, command, "error", "Unknown command action: %s" % action)


func _apply_set_squad_objective(command: Dictionary, active_squads: Dictionary, command_log: Array[Dictionary]) -> void:
	var squad_id := str(command.get("squad_id", "")).strip_edges()
	if not active_squads.has(squad_id):
		_append_command_log(command_log, command, "error", "Unknown squad: %s" % squad_id)
		return
	var record: Dictionary = active_squads[squad_id]
	_write_objective_to_squad_record(record, command)
	active_squads[squad_id] = record
	_append_command_log(command_log, command, "applied", "Queued objective for %s" % squad_id)


func _apply_set_squads_objective(command: Dictionary, active_squads: Dictionary, command_log: Array[Dictionary]) -> void:
	var squad_ids := _string_array(command.get("squad_ids", []))
	if squad_ids.is_empty():
		_append_command_log(command_log, command, "error", "No squads supplied")
		return
	var applied_count := 0
	for squad_id in squad_ids:
		if not active_squads.has(squad_id):
			continue
		var record: Dictionary = active_squads[squad_id]
		_write_objective_to_squad_record(record, command)
		active_squads[squad_id] = record
		applied_count += 1
	if applied_count <= 0:
		_append_command_log(command_log, command, "error", "No supplied squads exist")
		return
	_append_command_log(command_log, command, "applied", "Queued objective for %d squads" % applied_count)


func _apply_force_encounter_command(command: Dictionary, active_squads: Dictionary, command_log: Array[Dictionary]) -> void:
	var debug_command := command.duplicate(true)
	debug_command["objective_id"] = "force_encounter_debug"
	debug_command["debug_only"] = true
	var squad_ids := _string_array(debug_command.get("squad_ids", []))
	if squad_ids.is_empty():
		_append_command_log(command_log, command, "error", "No squads supplied for debug encounter")
		return
	var applied_count := 0
	for squad_id in squad_ids:
		if not active_squads.has(squad_id):
			continue
		var record: Dictionary = active_squads[squad_id]
		_write_objective_to_squad_record(record, debug_command)
		active_squads[squad_id] = record
		applied_count += 1
	if applied_count <= 0:
		_append_command_log(command_log, command, "error", "No supplied squads exist for debug encounter")
		return
	_append_command_log(command_log, command, "applied", "Recorded debug-only forced encounter placeholder for %d squads" % applied_count)


func _apply_reset_world_squads_command(command: Dictionary, active_squads: Dictionary, command_log: Array[Dictionary]) -> void:
	var reset_state := _initial_world_squad_state()
	var reset_squads: Dictionary = reset_state.get("active_squads", {})
	active_squads.clear()
	for squad_id in reset_squads.keys():
		active_squads[squad_id] = reset_squads[squad_id]
	_ensure_world_squad_population_records_for_squads(active_squads, true)
	_append_command_log(command_log, command, "applied", "Reset world squad records")


func _command_resets_world_squads(command: Dictionary) -> bool:
	match str(command.get("action", "")).strip_edges():
		"reset_demo_squads", "reset_world_squads":
			return true
		_:
			return false


func _write_objective_to_squad_record(record: Dictionary, command: Dictionary) -> void:
	var current_location := _record_location(record)
	var objective_id := str(command.get("objective_id", "move_to")).strip_edges()
	if objective_id.is_empty():
		objective_id = "move_to"
	var target_location := _objective_target_location(record, command, current_location, objective_id)
	record["command_id"] = str(command.get("command_id", "")).strip_edges()
	record["command_action"] = str(command.get("action", "")).strip_edges()
	record["objective_id"] = objective_id
	record["objective_state"] = "active"
	record["target_id"] = str(command.get("target_id", "")).strip_edges()
	record["target_location"] = target_location
	record["route"] = [current_location, target_location]
	record["speed"] = maxf(float(command.get("speed", record.get("speed", DEFAULT_SQUAD_SPEED))), 0.0)
	record["arrival_threshold"] = maxf(float(command.get("arrival_threshold", record.get("arrival_threshold", DEFAULT_ARRIVAL_THRESHOLD))), 0.0)
	record["arrival_state"] = "en_route"
	record["debug_only"] = bool(command.get("debug_only", false))
	var battle_sim_config = command.get("battle_sim_config", {})
	if battle_sim_config is Dictionary and not (battle_sim_config as Dictionary).is_empty():
		record["battle_sim_config"] = (battle_sim_config as Dictionary).duplicate(true)
	else:
		record.erase("battle_sim_config")
	var squad_state := str(command.get("squad_state", "commanded")).strip_edges()
	record["state"] = squad_state if not squad_state.is_empty() else "commanded"


func _advance_squad_objectives(fixed_delta: float) -> void:
	if fixed_delta <= 0.0:
		return
	if _world_squad_state_component == null or not _world_squad_state_component.has_method("apply_state"):
		return
	var state := get_world_squad_state()
	var active_squads = state.get("active_squads", {})
	if not (active_squads is Dictionary):
		return
	var command_log := _command_log_from_state(state)
	var changed := false
	for squad_id in active_squads.keys():
		var record = active_squads[squad_id]
		if not (record is Dictionary):
			continue
		var squad_record: Dictionary = record
		if _advance_squad_record(squad_record, fixed_delta, command_log):
			active_squads[squad_id] = squad_record
			changed = true
	if not changed:
		return
	state["active_squads"] = active_squads
	state["command_log"] = command_log
	_world_squad_state_component.call("apply_state", state)


func _advance_squad_record(record: Dictionary, fixed_delta: float, command_log: Array[Dictionary]) -> bool:
	if not str(record.get("active_encounter_id", "")).strip_edges().is_empty():
		return false
	if str(record.get("state", "")).strip_edges() == "engaged":
		return false
	if str(record.get("objective_state", "")).strip_edges() != "active":
		return false
	if str(record.get("arrival_state", "")).strip_edges() != "en_route":
		return false
	var current_location := _record_location(record)
	var target_location := _record_target_location(record, current_location)
	var arrival_threshold := maxf(float(record.get("arrival_threshold", DEFAULT_ARRIVAL_THRESHOLD)), 0.0)
	var remaining_distance := _xz_distance(current_location, target_location)
	if remaining_distance <= arrival_threshold:
		_complete_squad_arrival(record, target_location, command_log)
		return true
	var speed := maxf(float(record.get("speed", DEFAULT_SQUAD_SPEED)), 0.0)
	if speed <= 0.0:
		return false
	var travel_distance := minf(speed * fixed_delta, remaining_distance)
	if travel_distance <= 0.0:
		return false
	var travel_ratio := travel_distance / remaining_distance
	var next_location := Vector3(
		lerpf(current_location.x, target_location.x, travel_ratio),
		current_location.y,
		lerpf(current_location.z, target_location.z, travel_ratio)
	)
	if _xz_distance(next_location, target_location) <= arrival_threshold:
		_complete_squad_arrival(record, target_location, command_log)
		return true
	record["location"] = next_location
	record["state"] = "travel"
	return true


func _complete_squad_arrival(record: Dictionary, target_location: Vector3, command_log: Array[Dictionary]) -> void:
	record["location"] = target_location
	record["objective_state"] = "complete"
	record["arrival_state"] = "arrived"
	record["state"] = "idle"
	_append_command_log(command_log, _command_from_squad_record(record), "arrived", "Squad arrived at %s" % str(record.get("target_id", record.get("squad_id", "target"))))


func _resolve_squad_encounters() -> void:
	if _world_squad_state_component == null or not _world_squad_state_component.has_method("apply_state"):
		return
	if _world_encounter_state_component == null or not _world_encounter_state_component.has_method("apply_state"):
		return
	var squad_state := get_world_squad_state()
	var active_squads = squad_state.get("active_squads", {})
	if not (active_squads is Dictionary):
		return
	var encounter_state := get_world_encounter_state()
	var encounters_by_id := _dictionary_from_state(encounter_state, "encounters_by_id")
	var active_pair_keys := _dictionary_from_state(encounter_state, "active_pair_keys")
	var recent_pair_cooldowns := _dictionary_from_state(encounter_state, "recent_pair_cooldowns")
	var encounter_log := _encounter_log_from_state(encounter_state)
	var current_tick := _current_tick_count()
	var default_resolution_ticks := maxi(0, int(encounter_state.get("default_resolution_ticks", DEFAULT_RESOLUTION_TICKS)))
	var repeat_cooldown_ticks := maxi(0, int(encounter_state.get("encounter_repeat_cooldown_ticks", DEFAULT_ENCOUNTER_REPEAT_COOLDOWN_TICKS)))
	var squads_changed := false
	var encounters_changed := _decrement_recent_pair_cooldowns(recent_pair_cooldowns)
	for encounter_id_value in encounters_by_id.keys():
		var encounter_id := str(encounter_id_value)
		var encounter = encounters_by_id[encounter_id_value]
		if not (encounter is Dictionary):
			continue
		var encounter_record: Dictionary = encounter
		var status := str(encounter_record.get("status", "")).strip_edges()
		if status == "engaged":
			encounter_record["status"] = "resolving"
			encounter_record["resolution_ticks_remaining"] = int(encounter_record.get("resolution_ticks_remaining", default_resolution_ticks))
			_append_encounter_log(encounter_log, "resolving", encounter_id, str(encounter_record.get("pair_key", "")), "Started resolving %s" % encounter_id)
			status = "resolving"
			encounters_changed = true
		if status != "resolving":
			encounters_by_id[encounter_id] = encounter_record
			continue
		var resolution_ticks_remaining := maxi(0, int(encounter_record.get("resolution_ticks_remaining", default_resolution_ticks)) - 1)
		encounter_record["resolution_ticks_remaining"] = resolution_ticks_remaining
		if resolution_ticks_remaining > 0:
			encounters_by_id[encounter_id] = encounter_record
			encounters_changed = true
			continue
		if _resolve_encounter_record(encounter_record, active_squads, active_pair_keys, recent_pair_cooldowns, encounter_log, current_tick, repeat_cooldown_ticks):
			encounters_by_id[encounter_id] = encounter_record
			squads_changed = true
			encounters_changed = true
		else:
			encounters_by_id[encounter_id] = encounter_record
	if squads_changed:
		squad_state["active_squads"] = active_squads
		_world_squad_state_component.call("apply_state", squad_state)
	if encounters_changed:
		encounter_state["encounters_by_id"] = encounters_by_id
		encounter_state["active_pair_keys"] = active_pair_keys
		encounter_state["recent_pair_cooldowns"] = recent_pair_cooldowns
		encounter_state["default_resolution_ticks"] = default_resolution_ticks
		encounter_state["encounter_repeat_cooldown_ticks"] = repeat_cooldown_ticks
		encounter_state["encounter_log"] = encounter_log
		_world_encounter_state_component.call("apply_state", encounter_state)


func _resolve_encounter_record(encounter_record: Dictionary, active_squads: Dictionary, active_pair_keys: Dictionary, recent_pair_cooldowns: Dictionary, encounter_log: Array[Dictionary], current_tick: int, repeat_cooldown_ticks: int) -> bool:
	var squad_ids := _string_array(encounter_record.get("squad_ids", []))
	if squad_ids.size() < 2:
		return false
	var squad_a_id := squad_ids[0]
	var squad_b_id := squad_ids[1]
	if not active_squads.has(squad_a_id) or not active_squads.has(squad_b_id):
		return false
	var squad_a = active_squads[squad_a_id]
	var squad_b = active_squads[squad_b_id]
	if not (squad_a is Dictionary) or not (squad_b is Dictionary):
		return false
	var squad_a_record: Dictionary = squad_a
	var squad_b_record: Dictionary = squad_b
	var encounter_id := str(encounter_record.get("encounter_id", ""))
	var pair_key := str(encounter_record.get("pair_key", _squad_pair_key(squad_a_id, squad_b_id))).strip_edges()
	var squad_a_payload := _battle_participant_payload(squad_a_record)
	var squad_b_payload := _battle_participant_payload(squad_b_record)
	var battle_result: Dictionary = BATTLE_SIM_SCRIPT.resolve_encounter(encounter_record, squad_a_payload, squad_b_payload, _battle_sim_config(encounter_record, current_tick))
	_apply_member_casualties_to_population_records(battle_result)
	_apply_battle_result_to_squad_record(squad_a_record, battle_result, encounter_id)
	_apply_battle_result_to_squad_record(squad_b_record, battle_result, encounter_id)
	active_squads[squad_a_id] = squad_a_record
	active_squads[squad_b_id] = squad_b_record
	encounter_record["status"] = "resolved"
	encounter_record["resolved_tick"] = current_tick
	encounter_record["resolution_ticks_remaining"] = 0
	battle_result["combat_continuity"] = COMBAT_PROJECTION_CONTINUITY_BUILDER_SCRIPT.build_continuity(encounter_record, battle_result, _combat_continuity_current_records(squad_a_record, squad_b_record))
	encounter_record["battle_result"] = battle_result
	encounter_record["is_debug_forced"] = bool(encounter_record.get("is_debug_forced", encounter_record.get("debug_only", false)))
	if not pair_key.is_empty():
		active_pair_keys.erase(pair_key)
		if repeat_cooldown_ticks > 0:
			recent_pair_cooldowns[pair_key] = repeat_cooldown_ticks
	_append_encounter_log(encounter_log, "resolved", encounter_id, pair_key, str(battle_result.get("summary", "Resolved encounter %s" % encounter_id)))
	return true


func _battle_sim_config(encounter_record: Dictionary, current_tick: int) -> Dictionary:
	var seed_text := "%s|%s|%s" % [_world_definition_id(), str(encounter_record.get("encounter_id", "")), str(encounter_record.get("created_tick", 0))]
	var config: Dictionary = encounter_record.get("battle_sim_config", {}).duplicate(true) if encounter_record.get("battle_sim_config", {}) is Dictionary else {}
	config.merge({
		"seed": seed_text,
		"encounter_id": str(encounter_record.get("encounter_id", "")),
		"current_tick": current_tick,
	}, true)
	return config


func _battle_participant_payload(squad_record: Dictionary) -> Dictionary:
	var payload := squad_record.duplicate(true)
	var member_ids := _string_array(squad_record.get("member_ids", []))
	var member_records := _resolve_squad_member_records(squad_record)
	if not member_records.is_empty() and member_records.size() == member_ids.size():
		payload["member_records"] = member_records
		payload["member_records_are_canonical"] = true
	return payload


func _combat_continuity_current_records(squad_a_record: Dictionary, squad_b_record: Dictionary) -> Dictionary:
	return {
		"squad_records": [
			_battle_participant_payload(squad_a_record),
			_battle_participant_payload(squad_b_record),
		],
	}


func _resolve_squad_member_records(squad_record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for member_id in _string_array(squad_record.get("member_ids", [])):
		var record := _population_record_for_member_id(member_id)
		if record.is_empty():
			continue
		if _gecs_world_controller != null and _gecs_world_controller.has_method("get_actor_battle_member_record"):
			var derived_record = _gecs_world_controller.call("get_actor_battle_member_record", member_id, record)
			if derived_record is Dictionary:
				record = (derived_record as Dictionary).duplicate(true)
		result.append(record)
	return result


func _population_record_for_member_id(member_id: String) -> Dictionary:
	var component = _population_record_component_for_member_id(member_id)
	if component != null and component.has_method("to_record"):
		return component.call("to_record")
	return {}


func _population_record_component_for_member_id(member_id: String):
	var actor_id := member_id.strip_edges()
	if actor_id.is_empty() or _ecs_world == null:
		return null
	var entity = _find_entity_by_id(_population_entity_id(actor_id))
	if entity == null:
		return null
	return entity.call("get_component", POPULATION_RECORD_SCRIPT)


func _apply_member_casualties_to_population_records(battle_result: Dictionary) -> void:
	var member_casualties = battle_result.get("member_casualties", {})
	if not (member_casualties is Dictionary):
		return
	for squad_id in member_casualties.keys():
		var entries = member_casualties[squad_id]
		if not (entries is Array):
			continue
		for entry in entries:
			if entry is Dictionary:
				_apply_member_casualty_to_population_record(entry)


func _apply_member_casualty_to_population_record(casualty: Dictionary) -> void:
	var member_id := str(casualty.get("member_id", casualty.get("actor_id", ""))).strip_edges()
	var component = _population_record_component_for_member_id(member_id)
	if component == null or not component.has_method("to_record") or not component.has_method("apply_record"):
		return
	var record: Dictionary = component.call("to_record")
	var life_state := int(casualty.get("life_state", LIFE_STATE_DYING))
	record["life_state"] = life_state
	var max_hp := float(record.get("max_hp", 0.0))
	if max_hp > 0.0:
		record["hp"] = 0.0 if life_state != LIFE_STATE_ALIVE else clampf(float(record.get("hp", max_hp)), 0.0, max_hp)
	var max_blood := float(record.get("max_blood", 0.0))
	if max_blood > 0.0:
		record["blood"] = minf(float(record.get("blood", max_blood)), max_blood * 0.35)
	component.call("apply_record", record)


func _apply_battle_result_to_squad_record(record: Dictionary, battle_result: Dictionary, encounter_id: String) -> void:
	var squad_id := str(record.get("squad_id", ""))
	var old_member_count := maxi(0, int(record.get("member_count", 0)))
	var profile := _battle_profile_for_squad(battle_result, squad_id)
	var used_canonical_members := bool(profile.get("member_records_used", false)) and bool(profile.get("member_records_are_canonical", false))
	var casualties := clampi(int(_value_for_squad(battle_result.get("casualties", {}), squad_id, 0)), 0, old_member_count)
	var next_member_count := _combat_capable_member_count(record) if used_canonical_members else maxi(0, old_member_count - casualties)
	var survivor_ratio := float(next_member_count) / maxf(float(old_member_count), 1.0)
	record["member_count"] = next_member_count
	if used_canonical_members:
		record["strength"] = _remaining_member_power(profile, battle_result, squad_id, next_member_count)
	else:
		record["strength"] = maxf(float(record.get("strength", 0.0)) * survivor_ratio, 0.0)
	var morale_delta := float(_value_for_squad(battle_result.get("morale_delta", {}), squad_id, 0.0))
	var current_morale := float(record.get("morale", 1.0))
	morale_delta = _morale_delta_for_record_units(current_morale, morale_delta)
	record["morale"] = maxf(current_morale + morale_delta, 0.0)
	var supplies_delta := float(_value_for_squad(battle_result.get("supplies_delta", {}), squad_id, 0.0))
	record["supplies"] = maxf(float(record.get("supplies", 0.0)) + supplies_delta, 0.0)
	record["active_encounter_id"] = ""
	record["last_encounter_id"] = encounter_id
	record["debug_only"] = false
	record.erase("battle_sim_config")
	record["target_location"] = _record_location(record)
	record["route"] = [_record_location(record), _record_location(record)]
	if next_member_count <= 0:
		record["state"] = "defeated"
		record["objective_id"] = "defeated"
		record["objective_state"] = "defeated"
		record["arrival_state"] = "stopped"
		return
	record["state"] = "post_battle"
	record["objective_id"] = "post_battle"
	record["objective_state"] = "interrupted"
	record["arrival_state"] = "idle"


func _morale_delta_for_record_units(current_morale: float, morale_delta: float) -> float:
	# BattleSim emits ratio deltas; old percent-like morale records need matching units.
	return morale_delta * 100.0 if current_morale > MORALE_PERCENT_SENTINEL else morale_delta


func _battle_profile_for_squad(battle_result: Dictionary, squad_id: String) -> Dictionary:
	var profile = _value_for_squad(battle_result.get("combat_profile", {}), squad_id, {})
	return profile.duplicate(true) if profile is Dictionary else {}


func _remaining_member_power(profile: Dictionary, battle_result: Dictionary, squad_id: String, next_member_count: int) -> float:
	var remaining_power := maxf(float(profile.get("base_power", 0.0)) - _member_casualty_power(battle_result, squad_id), 0.0)
	if next_member_count > 0 and remaining_power <= 0.0:
		return float(next_member_count)
	return remaining_power


func _member_casualty_power(battle_result: Dictionary, squad_id: String) -> float:
	var total := 0.0
	var casualties = _value_for_squad(battle_result.get("member_casualties", {}), squad_id, [])
	if not (casualties is Array):
		return total
	for casualty in casualties:
		if casualty is Dictionary:
			total += maxf(float(casualty.get("power_before", 0.0)), 0.0)
	return total


func _combat_capable_member_count(squad_record: Dictionary) -> int:
	var count := 0
	for member_record in _resolve_squad_member_records(squad_record):
		if _member_record_can_fight(member_record):
			count += 1
	return count


func _member_record_can_fight(member_record: Dictionary) -> bool:
	if int(member_record.get("life_state", LIFE_STATE_ALIVE)) != LIFE_STATE_ALIVE:
		return false
	var max_hp := float(member_record.get("max_hp", 0.0))
	if max_hp > 0.0 and float(member_record.get("hp", max_hp)) <= 0.0:
		return false
	var max_blood := float(member_record.get("max_blood", 0.0))
	if max_blood > 0.0 and float(member_record.get("blood", max_blood)) <= 0.0:
		return false
	return true


func _value_for_squad(source, squad_id: String, default_value):
	if source is Dictionary:
		return source.get(squad_id, default_value)
	return default_value


func _decrement_recent_pair_cooldowns(recent_pair_cooldowns: Dictionary) -> bool:
	var changed := false
	for pair_key in recent_pair_cooldowns.keys():
		var next_ticks := int(recent_pair_cooldowns.get(pair_key, 0)) - 1
		if next_ticks <= 0:
			recent_pair_cooldowns.erase(pair_key)
		else:
			recent_pair_cooldowns[pair_key] = next_ticks
		changed = true
	return changed


func _detect_squad_encounters() -> void:
	if _world_squad_state_component == null or not _world_squad_state_component.has_method("apply_state"):
		return
	if _world_encounter_state_component == null or not _world_encounter_state_component.has_method("apply_state"):
		return
	var squad_state := get_world_squad_state()
	var active_squads = squad_state.get("active_squads", {})
	if not (active_squads is Dictionary):
		return
	var encounter_state := get_world_encounter_state()
	var encounters_by_id = _dictionary_from_state(encounter_state, "encounters_by_id")
	var active_pair_keys = _dictionary_from_state(encounter_state, "active_pair_keys")
	var recent_pair_cooldowns = _dictionary_from_state(encounter_state, "recent_pair_cooldowns")
	var encounter_log := _encounter_log_from_state(encounter_state)
	var encounter_range := maxf(float(encounter_state.get("encounter_range", DEFAULT_ENCOUNTER_RANGE)), 0.0)
	if encounter_range <= 0.0:
		return
	var spatial_bin_size := maxf(float(encounter_state.get("spatial_bin_size", DEFAULT_SPATIAL_BIN_SIZE)), encounter_range)
	var hostile_threshold := int(encounter_state.get("hostile_threshold", DEFAULT_HOSTILE_THRESHOLD))
	var bins := _build_squad_spatial_bins(active_squads, spatial_bin_size)
	if bins.is_empty():
		return
	var faction_outlooks := _faction_outlooks_by_direction()
	var checked_pair_keys := {}
	var next_encounter_id: int = maxi(1, int(encounter_state.get("next_encounter_id", 1)))
	var range_squared := encounter_range * encounter_range
	var squads_changed := false
	var encounters_changed := false
	for squad_id_value in active_squads.keys():
		var squad_id := str(squad_id_value)
		var record = active_squads[squad_id_value]
		if not (record is Dictionary):
			continue
		var squad_record: Dictionary = record
		if not _squad_can_be_spatial_bin_member(squad_record):
			continue
		var squad_location := _record_location(squad_record)
		var bin_coords := _spatial_bin_coords(squad_location, spatial_bin_size)
		var squad_engaged := false
		for x_offset in range(-1, 2):
			if squad_engaged:
				break
			for z_offset in range(-1, 2):
				if squad_engaged:
					break
				var neighbor_key := _spatial_bin_key(Vector2i(bin_coords.x + x_offset, bin_coords.y + z_offset))
				var nearby_squad_ids = bins.get(neighbor_key, [])
				if not (nearby_squad_ids is Array):
					continue
				for other_id_value in nearby_squad_ids:
					if squad_engaged:
						break
					var other_id := str(other_id_value)
					if other_id == squad_id:
						continue
					var pair_key := _squad_pair_key(squad_id, other_id)
					if checked_pair_keys.has(pair_key):
						continue
					checked_pair_keys[pair_key] = true
					if active_pair_keys.has(pair_key):
						var existing_encounter_id := str(active_pair_keys.get(pair_key, "")).strip_edges()
						if existing_encounter_id.is_empty() or not encounters_by_id.has(existing_encounter_id):
							active_pair_keys.erase(pair_key)
							encounters_changed = true
						else:
							if _mark_duplicate_encounter_suppressed(pair_key, encounters_by_id, active_pair_keys, encounter_log):
								encounters_changed = true
							continue
					if int(recent_pair_cooldowns.get(pair_key, 0)) > 0:
						continue
					if not active_squads.has(other_id):
						continue
					var other_record_value = active_squads[other_id]
					if not (other_record_value is Dictionary):
						continue
					var other_record: Dictionary = other_record_value
					if not _squad_can_be_encounter_candidate(squad_record):
						continue
					if not _squad_can_be_encounter_candidate(other_record):
						continue
					var distance_squared := _xz_distance_squared(squad_location, _record_location(other_record))
					if distance_squared > range_squared:
						continue
					var decision := _encounter_decision(squad_id, squad_record, other_id, other_record, faction_outlooks, hostile_threshold)
					if not bool(decision.get("should_create", false)):
						continue
					var encounter_id := "encounter:%04d" % next_encounter_id
					next_encounter_id += 1
					encounters_by_id[encounter_id] = _encounter_record(encounter_id, pair_key, squad_id, squad_record, other_id, other_record, decision, distance_squared, encounter_range)
					active_pair_keys[pair_key] = encounter_id
					_mark_squad_engaged(squad_record, encounter_id)
					_mark_squad_engaged(other_record, encounter_id)
					active_squads[squad_id] = squad_record
					active_squads[other_id] = other_record
					_append_encounter_log(encounter_log, "engaged", encounter_id, pair_key, "Created encounter %s" % encounter_id)
					squads_changed = true
					encounters_changed = true
					squad_engaged = true
	if squads_changed:
		squad_state["active_squads"] = active_squads
		_world_squad_state_component.call("apply_state", squad_state)
	if encounters_changed:
		encounter_state["encounters_by_id"] = encounters_by_id
		encounter_state["active_pair_keys"] = active_pair_keys
		encounter_state["recent_pair_cooldowns"] = recent_pair_cooldowns
		encounter_state["next_encounter_id"] = next_encounter_id
		encounter_state["encounter_range"] = encounter_range
		encounter_state["spatial_bin_size"] = spatial_bin_size
		encounter_state["hostile_threshold"] = hostile_threshold
		encounter_state["encounter_log"] = encounter_log
		_world_encounter_state_component.call("apply_state", encounter_state)


func _build_squad_spatial_bins(active_squads: Dictionary, bin_size: float) -> Dictionary:
	var bins := {}
	for squad_id_value in active_squads.keys():
		var record = active_squads[squad_id_value]
		if not (record is Dictionary):
			continue
		var squad_record: Dictionary = record
		if not _squad_can_be_spatial_bin_member(squad_record):
			continue
		var bin_key := _spatial_bin_key(_spatial_bin_coords(_record_location(squad_record), bin_size))
		if not bins.has(bin_key):
			bins[bin_key] = []
		bins[bin_key].append(str(squad_id_value))
	return bins


func _spatial_bin_coords(location: Vector3, bin_size: float) -> Vector2i:
	var safe_bin_size := maxf(bin_size, 1.0)
	return Vector2i(floori(location.x / safe_bin_size), floori(location.z / safe_bin_size))


func _spatial_bin_key(coords: Vector2i) -> String:
	return "%d,%d" % [coords.x, coords.y]


func _squad_can_be_spatial_bin_member(record: Dictionary) -> bool:
	if float(record.get("strength", 0.0)) <= 0.0:
		return false
	match str(record.get("state", "")).strip_edges():
		"defeated", "retreating":
			return false
	return true


func _squad_can_be_encounter_candidate(record: Dictionary) -> bool:
	if not _squad_can_be_spatial_bin_member(record):
		return false
	if not str(record.get("active_encounter_id", "")).strip_edges().is_empty():
		return false
	match str(record.get("state", "")).strip_edges():
		"engaged":
			return false
	return true


func _squad_can_initiate_encounter(record: Dictionary) -> bool:
	if not _squad_can_be_encounter_candidate(record):
		return false
	if float(record.get("morale", 1.0)) <= 0.1:
		return false
	if float(record.get("supplies", 1.0)) <= 0.0:
		return false
	return true


func _encounter_decision(squad_a_id: String, squad_a: Dictionary, squad_b_id: String, squad_b: Dictionary, faction_outlooks: Dictionary, hostile_threshold: int) -> Dictionary:
	if _debug_forced_objective(squad_a):
		return _encounter_decision_result(true, true, "force_encounter_debug", squad_a_id, squad_b_id, 0)
	if _debug_forced_objective(squad_b):
		return _encounter_decision_result(true, true, "force_encounter_debug", squad_b_id, squad_a_id, 0)
	var faction_a := str(squad_a.get("faction_id", "")).strip_edges()
	var faction_b := str(squad_b.get("faction_id", "")).strip_edges()
	var a_outlook := _faction_outlook(faction_a, faction_b, faction_outlooks)
	var b_outlook := _faction_outlook(faction_b, faction_a, faction_outlooks)
	if a_outlook <= hostile_threshold and _aggressive_objective_allows_attack(squad_a, squad_b) and _squad_can_initiate_encounter(squad_a):
		return _encounter_decision_result(true, false, str(squad_a.get("objective_id", "")), squad_a_id, squad_b_id, a_outlook)
	if b_outlook <= hostile_threshold and _aggressive_objective_allows_attack(squad_b, squad_a) and _squad_can_initiate_encounter(squad_b):
		return _encounter_decision_result(true, false, str(squad_b.get("objective_id", "")), squad_b_id, squad_a_id, b_outlook)
	return _encounter_decision_result(false, false, "", "", "", 0)


func _encounter_decision_result(should_create: bool, debug_only: bool, reason: String, initiator_squad_id: String, defender_squad_id: String, hostility_value: int) -> Dictionary:
	return {
		"should_create": should_create,
		"debug_only": debug_only,
		"reason": reason,
		"initiator_squad_id": initiator_squad_id,
		"defender_squad_id": defender_squad_id,
		"hostility_value": hostility_value,
	}


func _debug_forced_objective(record: Dictionary) -> bool:
	if bool(record.get("debug_only", false)):
		return true
	var objective_id := str(record.get("objective_id", "")).strip_edges()
	return objective_id == "force_encounter_debug" or objective_id == "debug_force_encounter"


func _aggressive_objective_allows_attack(attacker: Dictionary, defender: Dictionary) -> bool:
	match str(attacker.get("objective_id", "")).strip_edges():
		"raid":
			return true
		"patrol_for_raid_targets":
			return float(attacker.get("strength", 0.0)) > float(defender.get("strength", 0.0))
		_:
			return false


func _faction_outlooks_by_direction() -> Dictionary:
	var result := {}
	if world_definition == null:
		return result
	var relations = world_definition.get("starting_relations")
	if not (relations is Array):
		return result
	for relation in relations:
		if not (relation is Resource):
			continue
		var faction_a_id := str(relation.get("faction_a_id")).strip_edges()
		var faction_b_id := str(relation.get("faction_b_id")).strip_edges()
		if faction_a_id.is_empty() or faction_b_id.is_empty():
			continue
		result[_directed_faction_key(faction_a_id, faction_b_id)] = int(relation.get("faction_a_outlook_to_b"))
		result[_directed_faction_key(faction_b_id, faction_a_id)] = int(relation.get("faction_b_outlook_to_a"))
	return result


func _faction_outlook(source_faction_id: String, target_faction_id: String, faction_outlooks: Dictionary) -> int:
	if source_faction_id.is_empty() or target_faction_id.is_empty() or source_faction_id == target_faction_id:
		return 0
	return int(faction_outlooks.get(_directed_faction_key(source_faction_id, target_faction_id), 0))


func _directed_faction_key(source_faction_id: String, target_faction_id: String) -> String:
	return "%s>%s" % [source_faction_id, target_faction_id]


func _squad_pair_key(squad_a_id: String, squad_b_id: String) -> String:
	var ids := [squad_a_id, squad_b_id]
	ids.sort()
	return "%s|%s" % [ids[0], ids[1]]


func _xz_distance_squared(first: Vector3, second: Vector3) -> float:
	var x_delta := first.x - second.x
	var z_delta := first.z - second.z
	return x_delta * x_delta + z_delta * z_delta


func _mark_duplicate_encounter_suppressed(pair_key: String, encounters_by_id: Dictionary, active_pair_keys: Dictionary, encounter_log: Array[Dictionary]) -> bool:
	var encounter_id := str(active_pair_keys.get(pair_key, "")).strip_edges()
	if encounter_id.is_empty() or not encounters_by_id.has(encounter_id):
		return false
	var encounter = encounters_by_id[encounter_id]
	if not (encounter is Dictionary):
		return false
	var encounter_record: Dictionary = encounter
	if bool(encounter_record.get("duplicate_suppression_logged", false)):
		return false
	encounter_record["duplicate_suppression_logged"] = true
	encounters_by_id[encounter_id] = encounter_record
	_append_encounter_log(encounter_log, "suppressed", encounter_id, pair_key, "Suppressed duplicate encounter for %s" % pair_key)
	return true


func _encounter_record(encounter_id: String, pair_key: String, squad_a_id: String, squad_a: Dictionary, squad_b_id: String, squad_b: Dictionary, decision: Dictionary, distance_squared: float, encounter_range: float) -> Dictionary:
	var squad_a_location := _record_location(squad_a)
	var squad_b_location := _record_location(squad_b)
	return {
		"encounter_id": encounter_id,
		"pair_key": pair_key,
		"status": "engaged",
		"squad_ids": [squad_a_id, squad_b_id],
		"initiator_squad_id": str(decision.get("initiator_squad_id", "")),
		"defender_squad_id": str(decision.get("defender_squad_id", "")),
		"reason": str(decision.get("reason", "")),
		"debug_only": bool(decision.get("debug_only", false)),
		"is_debug_forced": bool(decision.get("debug_only", false)),
		"created_tick": _current_tick_count(),
		"location": squad_a_location.lerp(squad_b_location, 0.5),
		"distance_squared": distance_squared,
		"encounter_range": encounter_range,
		"faction_ids": [str(squad_a.get("faction_id", "")), str(squad_b.get("faction_id", ""))],
		"objective_ids": [str(squad_a.get("objective_id", "")), str(squad_b.get("objective_id", ""))],
		"hostility_value": int(decision.get("hostility_value", 0)),
		"duplicate_suppression_logged": false,
		"battle_sim_config": _battle_sim_config_from_squads(squad_a, squad_b),
	}


func _battle_sim_config_from_squads(squad_a: Dictionary, squad_b: Dictionary) -> Dictionary:
	var result := {}
	for squad in [squad_a, squad_b]:
		var config = (squad as Dictionary).get("battle_sim_config", {})
		if not (config is Dictionary):
			continue
		for key in (config as Dictionary).keys():
			result[key] = (config as Dictionary).get(key)
	return result


func _mark_squad_engaged(record: Dictionary, encounter_id: String) -> void:
	record["state"] = "engaged"
	record["active_encounter_id"] = encounter_id
	record["last_encounter_id"] = encounter_id


func _current_tick_count() -> int:
	var runner := _get_sim_runner()
	if runner != null and runner.has_method("get_tick_count"):
		return int(runner.call("get_tick_count"))
	return 0


func _dictionary_from_state(state: Dictionary, key: String) -> Dictionary:
	var value = state.get(key, {})
	return value.duplicate(true) if value is Dictionary else {}


func _encounter_log_from_state(state: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var source = state.get("encounter_log", [])
	if not (source is Array):
		return result
	for entry in source:
		if entry is Dictionary:
			result.append(entry.duplicate(true))
	return result


func _append_encounter_log(encounter_log: Array[Dictionary], status: String, encounter_id: String, pair_key: String, message: String) -> void:
	var action := "encounter_resolution" if status == "resolving" or status == "resolved" else "encounter_detection"
	var log_id := 1
	if not encounter_log.is_empty():
		var previous_entry: Dictionary = encounter_log[encounter_log.size() - 1]
		log_id = int(previous_entry.get("log_id", encounter_log.size())) + 1
	encounter_log.append({
		"log_id": log_id,
		"status": status,
		"action": action,
		"encounter_id": encounter_id,
		"pair_key": pair_key,
		"message": message,
	})
	while encounter_log.size() > MAX_ENCOUNTER_LOG_ENTRIES:
		encounter_log.pop_front()


func _command_log_from_state(state: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var source = state.get("command_log", [])
	if not (source is Array):
		return result
	for entry in source:
		if entry is Dictionary:
			result.append(entry.duplicate(true))
	return result


func _append_command_log(command_log: Array[Dictionary], command: Dictionary, status: String, message: String) -> void:
	var log_id := 1
	if not command_log.is_empty():
		var previous_entry: Dictionary = command_log[command_log.size() - 1]
		log_id = int(previous_entry.get("log_id", command_log.size())) + 1
	command_log.append({
		"log_id": log_id,
		"status": status,
		"command_id": str(command.get("command_id", "")),
		"action": str(command.get("action", "")),
		"message": message,
	})
	while command_log.size() > MAX_COMMAND_LOG_ENTRIES:
		command_log.pop_front()


func _string_array(value) -> Array[String]:
	var result: Array[String] = []
	if not (value is Array) and not (value is PackedStringArray):
		return result
	for item in value:
		var text := str(item).strip_edges()
		if not text.is_empty():
			result.append(text)
	return result


func _record_location(record: Dictionary) -> Vector3:
	return _location_value(record.get("location", Vector3.ZERO), Vector3.ZERO)


func _record_target_location(record: Dictionary, current_location: Vector3) -> Vector3:
	if record.has("target_location"):
		return _location_value(record.get("target_location"), current_location)
	var route = record.get("route", [])
	if route is Array and route.size() >= 2:
		return _location_value(route[1], current_location)
	return current_location


func _objective_target_location(record: Dictionary, command: Dictionary, current_location: Vector3, objective_id: String) -> Vector3:
	if command.has("target_location"):
		return _location_value(command.get("target_location"), current_location)
	if objective_id == "return_home":
		return _location_value(record.get("home_location", current_location), current_location)
	return current_location


func _location_value(value, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value
	if value is Vector2:
		return Vector3(value.x, fallback.y, value.y)
	return fallback


func _xz_distance(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x, first.z).distance_to(Vector2(second.x, second.z))


func _command_from_squad_record(record: Dictionary) -> Dictionary:
	return {
		"command_id": str(record.get("command_id", "")),
		"action": str(record.get("command_action", "")),
		"squad_id": str(record.get("squad_id", "")),
		"objective_id": str(record.get("objective_id", "")),
	}


func _world_squad_templates() -> Array[Resource]:
	var result: Array[Resource] = []
	if world_definition == null:
		return result
	var templates = world_definition.get("squad_templates")
	if not (templates is Array):
		return result
	for template in templates:
		if template is Resource:
			result.append(template)
	return result


func _settlement_locations_by_faction_id() -> Dictionary:
	var result := {}
	if world_definition == null:
		return result
	var placements = world_definition.get("settlement_placements")
	if not (placements is Array):
		return result
	for placement in placements:
		if not (placement is Resource):
			continue
		var settlement_definition := placement.get("settlement_definition") as Resource
		var faction_id := _settlement_faction_id(settlement_definition)
		if faction_id.is_empty() or result.has(faction_id):
			continue
		result[faction_id] = _placement_world_position(placement)
	return result


func _settlement_faction_id(settlement_definition: Resource) -> String:
	if settlement_definition == null:
		return ""
	if settlement_definition.has_method("get_faction_id"):
		return str(settlement_definition.call("get_faction_id")).strip_edges()
	var faction_definition := settlement_definition.get("faction_definition") as Resource
	return _resource_id(faction_definition)


func _placement_world_position(placement: Resource) -> Vector3:
	var transform_value = placement.get("world_transform")
	if transform_value is Transform3D:
		var world_transform: Transform3D = transform_value
		return world_transform.origin
	var settlement_definition := placement.get("settlement_definition") as Resource
	if settlement_definition != null:
		var position_value = settlement_definition.get("world_position")
		if position_value is Vector3:
			return position_value
	return Vector3.ZERO


func _squad_id_for_template(template: Resource, index: int) -> String:
	var template_id := _resource_id(template)
	if template_id.is_empty():
		template_id = "squad_%02d" % index
	return "%s:%s" % [squad_id_prefix, template_id]


func _member_ids_for_squad_template(squad_id: String, template: Resource, member_count: int) -> Array[String]:
	var result: Array[String] = []
	var template_id := _resource_id(template)
	if template_id.is_empty():
		template_id = squad_id.replace("%s:" % squad_id_prefix, "")
	for member_index in range(maxi(0, member_count)):
		result.append("%s:%s:%02d" % [member_id_prefix, template_id, member_index + 1])
	return result


func _template_faction_id(template: Resource) -> String:
	if template != null and template.has_method("get_faction_id"):
		return str(template.call("get_faction_id")).strip_edges()
	var faction_definition := template.get("faction_definition") as Resource if template != null else null
	return _resource_id(faction_definition)


func _resource_id(resource: Resource) -> String:
	if resource != null and resource.has_method("get_id"):
		return str(resource.call("get_id")).strip_edges()
	return ""


func _resource_int(resource: Resource, property_name: String, default_value: int) -> int:
	if resource == null:
		return default_value
	var value = resource.get(property_name)
	return default_value if value == null else int(value)


func _resource_float(resource: Resource, property_name: String, default_value: float) -> float:
	if resource == null:
		return default_value
	var value = resource.get(property_name)
	return default_value if value == null else float(value)


func _resource_string(resource: Resource, property_name: String, default_value: String) -> String:
	return str(resource.get(property_name)).strip_edges() if resource != null else default_value


func _resource_string_array(resource: Resource, property_name: String) -> Array[String]:
	if resource == null:
		return []
	return _string_array(resource.get(property_name))


func _safe_node_name(value: String) -> String:
	var result := ""
	for index in range(value.length()):
		var character := value.substr(index, 1)
		if character.is_valid_identifier() or character.is_valid_int():
			result += character
		else:
			result += "_"
	return result if not result.is_empty() else "record"


func _world_definition_id() -> String:
	if world_definition != null and world_definition.has_method("get_id"):
		return str(world_definition.call("get_id")).strip_edges()
	return ""


func _world_definition_path() -> String:
	return str(world_definition.resource_path) if world_definition != null else ""


func _find_world_definition() -> Resource:
	if root_scene != null:
		var loader := root_scene.get_node_or_null("WorldLoader")
		if loader != null:
			var definition = loader.get("world_definition")
			if definition is Resource:
				return definition
	if is_inside_tree():
		var tree := get_tree()
		if tree != null:
			for node in tree.get_nodes_in_group("world_loader"):
				var definition = node.get("world_definition")
				if definition is Resource:
					return definition
	return null


func _find_gecs_world_controller() -> Node:
	if not is_inside_tree():
		return null
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("GecsWorldController")
		if local != null:
			return local
	var tree := get_tree()
	if tree == null:
		return null
	var existing := tree.get_first_node_in_group("gecs_world_controller")
	if existing != null and (parent_node == null or existing.get_parent() == parent_node):
		return existing
	return null


func _set_active_ecs_world() -> void:
	var ecs_singleton := get_node_or_null("/root/ECS")
	if ecs_singleton != null:
		ecs_singleton.set("world", _ecs_world)


func _get_sim_runner() -> Node:
	if _sim_runner != null and is_instance_valid(_sim_runner):
		return _sim_runner
	_sim_runner = _find_sim_runner()
	return _sim_runner


func _find_sim_runner() -> Node:
	var direct := get_node_or_null("FixedTickSimRunner")
	if _is_sim_runner_candidate(direct):
		return direct
	var sibling := get_node_or_null("../WorldMapCombatFixedTickRunner")
	if _is_sim_runner_candidate(sibling):
		return sibling
	for child in get_children():
		if _is_sim_runner_candidate(child):
			return child
	var parent := get_parent()
	if parent != null:
		for child in parent.get_children():
			if child == self:
				continue
			if _is_sim_runner_candidate(child):
				return child
	return null


func _is_sim_runner_candidate(node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var node_name := str(node.name)
	return node_name == "FixedTickSimRunner" or node_name == "WorldMapCombatFixedTickRunner" or node.is_in_group("fixed_tick_sim_runner")
