extends SceneTree

## Focused production-controller lifecycle regression; cache writes only in user://.
## godot --headless --path . --script res://tests/validation/validate_navigation_lifecycle.gd
## Runtime load avoids the GECS preload chain during SceneTree compilation.
const CONTROLLER_PATH := "res://features/core/navigation/world_navigation_controller.gd"
const PIPELINE_PATH := "res://features/core/navigation/world_nav_bake_pipeline.gd"
const SETTINGS_PATH := "res://features/core/navigation/resources/world_navigation_settings.tres"
const COORD := Vector2i.ZERO
const NO_TILE := Vector2i(2147483647, 2147483647)

var _controller_script: Script
var _pipeline: Script
var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_controller_script = load(CONTROLLER_PATH)
	_pipeline = load(PIPELINE_PATH)
	await _test_large_static_world()
	await _test_dirty_during_bake()
	await _test_settings_generation()
	await _test_local_invalidation()
	await _test_runtime_bounds()
	await _test_full_scene_lifecycle()
	await _test_pending_source_idle()
	await _test_teardown()
	await _test_joined_callback()
	_test_bake_border_contacts()
	await _test_empty_tiled_source()
	await _test_disposable_callbacks()
	await _test_compatibility_coverage()
	await _test_local_change_isolation()
	print("NAV_LIFECYCLE_RESULT checks=%d failures=%d" % [_checks, _failures.size()])
	for failure in _failures:
		print("NAV_LIFECYCLE_FAIL ", failure)
	quit(0 if _failures.is_empty() else 1)


func _test_large_static_world() -> void:
	# The demo's 1100m static floor exceeded Recast's whole-scene cell limit.
	# A narrow strip crosses that same limit without a whole-world workload.
	var world := Node3D.new()
	root.add_child(world)
	# Give this isolated fixture a cache namespace, never a production path.
	world.scene_file_path = "user://navigation-lifecycle/large-static.tscn"
	var previous_scene := current_scene
	current_scene = world
	var floor_body := _floor(world, Vector3(170.0, -0.5, 24.0))
	floor_body.owner = world
	floor_body.get_child(0).owner = world
	(floor_body.get_child(0).shape as BoxShape3D).size = Vector3(340.0, 1.0, 8.0)
	var controller: Node = _controller_script.new()
	controller.settings = load(SETTINGS_PATH).duplicate()
	world.add_child(controller)
	controller.root_scene = world
	controller._activate()
	controller.set_process(false)
	_expect(controller._mode == _controller_script.Mode.TILED, "oversized static floor uses bounded tiles, not unsafe whole-scene bake")
	if controller._mode != _controller_script.Mode.TILED:
		current_scene = previous_scene
		world.free()
		return
	controller.set_process(true)
	var deadline := Time.get_ticks_msec() + 15000
	while not controller.is_idle() and Time.get_ticks_msec() < deadline:
		await create_timer(0.01).timeout
	_expect(controller.is_idle() and controller.baked_tile_count() > 1, "large static floor finishes tiled navigation")
	var map := world.get_world_3d().navigation_map
	for frame in range(120):
		await physics_frame
		var path := NavigationServer3D.map_get_path(map, Vector3(60, 0.1, 24), Vector3(70, 0.1, 24), true)
		if not path.is_empty() and path[-1].distance_to(Vector3(70, 0.1, 24)) < 0.3:
			break
	var connected := NavigationServer3D.map_get_path(map, Vector3(60, 0.1, 24), Vector3(70, 0.1, 24), true)
	_expect(not connected.is_empty() and connected[-1].distance_to(Vector3(70, 0.1, 24)) < 0.3, "static tiles connect across a real seam")
	var empty_tiles := 0
	for tile in controller._tiles.values():
		if not is_instance_valid(tile.region) or tile.region.navigation_mesh == null:
			empty_tiles += 1
	_expect(empty_tiles > 0, "cache fixture includes completed empty margin tiles")
	var saved: int = controller.save_world_cache()
	_expect(saved == controller.baked_tile_count(), "large static world saves all prebaked tiles")
	controller.free()
	await physics_frame
	controller = _controller_script.new()
	controller.settings = load(SETTINGS_PATH).duplicate()
	world.add_child(controller)
	controller.root_scene = world
	controller._activate()
	_expect(controller.pending_tile_count() == 0 and controller.baked_tile_count() == saved and controller._inflight.is_empty(), "static world reload consumes prebake without starting a whole-world bake")
	var restored_empty_tiles := 0
	for tile in controller._tiles.values():
		if not is_instance_valid(tile.region):
			restored_empty_tiles += 1
	_expect(restored_empty_tiles == empty_tiles, "cached empty tiles stay regionless, not missing or stale walkable meshes")
	var before := {}
	for coord in controller._tiles:
		before[coord] = controller._tiles[coord].requested_revision
	# The authored strip starts at X=0; tile (-1,0) is an empty margin.
	# Extend real solid geometry across that boundary using the same local
	# event route as construction, not a manually installed mesh.
	var margin_coord := Vector2i(-1, 0)
	_expect(_mesh(controller, margin_coord) == null, "west margin is initially empty")
	var extension := _floor(world, Vector3(0, -0.5, 24))
	extension.owner = world
	extension.get_child(0).owner = world
	var bounds: AABB = controller._static_body_world_bounds(extension)
	controller.notify_geometry_changed(bounds, bounds)
	var changed := 0
	for coord in before:
		if before[coord] != controller._tiles[coord].requested_revision:
			changed += 1
	_expect(changed > 0 and changed < saved, "cached static world mutations queue local tiles only")
	_expect(controller._tiles[margin_coord].requested_revision > before[margin_coord] and controller._tiles[Vector2i.ZERO].requested_revision > before[Vector2i.ZERO], "boundary patch includes both formerly empty and neighboring solid tiles")
	deadline = Time.get_ticks_msec() + 15000
	while not controller.is_idle() and Time.get_ticks_msec() < deadline:
		await create_timer(0.01).timeout
	_expect(controller.is_idle(), "cached static local patch finishes")
	var positive := _mesh(controller, margin_coord)
	_expect(positive != null and positive.get_polygon_count() > 0, "real boundary extension makes the formerly empty margin walkable")
	_expect(controller.save_world_cache() == saved, "save includes the newly positive margin without losing empty completions")
	var cache_dir: String = _pipeline.cache_dir_for_scene(world.scene_file_path)
	var cached_positive: NavigationMesh = _pipeline.load_tile(cache_dir, margin_coord)
	_expect(cached_positive != null and cached_positive.get_polygon_count() > 0, "positive margin cache exists before geometry removal")
	# Remove only the fixture extension. Its old positive cache must not
	# survive the real empty rebake; no production collider is changed.
	extension.free()
	controller.notify_geometry_changed(bounds, bounds)
	deadline = Time.get_ticks_msec() + 15000
	while not controller.is_idle() and Time.get_ticks_msec() < deadline:
		await create_timer(0.01).timeout
	_expect(controller.is_idle() and _mesh(controller, margin_coord) == null, "removing the extension completes a genuinely empty margin rebake")
	_expect(controller.save_world_cache() == saved, "empty rebake is saved, not omitted")
	var cached_empty: NavigationMesh = _pipeline.load_tile(cache_dir, margin_coord)
	_expect(cached_empty != null and cached_empty.get_polygon_count() == 0, "empty completion replaces obsolete positive polygons on disk")
	controller.free()
	await physics_frame
	controller = _controller_script.new()
	controller.settings = load(SETTINGS_PATH).duplicate()
	world.add_child(controller)
	controller.root_scene = world
	controller._activate()
	_expect(controller.pending_tile_count() == 0 and controller.baked_tile_count() == saved and controller._inflight.is_empty() and _mesh(controller, margin_coord) == null, "fresh reload after positive-to-empty change neither restores stale polygons nor queues missing margin bakes")
	current_scene = previous_scene
	await _dispose(controller)


func _fixture() -> Node:
	var world := Node3D.new()
	root.add_child(world)
	var controller: Node = _controller_script.new()
	controller.settings = load(SETTINGS_PATH).duplicate()
	world.add_child(controller)
	controller.set_process(false)
	controller.root_scene = world
	controller._mode = _controller_script.Mode.TILED
	controller._template = _pipeline.build_template(controller.settings, true)
	controller._sync_map_cell_size()
	controller._ensure_tile(COORD)
	return controller


func _floor(world: Node, position := Vector3(24.0, -0.5, 24.0)) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 1.0, 8.0)
	collision.shape = box
	body.add_child(collision)
	world.add_child(body)
	body.position = position
	return body


func _mesh(controller: Node, coord := COORD) -> NavigationMesh:
	var region: NavigationRegion3D = controller._tiles[coord].region
	return region.navigation_mesh if is_instance_valid(region) else null


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
	print("NAV_LIFECYCLE_CHECK %s %s" % ["PASS" if condition else "FAIL", label])


func _drain(controller: Node) -> void:
	var deadline := Time.get_ticks_msec() + 15000
	while controller.is_baking() and Time.get_ticks_msec() < deadline:
		await create_timer(0.01).timeout
	_expect(not controller.is_baking(), "worker callbacks drain within deadline")


func _dispose(controller: Node) -> void:
	await _drain(controller)
	controller.root_scene.free()
	await process_frame


func _await_initial_navigation(controller: Node) -> void:
	# These fixtures manually drive the controller to control worker races.
	# A completed bake is not a synchronized, queryable native navigation map.
	var deadline := Time.get_ticks_msec() + 15000
	while controller.is_initial_navigation_pending() and Time.get_ticks_msec() < deadline:
		await physics_frame
		controller._process(0.0)
	_expect(not controller.is_initial_navigation_pending(), "native navigation installation completes within deadline")


func _test_dirty_during_bake() -> void:
	var controller := _fixture()
	var floor_body := _floor(controller.root_scene)
	controller._start_tile_bake(COORD)
	await _drain(controller)
	var previous := _mesh(controller)
	_expect(previous != null and previous.get_polygon_count() > 0, "fixture bakes real static collision")
	controller.notify_world_geometry_changed()
	controller._start_tile_bake(COORD)
	# No yield: the worker may finish, but its main-thread callback cannot yet
	# run. This deterministically puts the mutation inside the bake lifecycle.
	floor_body.position.x += 10.0
	controller.notify_world_geometry_changed()
	_expect(controller._pick_next_tile() == NO_TILE, "dirty in-flight tile is not concurrently schedulable")
	await _drain(controller)
	_expect(_mesh(controller) == previous, "stale geometry completion never replaces installed mesh")
	_expect(controller.pending_tile_count() == 1, "dirty during bake remains pending after stale completion")
	controller._process(0.0)
	await _drain(controller)
	var fresh := _mesh(controller)
	_expect(fresh != null and fresh != previous, "latest geometry installs on the follow-up bake")
	if fresh != null:
		var min_x := INF
		for vertex in fresh.get_vertices():
			min_x = minf(min_x, vertex.x)
		_expect(min_x > 29.0, "follow-up bake uses moved collision, not parsed stale source")
	_expect(controller.pending_tile_count() == 0, "latest tile becomes baked")
	controller.notify_world_geometry_changed()
	controller._start_tile_bake(COORD)
	controller._start_tile_bake(COORD)
	_expect(controller._inflight.size() == 1, "duplicate start cannot launch a second worker for one tile")
	await _dispose(controller)


func _test_settings_generation() -> void:
	var controller := _fixture()
	_floor(controller.root_scene)
	controller._start_tile_bake(COORD)
	controller.settings.postprocess_enabled = not controller.settings.postprocess_enabled
	controller.apply_settings()
	# No terrain needed: seed the same coordinate into the new generation.
	controller._ensure_tile(COORD)
	_expect(controller._pick_next_tile() == NO_TILE, "settings reset does not overlap an old worker at the same tile")
	await _drain(controller)
	_expect(_mesh(controller) == null, "old settings completion cannot install into the new generation")
	_expect(controller.pending_tile_count() == 1, "new settings tile still requires its own bake")
	controller._process(0.0)
	await _drain(controller)
	_expect(_mesh(controller) != null and controller.pending_tile_count() == 0, "new settings generation completes normally")
	await _dispose(controller)


func _set_tiles_baked(controller: Node) -> void:
	for coord in controller._tiles:
		controller._tiles[coord].state = _controller_script.TileState.BAKED
	controller._geometry_dirty = false


func _queued_coords(controller: Node) -> Array:
	var result: Array = []
	for coord in controller._tiles:
		if controller._tiles[coord].state == _controller_script.TileState.QUEUED:
			result.append(coord)
	result.sort()
	return result


func _seed_grid(controller: Node) -> void:
	for x in range(-3, 8):
		for z in range(-2, 3):
			controller._ensure_tile(Vector2i(x, z))
	_set_tiles_baked(controller)


func _test_local_invalidation() -> void:
	var controller := _fixture()
	var floor_body := _floor(controller.root_scene)
	controller._start_tile_bake(COORD)
	await _drain(controller)
	var before := _mesh(controller)
	floor_body.position.x += 10.0
	controller.notify_content_changed_at(floor_body.global_position)
	_expect(controller._geometry_dirty, "compatibility position notification refreshes parsed source")
	controller._process(0.0)
	await _drain(controller)
	var fresh := _mesh(controller)
	_expect(fresh != before, "compatibility position notification schedules a patch")
	if fresh != null:
		var min_x := INF
		for vertex in fresh.get_vertices():
			min_x = minf(min_x, vertex.x)
		_expect(min_x > 29.0, "local patch reparses actual moved collider")
	_seed_grid(controller)
	var has_api := controller.has_method("notify_geometry_changed")
	_expect(has_api, "one public local API accepts old and new world AABBs")
	if has_api:
		var old_bounds := AABB(Vector3(-70.0, -1.0, 20.0), Vector3(12.0, 2.0, 8.0))
		var new_bounds := AABB(Vector3(190.0, -1.0, 20.0), Vector3(200.0, 2.0, 8.0))
		controller.notify_geometry_changed(old_bounds, new_bounds)
		_expect(_queued_coords(controller) == [Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0)], "old/new bounds dirty both footprints without filling the travel gap")
		_expect(controller._geometry_dirty, "bounds notification invalidates parsed source")
		_set_tiles_baked(controller)
		var border: float = controller.settings.cell_size * _pipeline.TILE_BORDER_CELLS
		var edge := AABB(Vector3(64.0 + border, 0.0, 24.0), Vector3.ZERO)
		controller.notify_geometry_changed(edge, edge)
		_expect(_queued_coords(controller) == [Vector2i(0, 0), Vector2i(1, 0)], "touching expanded bake border invalidates both neighboring tiles")
		_set_tiles_baked(controller)
		var above := AABB(Vector3(24.0, 1000.0, 24.0), Vector3.ONE)
		controller.notify_geometry_changed(above, above)
		_expect(_queued_coords(controller).is_empty(), "out-of-height geometry does not queue unrelated tile volumes")
	await _dispose(controller)


func _test_runtime_bounds() -> void:
	var controller := _fixture()
	_seed_grid(controller)
	# Exercise the production tree event handlers without loading a terrain.
	node_added.connect(controller._on_scene_node_added)
	node_removed.connect(controller._on_scene_node_removed)
	var body := _floor(controller.root_scene)
	(body.get_child(0).shape as BoxShape3D).size.x = 300.0
	# Normal spawn order: add first, then set the final transform.
	body.position.x = 170.0
	await process_frame
	await process_frame
	_expect(_queued_coords(controller) == [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0)], "runtime spawn dirties whole collider bounds at final transform")
	_set_tiles_baked(controller)
	body.free()
	await process_frame
	_expect(_queued_coords(controller) == [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0)], "runtime removal dirties the complete former collider bounds")
	_expect(controller._geometry_dirty, "runtime removal invalidates parsed source")
	await _dispose(controller)


func _full_fixture() -> Node:
	var controller := _fixture()
	controller._mode = _controller_script.Mode.INACTIVE
	controller._tiles.clear()
	controller._activate()
	controller.set_process(false)
	return controller


func _test_full_scene_lifecycle() -> void:
	var controller := _full_fixture()
	var ready_events: Array[int] = []
	controller.initial_navigation_ready.connect(func() -> void: ready_events.append(1))
	var body := _floor(controller.root_scene)
	await process_frame
	controller._process(0.0)
	await _drain(controller)
	var region: NavigationRegion3D = controller._full_scene_region
	var previous := region.navigation_mesh
	_expect(previous != null and controller._has_navmesh, "full-scene mode installs real floor geometry")
	await _await_initial_navigation(controller)
	_expect(ready_events.size() == 1, "first full-scene bake releases startup exactly once")
	var map := controller.get_viewport().find_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, Vector3(22.0, 0.0, 24.0), Vector3(26.0, 0.0, 24.0), true)
	_expect(not path.is_empty() and path[-1].distance_to(Vector3(26.0, 0.0, 24.0)) < 0.5, "released full-scene startup has a usable native path")
	controller.notify_world_geometry_changed()
	_expect(not controller.is_idle(), "full-scene pending source change is not idle")
	controller._process(0.0)
	body.free()
	await _drain(controller)
	_expect(region.navigation_mesh == previous, "full-scene stale source result does not replace prior mesh")
	_expect(not controller.is_idle(), "full-scene removal during bake stays pending")
	controller._process(0.0)
	await _drain(controller)
	_expect(region.navigation_mesh == null or region.navigation_mesh.get_polygon_count() == 0, "empty full-scene rebake clears obsolete navigation")
	_expect(not controller._has_navmesh, "empty full-scene rebake clears has-navmesh flag")
	_expect(controller.is_idle(), "empty full-scene rebake reaches idle")
	_expect(ready_events.size() == 1 and controller.gate_tiles_pending() == 0, "empty runtime patch does not reopen startup gate")
	await _dispose(controller)
	controller = _full_fixture()
	controller._process(0.0)
	await _drain(controller)
	await _await_initial_navigation(controller)
	_expect(not controller.is_initial_navigation_pending() and controller.gate_tiles_pending() == 0, "initial empty full-scene bake releases startup gate")
	await _dispose(controller)
	controller = _full_fixture()
	_floor(controller.root_scene)
	await process_frame
	controller._process(0.0)
	controller.settings.postprocess_enabled = not controller.settings.postprocess_enabled
	controller.apply_settings()
	await _drain(controller)
	_expect(controller._full_scene_region.navigation_mesh == null, "full-scene old settings generation cannot install")
	_expect(controller.is_initial_navigation_pending(), "stale full-scene completion cannot release startup")
	controller._process(0.0)
	await _drain(controller)
	await _await_initial_navigation(controller)
	_expect(controller._has_navmesh and not controller.is_initial_navigation_pending(), "full-scene new settings generation installs")
	await _dispose(controller)


func _test_pending_source_idle() -> void:
	var controller := _fixture()
	_seed_grid(controller)
	# A source change can fall outside all existing tile volumes. It still
	# invalidates the parsed snapshot and must be consumed, not look idle.
	var above := AABB(Vector3(24.0, 1000.0, 24.0), Vector3.ONE)
	controller.notify_geometry_changed(above, above)
	_expect(not controller.is_idle(), "tiled source-only change is pending without queued tiles")
	controller._process(0.0)
	_expect(controller.is_idle() and not controller._geometry_dirty and not controller.is_baking(), "source-only change is parsed without rebaking unrelated tiles")
	node_added.connect(controller._on_scene_node_added)
	node_removed.connect(controller._on_scene_node_removed)
	_floor(controller.root_scene)
	_expect(not controller.is_idle(), "deferred spawn bounds count as pending before their callback")
	await process_frame
	await _dispose(controller)


func _test_teardown() -> void:
	var controller := _fixture()
	var world: Node = controller.root_scene
	_floor(world)
	var events: Array[int] = []
	controller.bake_finished.connect(func() -> void: events.append(1))
	controller._start_tile_bake(COORD)
	# Wait for worker execution, NOT its deferred callback; it cannot execute
	# until this main-thread stack yields. Covers a queued result at teardown.
	var task_id: int = controller._inflight.keys()[0]
	var deadline := Time.get_ticks_msec() + 15000
	while not WorkerThreadPool.is_task_completed(task_id) and Time.get_ticks_msec() < deadline:
		OS.delay_msec(1)
	world.remove_child(controller)
	_expect(not controller.is_baking(), "controller exit drains worker ownership before detaching")
	await _drain(controller)
	_expect(_mesh(controller) == null and events.is_empty(), "queued result cannot install or emit after controller exit")
	controller.notify_world_geometry_changed()
	controller._start_tile_bake(COORD)
	_expect(not controller.is_baking(), "detached controller cannot dispatch another tile bake")
	await _drain(controller)
	controller.free()
	world.free()
	await process_frame
	controller = _full_fixture()
	_floor(controller.root_scene)
	await process_frame
	controller._process(0.0)
	world = controller.root_scene
	world.remove_child(controller)
	_expect(not controller.is_baking(), "full-scene exit drains its active worker")
	await _drain(controller)
	_expect(controller._full_scene_region.navigation_mesh == null, "full-scene callback cannot install after detach")
	controller.free()
	world.free()
	await process_frame


func _test_joined_callback() -> void:
	var controller := _fixture()
	_floor(controller.root_scene)
	controller._start_tile_bake(COORD)
	# This is the production terrain tree_exiting guard. Joining must not
	# orphan tile state or erase callback identity before finalization.
	controller._wait_for_inflight_bakes()
	controller._wait_for_inflight_bakes()
	_expect(controller.is_baking(), "terrain lifetime join retains pending callback ownership")
	await _drain(controller)
	_expect(_mesh(controller) != null and controller.pending_tile_count() == 0, "joined worker callback still finalizes the tile exactly once")
	await _dispose(controller)


func _test_bake_border_contacts() -> void:
	var settings: Resource = load(SETTINGS_PATH).duplicate()
	var missed: Array[String] = []
	for x in range(-3, 4):
		for z in range(-3, 4):
			var coord := Vector2i(x, z)
			var bake_bounds: AABB = _pipeline.tile_bake_aabb(coord, settings)
			var center := bake_bounds.get_center()
			for point in [Vector3(bake_bounds.position.x, 0.0, center.z), Vector3(bake_bounds.end.x, 0.0, center.z), Vector3(center.x, 0.0, bake_bounds.position.z), Vector3(center.x, 0.0, bake_bounds.end.z)]:
				if not _pipeline.affected_tile_coords(AABB(point, Vector3.ZERO), settings).has(coord):
					missed.append("%s at %s" % [coord, point])
	_expect(missed.is_empty(), "every signed-grid bake border contact maps back to its tile: %s" % [missed])


func _test_empty_tiled_source() -> void:
	var controller := _fixture()
	controller._tiles.clear()
	var bounds := AABB(Vector3(24.0, 0.0, 24.0), Vector3.ONE)
	controller.notify_geometry_changed(bounds, bounds)
	controller._process(0.0)
	_expect(controller.is_idle(), "empty tiled coverage consumes source changes without orphaned pending bounds")
	await _dispose(controller)


func _test_disposable_callbacks() -> void:
	var controller := _fixture()
	_seed_grid(controller)
	node_added.connect(controller._on_scene_node_added)
	node_removed.connect(controller._on_scene_node_removed)
	var body := _floor(controller.root_scene)
	body.position.x = 170.0
	body.free()
	await process_frame
	await process_frame
	_expect(_queued_coords(controller) == [Vector2i(2, 0)], "add/free in one frame keeps only former bounds and safely drops queued node reference")
	await _dispose(controller)
	controller = _fixture()
	_floor(controller.root_scene)
	controller._start_tile_bake(COORD)
	var tile_task: RefCounted = controller._inflight.values()[0]
	var world: Node = controller.root_scene
	controller.free()
	world.free()
	await process_frame
	await process_frame
	_expect(tile_task.worker_joined and not is_instance_valid(controller), "free during real tile bake joins worker before deferred callback delivery")
	controller = _full_fixture()
	_floor(controller.root_scene)
	await process_frame
	controller._process(0.0)
	var full_task: RefCounted = controller._inflight.values()[0]
	world = controller.root_scene
	controller.free()
	world.free()
	await process_frame
	await process_frame
	_expect(full_task.worker_joined and not is_instance_valid(controller), "free during real full-scene bake joins worker before deferred callback delivery")


func _test_compatibility_coverage() -> void:
	var controller := _fixture()
	_seed_grid(controller)
	controller.notify_content_changed_at(Vector3(170.0, 0.0, 24.0))
	_expect(_queued_coords(controller) == [Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, -1), Vector2i(2, 0), Vector2i(2, 1), Vector2i(3, -1), Vector2i(3, 0), Vector2i(3, 1)], "position compatibility wrapper retains conservative neighborhood coverage")
	_set_tiles_baked(controller)
	var body := _floor(controller.root_scene)
	(body.get_child(0).shape as BoxShape3D).size.x = 300.0
	body.position.x = 170.0
	controller._dirty_runtime_spawned_tiles()
	_expect(_queued_coords(controller) == [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0)], "cache-loaded runtime content uses the same collider bounds invalidation")
	_expect(controller._geometry_dirty, "cache-loaded runtime content refreshes parsed source")
	_expect(controller.baked_tile_count() + controller.pending_tile_count() == controller.initial_tiles_total(), "public tile counters remain consistent")
	_expect(controller.initial_tiles_done() == controller.baked_tile_count(), "public startup progress remains compatible")
	await _dispose(controller)


func _test_local_change_isolation() -> void:
	var controller := _fixture()
	var other := Vector2i(1, 0)
	controller._ensure_tile(other)
	var body := _floor(controller.root_scene)
	_floor(controller.root_scene, Vector3(88.0, -0.5, 24.0))
	controller._start_tile_bake(COORD)
	controller._start_tile_bake(other)
	var old_bounds: AABB = controller._static_body_world_bounds(body)
	body.position.x += 10.0
	controller.notify_geometry_changed(old_bounds, controller._static_body_world_bounds(body))
	await _drain(controller)
	_expect(_mesh(controller) == null and _mesh(controller, other) != null, "local in-flight change rejects only the affected tile result")
	_expect(controller.pending_tile_count() == 1, "unaffected concurrent tile is not needlessly requeued")
	controller._process(0.0)
	await _drain(controller)
	controller.set_debug_visualization(true)
	controller.set_tile_debug(true)
	_expect(controller.is_debug_visualization_enabled() and controller.is_tile_debug_enabled(), "public debug toggles remain compatible")
	_expect(controller._tiles[other].debug_mesh != null and controller._tiles[COORD].debug_frame != null, "typed tile state still draws mesh and tile frame")
	controller.set_debug_visualization(false)
	controller.set_tile_debug(false)
	_expect(controller._tiles[other].debug_mesh == null and controller._tiles[COORD].debug_frame == null, "debug cleanup releases each tile drawing")
	await _dispose(controller)
