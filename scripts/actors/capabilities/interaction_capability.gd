extends "res://scripts/actors/capabilities/actor_capability.gd"

class_name InteractionCapability

const ORDER_TYPE_NONE := 0
const ORDER_TYPE_MOVE := 1
const ORDER_TYPE_MINE := 2
const ORDER_TYPE_SCAVENGE := 3
const ORDER_TYPE_OPEN_CONTAINER := 4
const ORDER_TYPE_TRADE := 5
const ORDER_TYPE_TALK := 6
const ORDER_TYPE_HEAL := 8
const ORDER_TYPE_FINISH_OFF := 9
const ORDER_TYPE_CARRY := 10
const ORDER_TYPE_SLEEP := 11
const ORDER_TYPE_PLACE_IN_BED := 12
const ORDER_TYPE_PLACE_IN_CELL := 13
const ORDER_TYPE_PLACE_IN_FURNACE := 14
const ORDER_TYPE_SIT := 15
const ORDER_TYPE_PICKUP_ITEM := 16
const MINING_ORE_WORTH_FOR_FIRST_LEVEL := 4.0
const MINING_STRENGTH_XP_FACTOR := 0.08
const SCAVENGING_ATTEMPTS_FOR_FIRST_LEVEL := 4.0

var _law_custody_return_active := false
var _law_custody_return_target := Vector3.ZERO
var _law_sentence_move_active := false
var _law_sentence_move_target := Vector3.ZERO


func _init() -> void:
	super._init(&"interaction")


func stop_mining_assignment() -> void:
	var mining_node = _node_property("_current_mining_node")
	if mining_node != null and is_instance_valid(mining_node) and mining_node.has_method("release_miner"):
		mining_node.call("release_miner", actor)
	_set_node_property("_current_mining_node", null)
	_set_node_property("_mining_active", false)
	if _current_order_type() == ORDER_TYPE_MINE:
		_set_current_order_type(ORDER_TYPE_NONE)
	_emit_actor_signal("mining_changed")


func stop_scavenging_assignment() -> void:
	var scavenging_node = _node_property("_current_scavenging_node")
	if scavenging_node != null and is_instance_valid(scavenging_node) and scavenging_node.has_method("release_scavenger"):
		scavenging_node.call("release_scavenger", actor)
	_set_node_property("_current_scavenging_node", null)
	_set_node_property("_scavenging_active", false)
	if _current_order_type() == ORDER_TYPE_SCAVENGE:
		_set_current_order_type(ORDER_TYPE_NONE)
	_emit_actor_signal("scavenging_changed")


func stop_container_interaction() -> void:
	var container = _node_property("_current_container_target")
	if container != null and is_instance_valid(container) and container.has_method("release_interactor"):
		container.call("release_interactor", actor)
	_set_node_property("_current_container_target", null)
	if _current_order_type() == ORDER_TYPE_OPEN_CONTAINER:
		_set_current_order_type(ORDER_TYPE_NONE)


func stop_trade_interaction() -> void:
	var trade_target = _node_property("_current_trade_target")
	if trade_target != null and is_instance_valid(trade_target) and trade_target.has_method("release_trader"):
		trade_target.call("release_trader", actor)
	_set_node_property("_current_trade_target", null)
	if _current_order_type() == ORDER_TYPE_TRADE:
		_set_current_order_type(ORDER_TYPE_NONE)


func stop_conversation_interaction() -> void:
	var conversation_target = _node_property("_current_conversation_target")
	if conversation_target != null and is_instance_valid(conversation_target) and conversation_target.has_method("release_talker"):
		conversation_target.call("release_talker", actor)
	_set_node_property("_current_conversation_target", null)
	if _current_order_type() == ORDER_TYPE_TALK:
		_set_current_order_type(ORDER_TYPE_NONE)


func stop_heal_assignment() -> void:
	_set_node_property("_current_heal_target", null)
	if _current_order_type() == ORDER_TYPE_HEAL:
		_set_current_order_type(ORDER_TYPE_NONE)


func stop_finish_off_assignment() -> void:
	var finish_target = _node_property("_current_finish_off_target")
	if _node_property("_auto_burn_reserved_target") == finish_target:
		_call_void("_release_auto_burn_target_reservation")
	_set_node_property("_current_finish_off_target", null)
	if _current_order_type() == ORDER_TYPE_FINISH_OFF:
		_set_current_order_type(ORDER_TYPE_NONE)


func stop_carry_assignment() -> void:
	var carry_target = _node_property("_current_carry_target")
	var auto_burn_target = _node_property("_auto_burn_reserved_target")
	if auto_burn_target == carry_target:
		if _node_property("_carried_character") == auto_burn_target:
			_call_void("_release_auto_burn_target_reservation")
		else:
			_call_void("_release_auto_burn_reservations")
	_set_node_property("_current_carry_target", null)
	if _current_order_type() == ORDER_TYPE_CARRY:
		_set_current_order_type(ORDER_TYPE_NONE)


func stop_place_in_bed_assignment() -> void:
	_set_node_property("_current_place_bed_target", null)
	if _current_order_type() == ORDER_TYPE_PLACE_IN_BED:
		_set_current_order_type(ORDER_TYPE_NONE)


func stop_place_in_cell_assignment() -> void:
	_set_node_property("_current_place_cell_target", null)
	_clear_place_cell_waypoints()
	if _current_order_type() == ORDER_TYPE_PLACE_IN_CELL:
		_set_current_order_type(ORDER_TYPE_NONE)


func stop_place_in_furnace_assignment() -> void:
	release_place_furnace_reservation()
	_set_node_property("_current_place_furnace_target", null)
	if _current_order_type() == ORDER_TYPE_PLACE_IN_FURNACE:
		_set_current_order_type(ORDER_TYPE_NONE)


func stop_sleep_assignment() -> void:
	var sleep_target = _node_property("_current_sleep_target")
	if _actor_life_state() == NpcRules.LifeState.ASLEEP and sleep_target != null and sleep_target.has_method("get_interaction_position"):
		_set_actor_global_position(sleep_target.call("get_interaction_position", actor))
	release_sleep_target_without_waking()
	if _actor_life_state() == NpcRules.LifeState.ASLEEP:
		_set_node_property("life_state", NpcRules.LifeState.ALIVE)
		var rotation := _actor_rotation()
		_set_actor_rotation(Vector3(0.0, rotation.y, 0.0))
		_set_node_property("velocity", Vector3.ZERO)
		_emit_actor_signal("state_changed")
	if _current_order_type() == ORDER_TYPE_SLEEP:
		_set_current_order_type(ORDER_TYPE_NONE)


func release_sleep_target_without_waking() -> void:
	var sleep_target = _node_property("_current_sleep_target")
	if sleep_target != null and sleep_target.has_method("release_sleeper"):
		sleep_target.call("release_sleeper", actor)
	_set_node_property("_current_sleep_target", null)
	if _current_order_type() == ORDER_TYPE_SLEEP:
		_set_current_order_type(ORDER_TYPE_NONE)


func stop_seat_assignment() -> void:
	var seat_target = _node_property("_current_seat_target")
	var did_stop_sitting := _actor_bool("_is_sitting", false)
	if did_stop_sitting and seat_target != null:
		var stand_position = _node_property("_current_seat_stand_position")
		if stand_position is Vector3:
			_set_actor_global_position(stand_position)
		elif seat_target.has_method("get_stand_position"):
			_set_actor_global_position(seat_target.call("get_stand_position"))
		elif seat_target.has_method("get_interaction_position"):
			_set_actor_global_position(seat_target.call("get_interaction_position", actor))
	if seat_target != null and seat_target.has_method("release_sitter"):
		seat_target.call("release_sitter", actor)
	_set_node_property("_current_seat_target", null)
	_set_node_property("_current_seat_stand_position", null)
	if did_stop_sitting:
		_set_node_property("_is_sitting", false)
		_call_void("_start_sitting_exit_animation")
		var rotation := _actor_rotation()
		_set_actor_rotation(Vector3(0.0, rotation.y, 0.0))
		_set_node_property("velocity", Vector3.ZERO)
		_emit_actor_signal("state_changed")
	if _current_order_type() == ORDER_TYPE_SIT:
		_set_current_order_type(ORDER_TYPE_NONE)


func stop_pickup_assignment() -> void:
	_set_node_property("_current_pickup_item", null)
	if _current_order_type() == ORDER_TYPE_PICKUP_ITEM:
		_set_current_order_type(ORDER_TYPE_NONE)


func assign_open_container(container, issued_by_player := true) -> void:
	if container == null:
		return
	if not _set_order(ORDER_TYPE_OPEN_CONTAINER, issued_by_player):
		return
	var current_container = _node_property("_current_container_target")
	if current_container != null and current_container != container and current_container.has_method("release_interactor"):
		current_container.call("release_interactor", actor)
	_set_node_property("_current_container_target", container)
	if container.has_method("register_interactor"):
		container.call("register_interactor", actor)
	_set_actor_move_target(container.call("get_interaction_position", actor))


func assign_trade_target(target_character, issued_by_player := true) -> void:
	if target_character == null:
		return
	if not _set_order(ORDER_TYPE_TRADE, issued_by_player):
		return
	var current_target = _node_property("_current_trade_target")
	if current_target != null and current_target != target_character and current_target.has_method("release_trader"):
		current_target.call("release_trader", actor)
	_set_node_property("_current_trade_target", target_character)
	if target_character.has_method("register_trader"):
		target_character.call("register_trader", actor)
	_set_actor_move_target(target_character.call("get_interaction_position", actor))


func assign_conversation_target(target_character, issued_by_player := true) -> void:
	if target_character == null or not _node_call_bool(target_character, "has_conversation_definition"):
		return
	var preserve_seat := issued_by_player and _actor_bool("_is_sitting", false)
	if not _set_order(ORDER_TYPE_TALK, issued_by_player, preserve_seat):
		return
	var current_target = _node_property("_current_conversation_target")
	if current_target != null and current_target != target_character and current_target.has_method("release_talker"):
		current_target.call("release_talker", actor)
	_set_node_property("_current_conversation_target", target_character)
	if target_character.has_method("register_talker"):
		target_character.call("register_talker", actor)
	if preserve_seat and _position().distance_to(_position_of(target_character)) <= get_conversation_interaction_distance():
		_clear_actor_move_target()
	else:
		_set_actor_move_target(target_character.call("get_interaction_position", actor))


func assign_mining_resource(resource_node, issued_by_player := true) -> void:
	var mining_node := resource_node as MiningResourceNode
	if mining_node == null:
		return
	if not ensure_mining_tool_equipped(mining_node, issued_by_player):
		return
	if not _set_order(ORDER_TYPE_MINE, issued_by_player):
		return
	var current_node = _node_property("_current_mining_node")
	if current_node != null and current_node != mining_node and current_node.has_method("release_miner"):
		current_node.call("release_miner", actor)
	_set_node_property("_current_mining_node", mining_node)
	if mining_node.has_method("register_miner"):
		mining_node.call("register_miner", actor)
	_set_node_property("_mining_active", false)
	_set_actor_move_target(mining_node.get_mining_position(actor))
	_emit_actor_signal("mining_changed")


func assign_scavenging_resource(resource_node, issued_by_player := true) -> void:
	if resource_node == null:
		return
	if _node_call_bool(resource_node, "is_depleted"):
		if issued_by_player:
			_emit_actor_signal("center_notice_requested", ["Depleted"])
		_call_void("_show_world_notice", ["Depleted", Color(0.75, 0.72, 0.62, 1.0), 1.2, 0.45])
		return
	if not _set_order(ORDER_TYPE_SCAVENGE, issued_by_player):
		return
	var current_node = _node_property("_current_scavenging_node")
	if current_node != null and current_node != resource_node and current_node.has_method("release_scavenger"):
		current_node.call("release_scavenger", actor)
	_set_node_property("_current_scavenging_node", resource_node)
	if resource_node.has_method("register_scavenger"):
		resource_node.call("register_scavenger", actor)
	_set_node_property("_scavenging_active", false)
	_set_actor_move_target(resource_node.call("get_scavenging_position", actor))
	_emit_actor_signal("scavenging_changed")


func assign_carry_target(target_character, issued_by_player := true) -> void:
	if target_character == null or target_character == actor:
		return
	if not _is_actor_alive():
		return
	if not _node_call_bool(target_character, "can_be_carried_by", [actor]) or _node_property("_carried_character") != null:
		return
	if not _set_order(ORDER_TYPE_CARRY, issued_by_player):
		return
	_set_node_property("_current_carry_target", target_character)


func assign_place_carried_in_bed_target(bed, issued_by_player := true) -> void:
	if bed == null or not bed.has_method("get_interaction_position"):
		return
	if not _is_actor_alive():
		return
	if not _is_valid_node(_node_property("_carried_character")):
		return
	if not _set_order(ORDER_TYPE_PLACE_IN_BED, issued_by_player):
		return
	_set_node_property("_current_place_bed_target", bed)
	_set_actor_move_target(bed.call("get_interaction_position", actor))


func assign_place_carried_in_cell_target(cell, issued_by_player := true) -> void:
	if cell == null or not cell.has_method("get_interaction_position"):
		return
	if not _is_actor_alive():
		return
	if not _is_valid_node(_node_property("_carried_character")):
		return
	if _current_order_type() == ORDER_TYPE_PLACE_IN_CELL and _node_property("_current_place_cell_target") == cell:
		return
	if not _set_order(ORDER_TYPE_PLACE_IN_CELL, issued_by_player):
		return
	_set_node_property("_current_place_cell_target", cell)
	_set_node_property("_current_place_cell_waypoints", get_place_cell_route(cell))
	set_next_place_cell_move_target(cell.call("get_interaction_position", actor))


func assign_place_carried_in_furnace_target(furnace, issued_by_player := true) -> void:
	if furnace == null or not furnace.has_method("get_interaction_position"):
		return
	if not _is_actor_alive():
		return
	var carried = _node_property("_carried_character")
	if not _is_valid_node(carried):
		return
	if furnace.has_method("can_accept_body") and not bool(furnace.call("can_accept_body", carried)):
		if issued_by_player:
			_call_void("_show_world_notice", ["Cannot burn", Color(1.0, 0.66, 0.28, 1.0)])
		return
	if furnace.has_method("reserve_for") and not bool(furnace.call("reserve_for", actor, carried)):
		if issued_by_player:
			_call_void("_show_world_notice", ["Furnace busy", Color(1.0, 0.78, 0.38, 1.0)])
		return
	if not _set_order(ORDER_TYPE_PLACE_IN_FURNACE, issued_by_player):
		if furnace.has_method("release_reservation"):
			furnace.call("release_reservation", actor, carried)
		return
	_set_node_property("_current_place_furnace_target", furnace)
	var reserved_furnace = _node_property("_auto_burn_reserved_furnace")
	if reserved_furnace != null and reserved_furnace != furnace:
		_call_void("_release_auto_burn_furnace_reservation")
	_set_actor_move_target(furnace.call("get_interaction_position", actor))


func assign_sleep_target(bed, issued_by_player := true) -> void:
	if bed == null or not bed.has_method("get_interaction_position"):
		return
	if not _is_actor_alive():
		return
	if _node_property("_carried_character") != null:
		if issued_by_player:
			_emit_actor_signal("center_notice_requested", ["Place them in bed first"])
			_call_void("_show_world_notice", ["Place them in bed first", Color(1.0, 0.78, 0.38, 1.0)])
		return
	if not _set_order(ORDER_TYPE_SLEEP, issued_by_player):
		return
	_set_node_property("_current_sleep_target", bed)
	_set_actor_move_target(bed.call("get_interaction_position", actor))


func assign_seat_target(seat, issued_by_player := true) -> void:
	if seat == null or not seat.has_method("get_interaction_position"):
		return
	if not _is_actor_alive():
		return
	if not _set_order(ORDER_TYPE_SIT, issued_by_player):
		return
	_set_node_property("_current_seat_target", seat)
	_set_node_property("_current_seat_stand_position", _position())
	if seat.has_method("can_sit_from_position") and bool(seat.call("can_sit_from_position", _position())):
		_clear_actor_move_target()
	else:
		_set_actor_move_target(seat.call("get_interaction_position", actor))


func sit_at_seat_immediately(seat) -> bool:
	if seat == null or not seat.has_method("claim_sitter") or not seat.has_method("get_seat_position"):
		return false
	if not _is_actor_alive():
		return false
	stop_seat_assignment()
	if not bool(seat.call("claim_sitter", actor)):
		return false
	_set_node_property("_current_seat_target", seat)
	_set_node_property("_current_seat_stand_position", seat.call("get_stand_position") if seat.has_method("get_stand_position") else _position())
	_set_actor_global_position(seat.call("get_seat_position", actor))
	if seat.has_method("get_seat_rotation"):
		_set_actor_rotation(seat.call("get_seat_rotation", actor))
	_set_node_property("velocity", Vector3.ZERO)
	_set_node_property("running", false)
	_call_void("_set_sneaking_state", [false, false])
	_clear_actor_move_target()
	_set_node_property("_is_sitting", true)
	_set_current_order_type(ORDER_TYPE_NONE)
	_call_void("_start_sitting_enter_animation")
	_emit_actor_signal("state_changed")
	return true


func assign_pickup_item(world_item, issued_by_player := true) -> void:
	if not _is_valid_node(world_item):
		return
	if not _is_actor_alive():
		return
	if not _set_order(ORDER_TYPE_PICKUP_ITEM, issued_by_player):
		return
	_set_node_property("_current_pickup_item", world_item)
	_set_actor_move_target(get_pickup_route_position(world_item))


func assign_heal_target(target_character, issued_by_player := true) -> void:
	if target_character == null:
		return
	if not _is_actor_alive():
		return
	if not _set_order(ORDER_TYPE_HEAL, issued_by_player):
		return
	_set_node_property("_current_heal_target", target_character)


func assign_finish_off_target(target_character, issued_by_player := true) -> void:
	if target_character == null or target_character == actor:
		return
	if not _is_actor_alive():
		return
	if not _node_call_bool(target_character, "is_downed_state"):
		return
	if not _set_order(ORDER_TYPE_FINISH_OFF, issued_by_player):
		return
	_set_node_property("_current_finish_off_target", target_character)


func is_law_custody_returning() -> bool:
	return _law_custody_return_active


func is_law_sentence_moving() -> bool:
	return _law_sentence_move_active


func has_direct_law_move() -> bool:
	return (_law_sentence_move_active or _law_custody_return_active) and _actor_bool("_has_move_target", false)


func assign_law_custody_return_target(target_position: Vector3) -> void:
	if not _is_actor_alive():
		return
	_call_void("disengage_combat_with")
	_law_custody_return_active = true
	_law_custody_return_target = target_position
	if not _set_order(ORDER_TYPE_MOVE, false):
		_set_current_order_type(ORDER_TYPE_MOVE)
		_set_node_property("_order_was_player_issued", false)
	_set_actor_move_target(target_position)


func clear_law_custody_return() -> void:
	_law_custody_return_active = false


func assign_law_sentence_move_target(target_position: Vector3) -> void:
	if not _is_actor_alive():
		return
	_law_sentence_move_active = true
	_law_sentence_move_target = target_position
	if _current_order_type() != ORDER_TYPE_MOVE:
		if not _set_order(ORDER_TYPE_MOVE, false):
			_set_current_order_type(ORDER_TYPE_MOVE)
			_set_node_property("_order_was_player_issued", false)
	else:
		_set_node_property("_order_was_player_issued", false)
	_set_actor_move_target(target_position)


func clear_law_sentence_move() -> void:
	_law_sentence_move_active = false


func clear_law_moves_for_order(order_type: int, issued_by_player: bool) -> void:
	if _law_custody_return_active and (issued_by_player or order_type != ORDER_TYPE_MOVE):
		_law_custody_return_active = false
	if _law_sentence_move_active and (issued_by_player or order_type != ORDER_TYPE_MOVE):
		_law_sentence_move_active = false


func wake_up_from_rest(show_notice := true) -> void:
	var did_wake := _actor_life_state() == NpcRules.LifeState.ASLEEP
	var did_stand := _actor_bool("_is_sitting", false)
	var stand_position = null
	var sleep_target = _node_property("_current_sleep_target")
	var seat_target = _node_property("_current_seat_target")
	if did_wake and sleep_target != null and sleep_target.has_method("get_interaction_position"):
		stand_position = sleep_target.call("get_interaction_position", actor)
	elif did_stand and seat_target != null:
		var seat_stand_position = _node_property("_current_seat_stand_position")
		if seat_stand_position is Vector3:
			stand_position = seat_stand_position
		elif seat_target.has_method("get_stand_position"):
			stand_position = seat_target.call("get_stand_position")
		elif seat_target.has_method("get_interaction_position"):
			stand_position = seat_target.call("get_interaction_position", actor)
	stop_sleep_assignment()
	stop_seat_assignment()
	if stand_position is Vector3:
		_set_actor_global_position(stand_position)
	if did_wake or did_stand:
		_set_node_property("life_state", NpcRules.LifeState.ALIVE)
		_clear_actor_move_target()
		_set_current_order_type(ORDER_TYPE_NONE)
		_set_node_property("velocity", Vector3.ZERO)
		if show_notice:
			_call_void("_show_world_notice", ["Awake" if did_wake else "Standing", Color(0.5, 1.0, 0.65, 1.0)])
		_emit_actor_signal("state_changed")


func has_mining_assignment() -> bool:
	return _node_property("_current_mining_node") != null


func get_assigned_mining_node():
	return _node_property("_current_mining_node")


func is_actively_mining() -> bool:
	return _actor_bool("_mining_active", false)


func get_mining_progress_ratio() -> float:
	var mining_node = _node_property("_current_mining_node")
	if mining_node == null:
		return 0.0
	return get_stored_mining_progress(mining_node)


func has_scavenging_assignment() -> bool:
	return _node_property("_current_scavenging_node") != null


func get_assigned_scavenging_node():
	return _node_property("_current_scavenging_node")


func is_actively_scavenging() -> bool:
	return _actor_bool("_scavenging_active", false)


func get_scavenging_progress_ratio() -> float:
	var scavenging_node = _node_property("_current_scavenging_node")
	if scavenging_node == null:
		return 0.0
	return get_stored_scavenging_progress(scavenging_node)


func process_mining(delta: float) -> void:
	var mining_node := _node_property("_current_mining_node") as MiningResourceNode
	if mining_node == null:
		return
	if not ensure_mining_tool_equipped(mining_node, _actor_bool("_order_was_player_issued", false)):
		stop_mining_assignment()
		return
	var mining_position := mining_node.get_mining_position(actor)
	if _position().distance_to(mining_position) > mining_node.get_mining_interaction_radius():
		_set_actor_move_target(mining_position)
		_set_node_property("_mining_active", false)
		_emit_actor_signal("mining_changed")
		return
	if _actor_bool("_has_move_target", false):
		return
	var duration := maxf(mining_node.get_effective_mine_duration(actor), 0.01)
	var mining_inventory = _work_inventory_override()
	if mining_inventory == null:
		mining_inventory = _inventory()
	var progress_before := get_stored_mining_progress(mining_node)
	if progress_before >= 1.0:
		if mining_node.can_produce_ore_for(actor):
			if mining_inventory != null and mining_inventory.add_item(mining_node.item_definition):
				progress_before = 0.0
			else:
				store_mining_progress(mining_node, 1.0)
				_set_node_property("_mining_active", false)
				_emit_actor_signal("mining_changed")
				return
		else:
			show_mining_requirement_notice(mining_node)
			progress_before = 0.0
	_set_node_property("_mining_active", true)
	var progress_delta := minf(delta / duration, maxf(1.0 - progress_before, 0.0))
	award_mining_progress_xp(progress_delta, mining_node.get_locked_attempt_xp_multiplier_for(actor))
	var progress := progress_before + progress_delta
	if progress >= 1.0:
		if mining_node.can_produce_ore_for(actor):
			if mining_inventory != null and mining_inventory.add_item(mining_node.item_definition):
				progress = 0.0
			else:
				progress = 1.0
				_set_node_property("_mining_active", false)
		else:
			progress = 0.0
			show_mining_requirement_notice(mining_node)
	store_mining_progress(mining_node, progress)
	_emit_actor_signal("mining_changed")


func process_scavenging(delta: float) -> void:
	var scavenging_node := _node_property("_current_scavenging_node") as ScavengingResourceNode
	if scavenging_node == null:
		return
	if scavenging_node.is_depleted():
		show_scavenging_notice("Depleted", Color(0.75, 0.72, 0.62, 1.0), true)
		stop_scavenging_assignment()
		return
	var scavenging_position := scavenging_node.get_scavenging_position(actor)
	if _position().distance_to(scavenging_position) > _actor_float("interact_distance", 1.8):
		_set_actor_move_target(scavenging_position)
		_set_node_property("_scavenging_active", false)
		_emit_actor_signal("scavenging_changed")
		return
	if _actor_bool("_has_move_target", false):
		return
	var duration := maxf(scavenging_node.get_effective_scavenge_duration(actor), 0.01)
	var progress_before := get_stored_scavenging_progress(scavenging_node)
	_set_node_property("_scavenging_active", true)
	var progress_delta := minf(delta / duration, maxf(1.0 - progress_before, 0.0))
	award_scavenging_progress_xp(progress_delta)
	var progress := progress_before + progress_delta
	if progress >= 1.0:
		var result := scavenging_node.complete_scavenge_attempt(actor)
		progress = 0.0
		var message := str(result.get("message", ""))
		if not message.is_empty():
			show_scavenging_notice(message, get_scavenging_notice_color(result), false)
		if bool(result.get("depleted", false)):
			store_scavenging_progress(scavenging_node, progress)
			stop_scavenging_assignment()
			return
	store_scavenging_progress(scavenging_node, progress)
	_emit_actor_signal("scavenging_changed")


func process_container_interaction() -> void:
	var container = _node_property("_current_container_target")
	if container == null:
		return
	var interaction_position: Vector3 = container.call("get_interaction_position", actor)
	if _position().distance_to(interaction_position) > _actor_float("interact_distance", 1.8):
		_set_actor_move_target(interaction_position)
		return
	if _actor_bool("_has_move_target", false):
		return
	_set_node_property("_current_container_target", null)
	_set_current_order_type(ORDER_TYPE_NONE)
	_emit_actor_signal("container_reached", [actor, container])


func process_trade_interaction() -> void:
	var target = _node_property("_current_trade_target")
	if target == null:
		return
	var interaction_position: Vector3 = target.call("get_interaction_position", actor)
	var target_position := _position_of(target)
	if _position().distance_to(target_position) > _actor_float("trade_interaction_distance", 3.0):
		_set_actor_move_target(interaction_position)
		return
	_clear_actor_move_target()
	_set_node_property("_current_trade_target", null)
	_set_current_order_type(ORDER_TYPE_NONE)
	_emit_actor_signal("trade_target_reached", [actor, target])


func process_conversation_interaction() -> void:
	var target = _node_property("_current_conversation_target")
	if target == null:
		return
	var interaction_position: Vector3 = target.call("get_interaction_position", actor)
	var target_position := _position_of(target)
	if _position().distance_to(target_position) > get_conversation_interaction_distance():
		if _actor_bool("_is_sitting", false):
			_call_void("stop_seat_assignment")
		_set_actor_move_target(interaction_position)
		return
	_clear_actor_move_target()
	_set_node_property("_current_conversation_target", null)
	_set_current_order_type(ORDER_TYPE_NONE)
	_emit_actor_signal("conversation_target_reached", [actor, target])


func process_law_movement() -> void:
	process_law_custody_return()
	process_law_sentence_move()


func process_law_custody_return() -> void:
	if not _law_custody_return_active:
		return
	if _horizontal_distance_to(_law_custody_return_target) <= _move_target_arrival_distance() or not _actor_bool("_has_move_target", false):
		_law_custody_return_active = false
		return
	if _current_order_type() != ORDER_TYPE_MOVE:
		_set_current_order_type(ORDER_TYPE_MOVE)
		_set_node_property("_order_was_player_issued", false)
	_set_actor_move_target(_law_custody_return_target)


func process_law_sentence_move() -> void:
	if not _law_sentence_move_active:
		return
	if _horizontal_distance_to(_law_sentence_move_target) <= _actor_float("interact_distance", 1.8) or not _actor_bool("_has_move_target", false):
		_law_sentence_move_active = false
		return
	if _current_order_type() != ORDER_TYPE_MOVE:
		_set_current_order_type(ORDER_TYPE_MOVE)
		_set_node_property("_order_was_player_issued", false)
	_set_actor_move_target(_law_sentence_move_target)


func process_heal_interaction() -> void:
	var heal_target = _node_property("_current_heal_target")
	if not _is_valid_node(heal_target):
		stop_heal_assignment()
		return
	if not _node_call_bool(heal_target, "can_receive_bandage"):
		if _actor_bool("_order_was_player_issued", false):
			_call_void("show_world_speech", ["They don't need bandaging", 5.0])
		stop_heal_assignment()
		return
	if _call("_get_best_bandage_definition") == null:
		if _actor_bool("_order_was_player_issued", false):
			_call_void("show_world_speech", ["I don't have anything to heal with", 5.0])
		stop_heal_assignment()
		return
	if heal_target == actor:
		_clear_actor_move_target()
		if _call_bool("apply_bandage_from", [actor]):
			stop_heal_assignment()
		return
	var target_position := _interaction_position_of(heal_target)
	if _position().distance_to(_position_of(heal_target)) > _actor_float("interact_distance", 1.8):
		_set_actor_move_target(target_position)
		return
	_clear_actor_move_target()
	if _node_call_bool(heal_target, "apply_bandage_from", [actor]):
		stop_heal_assignment()


func process_finish_off_interaction() -> void:
	var finish_target = _node_property("_current_finish_off_target")
	if not _is_finish_off_target_valid(finish_target):
		stop_finish_off_assignment()
		return
	if try_complete_finish_off_interaction():
		return
	var target_position_value = _call("_get_downed_target_interaction_position", [finish_target])
	var target_position: Vector3 = target_position_value if target_position_value is Vector3 else Vector3.INF
	if target_position == Vector3.INF:
		stop_finish_off_assignment()
		return
	_set_actor_move_target(target_position)


func try_complete_finish_off_interaction(extra_distance := 0.0) -> bool:
	var finish_target = _node_property("_current_finish_off_target")
	if not _is_finish_off_target_valid(finish_target):
		return false
	if not _call_bool("_is_close_enough_to_downed_interaction_target", [finish_target, extra_distance]):
		return false
	_clear_actor_move_target()
	if _node_call_bool(finish_target, "requires_fire_to_die"):
		_call_void("burn_target_with_cinder_flask", [finish_target, _actor_bool("_order_was_player_issued", false)])
		stop_finish_off_assignment()
		return true
	_call_node_void(finish_target, "force_kill", [actor])
	_call_void("_show_world_notice", ["Finished", Color(0.95, 0.2, 0.2, 1.0)])
	stop_finish_off_assignment()
	return true


func validate_heal_finish_order_targets() -> void:
	if _current_order_type() == ORDER_TYPE_HEAL:
		var heal_target = _node_property("_current_heal_target")
		if not _is_valid_node(heal_target):
			stop_heal_assignment()
	if _current_order_type() == ORDER_TYPE_FINISH_OFF:
		var finish_target = _node_property("_current_finish_off_target")
		if not _is_finish_off_target_valid(finish_target):
			stop_finish_off_assignment()


func process_carry_interaction() -> void:
	var carry_target = _node_property("_current_carry_target")
	if not _is_valid_node(carry_target):
		stop_carry_assignment()
		return
	if not _node_call_bool(carry_target, "can_be_carried_by", [actor]) or _node_property("_carried_character") != null:
		stop_carry_assignment()
		return
	var target_position := _position_of(carry_target)
	if _position().distance_to(target_position) > _actor_float("interact_distance", 1.8):
		_set_actor_move_target(target_position)
		return
	_clear_actor_move_target()
	_call_void("_attach_carried_character", [carry_target])
	_call_void("_show_world_notice", ["Carrying %s" % _node_display_name(carry_target), Color(0.86, 0.92, 1.0, 1.0)])
	stop_carry_assignment()


func process_place_in_bed_interaction() -> void:
	var bed = _node_property("_current_place_bed_target")
	if not _is_valid_node(bed):
		stop_place_in_bed_assignment()
		return
	var carried = _node_property("_carried_character")
	if not _is_valid_node(carried):
		stop_place_in_bed_assignment()
		return
	var interaction_position: Vector3 = bed.call("get_interaction_position", actor)
	if _position().distance_to(interaction_position) > _actor_float("interact_distance", 1.8):
		_set_actor_move_target(interaction_position)
		return
	if _actor_bool("_has_move_target", false):
		return
	var sleep_result: Dictionary = bed.call("request_sleep", actor) if bed.has_method("request_sleep") else {"allowed": true, "message": ""}
	if not bool(sleep_result.get("allowed", false)):
		var failure_message := str(sleep_result.get("message", "Cannot use this bed"))
		if not failure_message.is_empty():
			_emit_actor_signal("center_notice_requested", [failure_message])
			_call_void("_show_world_notice", [failure_message, Color(1.0, 0.78, 0.38, 1.0)])
		stop_place_in_bed_assignment()
		return
	if carried.has_method("stop_sleep_assignment"):
		carried.call("stop_sleep_assignment")
	if not bed.call("claim_sleeper", carried):
		_emit_actor_signal("center_notice_requested", ["Bed occupied"])
		_call_void("_show_world_notice", ["Bed occupied", Color(1.0, 0.78, 0.38, 1.0)])
		stop_place_in_bed_assignment()
		return
	_call("_detach_carried_character")
	_set_node3d_position(carried, bed.call("get_sleep_position"))
	carried.set("rotation", bed.call("get_sleep_rotation"))
	carried.set("velocity", Vector3.ZERO)
	carried.set("running", false)
	_call_node_void(carried, "_set_sneaking_state", [false, false])
	_call_node_void(carried, "_clear_actor_move_target")
	carried.set("_current_order_type", ORDER_TYPE_SLEEP)
	carried.set("_current_sleep_target", bed)
	if int(carried.get("life_state")) == NpcRules.LifeState.ALIVE:
		carried.set("life_state", NpcRules.LifeState.ASLEEP)
	var success_message := str(sleep_result.get("message", ""))
	if not success_message.is_empty():
		_emit_actor_signal("center_notice_requested", [success_message])
	_clear_actor_move_target()
	_set_node_property("_current_place_bed_target", null)
	_set_current_order_type(ORDER_TYPE_NONE)
	_call_void("_show_world_notice", ["Placed in bed", Color(0.55, 0.72, 1.0, 1.0)])
	_emit_actor_signal("state_changed")
	_emit_node_signal(carried, "state_changed")


func process_place_in_cell_interaction() -> void:
	var cell = _node_property("_current_place_cell_target")
	if not _is_valid_node(cell):
		stop_place_in_cell_assignment()
		return
	var carried = _node_property("_carried_character")
	if not _is_valid_node(carried):
		stop_place_in_cell_assignment()
		return
	var interaction_position: Vector3 = cell.call("get_interaction_position", actor)
	var place_distance := maxf(_actor_float("interact_distance", 1.8), _actor_float("CELL_PLACEMENT_INTERACT_DISTANCE", 2.4))
	if _horizontal_distance_to(interaction_position) > place_distance or absf(_position().y - interaction_position.y) > _actor_float("move_target_vertical_tolerance", 0.75) + 0.8:
		set_next_place_cell_move_target(interaction_position)
		return
	if _actor_bool("_has_move_target", false):
		_clear_actor_move_target()
	_call("_detach_carried_character")
	if not bool(cell.call("place_carried_prisoner", actor, carried)):
		_call_void("_attach_carried_character", [carried])
		_call_void("_show_world_notice", ["Cell unavailable", Color(1.0, 0.78, 0.38, 1.0)])
		stop_place_in_cell_assignment()
		return
	notify_law_custody_placed(carried)
	_clear_actor_move_target()
	_set_node_property("_current_place_cell_target", null)
	_clear_place_cell_waypoints()
	_set_current_order_type(ORDER_TYPE_NONE)
	_call_void("_show_world_notice", ["Placed in cell", Color(0.55, 0.72, 1.0, 1.0)])
	_emit_actor_signal("state_changed")
	_emit_node_signal(carried, "state_changed")


func process_place_in_furnace_interaction() -> void:
	var furnace = _node_property("_current_place_furnace_target")
	if not _is_valid_node(furnace):
		stop_place_in_furnace_assignment()
		return
	var carried = _node_property("_carried_character")
	if not _is_valid_node(carried):
		stop_place_in_furnace_assignment()
		return
	if furnace.has_method("can_accept_body") and not bool(furnace.call("can_accept_body", carried)):
		stop_place_in_furnace_assignment()
		return
	var interaction_position: Vector3 = furnace.call("get_interaction_position", actor)
	if _position().distance_to(interaction_position) > _actor_float("interact_distance", 1.8):
		_set_actor_move_target(interaction_position)
		return
	if _actor_bool("_has_move_target", false):
		_clear_actor_move_target()
	_call("_detach_carried_character")
	if not furnace.has_method("place_carried_body") or not bool(furnace.call("place_carried_body", actor, carried)):
		_call_void("_attach_carried_character", [carried])
		_call_void("_show_world_notice", ["Furnace unavailable", Color(1.0, 0.78, 0.38, 1.0)])
		stop_place_in_furnace_assignment()
		_call_void("_set_auto_burn_backoff", [_actor_float("auto_burn_failed_backoff_seconds", 5.0)])
		return
	_clear_actor_move_target()
	_set_node_property("_current_place_furnace_target", null)
	_set_current_order_type(ORDER_TYPE_NONE)
	_call_void("_release_auto_burn_reservations")
	_call_void("_show_world_notice", ["Burning", Color(1.0, 0.45, 0.12, 1.0)])
	_emit_actor_signal("state_changed")
	_emit_node_signal(carried, "state_changed")


func process_sleep_interaction() -> void:
	var sleep_target = _node_property("_current_sleep_target")
	if not _is_valid_node(sleep_target):
		stop_sleep_assignment()
		return
	var interaction_position: Vector3 = sleep_target.call("get_interaction_position", actor)
	if _position().distance_to(interaction_position) > _actor_float("interact_distance", 1.8):
		_set_actor_move_target(interaction_position)
		return
	if _actor_bool("_has_move_target", false):
		return
	var sleep_result: Dictionary = sleep_target.call("request_sleep", actor) if sleep_target.has_method("request_sleep") else {"allowed": true, "message": ""}
	if not bool(sleep_result.get("allowed", false)):
		var failure_message := str(sleep_result.get("message", "Cannot sleep here"))
		if not failure_message.is_empty():
			_emit_actor_signal("center_notice_requested", [failure_message])
			_call_void("_show_world_notice", [failure_message, Color(1.0, 0.78, 0.38, 1.0)])
		stop_sleep_assignment()
		return
	if not sleep_target.call("claim_sleeper", actor):
		_emit_actor_signal("center_notice_requested", ["Bed occupied"])
		_call_void("_show_world_notice", ["Bed occupied", Color(1.0, 0.78, 0.38, 1.0)])
		stop_sleep_assignment()
		return
	var success_message := str(sleep_result.get("message", ""))
	if not success_message.is_empty():
		_emit_actor_signal("center_notice_requested", [success_message])
	_set_actor_global_position(sleep_target.call("get_sleep_position"))
	_set_actor_rotation(sleep_target.call("get_sleep_rotation"))
	_set_node_property("velocity", Vector3.ZERO)
	_set_node_property("running", false)
	_call_void("_set_sneaking_state", [false, false])
	_clear_actor_move_target()
	_set_node_property("life_state", NpcRules.LifeState.ASLEEP)
	_call_void("_show_world_notice", ["Sleeping", Color(0.55, 0.72, 1.0, 1.0)])
	_emit_actor_signal("state_changed")


func process_seat_interaction() -> void:
	var seat_target = _node_property("_current_seat_target")
	if not _is_valid_node(seat_target):
		stop_seat_assignment()
		return
	if _actor_bool("_is_sitting", false):
		_set_node_property("velocity", Vector3.ZERO)
		return
	var interaction_position: Vector3 = seat_target.call("get_interaction_position", actor)
	var arrival_distance := _actor_float("interact_distance", 1.8)
	if seat_target.has_method("get_arrival_distance"):
		arrival_distance = maxf(arrival_distance, float(seat_target.call("get_arrival_distance")))
	var can_snap_to_seat := false
	if seat_target.has_method("can_sit_from_position"):
		can_snap_to_seat = bool(seat_target.call("can_sit_from_position", _position()))
	else:
		can_snap_to_seat = _position().distance_to(interaction_position) <= arrival_distance
	if not can_snap_to_seat:
		_set_actor_move_target(interaction_position)
		return
	_clear_actor_move_target()
	if not bool(seat_target.call("claim_sitter", actor)):
		_call_void("_show_world_notice", ["Seat occupied", Color(1.0, 0.78, 0.38, 1.0)])
		stop_seat_assignment()
		return
	_set_actor_global_position(seat_target.call("get_seat_position", actor))
	_set_actor_rotation(seat_target.call("get_seat_rotation", actor))
	_set_node_property("velocity", Vector3.ZERO)
	_set_node_property("running", false)
	_call_void("_set_sneaking_state", [false, false])
	_clear_actor_move_target()
	_set_node_property("_is_sitting", true)
	_call_void("_start_sitting_enter_animation")
	_set_current_order_type(ORDER_TYPE_NONE)
	_call_void("_show_world_notice", ["Sitting", Color(0.55, 0.72, 1.0, 1.0)])
	_emit_actor_signal("state_changed")


func process_pickup_interaction() -> void:
	var pickup_item = _node_property("_current_pickup_item")
	if not _is_valid_node(pickup_item):
		stop_pickup_assignment()
		return
	if try_complete_pickup_interaction(_actor_float("PICKUP_GRAB_EXTRA_DISTANCE", 0.1)):
		return
	var pickup_position := get_pickup_route_position(pickup_item)
	if _horizontal_distance_to(pickup_position) > _move_target_arrival_distance():
		_set_actor_move_target(pickup_position)
		return
	if try_complete_pickup_interaction(_actor_float("PICKUP_UNREACHABLE_EXTRA_DISTANCE", 0.25)):
		return
	if _actor_bool("_order_was_player_issued", false):
		_call_void("show_world_speech", ["I can't reach that", 4.0])
	stop_pickup_assignment()


func try_complete_pickup_interaction(extra_distance := 0.0) -> bool:
	var pickup_item = _node_property("_current_pickup_item")
	if not _is_valid_node(pickup_item):
		stop_pickup_assignment()
		return true
	if not can_pickup_item_from_position(pickup_item, _position(), extra_distance):
		return false
	_clear_actor_move_target()
	if pickup_item.has_method("try_pickup"):
		pickup_item.call("try_pickup", actor)
	stop_pickup_assignment()
	return true


func can_pickup_item_from_position(item, actor_position: Vector3, extra_distance := 0.0) -> bool:
	if not _is_valid_node(item):
		return false
	var reach_distance := _actor_float("interact_distance", 1.8) + maxf(extra_distance, 0.0)
	if item.has_method("is_pickup_reachable_from"):
		return bool(item.call("is_pickup_reachable_from", actor, actor_position, reach_distance))
	return actor_position.distance_to(get_pickup_route_position(item)) <= reach_distance


func get_pickup_route_position(item) -> Vector3:
	if not _is_valid_node(item):
		return _position()
	if item.has_method("get_pickup_position"):
		return item.call("get_pickup_position", actor)
	if item is Node3D:
		return (item as Node3D).global_position
	return _position()


func validate_carried_order_targets() -> void:
	if _current_order_type() == ORDER_TYPE_CARRY:
		var carry_target = _node_property("_current_carry_target")
		if not _is_valid_node(carry_target) or not _node_call_bool(carry_target, "can_be_carried_by", [actor]):
			stop_carry_assignment()
	if _current_order_type() == ORDER_TYPE_PLACE_IN_BED:
		if not _is_valid_node(_node_property("_current_place_bed_target")) or not _is_valid_node(_node_property("_carried_character")):
			stop_place_in_bed_assignment()
	if _current_order_type() == ORDER_TYPE_PLACE_IN_CELL:
		if not _is_valid_node(_node_property("_current_place_cell_target")) or not _is_valid_node(_node_property("_carried_character")):
			stop_place_in_cell_assignment()
	if _current_order_type() == ORDER_TYPE_PLACE_IN_FURNACE:
		if not _is_valid_node(_node_property("_current_place_furnace_target")) or not _is_valid_node(_node_property("_carried_character")):
			stop_place_in_furnace_assignment()


func release_place_furnace_reservation() -> void:
	var furnace = _node_property("_current_place_furnace_target")
	if _is_valid_node(furnace) and furnace.has_method("release_reservation"):
		furnace.call("release_reservation", actor, _node_property("_carried_character"))
	if _node_property("_auto_burn_reserved_furnace") == furnace:
		_set_node_property("_auto_burn_reserved_furnace", null)


func notify_law_custody_placed(placed_actor) -> void:
	if placed_actor == null or actor == null or not is_instance_valid(actor):
		return
	var tree := actor.get_tree()
	if tree == null:
		return
	for controller in tree.get_nodes_in_group("law_order_controller"):
		if controller != null and controller.has_method("complete_custody_if_placed") and bool(controller.call("complete_custody_if_placed", placed_actor)):
			return


func get_place_cell_route(cell) -> Array[Vector3]:
	var route: Array[Vector3] = []
	if cell != null and cell.has_method("get_interaction_route"):
		for point in cell.call("get_interaction_route", actor):
			if point is Vector3:
				route.append(point)
	var final_position: Vector3 = cell.call("get_interaction_position", actor)
	if route.is_empty() or route[route.size() - 1].distance_squared_to(final_position) > 0.04:
		route.append(final_position)
	return route


func set_next_place_cell_move_target(final_position: Vector3) -> void:
	var waypoints: Array = _node_property("_current_place_cell_waypoints") if _node_property("_current_place_cell_waypoints") is Array else []
	while not waypoints.is_empty() and _position().distance_to(waypoints[0]) <= _actor_float("interact_distance", 1.8):
		waypoints.remove_at(0)
	var next_position := final_position
	if not waypoints.is_empty():
		next_position = waypoints[0]
	var move_target = _node_property("_move_target")
	if _actor_bool("_has_move_target", false) and move_target is Vector3 and move_target.distance_squared_to(next_position) <= 0.04:
		_set_node_property("_current_place_cell_waypoints", waypoints)
		return
	_set_node_property("_current_place_cell_waypoints", waypoints)
	_set_actor_move_target(next_position)


func get_conversation_interaction_distance() -> float:
	if _actor_bool("_order_was_player_issued", false) and _actor_bool("_is_sitting", false):
		return _actor_float("interact_distance", 1.8) * maxf(1.0, _actor_float("seated_player_talk_distance_multiplier", 2.0))
	return _actor_float("interact_distance", 1.8)


func ensure_mining_tool_equipped(mining_node: MiningResourceNode, issued_by_player: bool) -> bool:
	if mining_node == null:
		return false
	var required_tag := str(mining_node.required_tool_tag)
	if required_tag.is_empty():
		return true
	var equipped_weapon := _call("get_equipped_item", [ItemDefinition.EQUIP_SLOT_WEAPON]) as ItemDefinition
	if item_has_tool_tag(equipped_weapon, required_tag):
		return true
	var tool := find_inventory_tool(required_tag)
	if tool == null:
		show_mining_notice("%s required" % get_mining_tool_label(mining_node), Color(1.0, 0.68, 0.24, 1.0), issued_by_player)
		return false
	var inventory = _inventory()
	if inventory == null or not inventory.remove_item_count(tool, 1):
		show_mining_notice("%s required" % get_mining_tool_label(mining_node), Color(1.0, 0.68, 0.24, 1.0), issued_by_player)
		return false
	var previous_weapon := _call("get_equipped_item", [ItemDefinition.EQUIP_SLOT_WEAPON]) as ItemDefinition
	if previous_weapon != null and not inventory.can_add_item(previous_weapon):
		inventory.add_item(tool)
		show_mining_notice("No room to stow weapon", Color(1.0, 0.38, 0.28, 1.0), issued_by_player)
		return false
	_call_void("begin_equipment_update_batch")
	var replaced := _call("equip_item_to_slot", [tool, ItemDefinition.EQUIP_SLOT_WEAPON]) as ItemDefinition
	var stowed := true
	if replaced != null:
		stowed = inventory.add_item(replaced)
	if not stowed:
		_call("equip_item_to_slot", [replaced, ItemDefinition.EQUIP_SLOT_WEAPON])
		inventory.add_item(tool)
	_call_void("end_equipment_update_batch")
	if not stowed:
		show_mining_notice("No room to stow weapon", Color(1.0, 0.38, 0.28, 1.0), issued_by_player)
		return false
	return true


func find_inventory_tool(required_tag: String) -> ItemDefinition:
	var inventory = _inventory()
	if required_tag.is_empty() or inventory == null:
		return null
	for entry in inventory.entries:
		if item_has_tool_tag(entry.definition, required_tag):
			return entry.definition
	return null


func item_has_tool_tag(item: ItemDefinition, required_tag: String) -> bool:
	return item != null and item.has_method("has_tool_tag") and item.has_tool_tag(required_tag)


func get_mining_tool_label(mining_node: MiningResourceNode) -> String:
	if mining_node != null and not str(mining_node.required_tool_label).is_empty():
		return str(mining_node.required_tool_label)
	return "Tool"


func show_mining_requirement_notice(mining_node: MiningResourceNode) -> void:
	show_mining_notice("Mining %d required" % mining_node.required_mining_level, Color(1.0, 0.68, 0.24, 1.0), _actor_bool("_order_was_player_issued", false))


func show_mining_notice(message: String, color: Color, center_notice: bool) -> void:
	if center_notice:
		_emit_actor_signal("center_notice_requested", [message])
	_call_void("_show_world_notice", [message, color, 1.2, 0.45])


func show_scavenging_notice(message: String, color: Color, center_notice: bool) -> void:
	if center_notice and _actor_bool("_order_was_player_issued", false):
		_emit_actor_signal("center_notice_requested", [message])
	_call_void("_show_world_notice", [message, color, 1.2, 0.45])


func get_scavenging_notice_color(result: Dictionary) -> Color:
	if bool(result.get("useful", false)):
		return Color(0.5, 1.0, 0.65, 1.0)
	if bool(result.get("dropped", false)):
		return Color(1.0, 0.82, 0.36, 1.0)
	return Color(0.74, 0.68, 0.55, 1.0)


func award_mining_progress_xp(progress_delta: float, xp_multiplier := 1.0) -> void:
	if progress_delta <= 0.0 or xp_multiplier <= 0.0:
		return
	var mining_xp := SkillRules.get_xp_to_next_level(SkillRules.DEFAULT_LEVEL) / MINING_ORE_WORTH_FOR_FIRST_LEVEL * progress_delta * xp_multiplier
	_call_void("add_skill_xp", [SkillRules.LABOR_MINING, mining_xp, "mining"])
	_call_void("add_skill_xp", [SkillRules.ATTRIBUTE_STRENGTH, mining_xp * MINING_STRENGTH_XP_FACTOR, "mining"])


func award_scavenging_progress_xp(progress_delta: float) -> void:
	if progress_delta <= 0.0:
		return
	var scavenging_xp := SkillRules.get_xp_to_next_level(SkillRules.DEFAULT_LEVEL) / SCAVENGING_ATTEMPTS_FOR_FIRST_LEVEL * progress_delta
	_call_void("add_skill_xp", [SkillRules.LABOR_SCAVENGING, scavenging_xp, "scavenging"])
	_call_void("add_skill_xp", [SkillRules.ATTRIBUTE_PERCEPTION, scavenging_xp * 0.03, "scavenging"])
	_call_void("add_skill_xp", [SkillRules.ATTRIBUTE_DEXTERITY, scavenging_xp * 0.02, "scavenging"])


func get_stored_mining_progress(resource_node) -> float:
	if resource_node == null:
		return 0.0
	var progress_map: Dictionary = _node_property("_mining_progress_by_node") if _node_property("_mining_progress_by_node") is Dictionary else {}
	return clampf(progress_map.get(resource_node.get_instance_id(), 0.0), 0.0, 1.0)


func store_mining_progress(resource_node, progress: float) -> void:
	if resource_node == null:
		return
	var progress_map: Dictionary = _node_property("_mining_progress_by_node") if _node_property("_mining_progress_by_node") is Dictionary else {}
	progress_map[resource_node.get_instance_id()] = clampf(progress, 0.0, 1.0)
	_set_node_property("_mining_progress_by_node", progress_map)


func get_stored_scavenging_progress(resource_node) -> float:
	if resource_node == null:
		return 0.0
	var progress_map: Dictionary = _node_property("_scavenging_progress_by_node") if _node_property("_scavenging_progress_by_node") is Dictionary else {}
	return clampf(progress_map.get(resource_node.get_instance_id(), 0.0), 0.0, 1.0)


func store_scavenging_progress(resource_node, progress: float) -> void:
	if resource_node == null:
		return
	var progress_map: Dictionary = _node_property("_scavenging_progress_by_node") if _node_property("_scavenging_progress_by_node") is Dictionary else {}
	progress_map[resource_node.get_instance_id()] = clampf(progress, 0.0, 1.0)
	_set_node_property("_scavenging_progress_by_node", progress_map)


func _set_order(order_type: int, issued_by_player: bool, preserve_seat := false) -> bool:
	return _call_bool("_set_order", [order_type, issued_by_player, preserve_seat])


func _set_actor_move_target(target_position: Vector3) -> void:
	_call_void("_set_actor_move_target", [target_position])


func _clear_actor_move_target() -> void:
	_call_void("_clear_actor_move_target")


func _current_order_type() -> int:
	return _actor_int("_current_order_type", ORDER_TYPE_NONE)


func _set_current_order_type(order_type: int) -> void:
	_set_node_property("_current_order_type", order_type)


func _position() -> Vector3:
	return (actor as Node3D).global_position if actor is Node3D else Vector3.ZERO


func _position_of(target) -> Vector3:
	return (target as Node3D).global_position if target is Node3D else Vector3.ZERO


func _interaction_position_of(target) -> Vector3:
	if _is_valid_node(target) and target.has_method("get_interaction_position"):
		var result = target.call("get_interaction_position", actor)
		if result is Vector3:
			return result
	return _position_of(target)


func _set_actor_global_position(position: Vector3) -> void:
	if actor is Node3D:
		(actor as Node3D).global_position = position


func _actor_rotation() -> Vector3:
	var value = _node_property("rotation")
	return value if value is Vector3 else Vector3.ZERO


func _set_actor_rotation(rotation: Vector3) -> void:
	_set_node_property("rotation", rotation)


func _horizontal_distance_to(target_position: Vector3) -> float:
	var current_position := _position()
	return Vector2(current_position.x - target_position.x, current_position.z - target_position.z).length()


func _move_target_arrival_distance() -> float:
	var value = _call("_get_move_target_arrival_distance")
	return float(value) if value != null else _actor_float("interact_distance", 1.8)


func _actor_life_state() -> int:
	return _actor_int("life_state", NpcRules.LifeState.DEAD)


func _is_actor_alive() -> bool:
	return _actor_life_state() == NpcRules.LifeState.ALIVE


func _is_valid_node(value) -> bool:
	return value != null and is_instance_valid(value)


func _is_finish_off_target_valid(target) -> bool:
	if not _is_valid_node(target):
		return false
	if not _node_call_bool(target, "is_downed_state"):
		return false
	return not _node_call_bool(target, "requires_fire_to_die") or _node_call_bool(target, "can_be_destroyed_by_cinder")


func _node_display_name(value) -> String:
	if value == null:
		return "target"
	var display_name := str(value.get("member_name"))
	return display_name if not display_name.is_empty() else str(value.name)


func _set_node3d_position(value, position: Vector3) -> void:
	if value is Node3D:
		(value as Node3D).global_position = position


func _clear_place_cell_waypoints() -> void:
	var empty: Array[Vector3] = []
	_set_node_property("_current_place_cell_waypoints", empty)


func _inventory():
	return actor.get("inventory") if actor != null and is_instance_valid(actor) else null


func _work_inventory_override():
	return actor.get("_work_inventory_override") if actor != null and is_instance_valid(actor) else null


func _node_property(property_name: String):
	return actor.get(property_name) if actor != null and is_instance_valid(actor) else null


func _set_node_property(property_name: String, value) -> void:
	if actor != null and is_instance_valid(actor):
		actor.set(property_name, value)


func _actor_float(property_name: String, fallback: float) -> float:
	var value = _node_property(property_name)
	return float(value) if value != null else fallback


func _actor_int(property_name: String, fallback: int) -> int:
	var value = _node_property(property_name)
	return int(value) if value != null else fallback


func _actor_bool(property_name: String, fallback: bool) -> bool:
	var value = _node_property(property_name)
	return bool(value) if value != null else fallback


func _call(method_name: StringName, args: Array = []):
	if actor != null and is_instance_valid(actor) and actor.has_method(method_name):
		return actor.callv(method_name, args)
	return null


func _call_void(method_name: StringName, args: Array = []) -> void:
	if actor != null and is_instance_valid(actor) and actor.has_method(method_name):
		actor.callv(method_name, args)


func _call_bool(method_name: StringName, args: Array = [], fallback := false) -> bool:
	if actor != null and is_instance_valid(actor) and actor.has_method(method_name):
		return bool(actor.callv(method_name, args))
	return fallback


func _node_call_bool(target, method_name: StringName, args: Array = [], fallback := false) -> bool:
	if target != null and is_instance_valid(target) and target.has_method(method_name):
		return bool(target.callv(method_name, args))
	return fallback


func _call_node_void(target, method_name: StringName, args: Array = []) -> void:
	if target != null and is_instance_valid(target) and target.has_method(method_name):
		target.callv(method_name, args)


func _emit_actor_signal(signal_name: StringName, args: Array = []) -> void:
	if actor != null and is_instance_valid(actor) and actor.has_signal(signal_name):
		match args.size():
			0:
				actor.emit_signal(signal_name)
			1:
				actor.emit_signal(signal_name, args[0])
			2:
				actor.emit_signal(signal_name, args[0], args[1])
			_:
				actor.emit_signal(signal_name, args[0], args[1], args[2])


func _emit_node_signal(target, signal_name: StringName, args: Array = []) -> void:
	if target != null and is_instance_valid(target) and target.has_signal(signal_name):
		match args.size():
			0:
				target.emit_signal(signal_name)
			1:
				target.emit_signal(signal_name, args[0])
			2:
				target.emit_signal(signal_name, args[0], args[1])
			_:
				target.emit_signal(signal_name, args[0], args[1], args[2])
