extends Node
class_name WorldZoneController

## Camera-focus geography, shared by consumers such as background music.
## Terrain3D regions already use world X/Z coordinates, even under moved parents.
## Index those cells once; camera movement never scans the scene or terrain maps.
const SERVICE_ID := &"world_zones"
signal zone_changed(zone: Zone)

var _scope: Node
var _camera_source: WorldInteractionController
var _terrains: Dictionary = {}
# Region width -> region cell -> terrain instance IDs (supports different scales).
var _cells: Dictionary = {}
var _pending: Dictionary = {}
var _focus := Vector3.INF
var _current_zone: WeakRef
var _current_zone_id := 0
var _initialized := false


func initialize(context: BootstrapContext) -> void:
	if _initialized:
		return
	_initialized = true
	_scope = context.root_scene
	var ancestor := _scope
	while ancestor != null:
		if ancestor is WorldRoot:
			_scope = ancestor
			break
		ancestor = ancestor.get_parent()
	_camera_source = context.get_optional(WorldInteractionController.SERVICE_ID) as WorldInteractionController
	if _camera_source != null:
		_camera_source.camera_focus_changed.connect(_on_camera_focus_changed)
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)
	if is_instance_valid(_scope):
		_register_subtree(_scope)
	if _camera_source != null:
		_on_camera_focus_changed(_camera_source.get_camera_focus_position())


func get_current_zone() -> Zone:
	return _current_zone.get_ref() as Zone if _current_zone != null else null


func get_zone_at_position(position: Vector3) -> Zone:
	if not position.is_finite():
		return null
	var result: Zone
	for width: float in _cells:
		var cell := Vector2i(floori(position.x / width), floori(position.z / width))
		for id: int in _cells[width].get(cell, {}):
			var zone := _terrains[id].zone.get_ref() as Zone
			if zone == null or not zone.is_inside_tree() or zone.is_queued_for_deletion():
				continue
			# Overlapping authored regions resolve by scene path, not event order.
			if result == null or str(zone.get_path()) < str(result.get_path()):
				result = zone
	return result


func _on_camera_focus_changed(position: Vector3) -> void:
	if position.x == _focus.x and position.z == _focus.z:
		return
	_focus = position
	_refresh_current_zone()


func _refresh_current_zone() -> void:
	var zone := get_zone_at_position(_focus)
	var id := zone.get_instance_id() if zone != null else 0
	if id == _current_zone_id:
		return
	_current_zone_id = id
	_current_zone = weakref(zone) if zone != null else null
	zone_changed.emit(zone)


func _register_subtree(node: Node) -> void:
	if node.is_class("Terrain3D"):
		_register_terrain(node)
	for child in node.get_children():
		_register_subtree(child)


func _register_terrain(terrain: Node) -> void:
	if not is_instance_valid(_scope) or not terrain.is_inside_tree() or terrain.is_queued_for_deletion():
		return
	if terrain != _scope and not _scope.is_ancestor_of(terrain):
		return
	var zone := terrain.get_parent()
	while zone != null and not zone is Zone:
		if zone == _scope:
			return
		zone = zone.get_parent()
	if zone == null:
		return
	var data: Object = terrain.get("data")
	if data == null:
		return
	var id := terrain.get_instance_id()
	_remove_terrain(id)
	var width := float(terrain.get("region_size")) * float(terrain.get("vertex_spacing"))
	if width <= 0.0:
		return
	# Native Terrain3D returns a live array; retain the cells we actually indexed.
	var locations: Array = data.get_region_locations().duplicate()
	var callback := _queue_terrain_refresh.bind(weakref(terrain))
	for signal_name in [&"maps_changed", &"region_map_changed"]:
		data.connect(signal_name, callback)
	_terrains[id] = {"zone": weakref(zone), "data": weakref(data),
		"width": width, "locations": locations, "callback": callback}
	var cells: Dictionary = _cells.get(width, {})
	for location: Vector2i in locations:
		var owners: Dictionary = cells.get(location, {})
		owners[id] = true
		cells[location] = owners
	_cells[width] = cells


func _remove_terrain(id: int) -> void:
	if not _terrains.has(id):
		return
	var entry: Dictionary = _terrains[id]
	var data: Object = entry.data.get_ref()
	if data != null:
		for signal_name in [&"maps_changed", &"region_map_changed"]:
			if data.is_connected(signal_name, entry.callback):
				data.disconnect(signal_name, entry.callback)
	var cells: Dictionary = _cells[entry.width]
	for location: Vector2i in entry.locations:
		var owners: Dictionary = cells[location]
		owners.erase(id)
		if owners.is_empty():
			cells.erase(location)
	if cells.is_empty():
		_cells.erase(entry.width)
	_terrains.erase(id)


func _on_node_added(node: Node) -> void:
	if node.is_class("Terrain3D"):
		_queue_terrain_refresh(weakref(node))


func _on_node_removed(node: Node) -> void:
	var id := node.get_instance_id()
	_pending.erase(id)
	if _terrains.has(id):
		_remove_terrain(id)
		_refresh_current_zone()


func _queue_terrain_refresh(reference: WeakRef) -> void:
	var terrain := reference.get_ref() as Node
	if terrain == null or not _initialized:
		return
	var needs_flush := _pending.is_empty()
	_pending[terrain.get_instance_id()] = reference
	if needs_flush:
		_flush_pending.call_deferred()


func _flush_pending() -> void:
	if not _initialized:
		return
	var pending := _pending.values()
	_pending.clear()
	for reference: WeakRef in pending:
		var terrain := reference.get_ref() as Node
		if terrain != null:
			_register_terrain(terrain)
	_refresh_current_zone()


func _exit_tree() -> void:
	_initialized = false
	_pending.clear()
	if is_instance_valid(_camera_source) and _camera_source.camera_focus_changed.is_connected(_on_camera_focus_changed):
		_camera_source.camera_focus_changed.disconnect(_on_camera_focus_changed)
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	if get_tree().node_removed.is_connected(_on_node_removed):
		get_tree().node_removed.disconnect(_on_node_removed)
	for id: int in _terrains.keys():
		_remove_terrain(id)
	_current_zone = null
	_current_zone_id = 0
	zone_changed.emit(null)
