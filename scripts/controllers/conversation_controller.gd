extends Node

class_name ConversationController

const PLAYER_PARTY_ID := "player_party"

var root_scene: Node
var hud_layer: CanvasLayer
var conversation_window: Control
var active_speaker_actor_id := ""
var active_target_actor_id := ""
var active_definition: Resource
var active_node: Resource
var transcript_lines: PackedStringArray = PackedStringArray()
var displayed_actions: Array[Dictionary] = []
var _initialized := false


func initialize(target_root: Node, target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	hud_layer = target_hud
	_do_initialize()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("conversation_controller")
	_do_initialize()


func begin_conversation(speaker_actor_id: String, target_actor_id: String) -> void:
	_do_initialize()
	var speaker_id := speaker_actor_id.strip_edges()
	var target_id := target_actor_id.strip_edges()
	if not _initialized or speaker_id.is_empty() or target_id.is_empty():
		return
	var target_record := _population_record(target_id)
	var definition := _conversation_definition_for_record(target_record)
	if definition == null:
		return
	active_speaker_actor_id = speaker_id
	active_target_actor_id = target_id
	active_definition = definition
	active_node = null
	transcript_lines.clear()
	displayed_actions.clear()
	_show_node(definition.call("get_node_by_id", str(definition.get("start_node_id"))))


func _do_initialize() -> void:
	if _initialized:
		return
	if root_scene == null and is_inside_tree():
		root_scene = get_tree().current_scene
	if hud_layer == null and root_scene != null:
		hud_layer = root_scene.get_node_or_null("GameHUD") as CanvasLayer
	if hud_layer == null:
		return
	conversation_window = hud_layer.get_node_or_null("ConversationWindow") as Control
	if conversation_window == null:
		return
	conversation_window.process_mode = Node.PROCESS_MODE_ALWAYS
	var response_callable := Callable(self, "_on_response_selected")
	if conversation_window.has_signal("response_selected") and not conversation_window.is_connected("response_selected", response_callable):
		conversation_window.connect("response_selected", response_callable)
	_initialized = true


func _show_node(node: Resource) -> void:
	if node == null:
		_end_conversation()
		return
	active_node = node
	_apply_effects(node.get("effects") if node.get("effects") is Array else [])
	var speaker_name := str(node.get("speaker_name")).strip_edges()
	if speaker_name.is_empty():
		speaker_name = _actor_name(active_target_actor_id)
	var node_text := str(node.get("text"))
	transcript_lines.append("%s: %s" % [speaker_name, node_text])
	var response_data: Array = []
	displayed_actions.clear()
	var responses: Array = node.get("responses") if node.get("responses") is Array else []
	for response in responses:
		if response == null:
			continue
		if not _response_visible(response):
			continue
		response_data.append({"text": str(response.get("text")), "disabled": false})
		displayed_actions.append({"type": "authored", "response": response})
	_append_job_offer_options(response_data)
	if bool(node.get("ends_conversation")) and response_data.is_empty():
		response_data.append({"text": "End conversation", "disabled": false})
		displayed_actions.append({"type": "leave"})
	response_data.append({"text": "Leave", "disabled": false})
	displayed_actions.append({"type": "leave"})
	conversation_window.call("show_conversation", speaker_name, "\n\n".join(transcript_lines), response_data, _actor_display_payload(active_speaker_actor_id), _actor_display_payload(active_target_actor_id))


func _on_response_selected(response_index: int) -> void:
	if response_index < 0 or response_index >= displayed_actions.size():
		return
	var action := displayed_actions[response_index]
	match str(action.get("type", "")):
		"authored":
			var response = action.get("response")
			if response == null:
				_end_conversation()
				return
			transcript_lines.append("%s: %s" % [_actor_name(active_speaker_actor_id), str(response.get("text"))])
			_apply_effects(response.get("effects") if response.get("effects") is Array else [])
			var next_node_id := str(response.get("next_node_id", "")).strip_edges()
			if next_node_id.is_empty():
				_end_conversation()
				return
			_show_node(active_definition.call("get_node_by_id", next_node_id))
		"job_offer":
			_handle_job_offer(action.get("offer", {}) if action.get("offer", {}) is Dictionary else {})
		"leave":
			_end_conversation()
		_:
			_end_conversation()


func _append_job_offer_options(response_data: Array) -> void:
	var target_record := _population_record(active_target_actor_id)
	var traits: Dictionary = target_record.get("traits", {}) if target_record.get("traits", {}) is Dictionary else {}
	var offers: Array = traits.get("job_offers", []) if traits.get("job_offers", []) is Array else []
	for offer in offers:
		if not (offer is Dictionary):
			continue
		var label := str((offer as Dictionary).get("display_name", "work")).strip_edges().to_lower()
		if label.is_empty():
			label = "work"
		response_data.append({"text": "Ask about %s" % label, "disabled": false})
		displayed_actions.append({"type": "job_offer", "offer": (offer as Dictionary).duplicate(true)})


func _handle_job_offer(offer: Dictionary) -> void:
	if offer.is_empty():
		_end_conversation()
		return
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("upsert_job_contract"):
		var provider_id := str(offer.get("provider_id", "job_provider:%s" % active_target_actor_id))
		var metadata := offer.duplicate(true)
		bridge.call("upsert_job_contract", {
			"actor_id": active_speaker_actor_id,
			"provider_id": provider_id,
			"provider_name": _actor_name(active_target_actor_id),
			"provider_owner_actor_id": active_target_actor_id,
			"job_id": str(offer.get("job_id", "job")),
			"job_index": int(offer.get("job_index", 0)),
			"algorithm_id": str(offer.get("algorithm_id", "manual")),
			"display_name": str(offer.get("display_name", "Work")),
			"status": "active",
			"metadata": metadata,
		})
	var message := str(offer.get("accept_text", "Work is available."))
	transcript_lines.append("%s: %s" % [_actor_name(active_target_actor_id), message])
	conversation_window.call("show_conversation", _actor_name(active_target_actor_id), "\n\n".join(transcript_lines), [{"text": "Leave", "disabled": false}], _actor_display_payload(active_speaker_actor_id), _actor_display_payload(active_target_actor_id))
	displayed_actions = [{"type": "leave"}]


func _response_visible(response) -> bool:
	var conditions: Array = response.get("visible_conditions") if response.get("visible_conditions") is Array else []
	for condition in conditions:
		if condition == null:
			continue
		if not _condition_passes(condition):
			return false
	return true


func _condition_passes(condition) -> bool:
	var passed := false
	match str(condition.get("condition_id", "")):
		"inventory.has_item_count":
			var parameters: Dictionary = condition.get("parameters", {}) if condition.get("parameters", {}) is Dictionary else {}
			var actor_id := active_speaker_actor_id if str(parameters.get("subject", "speaker_member")) == "speaker_member" else active_target_actor_id
			var item_definition = parameters.get("item_definition")
			var item_path := str(item_definition.resource_path) if item_definition is Resource else str(parameters.get("item_definition_path", ""))
			passed = _actor_item_count(actor_id, item_path) >= int(parameters.get("count", 1))
		_:
			passed = false
	return not passed if bool(condition.get("negate")) else passed


func _apply_effects(effects: Array) -> void:
	for effect in effects:
		if effect != null:
			_execute_effect(effect)


func _execute_effect(effect) -> void:
	match str(effect.get("action_id", "")):
		"core.start_trade":
			var inventory := _get_inventory_controller()
			if inventory != null and inventory.has_method("open_inventory_pair"):
				inventory.call("open_inventory_pair", active_speaker_actor_id, active_target_actor_id)
		"core.transfer_item":
			var parameters: Dictionary = effect.get("parameters", {}) if effect.get("parameters", {}) is Dictionary else {}
			var item_definition = parameters.get("item_definition")
			var item_path := str(item_definition.resource_path) if item_definition is Resource else str(parameters.get("item_definition_path", ""))
			var from_id := _subject_actor_id(str(parameters.get("from_subject", "speaker_member")))
			var to_id := _subject_actor_id(str(parameters.get("to_subject", "conversation_target")))
			_apply_inventory_command({"action": "transfer_item_count", "source_actor_id": from_id, "target_actor_id": to_id, "item_definition_path": item_path, "count": int(parameters.get("count", 1))})
		"core.join_party":
			var target_id := _subject_actor_id(str((effect.get("parameters", {}) as Dictionary).get("subject", "conversation_target")))
			_upsert_population_record({"actor_id": target_id, "role_id": "party_member", "party_id": PLAYER_PARTY_ID, "player_party_member": true, "player_controllable": true})
		"core.set_faction":
			var parameters: Dictionary = effect.get("parameters", {}) if effect.get("parameters", {}) is Dictionary else {}
			var target_id := _subject_actor_id(str(parameters.get("subject", "conversation_target")))
			_upsert_population_record({"actor_id": target_id, "faction_id": str(parameters.get("faction_name", ""))})
		_:
			return


func _subject_actor_id(subject_key: String) -> String:
	match subject_key:
		"speaker_member":
			return active_speaker_actor_id
		"conversation_target", "npc_self":
			return active_target_actor_id
	return ""


func _actor_item_count(actor_id: String, item_path: String) -> int:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_inventory_stacks") or not bridge.has_method("get_actor_inventory_container_id"):
		return 0
	var container_id := str(bridge.call("get_actor_inventory_container_id", actor_id))
	var total := 0
	for stack in bridge.call("get_inventory_stacks", container_id):
		if stack is Dictionary and str((stack as Dictionary).get("item_definition_path", "")) == item_path:
			total += int((stack as Dictionary).get("count", 1))
	return total


func _conversation_definition_for_record(record: Dictionary) -> Resource:
	var traits: Dictionary = record.get("traits", {}) if record.get("traits", {}) is Dictionary else {}
	var path := str(traits.get("conversation_definition_path", "")).strip_edges()
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path)


func _actor_display_payload(actor_id: String) -> Dictionary:
	var record := _population_record(actor_id)
	return {"actor_id": actor_id, "member_name": str(record.get("member_name", actor_id))}


func _actor_name(actor_id: String) -> String:
	var record := _population_record(actor_id)
	var member_name := str(record.get("member_name", actor_id)).strip_edges()
	return member_name if not member_name.is_empty() else actor_id


func _population_record(actor_id: String) -> Dictionary:
	var bridge := _get_gecs_world()
	if bridge == null:
		return {}
	var record = bridge.call("get_population_record", actor_id) if bridge.has_method("get_population_record") else {}
	return record if record is Dictionary else {}


func _upsert_population_record(record: Dictionary) -> Dictionary:
	var bridge := _get_gecs_world()
	if bridge == null or record.is_empty():
		return {}
	var updated = bridge.call("upsert_population_record_core", record) if bridge.has_method("upsert_population_record_core") else (bridge.call("upsert_population_record", record) if bridge.has_method("upsert_population_record") else {})
	return updated if updated is Dictionary else {}


func _apply_inventory_command(command: Dictionary) -> Dictionary:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("apply_inventory_command"):
		return {"ok": false, "message": "Missing inventory"}
	var result = bridge.call("apply_inventory_command", command)
	return result if result is Dictionary else {"ok": false, "message": "Invalid inventory result"}


func _end_conversation() -> void:
	if conversation_window != null and conversation_window.has_method("hide_conversation"):
		conversation_window.call("hide_conversation")
	active_speaker_actor_id = ""
	active_target_actor_id = ""
	active_definition = null
	active_node = null
	transcript_lines.clear()
	displayed_actions.clear()


func _get_gecs_world() -> Node:
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("GecsWorldController")
		if local != null:
			return local
	return get_tree().get_first_node_in_group("gecs_world_controller") if is_inside_tree() else null


func _get_inventory_controller() -> Node:
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("PartyInventoryController")
		if local != null:
			return local
	return get_tree().get_first_node_in_group("party_inventory_controller") if is_inside_tree() else null
