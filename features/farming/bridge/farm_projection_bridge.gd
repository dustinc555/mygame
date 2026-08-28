extends Node

class_name FarmProjectionBridge

const SERVICE_ID := &"farm_projection"
const PLOT_SCRIPT := preload("res://features/farming/projection/farm_plot_projection.gd")
const FARM_CONTROLLER := preload("res://features/farming/sim/farm_controller.gd")

var _context: BootstrapContext
var _farm: Node
var _gecs: Node
var _root: Node3D
var _plots: Dictionary = {}
var _terrain_height_sampler := Callable()


func initialize(context: BootstrapContext) -> void:
	_context = context
	_farm = context.get_optional(FARM_CONTROLLER.SERVICE_ID)
	_gecs = context.get_optional(&"gecs_world")
	_root = Node3D.new()
	_root.name = "FarmPlots"
	context.projection_root.add_child(_root)
	if _farm == null:
		return
	_farm.plot_changed.connect(_on_plot_changed)
	_farm.plot_cells_changed.connect(_on_plot_cells_changed)
	_farm.plot_removed.connect(_on_plot_removed)
	var terrain_camera := context.get_optional(&"terrain_camera")
	if terrain_camera != null and terrain_camera.has_method("get_terrain_height"):
		_terrain_height_sampler = Callable(terrain_camera, "get_terrain_height")
	if _gecs != null and not _gecs.world_reindexed.is_connected(_on_world_reindexed):
		_gecs.world_reindexed.connect(_on_world_reindexed)
	_synchronize_projections()


func teardown() -> void:
	if _farm != null and is_instance_valid(_farm) and _farm.plot_cells_changed.is_connected(_on_plot_cells_changed):
		_farm.plot_cells_changed.disconnect(_on_plot_cells_changed)
	if _gecs != null and _gecs.world_reindexed.is_connected(_on_world_reindexed):
		_gecs.world_reindexed.disconnect(_on_world_reindexed)
	_gecs = null
	_farm = null


func _on_world_reindexed() -> void:
	_synchronize_projections.call_deferred()


func _synchronize_projections() -> void:
	if _farm == null:
		return
	var loaded: Dictionary = _farm.get_plots()
	for plot_id_value in _plots.keys().duplicate():
		var plot_id := str(plot_id_value)
		if not loaded.has(plot_id):
			_on_plot_removed(plot_id)
	for plot_id_value in loaded.keys():
		var plot_id := str(plot_id_value)
		_on_plot_changed(plot_id, loaded[plot_id_value])


func _on_plot_changed(plot_id: String, state: Dictionary) -> void:
	var projection = _plots.get(plot_id)
	if projection == null or not is_instance_valid(projection):
		projection = PLOT_SCRIPT.new()
		_root.add_child(projection)
		projection.set_terrain_height_sampler(_terrain_height_sampler)
		projection.setup(state, _farm)
		_plots[plot_id] = projection
	else:
		projection.update_state(state)


func _on_plot_cells_changed(plot_id: String, changed_cells: Dictionary, _settlement_id: String) -> void:
	var projection = _plots.get(plot_id)
	if projection != null and is_instance_valid(projection):
		projection.update_cells_state(changed_cells)
func _on_plot_removed(plot_id: String) -> void:
	var projection = _plots.get(plot_id)
	if projection != null and is_instance_valid(projection):
		projection.queue_free()
	_plots.erase(plot_id)
