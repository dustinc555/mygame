extends GutTest

const ITEM_PATH := "res://features/inventory/resources/items/medium_leather_bag.tres"

class FixtureActor extends HumanoidCharacter:
	func _ready() -> void:
		pass

func test_backpack_uses_one_source_for_humans_and_puglins() -> void:
	assert_true(ResourceLoader.exists(ITEM_PATH), "The wearable backpack must be a real catalog item")
	if not ResourceLoader.exists(ITEM_PATH): return
	var item: ItemDefinition = load(ITEM_PATH)
	var source: PackedScene
	for id: String in ["human_male", "human_female", "puglin", "desert_puglin"]:
		var body: Resource = load("res://features/actors/resources/character_body_archetypes/" + id + ".tres")
		var visual: Resource = item.get_equipment_visual_for_body_archetype(body)
		assert_not_null(visual, id)
		if visual == null: continue
		if source == null: source = visual.visual_scene
		assert_same(visual.visual_scene, source, "All bodies use the same maintained backpack")
		assert_true(item.fits_race(body.get_race_id()))
		var race: Resource = load("res://features/actors/resources/character_races/" + body.get_race_id() + ".tres")
		assert_true(race.equipment_slots.has("backpack"), id + " permits backpack equipment")
	assert_eq(item.equip_slot, "backpack")
	assert_true(item.stat_modifiers.is_empty(), "The visual pass must not grant carrying capacity")

func test_equipping_depends_on_humanoid_body_not_race_name_or_cargo_slot() -> void:
	var item: ItemDefinition = load(ITEM_PATH)
	assert_eq(item.display_name, "Medium Leather Bag")
	assert_true(item.compatible_races.is_empty(), "No race-name whitelist")
	for race_id: String in ["human", "rustdead", "puglin", "desert_puglin", "quadbot", "new_humanoid"]:
		var actor := FixtureActor.new()
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		actor.appearance_data = CharacterAppearanceData.new()
		var race: CharacterRaceDefinition
		var body: CharacterBodyArchetypeDefinition
		if race_id == "new_humanoid":
			race = CharacterRaceDefinition.new()
			race.race_id = race_id
			race.equipment_slots = PackedStringArray(["backpack"])
			body = CharacterBodyArchetypeDefinition.new()
			body.visual_body_type = CharacterBodyArchetypeDefinition.VISUAL_BODY_TYPE_MALE
		else:
			race = load("res://features/actors/resources/character_races/%s.tres" % race_id)
			body = race.default_male_archetype
		actor.appearance_data.character_race = race
		actor.appearance_data.body_archetype = body
		add_child_autofree(actor)
		var equipment := EquipmentCapability.new()
		equipment.setup(actor)
		actor.add_capability(equipment)
		assert_eq(equipment.can_equip_item_to_slot(item, "backpack"), race_id != "quadbot", race_id)
		assert_eq(item.get_equipment_visual_for_body_archetype(body) != null, race_id != "quadbot", race_id + " visible fit")
