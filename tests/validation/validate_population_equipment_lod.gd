extends "res://tests/validation/test_case.gd"
## Real capability -> population/GECS -> destruction -> realizer -> in-place load.
const ACTOR_ID := "validation.equipment_lod"
const HATCHET := preload("res://features/inventory/resources/items/hatchet.tres")
const SWORD := preload("res://features/inventory/resources/items/iron_sword.tres")
const SHIELD := preload("res://features/inventory/resources/items/round_shield.tres")
const SILVER := preload("res://features/inventory/resources/items/silver.tres")
const SILVER_POUCH := preload("res://features/inventory/resources/items/silver_pouch.tres")
var _failures: Array[String] = []
var _checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var context := BootstrapContext.new(scene)
	BootstrapContext.active = context
	var bridge := GecsWorldController.new()
	context.register(GecsWorldController.SERVICE_ID, bridge)
	scene.add_child(bridge)
	bridge.initialize(context)
	bridge.set_process(false)
	var population := PopulationController.new()
	context.register(PopulationController.SERVICE_ID, population)
	scene.add_child(population)
	population.initialize(context)
	var factions := FactionController.new()
	context.register(FactionController.SERVICE_ID, factions)
	scene.add_child(factions)
	var realizer := PopulationCharacterRealizer.new()
	scene.add_child(realizer)
	realizer.initialize(context)
	var actor := HumanoidCharacter.new()
	actor.name = "EquipmentLodActor"
	actor.stable_id = ACTOR_ID
	actor.starting_equipment = [HATCHET, SHIELD]
	realizer._ensure_projection_bootstrap(actor)
	scene.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	bridge.register_actor(actor)
	population.register_actor(actor)
	_expect(actor.get_equipped_item("weapon") == HATCHET and actor.get_equipped_item("offhand") == SHIELD, "fixture starts with both authored slots")
	actor.get_equipment().equip_item_to_slot(SWORD, "weapon", "lod.sword.stable")
	actor.get_equipment().unequip_item_from_slot("offhand")
	# Loose coins have max_stack=1. A real pouch keeps this one-entry fixture
	# valid while also proving its contained currency survives the round trip.
	actor.get_inventory().hydrate_population_entries([{
		"item_id": SILVER_POUCH.resource_path, "count": 1, "grid_position": Vector2i(2, 1),
		"stack_id": "lod.silver.stable", "contained_item_counts": {SILVER.resource_path: 7},
		"metadata": {"owner": "original", "quality": 0.625}
	}])
	_check_inventory(actor)
	actor.get_needs().hunger = 38.75
	actor.get_needs().food_effect_remaining_seconds = 6.25
	population.unregister_actor(actor)
	bridge.unregister_actor(actor)
	var record := population.get_actor_record(ACTOR_ID)
	_expect(is_equal_approx(float(record.get("needs_state", {}).get("hunger", 0.0)), 38.75) and is_equal_approx(float(record.get("needs_state", {}).get("food_effect_remaining_seconds", 0.0)), 6.25), "retirement preserves the live needs capability handoff without a save-time scrape")
	print("EQUIPMENT_LEDGER slots=%s inventory=%s" % [str(record.get("equipment_slots", {})), str(record.get("inventory_entries", []))])
	_expect(record.get("equipment_slots", {}) == {"weapon": SWORD.resource_path}, "LOD snapshot preserves replacement and does not resurrect removed starting shield")
	var slots := bridge.get_equipment_slots(ACTOR_ID)
	print("EQUIPMENT_STACKS %s" % str(slots))
	_expect(slots.size() == 1 and str(slots[0].get("stack_id", "")) == "lod.sword.stable", "ledger keeps stable equipped stack identity")
	var old_id := actor.get_instance_id()
	actor.queue_free()
	await process_frame
	await process_frame
	_expect(not is_instance_id_valid(old_id) and population.get_live_actor(ACTOR_ID) == null, "old projection is destroyed and deregistered")
	var restored := realizer.realize_record_actor(ACTOR_ID, scene, "RestoredEquipmentActor") as HumanoidCharacter
	_expect(restored != null, "production realizer reconstructs same permanent person")
	if restored != null:
		restored.set_process(false)
		restored.set_physics_process(false)
		_expect(restored.stable_id == ACTOR_ID and restored.get_instance_id() != old_id, "re-realization keeps identity but creates new projection")
		_expect(restored.get_equipped_item("weapon") == SWORD and restored.get_equipped_item("offhand") == null, "re-realized gear matches changed and removed slots")
		_expect(restored.get_equipment().get_equipped_stack_id("weapon") == "lod.sword.stable", "re-realized equipped stack identity survives")
		_check_inventory(restored)
		_expect(is_equal_approx(restored.get_needs().hunger, 38.75) and is_equal_approx(restored.get_needs().food_effect_remaining_seconds, 6.25), "same person retains hunger and active food effect after LOD")
		var save_path := "user://equipment_lod_%d.tres" % OS.get_process_id()
		_expect(bridge.save_gecs_world(save_path), "save populated actor ledger")
		restored.get_equipment().equip_item_to_slot(HATCHET, "weapon", "discard.after.load")
		restored.get_equipment().equip_item_to_slot(SHIELD, "offhand", "discard.shield")
		restored.get_inventory().hydrate_population_entries([])
		_expect(bridge.load_gecs_world(save_path), "load same world while projection remains alive")
		# Population queues live hydration after GECS finishes rebuilding all indexes.
		await process_frame
		await process_frame
		_expect(is_instance_valid(restored) and population.get_live_actor(ACTOR_ID) == restored, "in-place load keeps the live actor")
		_expect(restored.get_equipped_item("weapon") == SWORD and restored.get_equipped_item("offhand") == null, "in-place load replaces weapon and removes extra slot")
		_expect(restored.get_equipment().get_equipped_stack_id("weapon") == "lod.sword.stable", "in-place load restores original equipped identity")
		_check_inventory(restored)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
		# A newer record may already remove every item while this retiring body
		# still displays its old loadout. Unregister must not scrape it back.
		var canonical_name := "Updated permanent person"
		population.update_actor_record(ACTOR_ID, {"member_name": canonical_name, "inventory_entries": [], "equipment_slots": {}})
		_expect(restored.get_equipped_item("weapon") == SWORD, "retiring projection remains deliberately stale")
		var handoff := Transform3D(Basis.from_euler(Vector3(0.0, 0.73, 0.0)), Vector3(7.0, 2.0, -4.0))
		restored.global_transform = handoff
		var destination := Vector3(11.0, 2.0, -4.0)
		restored.set_move_target(destination, true)
		population.unregister_actor(restored)
		bridge.unregister_actor(restored)
		var empty_record := population.get_actor_record(ACTOR_ID)
		_expect(empty_record.get("member_name") == canonical_name and empty_record.get("inventory_entries", []).is_empty() and empty_record.get("equipment_slots", {}).is_empty(), "retirement preserves newer name and explicitly empty inventory/equipment")
		_expect((empty_record.get("last_world_transform", Transform3D.IDENTITY) as Transform3D).is_equal_approx(handoff), "retirement hands back exact final position and facing")
		_expect(empty_record.get("movement_state", {}).get("move_target") == destination and empty_record.get("movement_state", {}).get("issued_by_player") == true, "retirement hands back the active movement actuator")
		restored.free()
		_expect(bridge.save_gecs_world(save_path, false), "save explicitly empty contents after projection destruction")
		_expect(bridge.load_gecs_world(save_path), "load explicitly empty durable contents")
		await process_frame
		await process_frame
		var empty_actor := realizer.realize_record_actor(ACTOR_ID, scene, "EmptyRestoredActor") as HumanoidCharacter
		_expect(empty_actor != null, "same permanent person realizes after empty save/load")
		if empty_actor != null:
			empty_actor.set_process(false)
			empty_actor.set_physics_process(false)
			_expect(empty_actor.stable_id == ACTOR_ID and empty_actor.member_name == canonical_name, "empty roundtrip preserves exact identity and newer name")
			_expect(empty_actor.inventory.entries.is_empty() and empty_actor.get_equipment().get_equipped_items().is_empty(), "empty roundtrip cannot resurrect starting or removed items")
			_expect(empty_actor.global_transform.is_equal_approx(handoff), "empty roundtrip restores saved transform")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	BootstrapContext.active = null
	scene.queue_free()
	await process_frame
	await process_frame
	for failure in _failures:
		push_error(failure)
	print("POPULATION_EQUIPMENT_LOD_%s checks=%d" % ["OK" if _failures.is_empty() else "FAILED", _checks])
	quit(0 if _failures.is_empty() else 1)

func _check_inventory(actor: WorldActor) -> void:
	print("EQUIPMENT_INVENTORY count=%d slots=%s" % [actor.inventory.entries.size(), str(actor.get_equipment().get_equipped_items())])
	_expect(actor.inventory.entries.size() == 1, "only the original inventory stack is restored")
	if actor.inventory.entries.size() != 1:
		return
	var entry = actor.inventory.entries[0]
	_expect(entry.definition == SILVER_POUCH and entry.count == 1 and entry.stack_id == "lod.silver.stable", "inventory item and stable ID survive")
	_expect(entry.contained_item_counts == {SILVER.resource_path: 7} and actor.inventory.count_item(SILVER) == 7, "exact pouch contents and total currency survive")
	_expect(entry.grid_position == Vector2i(2, 1) and entry.metadata == {"owner": "original", "quality": 0.625}, "non-default grid and metadata survive")

func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
