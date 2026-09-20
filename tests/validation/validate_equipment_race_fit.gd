extends SceneTree
var failures: Array[String] = []
class Wearer extends Node:
	var appearance_data := CharacterAppearanceData.new()
	var starting_equipment: Array = []
	var inventory := InventoryData.new()
	func get_equipment_slot_names() -> Array[String]: return ["head", "chest", "weapon"]
func _initialize() -> void:
	var wearer := Wearer.new()
	var race := CharacterRaceDefinition.new()
	race.race_id = "human"
	wearer.appearance_data.character_race = race
	var equipment := EquipmentCapability.new()
	equipment.setup(wearer)
	var helmet := ItemDefinition.new()
	helmet.equip_slot = "head"
	helmet.set("compatible_races", PackedStringArray(["skeleton"]))
	_check(not equipment.can_equip_item_to_slot(helmet, "head"), "human cannot equip skeleton armor")
	race.race_id = "skeleton"
	_check(equipment.can_equip_item_to_slot(helmet, "head"), "skeleton can equip skeleton armor")
	equipment.equip_item_to_slot(helmet, "head")
	_check(equipment.get_equipped_item("head") == helmet, "compatible item equips")
	race.race_id = "human"
	equipment.unequip_item_from_slot("head")
	_check(wearer.inventory.add_item(helmet), "race restriction does not prevent carrying loot")
	var sword := ItemDefinition.new()
	sword.equip_slot = "weapon"
	_check(equipment.can_equip_item_to_slot(sword, "weapon"), "unrestricted legacy weapon is unchanged")
	equipment.teardown()
	wearer.free()
	for failure in failures: push_error(failure)
	print("EQUIPMENT_RACE_FIT_OK" if failures.is_empty() else "EQUIPMENT_RACE_FIT_FAILED")
	quit(0 if failures.is_empty() else 1)
func _check(value: bool, message: String) -> void:
	if not value: failures.append(message)
