extends GutTest

const MAP := preload("res://features/ui/projection/world_map_overlay.gd")

class MoveSink extends Node:
	var targets: Array[Vector3] = []
	func issue_move_command_at_world(target: Vector3, _show: bool) -> bool:
		targets.append(target)
		return true

class GroundSource extends Node:
	var height := 17.5
	func get_terrain_height(_position: Vector3) -> float:
		return height

func test_map_header_has_no_title_or_subtitle() -> void:
	var map := MAP.new()
	add_child_autofree(map)
	var header_labels: Array[String] = []
	for child in map.get_children():
		if child is Label and child.position.y < map._canvas.position.y:
			header_labels.append(child.text)
	assert_eq(header_labels, [], "The map has no decorative title or tagline")

func test_wheel_zooms_toward_cursor_without_losing_world_anchor() -> void:
	var map := MAP.new()
	add_child_autofree(map)
	map.visible = true
	var cursor := Vector2(240, 180)
	var before: Vector2 = map._screen_to_world(cursor)
	var scale_before: float = map.pixels_per_meter
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = cursor
	map._gui_input(wheel)
	assert_gt(map.pixels_per_meter, scale_before, "Wheel must zoom the actual map")
	assert_almost_eq(map._screen_to_world(cursor), before, Vector2.ONE * 0.001, "Zoom stays anchored to the cursor")

func test_drag_pans_and_refresh_does_not_reset_the_view() -> void:
	var map := MAP.new()
	add_child_autofree(map)
	map.visible = true
	var before: Vector2 = map._screen_to_world(Vector2(300, 250))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(300, 250)
	map._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(360, 250)
	motion.relative = Vector2(60, 0)
	map._gui_input(motion)
	assert_almost_eq(map._screen_to_world(Vector2(360, 250)), before, Vector2.ONE * 0.001)
	var panned: Vector2 = map._screen_to_world(Vector2(300, 250))
	map._rebuild_markers()
	assert_eq(map._screen_to_world(Vector2(300, 250)), panned)

func test_map_order_into_unknown_ground_does_not_reveal_it() -> void:
	var map := MAP.new()
	add_child_autofree(map)
	map.visible = true
	var commands := MoveSink.new()
	var ground := GroundSource.new()
	var exploration = load("res://features/world_map/bridge/map_exploration_controller.gd").new()
	add_child_autofree(commands)
	add_child_autofree(ground)
	add_child_autofree(exploration)
	exploration.set_physics_process(false)
	exploration.state = load("res://features/world_map/sim/c_map_exploration_state.gd").new()
	exploration.state.reveal_circle(Vector2(-64, -64), 32)
	var knowledge_before: Dictionary = exploration.state.to_state()
	map._interaction = commands
	map._terrain = ground
	map._exploration = exploration
	var destination := Vector2(20, 20)
	assert_true(map._settings.discovery_enabled)
	assert_false(exploration.state.is_discovered(destination))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	click.position = map._world_to_screen(destination)
	map._gui_input(click)
	assert_eq(commands.targets.size(), 1, "Expeditions can receive orders into unknown terrain")
	if not commands.targets.is_empty():
		assert_almost_eq(commands.targets[0], Vector3(20, 17.5, 20), Vector3.ONE * 0.001, "Unknown destinations still use the actual terrain height")
	assert_eq(exploration.state.to_state(), knowledge_before, "An order must not reveal terrain or add remembered locations")
	assert_false(exploration.state.is_discovered(destination), "Only exploration reveals the destination, not clicking it")
	map._update_footer(click.position)
	assert_string_contains(map._footer.text, "Unexplored")
	assert_string_contains(map._footer.text, "Right-click to travel")

func test_map_travel_accepts_known_ground_and_refuses_missing_or_outside_ground() -> void:
	var map := MAP.new()
	add_child_autofree(map)
	map.visible = true
	var commands := MoveSink.new()
	var ground := GroundSource.new()
	var exploration = load("res://features/world_map/bridge/map_exploration_controller.gd").new()
	add_child_autofree(commands)
	add_child_autofree(ground)
	add_child_autofree(exploration)
	exploration.set_physics_process(false)
	exploration.state = load("res://features/world_map/sim/c_map_exploration_state.gd").new()
	map._interaction = commands
	map._terrain = ground
	map._exploration = exploration
	var cursor: Vector2 = map._world_to_screen(Vector2(20, 20))
	exploration.state.reveal_circle(Vector2(20, 20), 32)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	click.position = cursor
	map._gui_input(click)
	assert_eq(commands.targets.size(), 1)
	assert_almost_eq(commands.targets[0], Vector3(20, 17.5, 20), Vector3.ONE * 0.001, "Order uses the actual terrain height, not the player's floor")
	ground.height = NAN
	assert_false(map._issue_move_order(cursor))
	assert_false(map._issue_move_order(map._world_to_screen(Vector2(10000, 10000))))
	assert_eq(commands.targets.size(), 1, "Refusals never forward a command")

func test_narrow_window_keeps_controls_outside_map_and_preserves_center() -> void:
	var map := MAP.new()
	add_child_autofree(map)
	map.visible = true
	map._view_center = Vector2(100, -200)
	map.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	map.size = Vector2(800, 600)
	map._layout()
	assert_eq(map._view_center, Vector2(100, -200))
	assert_lt(map._toolbar.position.y + 34, map._canvas.position.y)

func test_tile_edges_share_snapped_pixels_without_parchment_cracks() -> void:
	var map := MAP.new()
	add_child_autofree(map)
	map._settings = map._settings.duplicate()
	map._settings.discovery_enabled = false
	map.pixels_per_meter = 0.17333
	map._sync_tiles([
		{"key": Vector3i(0, 0, 0), "rect": Rect2(0, 0, 256, 256), "texture": null},
		{"key": Vector3i(0, 1, 0), "rect": Rect2(256, 0, 256, 256), "texture": null},
	])
	var first: TextureRect = map._tile_nodes[Vector3i(0, 0, 0)]
	var second: TextureRect = map._tile_nodes[Vector3i(0, 1, 0)]
	assert_eq(first.position, first.position.round())
	assert_eq(first.size, first.size.round())
	assert_eq(first.position.x + first.size.x, second.position.x)
	assert_false(first.visible, "Missing images must not draw white fallback quads")
