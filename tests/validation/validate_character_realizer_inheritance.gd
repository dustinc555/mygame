extends SceneTree

const TOWN_TEMPLATE := "res://features/settlements/bridge/settlement_town.tscn"
const FACILITY_SCENE := "res://scenes/test_levels/fixtures/generic_staffed_facility.tscn"
const CANYON_DEFINITION := "res://features/world_sim/resources/settlements/canyon.tres"
const CANYON_FACTION := "res://features/factions/resources/factions/canyonites.tres"
const QUADBOT_REALIZER := "res://features/world_sim/resources/population_appearance_profiles/quadbot.tres"
const STANDARD_CHARACTER_TYPES := "res://features/world_sim/resources/character_type_sets/standard.tres"
const GUARD_ROLE := "res://features/settlements/resources/roles/guard.tres"
const TOWN_TOOLS := "res://addons/world_authoring/town_tools.gd"
const FACILITY_DEFINITION_SCRIPT := "res://features/settlements/resources/facility_definition.gd"
const FACILITY_ROLE_SLOT_SCRIPT := "res://features/settlements/resources/facility_role_slot_definition.gd"
const POPULATION_CONTROLLER_SCRIPT := "res://features/world_sim/sim/population/population_controller.gd"
const FACTION_CONTROLLER_SCRIPT := "res://features/factions/sim/faction_controller.gd"
const CHARACTER_REALIZER_SCRIPT := "res://features/settlements/bridge/population_character_realizer.gd"
const FACTIONS_DIR := "res://features/factions/resources/factions"
const TEMP_TOWN := "user://character_realizer_add_facility_test.tscn"
const TEMP_FACILITY := "user://character_realizer_facility_test.tscn"

var _failures: Array[String] = []
var _population
var _factions
var _realizer


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var source_definition = load(CANYON_DEFINITION)
	var settlement_definition = source_definition.duplicate(true)
	var faction_definition = load(CANYON_FACTION)
	settlement_definition.set("faction_definition", faction_definition)
	settlement_definition.set("population_appearance_profile", null)
	var town := (load(TOWN_TEMPLATE) as PackedScene).instantiate()
	town.name = "RealizerTestTown"
	town.set("settlement_definition", settlement_definition)
	var packed := PackedScene.new()
	_expect(packed.pack(town) == OK and ResourceSaver.save(packed, TEMP_TOWN) == OK, "Could not create temporary town scene")
	town.free()

	var facility_template := (load(FACILITY_SCENE) as PackedScene).instantiate()
	var guard_slot = load(FACILITY_ROLE_SLOT_SCRIPT).new()
	guard_slot.slot_id = "guard"
	guard_slot.role = load(GUARD_ROLE)
	guard_slot.character_type_id = ""
	facility_template.role_slots.append(guard_slot)
	var packed_facility := PackedScene.new()
	_expect(packed_facility.pack(facility_template) == OK and ResourceSaver.save(packed_facility, TEMP_FACILITY) == OK, "Could not create temporary role-slotted facility scene")
	facility_template.free()

	var facility_definition = load(FACILITY_DEFINITION_SCRIPT).new()
	facility_definition.facility_id = "realizer_probe"
	facility_definition.display_name = "Realizer Probe"
	facility_definition.scene_path = TEMP_FACILITY
	var town_tools = load(TOWN_TOOLS)
	_expect(town_tools.add_facility_to_town_scene(TEMP_TOWN, facility_definition, Transform3D.IDENTITY), "Actual Add Facility scene path failed")

	var added_town := (ResourceLoader.load(TEMP_TOWN, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene).instantiate()
	var runtime_definition = added_town.get("settlement_definition")
	var facility = added_town.get_node_or_null("RealizerProbe")
	_expect(facility != null, "Add Facility did not create the generic facility")
	if facility == null:
		_finish(added_town)
		return
	_expect(facility.role_slots.size() == 1, "Add Facility did not preserve the facility scene role slot")
	_expect(facility.population_appearance_profile == null, "Generic facility should inherit its realizer")

	_population = load(POPULATION_CONTROLLER_SCRIPT).new()
	_factions = load(FACTION_CONTROLLER_SCRIPT).new()
	_factions.register_faction(faction_definition)
	_realizer = load(CHARACTER_REALIZER_SCRIPT).new()
	_realizer.set("_population", _population)
	_realizer.set("_factions", _factions)
	var faction_realizer = faction_definition.get_character_realizer()
	_expect(_realizer.resolve_effective_realizer(facility).get("profile_id") == "settler_common", "New facility did not inherit the faction realizer through its town")
	var faction_types = faction_definition.get_character_type_set()
	_expect(faction_types != null and faction_types.resource_path == STANDARD_CHARACTER_TYPES, "Faction has no authored Character Type Set")
	_expect(_realizer.resolve_effective_character_type_set(facility) == faction_types, "New facility did not inherit Character Types through town -> faction")
	var town_types = faction_types.duplicate(true)
	runtime_definition.character_type_set = town_types
	_expect(_realizer.resolve_effective_character_type_set(facility) == town_types, "Town Character Type override was not honored")
	runtime_definition.character_type_set = null
	var facility_types = faction_types.duplicate(true)
	facility.character_type_set = facility_types
	_expect(_realizer.resolve_effective_character_type_set(facility) == facility_types, "Facility Character Type override was not honored")
	facility.character_type_set = null

	var quadbot := load(QUADBOT_REALIZER) as Resource
	runtime_definition.population_appearance_profile = quadbot
	_expect(_realizer.resolve_effective_realizer(facility) == quadbot, "Town realizer override was not honored")
	runtime_definition.population_appearance_profile = null
	facility.population_appearance_profile = quadbot
	_expect(_realizer.resolve_effective_realizer(facility) == quadbot, "Facility realizer override was not honored")
	facility.population_appearance_profile = null

	var records = _population.ensure_generated_population("realizer_test", "census", 1, {
		"faction_id": faction_definition.get_id(),
		"squad_name": "Realizer Test",
		"population_appearance_profile": faction_realizer,
		"population_name_profile": faction_definition.get_population_name_profile(),
		"generation_seed": 41821,
		"character_type": faction_types.call("resolve_character_type", "", "resident"),
	})
	_expect(records.size() == 1, "Faction realizer did not create a complete population record")
	if records.is_empty():
		_finish(added_town)
		return
	var slots = facility.get_assignment_slot_specs()
	_expect(slots.size() == 1, "Generic facility did not expose its authored assignment slot")
	var authored_slot = facility.role_slots[0]
	_expect(authored_slot.character_type_id.is_empty(), "Guard slot must remain Auto rather than authoring a concrete Character Type")
	_expect(authored_slot.role.default_character_type_id == "default", "Auto guard slot did not inherit its type request from the role definition")
	var slot: Dictionary = slots[0] if not slots.is_empty() else {}
	_expect(str(slot.get("character_type_id", "")) == authored_slot.role.default_character_type_id, "Assignment slot did not derive its Auto type request from the role definition")
	var effective_slot_type = _realizer.resolve_effective_character_type_set(facility).call(
		"resolve_character_type",
		str(slot.get("character_type_id", "")),
		str(slot.get("role_id", ""))
	)
	_expect(effective_slot_type != null and str(effective_slot_type.get("type_id")) == "soldier", "Auto guard type did not resolve through the effective Character Type Set")
	var record: Dictionary = records[0]
	var actor_id := str(record.get("actor_id", ""))
	var original_skills: Dictionary = (record.get("skill_levels", {}) as Dictionary).duplicate(true)
	_population.update_actor_record(actor_id, {"role_id": "guard"})
	var actor = _realizer.realize_actor(actor_id, facility, facility.get_staff_root(), "Guard", str(slot.get("character_type_id", "")))
	_expect(actor != null, "Shared realizer rejected a valid inherited faction record")
	if actor != null:
		facility.configure_settlement_assignment_actor(actor, str(slot.get("slot_id", "")), slot)
		_expect(actor.get_script() == faction_realizer.get("actor_script"), "Runtime actor class differs from the editor-selected faction realizer")
		_expect(actor.get("appearance_data") != null, "Runtime actor has no appearance data")
		_expect(str(actor.get("member_name")) != "Character" and not str(actor.get("member_name")).strip_edges().is_empty(), "Runtime actor used the default Character name")
		_expect(str(actor.get_meta("population_character_realizer_id", "")) == "settler_common", "Runtime actor did not retain the effective realizer id")
		var equipment: Dictionary = _population.get_actor_record(str(record.get("actor_id", ""))).get("equipment_slots", {})
		_expect(equipment.has("chest") and equipment.has("legs") and equipment.has("feet"), "Runtime record is missing faction clothing")
		_expect(equipment.has("weapon") and equipment.has("offhand"), "Soldier Character Type did not issue its authored equipment")
		var typed_record: Dictionary = _population.get_actor_record(actor_id)
		_expect(str(typed_record.get("character_type_id", "")) == "soldier", "Guard slot did not resolve the authored Soldier type")
		_expect(typed_record.get("skill_levels", {}) == original_skills, "Promoting an existing person rerolled their skills")
		_expect(actor.get_node_or_null("BodyMesh") != null, "Runtime humanoid projection bootstrap is missing")
		var revised_realizer: Resource = faction_realizer.duplicate(true)
		revised_realizer.set("height_range", Vector2(0.8, 1.2))
		_population.ensure_record_character_realizer(actor_id, revised_realizer, faction_definition.get_population_name_profile())
		var revised_record: Dictionary = _population.get_actor_record(actor_id)
		_expect(revised_record.get("appearance", {}) == typed_record.get("appearance", {}), "Realizer authoring changes rerolled permanent appearance")
		_expect(revised_record.get("equipment_slots", {}) == typed_record.get("equipment_slots", {}), "Realizer authoring changes replaced permanent equipment")
		_population.ensure_record_character_realizer(actor_id, faction_realizer, faction_definition.get_population_name_profile())
		typed_record = _population.get_actor_record(actor_id)
		var permanent_snapshot := typed_record.duplicate(true)
		facility.get_staff_root().remove_child(actor)
		actor.free()
		_population.apply_serialized_state({"actor_records": {actor_id: permanent_snapshot}})
		var realized_again = _realizer.realize_actor(actor_id, facility, facility.get_staff_root(), "Guard", str(slot.get("character_type_id", "")))
		_expect(realized_again != null, "Ledger character did not re-realize after leaving town")
		if realized_again != null:
			var restored_record: Dictionary = _population.get_actor_record(actor_id)
			_expect(str(realized_again.get("member_name")) == str(permanent_snapshot.get("member_name")), "Re-realization changed the permanent character name")
			_expect(restored_record.get("appearance", {}) == permanent_snapshot.get("appearance", {}), "Re-realization changed the permanent character appearance")
			_expect(restored_record.get("skill_levels", {}) == permanent_snapshot.get("skill_levels", {}), "Re-realization changed permanent character skills")
			_expect(restored_record.get("equipment_slots", {}) == permanent_snapshot.get("equipment_slots", {}), "Re-realization changed permanent character equipment")
			_expect(restored_record.get("inventory_entries", []) == permanent_snapshot.get("inventory_entries", []), "Re-realization changed permanent character inventory")

	facility.population_appearance_profile = quadbot
	var nonhuman_records = _population.ensure_generated_population("realizer_test", "nonhuman_probe", 1, {
		"faction_id": faction_definition.get_id(),
		"squad_name": "Realizer Test",
		"population_appearance_profile": faction_realizer,
		"population_name_profile": faction_definition.get_population_name_profile(),
		"generation_seed": 41822,
	})
	_expect(nonhuman_records.size() == 1, "Could not create the non-human override probe record")
	if not nonhuman_records.is_empty():
		var nonhuman_record: Dictionary = nonhuman_records[0]
		var nonhuman_actor = _realizer.realize_actor(str(nonhuman_record.get("actor_id", "")), facility, facility.get_staff_root(), "NonhumanTester")
		_expect(nonhuman_actor != null, "Facility non-human realizer override did not create an actor")
		if nonhuman_actor != null:
			_expect(nonhuman_actor.get_script() == quadbot.get("actor_script"), "Facility override was replaced by a hardcoded humanoid")
			_expect(str(nonhuman_actor.get_meta("population_character_realizer_id", "")) == "quadbot", "Non-human actor did not retain the facility realizer id")
			_expect(str(nonhuman_actor.get("appearance_data").character_race.get("race_id")) == "quadbot", "Non-human actor received the wrong race appearance")
	facility.population_appearance_profile = null

	_validate_no_facility_factories()
	_validate_faction_realizers()
	_finish(added_town)


func _validate_no_facility_factories() -> void:
	for path in [
		"res://features/settlements/bridge/settlement_bar.gd",
		"res://features/settlements/bridge/settlement_jail.gd",
		"res://features/settlements/bridge/settlement_keep.gd",
		"res://features/settlements/bridge/settlement_town.gd",
		"res://features/settlements/bridge/settlement_population_spawner.gd",
	]:
		var source := FileAccess.get_file_as_string(path)
		_expect(not source.contains("CharacterBody3D.new()"), "%s directly constructs character bodies" % path)
		_expect(not source.contains("FACTION_HUMANOID_SCRIPT"), "%s contains a hardcoded humanoid fallback" % path)
		_expect(not source.contains("func _create_staff_actor") and not source.contains("func _create_guard_actor"), "%s retains a facility-local actor factory" % path)
		_expect(not source.contains("func _create_generated_staff_for_role") and not source.contains("func _ensure_staff_member"), "%s retains a generated staff factory" % path)
		_expect(not source.contains("func _add_basic_humanoid_children"), "%s still owns character projection bootstrap" % path)
		_expect(not source.contains("apply_to_actor"), "%s still applies appearance outside the shared realizer" % path)
		_expect(not source.contains("apply_guard_stat_tiers") and not source.contains("apply_civilian_stat_tiers"), "%s still hardcodes role stat tiers" % path)
		_expect(not source.contains("HATCHET_ITEM") and not source.contains("ROUND_SHIELD_ITEM"), "%s still hardcodes guard equipment" % path)
	var population_source := FileAccess.get_file_as_string(POPULATION_CONTROLLER_SCRIPT)
	_expect(not population_source.contains("else CHARACTER_APPEARANCE_DATA_SCRIPT.new()"), "Population generation retains a blank appearance fallback")


func _validate_faction_realizers() -> void:
	for file_name in DirAccess.get_files_at(FACTIONS_DIR):
		if not file_name.ends_with(".tres"):
			continue
		var faction = load("%s/%s" % [FACTIONS_DIR, file_name])
		var realizer = faction.call("get_character_realizer") if faction != null and faction.has_method("get_character_realizer") else null
		var type_set = faction.call("get_character_type_set") if faction != null and faction.has_method("get_character_type_set") else null
		_expect(realizer != null and realizer.get("actor_script") != null and not str(realizer.get("profile_id")).strip_edges().is_empty(), "%s has no complete Character Realizer" % file_name)
		_expect(type_set != null and type_set.has_method("resolve_character_type"), "%s has no complete Character Type Set" % file_name)
		_expect(faction.get("population_name_profile") != null, "%s has no population name profile" % file_name)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish(town: Node) -> void:
	if town != null:
		town.free()
	if _realizer != null:
		_realizer.free()
	if _factions != null:
		_factions.free()
	if _population != null:
		_population.free()
	if FileAccess.file_exists(TEMP_TOWN):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_TOWN))
	if FileAccess.file_exists(TEMP_FACILITY):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_FACILITY))
	if _failures.is_empty():
		print("CHARACTER_REALIZER_INHERITANCE_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("CHARACTER_REALIZER_INHERITANCE_FAILED count=%d" % _failures.size())
	quit(1)
