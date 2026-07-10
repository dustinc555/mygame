@tool
extends PanelContainer

## Bottom-panel Facility editor for the world_authoring plugin — the
## Facility twin of the Town dock. Shows the selected facility's function
## assignment and building shell, and makes both editable in one visible
## place: a function picker scanned from FacilityFunctionDefinition
## resources and a shell grid scanned from WorldBuilding scenes. Also
## summarizes the furniture discovered in the facility's subtree, since
## function behavior binds to furniture at runtime.

const FUNCTIONS_DIR := "res://features/world_sim/resources/facility_functions"
const APPEARANCE_PROFILES_DIR := "res://features/world_sim/resources/population_appearance_profiles"
const ICONS_DIR := "res://addons/world_authoring/icons"
## facility_type / function facility_type -> icon file.
const TYPE_ICONS := {
	"bar": "facility_bar.svg",
	"tavern": "facility_bar.svg",
	"social": "facility_bar.svg",
	"police": "facility_jail.svg",
	"guard": "facility_jail.svg",
	"keep": "facility_keep.svg",
	"farm": "facility_field.svg",
	"shop": "facility_shop.svg",
	"weapon_shop": "facility_shop.svg",
	"armor_shop": "facility_shop.svg",
	"travel_shop": "facility_shop.svg",
	"potion_shop": "facility_shop.svg",
	"housing": "facility_house.svg",
}

var _tools: RefCounted
var _facility: Node
var _updating := false
var _placeholder: Label
var _content: HBoxContainer
var _identity_box: VBoxContainer
var _shell_list: VBoxContainer
var _furniture_text: RichTextLabel
var _clear_furniture_check: CheckBox
var _staffing_box: VBoxContainer
var _icon_cache := {}


func setup(tools: RefCounted) -> void:
	_tools = tools
	custom_minimum_size = Vector2(0, 220)
	_placeholder = Label.new()
	_placeholder.text = "Select a facility (a building under a town's Facilities root) to edit it here."
	_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_placeholder)
	_content = HBoxContainer.new()
	_content.add_theme_constant_override("separation", 14)
	_content.visible = false
	add_child(_content)
	var identity_scroll := ScrollContainer.new()
	identity_scroll.custom_minimum_size = Vector2(340, 0)
	identity_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_identity_box = VBoxContainer.new()
	_identity_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity_scroll.add_child(_identity_box)
	_content.add_child(identity_scroll)
	var shell_column := VBoxContainer.new()
	shell_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell_column.add_child(_section_title("Building Shell (click to swap)"))
	_clear_furniture_check = CheckBox.new()
	_clear_furniture_check.text = "Clear old furniture on swap"
	_clear_furniture_check.tooltip_text = "Furniture is laid out against a specific shell's floor plan; carrying it into a different shell strands it. Swap is undoable either way."
	_clear_furniture_check.button_pressed = true
	shell_column.add_child(_clear_furniture_check)
	var shell_scroll := ScrollContainer.new()
	shell_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_shell_list = VBoxContainer.new()
	_shell_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell_scroll.add_child(_shell_list)
	shell_column.add_child(shell_scroll)
	_content.add_child(shell_column)
	var staffing_scroll := ScrollContainer.new()
	staffing_scroll.custom_minimum_size = Vector2(300, 0)
	staffing_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_staffing_box = VBoxContainer.new()
	_staffing_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	staffing_scroll.add_child(_staffing_box)
	_content.add_child(staffing_scroll)
	var furniture_column := VBoxContainer.new()
	furniture_column.custom_minimum_size = Vector2(220, 0)
	furniture_column.add_child(_section_title("Furniture (discovered)"))
	_furniture_text = RichTextLabel.new()
	_furniture_text.bbcode_enabled = true
	_furniture_text.fit_content = true
	_furniture_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	furniture_column.add_child(_furniture_text)
	_content.add_child(furniture_column)


func set_facility(facility: Node) -> void:
	_facility = facility if facility != null and is_instance_valid(facility) else null
	# Deferred on purpose: set_facility is reachable from this dock's own
	# button signals (shell swap -> refresh); rebuilding synchronously would
	# free the pressed button while its signal is still on the stack.
	_rebuild.call_deferred()


func _rebuild() -> void:
	if _placeholder == null:
		return
	if _facility != null and not is_instance_valid(_facility):
		_facility = null
	var has_facility := _facility != null
	_placeholder.visible = not has_facility
	_content.visible = has_facility
	if not has_facility:
		return
	_updating = true
	_rebuild_identity()
	_rebuild_shell_list()
	_rebuild_staffing()
	_rebuild_furniture_summary()
	_updating = false


func _rebuild_identity() -> void:
	for child in _identity_box.get_children():
		_identity_box.remove_child(child)
		child.queue_free()
	var kind := "composed facility" if _facility is SettlementFacilityInstance else "building shell"
	_identity_box.add_child(_section_title("%s  —  %s" % [_facility.name, kind]))
	if _facility.get("display_name") != null:
		_identity_box.add_child(_facility_name_field(str(_facility.get("display_name"))))
	var shell_path: String = _tools.current_shell_path(_facility)
	var shell_label := Label.new()
	shell_label.text = "Current shell: %s" % (shell_path.get_file().get_basename() if not shell_path.is_empty() else "(none)")
	_identity_box.add_child(shell_label)
	if _tools.facility_is_packed(_facility):
		var unpack := Button.new()
		if _tools.facility_unpack_blocked(_facility):
			unpack.text = "Unpack the town first"
			unpack.disabled = true
			unpack.tooltip_text = "This facility sits inside a packed town instance. Select the town node and use its 'Unpack Into Zone' button, then unpack this facility."
		else:
			unpack.text = "Unpack For Editing"
			unpack.tooltip_text = "This facility is a locked scene instance — its furniture and points can't be edited here. Unpack expands it into plain nodes owned by this scene. Undoable."
			unpack.pressed.connect(func(): _tools.unpack_facility(_facility))
		_identity_box.add_child(unpack)
	if _facility is SettlementFacilityInstance:
		_identity_box.add_child(_function_picker())
		var furnish_row := HBoxContainer.new()
		var furnish := Button.new()
		furnish.text = "Furnish"
		furnish.tooltip_text = "Generate furniture for this facility as normal editable nodes (counter, table clusters, wall shelves). Hand-placed furniture is never touched. Undoable."
		furnish.pressed.connect(func(): _tools.furnish_facility(_facility))
		furnish_row.add_child(furnish)
		var reroll := Button.new()
		reroll.text = "Reroll"
		reroll.tooltip_text = "New seed, new layout. Replaces only generated furniture; your edits stay."
		reroll.pressed.connect(func(): _tools.furnish_facility(_facility, true))
		furnish_row.add_child(reroll)
		_identity_box.add_child(furnish_row)
	elif _facility is WorldBuilding:
		var note := Label.new()
		note.text = "Pure shell (housing). Assigning a function will wrap it in a facility — coming with the furnish pass."
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_identity_box.add_child(note)


func _facility_name_field(current_name: String) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Name"
	label.custom_minimum_size = Vector2(110, 0)
	row.add_child(label)
	var edit := LineEdit.new()
	edit.text = current_name
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var commit := func():
		if not _updating and edit.text.strip_edges() != str(_facility.get("display_name")):
			_tools.set_facility_property(_facility, "display_name", edit.text.strip_edges())
	edit.text_submitted.connect(func(_text: String): commit.call())
	edit.focus_exited.connect(commit)
	row.add_child(edit)
	return row


func _function_picker() -> Control:
	var paths := _scan_function_paths()
	var option := OptionButton.new()
	option.add_item("(no function)")
	var current: Resource = _facility.get("facility_function") as Resource
	var selected := 0
	for index in range(paths.size()):
		var definition := load(paths[index]) as FacilityFunctionDefinition
		var label_text := definition.display_name if definition != null else paths[index].get_file().get_basename()
		var icon := _type_icon(definition.facility_type if definition != null else "")
		if icon != null:
			option.add_icon_item(icon, label_text)
		else:
			option.add_item(label_text)
		if current != null and current.resource_path == paths[index]:
			selected = index + 1
	option.selected = selected
	option.item_selected.connect(func(index: int):
		if _updating:
			return
		var value: Resource = null if index == 0 else load(paths[index - 1])
		_tools.assign_function(_facility, value))
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Function"
	label.custom_minimum_size = Vector2(110, 0)
	row.add_child(label)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)
	return row


func _rebuild_shell_list() -> void:
	for child in _shell_list.get_children():
		_shell_list.remove_child(child)
		child.queue_free()
	var current_path: String = _tools.current_shell_path(_facility)
	for shell_path_value in _tools.rescan_shell_catalog():
		var shell_path := str(shell_path_value)
		var button := Button.new()
		button.text = shell_path.get_file().get_basename()
		button.tooltip_text = shell_path
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if shell_path == current_path:
			button.disabled = true
			button.text += "  (current)"
		button.pressed.connect(func(): _tools.swap_shell(_facility, shell_path, _clear_furniture_check.button_pressed))
		_shell_list.add_child(button)


## Guard counts, guard-post placement, and the facility's staff slots (who is
## assigned). Controls appear only when the facility actually has the
## property — a plain housing shell shows none.
func _rebuild_staffing() -> void:
	for child in _staffing_box.get_children():
		_staffing_box.remove_child(child)
		child.queue_free()
	_staffing_box.add_child(_section_title("Staffing"))
	var has_any := false
	# Role toggles first (facilities start empty; each role is opt-in), then
	# counted roles. Only properties the facility actually has show up.
	for property_name in ["has_barkeeper", "has_barber"]:
		var toggle_value = _facility.get(property_name)
		if toggle_value == null:
			continue
		has_any = true
		_staffing_box.add_child(_staff_toggle_field(property_name, bool(toggle_value)))
	for property_name in ["waiter_count", "guard_count", "guard_post_count", "visitor_capacity"]:
		var value = _facility.get(property_name)
		if value == null:
			continue
		has_any = true
		_staffing_box.add_child(_staff_count_field(property_name, int(value)))
	if _facility.get("population_appearance_profile") != null or "population_appearance_profile" in _facility:
		has_any = true
		_staffing_box.add_child(_appearance_profile_picker())
	if has_any:
		var place_post := Button.new()
		place_post.text = "Place Guard Post"
		place_post.tooltip_text = "Click terrain to add an authored guard post to this facility (extra to the generated ones)."
		place_post.pressed.connect(func(): _tools.begin_guard_post_placement(_facility))
		_staffing_box.add_child(place_post)
	if _facility.has_method("get_settlement_staff_slots"):
		_staffing_box.add_child(_section_title("Staff Slots"))
		var slots: Array = _facility.call("get_settlement_staff_slots")
		if slots.is_empty():
			var empty := Label.new()
			empty.text = "No staff slots (add guards or assign a function)."
			empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_staffing_box.add_child(empty)
		for slot_value in slots:
			var slot: Dictionary = slot_value
			var row := Label.new()
			var filled := bool(slot.get("filled", false))
			row.text = "%s %s — %s" % ["●" if filled else "○", str(slot.get("display_name", slot.get("slot_id", "slot"))), "assigned" if filled else "vacant"]
			_staffing_box.add_child(row)
	if not has_any and not _facility.has_method("get_settlement_staff_slots"):
		var none := Label.new()
		none.text = "This facility has no staffing."
		_staffing_box.add_child(none)


## Character generator for whoever this facility realizes (staff, visitors).
## "(inherit)" falls back to the parent town's profile.
func _appearance_profile_picker() -> Control:
	var paths: Array[String] = _scan_resource_paths(APPEARANCE_PROFILES_DIR)
	var option := OptionButton.new()
	option.add_item("(inherit from town)")
	var current: Resource = _facility.get("population_appearance_profile") as Resource
	var selected := 0
	for index in range(paths.size()):
		option.add_item(paths[index].get_file().get_basename().capitalize())
		if current != null and current.resource_path == paths[index]:
			selected = index + 1
	option.selected = selected
	option.item_selected.connect(func(index: int):
		if _updating:
			return
		var value: Resource = null if index == 0 else load(paths[index - 1])
		_tools.set_facility_property(_facility, "population_appearance_profile", value))
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Characters"
	label.tooltip_text = "Appearance generator used when this facility realizes new characters."
	label.custom_minimum_size = Vector2(120, 0)
	row.add_child(label)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)
	return row


func _staff_toggle_field(property_name: String, value: bool) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = property_name.trim_prefix("has_").capitalize()
	label.custom_minimum_size = Vector2(120, 0)
	row.add_child(label)
	var check := CheckBox.new()
	check.button_pressed = value
	check.text = "staffed" if value else "none"
	check.toggled.connect(func(pressed: bool):
		if not _updating:
			_tools.set_facility_property(_facility, property_name, pressed))
	row.add_child(check)
	return row


func _staff_count_field(property_name: String, value: int) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = property_name.capitalize()
	label.custom_minimum_size = Vector2(120, 0)
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 24
	spin.step = 1
	spin.value = value
	spin.value_changed.connect(func(new_value: float):
		if not _updating:
			_tools.set_facility_property(_facility, property_name, int(new_value)))
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin)
	return row


func _rebuild_furniture_summary() -> void:
	var counts := {}
	_count_furniture(_facility, counts)
	if counts.is_empty():
		_furniture_text.text = "[color=#999]No furniture in this facility yet.[/color]"
		return
	var lines: Array[String] = []
	var keys := counts.keys()
	keys.sort()
	for key in keys:
		lines.append("%s: %d" % [str(key).capitalize(), int(counts[key])])
	_furniture_text.text = "\n".join(lines)


func _count_furniture(node: Node, counts: Dictionary) -> void:
	if node != _facility and node.is_in_group(FurnitureRules.FURNITURE_GROUP):
		var type_value = node.get("furniture_type")
		var type_name := FurnitureRules.type_name(int(type_value)) if type_value != null else "decor"
		counts[type_name] = int(counts.get(type_name, 0)) + 1
	for child in node.get_children():
		_count_furniture(child, counts)


func _scan_function_paths() -> Array[String]:
	return _scan_resource_paths(FUNCTIONS_DIR)


func _scan_resource_paths(directory: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return result
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.get_extension() == "tres":
			result.append(directory.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result


func _type_icon(facility_type: String) -> Texture2D:
	var icon_file := str(TYPE_ICONS.get(facility_type, ""))
	if icon_file.is_empty():
		icon_file = "facility.svg"
	if _icon_cache.has(icon_file):
		return _icon_cache[icon_file]
	var icon_bytes := FileAccess.get_file_as_bytes(ICONS_DIR.path_join(icon_file))
	if icon_bytes.size() == 0:
		return null
	var image := Image.new()
	if image.load_svg_from_buffer(icon_bytes) != OK:
		return null
	var texture := ImageTexture.create_from_image(image)
	_icon_cache[icon_file] = texture
	return texture


func _section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9))
	return label
