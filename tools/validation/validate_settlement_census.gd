extends Node

## Live-runtime census validation: instances the two-towns test level (real
## GameBootstrap, real GECS) and proves the born-settled seeding pass —
## census records exist for both towns, the settlement population equals its
## living records, and staff slots are filled by census-owned people.
## Scene-based on purpose: --script SceneTree validators cannot compile GECS
## chains (known harness limitation), so this runs as a scene:
##   timeout 60 godot --headless --path . res://tools/validation/validate_settlement_census.tscn

const LEVEL_PATH := "res://scenes/test_levels/two_towns_road_test.tscn"
const SETTLEMENT_IDS := ["farmer_crossing", "raider_camp"]
const SETTLE_FRAMES := 90
const BANDAGE := preload("res://features/inventory/resources/items/bandage.tres")
const LOAD_PROVENANCE_SAVE := "user://settlement_census_provenance_validation.tres"

var _failures: Array[String] = []
var _projection_silent_only := false


func _ready() -> void:
	_projection_silent_only = OS.get_cmdline_user_args().has("--projection-silent-only")
	var level := (load(LEVEL_PATH) as PackedScene).instantiate()
	add_child(level)
	_run.call_deferred()


func _run() -> void:
	for _frame in range(SETTLE_FRAMES):
		await get_tree().process_frame
	var settlement := get_tree().get_first_node_in_group("settlement_controller")
	var population := get_tree().get_first_node_in_group("population_controller")
	if settlement == null or population == null:
		_fail("settlement/population controllers missing from bootstrapped scene")
		_finish()
		return
	for settlement_id in SETTLEMENT_IDS:
		await _validate_settlement(settlement, population, str(settlement_id))
	await _validate_in_place_load_provenance(population)
	_validate_provenance_sources()
	_finish()


func _validate_settlement(settlement: Node, population: Node, settlement_id: String) -> void:
	var state: Dictionary = settlement.call("get_settlement_state", settlement_id)
	if state.is_empty():
		_fail("%s has no settlement state" % settlement_id)
		return
	var records: Array = population.call("get_records_for_settlement", settlement_id)
	var census_alive := 0
	var census_total := 0
	for record_value in records:
		var record: Dictionary = record_value
		var source := str(record.get("generation_source", ""))
		if source != "census" and source != "census_authored":
			continue
		census_total += 1
		if int(record.get("life_state", 0)) != NpcRules.LifeState.DEAD:
			census_alive += 1
	if census_total <= 0:
		_fail("%s was not census-seeded (0 census records)" % settlement_id)
		return
	var alive := int(population.call("count_alive_records_for_settlement", settlement_id))
	var pop := int(state.get("population", -1))
	if pop != alive:
		_fail("%s population %d != living records %d (census must be truth)" % [settlement_id, pop, alive])
	# Staff may come from census surplus OR hand-authored scene residents —
	# both are registered town people. The pool invariant is that every
	# filled slot's worker is a living population record (no minted ghosts).
	var slots: Dictionary = state.get("staff_slots", {})
	var filled := 0
	var filled_with_record := 0
	var staff_snapshots := {}
	for slot_value in slots.values():
		var slot: Dictionary = slot_value
		if not bool(slot.get("filled", false)):
			continue
		filled += 1
		var worker_id := str(slot.get("worker_actor_id", ""))
		if worker_id.is_empty():
			continue
		var record: Dictionary = population.call("get_actor_record", worker_id)
		if not record.is_empty():
			filled_with_record += 1
			_validate_realized_staff_record(record, slot, settlement_id)
			_validate_projection_appearance_isolated(population, worker_id, settlement_id)
			staff_snapshots[worker_id] = _permanent_character_data(record)
	if filled > 0 and filled_with_record < filled:
		_fail("%s has %d filled staff slots but only %d backed by population records" % [settlement_id, filled, filled_with_record])
	_validate_reconciliation_is_projection_silent(settlement, population, settlement_id, slots)
	if _projection_silent_only:
		return
	await _validate_immediate_provenance(population, staff_snapshots, settlement_id)
	for slot_id_value in slots.keys():
		settlement.call("derealize_staff_slot", settlement_id, str(slot_id_value))
	for worker_id in staff_snapshots:
		var ledger_record: Dictionary = population.call("get_actor_record", str(worker_id))
		if str(ledger_record.get("realization_state", "")) != "ledger":
			_fail("%s did not return %s to its permanent GECS ledger record" % [settlement_id, str(worker_id)])
	for slot_id_value in slots.keys():
		settlement.call("realize_staff_slot", settlement_id, str(slot_id_value))
	for worker_id in staff_snapshots:
		var restored: Dictionary = population.call("get_actor_record", str(worker_id))
		var before: Dictionary = staff_snapshots[worker_id]
		var after := _permanent_character_data(restored)
		if _canonical_snapshot_value(after) != _canonical_snapshot_value(before):
			var changed_fields: Array[String] = []
			for field in before:
				if _canonical_snapshot_value(before[field]) != _canonical_snapshot_value(after.get(field)):
					changed_fields.append(str(field))
			_fail("%s changed permanent character %s fields %s during LOD re-realization" % [settlement_id, str(worker_id), ", ".join(changed_fields)])
	print("census[%s]: records=%d alive=%d population=%d staff_filled=%d record_backed=%d" % [
		settlement_id, census_total, census_alive, pop, filled, filled_with_record])


func _validate_reconciliation_is_projection_silent(settlement: Node, population: Node, settlement_id: String, slots: Dictionary) -> void:
	var live_snapshots := {}
	for slot_value in slots.values():
		var actor_id := str((slot_value as Dictionary).get("worker_actor_id", ""))
		var actor = population.call("get_live_actor", actor_id)
		if actor is Node3D:
			live_snapshots[actor_id] = {
				"instance_id": actor.get_instance_id(),
				"transform": (actor as Node3D).global_transform,
			}
	settlement.call("_sync_settlement_staff_slots", settlement_id)
	for slot_id_value in slots.keys():
		settlement.call("realize_staff_slot", settlement_id, str(slot_id_value))
	for actor_id in live_snapshots:
		var actor = population.call("get_live_actor", str(actor_id))
		var before: Dictionary = live_snapshots[actor_id]
		if actor == null or actor.get_instance_id() != int(before.get("instance_id", -1)):
			_fail("%s hourly reconciliation replaced live staff %s" % [settlement_id, str(actor_id)])
			continue
		if actor is Node3D and not (actor as Node3D).global_transform.is_equal_approx(before.get("transform", Transform3D.IDENTITY)):
			_fail("%s hourly reconciliation moved live staff %s" % [settlement_id, str(actor_id)])


func _validate_realized_staff_record(record: Dictionary, slot: Dictionary, settlement_id: String) -> void:
	var actor_id := str(record.get("actor_id", ""))
	if str(record.get("character_realizer_id", "")).strip_edges().is_empty() or str(record.get("character_realizer_signature", "")).strip_edges().is_empty():
		_fail("%s staff %s has no persisted Character Realizer" % [settlement_id, actor_id])
	var type_id := str(record.get("character_type_id", "")).strip_edges()
	if type_id.is_empty() or str(record.get("character_type_signature", "")).strip_edges().is_empty():
		_fail("%s staff %s has no persisted Character Type" % [settlement_id, actor_id])
	var equipment: Dictionary = record.get("equipment_slots", {})
	for clothing_slot in ["chest", "legs", "feet"]:
		if not equipment.has(clothing_slot):
			_fail("%s staff %s is missing Realizer clothing slot %s" % [settlement_id, actor_id, clothing_slot])
	var role_id := str(slot.get("role_id", "")).strip_edges().to_lower()
	if role_id in ["guard", "warden"]:
		if type_id != "soldier":
			_fail("%s %s resolved %s instead of Soldier" % [settlement_id, role_id, type_id])
		if not equipment.has("weapon") or not equipment.has("offhand"):
			_fail("%s Soldier %s is missing authored weapon or offhand equipment" % [settlement_id, actor_id])


func _validate_projection_appearance_isolated(population: Node, actor_id: String, settlement_id: String) -> void:
	var actor = population.call("get_live_actor", actor_id)
	var body = actor.call("get_body_projection") if actor != null and actor.has_method("get_body_projection") else null
	var actor_appearance = actor.get("appearance_data") if actor != null else null
	var body_appearance = body.get("appearance_data") if body != null else null
	if actor_appearance != null and body_appearance != null and is_same(actor_appearance, body_appearance):
		_fail("%s projection aliases durable appearance for %s" % [settlement_id, actor_id])


func _validate_immediate_provenance(population: Node, snapshots: Dictionary, settlement_id: String) -> void:
	if snapshots.is_empty():
		return
	var actor_ids := snapshots.keys()
	actor_ids.sort()
	var actor_id := str(actor_ids[0])
	var actor = population.call("get_live_actor", actor_id)
	if actor == null:
		_fail("%s immediate provenance fixture has no live actor %s" % [settlement_id, actor_id])
		return
	var appearance = actor.get("appearance_data")
	if appearance != null and appearance.has_method("make_copy"):
		var edited = appearance.make_copy()
		edited.hair_color = Color(0.21, 0.32, 0.43, 1.0)
		var updated: Dictionary = population.call("update_actor_appearance", actor_id, edited)
		var immediate: Dictionary = population.call("get_actor_record", actor_id)
		if updated.is_empty() or (immediate.get("appearance", {}) as Dictionary).get("hair_color") != edited.hair_color:
			_fail("%s appearance edit did not reach GECS immediately for %s" % [settlement_id, actor_id])
		else:
			actor.call("apply_appearance_data", PopulationController.appearance_from_record(immediate.get("appearance", {}) as Dictionary))
	var inventory = actor.get("inventory")
	if inventory != null:
		var before_bandages := _record_item_count(population.call("get_actor_record", actor_id), BANDAGE.resource_path)
		inventory.add_item_count(BANDAGE, 1)
		var after_bandages := _record_item_count(population.call("get_actor_record", actor_id), BANDAGE.resource_path)
		if after_bandages != before_bandages + 1:
			_fail("%s inventory mutation did not reach GECS immediately for %s" % [settlement_id, actor_id])
	var stats = actor.call("get_stats") if actor.has_method("get_stats") else null
	if stats != null:
		var skill_id := SkillRules.MOVEMENT_RUNNING
		var next_level := int(stats.call("get_skill_level", skill_id)) + 1
		stats.call("set_skill_level", skill_id, next_level)
		stats.call("add_skill_xp", skill_id, 1.0, "provenance_validation")
		var skill_record: Dictionary = population.call("get_actor_record", actor_id)
		if int((skill_record.get("skill_levels", {}) as Dictionary).get(skill_id, 0)) != next_level or not is_equal_approx(float((skill_record.get("skill_xp", {}) as Dictionary).get(skill_id, 0.0)), 1.0):
			_fail("%s skill mutation did not reach GECS immediately for %s" % [settlement_id, actor_id])
	var equipment = actor.call("get_equipment") if actor.has_method("get_equipment") else null
	if equipment != null:
		var weapon = equipment.call("get_equipped_item", "weapon")
		if weapon != null:
			var weapon_stack_id := str(equipment.call("get_equipped_stack_id", "weapon"))
			if weapon_stack_id.is_empty():
				_fail("%s equipped weapon has no durable stack ID for %s" % [settlement_id, actor_id])
			var gecs = population.call("_get_gecs_world")
			var party_inventory := BootstrapContext.service(PartyInventoryController.SERVICE_ID)
			var lifecycle := BootstrapContext.service(&"item_lifecycle")
			if gecs == null or party_inventory == null or lifecycle == null:
				_fail("%s equipment provenance controllers missing for %s" % [settlement_id, actor_id])
			else:
				var marker := {"provenance_validation": actor_id}
				var metadata_result: Dictionary = lifecycle.call("submit_metadata", weapon_stack_id, marker)
				if not bool(metadata_result.get("accepted", false)):
					_fail("%s equipment metadata command rejected for %s" % [settlement_id, actor_id])
					return
				lifecycle.call("_drain_commands")
				if (gecs.call("get_item_stack", weapon_stack_id).get("metadata", {}) as Dictionary) != marker:
					_fail("%s equipment metadata command did not resolve for %s" % [settlement_id, actor_id])
					return
				await get_tree().process_frame
				var target_cell: Vector2i = inventory.find_first_space(weapon)
				if target_cell == Vector2i(-1, -1):
					_fail("%s has no room to validate equipment provenance for %s" % [settlement_id, actor_id])
				else:
					party_inventory.call("_on_inventory_unequip_requested", actor, "weapon", actor, target_cell)
					var inventory_entry = _inventory_entry_by_stack_id(inventory, weapon_stack_id)
					var inventory_stack: Dictionary = gecs.call("get_item_stack", weapon_stack_id)
					if inventory_entry == null or str(inventory_stack.get("location_kind", "")) != "inventory" or inventory_stack.get("metadata", {}) != marker:
						_fail("%s equipment-to-inventory lost stack provenance for %s" % [settlement_id, actor_id])
					else:
						party_inventory.call("_on_inventory_equip_requested", actor, inventory_entry, actor, "weapon")
						if equipment.call("get_equipped_item", "weapon") == null:
							_fail("%s inventory-to-equipment action failed for %s" % [settlement_id, actor_id])
							return
						party_inventory.call("_on_inventory_equipment_drop_requested", actor, "weapon")
						lifecycle.call("_drain_commands")
						var world_item := _world_item_by_stack_id(weapon_stack_id)
						var world_stack: Dictionary = lifecycle.call("get_stack_record", weapon_stack_id)
						if world_item == null or str(world_stack.get("location_kind", "")) != "world_loose":
							_fail("%s equipment-to-world lost stack provenance for %s" % [settlement_id, actor_id])
						elif int(world_item.get("quantity")) != 1 or world_stack.get("metadata", {}) != marker or not (world_stack.get("world_transform", Transform3D.IDENTITY) as Transform3D).is_equal_approx(world_item.global_transform):
							_fail("%s world drop did not persist final stack state for %s" % [settlement_id, actor_id])
						elif not bool(world_item.call("try_pickup", actor)):
							_fail("%s world-to-inventory failed for %s" % [settlement_id, actor_id])
						else:
							lifecycle.call("_drain_commands")
							inventory_entry = _inventory_entry_by_stack_id(inventory, weapon_stack_id)
							if inventory_entry == null:
								_fail("%s world pickup changed stack ID for %s" % [settlement_id, actor_id])
							else:
								party_inventory.call("_on_inventory_equip_requested", actor, inventory_entry, actor, "weapon")
								var restored_stack: Dictionary = gecs.call("get_item_stack", weapon_stack_id)
								if str(equipment.call("get_equipped_stack_id", "weapon")) != weapon_stack_id or str(restored_stack.get("location_kind", "")) != "equipment" or restored_stack.get("metadata", {}) != marker:
									_fail("%s inventory-to-equipment changed stack provenance for %s" % [settlement_id, actor_id])
	snapshots[actor_id] = _permanent_character_data(population.call("get_actor_record", actor_id))


func _record_item_count(record: Dictionary, item_path: String) -> int:
	var count := 0
	for entry_value in record.get("inventory_entries", []) as Array:
		var entry := entry_value as Dictionary
		if str(entry.get("item_id", "")) == item_path:
			count += int(entry.get("count", 0))
	return count


func _inventory_entry_by_stack_id(inventory, stack_id: String):
	if inventory == null:
		return null
	for entry in inventory.entries:
		if str(entry.get("stack_id")) == stack_id:
			return entry
	return null


func _world_item_by_stack_id(stack_id: String) -> WorldItem:
	for item in get_tree().get_nodes_in_group("world_item"):
		if item is WorldItem and str(item.get("stack_id")) == stack_id:
			return item as WorldItem
	return null


func _validate_provenance_sources() -> void:
	var appearance_controller := FileAccess.get_file_as_string("res://features/actors/projection/appearance/character_appearance_controller.gd")
	var save_source := appearance_controller.get_slice("func _on_editor_save_requested", 1).get_slice("func _on_editor_cancel_requested", 0)
	if save_source.find("update_actor_appearance") < 0 or save_source.find("update_actor_appearance") > save_source.find("actor.apply_appearance_data"):
		_fail("appearance save must update GECS before refreshing the live projection")
	var population_source := FileAccess.get_file_as_string("res://features/world_sim/sim/population/population_controller.gd")
	var unregister_source := population_source.get_slice("func unregister_actor", 1).get_slice("func get_actor_record", 0)
	if unregister_source.contains("_merge_actor_state_into_record"):
		_fail("population derealization must not scrape durable state from the live actor")
	var gecs_source := FileAccess.get_file_as_string("res://features/core/gecs_world_controller.gd")
	var gecs_unregister := gecs_source.get_slice("func unregister_actor", 1).get_slice("func get_actor_entity", 0)
	if gecs_unregister.contains("sync_actor_inventory(actor)") or gecs_unregister.contains("global_position"):
		_fail("GECS actor unregister must use canonical components, not scrape the live projection")
	var rustdead_source := FileAccess.get_file_as_string("res://features/actors/projection/rustdead/rustdead_body_projection.gd")
	var rustdead_eyebrows := rustdead_source.get_slice("func apply_automatic_eyebrow_style", 1).get_slice("func begin_cinder_burn_visuals", 0)
	if rustdead_eyebrows.contains("_actor.appearance_data"):
		_fail("Rustdead projection must not mutate actor appearance truth")
	if population_source.get_slice("func serialize_state", 1).get_slice("func apply_serialized_state", 0).contains("sync_population_state"):
		_fail("population save must serialize GECS without scraping live actors")


func _validate_in_place_load_provenance(population: Node) -> void:
	var records: Array = population.call("get_records_for_settlement", "farmer_crossing")
	if records.is_empty():
		_fail("in-place load provenance fixture has no farmer records")
		return
	var actor_id := str((records[0] as Dictionary).get("actor_id", ""))
	var actor = population.call("get_live_actor", actor_id)
	var gecs = population.call("_get_gecs_world")
	if actor == null or gecs == null:
		_fail("in-place load provenance fixture has no live actor or GECS")
		return
	var before := _permanent_character_data(population.call("get_actor_record", actor_id))
	if not bool(gecs.call("save_gecs_world", LOAD_PROVENANCE_SAVE, false)):
		_fail("in-place provenance save failed")
		return
	var stale_appearance = actor.get("appearance_data").make_copy()
	stale_appearance.hair_color = Color(0.91, 0.02, 0.03, 1.0)
	actor.call("apply_appearance_data", stale_appearance)
	actor.get("inventory").add_item_count(BANDAGE, 1)
	var equipment = actor.call("get_equipment")
	if equipment != null:
		equipment.call("unequip_item_from_slot", "weapon")
	if not bool(gecs.call("load_gecs_world", LOAD_PROVENANCE_SAVE)):
		_fail("in-place provenance load failed")
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var after := _permanent_character_data(population.call("get_actor_record", actor_id))
	if _canonical_snapshot_value(after) != _canonical_snapshot_value(before):
		var changed_fields: Array[String] = []
		for field in before:
			if _canonical_snapshot_value(before[field]) != _canonical_snapshot_value(after.get(field)):
				changed_fields.append(str(field))
		_fail("in-place load changed canonical GECS fields %s for %s" % [", ".join(changed_fields), actor_id])
	var expected_appearance := before.get("appearance", {}) as Dictionary
	if actor.get("appearance_data").hair_color != expected_appearance.get("hair_color"):
		_fail("in-place load did not hydrate live appearance for %s" % actor_id)
	var expected_weapon := str((before.get("equipment", {}) as Dictionary).get("weapon", ""))
	var live_weapon = actor.call("get_equipped_item", "weapon")
	if live_weapon == null or live_weapon.resource_path != expected_weapon:
		_fail("in-place load did not hydrate live equipment for %s" % actor_id)
	if _inventory_item_count(actor.get("inventory"), BANDAGE) != _record_item_count({"inventory_entries": before.get("inventory", [])}, BANDAGE.resource_path):
		_fail("in-place load did not hydrate live inventory for %s" % actor_id)
	var absolute_path := ProjectSettings.globalize_path(LOAD_PROVENANCE_SAVE)
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)


func _inventory_item_count(inventory, definition: ItemDefinition) -> int:
	return int(inventory.count_item(definition)) if inventory != null else 0


func _permanent_character_data(record: Dictionary) -> Dictionary:
	return {
		"actor_id": record.get("actor_id"),
		"member_name": record.get("member_name"),
		"appearance": record.get("appearance"),
		"skills": record.get("skill_levels"),
		"skill_xp": record.get("skill_xp"),
		"equipment": record.get("equipment_slots"),
		"inventory": record.get("inventory_entries"),
		"realizer": record.get("character_realizer_signature"),
		"character_type": record.get("character_type_signature"),
	}


func _canonical_snapshot_value(value) -> String:
	if value is float:
		return "%.6f" % value
	if value is Dictionary:
		var keys := (value as Dictionary).keys()
		keys.sort_custom(func(a, b): return str(a) < str(b))
		var parts: Array[String] = []
		for key in keys:
			parts.append("%s:%s" % [str(key), _canonical_snapshot_value((value as Dictionary)[key])])
		return "{%s}" % ",".join(parts)
	if value is Array:
		var parts: Array[String] = []
		for entry in value as Array:
			parts.append(_canonical_snapshot_value(entry))
		return "[%s]" % ",".join(parts)
	return var_to_str(value)


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("SETTLEMENT_CENSUS_OK")
		get_tree().quit(0)
		return
	print("SETTLEMENT_CENSUS_FAILED count=%d" % _failures.size())
	get_tree().quit(1)
