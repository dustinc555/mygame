extends Node

class_name DoorController

const SERVICE_ID := &"doors"

const ENTITY_SCRIPT := preload("res://addons/gecs/ecs/entity.gd")
const C_DOOR_STATE := preload("res://features/doors/sim/c_game_door_state.gd")
const C_DOOR_COMMAND := preload("res://features/doors/sim/c_game_door_command.gd")
const GAME_DOOR_SYSTEM := preload("res://features/doors/sim/game_door_system.gd")
const DOOR_LOCK_RULES := preload("res://features/doors/sim/door_lock_rules.gd")
const SKILL_RULES := preload("res://features/skills/sim/skill_rules.gd")

## How long door-state drift may stand mid-business before the keeper is sent.
## Variable rather than const so validation can shorten the wait.
var keeper_reconcile_delay_seconds := 20.0

var _context: BootstrapContext
var _gecs_world: Node
var _world_time: Node
var _door_entity_by_id := {}
var _command_entity_by_id := {}
var _pending_building_config := {}
var _door_system

signal door_state_changed(door_id: String, state: Dictionary)
signal door_command_resolved(result: Dictionary)
signal scheduled_door_action_requested(actor_id: String, door_id: String, action: String)


func initialize(context: BootstrapContext) -> void:
	_context = context
	_gecs_world = context.require(&"gecs_world")
	_world_time = context.get_optional(&"world_time")
	if _world_time != null and not _world_time.hour_changed.is_connected(_on_world_hour_changed):
		_world_time.hour_changed.connect(_on_world_hour_changed)
	_ensure_system()


func register_door(record: Dictionary) -> Dictionary:
	_ensure_system()
	var door_id := str(record.get("door_id", "")).strip_edges()
	if door_id.is_empty() or _gecs_world == null or _gecs_world.world == null:
		return {}
	var entity = _door_entity_by_id.get(door_id)
	var created := entity == null or not is_instance_valid(entity)
	if created:
		entity = _gecs_world.world.get_entity_by_id(_door_entity_id(door_id))
	if entity == null or not is_instance_valid(entity):
		entity = ENTITY_SCRIPT.new()
		entity.name = "Door_%s" % _sanitize_id(door_id)
		entity.id = _door_entity_id(door_id)
		_gecs_world.world.add_entity(entity, [C_DOOR_STATE.new()])
	_door_entity_by_id[door_id] = entity
	var state = entity.get_component(C_DOOR_STATE)
	if state == null:
		return {}
	if created:
		state.door_id = door_id
		state.building_id = str(record.get("building_id", ""))
		state.is_locked = bool(record.get("default_locked", false))
		state.is_open = bool(record.get("default_open", false)) and not state.is_locked
		state.lock_tier_id = str(record.get("lock_tier_id", "easy"))
		state.exit_policy = str(record.get("exit_policy", "free_exit"))
		state.authorized_actor_ids = PackedStringArray(record.get("authorized_actor_ids", []))
		state.authorized_faction_ids = PackedStringArray(record.get("authorized_faction_ids", []))
		state.authorized_key_ids = PackedStringArray(record.get("authorized_key_ids", []))
		state.close_behavior = str(record.get("close_behavior", "stay_open"))
		state.auto_close_delay_seconds = maxf(0.0, float(record.get("auto_close_delay_seconds", 0.0)))
		state.scheduled_actor_id = str(record.get("scheduled_actor_id", ""))
		state.scheduled_open_hour = int(record.get("scheduled_open_hour", -1))
		state.scheduled_close_hour = int(record.get("scheduled_close_hour", -1))
		state.kept_open = bool(record.get("kept_open", false))
	state.interaction_side_a = record.get("interaction_side_a", state.interaction_side_a)
	state.interaction_side_b = record.get("interaction_side_b", state.interaction_side_b)
	state.interaction_radius = maxf(0.1, float(record.get("interaction_radius", state.interaction_radius)))
	state.is_realized = true
	if _pending_building_config.has(state.building_id):
		_apply_building_config(state, _pending_building_config[state.building_id])
	elif created:
		_apply_business_hours_state(state)
	return get_door_state(door_id)


## Facilities own door semantics for their building: staff authorization, the
## keeper (bartender/shopkeeper), business hours, and whether the door stands
## open during them. Config is remembered so it also applies to doors that
## register after the facility wires itself up.
func configure_building_doors(building_id: String, config: Dictionary) -> void:
	if building_id.is_empty():
		return
	_pending_building_config[building_id] = config
	for door_id in _door_entity_by_id.keys():
		var state = _get_door_component(str(door_id))
		if state != null and state.building_id == building_id:
			_apply_building_config(state, config)


func _apply_building_config(state, config: Dictionary) -> void:
	var keeper_actor_id := str(config.get("keeper_actor_id", ""))
	if config.has("authorized_actor_ids"):
		state.authorized_actor_ids = PackedStringArray(config.get("authorized_actor_ids", []))
	if config.has("authorized_faction_ids"):
		state.authorized_faction_ids = PackedStringArray(config.get("authorized_faction_ids", []))
	if bool(config.get("public_access", false)):
		# Public use removes entry restrictions, but the keeper still needs
		# authority for the scheduled lock/unlock ceremony.
		state.authorized_actor_ids = PackedStringArray([keeper_actor_id]) if not keeper_actor_id.is_empty() else PackedStringArray()
		state.authorized_faction_ids = PackedStringArray()
	if config.has("keeper_actor_id"):
		state.scheduled_actor_id = keeper_actor_id
	if config.has("open_hour"):
		state.scheduled_open_hour = int(config.get("open_hour"))
	if config.has("close_hour"):
		state.scheduled_close_hour = int(config.get("close_hour"))
	if config.has("kept_open"):
		state.kept_open = bool(config.get("kept_open"))
	var initial_state_changed := false
	if state.state_revision == 0 and config.has("initial_state"):
		var initial_state := str(config.get("initial_state", "door_default"))
		var initial_open: bool = state.is_open
		var initial_locked: bool = state.is_locked
		match initial_state:
			"open":
				initial_open = true
				initial_locked = false
			"closed":
				initial_open = false
				initial_locked = false
			"locked":
				initial_open = false
				initial_locked = true
		if state.is_open != initial_open or state.is_locked != initial_locked:
			state.is_open = initial_open
			state.is_locked = initial_locked
			initial_state_changed = true
	if initial_state_changed:
		_commit_state_change(state)
	_apply_business_hours_state(state)


## Spawn/config-time reconcile: a bar materializing at noon must not present
## a locked front door, and one materializing at midnight must not stand open.
## Runtime drift is fixed by the keeper ceremony instead, never snapped.
func _apply_business_hours_state(state) -> void:
	if state.scheduled_open_hour < 0 or state.scheduled_close_hour < 0:
		return
	var changed := false
	if _within_business_hours(state):
		if state.is_locked:
			state.is_locked = false
			changed = true
		if state.kept_open and not state.is_open:
			state.is_open = true
			changed = true
	elif state.is_open or not state.is_locked:
		state.is_open = false
		state.is_locked = true
		changed = true
	if changed:
		_commit_state_change(state)


func _within_business_hours(state) -> bool:
	if state.scheduled_open_hour < 0 or state.scheduled_close_hour < 0 or _world_time == null:
		return false
	var hour := int(_world_time.get_hour())
	if state.scheduled_open_hour <= state.scheduled_close_hour:
		return hour >= state.scheduled_open_hour and hour < state.scheduled_close_hour
	return hour >= state.scheduled_open_hour or hour < state.scheduled_close_hour


func mark_door_unrealized(door_id: String) -> void:
	var state = _get_door_component(door_id)
	if state != null:
		state.is_realized = false


func get_door_state(door_id: String) -> Dictionary:
	var state = _get_door_component(door_id)
	return _state_to_dictionary(state) if state != null else {}


func submit_command(actor_id: String, door_id: String, action_name: String, actor_snapshot: Dictionary = {}, expected_state_revision := -1) -> Dictionary:
	_ensure_system()
	var state = _get_door_component(door_id)
	if state == null:
		return {"accepted": false, "result_code": "door_missing"}
	if not state.is_realized:
		return {"accepted": false, "result_code": "door_unrealized"}
	if _gecs_world == null or _gecs_world.world == null or _gecs_world.world.get_entity_by_id("actor:%s" % actor_id) == null:
		return {"accepted": false, "result_code": "actor_missing"}
	var action := _action_from_name(action_name)
	if action < 0:
		return {"accepted": false, "result_code": "invalid_action"}
	if not state.active_command_id.is_empty():
		return {"accepted": false, "result_code": "door_busy"}
	var command_id := "%s:%d" % [door_id, state.next_command_sequence]
	state.next_command_sequence += 1
	var entity = ENTITY_SCRIPT.new()
	entity.name = "DoorCommand_%s" % _sanitize_id(command_id)
	entity.id = "door_command:%s" % command_id
	var command = C_DOOR_COMMAND.new()
	command.command_id = command_id
	command.door_id = door_id
	command.actor_id = actor_id
	command.action = action
	command.expected_state_revision = expected_state_revision
	command.lockpick_skill_level = maxf(0.0, float(actor_snapshot.get("lockpick_skill_level", 0.0)))
	command.assisting_attribute_level = maxf(0.0, float(actor_snapshot.get("assisting_attribute_level", 0.0)))
	command.actor_faction_id = str(actor_snapshot.get("actor_faction_id", ""))
	command.active_law_response = bool(actor_snapshot.get("active_law_response", false))
	command.actor_key_ids = PackedStringArray(actor_snapshot.get("actor_key_ids", []))
	command.has_required_lockpick = bool(actor_snapshot.get("has_required_lockpick", false))
	command.from_inside = bool(actor_snapshot.get("from_inside", false))
	_gecs_world.world.add_entity(entity, [command])
	_command_entity_by_id[command_id] = entity
	state.active_command_id = command_id
	return {"accepted": true, "command_id": command_id, "phase": command.phase}


func begin_command(command_id: String) -> Dictionary:
	var entity = _command_entity_by_id.get(command_id)
	if entity == null or not is_instance_valid(entity):
		return {"started": false, "result_code": "command_missing"}
	var command = entity.get_component(C_DOOR_COMMAND)
	var state = _get_door_component(command.door_id) if command != null else null
	if command == null or state == null:
		return {"started": false, "result_code": "door_missing"}
	if command.phase != command.Phase.APPROACHING:
		return {"started": false, "result_code": "invalid_phase"}
	command.phase = command.Phase.PERFORMING
	command.remaining_seconds = DOOR_LOCK_RULES.get_attempt_duration_seconds() if command.action == command.Action.LOCKPICK else 0.0
	return {"started": true, "command_id": command.command_id, "remaining_seconds": command.remaining_seconds}


func cancel_command(command_id: String, result_code := "cancelled") -> void:
	var entity = _command_entity_by_id.get(command_id)
	if entity == null or not is_instance_valid(entity):
		return
	var command = entity.get_component(C_DOOR_COMMAND)
	if command != null:
		command.phase = command.Phase.CANCELLED
		command.result_code = result_code
		_finish_command(entity, command, _get_door_component(command.door_id))


func resolve_performing_command(entity, command) -> void:
	var state = _get_door_component(command.door_id)
	if state == null:
		command.phase = command.Phase.FAILED
		command.result_code = "door_missing"
		_finish_command(entity, command, null)
		return
	if command.expected_state_revision >= 0 and command.expected_state_revision != state.state_revision:
		command.phase = command.Phase.FAILED
		command.result_code = "stale_state"
		_finish_command(entity, command, state)
		return
	match command.action:
		command.Action.OPEN:
			_resolve_open(command, state)
		command.Action.CLOSE:
			_resolve_close(command, state)
		command.Action.LOCK:
			_resolve_lock(command, state)
		command.Action.UNLOCK:
			_resolve_unlock(command, state)
		command.Action.LOCKPICK:
			_resolve_lockpick(command, state)
	_finish_command(entity, command, state)


func _resolve_open(command, state) -> void:
	if state.exit_policy == "authorized_exit" and command.from_inside and not _has_authorized_access(command, state):
		_fail(command, "exit_denied")
		return
	if state.is_locked:
		if state.exit_policy == "free_exit" and command.from_inside:
			# A free-exit lock binds from the outside only: leaving is always
			# possible, and the door re-locks behind the leaver on close.
			state.is_locked = false
			state.relock_on_close = true
		else:
			_fail(command, "locked")
			return
	if state.is_open:
		_resolve(command, "already_open")
		return
	state.is_open = true
	_commit_state_change(state)
	_resolve(command, "opened")


func _resolve_close(command, state) -> void:
	if not state.is_open:
		_resolve(command, "already_closed")
		return
	state.is_open = false
	if state.relock_on_close:
		state.relock_on_close = false
		state.is_locked = true
	_commit_state_change(state)
	_resolve(command, "closed")


func _resolve_lock(command, state) -> void:
	if state.is_open:
		_fail(command, "must_close_before_locking")
		return
	if not _has_authorized_access(command, state):
		_fail(command, "access_denied")
		return
	if state.is_locked:
		_resolve(command, "already_locked")
		return
	state.is_locked = true
	_commit_state_change(state)
	_resolve(command, "locked")


func _resolve_unlock(command, state) -> void:
	if not state.is_locked:
		_resolve(command, "already_unlocked")
		return
	if not _has_authorized_access(command, state):
		_fail(command, "access_denied")
		return
	state.is_locked = false
	state.relock_on_close = false
	_commit_state_change(state)
	_resolve(command, "unlocked")


func _resolve_lockpick(command, state) -> void:
	if not state.is_locked:
		_resolve(command, "already_unlocked")
		return
	if not DOOR_LOCK_RULES.can_attempt(state.lock_tier_id, command.lockpick_skill_level, command.has_required_lockpick):
		_fail(command, "lockpick_ineligible")
		return
	command.result_chance = DOOR_LOCK_RULES.get_success_chance(state.lock_tier_id, command.lockpick_skill_level, command.assisting_attribute_level)
	command.result_roll = DOOR_LOCK_RULES.roll(command.command_id)
	var passed: bool = command.result_roll <= command.result_chance
	command.result_xp = SKILL_RULES.get_chance_check_xp(command.result_chance, passed)
	command.lockpick_broke = not passed and DOOR_LOCK_RULES.roll_tool_break(command.command_id) <= float(DOOR_LOCK_RULES.LOCKPICKING_CHECK.get("tool_break_chance_on_failure"))
	if passed:
		state.is_locked = false
		_commit_state_change(state)
		_resolve(command, "lockpicked")
	else:
		_fail(command, "lockpick_failed")


func _has_authorized_access(command, state) -> bool:
	return command.active_law_response or state.authorized_actor_ids.has(command.actor_id) or state.authorized_faction_ids.has(command.actor_faction_id) or _contains_shared_value(state.authorized_key_ids, command.actor_key_ids)


func _contains_shared_value(required_values: PackedStringArray, candidate_values: PackedStringArray) -> bool:
	for value in required_values:
		if candidate_values.has(value):
			return true
	return false


func _resolve(command, result_code: String) -> void:
	command.phase = command.Phase.RESOLVED
	command.result_code = result_code


func _fail(command, result_code: String) -> void:
	command.phase = command.Phase.FAILED
	command.result_code = result_code


func _commit_state_change(state) -> void:
	state.state_revision += 1
	door_state_changed.emit(state.door_id, _state_to_dictionary(state))
	_schedule_keeper_reconcile(state)


## Custodianship without ticking: drift (someone shut the front door
## mid-business) arms one one-shot timer; when it fires the keeper is sent
## only if the door is still wrong. Outside business hours this never arms,
## so a 3am lockpick wakes nobody — that is law and order's problem.
func _schedule_keeper_reconcile(state) -> void:
	if state.keeper_reconcile_armed or state.scheduled_actor_id.is_empty() or not _needs_keeper_attention(state):
		return
	state.keeper_reconcile_armed = true
	get_tree().create_timer(keeper_reconcile_delay_seconds).timeout.connect(_on_keeper_reconcile_timeout.bind(state.door_id))


func _on_keeper_reconcile_timeout(door_id: String) -> void:
	var state = _get_door_component(door_id)
	if state == null:
		return
	state.keeper_reconcile_armed = false
	if not state.is_realized or not state.active_command_id.is_empty() or not _needs_keeper_attention(state):
		return
	scheduled_door_action_requested.emit(state.scheduled_actor_id, door_id, "unlock" if state.is_locked else "open")


func _needs_keeper_attention(state) -> bool:
	if not state.kept_open or not _within_business_hours(state):
		return false
	return state.is_locked or not state.is_open


func _on_world_hour_changed(_absolute_hour: int, _day_index: int, hour: int) -> void:
	for door_id in _door_entity_by_id.keys():
		var state = _get_door_component(str(door_id))
		if state == null or not state.is_realized or not state.active_command_id.is_empty():
			continue
		var opens: bool = state.scheduled_open_hour >= 0 and hour == state.scheduled_open_hour
		var closes: bool = state.scheduled_close_hour >= 0 and hour == state.scheduled_close_hour
		if not opens and not closes:
			continue
		if state.scheduled_actor_id.is_empty():
			# No keeper to perform the ceremony: the building flips its own
			# lock state at the hour.
			if opens:
				var changed := false
				if state.is_locked:
					state.is_locked = false
					changed = true
				if state.kept_open and not state.is_open:
					state.is_open = true
					changed = true
				if changed:
					_commit_state_change(state)
			elif closes and (state.is_open or not state.is_locked):
				state.is_open = false
				state.is_locked = true
				_commit_state_change(state)
			continue
		if opens:
			if state.is_locked:
				scheduled_door_action_requested.emit(state.scheduled_actor_id, state.door_id, "unlock")
			elif not state.is_open:
				scheduled_door_action_requested.emit(state.scheduled_actor_id, state.door_id, "open")
		elif closes and (state.is_open or not state.is_locked):
			scheduled_door_action_requested.emit(state.scheduled_actor_id, state.door_id, "lock")


func _finish_command(entity, command, state) -> void:
	if state != null and state.active_command_id == command.command_id:
		state.active_command_id = ""
	var result := {
		"command_id": command.command_id,
		"door_id": command.door_id,
		"actor_id": command.actor_id,
		"action": _action_name(command.action),
		"phase": command.phase,
		"result_code": command.result_code,
		"chance": command.result_chance,
		"roll": command.result_roll,
		"skill_xp": command.result_xp,
		"lockpick_broke": command.lockpick_broke,
	}
	door_command_resolved.emit(result)
	# A command that finished without fixing the kept state (cancelled,
	# failed, or the door was re-shut) re-arms the keeper so the door cannot
	# silently stay wrong until the next unrelated state change.
	if state != null:
		_schedule_keeper_reconcile(state)
	_command_entity_by_id.erase(command.command_id)
	if _gecs_world != null and _gecs_world.world != null and entity != null and is_instance_valid(entity):
		_gecs_world.world.remove_entity(entity)


func _get_door_component(door_id: String):
	if door_id.is_empty() or _gecs_world == null or _gecs_world.world == null:
		return null
	var entity = _door_entity_by_id.get(door_id)
	if entity == null or not is_instance_valid(entity):
		entity = _gecs_world.world.get_entity_by_id(_door_entity_id(door_id))
		if entity != null:
			_door_entity_by_id[door_id] = entity
	return entity.get_component(C_DOOR_STATE) if entity != null and is_instance_valid(entity) else null


func _ensure_system() -> void:
	if _door_system != null or _gecs_world == null or _gecs_world.world == null:
		return
	_door_system = GAME_DOOR_SYSTEM.new()
	_door_system.name = "GameDoorSystem"
	_door_system.controller = self
	_gecs_world.world.add_system(_door_system)
	_gecs_world.world.finalize_system_setup()


func _state_to_dictionary(state) -> Dictionary:
	return {
		"door_id": state.door_id,
		"building_id": state.building_id,
		"is_open": state.is_open,
		"is_locked": state.is_locked,
		"lock_tier_id": state.lock_tier_id,
		"exit_policy": state.exit_policy,
		"relock_on_close": state.relock_on_close,
		"kept_open": state.kept_open,
		"authorized_actor_ids": state.authorized_actor_ids,
		"authorized_faction_ids": state.authorized_faction_ids,
		"authorized_key_ids": state.authorized_key_ids,
		"close_behavior": state.close_behavior,
		"auto_close_delay_seconds": state.auto_close_delay_seconds,
		"scheduled_actor_id": state.scheduled_actor_id,
		"scheduled_open_hour": state.scheduled_open_hour,
		"scheduled_close_hour": state.scheduled_close_hour,
		"state_revision": state.state_revision,
		"is_realized": state.is_realized,
		"active_command_id": state.active_command_id,
	}


func _door_entity_id(door_id: String) -> String:
	return "door:%s" % door_id


func _action_from_name(action_name: String) -> int:
	match action_name.to_lower():
		"open": return C_DOOR_COMMAND.Action.OPEN
		"close": return C_DOOR_COMMAND.Action.CLOSE
		"lock": return C_DOOR_COMMAND.Action.LOCK
		"unlock": return C_DOOR_COMMAND.Action.UNLOCK
		"lockpick": return C_DOOR_COMMAND.Action.LOCKPICK
	return -1


func _action_name(action: int) -> String:
	match action:
		C_DOOR_COMMAND.Action.OPEN: return "open"
		C_DOOR_COMMAND.Action.CLOSE: return "close"
		C_DOOR_COMMAND.Action.LOCK: return "lock"
		C_DOOR_COMMAND.Action.UNLOCK: return "unlock"
		C_DOOR_COMMAND.Action.LOCKPICK: return "lockpick"
	return "unknown"


func _sanitize_id(value: String) -> String:
	var result := ""
	for index in range(value.length()):
		var character := value.substr(index, 1)
		result += character if character.to_lower() >= "a" and character.to_lower() <= "z" or character >= "0" and character <= "9" else "_"
	return result
