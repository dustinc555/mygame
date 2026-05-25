extends PanelContainer

class_name CharacterSkillsWindow

const WINDOW_SIZE := Vector2(760.0, 520.0)
const LIVE_REFRESH_SECONDS := 0.15
const TITLE_BAR_PADDING := Vector2i(12, 5)
const SECTION_LAYOUT := [
	["attributes", "combat", "subterfuge"],
	["movement", "labor", "craft", "knowledge_tech"],
]
const SECTION_TITLES := {
	"attributes": "Core Attributes",
	"combat": "Combat",
	"subterfuge": "Subterfuge",
	"movement": "Movement",
	"labor": "Labor",
	"craft": "Crafting",
	"knowledge_tech": "Knowledge / Tech",
}
const CATEGORY_TO_SECTION := {
	"attributes": "attributes",
	"combat": "combat",
	"subterfuge": "subterfuge",
	"movement": "movement",
	"labor": "labor",
	"craft": "craft",
	"knowledge": "knowledge_tech",
	"tech": "knowledge_tech",
}

var actor: WorldActor
var title_label: Label
var title_bar: PanelContainer
var columns_root: HBoxContainer
var _section_roots: Dictionary = {}
var _row_controls_by_skill: Dictionary = {}
var _refresh_remaining := 0.0
var _connected_skill_set: ActorSkillSet
var _dragging := false
var _drag_offset := Vector2.ZERO
var _user_positioned := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = WINDOW_SIZE
	size = WINDOW_SIZE
	_set_window_position()
	_build_layout()


func _process(delta: float) -> void:
	if not visible or actor == null:
		return
	_refresh_remaining -= delta
	if _refresh_remaining > 0.0:
		return
	_refresh_remaining = LIVE_REFRESH_SECONDS
	_update_rows()


func show_for_actor(target_actor: WorldActor) -> void:
	var actor_changed := actor != target_actor
	actor = target_actor
	if title_label == null:
		call_deferred("show_for_actor", target_actor)
		return
	visible = actor != null
	if actor_changed or _row_controls_by_skill.is_empty():
		_rebuild_rows()
	_connect_actor_skill_set()
	_update_rows()
	_refresh_remaining = LIVE_REFRESH_SECONDS
	if not _user_positioned:
		_set_window_position()


func _set_window_position() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	size = WINDOW_SIZE
	var viewport_size := get_viewport_rect().size
	position = _clamp_position_to_viewport((viewport_size - WINDOW_SIZE) * 0.5)


func _build_layout() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.14, 0.98)
	style.border_color = Color(0.42, 0.38, 0.28, 1.0)
	style.set_border_width_all(2)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	title_bar = PanelContainer.new()
	title_bar.name = "TitleBar"
	title_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	title_bar.gui_input.connect(_on_title_bar_gui_input)
	var title_style := StyleBoxFlat.new()
	title_style.bg_color = Color(0.18, 0.17, 0.15, 0.96)
	title_style.border_color = Color(0.34, 0.30, 0.22, 1.0)
	title_style.set_border_width_all(1)
	title_style.corner_radius_top_left = 4
	title_style.corner_radius_top_right = 4
	title_style.corner_radius_bottom_right = 4
	title_style.corner_radius_bottom_left = 4
	title_bar.add_theme_stylebox_override("panel", title_style)
	root.add_child(title_bar)

	var title_margin := MarginContainer.new()
	title_margin.name = "TitlePadding"
	title_margin.add_theme_constant_override("margin_left", TITLE_BAR_PADDING.x)
	title_margin.add_theme_constant_override("margin_top", TITLE_BAR_PADDING.y)
	title_margin.add_theme_constant_override("margin_right", TITLE_BAR_PADDING.x)
	title_margin.add_theme_constant_override("margin_bottom", TITLE_BAR_PADDING.y)
	title_bar.add_child(title_margin)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	title_margin.add_child(header)

	title_label = Label.new()
	title_label.text = "Skills"
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)

	var close_button := Button.new()
	close_button.text = "X"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(hide)
	header.add_child(close_button)

	columns_root = HBoxContainer.new()
	columns_root.name = "SkillsColumns"
	columns_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns_root.add_theme_constant_override("separation", 12)
	root.add_child(columns_root)
	_build_section_columns()


func _rebuild_rows() -> void:
	_row_controls_by_skill.clear()
	for section_root in _section_roots.values():
		if not (section_root is VBoxContainer):
			continue
		for child in (section_root as VBoxContainer).get_children():
			(section_root as VBoxContainer).remove_child(child)
			child.queue_free()
	if actor == null:
		title_label.text = "Skills"
		return
	var actor_name: String = actor.name
	var member_name_value = actor.get("member_name")
	if member_name_value != null:
		actor_name = str(member_name_value)
	title_label.text = "%s Skills" % actor_name
	for definition in SkillRules.get_all_definitions():
		_add_skill_row(definition)


func _update_rows() -> void:
	if actor == null:
		return
	for definition in SkillRules.get_all_definitions():
		_update_skill_row(definition)


func _add_skill_row(definition: SkillDefinition) -> void:
	var section_id := _get_section_id(definition.category_id)
	var rows_root := _section_roots.get(section_id, null) as VBoxContainer
	if rows_root == null:
		return
	var row := HBoxContainer.new()
	row.name = "%sRow" % definition.skill_id.replace(".", "_")
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 5)
	rows_root.add_child(row)

	var name_label := Label.new()
	name_label.text = definition.display_name
	name_label.custom_minimum_size = Vector2(112.0, 0.0)
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", 12)
	row.add_child(name_label)

	var level_label := Label.new()
	level_label.text = "Lv -"
	level_label.custom_minimum_size = Vector2(44.0, 0.0)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	level_label.add_theme_font_size_override("font_size", 12)
	row.add_child(level_label)

	var progress := ProgressBar.new()
	progress.show_percentage = false
	progress.min_value = 0.0
	progress.max_value = 1.0
	progress.value = 0.0
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress.custom_minimum_size = Vector2(72.0, 14.0)
	row.add_child(progress)

	var xp_label := Label.new()
	xp_label.text = "0 / 0"
	xp_label.custom_minimum_size = Vector2(68.0, 0.0)
	xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	xp_label.add_theme_font_size_override("font_size", 10)
	row.add_child(xp_label)

	_row_controls_by_skill[definition.skill_id] = {
		"level_label": level_label,
		"progress": progress,
		"xp_label": xp_label,
	}
	_update_skill_row(definition)


func _update_skill_row(definition: SkillDefinition) -> void:
	if actor == null or not _row_controls_by_skill.has(definition.skill_id):
		return
	var controls: Dictionary = _row_controls_by_skill[definition.skill_id]
	var level_label := controls.get("level_label") as Label
	var progress := controls.get("progress") as ProgressBar
	var xp_label := controls.get("xp_label") as Label
	if level_label == null or progress == null or xp_label == null:
		return
	var snapshot := actor.get_skill_entry_snapshot(definition.skill_id) if actor.has_method("get_skill_entry_snapshot") else {}
	var level := int(snapshot.get("level", SkillRules.get_default_level(definition.skill_id)))
	var xp := float(snapshot.get("xp", 0.0))
	var xp_to_next := float(snapshot.get("xp_to_next", SkillRules.get_xp_to_next_level(level)))
	level_label.text = "Lv %d" % level
	progress.max_value = maxf(xp_to_next, 1.0)
	progress.value = clampf(xp, 0.0, progress.max_value)
	xp_label.text = "%d / %d" % [int(floor(xp)), int(ceil(xp_to_next))]


func _connect_actor_skill_set() -> void:
	if _connected_skill_set != null and _connected_skill_set.skill_changed.is_connected(_on_actor_skill_changed):
		_connected_skill_set.skill_changed.disconnect(_on_actor_skill_changed)
	_connected_skill_set = null
	if actor == null:
		return
	actor.get_skill_level(SkillRules.ATTRIBUTE_STRENGTH)
	_connected_skill_set = actor.get("skill_set") as ActorSkillSet
	if _connected_skill_set != null and not _connected_skill_set.skill_changed.is_connected(_on_actor_skill_changed):
		_connected_skill_set.skill_changed.connect(_on_actor_skill_changed)


func _on_actor_skill_changed(skill_id: String) -> void:
	if not visible:
		return
	var definition := SkillRules.get_definition(skill_id)
	if definition != null:
		_update_skill_row(definition)


func _build_section_columns() -> void:
	_section_roots.clear()
	for column_index in range(SECTION_LAYOUT.size()):
		var column := VBoxContainer.new()
		column.name = "SkillsColumn%d" % (column_index + 1)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 8)
		columns_root.add_child(column)
		for section_id in SECTION_LAYOUT[column_index]:
			_add_section(column, section_id)


func _add_section(parent: VBoxContainer, section_id: String) -> void:
	var panel := PanelContainer.new()
	panel.name = _get_section_node_name(section_id)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.085, 0.095, 0.78)
	panel_style.border_color = Color(0.25, 0.23, 0.18, 0.9)
	panel_style.set_border_width_all(1)
	panel_style.corner_radius_top_left = 4
	panel_style.corner_radius_top_right = 4
	panel_style.corner_radius_bottom_right = 4
	panel_style.corner_radius_bottom_left = 4
	panel.add_theme_stylebox_override("panel", panel_style)
	parent.add_child(panel)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 7)
	panel.add_child(margin)

	var section_root := VBoxContainer.new()
	section_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	section_root.add_theme_constant_override("separation", 3)
	margin.add_child(section_root)

	var header := Label.new()
	header.name = "SectionHeader"
	header.text = str(SECTION_TITLES.get(section_id, section_id.capitalize()))
	header.add_theme_font_size_override("font_size", 13)
	header.add_theme_color_override("font_color", Color(1.0, 0.86, 0.48, 1.0))
	section_root.add_child(header)

	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 2)
	section_root.add_child(rows)
	_section_roots[section_id] = rows


func _get_section_id(category_id: String) -> String:
	return str(CATEGORY_TO_SECTION.get(category_id, category_id))


func _get_section_node_name(section_id: String) -> String:
	if section_id == "attributes":
		return "CoreAttributesSection"
	return "%sSection" % _to_pascal_case(section_id)


func _on_title_bar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return
		_dragging = mouse_button.pressed
		if _dragging:
			_user_positioned = true
			_drag_offset = _event_global_position(mouse_button) - position
			move_to_front()
		return
	if event is InputEventMouseMotion and _dragging:
		position = _clamp_position_to_viewport(_event_global_position(event) - _drag_offset)


func _event_global_position(event: InputEvent) -> Vector2:
	if event is InputEventMouse:
		return (event as InputEventMouse).global_position
	return get_global_mouse_position()


func _clamp_position_to_viewport(target_position: Vector2) -> Vector2:
	var viewport_size := get_viewport_rect().size
	var effective_size := size
	if effective_size.x <= 0.0 or effective_size.y <= 0.0:
		effective_size = WINDOW_SIZE
	var max_x := maxf(0.0, viewport_size.x - effective_size.x)
	var max_y := maxf(0.0, viewport_size.y - effective_size.y)
	return Vector2(clampf(target_position.x, 0.0, max_x), clampf(target_position.y, 0.0, max_y))


func _to_pascal_case(value: String) -> String:
	var result := ""
	for part in value.split("_"):
		if part.is_empty():
			continue
		result += part.substr(0, 1).to_upper() + part.substr(1).to_lower()
	return result
