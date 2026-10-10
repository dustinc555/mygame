extends GutTest

var context: BootstrapContext
var previous_context: BootstrapContext
var root: Node3D
var gecs: GecsWorldController
var population: PopulationController
var law: LawOrderController
var jail: SettlementJail
var cell: JailCell


func before_each() -> void:
	previous_context = BootstrapContext.active
	root = Node3D.new()
	add_child(root)
	context = BootstrapContext.new(root)
	BootstrapContext.active = context
	gecs = GecsWorldController.new()
	root.add_child(gecs)
	context.register(&"gecs_world", gecs)
	gecs.initialize(context)
	gecs.set_process(false)
	population = PopulationController.new()
	root.add_child(population)
	context.register(&"population", population)
	population.initialize(context)
	law = LawOrderController.new()
	root.add_child(law)
	context.register(&"law_order", law)
	law._context = context
	law.root_scene = root
	law.set_process(false)
	jail = SettlementJail.new()
	jail.facility_id = "town.jail"
	jail.name = "Jail"
	var furniture := Node3D.new()
	furniture.name = "Furniture"
	jail.add_child(furniture)
	cell = JailCell.new()
	cell.cell_id = "cell_a"
	cell.position = Vector3(4, 0, 2)
	furniture.add_child(cell)
	root.add_child(jail)
	jail.set_process(false)
	var record: Dictionary = load("res://features/actors/resources/characters/tavin_rook.tres").to_record()
	record["settlement_id"] = "town"
	record["faction_id"] = "town_faction"
	record["generation_source"] = "assignment_preferred"
	population._save_actor_record("tavin_rook", record)


func after_each() -> void:
	root.queue_free()
	await get_tree().process_frame
	BootstrapContext.active = previous_context


func slot() -> Dictionary:
	return {"slot_id": "town.jail.prisoner_a", "settlement_id": "town", "assignment_domain": "custody", "role_id": "prisoner", "authority_scope": "", "assignment_exclusivity_group": "custody"}


func start() -> bool:
	assert_true(law.has_method("start_authored_prisoner"), "Law must own one-time starting custody")
	if not law.has_method("start_authored_prisoner"):
		return false
	return law.call("start_authored_prisoner", "tavin_rook", slot(), jail)


func test_start_reserves_cell_and_persists_indefinite_custody_without_a_live_body() -> void:
	if not start():
		return
	assert_eq(cell.occupant_ids, ["tavin_rook"] as Array[String])
	assert_true(cell.is_locked)
	var custody: Dictionary = law.prisoner_records.tavin_rook
	assert_eq(custody.state, "jailed")
	assert_eq(custody.jail_id, "town.jail")
	assert_eq(custody.cell_id, "cell_a")
	assert_eq(custody.release_at_minute, -1)
	assert_true(custody.sentence_decision_given)
	assert_eq(population.get_actor_record("tavin_rook").last_world_position, cell.get_prisoner_position())
	law._process_prisoners()
	assert_eq(law.prisoner_records.tavin_rook.release_at_minute, -1)
	assert_false(law.call("start_authored_prisoner", "tavin_rook", slot(), jail), "A starting assignment must not run twice")
	var saved := gecs.get_law_order_state()
	assert_eq(saved.authored_prisoner_starts[slot().slot_id], "tavin_rook")


func test_no_cell_leaves_start_unconsumed_and_does_not_imprison_anyone() -> void:
	cell.occupant_ids.assign(["other"])
	assert_false(start())
	assert_false(law.prisoner_records.has("tavin_rook"))
	assert_false(law.serialize_state().get("authored_prisoner_starts", {}).has(slot().slot_id))
	assert_eq(cell.occupant_ids, ["other"] as Array[String])


func test_escape_unbinds_start_and_roundtrip_cannot_rejail() -> void:
	population.assign_record_to_slot("tavin_rook", slot(), true)
	assert_true(start())
	cell.is_locked = false
	law.release_picked_cell(cell)
	var person := population.get_actor_record("tavin_rook")
	assert_false(person.assignments.has("custody"))
	assert_eq(person.role_id, "resident")
	assert_eq(person.last_world_position, cell.get_release_position())
	assert_eq(population.get_seeded_resident_records("town").size(), 1, "The same released person remains realizable")
	var saved := CGameLawOrderState.new()
	saved.apply_state(law.serialize_state())
	law.apply_serialized_state(saved.to_state())
	assert_false(start(), "Escape survives save/load")
	assert_true(cell.occupant_ids.is_empty())
	assert_false(law.prisoner_records.has("tavin_rook"))


func test_load_restores_offscreen_cell_reservation_and_death_frees_it() -> void:
	assert_true(start())
	var saved := law.serialize_state()
	cell.occupant_ids.clear()
	law.apply_serialized_state(saved)
	assert_eq(cell.occupant_ids, ["tavin_rook"] as Array[String])
	population.mark_record_dead("tavin_rook")
	law._on_population_life_state_changed("tavin_rook", NpcRules.LifeState.ALIVE, NpcRules.LifeState.DEAD)
	assert_true(cell.occupant_ids.is_empty())
	assert_false(law.prisoner_records.has("tavin_rook"))
	assert_false(start())


func test_custody_is_exclusive_and_never_claimed_as_a_vacancy() -> void:
	assert_true(population.claim_record_for_assignment("town", slot()).is_empty())
	assert_true(population.claim_records_for_assignments("town", [slot()]).is_empty())
	assert_false(population.assign_record_to_slot("tavin_rook", slot(), true).is_empty())
	var home := {"settlement_id": "town", "slot_id": "town.home", "assignment_domain": "residence", "assignment_exclusivity_group": "residence"}
	assert_true(population.assign_record_to_slot("tavin_rook", home, true).is_empty())


func test_dead_character_cannot_be_seeded_into_a_cell() -> void:
	population.mark_record_dead("tavin_rook")
	assert_false(start())
	assert_true(cell.occupant_ids.is_empty())


func test_facility_binding_starts_custody_once_and_never_refills_after_escape() -> void:
	var settlement := SettlementController.new()
	root.add_child(settlement)
	settlement.set_process(false)
	settlement._context = context
	var spec := slot()
	spec.owner_id = "town.jail"
	spec.filled = false
	spec.occupant_actor_id = ""
	var key := "custody:" + str(spec.slot_id)
	settlement.settlement_states["town"] = {"assignment_slots": {key: spec}, "assignment_vacancies": {}}
	settlement._staff_role_owners_by_settlement["town"] = {"town.jail": jail}
	assert_false(settlement.assign_actor_to_assignment_slot("town", "custody", str(spec.slot_id), "tavin_rook").is_empty())
	assert_true(law.prisoner_records.has("tavin_rook"))
	cell.is_locked = false
	law.release_picked_cell(cell)
	settlement._on_population_record_changed("town", "tavin_rook")
	settlement._assign_from_ledger("town", true)
	assert_true(settlement.settlement_states.town.assignment_vacancies.is_empty())
	assert_false(settlement.settlement_states.town.assignment_slots[key].filled)
	assert_true(settlement.assign_actor_to_assignment_slot("town", "custody", str(spec.slot_id), "tavin_rook").is_empty())
	assert_false(population.get_actor_record("tavin_rook").assignments.has("custody"))


func test_prisoner_role_is_jail_only_and_warns_when_cells_are_overbooked() -> void:
	var role := load("res://features/settlements/resources/roles/prisoner.tres") as FacilityRoleDefinition
	var entry := FacilityRoleSlotDefinition.new()
	entry.slot_id = "prisoner_a"
	entry.role = role
	entry.named_character = load("res://features/actors/resources/characters/tavin_rook.tres")
	var spec := entry.to_slot_spec("town.jail")
	assert_eq(spec.assignment_domain, "custody")
	assert_eq(spec.authority_scope, "")
	assert_false(spec.uses_settlement_jobs)
	var dock = load("res://addons/world_authoring/facility_dock.gd").new()
	dock._facility = jail
	var roles: Array[Resource] = dock._role_catalog()
	var characters: Array[Resource] = dock._character_catalog()
	assert_true(roles.has(role))
	jail.role_slots.assign([entry, entry.duplicate()])
	var issues: Dictionary = dock._person_issues(entry, role, entry.named_character, roles, characters, {}, {}, {})
	assert_true(str(issues.warning).contains("cell"), "Overbooked jails must explain the missing physical capacity")
	var ordinary := SettlementFacilityInstance.new()
	dock._facility = ordinary
	assert_false(dock._role_catalog().has(role))
	dock.free()
	ordinary.free()
