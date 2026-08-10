extends Node

class_name FarmObstructionBridge

const SERVICE_ID := &"farm_obstructions"
const FARM_CONTROLLER := preload("res://features/farming/sim/farm_controller.gd")
const SOLVER := preload("res://features/farming/bridge/farm_placement_solver.gd")

@export_range(0.2, 10.0, 0.1) var rescan_seconds := 2.0

var _context: BootstrapContext
var _farm: Node
var _rescan_timer: Timer


func initialize(context: BootstrapContext) -> void:
	_context = context
	_farm = context.get_optional(FARM_CONTROLLER.SERVICE_ID)
	_rescan_timer = Timer.new()
	_rescan_timer.wait_time = rescan_seconds
	_rescan_timer.autostart = true
	_rescan_timer.timeout.connect(_rescan_all)
	add_child(_rescan_timer)


func teardown() -> void:
	if _rescan_timer != null and is_instance_valid(_rescan_timer):
		_rescan_timer.stop()
		_rescan_timer.queue_free()
	_rescan_timer = null
	_context = null
	_farm = null


func _rescan_all() -> void:
	var viewport := get_viewport()
	if viewport == null or viewport.world_3d == null:
		return
	var space := viewport.world_3d.direct_space_state
	for plot_value in _farm.get_plots().values():
		var plot: Dictionary = plot_value
		var cells: Dictionary = plot.get("cells", {})
		var positions: Array[Vector3] = []
		var cell_keys := PackedStringArray()
		for key_value in cells.keys():
			var cell: Dictionary = cells[key_value]
			positions.append(cell.get("world_position", Vector3.ZERO))
			cell_keys.append(str(key_value))
		var sampled: Dictionary = SOLVER.sample_grid(space, {
			"positions": positions,
			"cell_keys": cell_keys,
			"cell_size": float(plot.get("cell_size", 1.25)),
			"dimensions": plot.get("dimensions", Vector2i.ONE),
			"ignore_groups": PackedStringArray(["farm_plot"]),
			"ignore_characters": true,
		})
		var samples: Array = sampled.get("samples", [])
		var blocked_cells: Dictionary = sampled.get("blocked_cells", {})
		for index in mini(samples.size(), positions.size()):
			var key := cell_keys[index] if index < cell_keys.size() else ""
			if key.is_empty():
				continue
			var cell: Dictionary = cells.get(key, {})
			var blocked_now := blocked_cells.has(key)
			var blocked_before := str(cell.get("state", "")) == "blocked"
			if blocked_now != blocked_before:
				_farm.refresh_obstacle(str(plot.get("plot_id", "")), key, blocked_now, str(blocked_cells.get(key, "obstacle")))
