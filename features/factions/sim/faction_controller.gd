extends Node

class_name FactionController

const SERVICE_ID := &"faction"

signal faction_relations_changed

const PLAYER_FACTION_ID := "Player"
const DIPLOMACY_WAR := "war"
const DIPLOMACY_HOSTILE := "hostile"
const DIPLOMACY_NEUTRAL := "neutral"
const DIPLOMACY_TRUCE := "truce"
const DIPLOMACY_TRADE := "trade"
const DIPLOMACY_ALLIANCE := "alliance"
const DIPLOMACY_VASSAL := "vassal"
const DIPLOMACY_TRIBUTARY := "tributary"
const DIPLOMACY_PROTECTORATE := "protectorate"
const DIRECTIONAL_STATES := [DIPLOMACY_VASSAL, DIPLOMACY_TRIBUTARY, DIPLOMACY_PROTECTORATE]
const FACTIONS_BUTTON_PARENT_PATH := NodePath("HudLayout/BottomHud/RightHud/BottomInfoRow/PortraitBar/Margin/PortraitColumn/SquadCommandStrip")
const FACTIONS_MENU_LAYER_PATH := NodePath("InventoryWindowLayer")

var root_scene: Node
var _context: BootstrapContext
var hud_layer: CanvasLayer
var faction_definitions: Dictionary = {}
var reputations: Dictionary = {}
var favor_points: Dictionary = {}
var diplomatic_states: Dictionary = {}
var faction_outlooks: Dictionary = {}
var help_allies := false
var _factions_button: Button
var _factions_window: PanelContainer
var _factions_title_bar: PanelContainer
var _factions_window_body: VBoxContainer
var _factions_dragging := false
var _factions_drag_offset := Vector2.ZERO


func initialize(context: BootstrapContext) -> void:
	_context = context
	root_scene = context.root_scene
	hud_layer = context.hud_layer
	_collect_definitions()
	refresh_from_gecs_state()
	_setup_factions_ui()


func _ready() -> void:
	add_to_group("faction_controller")
	_collect_definitions()
	refresh_from_gecs_state()
	_setup_factions_ui()


func register_faction(definition: Resource) -> void:
	if definition == null:
		return
	var faction_id: String = _resource_id(definition)
	if faction_id.is_empty():
		return
	faction_definitions[faction_id] = definition
	_apply_definition_starting_diplomacy(definition)


func get_faction_definition(faction_id: String) -> Resource:
	return faction_definitions.get(faction_id, null) as Resource


func get_faction_ids() -> Array:
	return faction_definitions.keys()


func are_hostile(faction_a: String, faction_b: String) -> bool:
	if faction_a.is_empty() or faction_b.is_empty() or faction_a == faction_b:
		return false
	var diplomatic_state := get_diplomatic_state(faction_a, faction_b)
	if diplomatic_state == DIPLOMACY_WAR or diplomatic_state == DIPLOMACY_HOSTILE:
		return true
	var definition_a: Resource = get_faction_definition(faction_a)
	if definition_a != null and (bool(definition_a.get("permanently_hostile")) or _resource_is_hostile_to(definition_a, faction_b)):
		return true
	var definition_b: Resource = get_faction_definition(faction_b)
	return definition_b != null and (bool(definition_b.get("permanently_hostile")) or _resource_is_hostile_to(definition_b, faction_a))


func get_diplomatic_state(faction_a: String, faction_b: String) -> String:
	if faction_a.is_empty() or faction_b.is_empty() or faction_a == faction_b:
		return DIPLOMACY_NEUTRAL
	var record: Dictionary = diplomatic_states.get(_relation_key(faction_a, faction_b), {})
	return str(record.get("state", DIPLOMACY_NEUTRAL))


func get_diplomatic_record(faction_a: String, faction_b: String) -> Dictionary:
	var record: Dictionary = diplomatic_states.get(_relation_key(faction_a, faction_b), {})
	if record.is_empty():
		return {
			"state": DIPLOMACY_NEUTRAL,
			"primary_faction_id": "",
			"secondary_faction_id": "",
		}
	return record.duplicate(true)


func set_diplomatic_state(faction_a: String, faction_b: String, state: String, primary_faction_id := "", secondary_faction_id := "") -> void:
	if faction_a.is_empty() or faction_b.is_empty() or faction_a == faction_b:
		return
	var normalized_state := state.strip_edges().to_lower()
	if normalized_state.is_empty():
		normalized_state = DIPLOMACY_NEUTRAL
	if DIRECTIONAL_STATES.has(normalized_state) and (primary_faction_id.is_empty() or secondary_faction_id.is_empty()):
		primary_faction_id = faction_a
		secondary_faction_id = faction_b
	diplomatic_states[_relation_key(faction_a, faction_b)] = {
		"state": normalized_state,
		"primary_faction_id": primary_faction_id,
		"secondary_faction_id": secondary_faction_id,
	}
	_save_faction_state_to_gecs()
	faction_relations_changed.emit()
	_refresh_factions_window()


func set_faction_outlook(viewer_faction_id: String, subject_faction_id: String, score: int) -> void:
	if viewer_faction_id.is_empty() or subject_faction_id.is_empty() or viewer_faction_id == subject_faction_id:
		return
	faction_outlooks[_outlook_key(viewer_faction_id, subject_faction_id)] = clampi(score, -100, 100)
	_save_faction_state_to_gecs()
	faction_relations_changed.emit()
	_refresh_factions_window()


func get_faction_outlook(viewer_faction_id: String, subject_faction_id: String) -> int:
	if viewer_faction_id.is_empty() or subject_faction_id.is_empty() or viewer_faction_id == subject_faction_id:
		return 0
	return int(faction_outlooks.get(_outlook_key(viewer_faction_id, subject_faction_id), 0))


func get_faction_outlook_label(viewer_faction_id: String, subject_faction_id: String) -> String:
	var score := get_faction_outlook(viewer_faction_id, subject_faction_id)
	if score >= 80:
		return "Honored"
	if score >= 45:
		return "Loved"
	if score >= 15:
		return "Liked"
	if score <= -65:
		return "Hated"
	if score <= -15:
		return "Disliked"
	return "Neutral"


func apply_faction_relation_definition(definition: Resource) -> void:
	if definition == null:
		return
	var faction_a := str(definition.get("faction_a_id")).strip_edges()
	var faction_b := str(definition.get("faction_b_id")).strip_edges()
	if faction_a.is_empty() or faction_b.is_empty() or faction_a == faction_b:
		return
	set_diplomatic_state(faction_a, faction_b, str(definition.get("diplomatic_state")))
	set_faction_outlook(faction_a, faction_b, int(definition.get("faction_a_outlook_to_b")))
	set_faction_outlook(faction_b, faction_a, int(definition.get("faction_b_outlook_to_a")))


func get_diplomatic_label_for_viewer(viewer_faction_id: String, other_faction_id: String) -> String:
	var record := get_diplomatic_record(viewer_faction_id, other_faction_id)
	var state := str(record.get("state", DIPLOMACY_NEUTRAL))
	var primary := str(record.get("primary_faction_id", ""))
	var secondary := str(record.get("secondary_faction_id", ""))
	match state:
		DIPLOMACY_WAR:
			return "War"
		DIPLOMACY_HOSTILE:
			return "Hostile"
		DIPLOMACY_TRUCE:
			return "Truce"
		DIPLOMACY_TRADE:
			return "Trade"
		DIPLOMACY_ALLIANCE:
			return "Alliance"
		DIPLOMACY_VASSAL:
			return "Vassal of %s" % _faction_display_name(secondary) if viewer_faction_id == primary else "Overlord of %s" % _faction_display_name(primary)
		DIPLOMACY_TRIBUTARY:
			return "Tributary to %s" % _faction_display_name(secondary) if viewer_faction_id == primary else "Receives Tribute from %s" % _faction_display_name(primary)
		DIPLOMACY_PROTECTORATE:
			return "Protected by %s" % _faction_display_name(secondary) if viewer_faction_id == primary else "Protector of %s" % _faction_display_name(primary)
		_:
			return "Neutral"


func are_formal_allies(faction_a: String, faction_b: String) -> bool:
	return get_diplomatic_state(faction_a, faction_b) == DIPLOMACY_ALLIANCE


func is_protector_of(protector_faction_id: String, protected_faction_id: String) -> bool:
	var record := get_diplomatic_record(protector_faction_id, protected_faction_id)
	return str(record.get("state", "")) == DIPLOMACY_PROTECTORATE \
		and str(record.get("primary_faction_id", "")) == protected_faction_id \
		and str(record.get("secondary_faction_id", "")) == protector_faction_id


func should_player_help_faction(faction_id: String) -> bool:
	if not help_allies or faction_id.is_empty() or faction_id == PLAYER_FACTION_ID:
		return false
	return are_formal_allies(PLAYER_FACTION_ID, faction_id) or is_protector_of(PLAYER_FACTION_ID, faction_id)


func set_help_allies(value: bool) -> void:
	help_allies = value
	_save_faction_state_to_gecs()
	faction_relations_changed.emit()
	_refresh_factions_window()


func get_reputation(faction_a: String, faction_b: String) -> int:
	return int(reputations.get(_relation_key(faction_a, faction_b), 0))


func set_reputation(faction_a: String, faction_b: String, value: int) -> void:
	reputations[_relation_key(faction_a, faction_b)] = clampi(value, -100, 100)
	_save_faction_state_to_gecs()
	faction_relations_changed.emit()
	_refresh_factions_window()


func add_reputation(faction_a: String, faction_b: String, amount: int) -> int:
	var next_value := get_reputation(faction_a, faction_b) + amount
	set_reputation(faction_a, faction_b, next_value)
	return get_reputation(faction_a, faction_b)


func get_reputation_label(faction_a: String, faction_b: String) -> String:
	var value := get_reputation(faction_a, faction_b)
	if value <= -76:
		return "Vilified"
	if value <= -26:
		return "Hostile"
	if value <= 24:
		return "Neutral"
	if value <= 49:
		return "Accepted"
	if value <= 74:
		return "Friendly"
	return "Beloved"


func get_reputation_bar_value(faction_a: String, faction_b: String) -> float:
	return float(get_reputation(faction_a, faction_b) + 100) * 0.5


func get_favor_points(faction_id: String) -> int:
	return int(favor_points.get(faction_id, 0))


func set_favor_points(faction_id: String, value: int) -> void:
	if faction_id.is_empty():
		return
	favor_points[faction_id] = max(0, value)
	_save_faction_state_to_gecs()
	faction_relations_changed.emit()
	_refresh_factions_window()


func add_favor_points(faction_id: String, amount: int) -> int:
	set_favor_points(faction_id, get_favor_points(faction_id) + amount)
	return get_favor_points(faction_id)


func apply_helped_faction_result(helped_faction_id: String, opposed_faction_id: String, reputation_gain := 10, favor_gain := 1, opposed_reputation_loss := -5) -> void:
	if not helped_faction_id.is_empty():
		add_reputation(PLAYER_FACTION_ID, helped_faction_id, reputation_gain)
		add_favor_points(helped_faction_id, favor_gain)
	if not opposed_faction_id.is_empty():
		add_reputation(PLAYER_FACTION_ID, opposed_faction_id, opposed_reputation_loss)


func record_player_combat_against(faction_id: String, reputation_loss := -1) -> void:
	if faction_id.is_empty() or faction_id == PLAYER_FACTION_ID:
		return
	add_reputation(PLAYER_FACTION_ID, faction_id, reputation_loss)


func serialize_state() -> Dictionary:
	_save_faction_state_to_gecs()
	var state := _current_faction_state()
	state["faction_ids"] = faction_definitions.keys()
	return state


func apply_serialized_state(state: Dictionary) -> void:
	if state.is_empty():
		refresh_from_gecs_state()
		return
	reputations = (state.get("reputations", {}) as Dictionary).duplicate(true)
	favor_points = (state.get("favor_points", {}) as Dictionary).duplicate(true)
	diplomatic_states = (state.get("diplomatic_states", {}) as Dictionary).duplicate(true)
	faction_outlooks = (state.get("faction_outlooks", {}) as Dictionary).duplicate(true)
	help_allies = bool(state.get("help_allies", help_allies))
	_save_faction_state_to_gecs()
	faction_relations_changed.emit()
	_refresh_factions_window()


func refresh_from_gecs_state() -> void:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_faction_state"):
		return
	var state: Dictionary = bridge.call("get_faction_state")
	if state.is_empty():
		return
	reputations = (state.get("reputations", {}) as Dictionary).duplicate(true)
	favor_points = (state.get("favor_points", {}) as Dictionary).duplicate(true)
	diplomatic_states = (state.get("diplomatic_states", {}) as Dictionary).duplicate(true)
	faction_outlooks = (state.get("faction_outlooks", {}) as Dictionary).duplicate(true)
	help_allies = bool(state.get("help_allies", help_allies))
	faction_relations_changed.emit()
	_refresh_factions_window()


func sync_faction_state() -> void:
	_save_faction_state_to_gecs()


func _current_faction_state() -> Dictionary:
	return {
		"state_id": "factions",
		"reputations": reputations.duplicate(true),
		"favor_points": favor_points.duplicate(true),
		"diplomatic_states": diplomatic_states.duplicate(true),
		"faction_outlooks": faction_outlooks.duplicate(true),
		"help_allies": help_allies,
	}


func _save_faction_state_to_gecs() -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("upsert_faction_state"):
		bridge.call("upsert_faction_state", _current_faction_state())


func _collect_definitions() -> void:
	if root_scene == null or not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group("world_sim_registry"):
		var definitions = node.get("faction_definitions")
		if definitions is Array:
			for definition in definitions:
				if definition is Resource:
					register_faction(definition)
	for node in get_tree().get_nodes_in_group("settlement_anchor"):
		var settlement_definition: Resource = node.get("settlement_definition") as Resource
		if settlement_definition != null:
			register_faction(settlement_definition.get("faction_definition") as Resource)
	for node in get_tree().get_nodes_in_group("world_sim_registry"):
		var relations = node.get("relation_definitions")
		if relations is Array:
			for relation in relations:
				if relation is Resource:
					apply_faction_relation_definition(relation)
	_refresh_factions_window()


func _apply_definition_starting_diplomacy(definition: Resource) -> void:
	var faction_id := _resource_id(definition)
	if faction_id.is_empty():
		return
	var war_ids = definition.get("starting_war_faction_ids")
	if war_ids != null:
		for other_id in war_ids:
			if not str(other_id).is_empty():
				set_diplomatic_state(faction_id, str(other_id), DIPLOMACY_WAR)
	var hostile_ids = definition.get("default_hostile_faction_ids")
	if hostile_ids != null:
		for other_id in hostile_ids:
			if not str(other_id).is_empty() and get_diplomatic_state(faction_id, str(other_id)) != DIPLOMACY_WAR:
				set_diplomatic_state(faction_id, str(other_id), DIPLOMACY_HOSTILE)


func _relation_key(faction_a: String, faction_b: String) -> String:
	var ids := [faction_a, faction_b]
	ids.sort()
	return "%s:%s" % [ids[0], ids[1]]


func _outlook_key(viewer_faction_id: String, subject_faction_id: String) -> String:
	return "%s>%s" % [viewer_faction_id, subject_faction_id]


func _faction_display_name(faction_id: String) -> String:
	var definition := get_faction_definition(faction_id)
	if definition != null:
		var display := str(definition.get("display_name"))
		if not display.is_empty():
			return display
	return faction_id


func _resource_id(definition: Resource) -> String:
	if definition != null and definition.has_method("get_id"):
		return str(definition.call("get_id"))
	return ""


func _get_gecs_world() -> Node:
	if not is_inside_tree():
		return null
	return _context.get_optional(GecsWorldController.SERVICE_ID) if _context != null else null


func _resource_is_hostile_to(definition: Resource, other_faction_id: String) -> bool:
	if definition == null or other_faction_id.is_empty():
		return false
	if definition.has_method("is_hostile_to"):
		return bool(definition.call("is_hostile_to", other_faction_id))
	var hostile_ids = definition.get("default_hostile_faction_ids")
	return hostile_ids != null and hostile_ids.has(other_faction_id)


func _setup_factions_ui() -> void:
	if hud_layer == null:
		if root_scene != null:
			hud_layer = root_scene.get_node_or_null("GameHUD") as CanvasLayer
		if hud_layer == null:
			return
	if _factions_button == null or not is_instance_valid(_factions_button):
		_factions_button = Button.new()
		_factions_button.name = "FactionsButton"
		_factions_button.text = "Factions"
		_factions_button.custom_minimum_size = Vector2(72.0, 22.0)
		_factions_button.focus_mode = Control.FOCUS_NONE
		_factions_button.pressed.connect(_on_factions_button_pressed)
	_add_factions_button_to_hud()
	if _factions_window == null or not is_instance_valid(_factions_window):
		_factions_window = PanelContainer.new()
		_factions_window.name = "FactionsPanel"
		_factions_window.visible = false
		_factions_window.process_mode = Node.PROCESS_MODE_ALWAYS
		_factions_window.custom_minimum_size = Vector2(720.0, 460.0)
		_factions_window.size = Vector2(720.0, 460.0)
		_factions_window.position = Vector2(80.0, 80.0)
		_factions_window.add_theme_stylebox_override("panel", _make_hud_panel_style())
		_get_factions_menu_parent().add_child(_factions_window)
		var margin := MarginContainer.new()
		margin.name = "Margin"
		margin.add_theme_constant_override("margin_left", 12)
		margin.add_theme_constant_override("margin_top", 10)
		margin.add_theme_constant_override("margin_right", 12)
		margin.add_theme_constant_override("margin_bottom", 12)
		_factions_window.add_child(margin)
		var column := VBoxContainer.new()
		column.name = "Column"
		column.add_theme_constant_override("separation", 10)
		margin.add_child(column)
		_factions_title_bar = PanelContainer.new()
		_factions_title_bar.name = "TitleBar"
		_factions_title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
		_factions_title_bar.add_theme_stylebox_override("panel", _make_title_bar_style())
		_factions_title_bar.gui_input.connect(_on_factions_title_bar_gui_input)
		column.add_child(_factions_title_bar)
		var title_row := HBoxContainer.new()
		_factions_title_bar.add_child(title_row)
		var title := Label.new()
		title.name = "Title"
		title.text = "Factions"
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.add_theme_color_override("font_color", Color(0.92, 0.84, 0.66, 1.0))
		title.add_theme_font_size_override("font_size", 15)
		title_row.add_child(title)
		var close_button := Button.new()
		close_button.name = "CloseButton"
		close_button.text = "X"
		close_button.custom_minimum_size = Vector2(32.0, 28.0)
		close_button.focus_mode = Control.FOCUS_NONE
		close_button.pressed.connect(_factions_window.hide)
		title_row.add_child(close_button)
		_factions_window_body = VBoxContainer.new()
		_factions_window_body.name = "Body"
		_factions_window_body.add_theme_constant_override("separation", 8)
		column.add_child(_factions_window_body)
		var viewport := get_viewport()
		if viewport != null and not viewport.size_changed.is_connected(_clamp_factions_panel_to_viewport):
			viewport.size_changed.connect(_clamp_factions_panel_to_viewport)
	_add_factions_panel_to_menu_layer()
	_refresh_factions_window()


func _add_factions_button_to_hud() -> void:
	if _factions_button == null or not is_instance_valid(_factions_button):
		return
	var parent := _get_factions_button_parent()
	if _factions_button.get_parent() == parent:
		return
	if _factions_button.get_parent() != null:
		_factions_button.get_parent().remove_child(_factions_button)
	parent.add_child(_factions_button)
	if parent == hud_layer:
		_factions_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_factions_button.offset_left = -488.0
		_factions_button.offset_top = 8.0
		_factions_button.offset_right = -398.0
		_factions_button.offset_bottom = 42.0


func _add_factions_panel_to_menu_layer() -> void:
	if _factions_window == null or not is_instance_valid(_factions_window):
		return
	var parent := _get_factions_menu_parent()
	if _factions_window.get_parent() == parent:
		return
	if _factions_window.get_parent() != null:
		_factions_window.get_parent().remove_child(_factions_window)
	parent.add_child(_factions_window)


func _get_factions_button_parent() -> Node:
	if hud_layer == null:
		return self
	return hud_layer.get_node_or_null(FACTIONS_BUTTON_PARENT_PATH) if hud_layer.get_node_or_null(FACTIONS_BUTTON_PARENT_PATH) != null else hud_layer


func _get_factions_menu_parent() -> Node:
	if hud_layer == null:
		return self
	return hud_layer.get_node_or_null(FACTIONS_MENU_LAYER_PATH) if hud_layer.get_node_or_null(FACTIONS_MENU_LAYER_PATH) != null else hud_layer


func _on_factions_button_pressed() -> void:
	_setup_factions_ui()
	_refresh_factions_window()
	if _factions_window != null:
		_factions_window.visible = true
		_factions_window.move_to_front()
		_clamp_factions_panel_to_viewport()


func _refresh_factions_window() -> void:
	if _factions_window_body == null or not is_instance_valid(_factions_window_body):
		return
	for child in _factions_window_body.get_children():
		child.queue_free()
	var help_toggle := CheckBox.new()
	help_toggle.name = "HelpAlliesToggle"
	help_toggle.text = "Help allies"
	help_toggle.button_pressed = help_allies
	help_toggle.add_theme_color_override("font_color", Color(0.78, 0.72, 0.62, 1.0))
	help_toggle.toggled.connect(set_help_allies)
	_factions_window_body.add_child(help_toggle)
	_factions_window_body.add_child(_make_header_row())
	for faction_id in get_faction_ids():
		var id := str(faction_id)
		if id == PLAYER_FACTION_ID:
			continue
		_factions_window_body.add_child(_make_faction_row(id))


func _make_faction_row(faction_id: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "FactionRow_%s" % faction_id
	row.custom_minimum_size = Vector2(0.0, 34.0)
	row.add_theme_constant_override("separation", 10)
	var name_label := Label.new()
	name_label.custom_minimum_size = Vector2(170.0, 0.0)
	name_label.text = _faction_display_name(faction_id)
	name_label.add_theme_color_override("font_color", Color(0.86, 0.78, 0.62, 1.0))
	row.add_child(name_label)
	var diplomacy_label := Label.new()
	diplomacy_label.custom_minimum_size = Vector2(150.0, 0.0)
	diplomacy_label.text = get_diplomatic_label_for_viewer(PLAYER_FACTION_ID, faction_id)
	diplomacy_label.add_theme_color_override("font_color", Color(0.72, 0.68, 0.58, 1.0))
	row.add_child(diplomacy_label)
	var reputation_bar := ProgressBar.new()
	reputation_bar.name = "ReputationBar"
	reputation_bar.custom_minimum_size = Vector2(170.0, 5.0)
	reputation_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reputation_bar.min_value = 0.0
	reputation_bar.max_value = 100.0
	reputation_bar.value = get_reputation_bar_value(PLAYER_FACTION_ID, faction_id)
	reputation_bar.show_percentage = false
	reputation_bar.add_theme_stylebox_override("background", _make_reputation_bar_background_style())
	reputation_bar.add_theme_stylebox_override("fill", _make_reputation_bar_fill_style())
	row.add_child(reputation_bar)
	var reputation_label := Label.new()
	reputation_label.custom_minimum_size = Vector2(82.0, 0.0)
	reputation_label.text = get_reputation_label(PLAYER_FACTION_ID, faction_id)
	reputation_label.add_theme_color_override("font_color", Color(0.78, 0.72, 0.62, 1.0))
	row.add_child(reputation_label)
	var favor_label := Label.new()
	favor_label.name = "FavorLabel"
	favor_label.custom_minimum_size = Vector2(86.0, 0.0)
	favor_label.text = "Favor %d" % get_favor_points(faction_id)
	favor_label.add_theme_color_override("font_color", Color(0.78, 0.72, 0.62, 1.0))
	row.add_child(favor_label)
	return row


func _make_header_row() -> Control:
	var row := HBoxContainer.new()
	row.name = "HeaderRow"
	row.add_theme_constant_override("separation", 10)
	_add_header_label(row, "Faction", 170.0)
	_add_header_label(row, "Diplomacy", 150.0)
	_add_header_label(row, "Reputation", 170.0)
	_add_header_label(row, "Standing", 82.0)
	_add_header_label(row, "Favors", 86.0)
	return row


func _add_header_label(row: HBoxContainer, text: String, width: float) -> void:
	var label := Label.new()
	label.custom_minimum_size = Vector2(width, 0.0)
	label.text = text
	label.add_theme_color_override("font_color", Color(0.58, 0.53, 0.43, 1.0))
	label.add_theme_font_size_override("font_size", 10)
	row.add_child(label)


func _on_factions_title_bar_gui_input(event: InputEvent) -> void:
	if _factions_window == null:
		return
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return
		_factions_dragging = mouse_button.pressed
		if _factions_dragging:
			_factions_drag_offset = _factions_window.get_global_mouse_position() - _factions_window.position
		_factions_title_bar.accept_event()
		return
	if event is InputEventMouseMotion and _factions_dragging:
		_factions_window.position = _clamp_factions_panel_position(_factions_window.get_global_mouse_position() - _factions_drag_offset)
		_factions_title_bar.accept_event()


func _clamp_factions_panel_to_viewport() -> void:
	var current_panel := _get_factions_menu_parent().get_node_or_null("FactionsPanel") as PanelContainer
	if current_panel != null:
		_factions_window = current_panel
	if _factions_window == null or not is_instance_valid(_factions_window):
		return
	_factions_window.position = _clamp_factions_panel_position(_factions_window.position)


func _clamp_factions_panel_position(target_position: Vector2) -> Vector2:
	if _factions_window == null:
		return target_position
	var viewport_rect := get_viewport().get_visible_rect()
	var panel_size := _factions_window.size
	var max_x := maxf(0.0, viewport_rect.size.x - panel_size.x)
	var max_y := maxf(0.0, viewport_rect.size.y - panel_size.y)
	return Vector2(clampf(target_position.x, 0.0, max_x), clampf(target_position.y, 0.0, max_y))


func _make_hud_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.075, 0.07, 0.065, 0.96)
	style.border_color = Color(0.35, 0.29, 0.2, 1.0)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style


func _make_title_bar_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.095, 0.075, 0.98)
	style.border_color = Color(0.35, 0.29, 0.2, 1.0)
	style.border_width_bottom = 1
	return style


func _make_reputation_bar_background_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.07, 0.075, 0.95)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	return style


func _make_reputation_bar_fill_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.76, 0.72, 1.0)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	return style
