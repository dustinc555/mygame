extends SceneTree
## Run: godot --headless --path . --script res://tests/validation/validate_farm_controller.gd

class FakeGecs:
	extends Node
	signal world_reindexed
	var states := {}
	var water_states := {}
	var farm_state_reads := 0
	var full_state_writes := 0
	var cell_state_reads := 0
	var cell_state_writes := 0
	var water_state_reads := 0
	var water_state_exact_reads := 0
	var water_state_writes := 0
	var fail_cell_writes := false
	func upsert_farm_plot_state(state: Dictionary) -> Dictionary:
		full_state_writes += 1
		states[str(state.get("plot_id", ""))] = state.duplicate(true)
		return states[str(state.get("plot_id", ""))].duplicate(true)
	func get_farm_plot_states() -> Dictionary:
		farm_state_reads += 1
		return states.duplicate(true)
	func remove_farm_plot_state(plot_id: String) -> void:
		states.erase(plot_id)
	func get_farm_plot_header_state(plot_id: String) -> Dictionary:
		var state: Dictionary = states.get(plot_id, {})
		if state.is_empty(): return {}
		var header := state.duplicate(true)
		header.erase("cells")
		header.erase("soil_remnants")
		return header
	func get_farm_plot_cell_record(plot_id: String, cell_key: String) -> Dictionary:
		cell_state_reads += 1
		var state: Dictionary = states.get(plot_id, {})
		if state.is_empty() or not (state.get("cells", {}) as Dictionary).has(cell_key): return {}
		return get_farm_plot_header_state(plot_id).merged({"cell_key": cell_key, "cell": (state["cells"][cell_key] as Dictionary).duplicate(true)}, true)
	func upsert_farm_plot_cells(plot_id: String, changed_cells: Dictionary) -> Dictionary:
		cell_state_writes += 1
		if fail_cell_writes:
			return {}
		var state: Dictionary = states.get(plot_id, {})
		var cells: Dictionary = state.get("cells", {})
		for key in changed_cells: cells[key] = (changed_cells[key] as Dictionary).duplicate(true)
		state["cells"] = cells
		state["state_revision"] = int(state.get("state_revision", 0)) + 1
		states[plot_id] = state
		return {"plot_id": plot_id, "settlement_id": state.get("settlement_id", ""), "state_revision": state["state_revision"], "cells": changed_cells.duplicate(true)}
	func upsert_farm_water_source_state(state: Dictionary) -> Dictionary:
		water_state_writes += 1
		water_states[str(state.get("source_id", ""))] = state.duplicate(true)
		return water_states[str(state.get("source_id", ""))].duplicate(true)
	func get_farm_water_source_states() -> Dictionary:
		water_state_reads += 1
		return water_states.duplicate(true)
	func get_farm_water_source_state(source_id: String) -> Dictionary:
		water_state_exact_reads += 1
		return (water_states.get(source_id, {}) as Dictionary).duplicate(true)
	func remove_farm_water_source_state(source_id: String) -> void:
		water_states.erase(source_id)

class FakeTime:
	extends Node
	signal minute_changed(absolute_minute: int, day: int, hour: int, minute: int)
	var absolute_minute := 0
	func get_absolute_minute() -> int:
		return absolute_minute

class FakeStock:
	extends Node
	var counts := {"seed.tomato": 1}
	var reject_additions := false
	func transact_item_count(_settlement_id: String, definition: ItemDefinition, count_delta: int, _facility_id := "") -> bool:
		if reject_additions and count_delta > 0:
			return false
		var item_id := definition.item_id if not definition.item_id.is_empty() else definition.resource_path
		var next := int(counts.get(item_id, 0)) + count_delta
		if next < 0:
			return false
		counts[item_id] = next
		return true

class FakeTerritory:
	extends Node
	func get_build_permission(_position: Vector3, _faction_id := "") -> Dictionary:
		return {"can_build": true}
	func get_build_permissions(positions: Array, _faction_id := "") -> Array[Dictionary]:
		var permissions: Array[Dictionary] = []
		for _position in positions:
			permissions.append({"can_build": true})
		return permissions

class FakeActor:
	extends Node
	var faction_name := ""
	var stable_id := "test-actor"

class FakeRetiringWork:
	extends Node
	var active_keys := PackedStringArray()
	var retired_plot_id := ""
	var controller: Node
	var queued_cell_key := ""
	var queued_revision := -1
	var queued_actor_id := ""
	func retire_plot_work(plot_id: String) -> PackedStringArray:
		retired_plot_id = plot_id
		if controller != null and not queued_cell_key.is_empty():
			controller.cancel_cell_operation(plot_id, queued_cell_key, queued_revision, queued_actor_id)
		return active_keys.duplicate()
	func get_active_cell_keys_for_plot(_plot_id: String) -> PackedStringArray:
		return active_keys.duplicate()

var failures: Array[String] = []
var plot_change_count := 0
var cell_change_count := 0


func _on_plot_changed(_plot_id: String, _state: Dictionary) -> void:
	plot_change_count += 1


func _on_plot_cells_changed(_plot_id: String, changed_cells: Dictionary, _settlement_id: String) -> void:
	cell_change_count += changed_cells.size()


func _init() -> void:
	var controller = load("res://features/farming/sim/farm_controller.gd").new()
	var gecs := FakeGecs.new()
	var time := FakeTime.new()
	var territory := FakeTerritory.new()
	var stock := FakeStock.new()
	root.add_child(gecs)
	root.add_child(time)
	root.add_child(territory)
	root.add_child(stock)
	root.add_child(controller)
	var controller_source := FileAccess.get_file_as_string("res://features/farming/sim/farm_controller.gd")
	var register_source_body := controller_source.get_slice("func register_water_source", 1).get_slice("func get_water_source", 0)
	_expect(not register_source_body.contains("_advance_water_sources("), "rebinding one projected water source never scans every durable source")
	controller.plot_changed.connect(_on_plot_changed)
	_expect(controller.has_signal("plot_cells_changed"), "FarmController exposes batched cell completion deltas")
	if controller.has_signal("plot_cells_changed"):
		controller.connect("plot_cells_changed", _on_plot_cells_changed)
	controller._gecs = gecs
	controller._world_time = time
	controller._territory = territory
	controller._inventory_stock = stock
	for crop_id in controller.CROP_PATHS:
		controller._crops[crop_id] = load(controller.CROP_PATHS[crop_id])
	_assert_create_plot_size_limits(controller, gecs)
	var positions: Array[Vector3] = [Vector3.ZERO, Vector3(1.25, 0, 0)]
	var plot: Dictionary = controller.create_plot(positions, Vector2i(2, 1), "tomato", "Player")
	_expect(not plot.is_empty(), "creates a durable plot")
	_expect((plot.get("cells", {}) as Dictionary).size() == 2, "creates one state record per cell")
	_expect(controller.create_plot(positions, Vector2i(2, 1), "wheat", "Player").is_empty(), "durable field authority rejects world-space overlap with an existing field")
	var painted_positions: Array[Vector3] = [Vector3(5.0, 0, 5.0), Vector3(6.25, 0, 5.0), Vector3(6.25, 0, 6.25)]
	var painted: Dictionary = controller.create_plot(painted_positions, Vector2i(2, 2), "tomato", "Player", "", {}, PackedStringArray(["0:0", "1:0", "1:1"]))
	_expect((painted.get("cells", {}) as Dictionary).size() == 3 and not (painted.get("cells", {}) as Dictionary).has("0:1"), "painted plot persists only painted cells")
	plot_change_count = 0
	cell_change_count = 0
	controller.call("_on_minute_changed", 1, 0, 0, 1)
	_expect(plot_change_count == 0 and cell_change_count == 5, "world-minute initialization publishes one cell batch instead of full plots")
	plot_change_count = 0
	cell_change_count = 0
	controller.call("_on_minute_changed", 2, 0, 0, 2)
	_expect(plot_change_count == 0 and cell_change_count == 0, "unchanged world-minute catch-up emits no projection or offer invalidation")
	var query_positions: Array[Vector3] = []
	for index in 128:
		query_positions.append(Vector3(float(index) * 1.25, 0.0, 50.0))
	gecs.farm_state_reads = 0
	var query_results: Array = controller.find_plot_cells_at_world_positions(query_positions)
	_expect(query_results.size() == query_positions.size() and gecs.farm_state_reads == 1, "batched occupancy query reconstructs GECS farm state once")
	controller.request_cell_operation(str(plot.plot_id), "0:0", "till")
	var work: Dictionary = controller.get_next_work(str(plot.plot_id))
	_expect(str(work.get("action", "")) == "till" and str(work.get("cell_key", "")) == "0:0", "individual till exposes only its requested cell")
	var world_positions: Array[Vector3] = [Vector3(20.0, 0.0, 20.0)]
	var world_plot: Dictionary = controller.create_plot(world_positions, Vector2i.ONE, "", "Player", "world_town")
	controller.request_cell_operation(str(world_plot.get("plot_id", "")), "0:0", "till")
	_expect(controller.has_method("advance_world_sim_work"), "FarmController exposes one aggregate world-sim labor entry point")
	if controller.has_method("advance_world_sim_work"):
		var world_summary: Dictionary = controller.call("advance_world_sim_work", "world_town", 60.0)
		var world_cell: Dictionary = controller.get_cell(str(world_plot.get("plot_id", "")), "0:0")
		_expect(str(world_cell.get("state", "")) == "tilled" and int(world_summary.get("completed_actions", 0)) == 1, "aggregate labor completes exact durable farm cells")
	var reserved_positions: Array[Vector3] = [Vector3(30.0, 0.0, 30.0)]
	var reserved_plot: Dictionary = controller.create_plot(reserved_positions, Vector2i.ONE, "", "Player", "world_town")
	controller.request_cell_operation(str(reserved_plot.get("plot_id", "")), "0:0", "till", "", PackedStringArray(["selected.actor"]))
	var reserved_before: Dictionary = controller.get_cell(str(reserved_plot.get("plot_id", "")), "0:0")
	if controller.has_method("advance_world_sim_work"):
		controller.call("advance_world_sim_work", "world_town", 60.0)
		_expect(controller.get_cell(str(reserved_plot.get("plot_id", "")), "0:0") == reserved_before, "world sim never mutates actor-reserved manual work")
	controller.remove_plot(str(world_plot.get("plot_id", "")))
	controller.remove_plot(str(reserved_plot.get("plot_id", "")))
	var maintenance_positions: Array[Vector3] = [Vector3(35.0, 0.0, 35.0), Vector3(36.25, 0.0, 35.0), Vector3(37.5, 0.0, 35.0)]
	var maintenance_plot: Dictionary = controller.create_plot(maintenance_positions, Vector2i(3, 1), "tomato", "Player", "world_town")
	var maintenance_state: Dictionary = controller.get_plot(str(maintenance_plot.get("plot_id", "")))
	for cell_key in ["0:0", "1:0"]:
		maintenance_state["cells"][cell_key] = controller.FARM_SIMULATION.complete_planting(
			controller.FARM_SIMULATION.complete_tilling(maintenance_state["cells"][cell_key]),
			"tomato",
			0.0
		)
	controller.call("_save_plot", maintenance_state)
	controller.register_water_source({
		"source_id": "world_town.water_tank",
		"settlement_id": "world_town",
		"source_kind": "storage",
		"owner_faction_name": "Player",
		"renewable": false,
		"capacity": 20.0,
		"current_water": 6.0,
		"recharge_per_world_minute": 0.0,
		"last_processed_minute": 0,
	})
	controller.register_water_source({
		"source_id": "world_town.well_1",
		"settlement_id": "world_town",
		"source_kind": "well",
		"owner_faction_name": "Player",
		"renewable": false,
		"capacity": 120.0,
		"current_water": 120.0,
		"recharge_per_world_minute": 1.0,
		"last_processed_minute": 0,
	})
	controller.register_water_source({
		"source_id": "identity_source",
		"settlement_id": "old_town",
		"source_kind": "storage",
		"owner_faction_name": "FormerOwner",
		"renewable": false,
		"capacity": 10.0,
		"current_water": 4.0,
	})
	controller.register_water_source({
		"source_id": "identity_source",
		"settlement_id": "new_town",
		"source_kind": "well",
		"owner_faction_name": "NewOwner",
		"renewable": false,
		"capacity": 10.0,
		"current_water": 10.0,
	})
	var reassigned_source: Dictionary = controller.get_water_source("identity_source")
	_expect(str(reassigned_source.get("settlement_id", "")) == "new_town" \
			and str(reassigned_source.get("source_kind", "")) == "well" \
			and str(reassigned_source.get("owner_faction_name", "")) == "NewOwner" \
			and is_equal_approx(float(reassigned_source.get("current_water", 0.0)), 4.0), "projected water-source identity updates without resetting durable water")
	_expect(controller.has_method("reassign_settlement_water_owner"), "water infrastructure exposes durable settlement capture")
	if controller.has_method("reassign_settlement_water_owner"):
		_expect(int(controller.call("reassign_settlement_water_owner", "new_town", "CapturedOwner")) == 1 \
				and str(controller.get_water_source("identity_source").get("owner_faction_name", "")) == "CapturedOwner", \
				"settlement capture updates off-screen durable water ownership")
	_expect(controller.has_method("remove_water_source"), "water infrastructure exposes explicit durable demolition")
	if controller.has_method("remove_water_source"):
		controller.call("remove_water_source", "identity_source")
		_expect(controller.get_water_source("identity_source").is_empty(), "explicit water-source demolition removes durable state")
	_expect(controller.has_method("get_settlement_water_status"), "FarmController exposes settlement water ledger metrics")
	if controller.has_method("get_settlement_water_status"):
		var water_status: Dictionary = controller.call("get_settlement_water_status", "world_town")
		_expect(is_equal_approx(float(water_status.get("well_output_per_day", -1.0)), 288.0), "water ledger totals capped same-town well recharge per day")
		_expect(is_equal_approx(float(water_status.get("stored_water", -1.0)), 6.0) and is_equal_approx(float(water_status.get("storage_capacity", -1.0)), 20.0), "water ledger totals same-town tank reserve and capacity")
		_expect(is_equal_approx(float(water_status.get("crop_demand_per_day", -1.0)), 34.56), "water ledger derives daily demand from growing crop cells")
		_expect(is_equal_approx(float(water_status.get("daily_shortfall", -1.0)), 0.0), "water ledger reports the daily supply shortfall")
	controller.register_water_source({
		"source_id": "world_town.aaa_raider_tank",
		"settlement_id": "world_town",
		"source_kind": "storage",
		"owner_faction_name": "Raiders",
		"renewable": false,
		"capacity": 10.0,
		"current_water": 10.0,
	})
	controller.request_cell_operation(str(maintenance_plot.get("plot_id", "")), "0:0", "water")
	controller.request_cell_operation(str(maintenance_plot.get("plot_id", "")), "1:0", "water")
	controller.request_cell_operation(str(maintenance_plot.get("plot_id", "")), "2:0", "till")
	gecs.water_state_writes = 0
	var water_signal_saw_durable_crop := [false]
	controller.water_source_changed.connect(func(source_id: String, _source_state: Dictionary) -> void:
		if source_id == "world_town.water_tank":
			water_signal_saw_durable_crop[0] = float(controller.get_cell(
					str(maintenance_plot.get("plot_id", "")), "0:0").get("water", 0.0)) > 0.0
	, CONNECT_ONE_SHOT)
	var maintenance_summary: Dictionary = controller.advance_world_sim_work("world_town", 4.0)
	_expect(is_equal_approx(float(controller.get_cell(str(maintenance_plot.get("plot_id", "")), "0:0").get("water", 0.0)), 5.0) \
			and is_equal_approx(float(controller.get_cell(str(maintenance_plot.get("plot_id", "")), "1:0").get("water", 0.0)), 1.0), "off-screen watering applies only exact liters drawn from town storage")
	_expect(is_equal_approx(float(controller.get_water_source("world_town.water_tank").get("current_water", -1.0)), 0.0) \
			and is_equal_approx(float(maintenance_summary.get("consumed_water", -1.0)), 6.0), "off-screen crop water is conserved against durable storage")
	_expect(is_equal_approx(float(controller.get_water_source("world_town.aaa_raider_tank").get("current_water", -1.0)), 10.0), "off-screen farming cannot drain another faction's storage")
	_expect(gecs.water_state_writes == 1, "off-screen watering persists one batched storage mutation instead of one write per cell")
	_expect(water_signal_saw_durable_crop[0], "off-screen watering publishes storage changes only after matching crop cells are durable")
	gecs.water_state_reads = 0
	gecs.water_state_exact_reads = 0
	controller.get_water_source("world_town.water_tank")
	_expect(gecs.water_state_reads == 0 and gecs.water_state_exact_reads == 1, "exact water-source reads use the maintained durable index")
	_expect(str(controller.get_cell(str(maintenance_plot.get("plot_id", "")), "2:0").get("state", "")) == "tilled" \
			and is_equal_approx(float(maintenance_summary.get("spent_labor_seconds", 0.0)), 4.0), "off-screen watering spends no labor needed for field development")
	var storage_authorization := {"source_id": "world_town.water_tank", "owner_faction_name": "Player", "actor_faction_name": "Player", "owner_access_approved": true, "theft_approved": false}
	controller.call("deposit_water_source", "world_town.water_tank", 5.0, storage_authorization)
	controller.call("reserve_water_source_outgoing", "world_town.water_tank", 2.0, storage_authorization)
	var reserved_tank_state: Dictionary = controller.get_water_source("world_town.water_tank")
	var unreserved_draw: Dictionary = controller.call("_draw_settlement_storage", "world_town", "Player", 2.0)
	_expect(is_equal_approx(float(unreserved_draw.get("drawn", 0.0)), 2.0) \
			and is_equal_approx(float(controller.get_water_source("world_town.water_tank").get("current_water", -1.0)), 3.0) \
			and is_equal_approx(float(controller.get_water_source("world_town.water_tank").get("reserved_outgoing_water", -1.0)), 2.0), "off-screen watering draws only unreserved water without consuming haul reservations")
	controller.call("_restore_water_transactions", unreserved_draw.get("transactions", []), 2.0)
	reserved_tank_state = controller.get_water_source("world_town.water_tank")
	_expect(is_equal_approx(float(reserved_tank_state.get("current_water", -1.0)), 5.0) \
			and is_equal_approx(float(reserved_tank_state.get("reserved_outgoing_water", -1.0)), 2.0), "off-screen rollback restores water without changing haul reservations")
	var renewable_storage := reserved_tank_state.duplicate(true)
	renewable_storage["source_id"] = "world_town.renewable_storage"
	renewable_storage["renewable"] = true
	renewable_storage["current_water"] = 0.0
	renewable_storage["reserved_outgoing_water"] = 0.0
	gecs.upsert_farm_water_source_state(renewable_storage)
	controller.call("_rebuild_water_storage_index")
	var renewable_draw: Dictionary = controller.call("_draw_settlement_storage", "world_town", "Player", 7.0)
	_expect(is_equal_approx(float(renewable_draw.get("drawn", 0.0)), 7.0) \
			and is_equal_approx(float(controller.get_water_source("world_town.renewable_storage").get("current_water", -1.0)), 0.0), "off-screen legacy renewable storage matches projected unlimited draws")
	controller.remove_water_source("world_town.renewable_storage")
	controller.call("release_water_source_outgoing", "world_town.water_tank", 2.0)
	var failed_water_state: Dictionary = controller.get_plot(str(maintenance_plot.get("plot_id", "")))
	failed_water_state["cells"]["0:0"]["water"] = 0.0
	controller.call("_save_plot", failed_water_state)
	var tank_state: Dictionary = controller.get_water_source("world_town.water_tank")
	tank_state["current_water"] = 5.0
	gecs.upsert_farm_water_source_state(tank_state)
	controller.request_cell_operation(str(maintenance_plot.get("plot_id", "")), "0:0", "water")
	gecs.fail_cell_writes = true
	var failed_water_summary: Dictionary = controller.advance_world_sim_work("world_town", 0.1)
	gecs.fail_cell_writes = false
	_expect(is_equal_approx(float(controller.get_cell(str(maintenance_plot.get("plot_id", "")), "0:0").get("water", -1.0)), 0.0) \
			and is_equal_approx(float(controller.get_water_source("world_town.water_tank").get("current_water", -1.0)), 5.0) \
			and is_equal_approx(float(failed_water_summary.get("consumed_water", -1.0)), 0.0), "failed farm persistence restores water to durable storage")
	controller.remove_plot(str(maintenance_plot.get("plot_id", "")))
	var stock_positions: Array[Vector3] = [Vector3(40.0, 0.0, 40.0)]
	var stock_plot: Dictionary = controller.create_plot(stock_positions, Vector2i.ONE, "tomato", "Player", "world_town")
	controller.request_cell_operation(str(stock_plot.get("plot_id", "")), "0:0", "till")
	controller.advance_world_sim_work("world_town", 60.0)
	controller.advance_world_sim_work("world_town", 60.0)
	_expect(str(controller.get_cell(str(stock_plot.get("plot_id", "")), "0:0").get("state", "")) == "growing" and int(stock.counts.get("seed.tomato", 0)) == 0, "world-sim planting consumes durable seed stock exactly once")
	controller.debug_crop_action_at(stock_positions[0], true)
	controller.request_cell_operation(str(stock_plot.get("plot_id", "")), "0:0", "harvest")
	stock.reject_additions = true
	controller.advance_world_sim_work("world_town", 60.0)
	_expect(str(controller.get_cell(str(stock_plot.get("plot_id", "")), "0:0").get("state", "")) == "ripe" and int(stock.counts.get("food.tomato", 0)) == 0, "world-sim harvest preserves the ripe crop when durable storage is full")
	stock.reject_additions = false
	gecs.fail_cell_writes = true
	var failed_commit_summary: Dictionary = controller.advance_world_sim_work("world_town", 60.0)
	_expect(str(controller.get_cell(str(stock_plot.get("plot_id", "")), "0:0").get("state", "")) == "ripe" and int(stock.counts.get("food.tomato", 0)) == 0 and int(failed_commit_summary.get("completed_actions", 0)) == 0, "failed farm persistence rolls back world-sim produce and reports no completion")
	gecs.fail_cell_writes = false
	controller.advance_world_sim_work("world_town", 60.0)
	_expect(str(controller.get_cell(str(stock_plot.get("plot_id", "")), "0:0").get("state", "")) == "tilled" and int(stock.counts.get("food.tomato", 0)) > 0, "world-sim harvesting deposits durable produce before clearing the crop")
	controller.remove_plot(str(stock_plot.get("plot_id", "")))
	plot_change_count = 0
	cell_change_count = 0
	gecs.full_state_writes = 0
	gecs.cell_state_reads = 0
	gecs.cell_state_writes = 0
	var partial: Dictionary = controller.apply_work(str(plot.plot_id), str(work.cell_key), "till", 1.0)
	_expect(not bool(partial.get("completed", true)), "short work preserves partial progress")
	_expect(plot_change_count == 0 and cell_change_count == 0, "partial progress emits no offer or projection invalidation")
	_expect(gecs.full_state_writes == 0 and gecs.cell_state_reads == 1 and gecs.cell_state_writes == 1, "worker progress persists through indexed cell IO instead of copying the full plot")
	var persisted: Dictionary = controller.get_plot(str(plot.plot_id))
	_expect(float((persisted.cells[work.cell_key] as Dictionary).work_progress) > 0.0, "partial progress persists in GECS state")
	var completed: Dictionary = controller.apply_work(str(plot.plot_id), str(work.cell_key), "till", 20.0)
	_expect(bool(completed.get("completed", false)), "enough work completes tilling")
	_expect(plot_change_count == 0 and cell_change_count == 1, "completion emits one cell delta without broadcasting the whole plot")
	persisted = controller.get_plot(str(plot.plot_id))
	_expect(str((persisted.cells[work.cell_key] as Dictionary).state) == "tilled", "completed tilling changes only its cell")
	controller.refresh_obstacle(str(plot.plot_id), str(work.cell_key), true, "temporary rock")
	controller.refresh_obstacle(str(plot.plot_id), str(work.cell_key), false)
	persisted = controller.get_plot(str(plot.plot_id))
	_expect(str((persisted.cells[work.cell_key] as Dictionary).state) == "tilled", "temporary obstruction restores the displaced cell state")
	controller.request_cell_operation(str(plot.plot_id), str(work.cell_key), "plant", "bell_pepper")
	var plant_work: Dictionary = controller.get_cell_work(str(plot.plot_id), str(work.cell_key))
	_expect(str(plant_work.get("crop_id", "")) == "bell_pepper", "individual plant order stores its selected crop on that cell")
	var bell_request_revision := int(plant_work.get("request_revision", -1))
	controller.request_cell_operation(str(plot.plot_id), str(work.cell_key), "plant", "tomato")
	_expect(controller.apply_work(str(plot.plot_id), str(work.cell_key), "plant", 20.0, 0.0, bell_request_revision).is_empty(), "reissued Plant crop invalidates the old seed/work transaction")
	_expect(str(controller.get_cell_work(str(plot.plot_id), str(work.cell_key)).get("crop_id", "")) == "tomato", "reissued Plant order exposes only its latest crop transaction")
	var owner := FakeActor.new()
	owner.faction_name = "Player"
	var outsider := FakeActor.new()
	outsider.faction_name = "Raiders"
	var retiring_work := FakeRetiringWork.new()
	root.add_child(retiring_work)
	retiring_work.controller = controller
	var controller_context := BootstrapContext.new(root)
	controller_context.register(&"farm_work", retiring_work)
	controller._context = controller_context
	_expect(controller.has_method("prepare_plot_till"), "selected fields expose one whole-field till transaction")
	if controller.has_method("prepare_plot_till"):
		var whole_positions: Array[Vector3] = [Vector3(70.0, 0.0, 70.0), Vector3(71.25, 0.0, 70.0), Vector3(72.5, 0.0, 70.0)]
		var whole_plot: Dictionary = controller.create_plot(whole_positions, Vector2i(3, 1), "", "Player")
		var whole_state: Dictionary = controller.get_plot(str(whole_plot.get("plot_id", "")))
		whole_state["cells"]["1:0"] = controller.FARM_SIMULATION.complete_tilling(whole_state["cells"]["1:0"])
		whole_state["cells"]["2:0"] = controller.FARM_SIMULATION.block_cell(whole_state["cells"]["2:0"], "occupied")
		controller.call("_save_plot", whole_state)
		var whole_order: Dictionary = controller.call("prepare_plot_till", str(whole_plot.get("plot_id", "")), owner)
		var whole_targets: Array = whole_order.get("targets", [])
		_expect(whole_targets.size() == 1 and str((whole_targets[0] as Dictionary).get("cell_key", "")) == "0:0", "whole-field Till skips cultivated and blocked cells")
		_expect(controller.call("prepare_plot_till", str(whole_plot.get("plot_id", "")), outsider).is_empty(), "whole-field Till is owner-gated")
		var plant_positions: Array[Vector3] = [Vector3(75.0, 0.0, 70.0), Vector3(76.25, 0.0, 70.0), Vector3(77.5, 0.0, 70.0)]
		var plant_plot: Dictionary = controller.create_plot(plant_positions, Vector2i(3, 1), "", "Player")
		var plant_state: Dictionary = controller.get_plot(str(plant_plot.get("plot_id", "")))
		plant_state["cells"]["0:0"] = controller.FARM_SIMULATION.complete_tilling(plant_state["cells"]["0:0"])
		plant_state["cells"]["1:0"] = controller.FARM_SIMULATION.complete_tilling(plant_state["cells"]["1:0"])
		controller.call("_save_plot", plant_state)
		var actor_ids := PackedStringArray([owner.stable_id])
		var plant_order: Dictionary = controller.prepare_plot_operation(str(plant_plot.get("plot_id", "")), "plant", "tomato", actor_ids, "1:0")
		var plant_targets: Array = plant_order.get("targets", [])
		_expect(plant_targets.size() == 2 and str((plant_targets[0] as Dictionary).get("cell_key", "")) == "1:0", "Shift Plant targets every valid tilled cell and starts with the clicked slot")
		_expect(PackedStringArray(controller.get_cell_work(str(plant_plot.get("plot_id", "")), "0:0").get("allowed_actor_ids", PackedStringArray())) == actor_ids \
				and controller.get_cell_work(str(plant_plot.get("plot_id", "")), "2:0").is_empty(), "field-wide manual work is actor-reserved and skips cells where that action is invalid")
		_expect(controller.prepare_plot_operation(str(plant_plot.get("plot_id", "")), "plant", "tomato", actor_ids, "2:0").is_empty(), "a stale invalid clicked slot rejects the whole Shift action instead of fanning out elsewhere")
		var harvest_positions: Array[Vector3] = [Vector3(75.0, 0.0, 75.0), Vector3(76.25, 0.0, 75.0)]
		var harvest_plot: Dictionary = controller.create_plot(harvest_positions, Vector2i(2, 1), "", "Player")
		var harvest_state: Dictionary = controller.get_plot(str(harvest_plot.get("plot_id", "")))
		harvest_state["cells"]["0:0"]["state"] = "ripe"
		harvest_state["cells"]["0:0"]["crop_id"] = "tomato"
		harvest_state["cells"]["1:0"]["state"] = "ripe"
		harvest_state["cells"]["1:0"]["crop_id"] = "wheat"
		controller.call("_save_plot", harvest_state)
		harvest_state = controller.get_plot(str(harvest_plot.get("plot_id", "")))
		harvest_state["cells"]["0:0"]["state"] = "growing"
		harvest_state["cells"]["0:0"]["growth"] = 0.0
		harvest_state["cells"]["0:0"]["stage_index"] = 0
		controller.call("_save_plot", harvest_state)
		var advanced_crop: Dictionary = controller.debug_crop_action_at(harvest_positions[0])
		_expect(bool(advanced_crop.get("success", false)) and int(controller.get_cell(str(harvest_plot.get("plot_id", "")), "0:0").get("stage_index", 0)) == 1, "debug Advance Crop advances only the clicked crop one stage")
		var full_grown_crop: Dictionary = controller.debug_crop_action_at(harvest_positions[0], true)
		_expect(bool(full_grown_crop.get("success", false)) and str(controller.get_cell(str(harvest_plot.get("plot_id", "")), "0:0").get("state", "")) == "ripe", "debug Full Grow Crop makes only the clicked crop ripe")
		var harvest_order: Dictionary = controller.prepare_plot_operation(str(harvest_plot.get("plot_id", "")), "harvest", "", actor_ids, "0:0", owner)
		var harvest_targets: Array = harvest_order.get("targets", [])
		_expect(harvest_targets.size() == 1 and str((harvest_targets[0] as Dictionary).get("cell_key", "")) == "0:0", "Shift Harvest skips mixed-crop cells whose required tool the selected actor cannot equip")
	_expect(controller.has_method("plot_cell_keys_in_rectangle"), "field subtraction can clip a rectangle to exact sparse membership")
	if controller.has_method("plot_cell_keys_in_rectangle"):
		var clipped: PackedStringArray = controller.call("plot_cell_keys_in_rectangle", str(painted.get("plot_id", "")), Vector3(5.0, 0.0, 5.0), Vector3(6.25, 0.0, 6.25))
		_expect(clipped.size() == 3 and not clipped.has("0:1"), "subtraction preview excludes non-field cells inside its rectangle")
	_expect(controller.has_method("delete_field"), "owned selected fields expose logical deletion")
	if controller.has_method("delete_field"):
		var deletion_positions: Array[Vector3] = [Vector3(80.0, 0.0, 80.0), Vector3(81.25, 0.0, 80.0), Vector3(82.5, 0.0, 80.0)]
		var deletion_plot: Dictionary = controller.create_plot(deletion_positions, Vector2i(3, 1), "tomato", "Player")
		var deletion_id := str(deletion_plot.get("plot_id", ""))
		var deletion_state: Dictionary = controller.get_plot(deletion_id)
		deletion_state["cells"]["0:0"] = controller.FARM_SIMULATION.complete_planting(controller.FARM_SIMULATION.complete_tilling(deletion_state["cells"]["0:0"]), "tomato", 20.0)
		deletion_state["cells"]["1:0"] = controller.FARM_SIMULATION.complete_tilling(deletion_state["cells"]["1:0"])
		controller.call("_save_plot", deletion_state)
		controller.request_cell_operation(deletion_id, "2:0", "till")
		var queued_request: Dictionary = controller.request_cell_operation(deletion_id, "1:0", "plant", "tomato", PackedStringArray(["owner-test"]))
		var queued_revision := int((queued_request.get("cells", {}) as Dictionary)["1:0"].get("request_revision", -1))
		retiring_work.queued_cell_key = "1:0"
		retiring_work.queued_revision = queued_revision
		retiring_work.queued_actor_id = "owner-test"
		retiring_work.active_keys = PackedStringArray(["2:0"])
		_expect(controller.call("delete_field", deletion_id, outsider).is_empty(), "another faction cannot delete the field")
		var deleted: Dictionary = controller.call("delete_field", deletion_id, owner)
		_expect(bool(deleted.get("field_deleted", false)), "deletion retires the logical field immediately")
		_expect((deleted.get("cells", {}) as Dictionary).size() == 3, "deletion preserves living crops, cultivated soil, and the active physical cell")
		_expect(not bool(controller.call("is_active_field", deleted)), "deleted remnant state is no longer a field")
		_expect(str(controller.get_cell(deletion_id, "1:0").get("requested_operation", "")).is_empty() and int(controller.get_cell(deletion_id, "1:0").get("request_revision", -1)) > queued_revision, "delete refetches queue-cancellation revisions instead of overwriting them with a stale snapshot")
		_expect(controller.get_next_work(deletion_id).is_empty(), "deleted remnants cannot publish new automatic work claims")
		_expect(retiring_work.retired_plot_id == deletion_id, "deletion retires the field work queue immediately")
		var active_work: Dictionary = controller.get_cell_work(deletion_id, "2:0")
		var active_finish: Dictionary = controller.apply_work(deletion_id, "2:0", "till", 20.0, 0.0, int(active_work.get("request_revision", -1)))
		_expect(bool(active_finish.get("completed", false)) and bool(controller.get_cell(deletion_id, "2:0").get("soil_created", false)), "the active cell can finish after logical field deletion")
		var retired_plant_request: Dictionary = controller.request_cell_operation(deletion_id, "1:0", "plant", "tomato", PackedStringArray(["owner-test"]))
		_expect(controller.get_next_work(deletion_id).is_empty(), "direct retired-cell work never becomes an automatic field offer")
		var retired_plant_work: Dictionary = controller.get_cell_work(deletion_id, "1:0")
		var retired_plant_finish: Dictionary = controller.apply_work(deletion_id, "1:0", "plant", 20.0, 0.0, int(retired_plant_work.get("request_revision", -1)))
		_expect(not retired_plant_request.is_empty() and bool(retired_plant_finish.get("completed", false)), "direct Plant remains functional on physical tilled soil after field deletion")
		var replanned: Dictionary = controller.create_plot(deletion_positions, Vector2i(3, 1), "", "Player")
		var replanned_cells: Dictionary = replanned.get("cells", {})
		_expect(controller.is_active_field(replanned) and replanned_cells.size() == 3, "a field can be redrawn directly over retired cultivated cells")
		_expect(str((replanned_cells.get("0:0", {}) as Dictionary).get("crop_id", "")) == "tomato" and str((replanned_cells.get("1:0", {}) as Dictionary).get("crop_id", "")) == "tomato", "redrawing preserves existing plants instead of replacing physical cell state")
		var fresh_position := Vector3(80.0, 0.0, 81.25)
		var fresh_positions: Array[Vector3] = [fresh_position]
		var fresh_order: Dictionary = controller.prepare_manual_till(fresh_positions, owner, fresh_position)
		var fresh_id := str(fresh_order.get("plot_id", ""))
		_expect(not fresh_id.is_empty() and fresh_id != deletion_id and controller.is_active_field(fresh_id), "new tilling beside remnants starts a new field instead of reviving deleted identity")
		var interrupted_position := Vector3(85.0, 0.0, 80.0)
		var interrupted_positions: Array[Vector3] = [interrupted_position]
		var interrupted_plot: Dictionary = controller.create_plot(interrupted_positions, Vector2i.ONE, "", "Player")
		var interrupted_id := str(interrupted_plot.get("plot_id", ""))
		controller.request_cell_operation(interrupted_id, "0:0", "till")
		retiring_work.active_keys = PackedStringArray(["0:0"])
		controller.delete_field(interrupted_id, owner)
		var interrupted_revision := int(controller.get_cell(interrupted_id, "0:0").get("request_revision", -1))
		retiring_work.active_keys.clear()
		controller.call("_reconcile_deleted_requests", controller.get_plot(interrupted_id))
		_expect(controller.get_cell_work(interrupted_id, "0:0").is_empty() and int(controller.get_cell(interrupted_id, "0:0").get("request_revision", -1)) > interrupted_revision, "reload interruption cancels and invalidates a retired active-cell request that no worker still owns")
		var offer_bridge = load("res://features/farming/bridge/farm_work_bridge.gd").new()
		offer_bridge._farm = controller
		root.add_child(offer_bridge)
		var deleted_offer_found := false
		for offer_value in offer_bridge.get_available_work_offers():
			if str((offer_value as Dictionary).get("plot_id", "")) in [deletion_id, interrupted_id]:
				deleted_offer_found = true
		_expect(not deleted_offer_found, "deleted remnant requests are never enumerated as fresh automatic work offers")
	var split_positions: Array[Vector3] = [Vector3(90.0, 0.0, 90.0), Vector3(91.25, 0.0, 90.0), Vector3(92.5, 0.0, 90.0), Vector3(93.75, 0.0, 90.0), Vector3(95.0, 0.0, 90.0)]
	var split_plot: Dictionary = controller.create_plot(split_positions, Vector2i(5, 1), "wheat", "Player")
	var split_id := str(split_plot.get("plot_id", ""))
	var count_before_split: int = controller.get_plots().size()
	var split_result: Dictionary = controller.shrink_plot(split_id, PackedStringArray(["2:0"]), owner)
	var inherited_fields: Array[Dictionary] = []
	for split_value in controller.get_plots().values():
		var candidate: Dictionary = split_value
		if not bool(candidate.get("field_deleted", false)) \
				and str(candidate.get("display_name", "")) == str(split_plot.get("display_name", "")) \
				and ((candidate.get("cells", {}) as Dictionary).has("0:0") or (candidate.get("cells", {}) as Dictionary).has("3:0")):
			inherited_fields.append(candidate)
	_expect(not split_result.is_empty() and controller.get_plots().size() == count_before_split + 1, "subtracting through a field splits disconnected islands")
	_expect(inherited_fields.size() == 2, "each disconnected island remains a separately managed field")
	_expect(controller.has_method("prepare_manual_till"), "controller exposes one durable manual-till rectangle transaction")
	if controller.has_method("prepare_manual_till"):
		var manual_positions: Array[Vector3] = [Vector3(20.0, 0.0, 20.0), Vector3(21.25, 0.0, 20.0)]
		var manual_order: Dictionary = controller.call("prepare_manual_till", manual_positions, owner, manual_positions[0])
		var manual_plot_id := str(manual_order.get("plot_id", ""))
		var manual_keys := PackedStringArray(manual_order.get("cell_keys", PackedStringArray()))
		var manual_plot: Dictionary = controller.get_plot(manual_plot_id)
		_expect(not manual_plot.is_empty() and str(manual_plot.get("crop_policy_id", "missing")).is_empty(), "manual hoeing starts a No Crop field")
		_expect(manual_keys.size() == 2, "one click-drag preserves every eligible rectangle cell")
		for manual_key in manual_keys:
			var manual_work: Dictionary = controller.get_cell_work(manual_plot_id, manual_key)
			_expect(str(manual_work.get("action", "")) == "till", "every manual rectangle cell receives exact till work")
			_expect(PackedStringArray(manual_work.get("allowed_actor_ids", PackedStringArray())) == PackedStringArray([owner.stable_id]), "Till Ground reserves every selected square for its commanded actor")
			var matching_targets: Array = (manual_order.get("targets", []) as Array).filter(func(target): return str(target.get("cell_key", "")) == manual_key)
			_expect(matching_targets.size() == 1 and int(matching_targets[0].get("request_revision", -1)) == int(manual_work.get("request_revision", -2)), "manual rectangle snapshots the current revision of each exact target")
		var adjacent_positions: Array[Vector3] = [Vector3(22.5, 0.0, 20.0)]
		var adjacent_order: Dictionary = controller.call("prepare_manual_till", adjacent_positions, owner, adjacent_positions[0])
		_expect(str(adjacent_order.get("plot_id", "")) == manual_plot_id, "adjacent No Crop hoeing expands the existing field")
		var recovery_keys := PackedStringArray(adjacent_order.get("cell_keys", PackedStringArray()))
		var edge_key := recovery_keys[0] if not recovery_keys.is_empty() else "2:0"
		var member_key := manual_keys[0]
		for recovery_key in [member_key, edge_key]:
			var recovery_work: Dictionary = controller.get_cell_work(manual_plot_id, recovery_key)
			controller.apply_work(manual_plot_id, recovery_key, "till", 999.0, 0.0, int(recovery_work.get("request_revision", -1)))
		var shrunk_for_recovery: Dictionary = controller.shrink_plot(manual_plot_id, PackedStringArray([edge_key]), owner)
		_expect(not shrunk_for_recovery.is_empty(), "removing an edge cell preserves a contiguous logical field")
		_expect(not (shrunk_for_recovery.get("cells", {}) as Dictionary).has(edge_key), "removed soil is no longer logical field membership")
		_expect((shrunk_for_recovery.get("soil_remnants", {}) as Dictionary).has(edge_key), "removed cultivated soil remains physically authoritative during recovery")
		controller.call("_advance_plot", manual_plot_id, 2879)
		_expect((controller.get_plot(manual_plot_id).get("soil_remnants", {}) as Dictionary).has(edge_key), "projection teardown before the threshold cannot recover removed soil")
		controller.call("_advance_plot", manual_plot_id, 2880)
		var recovered_plot: Dictionary = controller.get_plot(manual_plot_id)
		_expect(not (recovered_plot.get("soil_remnants", {}) as Dictionary).has(edge_key), "elapsed authoritative time removes recovered physical remnants")
		_expect((recovered_plot.get("cells", {}) as Dictionary).has(member_key), "soil recovery never deletes logical field membership")
		_expect(not bool(((recovered_plot.get("cells", {}) as Dictionary)[member_key] as Dictionary).get("soil_created", true)), "empty No Crop member soil also recovers to natural ground")
		var detached_position := Vector3(23.75, 0.0, 20.0)
		var detached_state: Dictionary = controller.get_plot(manual_plot_id)
		var detached_remnants: Dictionary = detached_state.get("soil_remnants", {}).duplicate(true)
		var detached_cell: Dictionary = controller.FARM_SIMULATION.complete_tilling(controller.FARM_SIMULATION.new_cell(Vector2i(3, 0), detached_position))
		detached_cell["soil_recovery_started_minute"] = 0
		detached_remnants["3:0"] = detached_cell
		detached_state["soil_remnants"] = detached_remnants
		controller.call("_save_plot", detached_state)
		var detached_positions: Array[Vector3] = [detached_position]
		var reclaimed_remnant: Dictionary = controller.create_plot(detached_positions, Vector2i.ONE, "", "Player")
		var reclaimed_remnant_cell: Dictionary = ((reclaimed_remnant.get("cells", {}) as Dictionary).values()[0] as Dictionary) if not (reclaimed_remnant.get("cells", {}) as Dictionary).is_empty() else {}
		_expect(bool(reclaimed_remnant_cell.get("soil_created", false)), "replanning over detached cultivated soil preserves its physical state")
		_expect(not (controller.get_plot(manual_plot_id).get("soil_remnants", {}) as Dictionary).has("3:0"), "replanning transfers a detached soil remnant instead of duplicating it")
		var policy_plot: Dictionary = controller.set_plot_crop_policy(manual_plot_id, "tomato", owner)
		_expect(str(policy_plot.get("crop_policy_id", "")) == "tomato", "field management sets a durable crop policy")
		_expect(str(controller.get_cell_work(manual_plot_id, member_key).get("action", "")) == "till", "crop policy schedules labor without instantly changing recovered ground")
		var merge_left_positions: Array[Vector3] = [Vector3(30.0, 0.0, 30.0)]
		var merge_right_positions: Array[Vector3] = [Vector3(32.5, 0.0, 30.0)]
		var merge_left: Dictionary = controller.create_plot(merge_left_positions, Vector2i.ONE, "", "Player")
		var merge_right: Dictionary = controller.create_plot(merge_right_positions, Vector2i.ONE, "", "Player")
		var bridge_positions: Array[Vector3] = [Vector3(31.25, 0.0, 30.0)]
		var bridge_order: Dictionary = controller.call("prepare_manual_till", bridge_positions, owner, bridge_positions[0])
		var merged_plot_id := str(bridge_order.get("plot_id", ""))
		_expect((controller.get_plot(merged_plot_id).get("cells", {}) as Dictionary).size() == 3, "touching behavior-identical fields automatically become one field")
		_expect(controller.get_plot(str(merge_left.get("plot_id", ""))).is_empty() or controller.get_plot(str(merge_right.get("plot_id", ""))).is_empty(), "automatic merge removes the absorbed field identity")
		var distinct_left_positions: Array[Vector3] = [Vector3(40.0, 0.0, 40.0)]
		var distinct_right_positions: Array[Vector3] = [Vector3(42.5, 0.0, 40.0)]
		var distinct_left: Dictionary = controller.create_plot(distinct_left_positions, Vector2i.ONE, "", "Player")
		var distinct_right: Dictionary = controller.create_plot(distinct_right_positions, Vector2i.ONE, "", "Player")
		var distinct_right_state: Dictionary = controller.get_plot(str(distinct_right.get("plot_id", "")))
		distinct_right_state["priority"] = 1
		controller.call("_save_plot", distinct_right_state)
		var distinct_bridge: Array[Vector3] = [Vector3(41.25, 0.0, 40.0)]
		controller.call("prepare_manual_till", distinct_bridge, owner, distinct_bridge[0])
		_expect(not controller.get_plot(str(distinct_left.get("plot_id", ""))).is_empty() and not controller.get_plot(str(distinct_right.get("plot_id", ""))).is_empty(), "different behavioral settings prevent automatic merging")
		_expect(controller.has_method("merge_adjacent_plots"), "field management exposes explicit adjacent-field merge")
		if controller.has_method("merge_adjacent_plots"):
			_expect(not controller.has_mergeable_adjacent_plot(str(distinct_left.get("plot_id", "")), null), "Merge requires explicit acting-character authority")
			_expect(controller.has_mergeable_adjacent_plot(str(distinct_left.get("plot_id", "")), owner), "Merge is offered when the owned field actually has an adjacent merge target")
			_expect(not controller.has_mergeable_adjacent_plot(str(distinct_left.get("plot_id", "")), outsider), "Merge is hidden when the acting character cannot command the adjacent field")
			var manual_merge: Dictionary = controller.call("merge_adjacent_plots", str(distinct_left.get("plot_id", "")), str(distinct_right.get("plot_id", "")), owner)
			_expect(not manual_merge.is_empty() and int(manual_merge.get("priority", -1)) == 0 and controller.get_plot(str(distinct_right.get("plot_id", ""))).is_empty(), "manual merge makes the clicked field inherit the source field's settings")
			_expect(not controller.has_mergeable_adjacent_plot(str(distinct_left.get("plot_id", "")), owner), "Merge disappears after the only adjacent field is absorbed")
			var busy_left_positions: Array[Vector3] = [Vector3(50.0, 0.0, 50.0)]
			var busy_right_positions: Array[Vector3] = [Vector3(51.25, 0.0, 50.0)]
			var busy_left: Dictionary = controller.create_plot(busy_left_positions, Vector2i.ONE, "", "Player")
			var busy_right: Dictionary = controller.create_plot(busy_right_positions, Vector2i.ONE, "", "Player")
			var busy_left_state: Dictionary = controller.get_plot(str(busy_left.get("plot_id", "")))
			var busy_key := str((busy_left_state.get("cells", {}) as Dictionary).keys()[0])
			busy_left_state["cells"][busy_key]["work_progress"] = 0.5
			controller.call("_save_plot", busy_left_state)
			_expect(not controller.has_mergeable_adjacent_plot(str(busy_left.get("plot_id", "")), owner), "Merge is hidden while either adjacent field has active work")
			_expect(controller.merge_adjacent_plots(str(busy_left.get("plot_id", "")), str(busy_right.get("plot_id", "")), owner).is_empty(), "field restructuring refuses to invalidate live cell work")
	_expect(controller.can_actor_command_plot(owner, str(plot.plot_id)), "owning faction can command its field")
	_expect(not controller.can_actor_command_plot(outsider, str(plot.plot_id)), "other factions cannot command the field")
	_expect(controller.has_method("expand_plot") and controller.has_method("shrink_plot"), "controller exposes durable sparse field edit operations")
	if controller.has_method("expand_plot") and controller.has_method("shrink_plot"):
		var outsider_expansion: Dictionary = controller.call("expand_plot", str(plot.plot_id), [Vector3(-1.25, 0.0, 0.0)], outsider)
		_expect(outsider_expansion.is_empty(), "other factions cannot expand the field")
		var expanded: Dictionary = controller.call("expand_plot", str(plot.plot_id), [Vector3(-1.25, 0.0, 0.0)], owner)
		_expect((expanded.get("cells", {}) as Dictionary).has("-1:0"), "owner can add one adjacent sparse field cell without rekeying existing work")
		var disconnected: Dictionary = controller.call("expand_plot", str(plot.plot_id), [Vector3(-5.0, 0.0, 0.0)], owner)
		_expect(disconnected.is_empty(), "field expansion rejects disconnected cells")
		var outsider_shrink: Dictionary = controller.call("shrink_plot", str(plot.plot_id), PackedStringArray(["-1:0"]), outsider)
		_expect(outsider_shrink.is_empty(), "other factions cannot shrink the field")
		var shrunk: Dictionary = controller.call("shrink_plot", str(plot.plot_id), PackedStringArray(["-1:0"]), owner)
		_expect(not (shrunk.get("cells", {}) as Dictionary).has("-1:0") and (shrunk.get("cells", {}) as Dictionary).size() == 2, "owner can remove one field cell")
	var reloaded_state: Dictionary = controller.get_plot(str(plot.plot_id))
	var growing_cell: Dictionary = controller.FARM_SIMULATION.complete_planting(controller.FARM_SIMULATION.complete_tilling(controller.FARM_SIMULATION.new_cell(Vector2i(1, 0), positions[1])), "tomato", 24.0)
	(reloaded_state.cells as Dictionary)["1:0"] = growing_cell
	reloaded_state.last_simulated_minute = 0
	gecs.upsert_farm_plot_state(reloaded_state)
	time.absolute_minute = 5000
	controller._on_world_reindexed()
	_expect(int(controller.get_plot(str(plot.plot_id)).last_simulated_minute) == 0, "world reindex waits for the restored save clock instead of advancing against the pre-load session clock")
	time.absolute_minute = 60
	controller.call("_reconcile_after_world_reindex")
	var advanced_state: Dictionary = controller.get_plot(str(plot.plot_id))
	_expect(int(advanced_state.last_simulated_minute) == 60 and float(((advanced_state.cells as Dictionary)["1:0"] as Dictionary).growth) > 0.0, "load reindex advances crops from durable elapsed world time")
	gecs.upsert_farm_water_source_state({"source_id": "cistern", "source_kind": "well", "owner_faction_name": "Player", "renewable": false, "capacity": 20.0, "current_water": 5.0, "recharge_per_world_minute": 0.1, "last_processed_minute": 0})
	time.absolute_minute = 120
	controller._on_world_reindexed()
	controller.call("_reconcile_after_world_reindex")
	var advanced_water: Dictionary = gecs.get_farm_water_source_states().get("cistern", {})
	_expect(is_equal_approx(float(advanced_water.get("current_water", 0.0)), 17.0) and int(advanced_water.get("last_processed_minute", 0)) == 120, "off-screen finite water sources recharge from elapsed world time")
	var foreign_denied := {"source_id": "cistern", "owner_faction_name": "Player", "actor_faction_name": "Other", "owner_access_approved": false, "theft_approved": false}
	var owner_authorized := {"source_id": "cistern", "owner_faction_name": "Player", "actor_faction_name": "Player", "owner_access_approved": true, "theft_approved": false}
	var theft_authorized := {"source_id": "cistern", "owner_faction_name": "Player", "actor_faction_name": "Other", "owner_access_approved": false, "theft_approved": true}
	var stale_authorization := {"source_id": "cistern", "owner_faction_name": "FormerOwner", "actor_faction_name": "FormerOwner", "owner_access_approved": true, "theft_approved": false}
	_expect(is_equal_approx(float(controller.call("draw_water_source", "cistern", 4.0, foreign_denied)), 0.0), "authoritative water mutation rejects foreign draws without theft authorization")
	_expect(is_equal_approx(float(controller.call("draw_water_source", "cistern", 4.0, stale_authorization)), 0.0), "authoritative water mutation rejects authorization for a stale owner")
	_expect(is_equal_approx(float(controller.call("draw_water_source", "cistern", 4.0, owner_authorized)), 4.0), "authoritative water mutation accepts the owner's draw")
	_expect(is_equal_approx(float(controller.call("draw_water_source", "cistern", 3.0, theft_authorized)), 3.0), "authoritative water mutation accepts a theft-system-approved foreign draw")
	_expect(controller.has_method("deposit_water_source"), "controller exposes exact conserved water deposits")
	if controller.has_method("deposit_water_source"):
		var deposited := float(controller.call("deposit_water_source", "cistern", 15.0, owner_authorized))
		_expect(is_equal_approx(deposited, 10.0) and is_equal_approx(float(controller.get_water_source("cistern").get("current_water", 0.0)), 20.0), "water deposit accepts only free storage capacity")
	gecs.upsert_farm_water_source_state({
		"source_id": "renewable_source",
		"owner_faction_name": "Player",
		"renewable": true,
		"capacity": 0.0,
		"current_water": 0.0,
	})
	var renewable_authorized := {"source_id": "renewable_source", "owner_faction_name": "Player", "actor_faction_name": "Player", "owner_access_approved": true, "theft_approved": false}
	var renewable_reserved := float(controller.call("reserve_water_source_outgoing", "renewable_source", 8.0, renewable_authorized))
	var renewable_drawn := float(controller.call("draw_reserved_water_source", "renewable_source", renewable_reserved, renewable_authorized))
	_expect(is_equal_approx(renewable_reserved, 8.0) and is_equal_approx(renewable_drawn, 8.0), "legacy renewable sources remain usable through reserved hauling")
	owner.free()
	outsider.free()
	controller.free()
	gecs.free()
	time.free()
	territory.free()
	stock.free()
	print("FARM_CONTROLLER_PHASES_COMPLETE")
	_finish()


func _assert_create_plot_size_limits(controller, gecs: FakeGecs) -> void:
	var max_dimension: int = controller.MAX_PLOT_DIMENSION
	var max_cells: int = controller.MAX_PLOT_CELLS
	var cell_size: float = controller.DEFAULT_CELL_SIZE
	_expect(max_dimension > 0 and max_cells > 0, "create_plot size: configured limits are positive")
	if max_dimension <= 0 or max_cells <= 0:
		return
	var full_width := mini(max_dimension, max_cells)
	var budget_rows := floori(float(max_cells) / full_width)
	var full_height := mini(max_dimension, budget_rows)
	# Use the real settings, not copied caps. Dimension and cell ceilings can
	# overlap; these cases check the public size contract, not guard ordering.
	var size_cases: Array[Dictionary] = [
		{"name": "width boundary", "dimensions": Vector2i(full_width, 1), "accepted": true},
		{"name": "height boundary", "dimensions": Vector2i(1, full_width), "accepted": true},
		{"name": "full-width permitted rectangle", "dimensions": Vector2i(full_width, full_height), "accepted": true},
		{"name": "width above limit", "dimensions": Vector2i(max_dimension + 1, 1), "accepted": false},
		{"name": "height above limit", "dimensions": Vector2i(1, max_dimension + 1), "accepted": false},
		{"name": "cell budget exceeded", "dimensions": Vector2i(full_width, budget_rows + 1), "accepted": false},
	]
	for size_case in size_cases:
		var dimensions: Vector2i = size_case["dimensions"]
		var positions := _plot_grid_positions(dimensions, cell_size)
		var before_states := gecs.states.duplicate(true)
		var before_writes := gecs.full_state_writes
		var before_events := plot_change_count
		var before_sequence: int = controller._next_plot_sequence
		var created: Dictionary = controller.create_plot(positions, dimensions, "tomato", "Player")
		var label := str(size_case["name"])
		if bool(size_case["accepted"]):
			_expect(not created.is_empty(), "create_plot size: accepts %s" % label)
			var stored: Dictionary = controller.get_plot(str(created.get("plot_id", "")))
			_expect(stored.get("dimensions", Vector2i.ZERO) == dimensions \
					and (stored.get("cells", {}) as Dictionary).size() == positions.size(), "create_plot size: preserves all cells at %s" % label)
		else:
			_expect(created.is_empty(), "create_plot size: rejects %s" % label)
			_expect(gecs.states == before_states and gecs.full_state_writes == before_writes \
					and plot_change_count == before_events and controller._next_plot_sequence == before_sequence, "create_plot size: rejection leaves state, IDs and events unchanged for %s" % label)
		# Each case starts on clear ground; an accepted or unexpectedly accepted
		# field must not cause the next rejection through overlap instead of size.
		if not created.is_empty():
			controller.remove_plot(str(created["plot_id"]))
		_expect(gecs.states == before_states, "create_plot size: fixture cleanup for %s" % label)


func _plot_grid_positions(dimensions: Vector2i, cell_size: float) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for row in dimensions.y:
		for column in dimensions.x:
			positions.append(Vector3(float(column) * cell_size, 0.0, float(row) * cell_size))
	return positions


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FARM_CONTROLLER_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FARM_CONTROLLER_FAILED count=%d" % failures.size())
	quit(1)
