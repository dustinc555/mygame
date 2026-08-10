extends SceneTree

const FACILITIES_DIR := "res://features/settlements/resources/facilities"
const ROLES_DIR := "res://features/settlements/resources/roles"
const CHARACTERS_DIR := "res://features/actors/resources/characters"
const ADA_PATH := "res://features/actors/resources/characters/ada.tres"
const DOCK_PATH := "res://addons/world_authoring/facility_dock.gd"
const TOOLS_PATH := "res://addons/world_authoring/facility_tools.gd"

var _failures: Array[String] = []
var _roles_by_path := {}
var _characters_by_path := {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_role_catalog()
	_validate_character_catalog()
	_validate_ada_record()
	_validate_facility_templates()
	_validate_plugin_contract()
	_finish()


func _validate_role_catalog() -> void:
	var ids := {}
	for path in _resource_paths(ROLES_DIR):
		var role := load(path) as Resource
		_expect(role != null, "Role failed to load: %s" % path)
		if role == null:
			continue
		var role_id := str(role.get("role_id")).strip_edges().to_lower()
		_expect(not role_id.is_empty(), "Role has no role_id: %s" % path)
		_expect(not ids.has(role_id), "Duplicate role_id: %s" % role_id)
		_expect(not str(role.get("display_name")).strip_edges().is_empty(), "Role has no display_name: %s" % path)
		_expect(not str(role.get("default_character_type_id")).strip_edges().is_empty(), "Role has no Auto character type: %s" % path)
		ids[role_id] = path
		_roles_by_path[path] = role
	_expect(not _roles_by_path.is_empty(), "Role catalog is empty")


func _validate_character_catalog() -> void:
	var ids := {}
	for path in _resource_paths(CHARACTERS_DIR):
		var character := load(path) as Resource
		_expect(character != null, "Character failed to load: %s" % path)
		if character == null:
			continue
		var actor_id := str(character.get("actor_id")).strip_edges()
		_expect(not actor_id.is_empty(), "Character has no actor_id: %s" % path)
		_expect(not ids.has(actor_id), "Duplicate character actor_id: %s" % actor_id)
		_expect(not str(character.get("member_name")).strip_edges().is_empty(), "Character has no member_name: %s" % path)
		ids[actor_id] = path
		_characters_by_path[path] = character
	_expect(not _characters_by_path.is_empty(), "Character catalog is empty")


func _validate_ada_record() -> void:
	var ada := load(ADA_PATH) as Resource
	_expect(ada != null, "Ada permanent character record is missing")
	if ada == null or not ada.has_method("to_record"):
		return
	var record: Dictionary = ada.call("to_record")
	var appearance: Dictionary = record.get("appearance", {})
	var skills: Dictionary = record.get("skill_levels", {})
	var equipment: Dictionary = record.get("equipment_slots", {})
	var inventory: Array = record.get("inventory_entries", [])
	_expect(str(record.get("actor_id", "")) == "ada" and str(record.get("member_name", "")) == "Ada", "Ada must have stable authored identity")
	_expect(str(appearance.get("body_archetype", "")).ends_with("human_female.tres") and int(appearance.get("visual_body_type", 0)) == 3, "Ada must use the female body record")
	_expect(is_equal_approx(float(skills.get("labor.farming", 0.0)), 55.0), "Ada Farming must be 55")
	for combat_skill in ["combat.axes_one_handed", "combat.daggers", "combat.shields", "combat.swords_one_handed", "combat.unarmed"]:
		_expect(float(skills.get(combat_skill, 999.0)) <= 20.0, "Ada combat skill must remain weak: %s" % combat_skill)
	_expect(equipment.has("chest") and equipment.has("legs") and equipment.has("feet"), "Ada must start clothed")
	var has_hoe := false
	var has_full_can := false
	for entry_value in inventory:
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		var item_id := str(entry.get("item_id", ""))
		if item_id.ends_with("hoe.tres"):
			has_hoe = true
		elif item_id.ends_with("watering_can.tres"):
			has_full_can = is_equal_approx(float((entry.get("metadata", {}) as Dictionary).get("farm_water", 0.0)), 16.0)
	_expect(has_hoe, "Ada must start with a Hoe")
	_expect(has_full_can, "Ada must start with a full Watering Can")


func _validate_facility_templates() -> void:
	for definition_path in _resource_paths(FACILITIES_DIR):
		var definition := load(definition_path) as Resource
		_expect(definition != null, "Facility definition failed to load: %s" % definition_path)
		if definition == null:
			continue
		var scene_path := str(definition.get("scene_path"))
		var scene := load(scene_path) as PackedScene
		_expect(scene != null, "Facility template failed to load: %s" % scene_path)
		if scene == null:
			continue
		var facility := scene.instantiate()
		_expect(_has_property(facility, "role_slots"), "Facility template has no role_slots: %s" % scene_path)
		if _has_property(facility, "role_slots"):
			_validate_slots(scene_path, facility.get("role_slots"))
		facility.free()


func _validate_slots(scene_path: String, slots: Array) -> void:
	var slot_ids := {}
	var assignments := {}
	for slot in slots:
		_expect(slot != null, "%s has a null role slot" % scene_path)
		if slot == null:
			continue
		var slot_id := str(slot.get("slot_id")).strip_edges()
		_expect(not slot_id.is_empty(), "%s has a role slot without slot_id" % scene_path)
		_expect(not slot_ids.has(slot_id), "%s has duplicate slot_id %s" % [scene_path, slot_id])
		slot_ids[slot_id] = true
		var role := slot.get("role") as Resource
		_expect(role != null, "%s slot %s has no role" % [scene_path, slot_id])
		if role != null:
			_expect(_roles_by_path.has(role.resource_path), "%s slot %s uses an unregistered role" % [scene_path, slot_id])
		var character := slot.get("named_character") as Resource
		if character == null:
			continue
		_expect(_characters_by_path.has(character.resource_path), "%s slot %s uses an unregistered character" % [scene_path, slot_id])
		var group := str(role.get("assignment_exclusivity_group")) if role != null else ""
		var key := "%s|%s" % [str(character.get("actor_id")), group]
		_expect(not assignments.has(key), "%s assigns named actor %s to incompatible rows" % [scene_path, character.get("actor_id")])
		assignments[key] = true


func _validate_plugin_contract() -> void:
	var dock := FileAccess.get_file_as_string(DOCK_PATH)
	var tools := FileAccess.get_file_as_string(TOOLS_PATH)
	for obsolete in ["_rebuild_staffing", "_staff_toggle_field", "_staff_count_field", "_appearance_profile_picker", "_character_type_set_picker", "_character_type_field", "has_barkeeper", "waiter_count", "guard_count", "staff_character_type_ids"]:
		_expect(not dock.contains(obsolete), "Facility dock retains obsolete staffing symbol: %s" % obsolete)
	_expect(dock.contains("ROLES_DIR") and dock.contains("CHARACTERS_DIR"), "Facility dock must discover role and character catalogs")
	_expect(dock.contains("_tabs = TabContainer.new()"), "General, Furniture, and People must be separated into dedicated tabs")
	_expect(dock.contains("PopupPanel.new()") and dock.contains("LineEdit.new()") and dock.contains("ItemList.new()"), "Character picker must be a searchable plain list popup")
	_expect(dock.contains("Auto Generate"), "Character picker must label generated characters explicitly")
	_expect(not dock.contains("character_option.add_item(\"Auto\")"), "Character picker must not remain a radio-style OptionButton list")
	var dock_script := load(DOCK_PATH) as Script
	var dock_instance = dock_script.new() if dock_script != null else null
	_expect(dock_instance != null and dock_instance.has_method("_character_matches_search"), "Character picker must expose testable name/actor-ID filtering")
	if dock_instance != null and dock_instance.has_method("_character_matches_search"):
		dock_instance.call("setup", RefCounted.new())
		var content := dock_instance.get("_content") as VBoxContainer
		var tabs := dock_instance.get("_tabs") as TabContainer
		var top_row := dock_instance.get("_top_row") as HBoxContainer
		var people_box := dock_instance.get("_people_box") as VBoxContainer
		var people_scroll := people_box.get_parent() as ScrollContainer if people_box != null else null
		var people_tab := people_scroll.get_parent() as VBoxContainer if people_scroll != null else null
		_expect(content != null and tabs != null and tabs.get_parent() == content and content.get_child_count() == 1, "Tabs must be the single facility workspace")
		_expect(tabs != null and tabs.get_child_count() == 3 and tabs.get_child(0).name == "General" and tabs.get_child(1).name == "Furniture" and tabs.get_child(2).name == "People", "Facility workspace must expose General, Furniture, and People tabs")
		_expect(top_row != null and top_row.get_parent() == tabs and top_row.get_child_count() == 2, "General must never exceed two side-by-side columns")
		_expect(people_tab != null and people_tab.name == "People" and people_tab.get_parent() == tabs, "People must occupy a dedicated full-height tab")
		_expect(people_scroll != null and people_scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "People must not have horizontal scrolling")
		_expect(dock_instance.custom_minimum_size.y >= 460.0, "Facility workspace must retain a usable minimum height")
		var ada := load(ADA_PATH) as Resource
		_expect(ada != null and bool(dock_instance.call("_character_matches_search", ada, "ADA")), "Character search must match names case-insensitively")
		_expect(ada != null and bool(dock_instance.call("_character_matches_search", ada, "ada")), "Character search must match actor IDs case-insensitively")
		var character_list := ItemList.new()
		var character_resources: Array[Resource] = []
		for character_value in _characters_by_path.values():
			character_resources.append(character_value as Resource)
		dock_instance.call("_populate_character_list", character_list, character_resources, "ada", null)
		_expect(character_list.item_count == 2, "Searching Ada must return Auto Generate and exactly Ada")
		if character_list.item_count == 2:
			_expect(character_list.get_item_text(0) == "Auto Generate", "Generated-character option must be first and explicit")
			_expect(character_list.get_item_text(1) == "Ada (ada)", "Ada must be visible by name and actor ID")
		character_list.free()
	if dock_instance != null:
		dock_instance.free()
	_expect(dock.contains("Missing: %s"), "Facility dock must preserve invalid saved values visibly")
	_expect(dock.contains("Time.get_ticks_usec()") and dock.contains("func _new_slot_id"), "Add Person must create a stable local slot ID")
	_expect(tools.contains("func set_facility_role_slots") and tools.contains("role_slots.duplicate(true)"), "People edits must deep-copy through UndoRedo")


func _resource_paths(directory: String) -> Array[String]:
	var paths: Array[String] = []
	_collect_resource_paths(directory, paths)
	paths.sort()
	return paths


func _collect_resource_paths(directory: String, paths: Array[String]) -> void:
	if DirAccess.open(directory) == null:
		return
	for file_name in DirAccess.get_files_at(directory):
		if file_name.get_extension() == "tres":
			paths.append(directory.path_join(file_name))
	for child in DirAccess.get_directories_at(directory):
		_collect_resource_paths(directory.path_join(child), paths)


func _has_property(target: Object, property_name: String) -> bool:
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("FACILITY_PEOPLE_AUTHORING_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("FACILITY_PEOPLE_AUTHORING_FAILED count=%d" % _failures.size())
	quit(1)
