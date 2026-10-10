extends RefCounted

## Converts authored/live world content into terrain snapshots and cartographic
## features. This is the sole scene-reading boundary; the atlas is data-only.
const RASTER := preload("res://features/world_map/projection/map_terrain_raster.gd")
const WATCH := preload("res://features/world_map/bridge/map_transform_watch.gd")
const FEATURE_CELL_METERS := 256.0
const ROAD_PIECE_METERS := 16.0
signal terrain_changed(area: Rect2)
signal features_changed

var raster := RASTER.new()
var _features: Dictionary = {}
var _feature_bins: Dictionary = {}
var _node_features: Dictionary = {}
var _terrain_patches: Dictionary = {}
var _watchers: Dictionary = {}
var _connections: Array[Dictionary] = []
var _pending: Dictionary = {}
var _terrain_edits: Dictionary = {}
var _disposed := false

func register_node(node: Node) -> void:
	if _disposed or not is_instance_valid(node) or node.is_queued_for_deletion():
		return
	if node.is_class("Terrain3D"):
		_register_terrain(node)
		return
	var id := node.get_instance_id()
	if not (node is WorldBuilding or node.is_in_group("settlement_town") or node is RoadNetwork):
		return
	_remove_node_features(id)
	var records: Array[Dictionary] = []
	if node is WorldBuilding:
		var polygons: Array[PackedVector2Array] = []
		_collect_building_polygons(node, polygons)
		polygons = _merge_footprints(polygons, _flat(node.global_position))
		if not polygons.is_empty():
			records.append({"id": "building:" + str(node.building_id), "kind": "building", "world": _flat(node.global_position), "polygons": polygons, "label": ""})
	elif node.is_in_group("settlement_town"):
		var label := str(node.name)
		var definition = node.get("settlement_definition")
		if definition != null:
			label = str(definition.get("display_name"))
		records.append({"id": "town:" + str(node.call("get_settlement_id")), "kind": "town", "world": _flat(node.global_position), "label": label})
	elif node is RoadNetwork:
		var seen := {}
		for waypoint in node.get_waypoints():
			for other in waypoint.get_connected_waypoints():
				var ends: Array[String] = [str(waypoint.get_waypoint_id()), str(other.get_waypoint_id())]
				ends.sort()
				var edge_id := "road:%s:%s:%s" % [node.get_network_id(), ends[0], ends[1]]
				if seen.has(edge_id):
					continue
				seen[edge_id] = true
				var start := _flat(waypoint.global_position)
				var end := _flat(other.global_position)
				var count := maxi(1, ceili(start.distance_to(end) / ROAD_PIECE_METERS))
				for i in range(count):
					var a := start.lerp(end, float(i) / count)
					var b := start.lerp(end, float(i + 1) / count)
					records.append({"id": edge_id + ":%d" % i, "kind": "road", "world": (a + b) * 0.5, "points": PackedVector2Array([a, b]), "label": ""})
			_watch(waypoint)
	var keys: Array[String] = []
	for record in records:
		var key: String = record["id"]
		_features[key] = record
		var cell := _feature_cell(record["world"])
		var bin: Dictionary = _feature_bins.get(cell, {})
		bin[key] = true
		_feature_bins[cell] = bin
		keys.append(key)
	_node_features[id] = keys
	_watch(node)
	features_changed.emit()

func unregister_node(node: Node) -> void:
	var id := node.get_instance_id()
	_remove_node_features(id)
	if _terrain_patches.has(id):
		var previous: Rect2 = raster.get_bounds()
		for key in _terrain_patches[id]:
			raster.remove_patch(key)
		_terrain_patches.erase(id)
		terrain_changed.emit(previous)
	if _watchers.has(id):
		var watcher = _watchers[id].get_ref()
		if is_instance_valid(watcher):
			watcher.queue_free()
		_watchers.erase(id)
	features_changed.emit()

func features_near(position: Vector2, radius: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var lo := _feature_cell(position - Vector2.ONE * radius)
	var hi := _feature_cell(position + Vector2.ONE * radius)
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			for id in _feature_bins.get(Vector2i(x, y), {}):
				var record: Dictionary = _features[id]
				if position.distance_squared_to(record["world"]) <= radius * radius:
					result.append(record)
	return result

func all_features() -> Array:
	return _features.values()

func queue_refresh(node: Node) -> void:
	if _disposed or not is_instance_valid(node):
		return
	if node is RoadWaypoint:
		node = node.get_road_network()
	if node == null:
		return
	_pending[node.get_instance_id()] = weakref(node)
	if _pending.size() == 1:
		_flush_pending.call_deferred()

func _flush_pending() -> void:
	var pending := _pending.values()
	_pending.clear()
	for reference: WeakRef in pending:
		var node = reference.get_ref()
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			register_node(node)

func _watch(node: Node3D) -> void:
	var id := node.get_instance_id()
	if _watchers.has(id):
		return
	var watcher := WATCH.new()
	watcher.name = "MapTransformWatch"
	node.add_child(watcher, false, Node.INTERNAL_MODE_BACK)
	watcher.moved.connect(_on_transform_changed.bind(weakref(node)))
	_watchers[id] = weakref(watcher)

func _on_transform_changed(reference: WeakRef) -> void:
	var node = reference.get_ref()
	if is_instance_valid(node):
		queue_refresh(node)

func _remove_node_features(id: int) -> void:
	for key in _node_features.get(id, []):
		if _features.has(key):
			var cell := _feature_cell(_features[key]["world"])
			var bin: Dictionary = _feature_bins.get(cell, {})
			bin.erase(key)
			if bin.is_empty():
				_feature_bins.erase(cell)
			_features.erase(key)
	_node_features.erase(id)

func _register_terrain(terrain: Node) -> void:
	var data: Object = terrain.get("data")
	if data == null:
		return
	var id := terrain.get_instance_id()
	var first := not _terrain_patches.has(id)
	var old_area: Rect2 = raster.get_bounds()
	var edited: Rect2 = _terrain_edits.get(id, Rect2())
	_terrain_edits.erase(id)
	var keys: Array[String] = []
	var region_world: float = float(terrain.get("region_size")) * float(terrain.get("vertex_spacing"))
	for location in data.get_region_locations():
		var region: Resource = data.get_region(location)
		var key := "%d:%d:%d" % [id, location.x, location.y]
		var area := Rect2(Vector2(location) * region_world, Vector2.ONE * region_world)
		keys.append(key)
		if not first and edited.has_area() and not area.intersects(edited, true) and _terrain_patches[id].has(key):
			continue
		var color: Image = region.get_color_map()
		if color != null and color.is_compressed():
			color = color.duplicate()
			color.decompress()
		raster.set_patch(key, area, region.get_height_map(), color, region.get_control_map())
	for old_key in _terrain_patches.get(id, []):
		if not keys.has(old_key):
			raster.remove_patch(old_key)
	_terrain_patches[id] = keys
	if first:
		if data.has_signal("maps_edited"):
			var callback := _on_terrain_edited.bind(weakref(terrain))
			data.connect("maps_edited", callback)
			_connections.append({"source": weakref(data), "signal": "maps_edited", "callback": callback})
		for signal_name in ["maps_changed", "region_map_changed"]:
			if data.has_signal(signal_name):
				var callback := _on_transform_changed.bind(weakref(terrain))
				data.connect(signal_name, callback)
				_connections.append({"source": weakref(data), "signal": signal_name, "callback": callback})
	var new_area: Rect2 = raster.get_bounds()
	terrain_changed.emit(edited if edited.has_area() else (old_area.merge(new_area) if old_area.has_area() else new_area))

func _on_terrain_edited(area: AABB, reference: WeakRef) -> void:
	var terrain = reference.get_ref()
	if not is_instance_valid(terrain):
		return
	var id: int = terrain.get_instance_id()
	var flat := Rect2(Vector2(area.position.x, area.position.z), Vector2(area.size.x, area.size.z)).grow(float(terrain.get("vertex_spacing")))
	var previous: Rect2 = _terrain_edits.get(id, Rect2())
	_terrain_edits[id] = previous.merge(flat) if previous.has_area() else flat
	queue_refresh(terrain)

func _collect_building_polygons(node: Node, result: Array[PackedVector2Array]) -> void:
	# Read structural meshes, including roofs hidden by the gameplay camera.
	# Furniture, actors and generated editor guides are not building geography.
	if node.name == &"Furniture" or node is WorldActor or node is CollisionShape3D:
		return
	if node is MeshInstance3D and node.mesh != null:
		var bounds: AABB = node.mesh.get_aabb()
		var points := PackedVector2Array()
		for x in [bounds.position.x, bounds.end.x]:
			for y in [bounds.position.y, bounds.end.y]:
				for z in [bounds.position.z, bounds.end.z]:
					points.append(_flat(node.global_transform * Vector3(x, y, z)))
		var hull := Geometry2D.convex_hull(points)
		if hull.size() >= 4:
			hull.remove_at(hull.size() - 1)
			result.append(hull)
	for child in node.get_children():
		_collect_building_polygons(child, result)

static func _merge_footprints(polygons: Array[PackedVector2Array], origin: Vector2) -> Array[PackedVector2Array]:
	# Work near the building origin, not large continental coordinates. Join
	# touching modular roof/floor pieces so the map shows silhouettes, not a
	# debug wireframe of every authored mesh.
	var merged: Array[PackedVector2Array] = []
	for polygon in polygons:
		var candidate := PackedVector2Array()
		for point in polygon:
			candidate.append(point - origin)
		if Geometry2D.triangulate_polygon(candidate).is_empty():
			continue
		var i := 0
		while i < merged.size():
			var union: Array[PackedVector2Array] = Geometry2D.merge_polygons(candidate, merged[i])
			if union.size() == 1:
				candidate = union[0]
				merged.remove_at(i)
				i = 0
			else:
				i += 1
		merged.append(candidate)
	for index in range(merged.size()):
		var polygon := merged[index]
		for i in range(polygon.size()):
			polygon[i] += origin
		merged[index] = polygon
	return merged

func dispose() -> void:
	_disposed = true
	_pending.clear()
	for connection in _connections:
		var source = connection["source"].get_ref()
		if is_instance_valid(source) and source.is_connected(connection["signal"], connection["callback"]):
			source.disconnect(connection["signal"], connection["callback"])
	_connections.clear()
	for reference: WeakRef in _watchers.values():
		var watcher = reference.get_ref()
		if is_instance_valid(watcher) and not watcher.is_queued_for_deletion():
			watcher.queue_free()
	_watchers.clear()

static func _flat(position: Vector3) -> Vector2:
	return Vector2(position.x, position.z)

static func _feature_cell(position: Vector2) -> Vector2i:
	return Vector2i((position / FEATURE_CELL_METERS).floor())
