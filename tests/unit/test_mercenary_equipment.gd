extends GutTest

const TYPES = preload("res://features/world_sim/resources/character_type_sets/standard.tres")
const ROLE = preload("res://features/settlements/resources/roles/mercenary.tres")
const HATCHET = preload("res://features/inventory/resources/items/hatchet.tres")
const SHIELD = preload("res://features/inventory/resources/items/round_shield.tres")
const SWORD = preload("res://features/inventory/resources/items/iron_sword.tres")
const ARMOR = preload("res://features/inventory/resources/items/ranger_jerkin.tres")
const ACTOR_ID := "unit.mercenary"

class EquipmentTestHumanoid extends HumanoidCharacter:
	# Exercise real actor equipment without loading unrelated animation/model caches.
	func _setup_body_projection() -> void:
		pass

func _population(slots: Dictionary = {}) -> PopulationController:
	var population := PopulationController.new()
	autofree(population)
	population.actor_records[ACTOR_ID] = {
		"actor_id": ACTOR_ID,
		"role_id": ROLE.get_id(),
		"birth_day_index": -9000,
		"equipment_slots": slots.duplicate(true),
		"inventory_entries": [],
	}
	return population

func _mercenary_type() -> Resource:
	return TYPES.resolve_character_type(ROLE.default_character_type_id, ROLE.get_id())

func test_default_mercenary_receives_weapon_and_shield_without_changing_role() -> void:
	var population := _population()
	var record := population.ensure_record_character_type(ACTOR_ID, _mercenary_type())
	assert_eq(record.equipment_slots.get("weapon", ""), HATCHET.resource_path)
	assert_eq(record.equipment_slots.get("offhand", ""), SHIELD.resource_path)
	assert_eq(record.role_id, "mercenary", "Equipment type must not turn private staff into town guards")

func test_issuing_mercenary_loadout_preserves_existing_weapon_and_armor() -> void:
	var population := _population({"weapon": SWORD.resource_path, "chest": ARMOR.resource_path})
	var record := population.ensure_record_character_type(ACTOR_ID, _mercenary_type())
	assert_eq(record.equipment_slots.get("weapon"), SWORD.resource_path)
	assert_eq(record.equipment_slots.get("chest"), ARMOR.resource_path)
	assert_eq(record.equipment_slots.get("offhand", ""), SHIELD.resource_path)

func test_reapplying_type_does_not_replace_removed_gear_or_duplicate_supplies() -> void:
	var population := _population()
	var record := population.ensure_record_character_type(ACTOR_ID, _mercenary_type())
	var supplies: Array = record.inventory_entries.duplicate(true)
	record.equipment_slots.erase("weapon")
	population.actor_records[ACTOR_ID] = record
	var restored := population.ensure_record_character_type(ACTOR_ID, _mercenary_type())
	assert_false(restored.equipment_slots.has("weapon"))
	assert_eq(restored.inventory_entries, supplies)

func test_explicit_type_override_and_civilian_defaults_remain_unchanged() -> void:
	assert_eq(TYPES.resolve_character_type("civilian", ROLE.get_id()).get_id(), "civilian")
	assert_eq(TYPES.resolve_character_type("default", "merchant").get_id(), "civilian")
	assert_eq(TYPES.resolve_character_type("default", "guard").get_id(), "soldier")

func test_mercenary_actor_equips_starting_weapons_and_accepts_armor() -> void:
	var previous_context := BootstrapContext.active
	var host := Node3D.new()
	add_child_autofree(host)
	BootstrapContext.active = BootstrapContext.new(host)
	var actor := EquipmentTestHumanoid.new()
	actor.stable_id = ACTOR_ID
	actor.starting_equipment.assign(_mercenary_type().starting_equipment)
	var realizer := PopulationCharacterRealizer.new()
	autofree(realizer)
	realizer._ensure_projection_bootstrap(actor)
	host.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	assert_eq(actor.get_equipped_item("weapon"), HATCHET)
	assert_eq(actor.get_equipped_item("offhand"), SHIELD)
	actor.get_equipment().equip_item_to_slot(ARMOR, "chest")
	assert_eq(actor.get_equipped_item("chest"), ARMOR)
	assert_eq(actor.get_equipped_item("weapon"), HATCHET, "Armor must not displace the weapon")
	actor.free()
	BootstrapContext.active = previous_context
