extends Node

class_name WorldPartyPanelController

const PARTY_PORTRAIT_CARD_SCENE := preload("res://scenes/ui/party_portrait_card.tscn")

@export var portrait_flow_path := NodePath("HudLayout/BottomHud/RightHud/BottomInfoRow/PortraitBar/Margin/PortraitColumn/PortraitScroll/PortraitFlow")
@export var squad_name_path := NodePath("HudLayout/BottomHud/RightHud/BottomInfoRow/PortraitBar/Margin/PortraitColumn/SquadCommandStrip/SquadName")
@export var all_button_path := NodePath("HudLayout/BottomHud/RightHud/BottomInfoRow/PortraitBar/Margin/PortraitColumn/SquadTabs/AllButton")
@export var add_squad_button_path := NodePath("HudLayout/BottomHud/RightHud/BottomInfoRow/PortraitBar/Margin/PortraitColumn/SquadTabs/AddSquadButton")
@export_range(0.05, 2.0, 0.05) var refresh_interval_seconds := 0.25

var root_scene: Node
var hud_layer: CanvasLayer
var _portrait_flow: Container
var _squad_name_label: Label
var _cards_by_actor_id: Dictionary = {}
var _latest_records: Array[Dictionary] = []
var _refresh_elapsed := 0.0
var _selected_actor_id_cache := ""
var _controlled_actor_ids_cache: Array[String] = []
var _equipment_slots_cache_by_actor_id: Dictionary = {}
var _equipment_slots_cache_dirty := true
var _equipment_signal_bridge: Node


func initialize(target_root: Node, target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	hud_layer = target_hud
	_bind_hud_nodes()
	_configure_static_controls()
	refresh_party_panel()


func _ready() -> void:
	add_to_group("world_party_panel_controller")


func _exit_tree() -> void:
	_disconnect_equipment_cache_signal()


func _process(delta: float) -> void:
	_refresh_elapsed += delta
	if _refresh_elapsed < refresh_interval_seconds:
		return
	_refresh_elapsed = 0.0
	refresh_party_panel()


func refresh_party_panel() -> Array[Dictionary]:
	_bind_hud_nodes()
	if _portrait_flow == null:
		return []
	_selected_actor_id_cache = _selected_actor_id()
	_controlled_actor_ids_cache = _controlled_actor_ids()
	var records := _party_records()
	_latest_records = records.duplicate(true)
	var expected_ids := {}
	for record in records:
		var actor_id := str(record.get("actor_id", record.get("stable_id", ""))).strip_edges()
		if actor_id.is_empty():
			continue
		expected_ids[actor_id] = true
		var card := _get_or_create_card(actor_id)
		if card == null:
			continue
		_apply_record_to_card(card, record)
	_remove_stale_cards(expected_ids)
	if _squad_name_label != null:
		_squad_name_label.text = "Party: %d" % records.size()
	return _latest_records.duplicate(true)


func get_party_panel_records() -> Array[Dictionary]:
	return _latest_records.duplicate(true)


func get_card_for_actor(actor_id: String) -> Button:
	var card = _cards_by_actor_id.get(actor_id)
	return card as Button if card != null and is_instance_valid(card) else null


func get_debug_state() -> Dictionary:
	var cards := {}
	for actor_id in _cards_by_actor_id.keys():
		var card := get_card_for_actor(str(actor_id))
		if card == null:
			continue
		var card_state: Dictionary = card.call("get_debug_state") if card.has_method("get_debug_state") else {}
		card_state.merge({
			"text": card.text,
			"pressed": card.button_pressed,
			"tooltip": card.tooltip_text,
			"record": card.get_meta("party_panel_record", {}).duplicate(true) if card.get_meta("party_panel_record", {}) is Dictionary else {},
		}, true)
		cards[str(actor_id)] = card_state
	return {
		"record_count": _latest_records.size(),
		"cards": cards,
		"squad_name": _squad_name_label.text if _squad_name_label != null else "",
	}


func _party_records() -> Array[Dictionary]:
	var bridge := _get_gecs_world()
	if bridge == null:
		return []
	var records_by_id := _get_population_records_core(bridge)
	var equipment_by_actor := _equipment_slots_by_actor(bridge)
	var result: Array[Dictionary] = []
	for actor_id_value in records_by_id.keys():
		var value = records_by_id[actor_id_value]
		if not (value is Dictionary):
			continue
		var record: Dictionary = (value as Dictionary).duplicate(true)
		if not _is_party_panel_record(record):
			continue
		var actor_id := str(record.get("actor_id", actor_id_value))
		result.append(_panel_record_from_population_record(record, equipment_by_actor.get(actor_id, {})))
	result.sort_custom(_sort_party_records)
	return result


func _is_party_panel_record(record: Dictionary) -> bool:
	return bool(record.get("player_party_member", false)) or bool(record.get("player_controllable", false)) or not str(record.get("party_id", "")).strip_edges().is_empty()


func _panel_record_from_population_record(record: Dictionary, equipment_slots: Dictionary = {}) -> Dictionary:
	var actor_id := str(record.get("actor_id", record.get("stable_id", ""))).strip_edges()
	var skill_levels: Dictionary = record.get("skill_levels", {}) if record.get("skill_levels", {}) is Dictionary else {}
	var squad_record := _squad_record_for_record(record)
	var life_state := int(record.get("life_state", 0))
	return {
		"actor_id": actor_id,
		"member_name": str(record.get("member_name", actor_id)),
		"faction_id": str(record.get("faction_id", "")),
		"party_id": str(record.get("party_id", "")),
		"squad_name": str(record.get("squad_name", "")),
		"role_id": str(record.get("role_id", "")),
		"player_party_member": bool(record.get("player_party_member", false)),
		"player_controllable": bool(record.get("player_controllable", false)),
		"life_state": life_state,
		"life_state_text": _life_state_text(life_state),
		"hp": float(record.get("hp", 0.0)),
		"max_hp": float(record.get("max_hp", 0.0)),
		"blood": float(record.get("blood", 0.0)),
		"max_blood": float(record.get("max_blood", 0.0)),
		"equipment_summary": _equipment_summary(equipment_slots),
		"objective_summary": _objective_summary(record, squad_record),
		"combat_summary": _combat_summary(record, squad_record),
		"stats_summary": _stats_summary(skill_levels),
		"selected": actor_id == _selected_actor_id_cache,
		"controlled": _controlled_actor_ids_cache.has(actor_id),
		"sort_key": _sort_key(record),
	}


func _get_or_create_card(actor_id: String) -> Button:
	var existing := get_card_for_actor(actor_id)
	if existing != null:
		return existing
	var instance := PARTY_PORTRAIT_CARD_SCENE.instantiate()
	var card := instance as Button
	if card == null:
		instance.queue_free()
		return null
	card.name = "PartyCard_%s" % _safe_node_name(actor_id)
	card.focus_mode = Control.FOCUS_NONE
	card.toggle_mode = true
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.text = ""
	card.add_to_group("party_panel_card")
	card.set_meta("actor_id", actor_id)
	if card.has_signal("portrait_pressed"):
		card.connect("portrait_pressed", Callable(self, "_on_party_card_portrait_pressed"))
	else:
		card.pressed.connect(_on_party_card_pressed.bind(actor_id))
	_portrait_flow.add_child(card)
	_cards_by_actor_id[actor_id] = card
	return card


func _apply_record_to_card(card: Button, record: Dictionary) -> void:
	var actor_id := str(record.get("actor_id", ""))
	var selected := bool(record.get("selected", false))
	var controlled := bool(record.get("controlled", false))
	card.set_meta("party_panel_record", record.duplicate(true))
	card.button_pressed = selected
	card.disabled = actor_id.is_empty()
	card.text = ""
	card.tooltip_text = "%s\n%s\n%s\n%s" % [
		str(record.get("combat_summary", "")),
		str(record.get("stats_summary", "")),
		"Faction: %s" % str(record.get("faction_id", "")),
		"Actor: %s" % actor_id,
	]
	var projection := _projection_for_actor(actor_id)
	if card.has_method("setup_projection"):
		card.call("setup_projection", record, projection)
	elif card.has_method("update_record"):
		card.call("update_record", record)
	if card.has_method("apply_state"):
		card.call("apply_state", selected, controlled)


func _remove_stale_cards(expected_ids: Dictionary) -> void:
	for actor_id_value in _cards_by_actor_id.keys():
		var actor_id := str(actor_id_value)
		if expected_ids.has(actor_id):
			continue
		var card := get_card_for_actor(actor_id)
		if card != null:
			card.queue_free()
		_cards_by_actor_id.erase(actor_id)


func _on_party_card_pressed(actor_id: String) -> void:
	var selection := _get_selection_controller()
	if selection != null and selection.has_method("select_actor_id"):
		selection.call("select_actor_id", actor_id)
	refresh_party_panel()


func _on_party_card_portrait_pressed(actor_id: String, double_click: bool, add_select: bool) -> void:
	var selection := _get_selection_controller()
	if selection != null and selection.has_method("select_actor_id"):
		selection.call("select_actor_id", actor_id, add_select)
	if double_click:
		_follow_actor_projection(actor_id)
	refresh_party_panel()


func _bind_hud_nodes() -> void:
	var hud := hud_layer if hud_layer != null else (root_scene.get_node_or_null("GameHUD") if root_scene != null else null)
	if hud == null:
		return
	if _portrait_flow == null or not is_instance_valid(_portrait_flow):
		_portrait_flow = hud.get_node_or_null(portrait_flow_path) as Container
	if _squad_name_label == null or not is_instance_valid(_squad_name_label):
		_squad_name_label = hud.get_node_or_null(squad_name_path) as Label


func _configure_static_controls() -> void:
	var hud := hud_layer if hud_layer != null else (root_scene.get_node_or_null("GameHUD") if root_scene != null else null)
	if hud == null:
		return
	var all_button := hud.get_node_or_null(all_button_path) as Button
	if all_button != null:
		all_button.button_pressed = true
		all_button.disabled = false
	var add_squad_button := hud.get_node_or_null(add_squad_button_path) as Button
	if add_squad_button != null:
		add_squad_button.disabled = true
		add_squad_button.tooltip_text = "Party membership is read from GECS."


func _selected_actor_id() -> String:
	var selection := _get_selection_controller()
	return str(selection.call("get_selected_actor_id")) if selection != null and selection.has_method("get_selected_actor_id") else ""


func _controlled_actor_ids() -> Array[String]:
	var control := _get_player_control_controller()
	if control == null or not control.has_method("get_control_state"):
		return []
	var state: Dictionary = control.call("get_control_state")
	if not bool(state.get("active", false)):
		return []
	var actor_ids: Array[String] = []
	var values: Array = state.get("actor_ids", []) if state.get("actor_ids", []) is Array else []
	for actor_id_value in values:
		var actor_id := str(actor_id_value).strip_edges()
		if not actor_id.is_empty():
			actor_ids.append(actor_id)
	return actor_ids


func _squad_record_for_record(record: Dictionary) -> Dictionary:
	var combat := _get_combat_controller()
	if combat == null or not combat.has_method("get_world_squad_state"):
		return {}
	var squad_state: Dictionary = combat.call("get_world_squad_state")
	var active_squads: Dictionary = squad_state.get("active_squads", {}) if squad_state.get("active_squads", {}) is Dictionary else {}
	var squad_name := str(record.get("squad_name", "")).strip_edges()
	var actor_id := str(record.get("actor_id", "")).strip_edges()
	if not squad_name.is_empty() and active_squads.has(squad_name) and active_squads[squad_name] is Dictionary:
		return (active_squads[squad_name] as Dictionary).duplicate(true)
	for squad in active_squads.values():
		if not (squad is Dictionary):
			continue
		var member_ids: Array = (squad as Dictionary).get("member_ids", []) if (squad as Dictionary).get("member_ids", []) is Array else []
		if member_ids.has(actor_id):
			return (squad as Dictionary).duplicate(true)
	return {}


func _objective_summary(record: Dictionary, squad_record: Dictionary) -> String:
	if not squad_record.is_empty():
		return "%s (%s)" % [_display_token(str(squad_record.get("objective_id", "hold_position"))), _display_token(str(squad_record.get("objective_state", "idle")))]
	var activity := str(record.get("ledger_activity_state", "routine")).strip_edges()
	return _display_token(activity if not activity.is_empty() else "routine")


func _combat_summary(record: Dictionary, squad_record: Dictionary) -> String:
	var parts: Array[String] = []
	parts.append("Stance: %s" % _stance_text(int(record.get("combat_stance", 0))))
	if not squad_record.is_empty():
		var encounter_id := str(squad_record.get("active_encounter_id", "")).strip_edges()
		parts.append("Encounter: %s" % (encounter_id if not encounter_id.is_empty() else "none"))
	return "; ".join(parts)


func _equipment_summary(equipment_slots: Dictionary) -> String:
	if equipment_slots.is_empty():
		return "Equipment: -"
	var preferred := ["weapon", "offhand", "chest"]
	var parts: Array[String] = []
	for slot_name in preferred:
		if equipment_slots.has(slot_name):
			parts.append("%s %s" % [_display_token(slot_name), _item_name(str(equipment_slots[slot_name]))])
	if parts.is_empty():
		for slot_name_value in equipment_slots.keys():
			parts.append("%s %s" % [_display_token(str(slot_name_value)), _item_name(str(equipment_slots[slot_name_value]))])
			if parts.size() >= 3:
				break
	return "; ".join(parts)


func _item_name(item_path: String) -> String:
	var identifier := item_path.strip_edges()
	return _display_token(identifier.get_file().get_basename() if identifier.begins_with("res://") else identifier)


func _stats_summary(skill_levels: Dictionary) -> String:
	var ids := ["attribute.strength", "attribute.dexterity", "attribute.endurance"]
	var parts: Array[String] = []
	for skill_id in ids:
		if skill_levels.has(skill_id):
			parts.append("%s %d" % [_short_skill_label(skill_id), int(skill_levels[skill_id])])
	return ", ".join(parts) if not parts.is_empty() else "Stats: -"


func _sort_key(record: Dictionary) -> String:
	var priority := "0" if bool(record.get("player_party_member", false)) else "1"
	return "%s:%04d:%s" % [priority, int(record.get("generation_index", 0)), str(record.get("member_name", record.get("actor_id", ""))).to_lower()]


func _sort_party_records(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("sort_key", "")) < str(b.get("sort_key", ""))


func _life_state_text(life_state: int) -> String:
	var label := NpcRules.get_life_state_label(life_state)
	return label if label != "Unknown" else "State %d" % life_state


func _stance_text(stance: int) -> String:
	match stance:
		0:
			return "Aggressive"
		1:
			return "Defensive"
		2:
			return "Passive"
	return "Stance %d" % stance


func _format_number(value: float) -> String:
	return str(int(round(value))) if is_equal_approx(value, round(value)) else "%.1f" % value


func _short_skill_label(skill_id: String) -> String:
	var text := skill_id.get_slice(".", skill_id.get_slice_count(".") - 1)
	var words := text.split("_")
	for index in range(words.size()):
		words[index] = str(words[index]).capitalize()
	return " ".join(words)


func _display_token(value: String) -> String:
	var text := value.strip_edges()
	if text.is_empty():
		return "-"
	var words := text.replace(".", "_").split("_")
	for index in range(words.size()):
		words[index] = str(words[index]).capitalize()
	return " ".join(words)


func _safe_node_name(value: String) -> String:
	var result := value.strip_edges()
	for character in [".", ":", "/", "\\", " "]:
		result = result.replace(character, "_")
	return result if not result.is_empty() else "unknown"


func _get_population_records_core(bridge: Node) -> Dictionary:
	if bridge.has_method("get_population_records_core"):
		var core_records = bridge.call("get_population_records_core")
		return core_records if core_records is Dictionary else {}
	if bridge.has_method("get_population_records"):
		var records = bridge.call("get_population_records")
		return records if records is Dictionary else {}
	return {}


func _equipment_slots_by_actor(bridge: Node) -> Dictionary:
	_bind_equipment_cache_signal(bridge)
	if _equipment_slots_cache_dirty:
		_equipment_slots_cache_by_actor_id = _load_equipment_slots_by_actor(bridge)
		_equipment_slots_cache_dirty = false
	return _equipment_slots_cache_by_actor_id


func _load_equipment_slots_by_actor(bridge: Node) -> Dictionary:
	var result := {}
	if bridge == null or not bridge.has_method("get_equipment_slots"):
		return result
	for slot in bridge.call("get_equipment_slots"):
		if not (slot is Dictionary):
			continue
		var actor_id := str((slot as Dictionary).get("actor_id", "")).strip_edges()
		var slot_name := str((slot as Dictionary).get("slot_name", "")).strip_edges()
		var item_id := str((slot as Dictionary).get("item_id", "")).strip_edges()
		if actor_id.is_empty() or slot_name.is_empty() or item_id.is_empty():
			continue
		var actor_slots: Dictionary = result.get(actor_id, {})
		actor_slots[slot_name] = item_id
		result[actor_id] = actor_slots
	return result


func _bind_equipment_cache_signal(bridge: Node) -> void:
	if bridge == _equipment_signal_bridge:
		return
	_disconnect_equipment_cache_signal()
	if bridge == null or not bridge.has_signal("inventory_state_changed"):
		return
	var callable := Callable(self, "_on_equipment_cache_changed")
	if bridge.is_connected("inventory_state_changed", callable):
		_equipment_signal_bridge = bridge
		return
	bridge.connect("inventory_state_changed", callable)
	_equipment_signal_bridge = bridge


func _disconnect_equipment_cache_signal() -> void:
	if _equipment_signal_bridge == null or not is_instance_valid(_equipment_signal_bridge):
		_equipment_signal_bridge = null
		return
	var callable := Callable(self, "_on_equipment_cache_changed")
	if _equipment_signal_bridge.has_signal("inventory_state_changed") and _equipment_signal_bridge.is_connected("inventory_state_changed", callable):
		_equipment_signal_bridge.disconnect("inventory_state_changed", callable)
	_equipment_signal_bridge = null


func _on_equipment_cache_changed(_result: Dictionary = {}) -> void:
	_equipment_slots_cache_dirty = true


func _get_gecs_world() -> Node:
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("GecsWorldController")
		if local != null:
			return local
	return get_tree().get_first_node_in_group("gecs_world_controller") if is_inside_tree() else null


func _get_selection_controller() -> Node:
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("WorldSelectionController")
		if local != null:
			return local
	return get_tree().get_first_node_in_group("world_selection_controller") if is_inside_tree() else null


func _get_player_control_controller() -> Node:
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("WorldPlayerControlController")
		if local != null:
			return local
	return get_tree().get_first_node_in_group("world_player_control_controller") if is_inside_tree() else null


func _projection_for_actor(actor_id: String) -> Node:
	var projection_controller := _get_projection_controller()
	if projection_controller == null or not projection_controller.has_method("get_projection_for_actor"):
		return null
	return projection_controller.call("get_projection_for_actor", actor_id) as Node


func _follow_actor_projection(actor_id: String) -> void:
	var projection := _projection_for_actor(actor_id) as Node3D
	if projection == null or root_scene == null:
		return
	var camera_rig := root_scene.find_child("CameraRig", true, false)
	if camera_rig != null and camera_rig.has_method("follow_target"):
		camera_rig.call("follow_target", projection)


func _get_projection_controller() -> Node:
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("WorldActorProjectionController")
		if local != null:
			return local
	return get_tree().get_first_node_in_group("world_actor_projection_controller") if is_inside_tree() else null


func _get_combat_controller() -> Node:
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("WorldMapCombatSimController")
		if local != null:
			return local
	return get_tree().get_first_node_in_group("world_map_combat_sim_controller") if is_inside_tree() else null
