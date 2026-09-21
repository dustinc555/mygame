extends GutTest

# Count discovery, not wall time: unchanged hours must not scale with scenery.
class Settlements extends SettlementController:
	var owner_walks := 0
	var nearby := true
	func _collect_staff_role_owners(root: Node) -> Array[Node]:
		owner_walks += 1
		return super._collect_staff_role_owners(root)
	func _settlement_is_within_lod_exit(_id: String) -> bool: return nearby

class Anchor extends Node3D:
	var resident_walks := 0
	var settlement_definition: Resource
	func get_settlement_id() -> String: return "town"
	func get_resident_characters() -> Array:
		resident_walks += 1
		return []

class Facility extends Node3D:
	var specs_read := 0
	var slots: Array[Dictionary] = [{"slot_id": "home.bed", "assignment_domain": "residence", "role_id": "resident", "population_cost": 0}]
	func get_facility_id() -> String: return "home"
	func get_assignment_slot_specs() -> Array[Dictionary]:
		specs_read += 1
		return slots.duplicate(true)

class Clock extends Node:
	signal hour_changed(absolute_hour: int, day: int, hour: int)
	var minute := 60
	func get_absolute_minute() -> int: return minute

# Use the real population assignment/death rules with an in-memory record query
# in place of the GECS world, so no game world or actor scenes are booted.
class Population extends PopulationController:
	func get_records_for_settlement(id: String) -> Array[Dictionary]:
		var result: Array[Dictionary] = []
		for record in actor_records.values():
			if record.get("settlement_id") == id: result.append(record.duplicate(true))
		return result
	func count_alive_records_for_settlement(id: String) -> int:
		var count := 0
		for record in get_records_for_settlement(id):
			if record.get("life_state", 0) != NpcRules.LifeState.DEAD: count += 1
		return count

class Registry extends BuildingRegistry:
	func get_building(_id: String) -> Dictionary: return {"settlement_id": "town"}
	func get_settlement_housing_capacity(_id: String) -> int: return 3

class Corpse extends Node:
	var life_state := NpcRules.LifeState.DEAD

class Ledger extends Node:
	var states: Dictionary = {}
	var slots: Dictionary = {}
	func get_settlement_states() -> Dictionary: return states.duplicate(true)
	func upsert_settlement_state(id: String, state: Dictionary) -> void: states[id] = state.duplicate(true)
	func upsert_assignment_slot(id: String, slot: Dictionary) -> void:
		slots["%s:%s:%s" % [id, slot.assignment_domain, slot.slot_id]] = slot.duplicate(true)
	func remove_assignment_slot(id: String, domain: String, slot_id: String) -> void:
		slots.erase("%s:%s:%s" % [id, domain, slot_id])

class Bed extends Node3D:
	var position_queries := 0
	func claim_sleeper(_actor: Node) -> bool: return true
	func get_interaction_position(_actor: Node) -> Vector3:
		position_queries += 1
		return global_position

func _fixture() -> Dictionary:
	var controller := Settlements.new()
	add_child_autofree(controller)
	var anchor := Anchor.new()
	anchor.settlement_definition = SettlementDefinition.new()
	anchor.settlement_definition.settlement_id = "town"
	add_child_autofree(anchor)
	var facility := Facility.new()
	anchor.add_child(facility)
	var furniture := Node3D.new()
	furniture.name = "Furniture"
	facility.add_child(furniture)
	var bed := Bed.new()
	furniture.add_child(bed)
	bed.position = Vector3(2, 0, 3)
	controller.settlement_anchors["town"] = anchor
	controller.settlement_definitions["town"] = anchor.settlement_definition
	controller.settlement_states["town"] = {"population": 3, "population_initialized": true, "assignment_slots": {}, "assignment_vacancies": {}}
	controller._sync_settlement_assignment_slots("town")
	var registry := Registry.new()
	controller.add_child(registry)
	var clock := Clock.new()
	controller.add_child(clock)
	var population := Population.new()
	controller.add_child(population)
	var ledger := Ledger.new()
	controller.add_child(ledger)
	ledger.states = controller.settlement_states.duplicate(true)
	var context := BootstrapContext.new(anchor)
	context.register(WorldTimeController.SERVICE_ID, clock)
	context.register(BuildingRegistry.SERVICE_ID, registry)
	context.register(PopulationController.SERVICE_ID, population)
	context.register(GecsWorldController.SERVICE_ID, ledger)
	controller.initialize(context)
	return {"controller": controller, "anchor": anchor, "facility": facility, "bed": bed, "registry": registry, "population": population, "clock": clock, "ledger": ledger}

func _add_resident(f: Dictionary, id: String) -> void:
	f.population._save_actor_record(id, {"actor_id": id, "settlement_id": "town", "role_id": "resident", "generation_source": "census", "birth_day_index": -100000, "life_state": NpcRules.LifeState.ALIVE})

func test_anchor_unload_preserves_slots_and_reload_discovers_geometry_once() -> void:
	var f := _fixture()
	_add_resident(f, "person")
	f.controller.assign_actor_to_assignment_slot("town", "residence", "home.bed", "person")
	var walks: int = f.controller.owner_walks
	f.registry.building_updated.emit("home.building")
	f.controller.unregister_settlement_anchor(f.anchor)
	remove_child(f.anchor)
	await get_tree().process_frame
	assert_eq(f.controller.owner_walks, walks)
	assert_eq(f.controller.get_assignment_slots_for_realization("town")[0].occupant_actor_id, "person")
	assert_eq(f.ledger.states.town.assignment_slots["residence:home.bed"].occupant_actor_id, "person")
	assert_false(f.controller._staff_role_owners_by_settlement.has("town"))
	f.bed.position = Vector3(5, 0, 6)
	add_child(f.anchor)
	f.controller.register_settlement_anchor(f.anchor)
	await get_tree().process_frame
	assert_eq(f.controller.owner_walks, walks + 1)
	assert_eq(f.controller.get_assignment_slots_for_realization("town")[0].occupant_actor_id, "person")
	assert_eq(f.controller.get_assignment_slots_for_realization("town")[0].world_position, Vector3(5, 0, 6))

func test_registry_rebuild_refreshes_saved_assignments_before_reconciling_definitions() -> void:
	var f := _fixture()
	f.facility.slots.append({"slot_id": "home.worker", "assignment_domain": "employment", "role_id": "worker"})
	f.controller._sync_settlement_assignment_slots("town")
	_add_resident(f, "person")
	f.controller.assign_actor_to_assignment_slot("town", "employment", "home.worker", "person")
	f.controller.assign_actor_to_assignment_slot("town", "residence", "home.bed", "person")
	f.controller.settlement_states.town.assignment_slots.clear()
	var late_facility := Facility.new()
	late_facility.slots = [{"slot_id": "home.second_bed", "assignment_domain": "residence", "role_id": "resident", "population_cost": 0}]
	# A projection can register during load, before registry_rebuilt's deferred
	# refresh. Its pending reconciliation must not overwrite restored GECS truth.
	f.anchor.add_child(late_facility)
	f.registry.registry_rebuilt.emit()
	await get_tree().process_frame
	assert_eq(f.controller.get_assignment_slots_for_realization("town").size(), 3)
	assert_eq(f.controller.settlement_states.town.assignment_slots["employment:home.worker"].occupant_actor_id, "person")
	assert_eq(f.controller.settlement_states.town.assignment_slots["residence:home.bed"].occupant_actor_id, "person")
	assert_eq(f.ledger.states.town.assignment_slots.size(), 3, "Reconciled definitions must reach GECS persistence")
	assert_eq(f.ledger.slots["town:employment:home.worker"].occupant_actor_id, "person")

func test_death_signal_releases_both_domains_and_records_fear_once_without_discovery() -> void:
	var f := _fixture()
	f.facility.slots.append({"slot_id": "home.worker", "assignment_domain": "employment", "role_id": "worker", "replacement_delay_days": 1.0})
	f.controller._sync_settlement_assignment_slots("town")
	_add_resident(f, "person")
	_add_resident(f, "survivor")
	assert_false(f.controller.assign_actor_to_assignment_slot("town", "employment", "home.worker", "person").is_empty())
	assert_false(f.controller.assign_actor_to_assignment_slot("town", "residence", "home.bed", "person").is_empty())
	assert_eq(f.controller.settlement_states.town.population_assigned, 1, "Manual assignment accounting cannot wait for an hourly rescan")
	var corpse := Corpse.new()
	corpse.name = "Worker"
	corpse.set_meta("settlement_staff_slot_id", "home.worker")
	f.facility.add_child(corpse)
	f.population._live_actor_by_id["person"] = corpse
	var walks: int = f.controller.owner_walks
	f.population.mark_record_dead("person")
	f.population.person_died.emit("person")
	var state: Dictionary = f.controller.settlement_states.town
	assert_eq(state.population, 1, "Living records remain authoritative")
	assert_eq(float(state.get("fear", 0.0)), 0.08, "A death retains the fear consequence without corpse scans")
	assert_eq((state.get("population_death_records", {}) as Dictionary).size(), 1)
	assert_eq(state.assignment_slots["employment:home.worker"].occupant_actor_id, "")
	assert_eq(state.assignment_slots["residence:home.bed"].occupant_actor_id, "")
	assert_eq(state.assignment_vacancies["employment:home.worker"].replacement_due_minute, 1500)
	assert_eq(f.controller.owner_walks, walks)
	assert_eq(f.anchor.resident_walks, 0)
	assert_eq(str(corpse.name), "Corpse", "Role-name fallback must not rediscover the dead worker")
	assert_eq(str(corpse.get_meta("settlement_staff_slot_id", "")), "")

func test_hourly_replacement_deadline_fills_ledger_without_geometry_or_realization() -> void:
	var f := _fixture()
	f.facility.slots.append({"slot_id": "home.worker", "assignment_domain": "employment", "role_id": "worker", "replacement_delay_days": 1.0})
	f.controller._sync_settlement_assignment_slots("town")
	_add_resident(f, "person")
	_add_resident(f, "replacement")
	f.controller._on_hour_changed(1, 0, 1)
	assert_eq(f.controller.settlement_states.town.assignment_slots["employment:home.worker"].occupant_actor_id, "person")
	f.population.mark_record_dead("person")
	assert_eq(f.controller.get_available_population("town"), 1, "Releasing a worker must update assignment accounting without the removed hourly rescan")
	var walks: int = f.controller.owner_walks
	f.controller.nearby = false
	f.clock.minute = 1499
	f.controller._on_hour_changed(24, 1, 0)
	assert_eq(f.controller.settlement_states.town.assignment_slots["employment:home.worker"].occupant_actor_id, "")
	f.clock.minute = 1500
	f.controller._on_hour_changed(25, 1, 1)
	assert_eq(f.controller.settlement_states.town.assignment_slots["employment:home.worker"].occupant_actor_id, "replacement")
	assert_eq(f.population.get_actor_record("replacement").get("assignments", {}).get("employment", ""), "home.worker")
	assert_eq(f.ledger.slots["town:employment:home.worker"].occupant_actor_id, "replacement")
	assert_null(f.population.get_live_actor("replacement"), "Ledger assignment does not realize offscreen people")
	assert_eq(f.controller.owner_walks, walks)

func test_registry_mutation_reconciles_slot_definitions_once_per_burst() -> void:
	var f := _fixture()
	f.facility.slots.append({"slot_id": "home.worker", "assignment_domain": "employment", "role_id": "worker"})
	f.controller.nearby = false
	var walks: int = f.controller.owner_walks
	f.registry.building_created.emit("home.building")
	f.registry.building_updated.emit("home.building")
	await get_tree().process_frame
	assert_eq(f.controller.get_assignment_slots_for_realization("town").size(), 2, "Registry mutation must discover new definitions even outside LOD")
	assert_eq(f.controller.owner_walks, walks + 1, "A registry burst reconciles a town once")
	f.controller._on_hour_changed(1, 0, 1)
	assert_eq(f.controller.owner_walks, walks + 1)

func test_live_facility_add_remove_reconciles_without_a_registry_write() -> void:
	var f := _fixture()
	var facility := Facility.new()
	facility.slots = [{"slot_id": "new.worker", "assignment_domain": "employment", "role_id": "worker"}]
	f.anchor.add_child(facility)
	await get_tree().process_frame
	assert_eq(f.controller.get_assignment_slots_for_realization("town").size(), 2)
	f.anchor.remove_child(facility)
	facility.free()
	await get_tree().process_frame
	assert_eq(f.controller.get_assignment_slots_for_realization("town").size(), 1)
	assert_false(f.controller.settlement_states.town.assignment_vacancies.has("employment:new.worker"))

func test_construction_scene_and_registry_events_share_one_reconciliation() -> void:
	var f := _fixture()
	var walks: int = f.controller.owner_walks
	var facility := Facility.new()
	facility.slots = [{"slot_id": "new.worker", "assignment_domain": "employment", "role_id": "worker"}]
	f.anchor.add_child(facility)
	f.registry.building_created.emit("new.building")
	await get_tree().process_frame
	assert_eq(f.controller.get_assignment_slots_for_realization("town").size(), 2)
	assert_eq(f.controller.owner_walks, walks + 1, "Construction emits both lifecycle and registry events")

func test_furniture_changes_refresh_residence_position_without_hourly_polling() -> void:
	var f := _fixture()
	var furniture: Node = f.bed.get_parent()
	furniture.remove_child(f.bed)
	f.bed.free()
	var replacement := Bed.new()
	replacement.position = Vector3(8, 0, 9)
	furniture.add_child(replacement)
	var walks: int = f.controller.owner_walks
	await get_tree().process_frame
	assert_eq(f.controller.get_assignment_slots_for_realization("town")[0].world_position, Vector3(8, 0, 9))
	assert_eq(f.controller.owner_walks, walks + 1)
	var decoration := Node3D.new()
	furniture.add_child(decoration)
	await get_tree().process_frame
	assert_eq(f.controller.owner_walks, walks + 1, "Unrelated scene nodes must not invalidate assignment discovery")

func test_unchanged_hours_do_not_rediscover_owners_furniture_or_residents() -> void:
	var f := _fixture()
	var slots: Array[Dictionary] = f.controller.get_assignment_slots_for_realization("town")
	assert_eq(slots[0].world_position, Vector3(2, 0, 3))
	var walks: int = f.controller.owner_walks
	var specs: int = f.facility.specs_read
	var positions: int = f.bed.position_queries
	for hour in [1, 2, 3]:
		f.controller._on_hour_changed(hour, 0, hour)
	assert_eq(f.controller.owner_walks, walks, "Hours must not walk unchanged settlement geometry")
	assert_eq(f.facility.specs_read, specs, "Hours must reuse registered slot definitions")
	assert_eq(f.bed.position_queries, positions, "Hours must reuse registered residence positions")
	assert_eq(f.anchor.resident_walks, 0, "Population death signals replace resident subtree polling")
	assert_eq(f.controller.get_assignment_slots_for_realization("town"), slots)
