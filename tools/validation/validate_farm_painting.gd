extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_farm_painting.gd

const SOLVER = preload("res://features/farming/bridge/farm_placement_solver.gd")
const PROJECTION = preload("res://features/farming/projection/farm_plot_projection.gd")
const FARM_SIMULATION = preload("res://features/farming/sim/farm_simulation.gd")

class RetiredFarmPlot:
	extends Node3D
	func blocks_farm_placement() -> bool:
		return false

var failures: Array[String] = []


func _initialize() -> void:
	var plan: Dictionary = SOLVER.build_grid(Vector3(10.0, 2.0, 20.0), Vector3(15.0, 2.0, 22.5), 1.25)
	_expect(plan.get("dimensions", Vector2i.ZERO) == Vector2i(5, 3), "field drag stores start-to-end rectangle dimensions")
	_expect((plan.get("positions", []) as Array).size() == 15, "field drag fills every cell in its rectangle")
	_expect((plan.get("positions", []) as Array).front() == Vector3(10.0, 2.0, 20.0), "field rectangle starts at the snapped anchor")
	_expect((plan.get("positions", []) as Array).back() == Vector3(15.0, 2.0, 22.5), "field rectangle includes the snapped release cell")

	var structure := StaticBody3D.new()
	_expect(SOLVER.obstacle_reason_for_collider(structure) == "occupied", "every static structure blocks farming")
	structure.free()
	var actor := CharacterBody3D.new()
	_expect(SOLVER.obstacle_reason_for_collider(actor).is_empty(), "characters do not block farming")
	actor.free()
	var retired_plot := RetiredFarmPlot.new()
	retired_plot.add_to_group("farm_plot")
	_expect(SOLVER.obstacle_reason_for_collider(retired_plot).is_empty(), "retired cultivated soil and plants do not obstruct replanning")
	retired_plot.free()
	var item := StaticBody3D.new()
	item.add_to_group("world_item")
	_expect(SOLVER.obstacle_reason_for_collider(item).is_empty(), "droppable world items do not block farming")
	item.free()
	var plot := Area3D.new()
	plot.add_to_group("farm_plot")
	_expect(SOLVER.obstacle_reason_for_collider(plot) == "occupied", "existing farm cells block overlap")
	plot.free()
	var harmless_area := Area3D.new()
	_expect(SOLVER.obstacle_reason_for_collider(harmless_area).is_empty(), "non-physical trigger areas do not block farming")
	harmless_area.free()

	var blocked_color: Color = PROJECTION.soil_color_for_state("blocked")
	_expect(blocked_color.r < 0.4 and blocked_color.g > 0.1, "blocked soil remains natural instead of turning red")
	var fresh_cell := FARM_SIMULATION.new_cell(Vector2i.ZERO, Vector3.ZERO)
	_expect(not bool(fresh_cell.get("soil_created", true)), "fresh field designation leaves the ground untouched")
	var tilled_cell := FARM_SIMULATION.complete_tilling(fresh_cell)
	_expect(bool(tilled_cell.get("soil_created", false)), "completed tilling physically creates soil")
	var simulation = FARM_SIMULATION.new()
	_expect(simulation.has_method("advance_soil_recovery"), "soil recovery is an authoritative simulation transition")
	if simulation.has_method("advance_soil_recovery"):
		var recovering: Dictionary = simulation.call("advance_soil_recovery", tilled_cell, 100, 2979, true, 2880)
		_expect(bool(recovering.get("soil_created", false)), "empty soil remains before the two-day recovery threshold")
		recovering = simulation.call("advance_soil_recovery", recovering, 2979, 2980, true, 2880)
		_expect(not bool(recovering.get("soil_created", true)) and str(recovering.get("state", "")) == FARM_SIMULATION.STATE_UNTILLED, "elapsed GECS time recovers empty physical soil without deleting its logical cell")
	var ripe_cell := FARM_SIMULATION.complete_planting(tilled_cell, "tomato")
	ripe_cell["state"] = FARM_SIMULATION.STATE_RIPE
	var harvested_cell: Dictionary = FARM_SIMULATION.complete_harvest(ripe_cell, {"base_yield": 1, "yield_per_farming_level": 0.0}, 0.0).cell
	_expect(bool(harvested_cell.get("soil_created", false)), "harvested ground remains visibly worked")
	var visual_cells := {
		"0:0": fresh_cell,
		"1:0": tilled_cell.merged({"grid_position": Vector2i(1, 0), "world_position": Vector3(1.25, 0.1, 0)}, true),
		"1:1": FARM_SIMULATION.new_cell(Vector2i(1, 1), Vector3(1.25, 0.05, 1.25)),
	}
	var soil_cells: Dictionary = PROJECTION.cells_with_created_soil(visual_cells)
	_expect(soil_cells.size() == 1 and soil_cells.has("1:0"), "only physically tilled cells contribute connected dirt")
	var soil_mesh: ArrayMesh = PROJECTION.build_connected_soil_mesh(soil_cells, 1.25)
	_expect(soil_mesh.get_surface_count() == 1, "tilled field uses one connected soil surface")
	var soil_bounds := soil_mesh.get_aabb()
	_expect(soil_bounds.size.x > 1.1 and soil_bounds.size.z > 1.1, "created soil covers the full tilled cell without grass gaps")
	var stake_positions: Array[Vector3] = PROJECTION.boundary_stake_positions(visual_cells, 1.25)
	_expect(stake_positions.size() >= 6, "logical field is marked by sparse perimeter stakes before tilling")
	var soil_material := PROJECTION.build_soil_material()
	_expect(soil_material.cull_mode == BaseMaterial3D.CULL_BACK, "connected soil uses correct front-face winding instead of disabling culling")
	var placement_source := FileAccess.get_file_as_string("res://features/farming/bridge/farm_placement_bridge.gd")
	_expect(placement_source.contains("SOLVER.build_grid(_anchor, _drag_end"), "planned farming uses a start-to-end rectangle")
	_expect(not placement_source.contains("SOLVER.raster_line"), "planned farming no longer accumulates a freehand brush path")
	var till_submit_source := placement_source.get_slice("func _submit_manual_till_positions", 1).get_slice("func _activate_field_expansion", 0)
	_expect(till_submit_source.contains("assign_cell_sequence") and till_submit_source.contains("prepare_manual_till") and not till_submit_source.contains("_claim_first_designated_till"), "drawing till squares creates one complete selected-actor command sequence")
	var work_bridge_source := FileAccess.get_file_as_string("res://features/farming/bridge/farm_work_bridge.gd")
	_expect(work_bridge_source.contains("assign_cell_sequence") and work_bridge_source.contains("command_targets") and not work_bridge_source.contains("_manual_queues"), "field-wide commands chain authoritative cell work without restoring a separate private queue")
	_expect(placement_source.contains("PREVIEW_REMOVE_COLOR") and placement_source.contains("plot_cell_keys_in_rectangle"), "Subtract previews exact overlapping field cells as red squares")
	_expect(placement_source.contains("Press Esc to cancel deletion"), "Subtract uses only the approved minimal white Escape hint")
	_expect(not placement_source.contains("Click ground to") and not placement_source.contains("Click a field cell to remove"), "field placement has no persistent center instruction prose")
	var details_source := FileAccess.get_file_as_string("res://features/ui/bridge/humanoid_details_controller.gd")
	_expect(not details_source.contains("{\"label\": \"Plan Field\", \"action\": \"farm_plan\"}"), "Plan Field is absent from character details")
	var hud_source := FileAccess.get_file_as_string("res://features/ui/projection/game_hud.tscn")
	_expect(hud_source.contains("BuildMenuButton"), "the player HUD exposes a dedicated build menu")
	var obstruction_source := FileAccess.get_file_as_string("res://features/farming/bridge/farm_obstruction_bridge.gd")
	_expect(obstruction_source.contains("\"cell_keys\": cell_keys"), "obstruction rescans preserve sparse painted cell identity")
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FARM_PAINTING_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FARM_PAINTING_FAILED count=%d" % failures.size())
	quit(1)
