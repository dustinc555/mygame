extends SceneTree

## Production-world smoke: actual bootstrap, terrain, input and session saves.
## Set MAP_CAPTURE_DIR for rendered evidence; no authored world is modified.
var _failures: Array[String] = []
var _world: Node

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	# The capture is a 2D UI proof, not a 3D-performance measurement.
	if not OS.get_environment("MAP_CAPTURE_DIR").is_empty():
		root.disable_3d = true
	_world = load("res://scenes/worlds/world1/world1.tscn").instantiate()
	root.add_child(_world)
	current_scene = _world
	var until := Time.get_ticks_msec() + 60000
	var map: Control
	while Time.get_ticks_msec() < until:
		await process_frame
		var context := BootstrapContext.active
		if context == null: continue
		var status := context.get_optional(&"world_status")
		if status != null:
			map = status.world_map_overlay
		var discovery := context.get_optional(&"map_exploration")
		if map != null and discovery != null and not discovery.party_markers.is_empty() and not paused:
			break
	_check(map != null, "production bootstrap supplies the M-key map")
	if map == null:
		await _finish()
		return
	var context := BootstrapContext.active
	var atlas := context.get_optional(&"world_atlas")
	var exploration := context.get_optional(&"map_exploration")
	_check(atlas.bounds.has_area(), "native Terrain3D provides actual world bounds")
	_check(not exploration.party_markers.is_empty(), "real party supplies discovery observers")
	print("MAP_WORLD bounds=", atlas.bounds, " party=", exploration.party_markers, " features=", atlas.source.all_features().size())
	await _key(KEY_M)
	_check(map.visible, "M opens through viewport input")
	await _settle(atlas)
	await _capture("01-discovery")
	var cursor: Vector2 = map._map_rect().get_center() + Vector2(70, 20)
	var anchor: Vector2 = map._screen_to_world(cursor)
	var old_scale: float = map.pixels_per_meter
	await _button(MOUSE_BUTTON_WHEEL_UP, cursor, true)
	_check(map.pixels_per_meter > old_scale and map._screen_to_world(cursor).distance_to(anchor) < 0.01, "real wheel input zooms around cursor")
	var before: Vector2 = map._screen_to_world(cursor)
	await _button(MOUSE_BUTTON_LEFT, cursor, true)
	var motion := InputEventMouseMotion.new()
	motion.position = cursor + Vector2(65, 0)
	motion.relative = Vector2(65, 0)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	await process_frame
	await _button(MOUSE_BUTTON_LEFT, cursor + Vector2(65, 0), false)
	_check(map._screen_to_world(cursor + Vector2(65, 0)).distance_to(before) < 0.01, "real pointer drag pans")
	await _key(KEY_ESCAPE)
	_check(not map.visible, "Escape closes map without opening another menu")
	await _key(KEY_M)
	map.fit_world()
	await _settle(atlas)
	await _capture("02-world-discovery")
	var sim := context.get_optional(&"world_simulation")
	var save := "user://map-runtime-roundtrip.tres"
	if sim != null and not exploration.party_markers.is_empty():
		var origin: Vector2 = exploration.party_markers[0]["world"]
		var remote: Vector2 = atlas.bounds.end + Vector2(2000, 2000)
		_check(exploration.state.is_discovered(origin) and not exploration.state.is_discovered(remote), "fresh game only knows visited ground")
		_check(sim.save_world_to_file(save), "normal session save writes exploration")
		exploration.state.reveal_circle(remote, 96)
		_check(sim.load_world_from_file(save), "normal session load succeeds")
		_check(exploration.state.is_discovered(origin) and not exploration.state.is_discovered(remote), "session load restores saved exploration, not unsaved reveals")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	else:
		_check(false, "session save service and party available")
	# Temporary authoring preview of the SAME terrain. Never save this setting
	# or seed fictional geography; captures distinguish it from player discovery.
	var original_settings: Resource = map._settings
	map._settings = original_settings.duplicate()
	map._settings.discovery_enabled = false
	map._on_discovery_changed([])
	map.fit_world()
	await _settle(atlas)
	await _capture("03-geography-preview")
	map.focus_party()
	map._zoom_at(map._map_rect().get_center(), 2.0)
	await _settle(atlas)
	await _capture("04-town-preview")
	map._settings = original_settings
	map._on_discovery_changed([])
	await _finish()

func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame

func _button(button: MouseButton, point: Vector2, pressed: bool) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = point
	event.pressed = pressed
	root.push_input(event, true)
	await process_frame

func _settle(atlas: Node) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while not atlas.is_idle() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(atlas.is_idle(), "visible atlas tiles finish within bounded wait")
	print("MAP_TILES resident=", atlas.resident_tile_count())

func _capture(label: String) -> void:
	var folder := OS.get_environment("MAP_CAPTURE_DIR")
	if folder.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(folder)
	_check(root.get_texture().get_image().save_png(folder.path_join(label + ".png")) == OK, "capture " + label)

func _check(ok: bool, label: String) -> void:
	print("MAP_CHECK ", "PASS " if ok else "FAIL ", label)
	if not ok: _failures.append(label)

func _finish() -> void:
	_world.queue_free()
	await process_frame
	await process_frame
	print("MAP_VALIDATION ", "PASS" if _failures.is_empty() else _failures)
	quit(0 if _failures.is_empty() else 1)
