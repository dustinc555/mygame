extends SceneTree
## Production bootstrap proof for world-sim farming and projection handoff.
## Run: godot --headless --path . --script res://tests/validation/validate_farm_world_simulation_runtime.gd

var failures: Array[String] = []
var game: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	game = (load("res://scenes/test_levels/two_towns_road_test.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	for _frame in 120:
		await process_frame
	var context := BootstrapContext.active
	var farm = context.get_optional(&"farming") if context != null else null
	var world_farm = context.get_optional(&"farm_world_simulation") if context != null else null
	var settlements = context.get_optional(&"settlement") if context != null else null
	var population = context.get_optional(&"population") if context != null else null
	var world_time = context.get_optional(&"world_time") if context != null else null
	_expect(farm != null and world_farm != null and settlements != null and population != null and world_time != null, "production bootstrap installs world-sim farming")
	if farm == null or world_farm == null or settlements == null or population == null or world_time == null:
		_finish()
		return
	var settlement_id := "farmer_crossing"
	var definition: SettlementDefinition = settlements.get_settlement_definition(settlement_id)
	var slot := _first_farm_assignment_slot(settlements.get_settlement_state(settlement_id))
	var generated: Array = population.ensure_generated_population(settlement_id, "world_farm_validation", 1, {
		"role_id": "resident", "faction_id": definition.get_faction_id(), "available_for_work": true,
		"population_appearance_profile": definition.get_population_appearance_profile(),
		"population_name_profile": definition.get_population_name_profile(),
	})
	var actor_id := str((generated[0] as Dictionary).get("actor_id", "")) if not generated.is_empty() else ""
	_expect(not slot.is_empty() and not actor_id.is_empty(), "production town has a durable field job and available resident")
	if slot.is_empty() or actor_id.is_empty():
		_finish()
		return
	var assigned: Dictionary = settlements.assign_actor_to_assignment_slot(settlement_id, str(slot.get("assignment_domain", "employment")), str(slot.get("slot_id", "")), actor_id)
	_expect(not assigned.is_empty(), "resident becomes the town's durable farmer")
	settlements.derealize_assignment_slot(settlement_id, str(slot.get("assignment_domain", "employment")), str(slot.get("slot_id", "")))
	await process_frame
	await process_frame
	_expect(population.get_live_actor(actor_id) == null, "worker projection is absent before world-sim labor")
	var before_tilled := _tilled_cell_count(farm, settlement_id)
	var advance_started := Time.get_ticks_usec()
	world_time.advance_hours(1.0)
	var world_summary: Dictionary = world_farm.get_last_summary()
	var advance_usec := Time.get_ticks_usec() - advance_started
	var after_unrealized_tilled := _tilled_cell_count(farm, settlement_id)
	_expect(after_unrealized_tilled > before_tilled, "unrealized town makes durable field progress")
	print("FARM_WORLD_SIMULATION_RUNTIME_METRIC usec=%d summary=%s" % [advance_usec, world_summary])
	# A fresh No Crop designation has no passive crop/water transitions to
	# confuse with labor, and unfinished work is guaranteed to remain.
	var fresh_positions: Array[Vector3] = []
	var fresh_dimensions := Vector2i.ONE
	var fresh_keys := PackedStringArray()
	for plot in farm.get_plots().values():
		if str(plot.get("settlement_id", "")) == settlement_id:
			if fresh_positions.is_empty():
				fresh_dimensions = plot.get("dimensions", Vector2i.ONE)
				fresh_keys = PackedStringArray(plot.cells.keys())
				for cell in plot.cells.values(): fresh_positions.append(cell.world_position)
			farm.remove_plot(str(plot.plot_id))
	var fresh: Dictionary = farm.create_plot(fresh_positions, fresh_dimensions, "", definition.get_faction_id(), settlement_id, {}, fresh_keys)
	_expect(not fresh.is_empty(), "realized-phase fixture creates fresh unworked soil")
	if fresh.is_empty():
		_finish()
		return
	for cell_key in fresh.cells: farm.request_cell_operation(str(fresh.plot_id), str(cell_key), "till")
	_expect(settlements.realize_assignment_slot(settlement_id, str(slot.get("assignment_domain", "employment")), str(slot.get("slot_id", ""))), "worker projection returns")
	_expect(population.get_live_actor(actor_id) != null, "the exact durable farmer has a live projection before suppressing aggregate labor")
	var cells_before: Dictionary = farm.get_plot(str(fresh.plot_id)).cells.duplicate(true)
	# The first canonical minute materializes this absent legacy default on
	# newly created cells. No crop/soil exists here, so no other change is valid.
	for key in cells_before:
		var cell: Dictionary = cells_before[key]
		cells_before[key] = FarmSimulation.new_cell(cell.grid_position, cell.world_position).merged(cell, true)
	var stock = context.get_optional(&"inventory_stock")
	var stock_before: Dictionary = stock.get_settlement_stock_snapshot(settlement_id)
	world_time.advance_hours(1.0)

	_expect(farm.get_plot(str(fresh.plot_id)).cells == cells_before and stock.get_settlement_stock_snapshot(settlement_id) == stock_before, "realized town leaves every cell request/progress and inventory untouched by aggregate labor")
	_finish()


func _first_farm_assignment_slot(state: Dictionary) -> Dictionary:
	for slot_value in (state.get("assignment_slots", {}) as Dictionary).values():
		var slot: Dictionary = slot_value
		if PackedStringArray(slot.get("allowed_job_entry_ids", PackedStringArray())).has("category:farm"):
			return slot
	return {}


func _tilled_cell_count(farm: Node, settlement_id: String) -> int:
	var count := 0
	for plot_value in (farm.get_plots() as Dictionary).values():
		var plot: Dictionary = plot_value
		if str(plot.get("settlement_id", "")) != settlement_id:
			continue
		for cell_value in (plot.get("cells", {}) as Dictionary).values():
			if str((cell_value as Dictionary).get("state", "")) == "tilled":
				count += 1
	return count


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if game != null and is_instance_valid(game):
		root.remove_child(game)
		game.free()
	if failures.is_empty():
		print("FARM_WORLD_SIMULATION_RUNTIME_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FARM_WORLD_SIMULATION_RUNTIME_FAILED count=%d" % failures.size())
	quit(1)
