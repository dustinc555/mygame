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
const CHARACTER_TYPE_SETS_DIR := "res://features/world_sim/resources/character_type_sets"
const FACTIONS_DIR := "res://features/factions/resources/factions"
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
var _furniture_browser: ItemList
var _furniture_search: LineEdit
var _furniture_category: OptionButton
var _furnisher_label: Label
var _open_rules_button: Button
var _create_rules_menu: MenuButton
var _create_rules_tiers: Array[Dictionary] = []
var _furnish_button: Button
var _reroll_button: Button
var _place_furniture_button: Button
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
	_content.add_child(_build_furniture_column())


## Dedicated Furniture column: generation (Furnish/Reroll) and hand placement
## live together. The browser is a thumbnail grid fed by the editor's
## resource previewer, narrowed by a search box and a category filter —
## built to stay usable as the furniture library grows.
func _build_furniture_column() -> Control:
	var furniture_column := VBoxContainer.new()
	furniture_column.custom_minimum_size = Vector2(320, 0)
	furniture_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	furniture_column.add_child(_section_title("Furniture"))
	# Which furnish recipe Furnish/Reroll will use is authoring truth, so it
	# is shown up front instead of hiding in the path convention: resolution
	# is facility override -> faction/type -> type -> default.
	var furnisher_row := HBoxContainer.new()
	_furnisher_label = Label.new()
	_furnisher_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_furnisher_label.clip_text = true
	furnisher_row.add_child(_furnisher_label)
	_open_rules_button = Button.new()
	_open_rules_button.text = "Open"
	_open_rules_button.tooltip_text = "Open the resolved furnish rules in the Inspector — every dial (clusters, chances, counts) is an export there."
	_open_rules_button.pressed.connect(_on_open_furnish_rules)
	furnisher_row.add_child(_open_rules_button)
	_create_rules_menu = MenuButton.new()
	_create_rules_menu.text = "Create"
	_create_rules_menu.flat = false
	_create_rules_menu.tooltip_text = "Create furnish rules for a tier this facility doesn't have yet (faction/type/default), seeded from the currently resolved rules, and open them for tuning."
	_create_rules_menu.get_popup().index_pressed.connect(_on_create_furnish_rules)
	furnisher_row.add_child(_create_rules_menu)
	furniture_column.add_child(furnisher_row)
	var generate_row := HBoxContainer.new()
	_furnish_button = Button.new()
	_furnish_button.text = "Furnish"
	_furnish_button.tooltip_text = "Generate a full layout for this facility (counter, tables, shelves, lights). Replaces previously GENERATED pieces only — hand-placed furniture is never touched."
	_furnish_button.pressed.connect(func(): _tools.furnish_facility(_facility))
	generate_row.add_child(_furnish_button)
	_reroll_button = Button.new()
	_reroll_button.text = "Reroll"
	_reroll_button.tooltip_text = "New seed, new generated layout. Hand-placed furniture stays."
	_reroll_button.pressed.connect(func(): _tools.furnish_facility(_facility, true))
	generate_row.add_child(_reroll_button)
	furniture_column.add_child(generate_row)
	var filter_row := HBoxContainer.new()
	_furniture_search = LineEdit.new()
	_furniture_search.placeholder_text = "Search furniture..."
	_furniture_search.clear_button_enabled = true
	_furniture_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_furniture_search.text_changed.connect(func(_text: String): _rebuild_furniture_browser())
	filter_row.add_child(_furniture_search)
	_furniture_category = OptionButton.new()
	_furniture_category.item_selected.connect(func(_index: int): _rebuild_furniture_browser())
	filter_row.add_child(_furniture_category)
	furniture_column.add_child(filter_row)
	_furniture_browser = ItemList.new()
	_furniture_browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_furniture_browser.custom_minimum_size = Vector2(0, 150)
	_furniture_browser.icon_mode = ItemList.ICON_MODE_TOP
	_furniture_browser.fixed_icon_size = Vector2i(56, 56)
	_furniture_browser.max_columns = 0
	_furniture_browser.same_column_width = true
	_furniture_browser.item_activated.connect(func(index: int): _begin_browser_placement(index))
	furniture_column.add_child(_furniture_browser)
	_place_furniture_button = Button.new()
	_place_furniture_button.text = "Place Selected"
	_place_furniture_button.tooltip_text = "Ghost-place the selected piece (double-click does the same): hold left-click to anchor, drag rotates, scroll = height (wall mounts), release places. Lands under this facility's Furniture root as a normal editable node."
	_place_furniture_button.pressed.connect(func():
		var selected := _furniture_browser.get_selected_items()
		if not selected.is_empty():
			_begin_browser_placement(selected[0]))
	furniture_column.add_child(_place_furniture_button)
	furniture_column.add_child(_section_title("In this facility"))
	_furniture_text = RichTextLabel.new()
	_furniture_text.bbcode_enabled = true
	_furniture_text.fit_content = true
	furniture_column.add_child(_furniture_text)
	return furniture_column

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
	_rebuild_furniture_browser()
	_rebuild_furniture_summary()
	_updating = false


func _rebuild_identity() -> void:
	for child in _identity_box.get_children():
		_identity_box.remove_child(child)
		child.queue_free()
	_identity_box.add_child(_section_title("%s  —  composed facility" % _facility.name))
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
	if _facility.get("owner_faction_id") != null:
		_identity_box.add_child(_owner_faction_picker())
	if _facility.get("door_access_policy") != null:
		_identity_box.add_child(_door_policy_editor())
	if _facility is SettlementFacilityInstance:
		_identity_box.add_child(_function_picker())


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


## Who owns this facility's property (theft/ownership checks resolve to it).
## "(inherit town)" leaves owner_faction_id empty so the town's faction
## applies; options come from the on-disk faction database.
func _owner_faction_picker() -> Control:
	var paths := _scan_resource_paths(FACTIONS_DIR)
	var option := OptionButton.new()
	option.add_item("(inherit town)")
	var current := str(_facility.get("owner_faction_id")).strip_edges()
	var ids: Array[String] = []
	var selected := 0
	for path in paths:
		var definition := load(path) as Resource
		if definition == null or not definition.has_method("get_id"):
			continue
		var id := str(definition.call("get_id"))
		ids.append(id)
		var emblem := definition.get("icon") as Texture2D
		var label_text := "%s (%s)" % [str(definition.get("display_name")), id]
		if emblem != null:
			option.add_icon_item(emblem, label_text)
		else:
			option.add_item(label_text)
		if id == current:
			selected = ids.size()
	option.selected = selected
	option.item_selected.connect(func(index: int):
		if _updating:
			return
		var value := "" if index == 0 else ids[index - 1]
		_tools.set_facility_property(_facility, "owner_faction_id", value))
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Owner Faction"
	label.custom_minimum_size = Vector2(110, 0)
	row.add_child(label)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)
	return row


func _door_policy_editor() -> Control:
	var column := VBoxContainer.new()
	column.add_child(_section_title("Door Policy"))
	var owner := _facility.call("get_property_owner_character") if _facility.has_method("get_property_owner_character") else null
	var owner_role := str(_facility.call("get_property_owner_role_id")).strip_edges() if _facility.has_method("get_property_owner_role_id") else ""
	var owner_faction := str(_facility.call("get_property_owner_faction")).strip_edges() if _facility.has_method("get_property_owner_faction") else ""
	var owner_label := Label.new()
	if owner != null:
		owner_label.text = "Owner: %s" % str(owner.get("member_name"))
	elif not owner_role.is_empty():
		owner_label.text = "Owner: %s staff slot" % owner_role.capitalize()
	else:
		owner_label.text = "Owner: faction"
	if not owner_faction.is_empty():
		owner_label.text += " (%s)" % owner_faction
	column.add_child(owner_label)
	var access_row := HBoxContainer.new()
	var access_label := Label.new()
	access_label.text = "Access"
	access_label.custom_minimum_size = Vector2(110, 0)
	access_row.add_child(access_label)
	var access := OptionButton.new()
	access.add_item("Private (owner)")
	access.set_item_metadata(0, "private")
	access.add_item("Public")
	access.set_item_metadata(1, "public")
	access.selected = 1 if str(_facility.get("door_access_policy")) == "public" else 0
	access.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	access.item_selected.connect(func(index: int):
		if not _updating:
			_tools.set_facility_property(_facility, "door_access_policy", str(access.get_item_metadata(index))))
	access_row.add_child(access)
	column.add_child(access_row)
	column.add_child(_door_initial_state_field())
	column.add_child(_door_toggle("Use Schedule", "door_schedule_enabled", "Open and close at authored world hours."))
	var schedule_enabled := bool(_facility.get("door_schedule_enabled"))
	column.add_child(_door_hour_field("Open Hour", "door_open_hour", schedule_enabled))
	column.add_child(_door_hour_field("Close Hour", "door_close_hour", schedule_enabled))
	var keep_open := _door_toggle("Keep Open During Hours", "doors_keep_open_during_hours", "The owner walks over to reopen a scheduled door if someone closes it.")
	keep_open.modulate = Color.WHITE if schedule_enabled else Color(1.0, 1.0, 1.0, 0.45)
	column.add_child(keep_open)
	column.add_child(_section_title("Discovered Doors"))
	var doors: Array[Node] = []
	_collect_doors(_facility, doors)
	if doors.is_empty():
		var none := Label.new()
		none.text = "No WorldDoor nodes in the current shell."
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(none)
	for door in doors:
		var target := door
		var button := Button.new()
		button.text = str(_facility.get_path_to(target))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.tooltip_text = "Select this door to edit its DoorDefinition and per-door overrides."
		button.pressed.connect(func(): _tools.select_facility_node(target))
		column.add_child(button)
	return column


func _door_initial_state_field() -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Initial State"
	label.custom_minimum_size = Vector2(110, 0)
	row.add_child(label)
	var option := OptionButton.new()
	for entry in [
		{"label": "Door Default", "value": "door_default"},
		{"label": "Closed", "value": "closed"},
		{"label": "Open", "value": "open"},
		{"label": "Locked", "value": "locked"},
	]:
		option.add_item(str(entry["label"]))
		option.set_item_metadata(option.item_count - 1, entry["value"])
		if str(_facility.get("door_initial_state")) == str(entry["value"]):
			option.selected = option.item_count - 1
	option.tooltip_text = "Initial state for newly-created door records. Saved gameplay state is never reset."
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.item_selected.connect(func(index: int):
		if not _updating:
			_tools.set_facility_property(_facility, "door_initial_state", str(option.get_item_metadata(index))))
	row.add_child(option)
	return row


func _door_toggle(label_text: String, property_name: String, tooltip: String) -> CheckBox:
	var toggle := CheckBox.new()
	toggle.text = label_text
	toggle.tooltip_text = tooltip
	toggle.button_pressed = bool(_facility.get(property_name))
	toggle.toggled.connect(func(pressed: bool):
		if not _updating:
			_tools.set_facility_property(_facility, property_name, pressed))
	return toggle


func _door_hour_field(label_text: String, property_name: String, enabled: bool) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(110, 0)
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 23
	spin.step = 1
	spin.value = int(_facility.get(property_name))
	spin.get_line_edit().editable = enabled
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(value: float):
		if not _updating:
			_tools.set_facility_property(_facility, property_name, int(value)))
	row.add_child(spin)
	return row


func _collect_doors(node: Node, doors: Array[Node]) -> void:
	if node is WorldDoor:
		doors.append(node)
	for child in node.get_children():
		_collect_doors(child, doors)


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
	var no_shell := Button.new()
	no_shell.text = "No Shell"
	no_shell.tooltip_text = "Remove the current shell. The facility remains valid and idle."
	no_shell.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if current_path.is_empty():
		no_shell.disabled = true
		no_shell.text += "  (current)"
	no_shell.pressed.connect(func(): _tools.swap_shell(_facility, "", _clear_furniture_check.button_pressed))
	_shell_list.add_child(no_shell)
	for shell_path_value in _tools.rescan_shell_catalog():
		var shell_path := str(shell_path_value)
		var button := Button.new()
		var basename := shell_path.get_file().get_basename()
		var display_name := str(_tools.shell_display_name(shell_path))
		button.text = display_name if display_name.to_snake_case() == basename else "%s (%s)" % [display_name, basename]
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
	if _facility.get("character_type_set") != null or "character_type_set" in _facility:
		has_any = true
		_staffing_box.add_child(_character_type_set_picker())
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
			_staffing_box.add_child(_character_type_field(slot))
	if not has_any and not _facility.has_method("get_settlement_staff_slots"):
		var none := Label.new()
		none.text = "This facility has no staffing."
		_staffing_box.add_child(none)


## Exact character realizer used by gameplay. Inheritance is facility -> town
## -> faction; missing or invalid realizers reject spawning instead of falling
## back to a generic humanoid.
func _appearance_profile_picker() -> Control:
	var paths: Array[String] = _scan_resource_paths(APPEARANCE_PROFILES_DIR)
	var column := VBoxContainer.new()
	var option := OptionButton.new()
	option.add_item("Default (inherit town/faction)")
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
	label.text = "Character Realizer"
	label.tooltip_text = "Runtime character class and appearance. This exact value, or its town/faction inheritance, is used in gameplay."
	label.custom_minimum_size = Vector2(120, 0)
	row.add_child(label)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)
	column.add_child(row)
	var effective := _facility.call("get_effective_character_realizer") as Resource if _facility.has_method("get_effective_character_realizer") else current
	var effective_label := Label.new()
	var source: String = str(_facility.call("get_effective_character_realizer_source")) if _facility.has_method("get_effective_character_realizer_source") else ("facility" if current != null else "inherited")
	effective_label.text = "Effective: %s (%s)" % [effective.resource_path.get_file().get_basename().capitalize() if effective != null else "INVALID", source]
	effective_label.modulate = Color(0.72, 0.9, 0.72) if effective != null and effective.get("actor_script") != null and not str(effective.get("profile_id")).strip_edges().is_empty() and effective.has_method("create_appearance") else Color(1.0, 0.42, 0.35)
	column.add_child(effective_label)
	return column


func _character_type_set_picker() -> Control:
	var paths: Array[String] = _scan_resource_paths(CHARACTER_TYPE_SETS_DIR)
	var column := VBoxContainer.new()
	var option := OptionButton.new()
	option.add_item("Default (inherit town/faction)")
	var current: Resource = _facility.get("character_type_set") as Resource
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
		_tools.set_facility_property(_facility, "character_type_set", value))
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Character Types"
	label.custom_minimum_size = Vector2(120, 0)
	row.add_child(label)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)
	column.add_child(row)
	var effective := _facility.call("get_effective_character_type_set") as Resource if _facility.has_method("get_effective_character_type_set") else current
	var effective_label := Label.new()
	var source: String = str(_facility.call("get_effective_character_type_set_source")) if _facility.has_method("get_effective_character_type_set_source") else ("facility" if current != null else "inherited")
	effective_label.text = "Effective: %s (%s)" % [effective.resource_path.get_file().get_basename().capitalize() if effective != null else "INVALID", source]
	effective_label.modulate = Color(0.72, 0.9, 0.72) if effective != null and effective.has_method("resolve_character_type") and effective.call("resolve_character_type", "", "resident") != null else Color(1.0, 0.42, 0.35)
	column.add_child(effective_label)
	return column


func _character_type_field(slot: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "  Character Type"
	label.custom_minimum_size = Vector2(120, 0)
	row.add_child(label)
	var option := OptionButton.new()
	var type_set := _facility.call("get_effective_character_type_set") as Resource if _facility.has_method("get_effective_character_type_set") else null
	var role_id := str(slot.get("role_id", "")).strip_edges().to_lower()
	var role_index := int(slot.get("role_index", 0))
	var requested := str(slot.get("character_type_id", "")).strip_edges().to_lower()
	var default_type := type_set.call("resolve_character_type", "", role_id) as Resource if type_set != null and type_set.has_method("resolve_character_type") else null
	option.add_item("Default: %s" % (str(default_type.get("display_name")) if default_type != null else "INVALID"))
	var available: Array = type_set.call("get_character_types") if type_set != null and type_set.has_method("get_character_types") else []
	var selected := 0
	for character_type in available:
		var type_id := str(character_type.get("type_id")).strip_edges().to_lower()
		option.add_item(str(character_type.get("display_name")))
		option.set_item_metadata(option.item_count - 1, type_id)
		if requested == type_id:
			selected = option.item_count - 1
	option.selected = selected
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.item_selected.connect(func(index: int):
		if _updating:
			return
		var overrides: Dictionary = (_facility.get("staff_character_type_ids") as Dictionary).duplicate(true)
		var key := "%s:%d" % [role_id, role_index]
		if index == 0:
			overrides.erase(key)
		else:
			overrides[key] = str(option.get_item_metadata(index))
		_tools.set_facility_property(_facility, "staff_character_type_ids", overrides))
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


func _rebuild_furnisher_row() -> void:
	if _furnisher_label == null:
		return
	var resolved: Dictionary = {}
	if _facility is SettlementFacilityInstance:
		resolved = _tools.resolve_furnish_rules(_facility)
	var rules: Resource = resolved.get("rules")
	if rules == null:
		_furnisher_label.text = "Furnisher: none — create one"
		_furnisher_label.tooltip_text = "Nothing resolves. Resolution: facility override -> faction/type -> type -> default."
	else:
		_furnisher_label.text = "Furnisher: %s" % str(resolved.get("label", "?"))
		_furnisher_label.tooltip_text = "%s\nResolution: facility override -> faction/type -> type -> default." % str(resolved.get("path", "embedded on this facility"))
	_open_rules_button.disabled = rules == null
	_create_rules_tiers = _tools.missing_furnish_rule_tiers(_facility) if _facility is SettlementFacilityInstance else []
	var popup := _create_rules_menu.get_popup()
	popup.clear()
	for tier in _create_rules_tiers:
		popup.add_item(str(tier["label"]))
	_create_rules_menu.disabled = _create_rules_tiers.is_empty()


func _on_open_furnish_rules() -> void:
	var resolved: Dictionary = _tools.resolve_furnish_rules(_facility) if _facility != null else {}
	var rules: Resource = resolved.get("rules")
	if rules != null:
		EditorInterface.edit_resource(rules)


func _on_create_furnish_rules(index: int) -> void:
	if index < 0 or index >= _create_rules_tiers.size():
		return
	_tools.create_furnish_rules_file(_facility, _create_rules_tiers[index])
	_rebuild_furnisher_row()


func _rebuild_furniture_browser() -> void:
	if _furniture_browser == null:
		return
	_rebuild_furnisher_row()
	var entries: Array = _tools.get_furniture_catalog()
	_populate_furniture_categories(entries)
	var placeable := _facility is SettlementFacilityInstance
	var blocked_tooltip := "" if placeable else "Hand placement needs a composed facility (bar/jail/keep)."
	_furniture_browser.tooltip_text = blocked_tooltip
	_place_furniture_button.disabled = not placeable
	_furnish_button.disabled = not placeable
	_reroll_button.disabled = not placeable
	var query := _furniture_search.text.strip_edges().to_lower() if _furniture_search != null else ""
	var category := ""
	if _furniture_category != null and _furniture_category.selected > 0:
		category = str(_furniture_category.get_item_metadata(_furniture_category.selected))
	_furniture_browser.clear()
	var fallback_icon := get_theme_icon("PackedScene", "EditorIcons")
	var previewer := EditorInterface.get_resource_previewer()
	for entry in entries:
		if not category.is_empty() and str(entry["category"]) != category:
			continue
		if not query.is_empty() and not str(entry["name"]).to_lower().contains(query):
			continue
		var path := str(entry["path"])
		var index := _furniture_browser.add_item(str(entry["name"]), fallback_icon)
		_furniture_browser.set_item_metadata(index, path)
		_furniture_browser.set_item_tooltip(index, "%s\nDouble-click to place." % path)
		if not placeable:
			_furniture_browser.set_item_disabled(index, true)
		previewer.queue_resource_preview(path, self, "_on_furniture_preview_ready", path)


## Category dropdown is rebuilt from the catalog (never hardcoded) while
## preserving the current selection.
func _populate_furniture_categories(entries: Array) -> void:
	if _furniture_category == null:
		return
	var selected := ""
	if _furniture_category.selected > 0:
		selected = str(_furniture_category.get_item_metadata(_furniture_category.selected))
	var categories: Array[String] = []
	for entry in entries:
		if not categories.has(str(entry["category"])):
			categories.append(str(entry["category"]))
	categories.sort()
	_furniture_category.clear()
	_furniture_category.add_item("All")
	for category in categories:
		_furniture_category.add_item(category.capitalize())
		_furniture_category.set_item_metadata(_furniture_category.item_count - 1, category)
		if category == selected:
			_furniture_category.selected = _furniture_category.item_count - 1


## Async thumbnail arrival from the editor's resource previewer: items are
## matched back by path metadata because the grid may have been refiltered
## while the preview rendered.
func _on_furniture_preview_ready(path: String, preview: Texture2D, _thumbnail: Texture2D, _userdata: Variant) -> void:
	if preview == null:
		return
	for index in range(_furniture_browser.item_count):
		if str(_furniture_browser.get_item_metadata(index)) == path:
			_furniture_browser.set_item_icon(index, preview)
			return


func _begin_browser_placement(index: int) -> void:
	if _facility == null or not is_instance_valid(_facility):
		return
	var path := str(_furniture_browser.get_item_metadata(index))
	if not path.is_empty():
		_tools.begin_furniture_placement(_facility, path)


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
