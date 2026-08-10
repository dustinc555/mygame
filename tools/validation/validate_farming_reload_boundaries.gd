extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_farming_reload_boundaries.gd

const PROJECTION_BRIDGE = preload("res://features/farming/bridge/farm_projection_bridge.gd")
const WORK_BRIDGE = preload("res://features/farming/bridge/farm_work_bridge.gd")
const WATER_SOURCE = preload("res://features/farming/projection/farm_water_source.gd")

class FakeGecs:
	extends Node
	signal world_reindexed
	var water_states: Dictionary = {}
	func get_farm_water_source_states() -> Dictionary:
		return water_states.duplicate(true)
	func upsert_farm_water_source_state(state: Dictionary) -> Dictionary:
		water_states[str(state.get("source_id", ""))] = state.duplicate(true)
		return state.duplicate(true)

class FakeTime:
	extends Node
	signal minute_changed(absolute_minute: int, day: int, hour: int, minute: int)
	func get_absolute_minute() -> int:
		return 10

class FakeFarm:
	extends Node
	signal plot_changed(plot_id: String, state: Dictionary)
	signal plot_removed(plot_id: String)
	signal water_source_changed(source_id: String, state: Dictionary)
	var plots: Dictionary = {}
	var gecs: FakeGecs
	func get_plots() -> Dictionary:
		return plots.duplicate(true)
	func get_plot(plot_id: String) -> Dictionary:
		return (plots.get(plot_id, {}) as Dictionary).duplicate(true)
	func get_crop(_crop_id: String):
		return null
	func register_water_source(state: Dictionary) -> Dictionary:
		var source_id := str(state.get("source_id", ""))
		if not gecs.water_states.has(source_id):
			gecs.upsert_farm_water_source_state(state)
		return (gecs.water_states.get(source_id, {}) as Dictionary).duplicate(true)
	func get_water_source(source_id: String) -> Dictionary:
		return (gecs.water_states.get(source_id, {}) as Dictionary).duplicate(true)
	func draw_water_source(_source_id: String, requested: float) -> float:
		return requested

class FakeActor:
	extends Node3D

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene_root := Node3D.new()
	root.add_child(scene_root)
	var projection_root := Node3D.new()
	scene_root.add_child(projection_root)
	var context := BootstrapContext.new(scene_root)
	context.projection_root = projection_root
	var gecs := FakeGecs.new()
	var time := FakeTime.new()
	var farm := FakeFarm.new()
	farm.gecs = gecs
	scene_root.add_child(gecs)
	scene_root.add_child(time)
	scene_root.add_child(farm)
	context.register(&"gecs_world", gecs)
	context.register(&"world_time", time)
	context.register(&"farming", farm)

	farm.plots["farm:old"] = _plot("farm:old")
	var projections = PROJECTION_BRIDGE.new()
	scene_root.add_child(projections)
	projections.initialize(context)
	await process_frame
	farm.plots.clear()
	farm.plots["farm:new"] = _plot("farm:new")
	gecs.world_reindexed.emit()
	await process_frame
	await process_frame
	_expect(not projections._plots.has("farm:old") and projections._plots.has("farm:new"), "in-place load removes stale plot projections and realizes loaded plots")

	# Projection teardown/rebuild is never a recovery event. It must reproduce the
	# same authoritative physical soil before the deadline, then stay natural once
	# GECS has advanced the cell to recovered state.
	farm.plots.clear()
	farm.plots["farm:recover"] = _plot("farm:recover", true)
	gecs.world_reindexed.emit()
	await process_frame
	await process_frame
	var before_projection = projections._plots.get("farm:recover")
	_expect(before_projection != null and before_projection._soil_surface.mesh.get_surface_count() == 1, "fresh authoritative soil renders before recovery")
	farm.plots.clear()
	gecs.world_reindexed.emit()
	await process_frame
	await process_frame
	farm.plots["farm:recover"] = _plot("farm:recover", true)
	gecs.world_reindexed.emit()
	await process_frame
	await process_frame
	var reloaded_before = projections._plots.get("farm:recover")
	_expect(reloaded_before != null and reloaded_before._soil_surface.mesh.get_surface_count() == 1, "unload and reload before elapsed recovery preserves physical soil")
	var recovered_state := _plot("farm:recover", false)
	farm.plots["farm:recover"] = recovered_state
	farm.plot_changed.emit("farm:recover", recovered_state)
	await process_frame
	var recovered_projection = projections._plots.get("farm:recover")
	_expect(recovered_projection != null and recovered_projection._soil_surface.mesh.get_surface_count() == 0, "authoritative elapsed recovery removes projected soil")
	_expect((recovered_state.get("cells", {}) as Dictionary).has("0:0"), "recovery keeps logical field membership")
	farm.plots.clear()
	gecs.world_reindexed.emit()
	await process_frame
	await process_frame
	farm.plots["farm:recover"] = recovered_state
	gecs.world_reindexed.emit()
	await process_frame
	await process_frame
	var reloaded_after = projections._plots.get("farm:recover")
	_expect(reloaded_after != null and reloaded_after._soil_surface.mesh.get_surface_count() == 0, "rebuild after recovery never restores stale cultivated geometry")

	var work = WORK_BRIDGE.new()
	scene_root.add_child(work)
	work.initialize(context)
	var actor := FakeActor.new()
	scene_root.add_child(actor)
	work._assignments[actor.get_instance_id()] = {"actor": actor}
	gecs.world_reindexed.emit()
	await process_frame
	_expect(work._assignments.is_empty(), "in-place load cancels volatile live farm assignments")

	gecs.water_states["reload_well"] = {
		"source_id": "reload_well", "capacity": 20.0, "current_water": 9.0,
		"renewable": false, "recharge_per_world_minute": 0.0, "last_processed_minute": 10,
	}
	BootstrapContext.active = context
	var source = WATER_SOURCE.new()
	source.source_id = "reload_well"
	scene_root.add_child(source)
	await process_frame
	source._bind_durable_state()
	_expect(is_equal_approx(source.current_water, 9.0), "water projection binds controller state")
	gecs.water_states["reload_well"]["current_water"] = 3.0
	gecs.world_reindexed.emit()
	await process_frame
	await process_frame
	_expect(is_equal_approx(source.current_water, 3.0), "in-place load refreshes water source projections")

	BootstrapContext.active = null
	scene_root.free()
	_finish()


func _plot(plot_id: String, soil_created := false) -> Dictionary:
	return {
		"plot_id": plot_id,
		"dimensions": Vector2i.ONE,
		"cell_size": 1.25,
		"cells": {
			"0:0": {
				"grid_position": Vector2i.ZERO,
				"world_position": Vector3.ZERO,
				"state": "tilled" if soil_created else "untilled",
				"soil_created": soil_created,
				"crop_id": "",
			},
		},
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("FARMING_RELOAD_BOUNDARIES_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("FARMING_RELOAD_BOUNDARIES_FAILED count=%d" % failures.size())
	quit(1)