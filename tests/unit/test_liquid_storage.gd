extends GutTest
## Controller contracts from validate_liquid_storage. Only the persistence port
## is a dictionary-backed double; authorization, quantities and indexes are real.
## Disk/GECS restoration and physical hauling remain validation scenarios.

class MemoryLedger extends Node:
	# LiquidStorageController connects to this production ledger contract.
	@warning_ignore("unused_signal")
	signal world_reindexed
	var states: Dictionary = {}
	var reject_writes := false

	func get_liquid_container_states() -> Dictionary:
		return states.duplicate(true)

	func upsert_liquid_container_state(state: Dictionary) -> Dictionary:
		if reject_writes:
			return {}
		states[state.liquid_container_id] = state.duplicate(true)
		return state.duplicate(true)


var ledger: MemoryLedger
var storage: LiquidStorageController
var authorization: Dictionary


func before_each() -> void:
	ledger = add_child_autofree(MemoryLedger.new())
	storage = add_child_autofree(LiquidStorageController.new())
	var context := BootstrapContext.new(self)
	context.register(&"gecs_world", ledger)
	storage.initialize(context)
	authorization = {
		"liquid_container_id": "unit.tank",
		"owner_faction_name": "Player",
		"actor_faction_name": "Player",
		"owner_access_approved": true,
		"theft_approved": false,
	}
	assert_false(storage.ensure_container({
		"liquid_container_id": "unit.tank",
		"settlement_id": "unit.town",
		"owner_faction_name": "Player",
		"assigned_liquid_id": "water",
		"capacity_liters": 100.0,
		"current_liters": 60.0,
	}).is_empty())


func after_each() -> void:
	storage.teardown()


func test_reserved_capacity_cannot_be_stolen_by_an_unreserved_deposit() -> void:
	assert_eq(storage.reserve_incoming("unit.tank", "water", 30.0, authorization), 30.0)
	assert_eq(storage.deposit("unit.tank", "water", 50.0, authorization), 10.0)
	assert_eq(ledger.states["unit.tank"].current_liters, 70.0)
	assert_eq(ledger.states["unit.tank"].reserved_incoming_liters, 30.0)
	assert_eq(storage.deposit_reserved("unit.tank", "water", 50.0, authorization), 30.0)
	assert_eq(storage.deposit_reserved("unit.tank", "water", 1.0, authorization), 0.0)
	assert_eq(ledger.states["unit.tank"].current_liters, 100.0)
	assert_eq(ledger.states["unit.tank"].reserved_incoming_liters, 0.0)
	assert_eq_deep(storage.get_settlement_liquid_totals("unit.town", "water"), {
		"stored_liters": 100.0, "capacity_liters": 100.0,
	})


func test_capture_revokes_old_owner_proof_without_losing_stock() -> void:
	assert_eq(storage.reassign_settlement_owner("unit.town", "NewOwner"), 1)
	var captured: Dictionary = ledger.states["unit.tank"].duplicate(true)
	watch_signals(storage)

	assert_eq(storage.draw("unit.tank", "water", 2.5), 0.0)
	assert_eq(storage.draw("unit.tank", "water", 2.5, authorization), 0.0)
	assert_eq_deep(ledger.states["unit.tank"], captured)
	assert_eq_deep(storage.get_container_state("unit.tank"), captured)
	assert_signal_not_emitted(storage, "liquid_container_changed")
	authorization.owner_faction_name = "NewOwner"
	authorization.actor_faction_name = "NewOwner"
	assert_eq(storage.draw("unit.tank", "water", 2.5, authorization), 2.5)
	assert_eq(ledger.states["unit.tank"].current_liters, 57.5)
	assert_signal_emit_count(storage, "liquid_container_changed", 1)


func test_nonempty_container_refuses_liquid_mixing_without_mutation() -> void:
	var original: Dictionary = ledger.states["unit.tank"].duplicate(true)
	var totals := storage.get_settlement_liquid_totals("unit.town", "water")
	watch_signals(storage)

	assert_false(storage.assign_liquid("unit.tank", "beer", authorization))
	assert_eq(storage.deposit("unit.tank", "beer", 10.0, authorization), 0.0)
	assert_eq(storage.draw("unit.tank", "beer", 10.0, authorization), 0.0)
	assert_eq_deep(ledger.states["unit.tank"], original)
	assert_eq_deep(storage.get_container_state("unit.tank"), original)
	assert_eq_deep(storage.get_settlement_liquid_totals("unit.town", "water"), totals)
	assert_signal_not_emitted(storage, "liquid_container_changed")


func test_rejected_persistence_write_leaves_balance_indexes_and_observers_unchanged() -> void:
	var original: Dictionary = ledger.states["unit.tank"].duplicate(true)
	var totals := storage.get_settlement_liquid_totals("unit.town", "water")
	ledger.reject_writes = true
	watch_signals(storage)

	assert_eq(storage.draw("unit.tank", "water", 10.0, authorization), 0.0)
	assert_eq_deep(ledger.states["unit.tank"], original)
	assert_eq_deep(storage.get_container_state("unit.tank"), original)
	assert_eq_deep(storage.get_settlement_liquid_totals("unit.town", "water"), totals)
	assert_signal_not_emitted(storage, "liquid_container_changed")
	assert_signal_not_emitted(storage, "liquid_stock_changed")
	ledger.reject_writes = false
	assert_eq(storage.draw("unit.tank", "water", 10.0, authorization), 10.0)
	assert_eq(ledger.states["unit.tank"].current_liters, 50.0)
	assert_signal_emit_count(storage, "liquid_container_changed", 1)
