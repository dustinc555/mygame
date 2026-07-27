extends Node

class_name BuildingOccupancyController

const SERVICE_ID := &"building_occupancy"
const CELL_SIZE := 64.0
const TICK_INTERVAL_SECONDS := 0.25
const MAX_TICKS_PER_FRAME := 8
const ACTOR_BROAD_PHASE_MARGIN := 2.0

var _projection_bridge: BuildingProjectionBridge
var _law_order: LawOrderController
var _party_manager: PartyManager
var _accumulator := 0.0
var _building_ids_by_cell: Dictionary = {}
var _cells_by_building_id: Dictionary = {}
var _building_ids_by_actor_id: Dictionary = {}
var _tracked_actor_ids: Dictionary = {}
var _tick_count := 0
var _exact_checks := 0
var _candidate_checks := 0


func initialize(context: BootstrapContext) -> void:
	_projection_bridge = context.require(BuildingProjectionBridge.SERVICE_ID) as BuildingProjectionBridge
	_law_order = context.require(LawOrderController.SERVICE_ID) as LawOrderController
	_party_manager = context.root_scene.get_node_or_null("PartyManager") as PartyManager
	if _party_manager == null:
		push_error("BuildingOccupancyController requires root_scene/PartyManager")
		return
	_projection_bridge.projection_bound.connect(_on_projection_bound)
	_projection_bridge.projection_unbound.connect(_on_projection_unbound)
	for building_id in _projection_bridge.get_bound_building_ids():
		var projection := _projection_bridge.get_projection(building_id)
		if projection != null:
			_index_building(building_id, projection)


func _process(delta: float) -> void:
	if _party_manager == null or _law_order == null:
		return
	_accumulator += delta
	var ticks := mini(int(_accumulator / TICK_INTERVAL_SECONDS), MAX_TICKS_PER_FRAME)
	if ticks <= 0:
		return
	_accumulator -= float(ticks) * TICK_INTERVAL_SECONDS
	if ticks == MAX_TICKS_PER_FRAME:
		_accumulator = minf(_accumulator, TICK_INTERVAL_SECONDS)
	for _tick in range(ticks):
		_update_occupancy()


func _update_occupancy() -> void:
	_tick_count += 1
	var current_actor_ids: Dictionary = {}
	for actor in _party_manager.party_members:
		if actor == null or not is_instance_valid(actor) or not actor.is_inside_tree():
			continue
		var actor_id := _stable_actor_id(actor)
		if actor_id.is_empty():
			continue
		current_actor_ids[actor_id] = true
		var next_building_ids: Array[String] = []
		var candidates: Dictionary = _building_ids_by_cell.get(_cell_for_position(actor.global_position), {})
		_candidate_checks += candidates.size()
		for candidate_id in candidates:
			var building_id := str(candidate_id)
			var projection := _projection_bridge.get_projection(building_id)
			if projection == null:
				continue
			_exact_checks += 1
			if projection.is_actor_inside(actor):
				next_building_ids.append(building_id)
		next_building_ids.sort()
		_set_actor_occupancy(actor_id, next_building_ids)
	for tracked_actor_id in _building_ids_by_actor_id.keys():
		var actor_id := str(tracked_actor_id)
		if not current_actor_ids.has(actor_id):
			_set_actor_occupancy(actor_id, [])
	_tracked_actor_ids = current_actor_ids


func _set_actor_occupancy(actor_id: String, building_ids: Array[String]) -> void:
	var previous := _stored_building_ids(actor_id)
	if previous == building_ids:
		return
	if building_ids.is_empty():
		_building_ids_by_actor_id.erase(actor_id)
	else:
		_building_ids_by_actor_id[actor_id] = building_ids.duplicate()
	_law_order.update_actor_building_occupancy(actor_id, building_ids)


func _on_projection_bound(building_id: String, projection: WorldBuilding) -> void:
	_index_building(building_id, projection)


func _on_projection_unbound(building_id: String, _projection: WorldBuilding) -> void:
	_unindex_building(building_id)
	for tracked_actor_id in _building_ids_by_actor_id.keys():
		var actor_id := str(tracked_actor_id)
		var current := _stored_building_ids(actor_id)
		if not current.has(building_id):
			continue
		var next := current.duplicate()
		next.erase(building_id)
		_set_actor_occupancy(actor_id, next)


func _index_building(building_id: String, projection: WorldBuilding) -> void:
	_unindex_building(building_id)
	if projection == null or not is_instance_valid(projection):
		return
	var bounds := projection.get_occupancy_world_aabb()
	if bounds.size.length_squared() <= 0.0:
		return
	bounds = bounds.grow(ACTOR_BROAD_PHASE_MARGIN)
	var min_cell := _cell_for_position(bounds.position)
	var max_cell := _cell_for_position(bounds.end)
	var cells: Array[Vector2i] = []
	for cell_x in range(min_cell.x, max_cell.x + 1):
		for cell_z in range(min_cell.y, max_cell.y + 1):
			var cell := Vector2i(cell_x, cell_z)
			cells.append(cell)
			if not _building_ids_by_cell.has(cell):
				_building_ids_by_cell[cell] = {}
			(_building_ids_by_cell[cell] as Dictionary)[building_id] = true
	_cells_by_building_id[building_id] = cells


func _unindex_building(building_id: String) -> void:
	var cells: Array = _cells_by_building_id.get(building_id, [])
	for cell in cells:
		var ids := _building_ids_by_cell.get(cell, {}) as Dictionary
		ids.erase(building_id)
		if ids.is_empty():
			_building_ids_by_cell.erase(cell)
	_cells_by_building_id.erase(building_id)


func _cell_for_position(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x / CELL_SIZE), floori(position.z / CELL_SIZE))


func _stable_actor_id(actor: WorldActor) -> String:
	var actor_id := actor.stable_id.strip_edges()
	if actor_id.is_empty() and actor.has_meta("actor_record_id"):
		actor_id = str(actor.get_meta("actor_record_id")).strip_edges()
	return actor_id


func get_building_id_for_actor(actor_id: String) -> String:
	var building_ids := get_building_ids_for_actor(actor_id)
	return building_ids[0] if not building_ids.is_empty() else ""


func get_building_ids_for_actor(actor_id: String) -> Array[String]:
	return _stored_building_ids(actor_id.strip_edges())


func is_actor_inside(actor_id: String, building_id: String) -> bool:
	var building_ids := _stored_building_ids(actor_id.strip_edges())
	return building_ids.has(building_id.strip_edges())


func _stored_building_ids(actor_id: String) -> Array[String]:
	var result: Array[String] = []
	result.assign(_building_ids_by_actor_id.get(actor_id, []))
	return result


func reset_metrics() -> void:
	_tick_count = 0
	_exact_checks = 0
	_candidate_checks = 0


func get_metrics() -> Dictionary:
	return {
		"tick_count": _tick_count,
		"exact_checks": _exact_checks,
		"candidate_checks": _candidate_checks,
		"tracked_actor_count": _tracked_actor_ids.size(),
		"indexed_building_count": _cells_by_building_id.size(),
	}


func _exit_tree() -> void:
	if _law_order == null or not is_instance_valid(_law_order):
		return
	for actor_id in _building_ids_by_actor_id.keys():
		_law_order.update_actor_building_occupancy(str(actor_id), [])
