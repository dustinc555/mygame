extends GutTest

const DEFINITION = preload("res://features/world_sim/resources/character_record_definition.gd")
const RECORD = preload("res://features/world_sim/sim/population/c_game_population_record.gd")


func test_authored_backstory_survives_resource_and_population_save() -> void:
	var definition := DEFINITION.new()
	definition.actor_id = "story_fixture"
	var fields := definition.get_property_list().map(func(p): return str(p.name))
	assert_has(fields, "backstory", "Characters need an editable saved Backstory")
	if not fields.has("backstory"):
		return
	var story := "He repaired the pump.\nThen he took its regulator back."
	definition.set("backstory", story)
	var source_path := "user://character_backstory_fixture.tres"
	assert_eq(ResourceSaver.save(definition, source_path), OK)
	var restored = ResourceLoader.load(source_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_eq(restored.get("backstory"), story)
	var component := RECORD.new()
	component.apply_record(restored.to_record())
	assert_eq(component.to_record().get("backstory", ""), story)
	var save_path := "user://population_backstory_fixture.tres"
	assert_eq(ResourceSaver.save(component, save_path), OK)
	var loaded = ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_eq(loaded.to_record().get("backstory", ""), story)
	DirAccess.remove_absolute(source_path)
	DirAccess.remove_absolute(save_path)


func test_older_characters_default_to_empty_backstory() -> void:
	var component := RECORD.new()
	component.apply_record({"actor_id": "legacy"})
	assert_eq(component.to_record().get("backstory", "missing"), "")


func test_tavin_is_a_saved_male_mechanic_with_his_history() -> void:
	var path := "res://features/actors/resources/characters/tavin_rook.tres"
	assert_true(ResourceLoader.exists(path), "Tavin must exist in the named-character catalog")
	if not ResourceLoader.exists(path):
		return
	var definition = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var record: Dictionary = definition.to_record()
	assert_eq(record.actor_id, "tavin_rook")
	assert_eq(record.member_name, "Tavin Rook")
	assert_eq(record.appearance.body_archetype, "res://features/actors/resources/character_body_archetypes/human_male.tres")
	assert_eq(int(record.appearance.visual_body_type), 2)
	assert_true(record.backstory.contains("regulator"))
	assert_true(record.backstory.contains("households"))
	assert_false(record.available_for_work)
	assert_gt(record.skill_levels["craft.blacksmithing"], record.skill_levels["combat.unarmed"])
	assert_gt(record.skill_levels["labor.scavenging"], record.skill_levels["combat.unarmed"])
	var reference: Dictionary = load("res://features/actors/resources/characters/tomas.tres").skill_levels
	for skill_id in reference:
		assert_has(record.skill_levels, skill_id)
	for item_path in record.equipment_slots.values():
		assert_true(ResourceLoader.exists(item_path), "Equipment must reference a real item")
