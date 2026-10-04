extends GutTest


func _equipment_for(race: CharacterRaceDefinition) -> EquipmentCapability:
	var actor := HumanoidCharacter.new()
	autofree(actor)
	actor.appearance_data = CharacterAppearanceData.new()
	actor.appearance_data.character_race = race
	var equipment := EquipmentCapability.new()
	equipment.setup(actor)
	return equipment


func _item(footprint: Vector2i, slot_name := "legs") -> ItemDefinition:
	var item := ItemDefinition.new()
	item.equip_slot = slot_name
	item.grid_size = footprint
	return item


func test_oversized_equipment_is_rejected_without_replacing_existing_gear() -> void:
	var race := CharacterRaceDefinition.new()
	race.equipment_slots = PackedStringArray(["legs"])
	race.equipment_slot_grid_sizes["legs"] = Vector2i(2, 3)
	var equipment := _equipment_for(race)
	var original := _item(Vector2i(2, 3))
	assert_true(equipment.can_equip_item_to_slot(original, "legs"))
	equipment.equip_item_to_slot(original, "legs", "original-pants")
	watch_signals(equipment)
	for footprint in [Vector2i(3, 2), Vector2i(1, 4), Vector2i(3, 4)]:
		var oversized := _item(footprint)
		assert_false(equipment.can_equip_item_to_slot(oversized, "legs"), str(footprint))
		assert_null(equipment.equip_item_to_slot(oversized, "legs", "oversized"))
		assert_same(equipment.get_equipped_item("legs"), original)
		assert_eq(equipment.get_equipped_stack_id("legs"), "original-pants")
	assert_signal_not_emitted(equipment, "equipment_changed")


func test_authored_slots_fit_current_trousers_underlayers_and_normal_weapons() -> void:
	var trousers: ItemDefinition = load("res://features/inventory/resources/items/traveler_trousers.tres")
	var underlayer: ItemDefinition = load("res://features/inventory/resources/items/knight_gambeson.tres")
	var sword: ItemDefinition = load("res://features/inventory/resources/items/steel_sword.tres")
	var spear: ItemDefinition = load("res://features/inventory/resources/items/spear.tres")
	var races: Array[CharacterRaceDefinition] = [
		CharacterRaceDefinition.new(),
		load("res://features/actors/resources/character_races/human.tres"),
		load("res://features/actors/resources/character_races/rustdead.tres"),
	]
	for race in races:
		assert_eq(race.get_slot_grid_size("legs"), Vector2i(2, 3))
		assert_eq(race.get_slot_grid_size("legs"), race.get_slot_grid_size("chest"))
		assert_eq(race.get_slot_grid_size("undershirt"), Vector2i(2, 3))
		assert_eq(race.get_slot_grid_size("weapon"), Vector2i(2, 5))
	var equipment := _equipment_for(races[1])
	for item in [trousers, underlayer, sword, spear]:
		assert_true(equipment.can_equip_item_to_slot(item, item.equip_slot), item.display_name)
		equipment.equip_item_to_slot(item, item.equip_slot)
		assert_same(equipment.get_equipped_item(item.equip_slot), item)


func test_equipment_capacity_uses_the_chosen_slot_and_live_race_override() -> void:
	var race := CharacterRaceDefinition.new()
	race.equipment_slots = PackedStringArray(["weapon", "offhand"])
	race.equipment_slot_grid_sizes["weapon"] = Vector2i(2, 4)
	race.equipment_slot_grid_sizes["offhand"] = Vector2i(1, 2)
	var equipment := _equipment_for(race)
	var item := _item(Vector2i(2, 3), "weapon")
	item.alternate_equip_slots = PackedStringArray(["offhand"])
	assert_true(equipment.can_equip_item_to_slot(item, "weapon"))
	assert_false(equipment.can_equip_item_to_slot(item, "offhand"))
	race.equipment_slot_grid_sizes["offhand"] = Vector2i(2, 3)
	assert_true(equipment.can_equip_item_to_slot(item, "offhand"))
	assert_false(equipment.can_equip_item_to_slot(item, "legs"))


func test_invalid_item_footprint_cannot_bypass_equipment_capacity() -> void:
	var race := CharacterRaceDefinition.new()
	race.equipment_slots = PackedStringArray(["legs"])
	var equipment := _equipment_for(race)
	for footprint in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 2)]:
		assert_false(equipment.can_equip_item_to_slot(_item(footprint), "legs"), str(footprint))
