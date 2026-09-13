extends Node

class_name WorldNavigationController

## Runtime navigation authority. The world is a grid of navmesh tiles
## (terrain source geometry from all Terrain3D nodes + static scene colliders
## per tile -- walls carve, stair ramps connect, neighboring tiles stitch
## flush via the shared WorldNavBakePipeline).
##
## Startup order of preference:
## 1. Load the world's prebaked navcache from disk (seconds; baked in the
##    editor via the world_authoring plugin's "Bake World Nav", or the CLI
##    tools/bake_world_navcache.gd). Tiles touched by runtime-spawned content
##    (ZoneLoader towns) are re-baked behind a short loading gate.
## 2. No/stale cache: bake the whole world once behind the loading gate.
## After the gate releases the game NEVER gates again; dynamic changes (a
## building or furniture StaticBody3D entering/leaving the tree) re-bake only
## the tiles the object touches, queued for background baking.
##
## Tuning lives in a WorldNavigationSettings resource; the Nav Debug window
## tunes the live game and draws the navmesh and tile grid.
##
## Scenes must NOT ship hand-authored NavigationRegion3D nodes. Generated
## NavigationMesh resources belong in the world cache; collision is the source.
##
## Modes, chosen once on activation:
## - DORMANT: the scene ships an authored NavigationRegion3D (legacy zones).
## - TILED: Terrain3D present (the open world).
## - FULL_SCENE: no terrain (test levels); one whole-scene bake, re-baked
##   when geometry changes.

const SERVICE_ID := &"world_navigation"

const PIPELINE := preload("res://features/core/navigation/world_nav_bake_pipeline.gd")
const DEFAULT_SETTINGS_PATH := "res://features/core/navigation/resources/world_navigation_settings.tres"

signal bake_finished
## The startup bake/cache-load is complete; the loading gate releases.
signal initial_navigation_ready

enum Mode { INACTIVE, DORMANT, TILED, FULL_SCENE }
enum TileState { QUEUED, BAKING, BAKED }

# Main-thread-owned state. Dirtiness advances even while a worker is baking;
# only a result for the latest requested revision may replace the live mesh.
class Tile:
	extends RefCounted
	var state: int = TileState.QUEUED
	var requested_revision := 1
	var baking_revision := 0
	var installed_revision := 0
	var region: NavigationRegion3D
	var debug_mesh: MeshInstance3D
	var debug_frame: MeshInstance3D


class BakeTask:
	extends RefCounted
	var task_id := -1
	var coord := Vector2i.ZERO
	var generation := 0
	# Tile request revision for tiled work; source revision for full-scene.
	var revision := 0
	var elapsed := 0.0
	var tiled := true
	var worker_joined := false

	# Worker callables belong to this RefCounted task, never the controller:
	# Godot locks an Object while calling it and rejects free() before the
	# controller's _exit_tree can join if its own method is still executing.
	func bake_tile(template: NavigationMesh, snapshot: WorldNavigationSettings, terrains: Array, geometry: NavigationMeshSourceGeometryData3D, completion: Callable) -> void:
		var nav_mesh: NavigationMesh = PIPELINE.bake_tile(template, coord, snapshot, terrains, geometry)
		completion.call_deferred(self, nav_mesh)

	func bake_full_scene(template: NavigationMesh, geometry: NavigationMeshSourceGeometryData3D, postprocess: bool, completion: Callable) -> void:
		var nav_mesh: NavigationMesh = template.duplicate()
		if geometry.has_data():
			NavigationServer3D.bake_from_source_geometry_data(nav_mesh, geometry)
			if postprocess:
				PIPELINE.POSTPROCESS.apply(nav_mesh)
		completion.call_deferred(self, nav_mesh)


@export var settings: WorldNavigationSettings

var root_scene: Node
var last_bake_seconds := 0.0

var _mode: int = Mode.INACTIVE
var _shutting_down := false
var _template: NavigationMesh
var _scene_geometry: NavigationMeshSourceGeometryData3D
var _terrains: Array[Node] = []
var _geometry_dirty := true
var _source_revision := 1

# Tile bookkeeping. Key: Vector2i grid coordinate.
var _tiles: Dictionary[Vector2i, Tile] = {}
var _inflight: Dictionary[int, BakeTask] = {}
var _settings_generation := 0
var _initial_ready := false
# Nav-relevant geometry changes seen before tiles are seeded (scene-load
# runtime mutation, e.g. furniture freeing imported collision hulls).
var _pending_dirty_bounds: Array[AABB] = []
var _pending_added_nodes: Dictionary[int, WeakRef] = {}

# Debug visualization.
var _debug_root: Node3D
var _navmesh_debug_enabled := false
var _tile_debug_enabled := false

# FULL_SCENE mode state.
var _full_scene_region: NavigationRegion3D
var _full_scene_baking := false
var _has_navmesh := false
# True once the first whole-scene bake finished, even with zero polygons: a
# scene with no bakeable collision must still release the startup gate, or
# the loading overlay pauses the tree forever (nothing will ever retry).
var _full_scene_bake_completed := false


func initialize(context: BootstrapContext) -> void:
	root_scene = context.root_scene
	if not initial_navigation_ready.is_connected(_report_agent_radius_violations):
		initial_navigation_ready.connect(_report_agent_radius_violations, CONNECT_ONE_SHOT)
	if is_inside_tree():
		_schedule_activation()


## INVARIANT tripwire: bake agent_radius must be >= every routed character's
## capsule radius, or the navmesh promises paths bodies cannot fit.
func _report_agent_radius_violations() -> void:
	if settings == null or get_tree() == null:
		return
	for actor in get_tree().get_nodes_in_group("world_actor"):
		var shape := (actor as Node).get_node_or_null("CollisionShape3D") as CollisionShape3D
		var capsule := shape.shape as CapsuleShape3D if shape != null else null
		if capsule != null and capsule.radius > settings.agent_radius + 0.001:
			push_error("WorldNavigationController: actor '%s' capsule radius %.2f exceeds nav agent_radius %.2f — characters will wedge at pinch points. Raise agent_radius or shrink the capsule." % [actor.name, capsule.radius, settings.agent_radius])


func _ready() -> void:
	add_to_group("world_navigation_controller")
	# Keep baking while the tree is paused: the loading gate pauses the game
	# until the startup bake lands, which would deadlock a pausable node.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if root_scene != null:
		_schedule_activation()


func _schedule_activation() -> void:
	if _shutting_down or _mode != Mode.INACTIVE:
		return
	# Defer one frame so scene _ready content (ZoneLoader towns, settlement
	# buildings) exists before the mode decision and first parse.
	_activate.call_deferred()


func _activate() -> void:
	if _mode != Mode.INACTIVE or not _can_bake():
		return
	if settings == null:
		settings = load(DEFAULT_SETTINGS_PATH)
	if _find_authored_region(_nav_root()) != null:
		_mode = Mode.DORMANT
		set_process(false)
		print("WorldNavigationController: authored NavigationRegion3D found; staying dormant.")
		return
	_sync_map_cell_size()
	get_tree().node_added.connect(_on_scene_node_added)
	get_tree().node_removed.connect(_on_scene_node_removed)
	_scan_terrains()
	_mode = Mode.TILED if not _terrains.is_empty() else Mode.FULL_SCENE
	_template = PIPELINE.build_template(settings, _mode == Mode.TILED)
	if _mode == Mode.FULL_SCENE:
		_full_scene_region = NavigationRegion3D.new()
		_full_scene_region.name = "WorldNavigationRegion"
		_full_scene_region.use_edge_connections = false
		add_child(_full_scene_region)
	else:
		_seed_world_tiles()
		_load_world_cache()
		_dirty_bounds(_pending_dirty_bounds)
		if pending_tile_count() == 0 and not _initial_ready:
			_initial_ready = true
			initial_navigation_ready.emit()
	_pending_dirty_bounds.clear()
	set_process(true)


func _exit_tree() -> void:
	_shutting_down = true
	set_process(false)
	var tree := get_tree()
	if tree.node_added.is_connected(_on_scene_node_added):
		tree.node_added.disconnect(_on_scene_node_added)
	if tree.node_removed.is_connected(_on_scene_node_removed):
		tree.node_removed.disconnect(_on_scene_node_removed)
	# The worker callable uses this controller to enqueue its result. Keep
	# the controller (and terrain readers) alive until every worker returns.
	_wait_for_inflight_bakes()
	_inflight.clear()
	_full_scene_baking = false
	_pending_added_nodes.clear()
	_pending_dirty_bounds.clear()


func _can_bake() -> bool:
	return (
		not _shutting_down and not is_queued_for_deletion() and is_inside_tree()
		and is_instance_valid(root_scene) and root_scene.is_inside_tree()
		and not root_scene.is_queued_for_deletion()
	)


## --- Public API -------------------------------------------------------------


func notify_world_geometry_changed() -> void:
	if _shutting_down or _mode == Mode.DORMANT:
		return
	_geometry_dirty = true
	_source_revision += 1
	for coord in _tiles:
		_mark_tile_dirty(coord)


## Explicit local mutation boundary for moves, resizes and collision edits.
## Supply bounds BEFORE and AFTER the edit, in world space. For add/remove,
## pass the same occupied bounds twice. No editor/property polling is done.
func notify_geometry_changed(old_world_bounds: AABB, new_world_bounds: AABB) -> void:
	if _shutting_down or _mode == Mode.DORMANT:
		return
	_geometry_dirty = true
	_source_revision += 1
	if _mode == Mode.FULL_SCENE:
		return
	if _mode == Mode.INACTIVE:
		_pending_dirty_bounds.append(old_world_bounds)
		_pending_dirty_bounds.append(new_world_bounds)
		return
	_dirty_bounds([old_world_bounds, new_world_bounds])


## Position-only compatibility keeps the old conservative neighborhood by
## treating the containing tile as the unknown footprint. Extent/move-aware
## callers should use notify_geometry_changed for smaller, accurate patches.
func notify_content_changed_at(global_position: Vector3) -> void:
	var effective_settings: WorldNavigationSettings = settings if settings != null else load(DEFAULT_SETTINGS_PATH)
	var size := PIPELINE.clamped_tile_size(effective_settings)
	var coord := PIPELINE.tile_coord(global_position, size)
	var bounds := AABB(Vector3(coord.x * size, -effective_settings.tile_height * 0.5, coord.y * size), Vector3(size, effective_settings.tile_height, size))
	notify_geometry_changed(bounds, bounds)


func is_baking() -> bool:
	return not _inflight.is_empty() or _full_scene_baking


## No bakes running and nothing waiting to bake.
func is_idle() -> bool:
	if is_baking():
		return false
	if not _pending_added_nodes.is_empty() or not _pending_dirty_bounds.is_empty():
		return false
	if (_mode == Mode.TILED or _mode == Mode.FULL_SCENE) and _geometry_dirty:
		return false
	if _mode == Mode.TILED:
		for coord in _tiles:
			if _tiles[coord].state != TileState.BAKED:
				return false
	return true


func is_initial_navigation_pending() -> bool:
	if _mode == Mode.FULL_SCENE:
		return not _has_navmesh and not _full_scene_bake_completed
	return _mode == Mode.TILED and not _initial_ready


## Determinate loading progress for the startup gate overlay.
func initial_tiles_done() -> int:
	return initial_tiles_total() - pending_tile_count()


func initial_tiles_total() -> int:
	return _tiles.size()


## >0 only during the startup bake; after that the game never gates.
func gate_tiles_pending() -> int:
	if _mode == Mode.FULL_SCENE:
		return 0 if (_has_navmesh or _full_scene_bake_completed) else 1
	if _mode != Mode.TILED or _initial_ready:
		return 0
	return pending_tile_count()


func baked_tile_count() -> int:
	var count := 0
	for coord in _tiles:
		if _tiles[coord].state == TileState.BAKED:
			count += 1
	return count


func pending_tile_count() -> int:
	return _tiles.size() - baked_tile_count()


func bake_elapsed_seconds() -> float:
	var oldest := 0.0
	for task_id in _inflight:
		oldest = maxf(oldest, _inflight[task_id].elapsed)
	return oldest


## Saves every baked tile plus the manifest into the world's navcache.
## Dev utility (used by tools/bake_world_navcache.gd); the editor plugin
## bakes the edited scene directly through the pipeline instead.
func save_world_cache() -> int:
	if _mode != Mode.TILED:
		return 0
	# Always save to the PLAYED scene's own directory; _cache_dir() is the
	# read path and may resolve to a zone's cache via the runtime fallback,
	# which a world bake must never overwrite.
	var cache_dir := ""
	var current := get_tree().current_scene
	if current != null and not current.scene_file_path.is_empty():
		cache_dir = PIPELINE.cache_dir_for_scene(current.scene_file_path)
	elif root_scene != null and not root_scene.scene_file_path.is_empty():
		cache_dir = PIPELINE.cache_dir_for_scene(root_scene.scene_file_path)
	if cache_dir.is_empty():
		return 0
	var saved := 0
	for coord in _tiles:
		var tile: Tile = _tiles[coord]
		if tile.state != TileState.BAKED:
			continue
		var region := tile.region
		if region != null and is_instance_valid(region) and region.navigation_mesh != null:
			if PIPELINE.save_tile(cache_dir, coord, region.navigation_mesh):
				saved += 1
	PIPELINE.save_manifest(cache_dir, settings, saved)
	return saved


## Rebuilds the bake template from `settings` and rebakes the world.
## Call after mutating settings at runtime (Nav Debug live tuning).
func apply_settings() -> void:
	if not _can_bake() or (_mode != Mode.TILED and _mode != Mode.FULL_SCENE):
		return
	_settings_generation += 1
	_template = PIPELINE.build_template(settings, _mode == Mode.TILED)
	_sync_map_cell_size()
	_geometry_dirty = true
	if _mode == Mode.TILED:
		for coord in _tiles.keys():
			_free_tile(coord)
		_tiles.clear()
		_seed_world_tiles()
	else:
		_has_navmesh = false


## Draws the baked navmesh as translucent overlay meshes. Custom-drawn:
## reliable in any build, unlike the NavigationServer debug flag.
func set_debug_visualization(enabled: bool) -> void:
	_navmesh_debug_enabled = enabled
	_rebuild_all_debug()


func is_debug_visualization_enabled() -> bool:
	return _navmesh_debug_enabled


## Draws tile boundary frames colored by state (gold baked, red pending).
func set_tile_debug(enabled: bool) -> void:
	_tile_debug_enabled = enabled
	_rebuild_all_debug()


func is_tile_debug_enabled() -> bool:
	return _tile_debug_enabled


## --- Scheduling -------------------------------------------------------------


func _process(delta: float) -> void:
	if not _can_bake() or (_mode != Mode.TILED and _mode != Mode.FULL_SCENE):
		return
	_flush_pending_node_changes()
	for task_id in _inflight:
		_inflight[task_id].elapsed += delta
	if _mode == Mode.FULL_SCENE:
		if _geometry_dirty and not _full_scene_baking:
			_start_full_scene_bake()
		return
	# Cached/empty tiles can leave only a source change to consume. Refresh
	# it once even when there is no tile work; is_idle includes this work.
	if _geometry_dirty:
		_parse_world_geometry()
		if _geometry_dirty:
			return
	while _inflight.size() < settings.max_concurrent_bakes:
		var next := _pick_next_tile()
		if next == Vector2i(2147483647, 2147483647):
			break
		_start_tile_bake(next)


func _seed_world_tiles() -> void:
	for coord in PIPELINE.enumerate_world_tiles(_terrains, settings):
		_ensure_tile(coord)
	if _tiles.is_empty():
		_initial_ready = true
		initial_navigation_ready.emit()


## Loads prebaked tiles from the world's navcache, then re-dirties tiles
## touched by runtime-spawned content (the cache only knows editor-authored
## geometry).
func _load_world_cache() -> void:
	var cache_dir := _cache_dir()
	if cache_dir.is_empty() or not PIPELINE.manifest_matches(cache_dir, settings):
		return
	var loaded := 0
	for coord in _tiles:
		var nav_mesh: NavigationMesh = PIPELINE.load_tile(cache_dir, coord)
		if nav_mesh == null:
			continue
		_assign_tile_mesh(coord, nav_mesh)
		_tiles[coord].state = TileState.BAKED
		_tiles[coord].installed_revision = _tiles[coord].requested_revision
		loaded += 1
	if loaded == 0:
		return
	print("WorldNavigationController: loaded %d cached navmesh tiles from %s" % [loaded, cache_dir])
	_dirty_runtime_spawned_tiles()


func _dirty_runtime_spawned_tiles() -> void:
	var bodies: Array[Node3D] = []
	_collect_runtime_static_bodies(_nav_root(), false, bodies)
	for body in bodies:
		_dirty_tiles_for_node(body)


## Runtime-spawned = any branch whose node has no owner (code-added scenes,
## e.g. ZoneLoader towns). Editor-authored nodes carry owner chains.
func _collect_runtime_static_bodies(node: Node, runtime_branch: bool, result: Array[Node3D]) -> void:
	var branch := runtime_branch or (node != _nav_root() and node != root_scene and node.owner == null)
	if branch and node is StaticBody3D:
		result.append(node as Node3D)
	for child in node.get_children():
		_collect_runtime_static_bodies(child, branch, result)


func _pick_next_tile() -> Vector2i:
	var sentinel := Vector2i(2147483647, 2147483647)
	var best := sentinel
	var best_distance := INF
	var anchor := _camera_anchor()
	var anchor_flat := Vector3(anchor.x, 0.0, anchor.z) if anchor != Vector3.INF else Vector3.ZERO
	for coord in _tiles:
		if _tiles[coord].state != TileState.QUEUED or _tile_has_worker(coord):
			continue
		# Nearest-to-camera first so the visible world fills in early.
		var distance: float = _tile_center(coord).distance_to(anchor_flat)
		if distance < best_distance:
			best_distance = distance
			best = coord
	return best


## --- Tile lifecycle ---------------------------------------------------------


func _ensure_tile(coord: Vector2i) -> void:
	if _tiles.has(coord):
		return
	_tiles[coord] = Tile.new()


func _mark_tile_dirty(coord: Vector2i) -> void:
	if not _tiles.has(coord):
		return
	var tile: Tile = _tiles[coord]
	tile.requested_revision += 1
	if tile.state != TileState.BAKING:
		tile.state = TileState.QUEUED
	_refresh_tile_debug(coord)


func _free_tile(coord: Vector2i) -> void:
	var tile: Tile = _tiles[coord]
	for node in [tile.region, tile.debug_mesh, tile.debug_frame]:
		if node != null and is_instance_valid(node):
			node.queue_free()


func _start_tile_bake(coord: Vector2i) -> void:
	if not _can_bake() or _mode != Mode.TILED or not _tiles.has(coord) or _tiles[coord].state != TileState.QUEUED or _tile_has_worker(coord):
		return
	if _geometry_dirty and not _parse_world_geometry():
		return
	var tile: Tile = _tiles[coord]
	tile.state = TileState.BAKING
	tile.baking_revision = tile.requested_revision
	var task := BakeTask.new()
	task.coord = coord
	task.generation = _settings_generation
	task.revision = tile.baking_revision
	# Duplicate parsed geometry on the main thread; worker tasks must not
	# share mutable geometry/settings or read the controller's live template.
	var geometry := _copy_scene_geometry()
	task.task_id = WorkerThreadPool.add_task(
		task.bake_tile.bind(_template, settings.duplicate(), _terrains.duplicate(), geometry, _finish_tile_bake),
		false, "WorldNavigationTile")
	_inflight[task.task_id] = task


func _tile_has_worker(coord: Vector2i) -> bool:
	for task_id in _inflight:
		var task := _inflight[task_id]
		if task.tiled and task.coord == coord:
			return true
	return false


func _complete_bake_task(task: BakeTask) -> bool:
	if _inflight.get(task.task_id) != task:
		return false
	# A deferred result can arrive just before the worker returns. Join the
	# exact task (also releases WorkerThreadPool bookkeeping), not a coord.
	_join_bake_task(task)
	_inflight.erase(task.task_id)
	last_bake_seconds = task.elapsed
	return true


func _finish_tile_bake(task: BakeTask, nav_mesh: NavigationMesh) -> void:
	if not _complete_bake_task(task):
		return
	if not _can_bake():
		return
	_flush_pending_node_changes()
	if task.generation != _settings_generation or not _tiles.has(task.coord):
		return
	var coord := task.coord
	if settings.log_timing:
		print("WorldNavigationController: tile %s baked in %.2fs (%d polys)" % [coord, last_bake_seconds, nav_mesh.get_polygon_count()])
	var tile: Tile = _tiles[coord]
	if task.revision == tile.requested_revision:
		tile.state = TileState.BAKED
		tile.installed_revision = task.revision
		_assign_tile_mesh(coord, nav_mesh if nav_mesh.get_polygon_count() > 0 else null)
	else:
		# Keep the previous mesh until a current result is available. Never
		# briefly install geometry we already know has been superseded.
		tile.state = TileState.QUEUED
		_refresh_tile_debug(coord)
	if not _initial_ready and pending_tile_count() == 0:
		_initial_ready = true
		initial_navigation_ready.emit()
	bake_finished.emit()


func _assign_tile_mesh(coord: Vector2i, nav_mesh: NavigationMesh) -> void:
	var tile: Tile = _tiles[coord]
	if nav_mesh != null:
		var region := tile.region
		if region == null or not is_instance_valid(region):
			region = NavigationRegion3D.new()
			region.name = "Tile_%d_%d" % [coord.x, coord.y]
			# Cross-tile pathing requires edge connections; borders are
			# cell-aligned so neighbors match exactly.
			region.use_edge_connections = true
			add_child(region)
			tile.region = region
		region.navigation_mesh = nav_mesh
	elif is_instance_valid(tile.region):
		tile.region.navigation_mesh = null
	_refresh_tile_debug(coord)


## Candidate navcache locations, most specific session first: the actually
## played scene (the WORLD when playing a world; editor bakes from the world
## scene write there), then the bootstrap root (the ZONE when it is played or
## instanced directly). The zone fallback only applies while the zone sits at
## the world origin: a standalone zone bake is in zone-local coordinates and
## would be silently misplaced for an offset zone.
func _cache_dir() -> String:
	var candidates: Array[String] = []
	var current := get_tree().current_scene
	if current != null and not current.scene_file_path.is_empty():
		candidates.append(PIPELINE.cache_dir_for_scene(current.scene_file_path))
	if root_scene != null and not root_scene.scene_file_path.is_empty():
		var zone_at_origin := not (root_scene is Node3D) or (root_scene as Node3D).global_transform.is_equal_approx(Transform3D.IDENTITY)
		if zone_at_origin:
			candidates.append(PIPELINE.cache_dir_for_scene(root_scene.scene_file_path))
	for candidate in candidates:
		if PIPELINE.manifest_matches(candidate, settings):
			return candidate
	return candidates[0] if not candidates.is_empty() else ""


## --- FULL_SCENE mode (test levels without terrain) ---------------------------


func _copy_scene_geometry() -> NavigationMeshSourceGeometryData3D:
	# Generic Resource.duplicate() can reject valid parsed indexed geometry
	# through set_indices() on some Godot builds. Native merge preserves the
	# parsed data in a separate resource for each worker task.
	var geometry := NavigationMeshSourceGeometryData3D.new()
	geometry.merge(_scene_geometry)
	return geometry


func _start_full_scene_bake() -> void:
	if not _can_bake() or _mode != Mode.FULL_SCENE or _full_scene_baking:
		return
	if not _parse_world_geometry():
		return
	_full_scene_baking = true
	var task := BakeTask.new()
	task.tiled = false
	task.generation = _settings_generation
	task.revision = _source_revision
	task.task_id = WorkerThreadPool.add_task(
		task.bake_full_scene.bind(_template, _copy_scene_geometry(), settings.postprocess_enabled, _finish_full_scene_bake),
		false, "WorldNavigationFullScene")
	_inflight[task.task_id] = task


func _finish_full_scene_bake(task: BakeTask, nav_mesh: NavigationMesh) -> void:
	if not _complete_bake_task(task):
		return
	_full_scene_baking = false
	if not _can_bake():
		return
	_flush_pending_node_changes()
	if task.generation != _settings_generation or task.revision != _source_revision:
		_geometry_dirty = true
		return
	var first := not _full_scene_bake_completed
	_full_scene_bake_completed = true
	_has_navmesh = nav_mesh.get_polygon_count() > 0
	if is_instance_valid(_full_scene_region):
		_full_scene_region.navigation_mesh = nav_mesh if _has_navmesh else null
	if first and not _has_navmesh:
		print("WorldNavigationController: no bakeable collision; releasing the startup gate without navigation.")
	if first:
		initial_navigation_ready.emit()
	bake_finished.emit()


## --- Geometry sources -------------------------------------------------------


## Navigation geometry is scoped to the PLAYED scene root (the world when a
## world is played), NOT the bootstrap's parent (the zone): world-level
## content — e.g. a building placed as a sibling of a zone — must bake and
## patch exactly like zone content. Hierarchy is irrelevant to nav.
func _nav_root() -> Node:
	if not is_instance_valid(root_scene):
		return null
	# Teardown-safe: node-removed signals keep firing while this controller
	# itself is leaving the tree, when get_tree() is already null.
	if not is_inside_tree():
		return root_scene
	var current := get_tree().current_scene
	if current != null and (current == root_scene or current.is_ancestor_of(root_scene)):
		return current
	return root_scene


func _parse_world_geometry() -> bool:
	# Main-thread only: parse_source_geometry_data walks the scene tree, so
	# the nav root must actually be IN the tree (scene switches can tick a
	# bake while the world is detaching). Stays dirty and retries otherwise.
	var nav_root := _nav_root()
	if not _can_bake() or not is_instance_valid(nav_root) or not nav_root.is_inside_tree():
		return false
	_scene_geometry = NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(_template, _scene_geometry, nav_root)
	_scan_terrains()
	_geometry_dirty = false
	return true


func _on_scene_node_added(node: Node) -> void:
	if not _is_nav_relevant(node):
		return
	# Spawners add_child() FIRST and position the node AFTERWARD, so the
	# bounds are resolved at end of frame. Never retain a disposable Node
	# in a queued callback; a spawn can be removed again in the same frame.
	_pending_added_nodes[node.get_instance_id()] = weakref(node)
	if _pending_added_nodes.size() == 1:
		_flush_pending_node_changes.call_deferred()


func _flush_pending_node_changes() -> void:
	if _shutting_down or _pending_added_nodes.is_empty():
		return
	var pending := _pending_added_nodes.values()
	_pending_added_nodes.clear()
	for reference: WeakRef in pending:
		var node = reference.get_ref()
		if is_instance_valid(node) and not node.is_queued_for_deletion() and _is_nav_relevant(node):
			_dirty_tiles_for_node(node)


func _on_scene_node_removed(node: Node) -> void:
	if not _is_nav_relevant(node):
		return
	_pending_added_nodes.erase(node.get_instance_id())
	# Removal must read bounds NOW, while the node still has its transform.
	_dirty_tiles_for_node(node)


func _is_nav_relevant(node: Node) -> bool:
	# Scene-teardown removals are not nav events; the whole map is going away.
	if not _can_bake() or not is_instance_valid(node):
		return false
	if _mode != Mode.TILED and _mode != Mode.FULL_SCENE:
		return false
	if node == self or is_ancestor_of(node):
		return false
	if node.is_in_group("navigation_bake_excluded"):
		return false
	if not (node is StaticBody3D or node.is_class("Terrain3D")):
		return false
	var nav_root := _nav_root()
	return is_instance_valid(nav_root) and nav_root.is_ancestor_of(node)


func _dirty_tiles_for_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	# Terrain edits have no finite StaticBody footprint here. The existing
	# explicit world invalidation remains the conservative fallback.
	if not (node is StaticBody3D):
		notify_world_geometry_changed()
		return
	var bounds := _static_body_world_bounds(node as StaticBody3D)
	notify_geometry_changed(bounds, bounds)


func _static_body_world_bounds(body: StaticBody3D) -> AABB:
	var bounds := AABB(body.global_position, Vector3.ZERO)
	var has_shape := false
	# Registered shape owners include CollisionPolygon3D and transformed
	# CollisionShape3D children, not merely the body's origin or visual mesh.
	for owner_id in body.get_shape_owners():
		var transform := body.global_transform * body.shape_owner_get_transform(owner_id)
		for index in range(body.shape_owner_get_shape_count(owner_id)):
			var shape := body.shape_owner_get_shape(owner_id, index)
			var shape_bounds: AABB = transform * shape.get_debug_mesh().get_aabb()
			bounds = bounds.merge(shape_bounds) if has_shape else shape_bounds
			has_shape = true
	return bounds


func _dirty_bounds(bounds: Array[AABB]) -> void:
	var affected := {}
	for world_bounds in bounds:
		for coord in PIPELINE.affected_tile_coords(world_bounds, settings):
			affected[coord] = true
	for coord in affected:
		_mark_tile_dirty(coord)


func _scan_terrains() -> void:
	_terrains.clear()
	if not is_instance_valid(root_scene):
		return
	_collect_terrains(_nav_root(), _terrains)
	for terrain in _terrains:
		# Tile bake tasks read terrain data on worker threads; a terrain being
		# freed mid-bake (quit, zone unload) is a use-after-free crash. Block
		# on in-flight tasks while the terrain is still valid.
		if not terrain.tree_exiting.is_connected(_wait_for_inflight_bakes):
			terrain.tree_exiting.connect(_wait_for_inflight_bakes)


func _wait_for_inflight_bakes() -> void:
	for task: BakeTask in _inflight.values():
		_join_bake_task(task)


func _join_bake_task(task: BakeTask) -> void:
	if not task.worker_joined:
		WorkerThreadPool.wait_for_task_completion(task.task_id)
		task.worker_joined = true


func _collect_terrains(node: Node, result: Array[Node]) -> void:
	if node.is_class("Terrain3D"):
		result.append(node)
	for child in node.get_children():
		_collect_terrains(child, result)


func _find_authored_region(node: Node) -> NavigationRegion3D:
	if node is NavigationRegion3D:
		return node
	for child in node.get_children():
		var found := _find_authored_region(child)
		if found != null:
			return found
	return null


## --- Debug drawing ----------------------------------------------------------


func _rebuild_all_debug() -> void:
	if _debug_root == null or not is_instance_valid(_debug_root):
		_debug_root = Node3D.new()
		_debug_root.name = "NavDebugDraw"
		add_child(_debug_root)
	for coord in _tiles:
		_refresh_tile_debug(coord)


func _refresh_tile_debug(coord: Vector2i) -> void:
	if _debug_root == null or not is_instance_valid(_debug_root):
		return
	var tile: Tile = _tiles[coord]
	for old in [tile.debug_mesh, tile.debug_frame]:
		if old != null and is_instance_valid(old):
			old.queue_free()
	tile.debug_mesh = null
	tile.debug_frame = null
	if _navmesh_debug_enabled:
		var region := tile.region
		if region != null and is_instance_valid(region) and region.navigation_mesh != null:
			tile.debug_mesh = _make_navmesh_debug_node(region.navigation_mesh)
			_debug_root.add_child(tile.debug_mesh)
	if _tile_debug_enabled:
		tile.debug_frame = _make_tile_frame_node(coord, tile.state == TileState.BAKED)
		_debug_root.add_child(tile.debug_frame)


func _make_navmesh_debug_node(nav_mesh: NavigationMesh) -> MeshInstance3D:
	var mesh: ArrayMesh = PIPELINE.build_navmesh_debug_mesh(nav_mesh)
	var instance := MeshInstance3D.new()
	if mesh != null:
		instance.mesh = mesh
		instance.material_override = PIPELINE.debug_material(Color(0.35, 0.75, 0.95, 0.35))
	return instance


func _make_tile_frame_node(coord: Vector2i, baked: bool) -> MeshInstance3D:
	var tile := PIPELINE.clamped_tile_size(settings)
	var instance := MeshInstance3D.new()
	instance.mesh = PIPELINE.build_tile_frame_mesh(coord, tile)
	var color := Color(0.71, 0.58, 0.32, 0.9) if baked else Color(0.85, 0.25, 0.2, 0.9)
	instance.material_override = PIPELINE.debug_material(color)
	return instance


## --- Grid math ----------------------------------------------------------------


func _camera_anchor() -> Vector3:
	var camera: Camera3D
	if is_instance_valid(root_scene):
		camera = root_scene.get_node_or_null("CameraRig/CameraPivot/Camera3D") as Camera3D
	if camera == null:
		var viewport := get_viewport()
		if viewport != null:
			camera = viewport.get_camera_3d()
	if camera != null:
		return camera.global_position
	return Vector3.INF


func _tile_center(coord: Vector2i) -> Vector3:
	var tile := PIPELINE.clamped_tile_size(settings)
	return Vector3((coord.x + 0.5) * tile, 0.0, (coord.y + 0.5) * tile)


func _sync_map_cell_size() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var map: RID = viewport.find_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, settings.cell_size)
	NavigationServer3D.map_set_cell_height(map, settings.cell_height)
