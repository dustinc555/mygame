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
## the tiles the object touches, instantly and in the background.
##
## Tuning lives in a WorldNavigationSettings resource; the Nav Debug window
## tunes the live game and draws the navmesh and tile grid.
##
## Scenes must NOT ship their own NavigationRegion3D or saved NavigationMesh
## resources; collision is the source of truth.
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

@export var settings: WorldNavigationSettings

var root_scene: Node
var last_bake_seconds := 0.0

var _mode: int = Mode.INACTIVE
var _template: NavigationMesh
var _scene_geometry: NavigationMeshSourceGeometryData3D
var _terrains: Array[Node] = []
var _geometry_dirty := true

# Tile bookkeeping. Key: Vector2i grid coordinate.
var _tiles := {}
var _inflight := {}
var _initial_ready := false
# Nav-relevant geometry changes seen before tiles are seeded (scene-load
# runtime mutation, e.g. furniture freeing imported collision hulls).
var _pending_dirty_positions: Array[Vector3] = []

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
	if _mode != Mode.INACTIVE:
		return
	# Defer one frame so scene _ready content (ZoneLoader towns, settlement
	# buildings) exists before the mode decision and first parse.
	_activate.call_deferred()


func _activate() -> void:
	if _mode != Mode.INACTIVE or root_scene == null:
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
		for position in _pending_dirty_positions:
			_dirty_tiles_at(position)
		_pending_dirty_positions.clear()
		if pending_tile_count() == 0 and not _initial_ready:
			_initial_ready = true
			initial_navigation_ready.emit()
	set_process(true)


## --- Public API -------------------------------------------------------------


func notify_world_geometry_changed() -> void:
	_geometry_dirty = true
	for coord in _tiles:
		_mark_tile_dirty(coord)


## Content spawned or moved at a known position (e.g. town ground snap):
## re-dirties only the 3x3 tile neighborhood around it.
func notify_content_changed_at(global_position: Vector3) -> void:
	if _mode == Mode.FULL_SCENE:
		_geometry_dirty = true
		return
	var tile := PIPELINE.clamped_tile_size(settings)
	var center := PIPELINE.tile_coord(global_position, tile)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			_mark_tile_dirty(Vector2i(center.x + dx, center.y + dz))


func is_baking() -> bool:
	return not _inflight.is_empty() or _full_scene_baking


## No bakes running and nothing waiting to bake.
func is_idle() -> bool:
	if is_baking():
		return false
	if _mode == Mode.TILED:
		for coord in _tiles:
			if _tiles[coord]["state"] != TileState.BAKED:
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
		if _tiles[coord]["state"] == TileState.BAKED:
			count += 1
	return count


func pending_tile_count() -> int:
	return _tiles.size() - baked_tile_count()


func bake_elapsed_seconds() -> float:
	var oldest := 0.0
	for task_id in _inflight:
		oldest = maxf(oldest, _inflight[task_id]["elapsed"])
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
		var tile: Dictionary = _tiles[coord]
		if tile["state"] != TileState.BAKED:
			continue
		var region: NavigationRegion3D = tile["region"]
		if region != null and is_instance_valid(region) and region.navigation_mesh != null:
			if PIPELINE.save_tile(cache_dir, coord, region.navigation_mesh):
				saved += 1
	PIPELINE.save_manifest(cache_dir, settings, saved)
	return saved


## Rebuilds the bake template from `settings` and rebakes the world.
## Call after mutating settings at runtime (Nav Debug live tuning).
func apply_settings() -> void:
	if _mode != Mode.TILED and _mode != Mode.FULL_SCENE:
		return
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
	for task_id in _inflight:
		_inflight[task_id]["elapsed"] += delta
	if _mode == Mode.FULL_SCENE:
		if _geometry_dirty and not _full_scene_baking:
			_start_full_scene_bake()
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
		_tiles[coord]["state"] = TileState.BAKED
		loaded += 1
	if loaded == 0:
		return
	print("WorldNavigationController: loaded %d cached navmesh tiles from %s" % [loaded, cache_dir])
	_dirty_runtime_spawned_tiles()


func _dirty_runtime_spawned_tiles() -> void:
	var bodies: Array[Node3D] = []
	_collect_runtime_static_bodies(_nav_root(), false, bodies)
	var tile := PIPELINE.clamped_tile_size(settings)
	for body in bodies:
		var center := PIPELINE.tile_coord(body.global_position, tile)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				_mark_tile_dirty(Vector2i(center.x + dx, center.y + dz))


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
		if _tiles[coord]["state"] != TileState.QUEUED:
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
	_tiles[coord] = {
		"state": TileState.QUEUED,
		"region": null,
		"debug_mesh": null,
		"debug_frame": null,
	}


func _mark_tile_dirty(coord: Vector2i) -> void:
	if not _tiles.has(coord):
		return
	if _tiles[coord]["state"] == TileState.BAKED:
		_tiles[coord]["state"] = TileState.QUEUED
		_refresh_tile_debug(coord)


func _free_tile(coord: Vector2i) -> void:
	var tile: Dictionary = _tiles[coord]
	for key in ["region", "debug_mesh", "debug_frame"]:
		var node: Node = tile[key]
		if node != null and is_instance_valid(node):
			node.queue_free()


func _start_tile_bake(coord: Vector2i) -> void:
	if _geometry_dirty:
		_parse_world_geometry()
	_tiles[coord]["state"] = TileState.BAKING
	# Duplicate parsed geometry on the main thread; worker tasks must not
	# share one mutable resource.
	var geometry: NavigationMeshSourceGeometryData3D = _scene_geometry.duplicate()
	var task_id := WorkerThreadPool.add_task(
		_task_bake_tile.bind(coord, _terrains.duplicate(), geometry),
		false, "WorldNavigationTile")
	_inflight[task_id] = {"coord": coord, "elapsed": 0.0}


func _task_bake_tile(coord: Vector2i, terrains: Array, geometry: NavigationMeshSourceGeometryData3D) -> void:
	var nav_mesh: NavigationMesh = PIPELINE.bake_tile(_template, coord, settings, terrains, geometry)
	_finish_tile_bake.call_deferred(coord, nav_mesh)


func _finish_tile_bake(coord: Vector2i, nav_mesh: NavigationMesh) -> void:
	for task_id in _inflight.keys():
		if _inflight[task_id]["coord"] == coord:
			last_bake_seconds = _inflight[task_id]["elapsed"]
			_inflight.erase(task_id)
			break
	if settings.log_timing:
		print("WorldNavigationController: tile %s baked in %.2fs (%d polys)" % [coord, last_bake_seconds, nav_mesh.get_polygon_count()])
	if not _tiles.has(coord):
		bake_finished.emit()
		return
	var tile: Dictionary = _tiles[coord]
	# A re-dirty while baking keeps the tile QUEUED for another pass.
	if tile["state"] == TileState.BAKING:
		tile["state"] = TileState.BAKED
	_assign_tile_mesh(coord, nav_mesh if nav_mesh.get_polygon_count() > 0 else null)
	if not _initial_ready and pending_tile_count() == 0:
		_initial_ready = true
		initial_navigation_ready.emit()
	bake_finished.emit()


func _assign_tile_mesh(coord: Vector2i, nav_mesh: NavigationMesh) -> void:
	var tile: Dictionary = _tiles[coord]
	if nav_mesh != null:
		var region: NavigationRegion3D = tile["region"]
		if region == null or not is_instance_valid(region):
			region = NavigationRegion3D.new()
			region.name = "Tile_%d_%d" % [coord.x, coord.y]
			# Cross-tile pathing requires edge connections; borders are
			# cell-aligned so neighbors match exactly.
			region.use_edge_connections = true
			add_child(region)
			tile["region"] = region
		region.navigation_mesh = nav_mesh
	elif tile["region"] != null and is_instance_valid(tile["region"]):
		(tile["region"] as NavigationRegion3D).navigation_mesh = null
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


func _start_full_scene_bake() -> void:
	_parse_world_geometry()
	_full_scene_baking = true
	var task_id := WorkerThreadPool.add_task(
		_task_bake_full_scene.bind(_scene_geometry.duplicate(), settings.postprocess_enabled),
		false, "WorldNavigationFullScene")
	_inflight[task_id] = {"coord": Vector2i.ZERO, "elapsed": 0.0}


func _task_bake_full_scene(geometry: NavigationMeshSourceGeometryData3D, postprocess: bool) -> void:
	var nav_mesh: NavigationMesh = _template.duplicate()
	if geometry.has_data():
		NavigationServer3D.bake_from_source_geometry_data(nav_mesh, geometry)
		if postprocess:
			PIPELINE.POSTPROCESS.apply(nav_mesh)
	_finish_full_scene_bake.call_deferred(nav_mesh)


func _finish_full_scene_bake(nav_mesh: NavigationMesh) -> void:
	_inflight.clear()
	_full_scene_baking = false
	var first := not _full_scene_bake_completed
	_full_scene_bake_completed = true
	if nav_mesh.get_polygon_count() > 0 and is_instance_valid(_full_scene_region):
		_full_scene_region.navigation_mesh = nav_mesh
		_has_navmesh = true
	elif first:
		push_warning("WorldNavigationController: full-scene bake produced no navmesh (no bakeable collision in scene); releasing the startup gate without navigation.")
	if first:
		initial_navigation_ready.emit()
	bake_finished.emit()


## --- Geometry sources -------------------------------------------------------


## Navigation geometry is scoped to the PLAYED scene root (the world when a
## world is played), NOT the bootstrap's parent (the zone): world-level
## content — e.g. a building placed as a sibling of a zone — must bake and
## patch exactly like zone content. Hierarchy is irrelevant to nav.
func _nav_root() -> Node:
	# Teardown-safe: node-removed signals keep firing while this controller
	# itself is leaving the tree, when get_tree() is already null.
	if not is_inside_tree():
		return root_scene
	var current := get_tree().current_scene
	if current != null and (current == root_scene or current.is_ancestor_of(root_scene)):
		return current
	return root_scene


func _parse_world_geometry() -> void:
	# Main-thread only: parse_source_geometry_data walks the scene tree, so
	# the nav root must actually be IN the tree (scene switches can tick a
	# bake while the world is detaching). Stays dirty and retries otherwise.
	var nav_root := _nav_root()
	if nav_root == null or not nav_root.is_inside_tree():
		return
	_scene_geometry = NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(_template, _scene_geometry, nav_root)
	_scan_terrains()
	_geometry_dirty = false


func _on_scene_node_added(node: Node) -> void:
	if not _is_nav_relevant(node):
		return
	# Spawners add_child() FIRST and position the node AFTERWARD, so the
	# position at signal time is garbage (often the origin). Defer the tile
	# dirtying to end of frame, when the final transform is set.
	_dirty_tiles_for_node.call_deferred(node)


func _on_scene_node_removed(node: Node) -> void:
	if not _is_nav_relevant(node):
		return
	# Removal must read the position NOW, while the node still has one.
	_dirty_tiles_for_node(node)


func _is_nav_relevant(node: Node) -> bool:
	# Scene-teardown removals are not nav events; the whole map is going away.
	if not is_inside_tree():
		return false
	if _mode != Mode.TILED and _mode != Mode.FULL_SCENE:
		return false
	if node == self or is_ancestor_of(node):
		return false
	if node.is_in_group("navigation_bake_excluded"):
		return false
	if not (node is StaticBody3D or node.is_class("Terrain3D")):
		return false
	return root_scene != null and _nav_root().is_ancestor_of(node)


func _dirty_tiles_for_node(node: Node) -> void:
	_geometry_dirty = true
	if _mode == Mode.FULL_SCENE or not (node is Node3D):
		return
	if not is_instance_valid(node):
		# Freed before the deferred call: conservative full re-dirty is the
		# only safe answer for an unknown position.
		notify_world_geometry_changed()
		return
	var position := (node as Node3D).global_position
	# Geometry can change during scene load, before tiles are seeded (e.g.
	# furniture freeing its imported collision hulls in _ready). Losing that
	# dirt would leave stale cached tiles; apply it after activation instead.
	if _mode == Mode.INACTIVE or _tiles.is_empty():
		_pending_dirty_positions.append(position)
		return
	_dirty_tiles_at(position)


func _dirty_tiles_at(position: Vector3) -> void:
	var tile := PIPELINE.clamped_tile_size(settings)
	var center := PIPELINE.tile_coord(position, tile)
	# Instant patch: re-dirty only the tiles the object's volume touches.
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			_mark_tile_dirty(Vector2i(center.x + dx, center.y + dz))


func _scan_terrains() -> void:
	_terrains.clear()
	if root_scene == null:
		return
	_collect_terrains(_nav_root(), _terrains)
	for terrain in _terrains:
		# Tile bake tasks read terrain data on worker threads; a terrain being
		# freed mid-bake (quit, zone unload) is a use-after-free crash. Block
		# on in-flight tasks while the terrain is still valid.
		if not terrain.tree_exiting.is_connected(_wait_for_inflight_bakes):
			terrain.tree_exiting.connect(_wait_for_inflight_bakes)


func _wait_for_inflight_bakes() -> void:
	for task_id in _inflight.keys():
		WorkerThreadPool.wait_for_task_completion(task_id)
	_inflight.clear()


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
	var tile: Dictionary = _tiles[coord]
	for key in ["debug_mesh", "debug_frame"]:
		var old: Node = tile[key]
		if old != null and is_instance_valid(old):
			old.queue_free()
		tile[key] = null
	if _navmesh_debug_enabled:
		var region: NavigationRegion3D = tile["region"]
		if region != null and is_instance_valid(region) and region.navigation_mesh != null:
			tile["debug_mesh"] = _make_navmesh_debug_node(region.navigation_mesh)
			_debug_root.add_child(tile["debug_mesh"])
	if _tile_debug_enabled:
		tile["debug_frame"] = _make_tile_frame_node(coord, tile["state"] == TileState.BAKED)
		_debug_root.add_child(tile["debug_frame"])


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
	var camera: Camera3D = root_scene.get_node_or_null("CameraRig/CameraPivot/Camera3D") as Camera3D
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
