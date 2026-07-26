extends Node

class_name WorldLightLodController

const SERVICE_ID := &"world_light_lod"
const POPULATION_REALIZATION_SERVICE_ID := &"population_realization"
const CELL_SIZE := 64.0
const UPDATE_INTERVAL_SECONDS := 0.2
const ACTIVATION_MARGIN := 4.0

var _realization: Node
var _records: Dictionary = {}
var _light_ids_by_cell: Dictionary = {}
var _active_light_ids: Dictionary = {}
var _update_remaining := 0.0


func initialize(context: BootstrapContext) -> void:
	_realization = context.require(POPULATION_REALIZATION_SERVICE_ID)
	_register_existing_fixtures.call_deferred()


func _exit_tree() -> void:
	for record in _records.values():
		_restore_fade(record)


func _process(delta: float) -> void:
	_update_remaining -= delta
	if _update_remaining > 0.0:
		return
	_update_remaining = UPDATE_INTERVAL_SECONDS
	_reconcile()


func register_light(light: Light3D) -> void:
	if light == null or not is_instance_valid(light) or not light.is_inside_tree():
		return
	var light_id := light.get_instance_id()
	if _records.has(light_id):
		return
	var cell := _cell_for_position(light.global_position)
	_records[light_id] = {
		"light": weakref(light),
		"cell": cell,
		"distance_fade_enabled": light.distance_fade_enabled,
	}
	var bucket: Dictionary = _light_ids_by_cell.get(cell, {})
	bucket[light_id] = true
	_light_ids_by_cell[cell] = bucket
	_update_remaining = 0.0


func unregister_light(light: Light3D) -> void:
	if light == null:
		return
	_remove_record(light.get_instance_id(), true)


func _register_existing_fixtures() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for fixture in tree.get_nodes_in_group("light_fixture"):
		if fixture.has_method("get_light_node"):
			register_light(fixture.call("get_light_node") as Light3D)


func _reconcile() -> void:
	if _realization == null:
		return
	var anchors: Array[Vector3] = []
	for value in _realization.call("get_realization_anchor_positions"):
		if value is Vector3:
			anchors.append(value)
	var radius := float(_realization.call("get_visible_radius")) + ACTIVATION_MARGIN
	var candidates := _candidate_light_ids(anchors, radius)
	var next_active := {}
	for light_id_value in candidates:
		var light_id := int(light_id_value)
		var record: Dictionary = _records.get(light_id, {})
		var light := _record_light(record)
		if light == null:
			_remove_record(light_id, false)
			continue
		if _is_near_any_anchor(light.global_position, anchors, radius):
			light.distance_fade_enabled = false
			next_active[light_id] = true
	for light_id_value in _active_light_ids:
		var light_id := int(light_id_value)
		if not next_active.has(light_id) and _records.has(light_id):
			_restore_fade(_records[light_id])
	_active_light_ids = next_active


func _candidate_light_ids(anchors: Array[Vector3], radius: float) -> Dictionary:
	var result := {}
	for anchor in anchors:
		var min_cell := _cell_for_position(anchor - Vector3(radius, 0.0, radius))
		var max_cell := _cell_for_position(anchor + Vector3(radius, 0.0, radius))
		for x in range(min_cell.x, max_cell.x + 1):
			for z in range(min_cell.y, max_cell.y + 1):
				for light_id in (_light_ids_by_cell.get(Vector2i(x, z), {}) as Dictionary):
					result[light_id] = true
	return result


func _remove_record(light_id: int, restore: bool) -> void:
	var record: Dictionary = _records.get(light_id, {})
	if record.is_empty():
		return
	if restore:
		_restore_fade(record)
	var cell: Vector2i = record.get("cell", Vector2i.ZERO)
	var bucket: Dictionary = _light_ids_by_cell.get(cell, {})
	bucket.erase(light_id)
	if bucket.is_empty():
		_light_ids_by_cell.erase(cell)
	_records.erase(light_id)
	_active_light_ids.erase(light_id)


func _restore_fade(record: Dictionary) -> void:
	var light := _record_light(record)
	if light != null:
		light.distance_fade_enabled = bool(record.get("distance_fade_enabled", false))


func _record_light(record: Dictionary) -> Light3D:
	var light_ref := record.get("light") as WeakRef
	if light_ref == null:
		return null
	var light := light_ref.get_ref() as Light3D
	return light if light != null and is_instance_valid(light) else null


func _cell_for_position(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x / CELL_SIZE), floori(position.z / CELL_SIZE))


func _is_near_any_anchor(position: Vector3, anchors: Array[Vector3], radius: float) -> bool:
	var radius_squared := radius * radius
	for anchor in anchors:
		var offset := position - anchor
		offset.y = 0.0
		if offset.length_squared() <= radius_squared:
			return true
	return false
