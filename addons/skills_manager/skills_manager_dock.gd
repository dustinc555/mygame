@tool
extends VBoxContainer

const CATALOG_PATH := "res://features/skills/resources/phase_1_skill_catalog.tres"
const PROGRESSION_PATH := "res://features/skills/resources/skill_progression.tres"
const CHECKS_DIRECTORY := "res://features/skills/resources/checks"
const DEFINITIONS_DIRECTORY := "res://features/skills/resources/definitions"
const SKILL_DEFINITION_SCRIPT := preload("res://features/skills/resources/skill_definition.gd")
const SKILL_CHECK_DEFINITION_SCRIPT := preload("res://features/skills/resources/skill_check_definition.gd")
const SKILL_CHECK_RULES := preload("res://features/skills/sim/skill_check_rules.gd")

var _plugin: EditorPlugin
var _catalog: SkillCatalog
var _progression: Resource
var _active_resource: Resource
var _skills_list: ItemList
var _checks_list: ItemList
var _inspector: EditorInspector
var _validation_label: RichTextLabel
var _progression_preview: RichTextLabel
var _check_preview: Tree
var _show_archived := false


func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin
	_catalog = load(CATALOG_PATH) as SkillCatalog
	_progression = load(PROGRESSION_PATH)
	name = "SkillsManagerDock"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()
	_refresh_all()


func _build_ui() -> void:
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(header)
	var title := Label.new()
	title.text = "Skills Manager"
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var save_button := Button.new()
	save_button.text = "Save"
	save_button.tooltip_text = "Save the active resource and the skill catalog."
	save_button.pressed.connect(_save_active_resource)
	header.add_child(save_button)
	var refresh_button := Button.new()
	refresh_button.text = "Refresh"
	refresh_button.pressed.connect(_refresh_all)
	header.add_child(refresh_button)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)
	tabs.add_child(_build_skills_tab())
	tabs.add_child(_build_progression_tab())
	tabs.add_child(_build_checks_tab())


func _build_skills_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = "Skills"
	tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var controls := HBoxContainer.new()
	tab.add_child(controls)
	var add_button := Button.new()
	add_button.text = "Add Skill"
	add_button.pressed.connect(_add_skill)
	controls.add_child(add_button)
	var archive_button := Button.new()
	archive_button.text = "Archive/Restore"
	archive_button.pressed.connect(_toggle_archive_selected_skill)
	controls.add_child(archive_button)
	var extract_button := Button.new()
	extract_button.text = "Extract Resources"
	extract_button.tooltip_text = "Save embedded skill definitions as separate .tres files for clean diffs."
	extract_button.pressed.connect(_extract_embedded_definitions)
	controls.add_child(extract_button)
	var archived := CheckBox.new()
	archived.text = "Show archived"
	archived.toggled.connect(func(value: bool) -> void:
		_show_archived = value
		_refresh_skills())
	controls.add_child(archived)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_child(split)
	_skills_list = ItemList.new()
	_skills_list.custom_minimum_size = Vector2(260.0, 0.0)
	_skills_list.item_selected.connect(_on_skill_selected)
	split.add_child(_skills_list)
	_inspector = EditorInspector.new()
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(_inspector)
	_validation_label = RichTextLabel.new()
	_validation_label.fit_content = true
	_validation_label.bbcode_enabled = true
	tab.add_child(_validation_label)
	return tab


func _build_progression_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = "Progression"
	tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_child(split)
	var inspector := EditorInspector.new()
	inspector.custom_minimum_size = Vector2(420.0, 0.0)
	inspector.edit(_progression)
	split.add_child(inspector)
	_progression_preview = RichTextLabel.new()
	_progression_preview.bbcode_enabled = true
	_progression_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(_progression_preview)
	var refresh_button := Button.new()
	refresh_button.text = "Refresh curve preview"
	refresh_button.pressed.connect(_refresh_progression_preview)
	tab.add_child(refresh_button)
	return tab


func _build_checks_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = "Checks"
	tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(260.0, 0.0)
	split.add_child(left)
	_checks_list = ItemList.new()
	_checks_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_checks_list.item_selected.connect(_on_check_selected)
	left.add_child(_checks_list)
	var check_inspector := EditorInspector.new()
	check_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(check_inspector)
	var preview_box := VBoxContainer.new()
	preview_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(preview_box)
	var heading := Label.new()
	heading.text = "Lockpick probability preview"
	preview_box.add_child(heading)
	_check_preview = Tree.new()
	_check_preview.columns = 7
	_check_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_box.add_child(_check_preview)
	var refresh_button := Button.new()
	refresh_button.text = "Refresh check preview"
	refresh_button.pressed.connect(_refresh_check_preview)
	preview_box.add_child(refresh_button)
	check_inspector.set_meta("skills_manager_check_inspector", true)
	return tab


func _refresh_all() -> void:
	_refresh_skills()
	_refresh_checks()
	_refresh_progression_preview()
	_refresh_check_preview()


func _refresh_skills() -> void:
	if _skills_list == null or _catalog == null:
		return
	_skills_list.clear()
	for definition in _catalog.get_definitions(_show_archived):
		if definition.is_archived and not _show_archived:
			continue
		var label := "%s  [%s]" % [definition.display_name, definition.skill_id]
		if definition.is_archived:
			label = "[Archived] " + label
		_skills_list.add_item(label)
		_skills_list.set_item_metadata(_skills_list.item_count - 1, definition)
	_refresh_validation()


func _refresh_checks() -> void:
	if _checks_list == null:
		return
	_checks_list.clear()
	for check in _get_checks():
		_checks_list.add_item("%s  [%s]" % [str(check.get("display_name")), str(check.get("check_id"))])
		_checks_list.set_item_metadata(_checks_list.item_count - 1, check)


func _refresh_validation() -> void:
	if _validation_label == null or _catalog == null:
		return
	var errors := _catalog.get_validation_errors()
	_validation_label.text = "[color=#8fd18f]Catalog valid[/color]" if errors.is_empty() else "[color=#e69a9a]" + "\n".join(errors) + "[/color]"


func _refresh_progression_preview() -> void:
	if _progression_preview == null or _progression == null:
		return
	var rows: PackedStringArray = ["[b]XP needed for the next level[/b]"]
	for level in [1, 10, 25, 50, 75, 100]:
		if level <= int(_progression.get("maximum_level")):
			rows.append("Level %d: %d XP" % [level, SkillRules.get_xp_to_next_level(level)])
	rows.append("\nMaximum level: %d" % int(_progression.get("maximum_level")))
	_progression_preview.text = "\n".join(rows)


func _refresh_check_preview() -> void:
	if _check_preview == null:
		return
	_check_preview.clear()
	var root := _check_preview.create_item()
	var check := _get_selected_check()
	if check == null:
		var checks := _get_checks()
		check = checks[0] if not checks.is_empty() else null
	if check == null:
		return
	for column in range(7):
		_check_preview.set_column_title(column, "Skill" if column == 0 else "")
	var header := _check_preview.create_item(root)
	header.set_text(0, "Skill")
	var tiers: Array[Resource] = check.get_valid_tiers()
	for index in range(mini(tiers.size(), 6)):
		header.set_text(index + 1, str(tiers[index].get("display_name")))
	for skill_level in [1, 10, 25, 50, 75, 100]:
		var row := _check_preview.create_item(root)
		row.set_text(0, str(skill_level))
		for index in range(mini(tiers.size(), 6)):
			var tier: Resource = tiers[index]
			var chance := SKILL_CHECK_RULES.get_success_chance(check, str(tier.get("tier_id")), skill_level)
			row.set_text(index + 1, "Cannot attempt" if chance <= 0.0 else "%.0f%%" % (chance * 100.0))


func _on_skill_selected(index: int) -> void:
	var definition = _skills_list.get_item_metadata(index) as SkillDefinition
	_set_active_resource(definition)


func _on_check_selected(index: int) -> void:
	var check = _checks_list.get_item_metadata(index) as Resource
	_set_active_resource(check)
	var inspector := _find_check_inspector()
	if inspector != null:
		inspector.edit(check)
	_refresh_check_preview()


func _set_active_resource(resource: Resource) -> void:
	_active_resource = resource
	if _inspector != null:
		_inspector.edit(resource)
	_bind_resource(resource)


func _bind_resource(resource: Resource) -> void:
	if resource != null and not resource.changed.is_connected(_on_resource_changed):
		resource.changed.connect(_on_resource_changed)


func _on_resource_changed() -> void:
	call_deferred("_refresh_all")


func _add_skill() -> void:
	if _catalog == null:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DEFINITIONS_DIRECTORY))
	var definition := SKILL_DEFINITION_SCRIPT.new() as SkillDefinition
	definition.skill_id = _next_skill_id()
	definition.display_name = "New Skill"
	definition.category_id = "misc"
	definition.category_name = "Misc"
	var save_path := "%s/%s.tres" % [DEFINITIONS_DIRECTORY, definition.skill_id.replace(".", "_")]
	var save_error := ResourceSaver.save(definition, save_path)
	if save_error != OK:
		push_error("Skills Manager could not create %s." % save_path)
		return
	var old_definitions: Array = _catalog.definitions.duplicate()
	var new_definitions: Array = old_definitions.duplicate()
	new_definitions.append(definition)
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Add Skill Definition")
	undo_redo.add_do_property(_catalog, "definitions", new_definitions)
	undo_redo.add_undo_property(_catalog, "definitions", old_definitions)
	undo_redo.add_do_method(self, "_save_catalog")
	undo_redo.add_undo_method(self, "_save_catalog")
	undo_redo.commit_action()
	_refresh_skills()
	_set_active_resource(definition)


func _toggle_archive_selected_skill() -> void:
	if not _active_resource is SkillDefinition:
		return
	var definition := _active_resource as SkillDefinition
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action("Archive Skill" if not definition.is_archived else "Restore Skill")
	undo_redo.add_do_property(definition, "is_archived", not definition.is_archived)
	undo_redo.add_undo_property(definition, "is_archived", definition.is_archived)
	undo_redo.add_do_method(self, "_save_active_resource")
	undo_redo.add_undo_method(self, "_save_active_resource")
	undo_redo.commit_action()
	_refresh_skills()


func _extract_embedded_definitions() -> void:
	if _catalog == null:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DEFINITIONS_DIRECTORY))
	for definition in _catalog.get_definitions(true):
		if not definition.resource_path.is_empty():
			continue
		var path := "%s/%s.tres" % [DEFINITIONS_DIRECTORY, definition.skill_id.replace(".", "_")]
		var save_error := ResourceSaver.save(definition, path)
		if save_error != OK:
			push_error("Skills Manager could not extract %s." % definition.skill_id)
	_save_catalog()
	_refresh_skills()


func _save_active_resource() -> void:
	if _active_resource != null and not _active_resource.resource_path.is_empty():
		ResourceSaver.save(_active_resource, _active_resource.resource_path)
	_save_catalog()


func _save_catalog() -> void:
	if _catalog != null:
		ResourceSaver.save(_catalog, CATALOG_PATH)


func _next_skill_id() -> String:
	var index := 1
	while _catalog.get_definition("misc.new_skill_%d" % index) != null:
		index += 1
	return "misc.new_skill_%d" % index


func _get_checks() -> Array[Resource]:
	var result: Array[Resource] = []
	var directory := DirAccess.open(CHECKS_DIRECTORY)
	if directory == null:
		return result
	for file_name in directory.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var resource := load(CHECKS_DIRECTORY.path_join(file_name))
		if resource != null and resource.get_script() == SKILL_CHECK_DEFINITION_SCRIPT:
			result.append(resource)
	result.sort_custom(func(a: Resource, b: Resource) -> bool: return str(a.get("check_id")) < str(b.get("check_id")))
	return result


func _get_selected_check() -> Resource:
	return _active_resource if _active_resource != null and _active_resource.get_script() == SKILL_CHECK_DEFINITION_SCRIPT else null


func _find_check_inspector() -> EditorInspector:
	for node in _collect_children_recursive(self):
		if node is EditorInspector and node.has_meta("skills_manager_check_inspector"):
			return node as EditorInspector
	return null


func _collect_children_recursive(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in node.get_children():
		result.append(child)
		result.append_array(_collect_children_recursive(child))
	return result
