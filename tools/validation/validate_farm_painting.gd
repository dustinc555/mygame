extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_farm_painting.gd

const SOLVER = preload("res://features/farming/bridge/farm_placement_solver.gd")
const PROJECTION = preload("res://features/farming/projection/farm_plot_projection.gd")
const FARM_SIMULATION = preload("res://features/farming/sim/farm_simulation.gd")

class RetiredFarmPlot:
	extends Node3D
	func blocks_farm_placement() -> bool:
		return false

class CropFarm:
	extends Node
	var tomato = preload("res://features/farming/resources/crops/tomato.tres")
	func get_crop(crop_id: String):
		return tomato if crop_id == "tomato" else null
	func get_crops() -> Array:
		return [tomato]

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
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
	var soil_arrays := soil_mesh.surface_get_arrays(0)
	var soil_vertices := soil_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var minimum_ground_offset := INF
	var maximum_ground_offset := -INF
	for vertex in soil_vertices:
		minimum_ground_offset = minf(minimum_ground_offset, vertex.y - 0.1)
		maximum_ground_offset = maxf(maximum_ground_offset, vertex.y - 0.1)
	_expect(minimum_ground_offset >= PROJECTION.SOIL_SURFACE_OFFSET - 0.0001 and minimum_ground_offset <= PROJECTION.SOIL_SURFACE_OFFSET + 0.0001, "connected soil perimeter touches the authored ground")
	_expect(maximum_ground_offset > 0.10 and maximum_ground_offset < 0.15, "connected soil keeps its raised organic worked-earth profile")
	var stake_positions: Array[Vector3] = PROJECTION.boundary_stake_positions(visual_cells, 1.25)
	_expect(stake_positions.size() >= 6, "logical field is marked by sparse perimeter stakes before tilling")
	var soil_material := PROJECTION.build_soil_material()
	_expect(soil_material.cull_mode == BaseMaterial3D.CULL_BACK, "connected soil uses correct front-face winding instead of disabling culling")
	_expect(soil_material.albedo_texture != null and soil_material.albedo_texture.resource_path.ends_with("T_Soil02A_C.png"), "connected soil uses the purchased Soil 02A base color")
	_expect(soil_material.normal_enabled and soil_material.normal_texture != null and soil_material.normal_texture.resource_path.ends_with("T_Soil02A_N.png"), "connected soil uses the purchased Soil 02A normal map")
	_expect(soil_material.roughness_texture != null and soil_material.roughness_texture.resource_path.ends_with("T_Soil02A_R.png"), "connected soil uses the purchased Soil 02A roughness map")
	var l_cells := {}
	for grid in [Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(2, 1), Vector2i(2, 0)]:
		l_cells["%d:%d" % [grid.x, grid.y]] = tilled_cell.merged({"grid_position": grid, "world_position": Vector3(grid.x * 1.25, 0.0, grid.y * 1.25)}, true)
	var l_mesh: ArrayMesh = PROJECTION.build_connected_soil_mesh(l_cells, 1.25)
	var l_top_minimum := INF
	var l_top_maximum := -INF
	var l_top_arrays := l_mesh.surface_get_arrays(0)
	var l_top_vertices := l_top_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var l_top_colors := l_top_arrays[Mesh.ARRAY_COLOR] as PackedColorArray
	for vertex_index in l_top_vertices.size():
		if l_top_colors[vertex_index].r >= 0.5:
			l_top_minimum = minf(l_top_minimum, l_top_vertices[vertex_index].y)
			l_top_maximum = maxf(l_top_maximum, l_top_vertices[vertex_index].y)
	_expect(l_top_maximum - l_top_minimum > 0.10 and l_top_maximum - l_top_minimum < 0.15, "flat terrain keeps connected non-flat worked-soil relief")
	var large_field_cells := {}
	for z in 10:
		for x in 10:
			var grid := Vector2i(x, z)
			large_field_cells["%d:%d" % [x, z]] = tilled_cell.merged({"grid_position": grid, "world_position": Vector3(x * 1.25, 0.0, z * 1.25)}, true)
	var large_field_mesh: ArrayMesh = PROJECTION.build_connected_soil_mesh(large_field_cells, 1.25)
	_expect(large_field_mesh.surface_get_array_len(0) <= 2400, "a 100-cell connected field and its sealed perimeter stay within the validated runtime mesh-density budget")
	var heights_by_position: Dictionary = {}
	var l_arrays := l_mesh.surface_get_arrays(0)
	var l_colors := l_arrays[Mesh.ARRAY_COLOR] as PackedColorArray
	var l_vertices := l_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	for vertex_index in l_vertices.size():
		if l_colors[vertex_index].r < 0.5:
			continue
		var vertex := l_vertices[vertex_index]
		var xz_key := str(Vector2(vertex.x, vertex.z).snapped(Vector2.ONE * 0.0001))
		var range: Vector2 = heights_by_position.get(xz_key, Vector2(vertex.y, vertex.y))
		heights_by_position[xz_key] = Vector2(minf(range.x, vertex.y), maxf(range.y, vertex.y))
	var maximum_shared_height_span := 0.0
	for range_value in heights_by_position.values():
		var range: Vector2 = range_value
		maximum_shared_height_span = maxf(maximum_shared_height_span, range.y - range.x)
	_expect(maximum_shared_height_span < 0.0001, "L-shaped fields share one taper height at concave corners without a notch or overlap")
	var sloped_l_cells := {}
	for grid in [Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(2, 1), Vector2i(2, 0)]:
		var terrain_height := float(grid.x) * 0.08 + float(grid.y) * 0.045
		sloped_l_cells["%d:%d" % [grid.x, grid.y]] = tilled_cell.merged({"grid_position": grid, "world_position": Vector3(grid.x * 1.25, terrain_height, grid.y * 1.25)}, true)
	var sloped_l_mesh: ArrayMesh = PROJECTION.build_connected_soil_mesh(sloped_l_cells, 1.25)
	var sloped_height_ranges: Dictionary = {}
	var sloped_arrays := sloped_l_mesh.surface_get_arrays(0)
	var sloped_vertices := sloped_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var sloped_colors := sloped_arrays[Mesh.ARRAY_COLOR] as PackedColorArray
	for vertex_index in sloped_vertices.size():
		if sloped_colors[vertex_index].r < 0.5:
			continue
		var vertex := sloped_vertices[vertex_index]
		var xz_key := str(Vector2(vertex.x, vertex.z).snapped(Vector2.ONE * 0.0001))
		var range: Vector2 = sloped_height_ranges.get(xz_key, Vector2(vertex.y, vertex.y))
		sloped_height_ranges[xz_key] = Vector2(minf(range.x, vertex.y), maxf(range.y, vertex.y))
	var maximum_sloped_shared_height_span := 0.0
	for range_value in sloped_height_ranges.values():
		var range: Vector2 = range_value
		maximum_sloped_shared_height_span = maxf(maximum_sloped_shared_height_span, range.y - range.x)
	_expect(maximum_sloped_shared_height_span < 0.0001, "terrain-conforming L fields share exact edge and concave-corner heights on slopes")
	_expect(sloped_colors.size() == sloped_vertices.size(), "terrain-conforming soil retains one material color per ground vertex")
	var sloped_indices := sloped_arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var sloped_mesh_bridges_missing_cell := false
	for index in range(0, sloped_indices.size(), 3):
		var centroid := (sloped_vertices[sloped_indices[index]] + sloped_vertices[sloped_indices[index + 1]] + sloped_vertices[sloped_indices[index + 2]]) / 3.0
		if centroid.x > 0.625 and centroid.x < 1.875 and centroid.z > 0.625 and centroid.z < 1.875:
			sloped_mesh_bridges_missing_cell = true
			break
	_expect(not sloped_mesh_bridges_missing_cell, "terrain-conforming L fields never bridge or fill their missing inside-corner cell")
	var crop_farm := CropFarm.new()
	root.add_child(crop_farm)
	var crop_projection := PROJECTION.new()
	root.add_child(crop_projection)
	_expect(crop_projection.has_method("update_cells_state"), "cell completions update one projection batch without full-plot synchronization")
	_expect(PROJECTION.SOIL_ASYNC_BUILD_CELL_THRESHOLD <= 8, "ordinary Canyon soil rebuilds are coalesced off the main thread")
	_expect(crop_projection.has_method("set_terrain_height_sampler"), "production soil accepts the authoritative Terrain3D height sampler")
	if crop_projection.has_method("set_terrain_height_sampler"):
		crop_projection.call("set_terrain_height_sampler", Callable(self, "_test_terrain_height"))
	var crop_grid := Vector2i(1, 0)
	var crop_cell := FARM_SIMULATION.complete_planting(tilled_cell.merged({"grid_position": crop_grid, "world_position": Vector3.ZERO}, true), "tomato")
	crop_cell["stage_index"] = FARM_SIMULATION.RIPE_VISUAL_STAGE_INDEX
	crop_projection.setup({"plot_id": "crop_center_test", "cell_size": 1.25, "cells": {"1:0": crop_cell}}, crop_farm)
	var crop_holder := crop_projection.get_node_or_null("Cells/Cell_1_0") as Node3D
	var connected_soil := crop_projection.get_node_or_null("Cells/ConnectedSoil") as MeshInstance3D
	var per_cell_soil_count := 0
	for child in crop_holder.get_children() if crop_holder != null else []:
		if child.name == "Soil":
			per_cell_soil_count += 1
	_expect(connected_soil != null and connected_soil.mesh != null and connected_soil.mesh.get_surface_count() == 1 and per_cell_soil_count == 0, "production projection uses only its connected soil surface and never restores per-cell soil nodes")
	_expect(connected_soil != null and connected_soil.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "tilled soil never casts a shadow")
	var terrain_fit_ok := connected_soil != null and connected_soil.mesh != null
	if terrain_fit_ok:
		var terrain_arrays := connected_soil.mesh.surface_get_arrays(0)
		var found_ground_contact := false
		var found_raised_center := false
		for vertex in terrain_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array:
			var relief := vertex.y - _test_terrain_height(vertex)
			if relief < PROJECTION.SOIL_SURFACE_OFFSET - 0.0001 or relief > 0.15:
				terrain_fit_ok = false
				break
			found_ground_contact = found_ground_contact or absf(relief - PROJECTION.SOIL_SURFACE_OFFSET) <= 0.0001
			found_raised_center = found_raised_center or relief > 0.10
		terrain_fit_ok = terrain_fit_ok and found_ground_contact and found_raised_center
	_expect(terrain_fit_ok, "every soil mesh vertex uses the actual Terrain3D height instead of averaged cell-center heights")
	var crop_pivot := crop_holder.get_node_or_null("Crop") as Node3D if crop_holder != null else null
	var crop_visual := crop_pivot.get_node_or_null("Visual") as Node3D if crop_pivot != null else null
	var crop_ground_position := Vector3(crop_holder.position.x, 0.0, crop_holder.position.z) if crop_holder != null else Vector3.ZERO
	_expect(
		crop_holder != null and is_equal_approx(crop_holder.position.y, _test_terrain_height(crop_ground_position)),
		"crop roots use the same sampled Terrain3D ground height as their connected soil",
	)
	_expect(crop_pivot != null and absf(crop_pivot.rotation.y) > 0.001 and crop_pivot.position.is_equal_approx(Vector3.ZERO), "production crop rotation uses a clean pivot at the cell center")
	var crop_minimum := Vector3(INF, INF, INF)
	var crop_maximum := Vector3(-INF, -INF, -INF)
	if crop_visual != null:
		for mesh_value in crop_visual.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := mesh_value as MeshInstance3D
			var relative := PROJECTION._transform_from_ancestor(mesh_instance, crop_visual)
			var box := mesh_instance.mesh.get_aabb()
			for x in [box.position.x, box.end.x]:
				for y in [box.position.y, box.end.y]:
					for z in [box.position.z, box.end.z]:
						var point := relative * Vector3(x, y, z)
						crop_minimum = crop_minimum.min(point)
						crop_maximum = crop_maximum.max(point)
	var fitted_crop_center := crop_visual.transform * ((crop_minimum + crop_maximum) * 0.5) if crop_visual != null else Vector3(INF, INF, INF)
	_expect(Vector2(fitted_crop_center.x, fitted_crop_center.z).length() < 0.0001, "production crop geometry is recentered beneath its rotation pivot instead of swinging off the mound")
	var recovered_cell := FARM_SIMULATION.new_cell(crop_grid, Vector3.ZERO)
	crop_projection.update_state({"plot_id": "crop_center_test", "cell_size": 1.25, "cells": {"1:0": recovered_cell}})
	var recovered_soil := crop_projection.get_node_or_null("Cells/ConnectedSoil") as MeshInstance3D
	_expect(recovered_soil != null and recovered_soil.mesh != null and recovered_soil.mesh.get_surface_count() == 0, "production recovery keeps a non-null empty connected mesh without stale cultivated geometry")
	var recultivated_cell := tilled_cell.merged({"grid_position": crop_grid, "world_position": Vector3.ZERO}, true)
	crop_projection.update_state({"plot_id": "crop_center_test", "cell_size": 1.25, "cells": {"1:0": recultivated_cell}})
	var recultivated_soil := crop_projection.get_node_or_null("Cells/ConnectedSoil") as MeshInstance3D
	_expect(recultivated_soil != null and recultivated_soil.mesh != null and recultivated_soil.mesh.get_surface_count() == 1, "production recultivation rebuilds connected soil after recovery")
	var original_soil_width := recultivated_soil.mesh.get_aabb().size.x
	crop_projection.update_state({"plot_id": "crop_center_test", "cell_size": 2.0, "cells": {"1:0": recultivated_cell}})
	var resized_soil := crop_projection.get_node_or_null("Cells/ConnectedSoil") as MeshInstance3D
	_expect(resized_soil.mesh.get_aabb().size.x > original_soil_width + 0.7, "connected-soil cache rebuilds when cell size changes without cell-key or terrain-position changes")
	crop_projection.free()
	crop_farm.free()
	var async_farm := CropFarm.new()
	root.add_child(async_farm)
	var async_projection := PROJECTION.new()
	root.add_child(async_projection)
	var fresh_large_cells: Dictionary = {}
	var cultivated_large_cells: Dictionary = {}
	for z in 16:
		for x in 16:
			var grid := Vector2i(x, z)
			var fresh_large_cell := FARM_SIMULATION.new_cell(grid, Vector3(x * 1.25, 0.0, z * 1.25))
			fresh_large_cells["%d:%d" % [x, z]] = fresh_large_cell
			cultivated_large_cells["%d:%d" % [x, z]] = FARM_SIMULATION.complete_tilling(fresh_large_cell)
	async_projection.setup({"plot_id": "async_soil_test", "cell_size": 1.25, "cells": fresh_large_cells}, async_farm)
	var first_large_footprint := cultivated_large_cells.duplicate(true)
	first_large_footprint.erase("15:15")
	async_projection.update_state({"plot_id": "async_soil_test", "cell_size": 1.25, "cells": first_large_footprint})
	_expect(async_projection._soil_build_active, "large connected-soil footprints build off the main thread")
	async_projection.update_state({"plot_id": "async_soil_test", "cell_size": 1.25, "cells": cultivated_large_cells})
	_expect(async_projection._soil_pending_valid, "soil footprint changes coalesce behind an active mesh build")
	var async_wait_frames := 0
	while (async_projection._soil_build_active or async_projection._soil_pending_valid) and async_wait_frames < 600:
		await process_frame
		async_wait_frames += 1
	var async_soil := async_projection.get_node_or_null("Cells/ConnectedSoil") as MeshInstance3D
	var async_vertex_count: int = async_soil.mesh.surface_get_array_len(0) if async_soil != null and async_soil.mesh != null and async_soil.mesh.get_surface_count() == 1 else -1
	var expected_async_mesh: ArrayMesh = PROJECTION.build_connected_soil_mesh(cultivated_large_cells, 1.25)
	var expected_async_vertex_count := expected_async_mesh.surface_get_array_len(0)
	_expect(not async_projection._soil_build_active and not async_projection._soil_pending_valid and async_vertex_count == expected_async_vertex_count, "coalesced async soil builds apply only the latest 256-cell connected mesh with a sealed perimeter")
	var reclaimed_soil_task_count := int(_optional_property(async_projection, "_soil_reclaimed_task_count", -1))
	_expect(reclaimed_soil_task_count >= 2, "every completed connected-soil worker task is awaited and reclaimed")
	_expect(int(_optional_property(async_projection, "_soil_last_reclaim_result", FAILED)) == OK, "normal soil completion keeps the successful result returned by worker-task reclamation")
	async_projection.free()
	async_farm.free()
	var supersede_farm := CropFarm.new()
	root.add_child(supersede_farm)
	var supersede_projection := PROJECTION.new()
	root.add_child(supersede_projection)
	supersede_projection.setup({"plot_id": "async_soil_supersede_test", "cell_size": 1.25, "cells": fresh_large_cells}, supersede_farm)
	supersede_projection.update_state({"plot_id": "async_soil_supersede_test", "cell_size": 1.25, "cells": first_large_footprint})
	supersede_projection.update_state({"plot_id": "async_soil_supersede_test", "cell_size": 1.25, "cells": cultivated_large_cells})
	_expect(supersede_projection._soil_build_active and supersede_projection._soil_pending_valid, "supersession fixture reaches active-plus-pending soil work")
	supersede_projection.update_state({"plot_id": "async_soil_supersede_test", "cell_size": 1.25, "cells": fresh_large_cells})
	var superseded_soil := supersede_projection.get_node_or_null("Cells/ConnectedSoil") as MeshInstance3D
	_expect(not supersede_projection._soil_pending_valid and supersede_projection._soil_pending_cells.is_empty(), "empty soil update releases the superseded queued cell snapshot immediately")
	var supersede_wait_frames := 0
	while supersede_projection._soil_build_active and supersede_wait_frames < 600:
		await process_frame
		supersede_wait_frames += 1
	_expect(
		not supersede_projection._soil_pending_valid
		and supersede_projection._soil_pending_cells.is_empty()
		and superseded_soil != null
		and superseded_soil.mesh != null
		and superseded_soil.mesh.get_surface_count() == 0,
		"superseded async completion cannot retain queued cells or restore stale soil"
	)
	supersede_projection.free()
	supersede_farm.free()
	var teardown_farm := CropFarm.new()
	root.add_child(teardown_farm)
	var teardown_projection := PROJECTION.new()
	root.add_child(teardown_projection)
	teardown_projection.setup({"plot_id": "async_soil_teardown_test", "cell_size": 1.25, "cells": fresh_large_cells}, teardown_farm)
	teardown_projection.update_state({"plot_id": "async_soil_teardown_test", "cell_size": 1.25, "cells": first_large_footprint})
	_expect(teardown_projection._soil_build_active, "teardown fixture starts an active connected-soil worker task")
	teardown_projection.update_state({"plot_id": "async_soil_teardown_test", "cell_size": 1.25, "cells": cultivated_large_cells})
	_expect(teardown_projection._soil_pending_valid, "teardown fixture queues a coalesced soil rebuild")
	root.remove_child(teardown_projection)
	_expect(
		teardown_projection._soil_task_id < 0
		and not teardown_projection._soil_build_active
		and not teardown_projection._soil_pending_valid
		and teardown_projection._soil_pending_cells.is_empty()
		and int(_optional_property(teardown_projection, "_soil_last_reclaim_result", FAILED)) == OK,
		"exiting projection reclaims its active worker and discards queued soil work"
	)
	for frame in 3:
		await process_frame
	_expect(teardown_projection._soil_task_id < 0 and not teardown_projection._soil_build_active and not teardown_projection._soil_pending_valid, "deferred completion cannot launch soil work after projection exit")
	teardown_projection.free()
	teardown_farm.free()
	_expect(FileAccess.file_exists("res://assets/vendor/larkart-store/stylized-soil-02a/LICENSE_RECORD.md"), "purchased soil keeps a local license record")
	var color_import_source := FileAccess.get_file_as_string("res://assets/vendor/larkart-store/stylized-soil-02a/T_Soil02A_C.png.import")
	_expect(color_import_source.contains("compress/mode=2") and color_import_source.contains("mipmaps/generate=true"), "soil color texture is VRAM-compressed and mipmapped for a runtime 3D surface")
	var normal_import_source := FileAccess.get_file_as_string("res://assets/vendor/larkart-store/stylized-soil-02a/T_Soil02A_N.png.import")
	_expect(normal_import_source.contains("compress/normal_map=1") and normal_import_source.contains("mipmaps/generate=true"), "soil normal texture uses normal-map compression and mipmaps")
	var attribution_source := FileAccess.get_file_as_string("res://ATTRIBUTION.md")
	_expect(attribution_source.contains("39477e0b-a19e-45cf-be76-77240006462e") and attribution_source.contains("LarkArt Store"), "purchased soil is listed in canonical attribution")
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
	var settlement_field_source := FileAccess.get_file_as_string("res://features/settlements/bridge/settlement_field.gd")
	_expect(not settlement_field_source.contains("func _ensure_footprint_visual") and settlement_field_source.contains("_remove_legacy_footprint_visual"), "Fields must never create persistent green tile visuals and must remove old serialized ones")
	var field_painter_source := FileAccess.get_file_as_string("res://addons/world_authoring/field_painter.gd")
	_expect(field_painter_source.contains("BORDER_THICKNESS") and field_painter_source.contains("_append_border_segment"), "Editor field painting must draw only the selected footprint border")
	var rustwash_source := FileAccess.get_file_as_string("res://scenes/zones/rustwash_basin/rustwash_basin.tscn")
	_expect(not rustwash_source.contains("[node name=\"FootprintVisual\""), "Rustwash must not serialize developer-only field tile visuals into runtime")
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _test_terrain_height(position: Vector3) -> float:
	return 0.2 + position.x * 0.08 + position.z * 0.03


func _optional_property(object: Object, property_name: String, default_value: Variant) -> Variant:
	for property in object.get_property_list():
		if str(property.get("name", "")) == property_name:
			return object.get(property_name)
	return default_value


func _finish() -> void:
	if failures.is_empty():
		print("FARM_PAINTING_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FARM_PAINTING_FAILED count=%d" % failures.size())
	quit(1)
