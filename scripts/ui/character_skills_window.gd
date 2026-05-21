extends PanelContainer

class_name CharacterSkillsWindow

const WINDOW_SIZE := Vector2(560.0, 600.0)
const LIVE_REFRESH_SECONDS := 0.15

var actor: WorldActor
var title_label: Label
var rows_root: VBoxContainer
var _row_controls_by_skill: Dictionary = {}
var _refresh_remaining := 0.0
var _connected_skill_set: ActorSkillSet


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = WINDOW_SIZE
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
	_set_window_position()


func _set_window_position() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -WINDOW_SIZE.x * 0.5
	offset_top = -WINDOW_SIZE.y * 0.5
	offset_right = WINDOW_SIZE.x * 0.5
	offset_bottom = WINDOW_SIZE.y * 0.5


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

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)

	title_label = Label.new()
	title_label.text = "Skills"
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(hide)
	header.add_child(close_button)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	rows_root = VBoxContainer.new()
	rows_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_root.add_theme_constant_override("separation", 6)
	scroll.add_child(rows_root)


func _rebuild_rows() -> void:
	_row_controls_by_skill.clear()
	for child in rows_root.get_children():
		rows_root.remove_child(child)
		child.queue_free()
	if actor == null:
		title_label.text = "Skills"
		return
	var actor_name: String = actor.name
	var member_name_value = actor.get("member_name")
	if member_name_value != null:
		actor_name = str(member_name_value)
	title_label.text = "%s Skills" % actor_name
	var current_category := ""
	for definition in SkillRules.get_all_definitions():
		if definition.category_id != current_category:
			current_category = definition.category_id
			_add_category_header(definition.category_name)
		_add_skill_row(definition)


func _update_rows() -> void:
	if actor == null:
		return
	for definition in SkillRules.get_all_definitions():
		_update_skill_row(definition)


func _add_category_header(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.48, 1.0))
	rows_root.add_child(label)


func _add_skill_row(definition: SkillDefinition) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	rows_root.add_child(row)

	var name_label := Label.new()
	name_label.text = definition.display_name
	name_label.custom_minimum_size = Vector2(170.0, 0.0)
	row.add_child(name_label)

	var level_label := Label.new()
	level_label.text = "Lv -"
	level_label.custom_minimum_size = Vector2(58.0, 0.0)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(level_label)

	var progress := ProgressBar.new()
	progress.show_percentage = false
	progress.min_value = 0.0
	progress.max_value = 1.0
	progress.value = 0.0
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress.custom_minimum_size = Vector2(120.0, 18.0)
	row.add_child(progress)

	var xp_label := Label.new()
	xp_label.text = "0 / 0"
	xp_label.custom_minimum_size = Vector2(96.0, 0.0)
	xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	xp_label.add_theme_font_size_override("font_size", 11)
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
