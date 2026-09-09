extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_liquid_storage.gd


class FakeGecs:
	extends Node
	signal world_reindexed
	var states: Dictionary = {}

	func get_liquid_container_states() -> Dictionary:
		return states.duplicate(true)

	func upsert_liquid_container_state(state: Dictionary) -> Dictionary:
		var container_id := str(state.get("liquid_container_id", ""))
		if container_id.is_empty():
			return {}
		states[container_id] = state.duplicate(true)
		return states[container_id].duplicate(true)

	func remove_liquid_container_state(container_id: String) -> void:
		states.erase(container_id)


class ProjectionFixture:
	extends Node3D
	var liquid_container_id := "rebind.tank"
	var settlement_id := "new_town"
	var facility_id := "new_facility"
	var owner_faction_name := "new_owner"
	var assigned_liquid_id := "beer"
	var capacity_liters := 120.0
	var current_liters := 0.0
	var reserved_incoming_liters := 0.0
	var reserved_outgoing_liters := 0.0

	func apply_liquid_state(state: Dictionary) -> void:
		settlement_id = str(state.get("settlement_id", settlement_id))
		facility_id = str(state.get("facility_id", facility_id))
		owner_faction_name = str(state.get("owner_faction_name", owner_faction_name))
		assigned_liquid_id = str(state.get("assigned_liquid_id", assigned_liquid_id))
		capacity_liters = float(state.get("capacity_liters", capacity_liters))
		current_liters = float(state.get("current_liters", current_liters))


func _init() -> void:
	call_deferred("_run")


func _authorization(container_id: String, owner: String) -> Dictionary:
	return {
		"liquid_container_id": container_id,
		"owner_faction_name": owner,
		"actor_faction_name": owner,
		"owner_access_approved": true,
		"theft_approved": false,
	}


func _run() -> void:
	var gecs := FakeGecs.new()
	var storage := LiquidStorageController.new()
	root.add_child(gecs)
	root.add_child(storage)
	storage._gecs = gecs
	storage._rebuild_indexes()
	var passed := true
	var state := storage.ensure_container({
		"liquid_container_id": "town.tank",
		"settlement_id": "town",
		"facility_id": "town.tank_facility",
		"owner_faction_name": "player",
		"capacity_liters": 100.0,
	})
	passed = passed and not state.is_empty() and str(state.get("assigned_liquid_id", "")) == ""
	var town_auth := _authorization("town.tank", "player")
	passed = passed and storage.assign_liquid("town.tank", "water", town_auth)
	passed = passed and is_equal_approx(storage.deposit("town.tank", "water", 60.0, town_auth), 60.0)
	passed = passed and is_equal_approx(storage.draw("town.tank", "water", 1.0), 0.0)
	passed = passed and not storage.assign_liquid("town.tank", "beer", town_auth)
	passed = passed and is_equal_approx(storage.deposit("town.tank", "beer", 10.0, town_auth), 0.0)
	var draw := storage.draw_from_settlement("town", "player", "water", 25.0, town_auth)
	passed = passed and is_equal_approx(float(draw.get("drawn", 0.0)), 25.0)
	var totals := storage.get_settlement_liquid_totals("town", "water")
	passed = passed and is_equal_approx(float(totals.get("stored_liters", 0.0)), 35.0)
	passed = passed and is_equal_approx(float(totals.get("capacity_liters", 0.0)), 100.0)
	passed = passed and is_equal_approx(storage.restore_transactions(draw.get("transactions", []), 25.0, town_auth), 25.0)
	var staged_notifications := [0]
	storage.liquid_container_changed.connect(func(container_id: String, _previous: Dictionary, _saved: Dictionary) -> void:
		if container_id == "town.tank":
			staged_notifications[0] += 1
	)
	var staged_draw := storage.draw_from_settlement_staged("town", "player", "water", 10.0, town_auth)
	passed = passed and is_equal_approx(float(staged_draw.get("drawn", 0.0)), 10.0) and staged_notifications[0] == 0
	passed = passed and is_equal_approx(storage.restore_transactions_staged(staged_draw.get("transactions", []), 4.0, town_auth), 4.0) \
			and staged_notifications[0] == 0
	storage.publish_staged_transactions(staged_draw.get("transactions", []))
	passed = passed and staged_notifications[0] == 1 \
			and is_equal_approx(float(storage.get_container_state("town.tank").get("current_liters", 0.0)), 54.0)
	passed = passed and is_equal_approx(storage.restore_transactions(staged_draw.get("transactions", []), 6.0, town_auth), 6.0)
	passed = passed and storage._available_ids_by_scope.has(storage._scope_key("town", "player", "water"))
	passed = passed and is_equal_approx(storage.draw("town.tank", "water", 100.0, town_auth), 60.0)
	passed = passed and not storage._available_ids_by_scope.has(storage._scope_key("town", "player", "water"))
	passed = passed and storage.assign_liquid("town.tank", "beer", town_auth)
	passed = passed and is_equal_approx(float(storage.get_settlement_liquid_totals("town", "water").get("capacity_liters", -1.0)), 0.0)
	passed = passed and is_equal_approx(float(storage.get_settlement_liquid_totals("town", "beer").get("capacity_liters", 0.0)), 100.0)
	storage.ensure_container({
		"liquid_container_id": "rebind.tank",
		"settlement_id": "old_town",
		"facility_id": "old_facility",
		"owner_faction_name": "old_owner",
		"assigned_liquid_id": "water",
		"capacity_liters": 100.0,
		"current_liters": 40.0,
	})
	var projection := ProjectionFixture.new()
	root.add_child(projection)
	passed = passed and storage.bind_liquid_container(projection)
	var rebound := storage.get_container_state("rebind.tank")
	passed = passed and str(rebound.get("settlement_id", "")) == "new_town" \
			and str(rebound.get("facility_id", "")) == "new_facility" \
			and str(rebound.get("owner_faction_name", "")) == "new_owner" \
			and str(rebound.get("assigned_liquid_id", "")) == "water" \
			and is_equal_approx(float(rebound.get("current_liters", 0.0)), 40.0) \
			and is_equal_approx(float(rebound.get("capacity_liters", 0.0)), 120.0)
	passed = passed and is_equal_approx(float(storage.get_settlement_liquid_totals("old_town", "water").get("stored_liters", 0.0)), 0.0)
	passed = passed and is_equal_approx(float(storage.get_settlement_liquid_totals("new_town", "water").get("stored_liters", 0.0)), 40.0)
	passed = passed and storage.has_method("reassign_settlement_owner")
	if storage.has_method("reassign_settlement_owner"):
		passed = passed and int(storage.call("reassign_settlement_owner", "new_town", "captured_owner")) == 1
		var captured := storage.get_container_state("rebind.tank")
		passed = passed and str(captured.get("owner_faction_name", "")) == "captured_owner"
		passed = passed and not storage._ids_by_scope.has(storage._scope_key("new_town", "new_owner", "water"))
		passed = passed and storage._ids_by_scope.has(storage._scope_key("new_town", "captured_owner", "water"))
	var supports_reservations := storage.has_method("reserve_incoming") \
			and storage.has_method("release_incoming") and storage.has_method("deposit_reserved")
	passed = passed and supports_reservations
	if supports_reservations:
		var rebound_auth := _authorization("rebind.tank", "captured_owner")
		passed = passed and is_equal_approx(float(storage.call("reserve_incoming", "rebind.tank", "water", 50.0, rebound_auth)), 50.0)
		passed = passed and is_equal_approx(storage.deposit("rebind.tank", "water", 100.0, rebound_auth), 30.0)
		passed = passed and is_equal_approx(float(storage.call("deposit_reserved", "rebind.tank", "water", 50.0, rebound_auth)), 50.0)
		passed = passed and is_equal_approx(float(storage.get_container_state("rebind.tank").get("current_liters", 0.0)), 120.0)
	var reindex_notifications: Array[Dictionary] = []
	storage.liquid_stock_changed.connect(func(settlement_id: String, facility_id: String, liquid_id: String) -> void:
		reindex_notifications.append({"settlement_id": settlement_id, "facility_id": facility_id, "liquid_id": liquid_id})
	)
	storage._on_world_reindexed()
	passed = passed and not reindex_notifications.is_empty()
	reindex_notifications.clear()
	gecs.states.erase("rebind.tank")
	storage._on_world_reindexed()
	var rebound_after_missing_state := storage.get_container_state("rebind.tank")
	passed = passed and not rebound_after_missing_state.is_empty() \
			and str(rebound_after_missing_state.get("settlement_id", "")) == "new_town" \
			and str(rebound_after_missing_state.get("owner_faction_name", "")) == "captured_owner" \
			and str(rebound_after_missing_state.get("assigned_liquid_id", "")) == "" \
			and is_equal_approx(float(rebound_after_missing_state.get("current_liters", -1.0)), 0.0)
	var orphan := LiquidContainer.new()
	orphan.liquid_container_id = "orphan.tank"
	root.add_child(orphan)
	passed = passed and not orphan.assign_liquid("water") and orphan.assigned_liquid_id.is_empty()
	orphan.queue_free()
	projection.queue_free()
	if not passed:
		push_error("generic liquid storage assignment, conservation, ownership scope, and ledger totals")
	storage.queue_free()
	gecs.queue_free()
	print("LIQUID_STORAGE_OK" if passed else "LIQUID_STORAGE_FAILED")
	quit(0 if passed else 1)
