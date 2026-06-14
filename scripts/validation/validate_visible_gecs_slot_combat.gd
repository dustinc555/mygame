extends SceneTree

const C_NODE_PATH := "res://scripts/ecs/components/c_game_actor_node.gd"
const C_IDENTITY_PATH := "res://scripts/ecs/components/c_game_actor_identity.gd"
const C_SPATIAL_PATH := "res://scripts/ecs/components/c_game_actor_spatial.gd"
const C_VITALS_PATH := "res://scripts/ecs/components/c_game_actor_vitals.gd"
const C_CONFIG_PATH := "res://scripts/ecs/components/c_game_combat_config.gd"
const C_STATE_PATH := "res://scripts/ecs/components/c_game_combat_state.gd"
const C_SLOT_PATH := "res://scripts/ecs/components/c_game_combat_slot_state.gd"
const C_ACTION_PATH := "res://scripts/ecs/components/c_game_combat_action.gd"
const GAME_COMBAT_SLOT_SYSTEM_PATH := "res://scripts/ecs/systems/game_combat_slot_system.gd"
const GAME_COMBAT_RESOLUTION_SYSTEM_PATH := "res://scripts/ecs/systems/game_combat_resolution_system.gd"
const SLOT_STATE_NONE := 0
const SLOT_STATE_MOVE_TO_TARGET := 1
const SLOT_STATE_FIGHTING := 3
const SLOT_STATE_WAITING := 4

var C_NODE
var C_IDENTITY
var C_SPATIAL
var C_VITALS
var C_CONFIG
var C_STATE
var C_SLOT
var C_ACTION
var GAME_COMBAT_SLOT_SYSTEM
var GAME_COMBAT_RESOLUTION_SYSTEM


class TestCombatActor:
	extends Node3D

	var stable_id := ""
	var started_count := 0
	var received_count := 0
	var _system_combat_action_active := false
	var _system_combat_reaction_remaining := 0.0
	var _system_combat_cooldown_remaining := 0.0
	var _system_combat_focus_id := 0

	func get_system_combat_attack_spec() -> Dictionary:
		return {
			"animation_names": PackedStringArray(),
			"attack_id": "test",
			"hit_reaction_names": PackedStringArray(),
			"total_seconds": 0.08,
			"first_clip_seconds": 0.0,
			"impact_seconds": 0.01,
		}

	func on_system_combat_attack_started(_target_actor: Node, _animation_names: PackedStringArray) -> float:
		started_count += 1
		return 0.0

	func prepare_system_combat_receive_attack(_attacker: Node, _blunt_damage: float, _cut_damage: float) -> Dictionary:
		return {"accepted": true, "can_actively_defend": false}

	func transform_system_incoming_damage(_attacker: Node, blunt_damage: float, cut_damage: float) -> Dictionary:
		return {"blunt_damage": blunt_damage, "cut_damage": cut_damage}

	func clamp_system_final_combat_damage(_attacker: Node, blunt_damage: float, cut_damage: float) -> Dictionary:
		return {"blunt_damage": blunt_damage, "cut_damage": cut_damage}

	func handle_system_combat_resolution(_attacker: Node, _outcome: String, _attack_id: String, _hit_reaction_names: PackedStringArray, _is_critical: bool, _has_shield_block: bool, _final_blunt: float, _final_cut: float, _can_actively_defend := true) -> float:
		received_count += 1
		return 0.0


var _failures: Array[String] = []
var _actors: Array[Node] = []
var _registered_ecs_singleton := false
var _ecs_placeholder: Node


func _initialize() -> void:
	_ensure_direct_script_ecs_singleton()
	_load_scripts()
	call_deferred("_run")


func _run() -> void:
	_test_slot_assignment_caps_and_spreads_waiters()
	_test_no_slot_no_attack()
	_test_valid_slot_starts_one_side()
	_test_symmetric_duel_keeps_alternating()
	_test_out_of_range_returns_to_move_to_target()
	_test_leash_blocks_impact()
	_cleanup_actors()
	_clear_script_refs()
	_cleanup_direct_script_ecs_singleton()
	if _failures.is_empty():
		print("VISIBLE_GECS_SLOT_COMBAT_VALIDATION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("VISIBLE_GECS_SLOT_COMBAT_VALIDATION_FAILED count=%d" % _failures.size())
	quit(1)


func _test_slot_assignment_caps_and_spreads_waiters() -> void:
	var target := _make_record("target", Vector3.ZERO)
	target["config"].active_attack_slots = 3
	var records: Array[Dictionary] = [target]
	for index in range(5):
		var angle := TAU * float(index) / 5.0
		var attacker := _make_record("attacker_%d" % index, Vector3(cos(angle), 0.0, sin(angle)) * 0.9)
		attacker["state"].current_target_actor_id = "target"
		records.append(attacker)
	var slot_system = GAME_COMBAT_SLOT_SYSTEM.new()
	slot_system._process_pairs(_slot_components(records))
	slot_system.free()
	var active_count := 0
	var waiting_count := 0
	var occupied := {}
	var wait_positions: Array[Vector3] = []
	for index in range(1, records.size()):
		var slot = records[index]["slot"]
		if int(slot.slot_state) == SLOT_STATE_FIGHTING:
			active_count += 1
			occupied[int(slot.slot_index)] = true
		elif int(slot.slot_state) == SLOT_STATE_WAITING:
			waiting_count += 1
			wait_positions.append(slot.wait_position)
	if active_count != 3:
		_failures.append("expected_three_active_slots got=%d" % active_count)
	if waiting_count != 2:
		_failures.append("expected_two_waiters got=%d" % waiting_count)
	for slot_index in range(3):
		if not bool(occupied.get(slot_index, false)):
			_failures.append("missing_active_slot_index_%d" % slot_index)
	if wait_positions.size() == 2 and wait_positions[0].distance_to(wait_positions[1]) <= 0.1:
		_failures.append("waiters_should_not_stack distance=%.3f" % wait_positions[0].distance_to(wait_positions[1]))
	_cleanup_actors()


func _test_symmetric_duel_keeps_alternating() -> void:
	# Regression for the "stuck staring at each other, never attacking" deadlock: a clean 1v1 where
	# BOTH fighters hold a FIGHTING slot pointing at the other. The turn token must live on a single
	# canonical slot that both fighters read. The old per-slot token crossed after the first
	# exchange (each handed the turn to the partner on its OWN slot, which the partner never read),
	# leaving both blocked forever. Driving resolution for several seconds must keep both attacking.
	var a := _make_record("a", Vector3.ZERO)
	var b := _make_record("b", Vector3(0.9, 0.0, 0.0))
	_make_ready_slot(a, "b", 0, "a")
	_make_ready_slot(b, "a", 0, "b")
	var records: Array[Dictionary] = [a, b]
	var resolution = GAME_COMBAT_RESOLUTION_SYSTEM.new()
	for _step in range(80):
		resolution.process([], _resolution_components(records), 0.05)
	resolution.free()
	if a["actor"].started_count < 2:
		_failures.append("symmetric_duel_a_should_keep_attacking started=%d" % a["actor"].started_count)
	if b["actor"].started_count < 2:
		_failures.append("symmetric_duel_b_should_keep_attacking started=%d" % b["actor"].started_count)
	_cleanup_actors()


func _test_out_of_range_returns_to_move_to_target() -> void:
	var a := _make_record("a", Vector3(5.0, 0.0, 0.0))
	var b := _make_record("b", Vector3.ZERO)
	a["state"].current_target_actor_id = "b"
	_make_ready_slot(a, "b", 0, "a")
	var records: Array[Dictionary] = [a, b]
	var slot_system = GAME_COMBAT_SLOT_SYSTEM.new()
	slot_system._process_pairs(_slot_components(records))
	slot_system.free()
	if int(a["slot"].slot_state) != SLOT_STATE_MOVE_TO_TARGET or int(a["slot"].slot_index) != -1:
		_failures.append("out_of_range_should_return_to_move_to_target state=%d slot=%d" % [int(a["slot"].slot_state), int(a["slot"].slot_index)])
	_cleanup_actors()


func _test_no_slot_no_attack() -> void:
	var a := _make_record("a", Vector3.ZERO)
	var b := _make_record("b", Vector3(0.9, 0.0, 0.0))
	a["state"].current_target_actor_id = "b"
	b["state"].current_target_actor_id = "a"
	var records: Array[Dictionary] = [a, b]
	var resolution = GAME_COMBAT_RESOLUTION_SYSTEM.new()
	resolution.process([], _resolution_components(records), 0.1)
	resolution.free()
	if bool(a["action"].action_active) or bool(b["action"].action_active):
		_failures.append("no_slot_should_not_start_attack a=%s b=%s" % [str(a["action"].action_active), str(b["action"].action_active)])
	_cleanup_actors()


func _test_valid_slot_starts_one_side() -> void:
	var a := _make_record("a", Vector3.ZERO)
	var b := _make_record("b", Vector3(0.9, 0.0, 0.0))
	_make_ready_slot(a, "b", 0, "a")
	var records: Array[Dictionary] = [a, b]
	var resolution = GAME_COMBAT_RESOLUTION_SYSTEM.new()
	resolution.process([], _resolution_components(records), 0.1)
	resolution.free()
	if not bool(a["action"].action_active) or bool(b["action"].action_active):
		_failures.append("valid_slot_should_start_one_attack a=%s b=%s" % [str(a["action"].action_active), str(b["action"].action_active)])
	if a["actor"].started_count != 1 or b["actor"].started_count != 0:
		_failures.append("valid_slot_started_counts a=%d b=%d" % [a["actor"].started_count, b["actor"].started_count])
	_cleanup_actors()


func _test_leash_blocks_impact() -> void:
	var a := _make_record("a", Vector3.ZERO)
	var b := _make_record("b", Vector3(0.9, 0.0, 0.0))
	_make_ready_slot(a, "b", 0, "a")
	var records: Array[Dictionary] = [a, b]
	var resolution = GAME_COMBAT_RESOLUTION_SYSTEM.new()
	resolution.process([], _resolution_components(records), 0.05)
	a["spatial"].world_position = Vector3(5.0, 0.0, 0.0)
	b["spatial"].world_position = Vector3.ZERO
	a["actor"].global_position = a["spatial"].world_position
	b["actor"].global_position = b["spatial"].world_position
	resolution.process([], _resolution_components(records), 0.05)
	resolution.free()
	if a["actor"].received_count != 0 or b["actor"].received_count != 0:
		_failures.append("leash_broken_slot_should_block_impact a_received=%d b_received=%d" % [a["actor"].received_count, b["actor"].received_count])
	_cleanup_actors()


func _make_record(actor_id: String, position: Vector3) -> Dictionary:
	var actor := TestCombatActor.new()
	actor.name = actor_id
	actor.stable_id = actor_id
	actor.position = position
	root.add_child(actor)
	actor.global_position = position
	_actors.append(actor)
	var node = C_NODE.new()
	node.actor = actor
	node.instance_id = actor.get_instance_id()
	var identity = C_IDENTITY.new()
	identity.actor_id = actor_id
	identity.stable_id = actor_id
	var spatial = C_SPATIAL.new()
	spatial.world_position = position
	spatial.last_world_position = position
	spatial.position_initialized = true
	var vitals = C_VITALS.new()
	vitals.life_state = NpcRules.LifeState.ALIVE
	var config = C_CONFIG.new()
	config.attack_range = 1.15
	config.active_attack_slots = 3
	config.attack_cooldown_seconds = 0.1
	config.blunt_damage = 10.0
	config.cut_damage = 0.0
	config.hit_score = 100.0
	config.dodge_score = 0.0
	config.block_score = 0.0
	var state = C_STATE.new()
	var slot = C_SLOT.new()
	var action = C_ACTION.new()
	return {
		"actor": actor,
		"node": node,
		"identity": identity,
		"spatial": spatial,
		"vitals": vitals,
		"config": config,
		"state": state,
		"slot": slot,
		"action": action,
	}


func _make_ready_slot(record: Dictionary, target_actor_id: String, slot_index: int, tempo_actor_id: String) -> void:
	var slot = record["slot"]
	slot.slot_state = SLOT_STATE_FIGHTING
	slot.slot_target_actor_id = target_actor_id
	slot.slot_index = slot_index
	slot.slot_position = record["spatial"].world_position
	slot.wait_position = record["spatial"].world_position
	slot.engage_distance = 1.03
	slot.leash_distance = 1.88
	slot.tempo_actor_id = tempo_actor_id


func _slot_components(records: Array[Dictionary]) -> Array:
	return [
		_collect(records, "identity"),
		_collect(records, "spatial"),
		_collect(records, "vitals"),
		_collect(records, "config"),
		_collect(records, "state"),
		_collect(records, "slot"),
		_collect(records, "action"),
	]


func _resolution_components(records: Array[Dictionary]) -> Array:
	return [
		_collect(records, "node"),
		_collect(records, "identity"),
		_collect(records, "spatial"),
		_collect(records, "vitals"),
		_collect(records, "config"),
		_collect(records, "action"),
		_collect(records, "slot"),
	]


func _collect(records: Array[Dictionary], key: String) -> Array:
	var values := []
	for record in records:
		values.append(record[key])
	return values


func _cleanup_actors() -> void:
	for actor in _actors:
		if actor != null and is_instance_valid(actor):
			root.remove_child(actor)
			actor.free()
	_actors.clear()


func _ensure_direct_script_ecs_singleton() -> void:
	if Engine.has_singleton("ECS"):
		return
	var placeholder := Node.new()
	placeholder.name = "ECS"
	Engine.register_singleton("ECS", placeholder)
	_ecs_placeholder = placeholder
	_registered_ecs_singleton = true


func _cleanup_direct_script_ecs_singleton() -> void:
	if not _registered_ecs_singleton:
		return
	Engine.unregister_singleton("ECS")
	if _ecs_placeholder != null:
		_ecs_placeholder.free()
	_ecs_placeholder = null
	_registered_ecs_singleton = false


func _load_scripts() -> void:
	C_NODE = load(C_NODE_PATH)
	C_IDENTITY = load(C_IDENTITY_PATH)
	C_SPATIAL = load(C_SPATIAL_PATH)
	C_VITALS = load(C_VITALS_PATH)
	C_CONFIG = load(C_CONFIG_PATH)
	C_STATE = load(C_STATE_PATH)
	C_SLOT = load(C_SLOT_PATH)
	C_ACTION = load(C_ACTION_PATH)
	GAME_COMBAT_SLOT_SYSTEM = load(GAME_COMBAT_SLOT_SYSTEM_PATH)
	GAME_COMBAT_RESOLUTION_SYSTEM = load(GAME_COMBAT_RESOLUTION_SYSTEM_PATH)


func _clear_script_refs() -> void:
	C_NODE = null
	C_IDENTITY = null
	C_SPATIAL = null
	C_VITALS = null
	C_CONFIG = null
	C_STATE = null
	C_SLOT = null
	C_ACTION = null
	GAME_COMBAT_SLOT_SYSTEM = null
	GAME_COMBAT_RESOLUTION_SYSTEM = null
