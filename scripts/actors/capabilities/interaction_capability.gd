extends "res://scripts/actors/capabilities/actor_capability.gd"

class_name InteractionCapability

const ORDER_TYPE_NONE := 0
const ORDER_TYPE_MINE := 2
const ORDER_TYPE_SCAVENGE := 3
const ORDER_TYPE_OPEN_CONTAINER := 4
const ORDER_TYPE_TRADE := 5
const ORDER_TYPE_TALK := 6
const MINING_ORE_WORTH_FOR_FIRST_LEVEL := 4.0
const MINING_STRENGTH_XP_FACTOR := 0.08
const SCAVENGING_ATTEMPTS_FOR_FIRST_LEVEL := 4.0


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
