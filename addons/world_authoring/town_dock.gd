@tool
extends PanelContainer

## Bottom-panel Town editor for the world_authoring plugin. Renders the
## active SettlementTown's SettlementDefinition — identity, profiles,
## staffing, population seeds, economy — plus a live demand-table preview
## computed from the placed facilities, the facility placement catalog, spawn
## marker tools, and a validation strip. Every edit writes the definition
## resource (the single sim-truth home); the dock never stores town state of
## its own.

const PROFILE_PICKERS := [
	{"label": "Faction", "property": "faction_definition", "dir": "res://features/factions/resources/factions", "empty": "(none)"},
	{"label": "Behavior", "property": "behavior_profile", "dir": "res://features/world_sim/resources/behavior_profiles", "empty": "(inherit faction)"},
	{"label": "Personality", "property": "personality_profile", "dir": "res://features/factions/resources/personality_profiles", "empty": "(inherit faction)"},
	{"label": "Law", "property": "law_profile", "dir": "res://features/factions/resources/law_profiles", "empty": "(inherit faction)"},
	{"label": "Names", "property": "population_name_profile", "dir": "res://features/world_sim/resources/population_name_profiles", "empty": "(inherit faction)"},
	{"label": "Characters", "property": "population_appearance_profile", "dir": "res://features/world_sim/resources/population_appearance_profiles", "empty": "(inherit faction)"},
]
const OCCUPANCY_LABELS := ["Depopulated", "Sparse", "Populated", "Overcrowded"]
const REALIZATION_POLICIES := ["", "full_town", "important_plus_near", "near_player"]

var _tools: RefCounted
var _town: Node
var _updating := false
var _placeholder: Label
var _content: HBoxContainer
var _definition_box: VBoxContainer
var _population_text: RichTextLabel
var _validation_text: RichTextLabel
var _facility_list: ItemList


func setup(tools: RefCounted) -> void:
	_tools = tools
	custom_minimum_size = Vector2(0, 260)
	_placeholder = Label.new()
	_placeholder.text = "Select a SettlementTown to edit it here."
	_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_placeholder)
	_content = HBoxContainer.new()
	_content.add_theme_constant_override("separation", 14)
	_content.visible = false
	add_child(_content)
	_build_definition_column()
	_build_population_column()
	_build_facilities_column()


func set_town(town: Node) -> void:
	_town = town if town != null and is_instance_valid(town) else null
	_rebuild()


func refresh() -> void:
	_rebuild()


## --- Column construction -----------------------------------------------------


func _build_definition_column() -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(360, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_definition_box = VBoxContainer.new()
	_definition_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_definition_box)
	_content.add_child(scroll)


func _build_population_column() -> void:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(300, 0)
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_section_title("Population (day-zero demand)"))
	_population_text = RichTextLabel.new()
	_population_text.bbcode_enabled = true
	_population_text.fit_content = true
	_population_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_population_text)
	column.add_child(_section_title("Validation"))
	_validation_text = RichTextLabel.new()
	_validation_text.bbcode_enabled = true
	_validation_text.fit_content = true
	column.add_child(_validation_text)
	_content.add_child(column)


func _build_facilities_column() -> void:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Facility placement lives in ONE place: the Town toolbar's Add Facility
	# menu. This dock only reports and navigates.
	column.add_child(_section_title("Markers"))
	var marker_row := HBoxContainer.new()
	var road_button := Button.new()
	road_button.text = "Place Road Spawn"
	road_button.pressed.connect(func(): _tools.begin_spawn_marker_placement("RoadSpawn"))
	marker_row.add_child(road_button)
	var defense_button := Button.new()
	defense_button.text = "Place Defense Spawn"
	defense_button.pressed.connect(func(): _tools.begin_spawn_marker_placement("DefenseSpawn"))
	marker_row.add_child(defense_button)
	column.add_child(marker_row)
	column.add_child(_section_title("Current Facilities"))
	_facility_list = ItemList.new()
	_facility_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_facility_list.custom_minimum_size = Vector2(0, 60)
	column.add_child(_facility_list)
	var actions := HBoxContainer.new()
	var select_button := Button.new()
	select_button.text = "Select"
	select_button.tooltip_text = "Select the highlighted facility in the scene tree (removal lives on the Facility toolbar)."
	select_button.pressed.connect(_on_select_facility_pressed)
	actions.add_child(select_button)
	column.add_child(actions)
	_content.add_child(column)


## --- Rebuild -----------------------------------------------------------------


func _rebuild() -> void:
	if _placeholder == null:
		return
	var definition := _definition()
	var has_town := _town != null and definition != null
	_placeholder.visible = not has_town
	if _town != null and definition == null:
		_placeholder.text = "%s has no SettlementDefinition — assign one in the inspector." % _town.name
	else:
		_placeholder.text = "Select a SettlementTown to edit it here."
	_content.visible = has_town
	if not has_town:
		return
	_updating = true
	_rebuild_definition_fields(definition)
	_rebuild_population_preview(definition)
	_rebuild_facility_list()
	_updating = false


func _rebuild_definition_fields(definition: Resource) -> void:
	for child in _definition_box.get_children():
		child.free()
	var header := _section_title("%s  —  %s" % [str(definition.get("display_name")), _definition_home_label(definition)])
	_definition_box.add_child(header)
	_definition_box.add_child(_text_field("Display Name", str(definition.get("display_name")),
		func(value: String): _write(definition, "display_name", value)))
	_definition_box.add_child(_option_field("Occupancy", OCCUPANCY_LABELS, int(definition.get("occupancy_state")),
		func(index: int): _write(definition, "occupancy_state", index)))
	var policy_labels := ["(inherit default)", "full_town", "important_plus_near", "near_player"]
	var policy_index: int = max(0, REALIZATION_POLICIES.find(str(definition.get("actor_realization_policy"))))
	_definition_box.add_child(_option_field("Realization", policy_labels, policy_index,
		func(index: int): _write(definition, "actor_realization_policy", REALIZATION_POLICIES[index])))
	for picker in PROFILE_PICKERS:
		_definition_box.add_child(_profile_picker(definition, picker))
	_definition_box.add_child(_section_title("Staffing"))
	_definition_box.add_child(_int_field("Guards", int(definition.get("guard_count")), 0, 24,
		func(value: int): _write(definition, "guard_count", value)))
	_definition_box.add_child(_int_field("Guard Posts", int(definition.get("guard_post_count")), 0, 24,
		func(value: int): _write(definition, "guard_post_count", value)))
	_definition_box.add_child(_text_field("Guard Name", str(definition.get("guard_name")),
		func(value: String): _write(definition, "guard_name", value)))
	_definition_box.add_child(_text_field("Staff Id Prefix", str(definition.get("staff_stable_id_prefix")),
		func(value: String): _write(definition, "staff_stable_id_prefix", value)))
	_definition_box.add_child(_text_field("Staff Squad", str(definition.get("staff_squad_name")),
		func(value: String): _write(definition, "staff_squad_name", value)))
	_definition_box.add_child(_check_field("Guards from population", bool(definition.get("use_settlement_population_for_guards")),
		func(value: bool): _write(definition, "use_settlement_population_for_guards", value)))
	_definition_box.add_child(_section_title("Population Seeding"))
	_definition_box.add_child(_int_field("Generation Seed (0 = random)", int(definition.get("generation_seed")), 0, 999999999,
		func(value: int): _write(definition, "generation_seed", value)))
	_definition_box.add_child(_section_title("Economy"))
	_definition_box.add_child(_float_field("Starting Food", float(definition.get("starting_food")),
		func(value: float): _write(definition, "starting_food", value)))
	_definition_box.add_child(_float_field("Max Food", float(definition.get("max_food")),
		func(value: float): _write(definition, "max_food", value)))
	_definition_box.add_child(_float_field("Starting Wealth", float(definition.get("starting_wealth")),
		func(value: float): _write(definition, "starting_wealth", value)))
	_definition_box.add_child(_float_field("Starting Supplies", float(definition.get("starting_supplies")),
		func(value: float): _write(definition, "starting_supplies", value)))
	_definition_box.add_child(_float_field("Growth / Day", float(definition.get("population_growth_per_day")),
		func(value: float): _write(definition, "population_growth_per_day", value)))


func _rebuild_population_preview(definition: Resource) -> void:
	var demand := _compute_demand(definition)
	var lines: Array[String] = []
	var roles: Dictionary = demand["roles"]
	var role_ids := roles.keys()
	role_ids.sort()
	var total_staff := 0
	for role_id in role_ids:
		lines.append("%s: %d" % [str(role_id).capitalize(), int(roles[role_id])])
		total_staff += int(roles[role_id])
	lines.append("")
	lines.append("Staff slots: [b]%d[/b]" % total_staff)
	lines.append("Housing capacity: [b]%d[/b]" % int(demand["housing"]))
	lines.append("Occupancy: [b]%s[/b] (fill x%.2f)" % [
		OCCUPANCY_LABELS[clampi(int(definition.get("occupancy_state")), 0, 3)],
		float(definition.call("get_occupancy_multiplier"))])
	var seed_value := int(definition.get("generation_seed"))
	lines.append("Seed: [b]%s[/b]" % ("randomized per new game" if seed_value == 0 else str(seed_value)))
	_population_text.text = "\n".join(lines)
	_rebuild_validation(definition, demand, total_staff)


func _rebuild_validation(definition: Resource, demand: Dictionary, total_staff: int) -> void:
	var warnings: Array[String] = []
	if definition.get("faction_definition") == null:
		warnings.append("No faction set — profiles and squads have nothing to inherit.")
	var occupancy := int(definition.get("occupancy_state"))
	if occupancy > 0 and int(demand["housing"]) <= 0 and total_staff > 0:
		warnings.append("Populated town with zero housing capacity — place housing.")
	if int(definition.get("guard_count")) > 0 and int(definition.get("guard_post_count")) <= 0 and not bool(demand["has_keep"]):
		warnings.append("Guards authored but no guard posts or keep — guards have nowhere to stand.")
	if str(definition.get("settlement_id")).strip_edges().is_empty():
		warnings.append("Definition has no settlement_id.")
	var town_3d := _town as Node3D
	if town_3d != null and _town.get_node_or_null("RoadSpawn") == null:
		warnings.append("No RoadSpawn marker — road arrivals fall back to the town origin.")
	if warnings.is_empty():
		_validation_text.text = "[color=#7fbf7f]No issues.[/color]"
	else:
		var rows: Array[String] = []
		for warning in warnings:
			rows.append("[color=#e0b060]• %s[/color]" % warning)
		_validation_text.text = "\n".join(rows)


func _compute_demand(definition: Resource) -> Dictionary:
	var roles: Dictionary = {}
	var housing := 0
	var has_keep := false
	var guard_count := int(definition.get("guard_count"))
	if guard_count > 0:
		roles["guard"] = guard_count
	for facility in _tools.get_town_facility_nodes(_town):
		var entry: FacilityDefinition = _tools.find_catalog_entry_for_scene(facility.scene_file_path)
		if entry != null:
			for role_id in entry.staff_role_counts:
				roles[role_id] = int(roles.get(role_id, 0)) + int(entry.staff_role_counts[role_id])
			if entry.get_category() == "keep":
				has_keep = true
		var node_capacity = facility.get("population_capacity")
		if node_capacity != null and int(node_capacity) > 0:
			housing += int(node_capacity)
		elif entry != null:
			housing += entry.population_capacity
	return {"roles": roles, "housing": housing, "has_keep": has_keep}


func _rebuild_facility_list() -> void:
	_facility_list.clear()
	for facility in _tools.get_town_facility_nodes(_town):
		var entry: FacilityDefinition = _tools.find_catalog_entry_for_scene(facility.scene_file_path)
		var label := str(facility.name)
		if entry != null:
			label += "  (%s)" % entry.get_category()
		var index := _facility_list.add_item(label)
		_facility_list.set_item_metadata(index, facility.get_path())


func _on_select_facility_pressed() -> void:
	var facility := _selected_list_facility()
	if facility != null:
		var selection := EditorInterface.get_selection()
		selection.clear()
		selection.add_node(facility)


func _selected_list_facility() -> Node3D:
	var selected := _facility_list.get_selected_items()
	if selected.is_empty() or _town == null:
		return null
	var path: NodePath = _facility_list.get_item_metadata(selected[0])
	return _town.get_tree().root.get_node_or_null(path) as Node3D


## --- Definition IO -----------------------------------------------------------


func _definition() -> Resource:
	if _town == null or not is_instance_valid(_town):
		return null
	return _town.get("settlement_definition") as Resource


func _write(definition: Resource, property_name: String, value) -> void:
	if _updating or definition == null:
		return
	definition.set(property_name, value)
	_save_definition(definition)
	_rebuild_population_preview(definition)


func _save_definition(definition: Resource) -> void:
	var path := definition.resource_path
	if not path.is_empty() and not path.contains("::"):
		ResourceSaver.save(definition, path)
	else:
		# Scene-embedded definition: the edit lives in the open scene.
		EditorInterface.mark_scene_as_unsaved()


func _definition_home_label(definition: Resource) -> String:
	var path := definition.resource_path
	if path.is_empty() or path.contains("::"):
		return "embedded in scene"
	return path.get_file()


## --- Field builders ----------------------------------------------------------


func _section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9))
	return label


func _labeled_row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(150, 0)
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


func _int_field(label_text: String, value: int, minimum: int, maximum: int, on_changed: Callable) -> Control:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1
	spin.value = value
	spin.value_changed.connect(func(new_value: float): on_changed.call(int(new_value)))
	return _labeled_row(label_text, spin)


func _float_field(label_text: String, value: float, on_changed: Callable) -> Control:
	var spin := SpinBox.new()
	spin.min_value = 0.0
	spin.max_value = 100000.0
	spin.step = 0.5
	spin.value = value
	spin.value_changed.connect(func(new_value: float): on_changed.call(new_value))
	return _labeled_row(label_text, spin)


func _check_field(label_text: String, value: bool, on_changed: Callable) -> Control:
	var check := CheckBox.new()
	check.button_pressed = value
	check.toggled.connect(func(pressed: bool): on_changed.call(pressed))
	return _labeled_row(label_text, check)


func _option_field(label_text: String, options: Array, selected_index: int, on_changed: Callable) -> Control:
	var option := OptionButton.new()
	for entry in options:
		option.add_item(str(entry))
	option.selected = clampi(selected_index, 0, options.size() - 1)
	option.item_selected.connect(func(index: int): on_changed.call(index))
	return _labeled_row(label_text, option)


func _profile_picker(definition: Resource, picker: Dictionary) -> Control:
	var paths := _scan_resource_paths(str(picker["dir"]))
	var labels: Array = [str(picker["empty"])]
	for path in paths:
		labels.append(path.get_file().get_basename())
	var current: Resource = definition.get(str(picker["property"])) as Resource
	var selected := 0
	if current != null:
		var found := paths.find(current.resource_path)
		selected = found + 1 if found >= 0 else 0
	return _option_field(str(picker["label"]), labels, selected,
		func(index: int):
			var value: Resource = null if index == 0 else load(paths[index - 1])
			_write(definition, str(picker["property"]), value))


func _scan_resource_paths(dir_path: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return result
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.get_extension() == "tres":
			result.append("%s/%s" % [dir_path, file_name])
		file_name = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result
