extends Node

class_name ConversationController

const SILVER_ITEM = preload("res://resources/items/silver.tres")
const ACTOR_CONDITION_EVALUATOR_SCRIPT = preload("res://scripts/conditions/actor_condition_evaluator.gd")

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
var displayed_actions: Array = []
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
	var node_text: String = node.text
	if active_target != null and active_target.has_method("get_job_provider"):
		var provider = active_target.get_job_provider()
		if provider != null and provider.has_method("get_greeting_text_for") and node == active_definition.get_node_by_id(active_definition.start_node_id):
			node_text = provider.get_greeting_text_for(active_speaker, node_text)
	transcript_lines.append("%s: %s" % [speaker_name, node_text])
	var response_data: Array = []
	displayed_actions.clear()
	for response in node.responses:
		if response == null:
			continue
		var evaluation := _evaluate_response(response)
		if evaluation.get("visible", true):
			response_data.append({
				"text": response.text,
				"disabled": evaluation.get("disabled", false)
			})
			displayed_actions.append({"type": "authored", "response": response})
	if node.ends_conversation and response_data.is_empty():
		response_data.append({"text": "End conversation", "disabled": false})
	if active_target != null and active_target.has_method("get_job_provider"):
		var provider = active_target.get_job_provider()
		if provider != null:
			for option in provider.build_conversation_options(active_speaker):
				response_data.append({
					"text": option.get("text", ""),
					"disabled": false,
				})
				displayed_actions.append({"type": "dynamic", "option": option})
	response_data.append({"text": "Leave", "disabled": false})
	displayed_actions.append({"type": "leave"})
	if conversation_window != null:
		conversation_window.show_conversation(speaker_name, "\n\n".join(transcript_lines), response_data, active_speaker, active_target)
	get_tree().paused = true


func _on_response_selected(response_index: int) -> void:
	if active_node == null:
		return
	if response_index < 0 or response_index >= displayed_actions.size():
		return
	var action: Dictionary = displayed_actions[response_index]
	match str(action.get("type", "")):
		"authored":
			var response = action.get("response")
			if response == null:
				return
			transcript_lines.append("%s: %s" % [active_speaker.member_name, response.text])
			_apply_effects(response.effects)
			if response.next_node_id.is_empty():
				_end_conversation()
				return
			_show_node(active_definition.get_node_by_id(response.next_node_id))
		"dynamic":
			_handle_dynamic_response(action.get("option", {}))
		"leave":
			_end_conversation()
		_:
			_end_conversation()


func _handle_dynamic_response(option: Dictionary) -> void:
	if active_target == null or not active_target.has_method("get_job_provider"):
		return
	var provider = active_target.get_job_provider()
	if provider == null:
		return
	if option.get("disabled", false):
		if floating_notice != null and option.get("reason", "") != "":
			floating_notice.show_message(option.get("reason", ""))
		return
	transcript_lines.append("%s: %s" % [active_speaker.member_name, option.get("text", "")])
	var result: Dictionary = provider.handle_conversation_option(active_speaker, option)
	var provider_name: String = active_target.member_name if active_target != null else ""
	if result.get("speaker_text", "") != "":
		transcript_lines.append("%s: %s" % [provider_name, result.get("speaker_text", "")])
	_show_result_speech(result)
	_show_result_world_notice(result)
	if result.has("follow_up_options"):
		_show_follow_up_options(provider_name, result.get("follow_up_options", []))
		return
	if result.get("end_conversation", true):
		if floating_notice != null and result.get("speaker_text", "") != "" and result.get("show_floating_notice", true):
			floating_notice.show_message(result.get("speaker_text", ""))
		_end_conversation()
		return
	_show_node(active_node)


func _evaluate_response(response) -> Dictionary:
	var reason := ""
	for condition in response.visible_conditions:
		if condition == null:
			continue
		var result := ACTOR_CONDITION_EVALUATOR_SCRIPT.evaluate(condition, {
			"speaker_member": active_speaker,
			"conversation_target": active_target,
		})
		if not result.get("passed", false):
			reason = result.get("reason", condition.disabled_reason)
			return {"visible": false, "disabled": false, "reason": reason}
	return {"visible": true, "disabled": false, "reason": reason}


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
		"bar.start_venue_trade":
			if inventory_controller != null and active_speaker != null and active_target != null:
				var venue := _resolve_bar_venue(active_target)
				if venue == null:
					return
				if venue.get_owner_character() == null:
					return
				if venue.has_method("set_trade_proxy_position"):
					venue.set_trade_proxy_position(active_target.global_position)
				inventory_controller.open_inventory_for_owner(active_speaker)
				inventory_controller.open_inventory_for_owner(venue)
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


func _resolve_bar_venue(start_node: Node) -> BarVenue:
	var node := start_node
	while node != null:
		if node is BarVenue:
			return node
		node = node.get_parent()
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
	displayed_actions.clear()


func _show_follow_up_options(speaker_name: String, options: Array) -> void:
	var response_data: Array = []
	displayed_actions.clear()
	for option in options:
		response_data.append({"text": option.get("text", ""), "disabled": false})
		displayed_actions.append({"type": "dynamic", "option": option})
	if conversation_window != null:
		conversation_window.show_conversation(speaker_name, "\n\n".join(transcript_lines), response_data, active_speaker, active_target)


func _show_result_world_notice(result: Dictionary) -> void:
	var notice_target = result.get("world_notice_target")
	if notice_target == null:
		return
	if not is_instance_valid(notice_target):
		return
	if not notice_target.has_method("show_world_notice"):
		return
	var notice_text := str(result.get("world_notice_text", ""))
	if notice_text.is_empty():
		return
	var notice_color: Color = result.get("world_notice_color", Color(0.5, 1.0, 0.65, 1.0))
	var notice_lifetime := float(result.get("world_notice_lifetime", 1.0))
	notice_target.show_world_notice(notice_text, notice_color, notice_lifetime)


func _show_result_speech(result: Dictionary) -> void:
	var speech_target = result.get("speech_target")
	if speech_target == null:
		return
	if not is_instance_valid(speech_target):
		return
	if not speech_target.has_method("show_world_speech"):
		return
	var speech_text := str(result.get("speech_text", ""))
	if speech_text.is_empty():
		return
	var speech_lifetime := float(result.get("speech_lifetime", 5.0))
	speech_target.show_world_speech(speech_text, speech_lifetime)
