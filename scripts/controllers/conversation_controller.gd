extends Node

class_name ConversationController

const SILVER_ITEM = preload("res://resources/items/silver.tres")

var root_scene: Node
var hud_layer: CanvasLayer
var inventory_controller
var party_manager
var floating_notice
var conversation_window
var active_speaker
var active_target
var active_definition
var active_node
var transcript_lines: PackedStringArray = PackedStringArray()
var _initialized := false


func initialize(target_root: Node, target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	hud_layer = target_hud
	if is_inside_tree():
		_do_initialize()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	if root_scene != null:
		if hud_layer == null:
			hud_layer = root_scene.get_node_or_null("GameHUD")
		_do_initialize()


func _do_initialize() -> void:
	if _initialized or root_scene == null:
		return
	party_manager = root_scene.get_node_or_null("PartyManager")
	if hud_layer == null:
		hud_layer = root_scene.get_node_or_null("GameHUD")
	if hud_layer == null:
		return
	inventory_controller = get_parent().get_node_or_null("PartyInventoryController")
	conversation_window = hud_layer.get_node_or_null("ConversationWindow")
	floating_notice = hud_layer.get_node_or_null("FloatingNotice")
	if conversation_window != null:
		conversation_window.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
		conversation_window.response_selected.connect(_on_response_selected)
	_initialized = true


func begin_conversation(speaker, target) -> void:
	if not _initialized or speaker == null or target == null:
		return
	var definition = target.get_conversation_definition()
	if definition == null:
		return
	active_speaker = speaker
	active_target = target
	active_definition = definition
	transcript_lines.clear()
	_show_node(definition.get_node_by_id(definition.start_node_id))


func _show_node(node) -> void:
	if node == null:
		_end_conversation()
		return
	active_node = node
	_apply_effects(node.effects)
	var speaker_name: String = node.speaker_name
	if speaker_name.is_empty():
		speaker_name = active_target.member_name if active_target != null else ""
	transcript_lines.append("%s: %s" % [speaker_name, node.text])
	var response_data: Array = []
	for response in node.responses:
		if response == null:
			continue
		var evaluation := _evaluate_response(response)
		if evaluation.get("visible", true):
			response_data.append({
				"text": response.text,
				"disabled": evaluation.get("disabled", false)
			})
	if node.ends_conversation and response_data.is_empty():
		response_data.append({"text": "End conversation", "disabled": false})
	if conversation_window != null:
		conversation_window.show_conversation(speaker_name, "\n\n".join(transcript_lines), response_data, active_speaker, active_target)
	get_tree().paused = true


func _on_response_selected(response_index: int) -> void:
	if active_node == null:
		return
	var visible_responses: Array = []
	for response in active_node.responses:
		if response == null:
			continue
		var evaluation := _evaluate_response(response)
		if evaluation.get("visible", true):
			visible_responses.append(response)
	if response_index < 0 or response_index >= visible_responses.size():
		if active_node.ends_conversation and active_node.responses.is_empty() and response_index == 0:
			_end_conversation()
		return
	var response = visible_responses[response_index]
	var evaluation := _evaluate_response(response)
	if evaluation.get("disabled", false):
		if floating_notice != null and evaluation.get("reason", "") != "":
			floating_notice.show_message(evaluation.get("reason", ""))
		return
	transcript_lines.append("%s: %s" % [active_speaker.member_name, response.text])
	_apply_effects(response.effects)
	if response.next_node_id.is_empty():
		_end_conversation()
		return
	_show_node(active_definition.get_node_by_id(response.next_node_id))


func _evaluate_response(response) -> Dictionary:
	var reason := ""
	for condition in response.visible_conditions:
		if condition == null:
			continue
		if not _evaluate_condition(condition):
			reason = condition.disabled_reason
			return {"visible": false, "disabled": false, "reason": reason}
	return {"visible": true, "disabled": false, "reason": reason}


func _evaluate_condition(condition) -> bool:
	var result := true
	match condition.condition_id:
		"inventory.has_item_count":
			var actor = _resolve_subject(condition.parameters.get("subject", "speaker_member"))
			var item_definition = condition.parameters.get("item_definition")
			var count := int(condition.parameters.get("count", 0))
			result = actor != null and actor.inventory != null and item_definition != null and actor.inventory.count_item(item_definition) >= count
		_:
			result = false
	if condition.negate:
		return not result
	return result


func _apply_effects(effects: Array) -> void:
	for effect in effects:
		if effect == null:
			continue
		_execute_action(effect)


func _execute_action(effect) -> void:
	match effect.action_id:
		"core.start_trade":
			if inventory_controller != null and active_speaker != null and active_target != null:
				inventory_controller.open_inventory_for_owner(active_speaker)
				inventory_controller.open_inventory_for_owner(active_target)
		"core.start_combat":
			if active_target == null:
				return
			var attackers: Array = []
			if party_manager != null and not party_manager.selected_members.is_empty() and party_manager.selected_members.has(active_speaker):
				attackers = party_manager.selected_members.duplicate()
			elif active_speaker != null:
				attackers.append(active_speaker)
			for attacker in attackers:
				attacker.assign_attack_target(active_target)
		"core.transfer_item":
			var from_actor = _resolve_subject(effect.parameters.get("from_subject", "speaker_member"))
			var to_actor = _resolve_subject(effect.parameters.get("to_subject", "conversation_target"))
			var item_definition = effect.parameters.get("item_definition", SILVER_ITEM)
			var count := int(effect.parameters.get("count", 1))
			if from_actor == null or to_actor == null or item_definition == null or from_actor.inventory == null or to_actor.inventory == null:
				return
			if not from_actor.inventory.remove_item_count(item_definition, count):
				return
			if not to_actor.inventory.add_item_count(item_definition, count):
				from_actor.inventory.add_item_count(item_definition, count)
		"core.join_party":
			var target_actor = _resolve_subject(effect.parameters.get("subject", "conversation_target"))
			if target_actor != null:
				target_actor.set_player_party_member(true)
				if party_manager != null:
					party_manager.register_party_member(target_actor)
		"core.set_faction":
			var faction_actor = _resolve_subject(effect.parameters.get("subject", "conversation_target"))
			if faction_actor != null:
				faction_actor.faction_name = str(effect.parameters.get("faction_name", faction_actor.faction_name))
		_:
			return


func _resolve_subject(subject_key: Variant):
	match str(subject_key):
		"speaker_member":
			return active_speaker
		"conversation_target", "npc_self":
			return active_target
	return null


func _end_conversation() -> void:
	get_tree().paused = false
	if conversation_window != null:
		conversation_window.hide_conversation()
	active_speaker = null
	active_target = null
	active_definition = null
	active_node = null
	transcript_lines.clear()
