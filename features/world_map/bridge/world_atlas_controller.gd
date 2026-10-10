extends Node

## Bounded map-tile work and LRU residency. The renderer consumes immutable
## data snapshots, not scene nodes, and never changes the gameplay camera.
const SERVICE_ID := &"world_atlas"
const SOURCE := preload("res://features/world_map/bridge/map_world_source.gd")
const DEFAULT_SETTINGS := preload("res://features/world_map/resources/default_world_map_settings.tres")
const TILE_METERS := 256.0
const TILE_PIXELS := 128
const TARGET_TILE_PIXELS := 192.0
signal tile_ready(key: Vector3i)
signal bounds_changed

var source := SOURCE.new()
var settings: Resource = DEFAULT_SETTINGS
var bounds := Rect2()
var _root: Node
var _exploration: Node
var _cache: Dictionary = {}
var _visible: Dictionary = {}
var _queue: Array[Vector3i] = []
var _revisions: Dictionary = {}
var _access := 0
var _thread: Thread
var _job_key := Vector3i.ZERO
var _job_revision := 0
var _shutting_down := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	source.terrain_changed.connect(invalidate)

func initialize(context: BootstrapContext) -> void:
	_exploration = context.get_optional(&"map_exploration")
	if is_instance_valid(_exploration):
		settings = _exploration.settings
		_root = _exploration.world_root
		_exploration.feature_source = source
		source.features_changed.connect(_exploration.refresh_observed_features)
	else:
		_root = context.root_scene
	_scan(_root)
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)
	if is_instance_valid(_exploration):
		_exploration.observe_party()

func request_view(area: Rect2, pixels_per_meter: float) -> Array[Dictionary]:
	_visible.clear()
	_queue.clear()
	if not area.has_area() or not bounds.has_area():
		set_process(not is_idle())
		return []
	# Keep even large windows inside the configured resident budget. Reserve
	# room for boundary tiles, then select detail from screen-space density.
	var screen_area := area.get_area() * pixels_per_meter * pixels_per_meter
	var target := maxf(TARGET_TILE_PIXELS, sqrt(screen_area / maxf(4, settings.resident_tile_limit / 4.0)))
	var level := clampi(floori(log(target / maxf(0.001, TILE_METERS * pixels_per_meter)) / log(2.0)), -3, 20)
	var span := TILE_METERS * pow(2.0, level)
	var lo := Vector2i((area.position / span).floor())
	var hi := Vector2i(((area.end - Vector2.ONE * 0.001) / span).floor())
	var result: Array[Dictionary] = []
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var key := Vector3i(level, x, y)
			var tile_area := tile_rect(key)
			if bounds.has_area() and not bounds.intersects(tile_area):
				continue
			_visible[key] = true
			_access += 1
			var entry: Dictionary = _cache.get(key, {})
			if not entry.is_empty():
				entry["used"] = _access
			else:
				_queue.append(key)
			result.append({"key": key, "rect": tile_area, "texture": entry.get("texture")})
	_queue.sort_custom(func(a: Vector3i, b: Vector3i): return tile_rect(a).get_center().distance_squared_to(area.get_center()) < tile_rect(b).get_center().distance_squared_to(area.get_center()))
	set_process(not is_idle())
	_evict()
	return result

func invalidate(area: Rect2) -> void:
	bounds = source.raster.get_bounds()
	for key in _cache.keys():
		if tile_rect(key).intersects(area, true):
			_cache.erase(key)
	if _thread != null and tile_rect(_job_key).intersects(area, true):
		_revisions[_job_key] = int(_revisions.get(_job_key, 0)) + 1
	for key in _visible:
		if not _cache.has(key) and not _queue.has(key):
			_queue.append(key)
	bounds_changed.emit()
	set_process(not is_idle())

func is_idle() -> bool:
	return _thread == null and _queue.is_empty()

func resident_tile_count() -> int:
	return _cache.size()

func _process(_delta: float) -> void:
	if _thread != null:
		if _thread.is_alive():
			return
		var image: Image = _thread.wait_to_finish()
		_thread = null
		if _job_revision == int(_revisions.get(_job_key, 0)) and _visible.has(_job_key):
			_cache[_job_key] = {"texture": ImageTexture.create_from_image(image), "used": _access}
			tile_ready.emit(_job_key)
		_evict()
	while not _queue.is_empty():
		var key: Vector3i = _queue.pop_front()
		if _cache.has(key) or not _visible.has(key):
			continue
		_job_key = key
		_job_revision = int(_revisions.get(key, 0))
		var area := tile_rect(key)
		var snapshot: Dictionary = source.raster.snapshot(area.grow(area.size.x / TILE_PIXELS))
		_thread = Thread.new()
		var error := _thread.start(source.raster.render.bind(area, TILE_PIXELS, snapshot, settings.raster_style()))
		if error != OK:
			_thread = null
			push_error("World map tile worker could not start: %s" % error_string(error))
		break
	set_process(not is_idle())

func _evict() -> void:
	var limit: int = clampi(settings.resident_tile_limit, 32, 512)
	if _cache.size() <= limit:
		return
	var candidates: Array = _cache.keys()
	candidates.sort_custom(func(a, b): return int(_cache[a]["used"]) < int(_cache[b]["used"]))
	for key in candidates:
		if not _visible.has(key):
			_cache.erase(key)
		if _cache.size() <= limit:
			break

func _scan(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node.is_class("Terrain3D") or node is WorldBuilding or node is RoadNetwork or node.is_in_group("settlement_town"):
		source.register_node(node)
	for child in node.get_children():
		_scan(child)

func _on_node_added(node: Node) -> void:
	if _shutting_down or not is_instance_valid(_root) or not _root.is_ancestor_of(node):
		return
	if node.is_class("Terrain3D") or node is WorldBuilding or node is RoadNetwork or node.has_method("get_settlement_id"):
		source.queue_refresh(node)
	elif node is ModularBuildingPiece or node is RoadWaypoint:
		var owner_node := node.get_parent()
		while owner_node != null and owner_node != _root:
			if owner_node is WorldBuilding or owner_node is RoadNetwork:
				source.queue_refresh(owner_node)
				break
			owner_node = owner_node.get_parent()

func _on_node_removed(node: Node) -> void:
	if _shutting_down:
		return
	if node.is_class("Terrain3D") or node is WorldBuilding or node is RoadNetwork or node.is_in_group("settlement_town"):
		source.unregister_node(node)

func _exit_tree() -> void:
	_shutting_down = true
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	source.dispose()
	_queue.clear()
	_cache.clear()

static func tile_rect(key: Vector3i) -> Rect2:
	var span := TILE_METERS * pow(2.0, key.x)
	return Rect2(Vector2(key.y, key.z) * span, Vector2.ONE * span)
