extends SceneTree

## Validates current catalogs and People dock commands with controlled records.
## Does not freeze named-character design, prove native UndoRedo, or run staff AI.

const FACILITIES_DIR := "res://features/settlements/resources/facilities"
const ROLES_DIR := "res://features/settlements/resources/roles"
const CHARACTERS_DIR := "res://features/actors/resources/characters"
const CHARACTER_SCRIPT := "res://features/world_sim/resources/character_record_definition.gd"
const ROLE_SCRIPT := "res://features/settlements/resources/facility_role_definition.gd"
const ROLE_SLOT_SCRIPT := "res://features/settlements/resources/facility_role_slot_definition.gd"
const DOCK_PATH := "res://addons/world_authoring/facility_dock.gd"

class PeopleFixture extends Node:
	var role_slots: Array = []

# Captures the dock command only; does not impersonate EditorUndoRedoManager.
class EditCapture extends RefCounted:
	var submitted: Array = []
	func set_facility_role_slots(_facility: Node, slots: Variant, _action: String) -> void:
		submitted = slots

var _failures: Array[String] = []
var _roles_by_path := {}
var _characters_by_path := {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_role_catalog()
	_validate_character_catalog()
	_validate_character_record(_character_fixture("validation.record", "Fixture Person"), "test-owned record")
	_validate_facility_templates()
	_validate_people_dock()
	_validate_people_edit_commands()
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
		_validate_character_record(character, path)
		ids[actor_id] = path
		_characters_by_path[path] = character
	_expect(not _characters_by_path.is_empty(), "Character catalog is empty")


func _validate_character_record(character: Resource, label: String) -> void:
	_expect(character.has_method("to_record"), "Character must expose record conversion: %s" % label)
	if not character.has_method("to_record"):
		return
	var record_value: Variant = character.call("to_record")
	_expect(record_value is Dictionary, "Character conversion must produce a record: %s" % label)
	if not (record_value is Dictionary):
		return
	var record: Dictionary = record_value
	_expect(record.get("actor_id") == str(character.get("actor_id")).strip_edges(), "Character conversion must preserve authored actor ID: %s" % label)
	_expect(record.get("member_name") == character.get("member_name"), "Character conversion must preserve authored name: %s" % label)
	# Preserve authored data without prescribing particular design values.
	for property_name in ["available_for_work", "appearance", "skill_levels", "equipment_slots", "inventory_entries", "traits", "personality"]:
		_expect(record.get(property_name) == character.get(property_name), "Character conversion must preserve %s: %s" % [property_name, label])


func _character_fixture(actor_id: String, member_name: String) -> Resource:
	var character := load(CHARACTER_SCRIPT).new() as Resource
	character.set("actor_id", actor_id)
	character.set("member_name", member_name)
	return character


func _role_fixture(role_id: String, display_name: String) -> Resource:
	var role := load(ROLE_SCRIPT).new() as Resource
	role.set("role_id", role_id)
	role.set("display_name", display_name)
	return role


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


func _validate_people_dock() -> void:
	var dock_script := load(DOCK_PATH) as Script
	var dock = dock_script.new() if dock_script != null else null
	_expect(dock != null, "People dock must construct")
	if dock == null:
		return
	for method in ["setup", "_role_catalog", "_character_catalog", "_character_matches_search", "_populate_character_list"]:
		_expect(dock.has_method(method), "People dock must expose current authoring operation: %s" % method)
		if not dock.has_method(method):
			dock.free()
			return
	dock.setup(RefCounted.new())
	var people_box := dock.get("_people_box") as VBoxContainer
	_expect(people_box != null and dock.is_ancestor_of(people_box), "People controls must belong to the constructed dock")
	# Discovery is checked against actual resources, not source-code spellings.
	_validate_dock_catalog(dock._role_catalog(), _roles_by_path, "roles")
	_validate_dock_catalog(dock._character_catalog(), _characters_by_path, "characters")
	_validate_character_search(dock)
	dock.free()


func _validate_dock_catalog(catalog: Array[Resource], expected: Dictionary, label: String) -> void:
	_expect(catalog.size() == expected.size(), "People dock must discover every registered %s resource" % label)
	var seen := {}
	for resource in catalog:
		_expect(resource != null, "People dock catalog must not contain null: %s" % label)
		if resource == null:
			continue
		_expect(expected.has(resource.resource_path), "People dock catalog must retain registered resource paths: %s" % label)
		_expect(not seen.has(resource.resource_path), "People dock catalog must not duplicate resources: %s" % label)
		seen[resource.resource_path] = true


func _validate_character_search(dock: Control) -> void:
	var first := _character_fixture("validation.actor_one", "Cinder Quinn")
	var second := _character_fixture("validation.actor_two", "Stone Vale")
	var third := _character_fixture("validation.actor_three", "Cinder Vale")
	var characters: Array[Resource] = [first, second, third]
	var character_list := ItemList.new()
	# Names differ from IDs; a shared name must not be mistaken for one result.
	for sample in [
		{"query": "cInDeR", "matches": [first, third], "current": third},
		{"query": " ACTOR_TWO ", "matches": [second], "current": second},
		{"query": "not_a_match", "matches": [], "current": null},
		{"query": " ", "matches": [first, second, third], "current": null},
	]:
		dock.call("_populate_character_list", character_list, characters, sample.query, sample.current)
		var expected: Array = sample.matches
		_expect(character_list.item_count == expected.size() + 1, "Character search must return only the matching fixture records: %s" % sample.query)
		if character_list.item_count != expected.size() + 1:
			continue
		_expect(character_list.get_item_text(0) == "Auto Generate" and character_list.get_item_metadata(0) == null, "Generated-character option must be explicit and hold no named character")
		var selected_index := 0
		for index in range(expected.size()):
			var character: Resource = expected[index]
			_expect(character_list.get_item_metadata(index + 1) == character, "Character picker must retain the matching resource reference: %s" % sample.query)
			var text := character_list.get_item_text(index + 1)
			_expect(text.contains(character.get("member_name")) and text.contains(character.get("actor_id")), "Character picker must display both authored name and actor ID")
			if character == sample.current:
				selected_index = index + 1
		_expect(character_list.get_selected_items() == PackedInt32Array([selected_index]), "Character picker must preserve the current selection or select Auto Generate")
	character_list.free()


func _validate_people_edit_commands() -> void:
	var dock = load(DOCK_PATH).new()
	var capture := EditCapture.new()
	dock.setup(capture)
	var fixture := PeopleFixture.new()
	var slot = load(ROLE_SLOT_SCRIPT).new()
	slot.slot_id = "saved.identity"
	slot.role = _role_fixture("validation.original_role", "Original Role")
	var character := _character_fixture("validation.row_actor", "Row Person")
	slot.named_character = character
	slot.display_name = "Original"
	fixture.role_slots = [slot]
	dock.set("_facility", fixture)
	dock.call("_set_person_value", 0, "display_name", "Edited")
	_expect(capture.submitted.size() == 1, "People callback submits exactly one edited slot")
	if capture.submitted.size() == 1:
		var edited: Resource = capture.submitted[0]
		_expect(edited != slot and slot.display_name == "Original", "Editing a People row must not mutate the saved slot before commit")
		_expect(edited.get("display_name") == "Edited" and edited.get("slot_id") == "saved.identity", "People edit must change requested value without changing durable slot ID")
		_expect(edited.get("named_character").get("actor_id") == character.get("actor_id"), "Nested named-character identity survives row copy")
		var before_role: Resource = edited.get("role")
		var replacement_role := _role_fixture("validation.replacement_role", "Replacement Role")
		dock.call("_set_person_value", 0, "role", replacement_role)
		_expect(capture.submitted[0].get("role") == replacement_role and slot.role != replacement_role and edited.get("role") == before_role, "Changing the nested role reference must not mutate the original or earlier submitted slot")
		dock.call("_add_person")
		fixture.role_slots = capture.submitted
		dock.call("_add_person")
		var ids := {}
		for created in capture.submitted:
			var id := str(created.get("slot_id"))
			_expect(not id.is_empty() and not ids.has(id), "Add Person must preserve existing and create unique nonblank slot identities")
			ids[id] = true
		_expect(ids.has("saved.identity") and capture.submitted.size() == 3, "Repeated Add Person retains original identity and both new rows")
	var missing_role := _role_fixture("missing_validation_role", "Missing Role")
	slot.role = missing_role
	var row: Control = dock._person_row(0, slot, [] as Array[Resource], [] as Array[Resource], {}, {}, {})
	var picker := row.get_child(0).get_child(0) as OptionButton
	_expect(picker != null and picker.get_item_text(picker.selected).begins_with("Missing:") and picker.get_item_metadata(picker.selected) == missing_role, "Unknown saved role remains visible and retained instead of silently replaced")
	var character_button := row.get_child(0).get_child(1) as Button
	_expect(character_button != null and character_button.text.begins_with("Missing:") and slot.named_character == character, "Unknown saved character remains visible without replacing the saved reference")
	row.free()
	dock.free()
	fixture.free()


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
