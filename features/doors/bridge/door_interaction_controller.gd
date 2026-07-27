extends Node

class_name DoorInteractionController

const SERVICE_ID := &"door_interactions"
const APPROACH_TIMEOUT_MSEC := 30000
const DOOR_LOCK_RULES := preload("res://features/doors/sim/door_lock_rules.gd")
const SKILL_RULES := preload("res://features/skills/sim/skill_rules.gd")

var _context: BootstrapContext
var _doors: Node
var _gecs_world: Node
var _combat_responses: GameCombatResponseSystem
var _approaches_by_command_id := {}
var _command_info_by_id := {}
var _active_command_by_actor_door := {}
var _door_projection_by_id := {}


func initialize(context: BootstrapContext) -> void:
	_context = context
	_doors = context.require(&"doors")
	_gecs_world = context.require(&"gecs_world")
	_combat_responses = context.require(GameCombatResponseSystem.SERVICE_ID) as GameCombatResponseSystem
	if _doors != null and not _doors.door_command_resolved.is_connected(_on_door_command_resolved):
		_doors.door_command_resolved.connect(_on_door_command_resolved)
	if _doors != null and not _doors.scheduled_door_action_requested.is_connected(_on_scheduled_door_action_requested):
		_doors.scheduled_door_action_requested.connect(_on_scheduled_door_action_requested)
	set_physics_process(true)
	# Scene doors ready before the bootstrap's deferred controller pass, so
	# their own registration attempt found no service. Sweep them now.
	for door in get_tree().get_nodes_in_group("world_door"):
		if door.has_method("ensure_registered"):
			door.call("ensure_registered")


func register_door_projection(door: Node) -> void:
	var door_id := _door_id(door)
	if not door_id.is_empty():
		_door_projection_by_id[door_id] = weakref(door)


func unregister_door_projection(door_id: String, door: Node) -> void:
	var reference = _door_projection_by_id.get(door_id)
	if reference is WeakRef and reference.get_ref() == door:
		_door_projection_by_id.erase(door_id)


func request_world_action(door: Node, action: String, actors: Array) -> String:
	var accepted := 0
	for actor in actors:
		if actor is Node and request_actor_action(actor as Node, door, action, true):
			accepted += 1
	# Successful door use needs no announcement; only surface dead controls.
	return "" if accepted > 0 else "Door command unavailable."


## Any actor walking at a closed door opens it in stride: party members and
## NPCs alike. Lockpicking stays consent-gated for the party — auto-committing
## a crime because the player clicked through a doorway would be wrong.
func request_npc_auto_open(actor: Node, door: Node) -> bool:
	if actor == null or door == null or not _actor_is_trying_to_cross_door(actor, door):
		return false
	var actor_id := _actor_id(actor)
	var door_id := _door_id(door)
	if actor_id.is_empty() or door_id.is_empty() or _active_command_by_actor_door.has(_actor_door_key(actor_id, door_id)):
		return false
	var state: Dictionary = _doors.get_door_state(door_id)
	if bool(state.get("is_open", false)):
		return false
	var issued_by_player := _is_player_party_member(actor)
	var action := "open"
	if bool(state.get("is_locked", false)):
		var snapshot := _actor_snapshot(actor, door)
		# Never auto-lockpick: picking a lock is a deliberate act commissioned
		# by an explicit thief job or the player, not a pathing side effect.
		var free_exit_from_inside: bool = str(state.get("exit_policy", "free_exit")) == "free_exit" and bool(snapshot.get("from_inside", false))
		if _snapshot_has_authorized_access(snapshot, state, actor_id):
			action = "unlock"
		elif not free_exit_from_inside:
			return false
	return request_actor_action(actor, door, action, issued_by_player, _current_move_target(actor))


func request_actor_action(actor: Node, door: Node, action: String, issued_by_player := true, resume_target = null, follow_up_action := "") -> bool:
	if actor == null or door == null or _doors == null:
		return false
	var actor_id := _actor_id(actor)
	var door_id := _door_id(door)
	if actor_id.is_empty() or door_id.is_empty() or _active_command_by_actor_door.has(_actor_door_key(actor_id, door_id)):
		return false
	var submission: Dictionary = _doors.submit_command(actor_id, door_id, action, _actor_snapshot(actor, door))
	if not bool(submission.get("accepted", false)):
		return false
	var interaction_position := _closest_interaction_position(actor, door)
	if interaction_position == Vector3.INF:
		_doors.cancel_command(str(submission.get("command_id", "")), "interaction_position_missing")
		return false
	actor.call("set_move_target", interaction_position, issued_by_player)
	if not issued_by_player:
		if not _actor_move_target_matches(actor, interaction_position):
			# A genuine priority order (hauling a prisoner, combat) refused the
			# move; drop the command and let the keeper reconcile retry later.
			_doors.cancel_command(str(submission.get("command_id", "")), "actor_busy")
			return false
		_set_door_duty_order(actor, true)
	var command_id := str(submission.get("command_id", ""))
	var info := {
		"actor_id": actor_id,
		"door_id": door_id,
		"door": weakref(door),
		"action": action,
		"issued_by_player": issued_by_player,
		"interaction_position": interaction_position,
		"resume_target": resume_target,
		"follow_up_action": follow_up_action,
		"queued_at_msec": Time.get_ticks_msec(),
	}
	_approaches_by_command_id[command_id] = info
	_command_info_by_id[command_id] = info
	_active_command_by_actor_door[_actor_door_key(actor_id, door_id)] = command_id
	return true


func _physics_process(_delta: float) -> void:
	# body_entered alone misses actors already standing inside the auto-open
	# volume when the door closes or their move target changes; poll the few
	# realized doors' overlap lists to cover that.
	for door_id in _door_projection_by_id.keys():
		var door := _door_projection(str(door_id))
		if door == null or not door.has_method("get_auto_open_candidates"):
			continue
		for body in door.call("get_auto_open_candidates"):
			request_npc_auto_open(body, door)
	for command_id in _approaches_by_command_id.keys().duplicate():
		var info: Dictionary = _approaches_by_command_id.get(command_id, {})
		var actor: Node = (_gecs_world.get_actor_by_stable_id(str(info.get("actor_id", ""))) as Node) if _gecs_world != null else null
		if actor == null or not is_instance_valid(actor) or not actor is Node3D:
			_doors.cancel_command(command_id, "actor_unavailable")
			_approaches_by_command_id.erase(command_id)
			continue
		var target: Vector3 = info.get("interaction_position", Vector3.INF)
		if target == Vector3.INF:
			_doors.cancel_command(command_id, "interaction_position_missing")
			_approaches_by_command_id.erase(command_id)
			continue
		# An actor whose AI keeps overriding the approach target must not pin
		# the door busy forever; the keeper reconcile will retry later.
		if Time.get_ticks_msec() - int(info.get("queued_at_msec", 0)) > APPROACH_TIMEOUT_MSEC:
			_doors.cancel_command(command_id, "approach_timed_out")
			_approaches_by_command_id.erase(command_id)
			continue
		if (actor as Node3D).global_position.distance_to(target) <= 1.5:
			_doors.begin_command(command_id)
			_approaches_by_command_id.erase(command_id)


func _on_door_command_resolved(result: Dictionary) -> void:
	var command_id := str(result.get("command_id", ""))
	var info: Dictionary = _command_info_by_id.get(command_id, {})
	_command_info_by_id.erase(command_id)
	_approaches_by_command_id.erase(command_id)
	_active_command_by_actor_door.erase(_actor_door_key(str(result.get("actor_id", "")), str(result.get("door_id", ""))))
	var actor: Node = (_gecs_world.get_actor_by_stable_id(str(result.get("actor_id", ""))) as Node) if _gecs_world != null else null
	if actor == null or not is_instance_valid(actor):
		return
	if not bool(info.get("issued_by_player", true)):
		_set_door_duty_order(actor, false)
	if str(result.get("action", "")) == "lockpick":
		var xp := float(result.get("skill_xp", 0.0))
		if xp > 0.0 and actor.has_method("add_skill_xp"):
			actor.call("add_skill_xp", SKILL_RULES.SUBTERFUGE_LOCKPICKING, xp, "lockpicking")
		if bool(result.get("lockpick_broke", false)):
			_break_lockpick(actor)
		var law_order := _context.get_optional(&"law_order") if _context != null else null
		var door = _weak_door(info)
		if law_order != null and door != null and law_order.has_method("report_lockpicking_if_witnessed"):
			law_order.call("report_lockpicking_if_witnessed", actor, door)
	var follow_up := str(info.get("follow_up_action", ""))
	if not follow_up.is_empty() and str(result.get("result_code", "")) == "closed":
		var chained_door = _weak_door(info)
		if chained_door != null:
			request_actor_action(actor, chained_door, follow_up, bool(info.get("issued_by_player", false)))
		return
	if not bool(info.get("issued_by_player", true)) and (str(result.get("result_code", "")) == "unlocked" or str(result.get("result_code", "")) == "lockpicked"):
		var door = _weak_door(info)
		if door != null:
			request_actor_action(actor, door, "open", false, info.get("resume_target", null))
		return
	if str(result.get("result_code", "")) == "opened":
		var resume_target = info.get("resume_target", null)
		if resume_target is Vector3:
			actor.call("set_move_target", resume_target, bool(info.get("issued_by_player", true)))


func _on_scheduled_door_action_requested(actor_id: String, door_id: String, action: String) -> void:
	var actor := _resolve_live_actor(actor_id)
	var door := _door_projection(door_id)
	if actor == null or door == null:
		return
	# Locking up an open shop is two acts: swing the door shut, then lock it.
	if action == "lock" and bool(_doors.get_door_state(door_id).get("is_open", false)):
		request_actor_action(actor, door, "close", false, null, "lock")
		return
	request_actor_action(actor, door, action, false)


func _actor_snapshot(actor: Node, door: Node) -> Dictionary:
	var actor_state: Dictionary = _gecs_world.get_actor_state(_actor_id(actor)) if _gecs_world != null else {}
	return {
		"lockpick_skill_level": float(actor.call("get_skill_level", SKILL_RULES.SUBTERFUGE_LOCKPICKING)) if actor.has_method("get_skill_level") else 0.0,
		"assisting_attribute_level": float(actor.call("get_skill_level", SKILL_RULES.ATTRIBUTE_DEXTERITY)) if actor.has_method("get_skill_level") else 0.0,
		"actor_faction_id": str(actor_state.get("faction_id", "")),
		"active_law_response": _combat_responses != null and _combat_responses.has_active_law_response(_actor_id(actor)),
		"actor_key_ids": _actor_key_ids(actor),
		"has_required_lockpick": _find_inventory_tool(actor, "lockpick") != null,
		"from_inside": _actor_is_inside_door_building(actor, door),
	}


## Direction of travel matters for exit policies: "inside" is the owning
## WorldBuilding's occupancy answer, found by walking the door's ancestors.
func _actor_move_target_matches(actor: Node, target: Vector3) -> bool:
	if not actor.has_method("get_move_target") or actor.call("has_move_target") != true:
		return false
	var current = actor.call("get_move_target")
	return current is Vector3 and (current as Vector3).distance_to(target) < 0.05


## Ambient staff-post and patrol loops re-target their actor every tick and
## would tug them off the door approach; the USE_DOOR order makes ambient
## moves yield until the command finishes (set here, cleared on resolution).
func _set_door_duty_order(actor: Node, active: bool) -> void:
	var interaction = actor.call("get_interaction") if actor.has_method("get_interaction") else null
	if interaction == null:
		return
	if active:
		interaction._set_order(InteractionCapability.ORDER_TYPE_USE_DOOR, false)
	elif interaction.current_order_type == InteractionCapability.ORDER_TYPE_USE_DOOR:
		interaction._set_order(InteractionCapability.ORDER_TYPE_NONE, false)


func _actor_is_inside_door_building(actor: Node, door: Node) -> bool:
	var node := door.get_parent() if door != null else null
	while node != null:
		if node.has_method("is_actor_inside"):
			return bool(node.call("is_actor_inside", actor))
		node = node.get_parent()
	return false


func _actor_key_ids(actor: Node) -> PackedStringArray:
	var key_ids := PackedStringArray()
	var inventory = actor.get("inventory")
	if inventory == null:
		return key_ids
	for entry in inventory.entries:
		var definition = entry.definition
		if definition == null:
			continue
		for key_id in (definition.get("access_key_ids") as PackedStringArray):
			if not key_ids.has(key_id):
				key_ids.append(key_id)
	return key_ids


func _find_inventory_tool(actor: Node, tool_tag: String):
	var inventory = actor.get("inventory")
	if inventory == null:
		return null
	for entry in inventory.entries:
		var definition = entry.definition
		if definition != null and definition.has_method("has_tool_tag") and definition.call("has_tool_tag", tool_tag):
			return definition
	return null


func _break_lockpick(actor: Node) -> void:
	var tool = _find_inventory_tool(actor, "lockpick")
	var inventory = actor.get("inventory")
	if tool != null and inventory != null:
		inventory.remove_item_count(tool, 1)
		if _gecs_world != null:
			_gecs_world.sync_actor_inventory(actor)


func _closest_interaction_position(actor: Node, door: Node) -> Vector3:
	if not actor is Node3D or not door.has_method("get_interaction_positions"):
		return Vector3.INF
	var best := Vector3.INF
	var best_distance := INF
	for position in door.call("get_interaction_positions"):
		var distance := (actor as Node3D).global_position.distance_squared_to(position)
		if distance < best_distance:
			best_distance = distance
			best = position
	return best


func _actor_is_trying_to_cross_door(actor: Node, door: Node) -> bool:
	var target = _current_move_target(actor)
	if not actor is Node3D or not door is Node3D or not target is Vector3:
		return false
	var normal := (door as Node3D).global_transform.basis.z.normalized()
	var origin := (door as Node3D).global_position
	var actor_side := normal.dot((actor as Node3D).global_position - origin)
	var target_side := normal.dot(target - origin)
	return absf(actor_side) > 0.15 and absf(target_side) > 0.15 and actor_side * target_side < 0.0


func _current_move_target(actor: Node):
	if actor == null or not actor.has_method("has_move_target") or actor.call("has_move_target") != true:
		return null
	var target = actor.call("get_move_target") if actor.has_method("get_move_target") else null
	return target if target is Vector3 else null


## A door is private when anything restricts it — any authorized actor,
## faction, or key list. Public doors (no lists) are nobody's business.
func is_door_private(door: Node) -> bool:
	if _doors == null or door == null:
		return false
	var state: Dictionary = _doors.get_door_state(_door_id(door))
	return not (state.get("authorized_actor_ids", PackedStringArray()) as PackedStringArray).is_empty() \
		or not (state.get("authorized_faction_ids", PackedStringArray()) as PackedStringArray).is_empty() \
		or not (state.get("authorized_key_ids", PackedStringArray()) as PackedStringArray).is_empty()


## Same access rule the sim applies to commands, exposed for UI legality
## tinting: actor id, faction, or a carried key grants access.
func is_actor_authorized(actor: Node, door: Node) -> bool:
	if _doors == null or actor == null or door == null:
		return true
	var state: Dictionary = _doors.get_door_state(_door_id(door))
	if state.is_empty():
		return true
	return _snapshot_has_authorized_access(_actor_snapshot(actor, door), state, _actor_id(actor))


func _snapshot_has_authorized_access(snapshot: Dictionary, state: Dictionary, actor_id: String) -> bool:
	return bool(snapshot.get("active_law_response", false)) or (state.get("authorized_actor_ids", PackedStringArray()) as PackedStringArray).has(actor_id) or (state.get("authorized_faction_ids", PackedStringArray()) as PackedStringArray).has(str(snapshot.get("actor_faction_id", ""))) or _shared_key_exists(state.get("authorized_key_ids", PackedStringArray()), snapshot.get("actor_key_ids", PackedStringArray()))


func _shared_key_exists(required_keys: PackedStringArray, actor_keys: PackedStringArray) -> bool:
	for key_id in required_keys:
		if actor_keys.has(key_id):
			return true
	return false


## Keeper/scheduled flows start from a stable id. Facility staff may exist
## only as population records, invisible to the GECS actor registry until
## something registers them — find the live body and register it on the spot.
func _resolve_live_actor(actor_id: String) -> Node:
	if actor_id.is_empty():
		return null
	var actor: Node = (_gecs_world.get_actor_by_stable_id(actor_id) as Node) if _gecs_world != null else null
	if actor != null and is_instance_valid(actor):
		return actor
	for candidate in get_tree().get_nodes_in_group("world_actor"):
		if str(candidate.get("stable_id")) == actor_id:
			_actor_id(candidate)
			return candidate
	return null


func _actor_id(actor: Node) -> String:
	if actor == null:
		return ""
	var actor_id := str(actor.get_meta("actor_record_id")) if actor.has_meta("actor_record_id") else ""
	if _gecs_world == null:
		return actor_id
	# Facility-generated staff carry a population record id but were never
	# registered with the GECS actor registry, so door commands rejected them
	# as unknown. register_actor is idempotent and keeps the existing id.
	if actor_id.is_empty() or _gecs_world.get_actor_by_stable_id(actor_id) == null:
		return _gecs_world.register_actor(actor)
	return actor_id


func _actor_door_key(actor_id: String, door_id: String) -> String:
	return "%s:%s" % [actor_id, door_id]


func _door_id(door: Node) -> String:
	return str(door.get("door_id")) if door != null else ""


func _is_player_party_member(actor: Node) -> bool:
	return bool(actor.call("is_player_party_member")) if actor.has_method("is_player_party_member") else false


func _weak_door(info: Dictionary) -> Node:
	var reference = info.get("door")
	var door = reference.get_ref() if reference is WeakRef else null
	return door as Node if door != null and is_instance_valid(door) else null


func _door_projection(door_id: String) -> Node:
	var reference = _door_projection_by_id.get(door_id)
	var door = reference.get_ref() if reference is WeakRef else null
	return door as Node if door != null and is_instance_valid(door) else null
