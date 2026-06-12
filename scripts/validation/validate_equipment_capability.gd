extends SceneTree

const WORLD_ACTOR_SCRIPT = preload("res://scripts/actors/world_actor.gd")
const HATCHET = preload("res://resources/items/hatchet.tres")
const BRONZE_SWORD = preload("res://resources/items/bronze_sword.tres")
const ROUND_SHIELD = preload("res://resources/items/round_shield.tres")
const BREAD = preload("res://resources/items/bread.tres")

var _failures: Array[String] = []
var _inventory_changed_count := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	_validate_equipment_capability_registration()
	_validate_starting_equipment_seed()
	_validate_equip_replace_and_unequip()
	_validate_equipment_stat_modifiers()
	_validate_equipment_change_batch_signal()
	if _failures.is_empty():
		print("EQUIPMENT_CAPABILITY_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("EQUIPMENT_CAPABILITY_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_equipment_capability_registration() -> void:
	var actor := _make_actor()
	var capability = actor.get_actor_capability(&"equipment")
	if capability == null:
		_fail("Expected WorldActor to register EquipmentCapability")
	elif not capability.has_method("initialize_from_actor"):
		_fail("Expected EquipmentCapability to expose initialize_from_actor")
	actor.free()


func _validate_starting_equipment_seed() -> void:
	var actor := _make_actor(false)
	actor.starting_equipment = [HATCHET, BREAD]
	actor.call("_setup_inventory_capability")
	actor.call("_setup_equipment_capability")
	if actor.get_equipped_item(ItemDefinition.EQUIP_SLOT_WEAPON) != HATCHET:
		_fail("Expected starting hatchet to equip to weapon slot")
	if actor.equipped_items.get(ItemDefinition.EQUIP_SLOT_WEAPON) != HATCHET:
		_fail("Expected actor-owned equipped_items to mirror starting equipment")
	if actor.inventory == null or actor.inventory.count_item(BREAD) != 1:
		_fail("Expected non-equippable starting equipment to seed inventory")
	actor.free()


func _validate_equip_replace_and_unequip() -> void:
	var actor := _make_actor()
	if not actor.can_equip_item_to_slot(HATCHET, ItemDefinition.EQUIP_SLOT_WEAPON):
		_fail("Expected hatchet to be valid for weapon slot")
	if actor.can_equip_item_to_slot(BREAD, ItemDefinition.EQUIP_SLOT_WEAPON):
		_fail("Expected non-equippable bread to be rejected")
	if actor.can_equip_item_to_slot(HATCHET, ItemDefinition.EQUIP_SLOT_OFFHAND):
		_fail("Expected hatchet to be rejected from offhand slot")
	if actor.equip_item_to_slot(HATCHET, ItemDefinition.EQUIP_SLOT_WEAPON) != null:
		_fail("Expected first equip to have no replacement")
	if actor.equip_item_to_slot(BRONZE_SWORD, ItemDefinition.EQUIP_SLOT_WEAPON) != HATCHET:
		_fail("Expected sword equip to replace hatchet")
	if actor.get_equipped_item(ItemDefinition.EQUIP_SLOT_WEAPON) != BRONZE_SWORD:
		_fail("Expected sword to remain equipped")
	if not is_equal_approx(actor.get_equipped_weight(), BRONZE_SWORD.unit_weight):
		_fail("Expected equipped weight to match sword weight")
	if actor.unequip_item_from_slot(ItemDefinition.EQUIP_SLOT_WEAPON) != BRONZE_SWORD:
		_fail("Expected unequip to return sword")
	if actor.has_equipment():
		_fail("Expected equipment to be empty after unequip")
	actor.free()


func _validate_equipment_stat_modifiers() -> void:
	var actor := _make_actor()
	actor.base_attack_damage = 10.0
	actor.equip_item_to_slot(BRONZE_SWORD, ItemDefinition.EQUIP_SLOT_WEAPON)
	var modifiers := actor.get_equipment_stat_modifiers()
	if modifiers.size() != BRONZE_SWORD.stat_modifiers.size():
		_fail("Expected equipment capability to expose equipped stat modifiers")
	if not is_equal_approx(actor.get_stat_value("attack_damage"), 17.0):
		_fail("Expected WorldActor attack_damage to include equipped sword modifier")
	if not actor.call("_item_has_stat_modifier", BRONZE_SWORD, "attack_range"):
		_fail("Expected item stat modifier lookup through equipment capability")
	if not is_equal_approx(float(actor.call("_get_item_stat_value", BRONZE_SWORD, "attack_range", 1.0)), 1.42):
		_fail("Expected item stat value lookup through equipment capability")
	actor.free()


func _validate_equipment_change_batch_signal() -> void:
	var actor := _make_actor()
	_inventory_changed_count = 0
	actor.inventory_changed.connect(_on_inventory_changed)
	actor.begin_equipment_update_batch()
	actor.equip_item_to_slot(HATCHET, ItemDefinition.EQUIP_SLOT_WEAPON)
	actor.equip_item_to_slot(ROUND_SHIELD, ItemDefinition.EQUIP_SLOT_OFFHAND)
	if _inventory_changed_count != 0:
		_fail("Expected equipment batch to defer inventory_changed signal")
	actor.end_equipment_update_batch()
	if _inventory_changed_count != 1:
		_fail("Expected equipment batch to emit one inventory_changed signal, got %d" % _inventory_changed_count)
	if actor.get_equipped_item(ItemDefinition.EQUIP_SLOT_OFFHAND) != ROUND_SHIELD:
		_fail("Expected shield to equip to offhand slot")
	actor.free()


func _make_actor(setup_equipment := true) -> WorldActor:
	var actor := WORLD_ACTOR_SCRIPT.new() as WorldActor
	actor.call("_setup_actor_capabilities")
	actor.call("_setup_inventory_capability")
	if setup_equipment:
		actor.call("_setup_equipment_capability")
	return actor


func _on_inventory_changed() -> void:
	_inventory_changed_count += 1


func _fail(message: String) -> void:
	_failures.append(message)
