extends "res://tests/validation/test_case.gd"
## Fast controller ledger checks plus a real GECS/projection save-load round trip.
var _failures: Array[String] = []
var _checks := 0


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


func _initialize() -> void:
	await _run_unit_cases()
	await _run_authority_round_trip()
	for failure in _failures:
		push_error(failure)
	print("LIQUID_STORAGE_%s checks=%d" % ["OK" if _failures.is_empty() else "FAILED", _checks])
	quit(0 if _failures.is_empty() else 1)


func _authorization(container_id: String, owner: String) -> Dictionary:
	return {
		"liquid_container_id": container_id,
		"owner_faction_name": owner,
		"actor_faction_name": owner,
		"owner_access_approved": true,
		"theft_approved": false,
	}


func _run_unit_cases() -> void:
	var gecs := FakeGecs.new()
	var storage := LiquidStorageController.new()
	root.add_child(gecs)
	root.add_child(storage)
	storage._gecs = gecs
	storage._rebuild_indexes()
	var state := storage.ensure_container({
		"liquid_container_id": "town.tank",
		"settlement_id": "town",
		"facility_id": "town.tank_facility",
		"owner_faction_name": "player",
		"capacity_liters": 100.0,
	})
	_expect(not state.is_empty() and str(state.get("assigned_liquid_id", "")) == "", "unit: new container starts unassigned")
	var town_auth := _authorization("town.tank", "player")
	_expect(storage.assign_liquid("town.tank", "water", town_auth), "unit: assign water to empty tank")
	_expect(is_equal_approx(storage.deposit("town.tank", "water", 60.0, town_auth), 60.0), "unit: authorized deposit accepts 60 liters")
	_expect(is_equal_approx(storage.draw("town.tank", "water", 1.0), 0.0), "unit: missing authorization refuses draw")
	_expect(not storage.assign_liquid("town.tank", "beer", town_auth), "unit: nonempty tank refuses reassignment")
	_expect(is_equal_approx(storage.deposit("town.tank", "beer", 10.0, town_auth), 0.0), "unit: mixed-liquid deposit refused")
	var draw := storage.draw_from_settlement("town", "player", "water", 25.0, town_auth)
	_expect(is_equal_approx(float(draw.get("drawn", 0.0)), 25.0), "unit: settlement draw removes 25 liters")
	var totals := storage.get_settlement_liquid_totals("town", "water")
	_expect(is_equal_approx(float(totals.get("stored_liters", 0.0)), 35.0), "unit: settlement total after draw")
	_expect(is_equal_approx(float(totals.get("capacity_liters", 0.0)), 100.0), "unit: capacity total after draw")
	_expect(is_equal_approx(storage.restore_transactions(draw.get("transactions", []), 25.0, town_auth), 25.0), "unit: restore full transaction")
	var staged_notifications := [0]
	storage.liquid_container_changed.connect(func(container_id: String, _previous: Dictionary, _saved: Dictionary) -> void:
		if container_id == "town.tank":
			staged_notifications[0] += 1
	)
	var staged_draw := storage.draw_from_settlement_staged("town", "player", "water", 10.0, town_auth)
	_expect(is_equal_approx(float(staged_draw.get("drawn", 0.0)), 10.0) and staged_notifications[0] == 0, "unit: staged draw is silent")
	_expect(is_equal_approx(storage.restore_transactions_staged(staged_draw.get("transactions", []), 4.0, town_auth), 4.0) and staged_notifications[0] == 0, "unit: partial staged rollback is silent")
	storage.publish_staged_transactions(staged_draw.get("transactions", []))
	_expect(staged_notifications[0] == 1 and is_equal_approx(float(storage.get_container_state("town.tank").get("current_liters", 0.0)), 54.0), "unit: publish staged draw once with net debit")
	_expect(is_equal_approx(storage.restore_transactions(staged_draw.get("transactions", []), 6.0, town_auth), 6.0), "unit: restore remainder")
	_expect(storage._available_ids_by_scope.has(storage._scope_key("town", "player", "water")), "unit: nonempty tank indexed as available")
	_expect(is_equal_approx(storage.draw("town.tank", "water", 100.0, town_auth), 60.0), "unit: overdraw clamps to remaining amount")
	_expect(not storage._available_ids_by_scope.has(storage._scope_key("town", "player", "water")), "unit: empty tank leaves available index")
	_expect(storage.assign_liquid("town.tank", "beer", town_auth), "unit: empty tank can switch to beer")
	_expect(is_equal_approx(float(storage.get_settlement_liquid_totals("town", "water").get("capacity_liters", -1.0)), 0.0), "unit: old liquid capacity removed")
	_expect(is_equal_approx(float(storage.get_settlement_liquid_totals("town", "beer").get("capacity_liters", 0.0)), 100.0), "unit: new liquid capacity indexed")
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
	_expect(storage.bind_liquid_container(projection), "unit: projection binds existing tank")
	var rebound := storage.get_container_state("rebind.tank")
	_expect(str(rebound.get("settlement_id", "")) == "new_town" and str(rebound.get("facility_id", "")) == "new_facility" and str(rebound.get("owner_faction_name", "")) == "new_owner" and str(rebound.get("assigned_liquid_id", "")) == "water" and is_equal_approx(float(rebound.get("current_liters", 0.0)), 40.0) and is_equal_approx(float(rebound.get("capacity_liters", 0.0)), 120.0), "unit: rebind moves context but preserves durable contents")
	_expect(is_equal_approx(float(storage.get_settlement_liquid_totals("old_town", "water").get("stored_liters", 0.0)), 0.0), "unit: old town total removed on rebind")
	_expect(is_equal_approx(float(storage.get_settlement_liquid_totals("new_town", "water").get("stored_liters", 0.0)), 40.0), "unit: new town total added on rebind")
	_expect(storage.has_method("reassign_settlement_owner"), "unit: owner reassignment API")
	if storage.has_method("reassign_settlement_owner"):
		_expect(int(storage.call("reassign_settlement_owner", "new_town", "captured_owner")) == 1, "unit: capture updates one container")
		var captured := storage.get_container_state("rebind.tank")
		_expect(str(captured.get("owner_faction_name", "")) == "captured_owner", "unit: captured owner persisted")
		_expect(not storage._ids_by_scope.has(storage._scope_key("new_town", "new_owner", "water")), "unit: old owner scope removed")
		_expect(storage._ids_by_scope.has(storage._scope_key("new_town", "captured_owner", "water")), "unit: new owner scope added")
	var supports_reservations := storage.has_method("reserve_incoming") \
			and storage.has_method("release_incoming") and storage.has_method("deposit_reserved")
	_expect(supports_reservations, "unit: reservation API")
	if supports_reservations:
		var rebound_auth := _authorization("rebind.tank", "captured_owner")
		_expect(is_equal_approx(float(storage.call("reserve_incoming", "rebind.tank", "water", 50.0, rebound_auth)), 50.0), "unit: reserve incoming capacity")
		_expect(is_equal_approx(storage.deposit("rebind.tank", "water", 100.0, rebound_auth), 30.0), "unit: unreserved deposit cannot consume reserved room")
		_expect(is_equal_approx(float(storage.call("deposit_reserved", "rebind.tank", "water", 50.0, rebound_auth)), 50.0), "unit: reserved deposit commits reservation")
		_expect(is_equal_approx(float(storage.get_container_state("rebind.tank").get("current_liters", 0.0)), 120.0), "unit: reservation and deposit conserve capacity")
	var reindex_notifications: Array[Dictionary] = []
	storage.liquid_stock_changed.connect(func(settlement_id: String, facility_id: String, liquid_id: String) -> void:
		reindex_notifications.append({"settlement_id": settlement_id, "facility_id": facility_id, "liquid_id": liquid_id})
	)
	storage._on_world_reindexed()
	_expect(not reindex_notifications.is_empty(), "unit: reindex publishes changed scopes")
	reindex_notifications.clear()
	gecs.states.erase("rebind.tank")
	storage._on_world_reindexed()
	var rebound_after_missing_state := storage.get_container_state("rebind.tank")
	_expect(not rebound_after_missing_state.is_empty() and str(rebound_after_missing_state.get("settlement_id", "")) == "new_town" and str(rebound_after_missing_state.get("owner_faction_name", "")) == "captured_owner" and str(rebound_after_missing_state.get("assigned_liquid_id", "")) == "" and is_equal_approx(float(rebound_after_missing_state.get("current_liters", -1.0)), 0.0), "unit: missing durable record resets rebound contents")
	var orphan := LiquidContainer.new()
	orphan.liquid_container_id = "orphan.tank"
	root.add_child(orphan)
	_expect(not orphan.assign_liquid("water") and orphan.assigned_liquid_id.is_empty(), "unit: orphan without storage refuses assignment")
	orphan.queue_free()
	projection.queue_free()
	storage.queue_free()
	gecs.queue_free()
	await process_frame
	await process_frame


func _run_authority_round_trip() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var context := BootstrapContext.new(scene)
	BootstrapContext.active = context
	var gecs := GecsWorldController.new()
	scene.add_child(gecs)
	context.register(GecsWorldController.SERVICE_ID, gecs)
	gecs.initialize(context)
	gecs.set_process(false)
	var storage := LiquidStorageController.new()
	scene.add_child(storage)
	context.register(LiquidStorageController.SERVICE_ID, storage)
	storage.initialize(context)
	var tank := _make_tank("old_town", "old_owner", 100.0)
	tank.assigned_liquid_id = "water"
	tank.current_liters = 60.0
	scene.add_child(tank)
	await process_frame
	await process_frame
	_expect(storage.get_live_container_candidates("old_town", "water") == [tank], "authority: ready-time binding registers the real projection")
	_expect(is_equal_approx(float(gecs.get_liquid_container_state(tank.liquid_container_id).get("current_liters", -1)), 60.0), "authority: authored seed reaches real GECS")
	var auth := _authorization(tank.liquid_container_id, "old_owner")
	_expect(is_equal_approx(storage.draw(tank.liquid_container_id, "water", 17.5, auth), 17.5), "authority: draw updates stored amount")
	_expect(is_equal_approx(storage.reserve_incoming(tank.liquid_container_id, "water", 12.0, auth), 12.0), "authority: reserve capacity before projection loss")
	var old_id := tank.get_instance_id()
	tank.queue_free()
	await process_frame
	await process_frame
	_expect(not is_instance_id_valid(old_id) and storage.get_live_container_candidates("old_town", "water").is_empty(), "authority: projection destroyed and detached, not just hidden")
	_expect(is_equal_approx(float(gecs.get_liquid_container_state("authority.tank").get("current_liters", -1)), 42.5), "authority: GECS contents survive projection destruction")
	# New authorship owns location/capacity, never the previously drawn contents.
	tank = _make_tank("new_town", "new_owner", 120.0)
	tank.assigned_liquid_id = "beer"
	tank.current_liters = 90.0
	tank.position = Vector3(19, 2, -7)
	scene.add_child(tank)
	await process_frame
	await process_frame
	_expect(tank.get_instance_id() != old_id and tank.assigned_liquid_id == "water" and is_equal_approx(tank.current_liters, 42.5), "authority: remount restores water and consumed balance rather than authored beer")
	_expect(is_equal_approx(tank.reserved_incoming_liters, 12.0), "authority: rebind preserves incoming reservation")
	_expect(is_zero_approx(float(storage.get_settlement_liquid_totals("old_town", "water").get("stored_liters", -1))), "authority: rebind removes old settlement total")
	_expect(is_equal_approx(float(storage.get_settlement_liquid_totals("new_town", "water").get("stored_liters", -1)), 42.5), "authority: rebind counts contents once in new settlement")
	_expect(is_zero_approx(storage.draw("authority.tank", "water", 1.0, auth)), "authority: old-owner proof cannot draw after rebind")
	var expected := gecs.get_liquid_container_state("authority.tank")
	_expect(expected.get("settlement_id") == "new_town" and expected.get("facility_id") == "new_town.facility" and expected.get("owner_faction_name") == "new_owner" and expected.get("world_position") == tank.global_position and is_equal_approx(float(expected.get("capacity_liters", -1)), 120.0), "authority: new scope, moved position and authored capacity reach GECS")
	var save_path := "user://liquid_authority_%d.tres" % OS.get_process_id()
	_expect(gecs.save_gecs_world(save_path), "authority: save real container entities")
	var new_auth := _authorization("authority.tank", "new_owner")
	_expect(is_equal_approx(storage.draw("authority.tank", "water", 10.0, new_auth), 10.0), "authority: mutate after save")
	_expect(storage.reassign_settlement_owner("new_town", "captured") == 1, "authority: change owner after save")
	_expect(gecs.load_gecs_world(save_path), "authority: in-place load real GECS snapshot")
	await process_frame
	await process_frame
	_expect(gecs.get_liquid_container_state("authority.tank") == expected and storage.get_container_state("authority.tank") == expected, "authority: disk load restores exact authoritative and indexed state")
	_expect(tank.owner_faction_name == "new_owner" and is_equal_approx(tank.current_liters, 42.5) and is_equal_approx(tank.reserved_incoming_liters, 12.0), "authority: world_reindexed hydrates existing projection")
	var denied := storage.draw_from_settlement("new_town", "captured", "water", 1.0, _authorization("authority.tank", "captured"))
	_expect(denied.is_empty() and gecs.get_liquid_container_state("authority.tank") == expected, "authority: discarded owner scope cannot draw or mutate after load")
	var drawn := storage.draw_from_settlement("new_town", "new_owner", "water", 2.5, new_auth)
	_expect(is_equal_approx(float(drawn.get("drawn", -1)), 2.5) and is_equal_approx(tank.current_liters, 40.0), "authority: restored scope supports real post-load draw and hydration")
	_expect(gecs.get_liquid_container_states().size() == 1, "authority: unload/rebind/load never duplicates the tank")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	scene.queue_free()
	await process_frame
	await process_frame
	BootstrapContext.active = null


func _make_tank(town: String, owner_faction: String, capacity: float) -> LiquidContainer:
	var tank := LiquidContainer.new()
	tank.liquid_container_id = "authority.tank"
	tank.settlement_id = town
	tank.facility_id = town + ".facility"
	tank.owner_faction_name = owner_faction
	tank.capacity_liters = capacity
	return tank


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
