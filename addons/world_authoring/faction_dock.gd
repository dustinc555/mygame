@tool
extends PanelContainer

## Bottom-panel Factions editor for the world_authoring plugin. Two views on
## one tab: the Factions root shows the roster (every authored faction with
## its emblem, plus New Faction); a Faction child shows that faction's
## editor. Every edit writes the FactionDefinition .tres on disk (the single
## truth the game boots with); the dock never stores faction state of its
## own.

const ICONS_DIR := "res://features/factions/resources/icons"
const PROFILE_PICKERS := [
	{"label": "Behavior", "property": "behavior_profile", "dir": "res://features/world_sim/resources/behavior_profiles", "empty": "(none)"},
	{"label": "Personality", "property": "personality_profile", "dir": "res://features/factions/resources/personality_profiles", "empty": "(none)"},
	{"label": "Law", "property": "law_profile", "dir": "res://features/factions/resources/law_profiles", "empty": "(none)"},
	{"label": "Names", "property": "population_name_profile", "dir": "res://features/world_sim/resources/population_name_profiles", "empty": "(none)"},
	{"label": "Characters", "property": "population_appearance_profile", "dir": "res://features/world_sim/resources/population_appearance_profiles", "empty": "(none)"},
]

var _tools: RefCounted
var _root: Node
var _faction: Node
var _updating := false
var _placeholder: Label
var _roster_view: VBoxContainer
var _roster_list: ItemList
var _editor_view: HBoxContainer
var _identity_box: VBoxContainer
var _profiles_box: VBoxContainer
var _icon_cache := {}


func setup(tools: RefCounted) -> void:
	_tools = tools
	custom_minimum_size = Vector2(0, 240)
	_placeholder = Label.new()
	_placeholder.text = "Select the Factions root or a Faction node to edit the faction database here."
	_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_placeholder)
	_build_roster_view()
	_build_editor_view()


## root = the Factions node in context; faction = the selected Faction child
## (null when the root itself is selected).
func set_context(root: Node, faction: Node) -> void:
	_root = root if root != null and is_instance_valid(root) else null
	_faction = faction if faction != null and is_instance_valid(faction) else null
	_rebuild.call_deferred()


func refresh() -> void:
	_rebuild.call_deferred()


## --- View construction ---------------------------------------------------------


func _build_roster_view() -> void:
	_roster_view = VBoxContainer.new()
	_roster_view.visible = false
	_roster_view.add_theme_constant_override("separation", 8)
	add_child(_roster_view)
	_roster_view.add_child(_section_title("Faction Database (on-disk .tres, ships with the game)"))
	_roster_list = ItemList.new()
	_roster_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_roster_list.fixed_icon_size = Vector2i(20, 20)
	_roster_list.item_activated.connect(func(index: int): _select_roster_faction(index))
	_roster_view.add_child(_roster_list)
	var actions := HBoxContainer.new()
	var new_button := Button.new()
	new_button.text = "New Faction"
	new_button.tooltip_text = "Create a new FactionDefinition .tres on disk and add its Faction node under this root."
	new_button.pressed.connect(func(): _tools.create_faction(_root))
	actions.add_child(new_button)
	var edit_button := Button.new()
	edit_button.text = "Edit Selected"
	edit_button.pressed.connect(func():
		var selected := _roster_list.get_selected_items()
		if not selected.is_empty():
			_select_roster_faction(selected[0]))
	actions.add_child(edit_button)
	_roster_view.add_child(actions)


func _build_editor_view() -> void:
	_editor_view = HBoxContainer.new()
	_editor_view.visible = false
	_editor_view.add_theme_constant_override("separation", 14)
	add_child(_editor_view)
	var identity_scroll := ScrollContainer.new()
	identity_scroll.custom_minimum_size = Vector2(380, 0)
	identity_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_identity_box = VBoxContainer.new()
	_identity_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity_scroll.add_child(_identity_box)
	_editor_view.add_child(identity_scroll)
	var profiles_scroll := ScrollContainer.new()
	profiles_scroll.custom_minimum_size = Vector2(340, 0)
	profiles_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_profiles_box = VBoxContainer.new()
	_profiles_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profiles_scroll.add_child(_profiles_box)
	_editor_view.add_child(profiles_scroll)


## --- Rebuild ---------------------------------------------------------------------


func _rebuild() -> void:
	if _placeholder == null:
		return
	if _root != null and not is_instance_valid(_root):
		_root = null
	if _faction != null and not is_instance_valid(_faction):
		_faction = null
	var definition: Resource = _faction.get("definition") as Resource if _faction != null else null
	var editing := _faction != null and definition != null
	_placeholder.visible = _root == null and _faction == null
	if _faction != null and definition == null:
		_placeholder.visible = true
		_placeholder.text = "%s has no FactionDefinition — assign one in the inspector or recreate it from the roster." % _faction.name
	else:
		_placeholder.text = "Select the Factions root or a Faction node to edit the faction database here."
	_roster_view.visible = not editing and _root != null
	_editor_view.visible = editing
	_updating = true
	if _roster_view.visible:
		_rebuild_roster()
	if editing:
		_rebuild_identity(definition)
		_rebuild_profiles(definition)
	_updating = false


func _rebuild_roster() -> void:
	_roster_list.clear()
	if _root == null:
		return
	for child in _root.get_children():
		var definition: Resource = child.get("definition") as Resource
		var label := str(child.name)
		if definition != null:
			var id := str(definition.call("get_id"))
			label = "%s  (%s)" % [str(definition.get("display_name")), id]
		else:
			label += "  (no definition)"
		var index := _roster_list.add_item(label, definition.get("icon") as Texture2D if definition != null else null)
		_roster_list.set_item_metadata(index, child.get_path())


func _select_roster_faction(index: int) -> void:
	if _root == null:
		return
	var path: NodePath = _roster_list.get_item_metadata(index)
	var node := _root.get_tree().root.get_node_or_null(path)
	if node != null:
		var selection := EditorInterface.get_selection()
		selection.clear()
		selection.add_node(node)


func _rebuild_identity(definition: Resource) -> void:
	for child in _identity_box.get_children():
		_identity_box.remove_child(child)
		child.queue_free()
	_identity_box.add_child(_section_title("%s  —  %s" % [str(definition.get("display_name")), _definition_home_label(definition)]))
	_identity_box.add_child(_text_field("Faction Id", str(definition.get("faction_id")),
		func(value: String): _write(definition, "faction_id", value.strip_edges())))
	_identity_box.add_child(_text_field("Display Name", str(definition.get("display_name")),
		func(value: String): _write_display_name(definition, value)))
	_identity_box.add_child(_description_field(definition))
	_identity_box.add_child(_color_field(definition))
	_identity_box.add_child(_icon_picker(definition))
	_identity_box.add_child(_section_title("Access"))
	_identity_box.add_child(_check_field("Open Access", bool(definition.get("open_access")),
		func(value: bool): _write(definition, "open_access", value)))
	_identity_box.add_child(_int_field("Accepted Rep Threshold", int(definition.get("accepted_reputation_threshold")), -100, 100,
		func(value: int): _write(definition, "accepted_reputation_threshold", value)))
	_identity_box.add_child(_check_field("Permanently Hostile", bool(definition.get("permanently_hostile")),
		func(value: bool): _write(definition, "permanently_hostile", value)))
	_identity_box.add_child(_section_title("Standing Hostilities (faction ids, comma-separated)"))
	_identity_box.add_child(_text_field("Hostile To", _ids_text(definition, "default_hostile_faction_ids"),
		func(value: String): _write(definition, "default_hostile_faction_ids", _parse_ids(value))))
	_identity_box.add_child(_text_field("At War With", _ids_text(definition, "starting_war_faction_ids"),
		func(value: String): _write(definition, "starting_war_faction_ids", _parse_ids(value))))


func _rebuild_profiles(definition: Resource) -> void:
	for child in _profiles_box.get_children():
		_profiles_box.remove_child(child)
		child.queue_free()
	_profiles_box.add_child(_section_title("Profiles"))
	for picker in PROFILE_PICKERS:
		_profiles_box.add_child(_profile_picker(definition, picker))
	_profiles_box.add_child(_section_title("World Sim"))
	_profiles_box.add_child(_check_field("Spawns Nests", bool(definition.get("spawns_nests")),
		func(value: bool): _write(definition, "spawns_nests", value)))
	_profiles_box.add_child(_int_field("Squad Size", int(definition.get("default_squad_size")), 1, 20,
		func(value: int): _write(definition, "default_squad_size", value)))
	_profiles_box.add_child(_float_field("March Fitness", float(definition.get("squad_march_fitness")), 0.5, 1.6, 0.05,
		func(value: float): _write(definition, "squad_march_fitness", value)))
	var back := Button.new()
	back.text = "Back To Roster"
	back.pressed.connect(func():
		if _root != null:
			var selection := EditorInterface.get_selection()
			selection.clear()
			selection.add_node(_root))
	_profiles_box.add_child(back)


## --- Definition IO ---------------------------------------------------------------


func _write(definition: Resource, property_name: String, value) -> void:
	if _updating or definition == null:
		return
	definition.set(property_name, value)
	_save_definition(definition)


## Display-name edits also rename the Faction node so the scene tree reads
## like the roster.
func _write_display_name(definition: Resource, value: String) -> void:
	if _updating:
		return
	_write(definition, "display_name", value)
	if _faction != null and is_instance_valid(_faction) and not value.strip_edges().is_empty():
		_faction.name = value.strip_edges().to_pascal_case()
	_rebuild.call_deferred()


func _save_definition(definition: Resource) -> void:
	var path := definition.resource_path
	if not path.is_empty() and not path.contains("::"):
		ResourceSaver.save(definition, path)
	else:
		EditorInterface.mark_scene_as_unsaved()


func _definition_home_label(definition: Resource) -> String:
	var path := definition.resource_path
	if path.is_empty() or path.contains("::"):
		return "embedded in scene — save it to features/factions/resources/factions"
	return path.get_file()


func _ids_text(definition: Resource, property_name: String) -> String:
	var ids = definition.get(property_name)
	if ids == null:
		return ""
	var parts: Array[String] = []
	for id in ids:
		parts.append(str(id))
	return ", ".join(parts)


func _parse_ids(text: String) -> PackedStringArray:
	var result := PackedStringArray()
	for part in text.split(","):
		var id := part.strip_edges()
		if not id.is_empty():
			result.append(id)
	return result


## --- Field builders ---------------------------------------------------------------


func _section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9))
	return label


func _labeled_row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(160, 0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _text_field(label_text: String, value: String, on_changed: Callable) -> Control:
	var edit := LineEdit.new()
	edit.text = value
	edit.text_submitted.connect(func(text: String): on_changed.call(text))
	edit.focus_exited.connect(func(): on_changed.call(edit.text))
	return _labeled_row(label_text, edit)


func _description_field(definition: Resource) -> Control:
	var edit := TextEdit.new()
	edit.text = str(definition.get("description"))
	edit.custom_minimum_size = Vector2(0, 54)
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.focus_exited.connect(func():
		if not _updating:
			_write(definition, "description", edit.text))
	return _labeled_row("Description", edit)


func _color_field(definition: Resource) -> Control:
	var picker := ColorPickerButton.new()
	picker.color = definition.get("primary_color")
	picker.custom_minimum_size = Vector2(0, 24)
	picker.popup_closed.connect(func():
		if not _updating:
			_write(definition, "primary_color", picker.color))
	return _labeled_row("Color", picker)


func _int_field(label_text: String, value: int, minimum: int, maximum: int, on_changed: Callable) -> Control:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1
	spin.value = value
	spin.value_changed.connect(func(new_value: float):
		if not _updating:
			on_changed.call(int(new_value)))
	return _labeled_row(label_text, spin)


func _float_field(label_text: String, value: float, minimum: float, maximum: float, step: float, on_changed: Callable) -> Control:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = value
	spin.value_changed.connect(func(new_value: float):
		if not _updating:
			on_changed.call(new_value))
	return _labeled_row(label_text, spin)


func _check_field(label_text: String, value: bool, on_changed: Callable) -> Control:
	var check := CheckBox.new()
	check.button_pressed = value
	check.toggled.connect(func(pressed: bool):
		if not _updating:
			on_changed.call(pressed))
	return _labeled_row(label_text, check)


func _profile_picker(definition: Resource, picker: Dictionary) -> Control:
	var paths := _scan_resource_paths(str(picker["dir"]), "tres")
	var option := OptionButton.new()
	option.add_item(str(picker["empty"]))
	var current: Resource = definition.get(str(picker["property"])) as Resource
	var selected := 0
	for index in range(paths.size()):
		option.add_item(paths[index].get_file().get_basename())
		if current != null and current.resource_path == paths[index]:
			selected = index + 1
	option.selected = selected
	option.item_selected.connect(func(index: int):
		if _updating:
			return
		var value: Resource = null if index == 0 else load(paths[index - 1])
		_write(definition, str(picker["property"]), value))
	return _labeled_row(str(picker["label"]), option)


## Emblem picker scanned from the icons folder; previews render straight from
## the SVG bytes so the picker works even before the editor imports them.
func _icon_picker(definition: Resource) -> Control:
	var paths := _scan_resource_paths(ICONS_DIR, "svg")
	var option := OptionButton.new()
	option.add_item("(no icon)")
	var current: Resource = definition.get("icon") as Resource
	var selected := 0
	for index in range(paths.size()):
		var preview := _svg_preview(paths[index])
		if preview != null:
			option.add_icon_item(preview, paths[index].get_file().get_basename())
		else:
			option.add_item(paths[index].get_file().get_basename())
		if current != null and current.resource_path == paths[index]:
			selected = index + 1
	option.selected = selected
	option.item_selected.connect(func(index: int):
		if _updating:
			return
		var value: Resource = null if index == 0 else load(paths[index - 1])
		_write(definition, "icon", value))
	return _labeled_row("Icon", option)


func _svg_preview(path: String) -> Texture2D:
	if _icon_cache.has(path):
		return _icon_cache[path]
	var icon_bytes := FileAccess.get_file_as_bytes(path)
	if icon_bytes.size() == 0:
		return null
	var image := Image.new()
	if image.load_svg_from_buffer(icon_bytes) != OK:
		return null
	var texture := ImageTexture.create_from_image(image)
	_icon_cache[path] = texture
	return texture


func _scan_resource_paths(dir_path: String, extension: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return result
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.get_extension() == extension:
			result.append("%s/%s" % [dir_path, file_name])
		file_name = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result
