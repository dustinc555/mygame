extends Node

class_name WorldPlayerControlController

const MOVE_COMMAND_INDICATOR_SCENE := preload("res://scenes/world/effects/move_command_indicator.tscn")

const MOVEMENT_MODE_WALK := 0
const MOVEMENT_MODE_RUN := 1
const MOVEMENT_MODE_SNEAK := 2
const SEGMENT_SINGLE := 0
const SEGMENT_LEFT := 1
const SEGMENT_MIDDLE := 2
const SEGMENT_RIGHT := 3
const MOVE_COMMAND_NAV_PROJECTION_VERTICAL_TOLERANCE := 0.8

@export_range(10.0, 10000.0, 10.0) var max_raycast_distance := 2000.0
@export_flags_3d_physics var command_collision_mask := 0xFFFFFFFF
@export var move_command_spacing := 1.4
@export var close_move_command_spacing := 0.85
@export var close_move_command_radius := 2.0
@export var vertical_move_formation_height_threshold := 1.0
@export var drag_select_threshold := 12.0
@export var hold_move_repeat_seconds := 0.15
@export var hold_move_indicator_seconds := 0.3
@export var command_bar_refresh_interval_seconds := 0.25

var root_scene: Node
var hud_layer: CanvasLayer
var _selection_rect: ColorRect
var _context_menu: PopupMenu
var _walk_button: Button
var _running_button: Button
var _sneaking_button: Button
var _auto_heal_button: Button
var _auto_burn_rustdead_button: Button
var _aggressive_button: Button
var _defensive_button: Button
var _passive_button: Button
var _command_bar_initialized := false
var _last_control_state: Dictionary = {}
var _is_left_mouse_down := false
var _is_right_mouse_down := false
var _is_hold_move_active := false
var _is_drag_selecting := false
var _left_mouse_press_position := Vector2.ZERO
var _left_mouse_press_double_click := false
var _hold_move_repeat_remaining := 0.0
var _hold_move_indicator_remaining := 0.0
var _command_bar_refresh_elapsed := 0.0


func initialize(target_root: Node, target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	hud_layer = target_hud
	_bind_hud_nodes()
	_setup_command_bar()
	_update_command_bar()


func _ready() -> void:
	add_to_group("world_player_control_controller")
	_bind_hud_nodes()
	_setup_command_bar()


func _process(delta: float) -> void:
	_process_hold_move(delta)
	_command_bar_refresh_elapsed += delta
	if _command_bar_refresh_elapsed >= command_bar_refresh_interval_seconds:
		_command_bar_refresh_elapsed = 0.0
		_update_last_control_state_from_selection()
		_update_command_bar()


func _unhandled_input(event: InputEvent) -> void:
	if _ui_blocks_control():
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
		return
	if event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)


func has_active_control() -> bool:
	return not _selected_controllable_actor_ids().is_empty()


func blocks_camera_free_movement() -> bool:
	return false


func get_control_state() -> Dictionary:
	_update_last_control_state_from_selection()
	return _last_control_state.duplicate(true)


func apply_control_input(_input: Vector2, _delta: float, _run := false) -> Dictionary:
	_last_control_state = _control_state(false, "direct_control_removed")
	return {}


func issue_move_command(screen_position: Vector2, show_indicator := true) -> bool:
	var ground_hit := _pick_ground_hit(screen_position)
	if ground_hit.is_empty():
		return false
	return issue_move_command_at_world_position(ground_hit["position"], show_indicator, ground_hit.get("normal", Vector3.UP))


func issue_move_command_at_world_position(target: Vector3, show_indicator := true, surface_normal := Vector3.UP) -> bool:
	var selected_ids := _selected_controllable_actor_ids()
	if selected_ids.is_empty():
		_last_control_state = _control_state(false, "no_controllable_selection")
		return false
	var center := _selection_center(selected_ids)
	if show_indicator:
		_spawn_move_command_indicator(target + surface_normal.normalized() * 0.08)
	var preserve_formation := absf(target.y - center.y) <= vertical_move_formation_height_threshold
	var use_close_formation := preserve_formation and selected_ids.size() > 1 and _horizontal_distance(target, center) <= close_move_command_radius
	var changed_ids: Array[String] = []
	for index in range(selected_ids.size()):
		var actor_id := selected_ids[index]
		var record := _population_record(actor_id)
		if record.is_empty():
			continue
		var offset := Vector3.ZERO
		if use_close_formation:
			offset = _get_group_grid_move_offset(index, selected_ids.size(), close_move_command_spacing)
		elif preserve_formation:
			offset = _record_position(record) - center
			offset.y = 0.0
			if offset.length() > move_command_spacing:
				offset = offset.normalized() * move_command_spacing
		else:
			offset = _get_group_grid_move_offset(index, selected_ids.size(), move_command_spacing)
		var member_target := _project_move_command_target(target + offset, target, target.y)
		var updated := _write_move_order(record, member_target, target)
		if not updated.is_empty():
			changed_ids.append(actor_id)
	if changed_ids.is_empty():
		_last_control_state = _control_state(false, "no_orders_written")
		return false
	_refresh_selection()
	_request_projection_sync()
	_update_command_bar()
	_last_control_state = _control_state(true, "move_order", {}, changed_ids)
	_last_control_state["target_position"] = target
	return true


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _context_menu != null:
			_context_menu.hide()
		_is_left_mouse_down = true
		_is_drag_selecting = false
		_left_mouse_press_position = event.position
		_left_mouse_press_double_click = event.double_click
		_update_selection_rect(event.position)
		get_viewport().set_input_as_handled()
		return
	if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_handle_left_mouse_release(event.position)
		get_viewport().set_input_as_handled()
		return
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if _context_menu != null:
			_context_menu.hide()
		_is_right_mouse_down = true
		_is_hold_move_active = issue_move_command(event.position)
		_hold_move_repeat_remaining = hold_move_repeat_seconds
		_hold_move_indicator_remaining = hold_move_indicator_seconds
		get_viewport().set_input_as_handled()
		return
	if event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		_is_right_mouse_down = false
		_is_hold_move_active = false
		get_viewport().set_input_as_handled()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _is_left_mouse_down:
		return
	if not _is_drag_selecting and _left_mouse_press_position.distance_to(event.position) >= drag_select_threshold:
		_is_drag_selecting = true
	if _is_drag_selecting:
		_update_selection_rect(event.position)
		get_viewport().set_input_as_handled()


func _handle_left_mouse_release(screen_position: Vector2) -> void:
	if not _is_left_mouse_down:
		return
	if _is_drag_selecting:
		_apply_drag_selection()
	else:
		_handle_world_selection(screen_position, _left_mouse_press_double_click)
	_is_left_mouse_down = false
	_is_drag_selecting = false
	_left_mouse_press_double_click = false
	if _selection_rect != null:
		_selection_rect.visible = false
	_update_command_bar()


func _handle_world_selection(screen_position: Vector2, should_follow: bool) -> void:
	var projection := _projection_from_screen_position(screen_position)
	var selection := _get_selection_controller()
	if projection == null:
		if selection != null and selection.has_method("clear_selection"):
			selection.call("clear_selection")
		return
	if selection == null or not selection.has_method("select_projection"):
		return
	var add_select := Input.is_key_pressed(KEY_ALT)
	if bool(selection.call("select_projection", projection, add_select)) and should_follow:
		_follow_projection(projection as Node3D)


func _process_hold_move(delta: float) -> void:
	if not _is_right_mouse_down or not _is_hold_move_active:
		return
	_hold_move_repeat_remaining -= delta
	_hold_move_indicator_remaining = maxf(0.0, _hold_move_indicator_remaining - delta)
	if _hold_move_repeat_remaining > 0.0:
		return
	_hold_move_repeat_remaining = hold_move_repeat_seconds
	var screen_position := get_viewport().get_mouse_position()
	var show_indicator := _hold_move_indicator_remaining <= 0.0
	if issue_move_command(screen_position, show_indicator) and show_indicator:
		_hold_move_indicator_remaining = hold_move_indicator_seconds


func _apply_drag_selection() -> void:
	var camera := _current_camera()
	var selection := _get_selection_controller()
	if camera == null or selection == null or not selection.has_method("select_actor_ids"):
		return
	var rect := _get_selection_rect(_left_mouse_press_position, get_viewport().get_mouse_position())
	var selected_ids: Array[String] = []
	for actor_id in _controllable_actor_ids():
		var projection := _projection_for_actor(actor_id)
		if not (projection is Node3D):
			continue
		var sample_position := (projection as Node3D).global_position + Vector3(0.0, 1.0, 0.0)
		if camera.is_position_behind(sample_position):
			continue
		if rect.has_point(camera.unproject_position(sample_position)):
			selected_ids.append(actor_id)
	selection.call("select_actor_ids", selected_ids, Input.is_key_pressed(KEY_ALT))


func _write_move_order(record: Dictionary, target_position: Vector3, issued_position: Vector3) -> Dictionary:
	if not _record_is_controllable(record):
		return {}
	var actor_id := str(record.get("actor_id", record.get("stable_id", ""))).strip_edges()
	if actor_id.is_empty():
		return {}
	var movement_mode := int(record.get("movement_mode", MOVEMENT_MODE_WALK))
	var patch := {
		"actor_id": actor_id,
		"move_order": {
			"active": true,
			"source": "player",
			"target_position": target_position,
			"issued_position": issued_position,
			"movement_mode": movement_mode,
			"issued_msec": Time.get_ticks_msec(),
		},
		"control_intent": {
			"source": "player",
			"mode": "move_order",
			"target_position": target_position,
			"movement_mode": movement_mode,
		},
		"ledger_activity_state": "player_move_order",
	}
	var updated := _upsert_population_record(patch)
	return updated if not updated.is_empty() else patch


func _on_movement_button_pressed(mode: int) -> void:
	for actor_id in _selected_controllable_actor_ids():
		var record := _population_record(actor_id)
		if record.is_empty():
			continue
		var patch := {"actor_id": actor_id, "movement_mode": mode}
		var move_order: Dictionary = record.get("move_order", {}) if record.get("move_order", {}) is Dictionary else {}
		if bool(move_order.get("active", false)):
			move_order = move_order.duplicate(true)
			move_order["movement_mode"] = mode
			patch["move_order"] = move_order
		_upsert_population_record(patch)
	_update_command_bar()
	_refresh_selection()


func _on_auto_heal_button_toggled(button_pressed: bool) -> void:
	_set_selected_flag("auto_heal_enabled", button_pressed)


func _on_auto_burn_rustdead_button_toggled(button_pressed: bool) -> void:
	_set_selected_flag("auto_burn_rustdead_enabled", button_pressed)


func _on_stance_button_pressed(stance: int) -> void:
	for actor_id in _selected_controllable_actor_ids():
		var record := _population_record(actor_id)
		if record.is_empty():
			continue
		_upsert_population_record({"actor_id": actor_id, "combat_stance": stance})
	_update_command_bar()
	_refresh_selection()


func _set_selected_flag(field_name: String, value: bool) -> void:
	for actor_id in _selected_controllable_actor_ids():
		var record := _population_record(actor_id)
		if record.is_empty():
			continue
		var patch := {"actor_id": actor_id}
		patch[field_name] = value
		_upsert_population_record(patch)
	_update_command_bar()
	_refresh_selection()


func _update_command_bar() -> void:
	_bind_hud_nodes()
	_setup_command_bar()
	if _walk_button == null or _running_button == null or _sneaking_button == null or _auto_heal_button == null or _auto_burn_rustdead_button == null or _aggressive_button == null or _defensive_button == null or _passive_button == null:
		return
	var selected_ids := _selected_controllable_actor_ids()
	if selected_ids.is_empty():
		_set_command_toggle(_walk_button, false, true)
		_set_command_toggle(_running_button, false, true)
		_set_command_toggle(_sneaking_button, false, true)
		_set_command_toggle(_auto_heal_button, false, true)
		_set_command_toggle(_auto_burn_rustdead_button, false, true)
		_set_command_toggle(_aggressive_button, false, true)
		_set_command_toggle(_defensive_button, false, true)
		_set_command_toggle(_passive_button, false, true)
		return
	var any_walking := false
	var all_walking := true
	var any_running := false
	var all_running := true
	var any_sneaking := false
	var all_sneaking := true
	var any_auto_heal := false
	var all_auto_heal := true
	var any_auto_burn := false
	var all_auto_burn := true
	var first_stance := -1
	var mixed_stance := false
	for actor_id in selected_ids:
		var record := _population_record(actor_id)
		if record.is_empty():
			continue
		var movement_mode := int(record.get("movement_mode", MOVEMENT_MODE_WALK))
		var walking := movement_mode == MOVEMENT_MODE_WALK
		var running := movement_mode == MOVEMENT_MODE_RUN
		var sneaking := movement_mode == MOVEMENT_MODE_SNEAK
		any_walking = any_walking or walking
		all_walking = all_walking and walking
		any_running = any_running or running
		all_running = all_running and running
		any_sneaking = any_sneaking or sneaking
		all_sneaking = all_sneaking and sneaking
		var auto_heal := bool(record.get("auto_heal_enabled", false))
		var auto_burn := bool(record.get("auto_burn_rustdead_enabled", false))
		any_auto_heal = any_auto_heal or auto_heal
		all_auto_heal = all_auto_heal and auto_heal
		any_auto_burn = any_auto_burn or auto_burn
		all_auto_burn = all_auto_burn and auto_burn
		var stance := int(record.get("combat_stance", 0))
		if first_stance < 0:
			first_stance = stance
		elif stance != first_stance:
			mixed_stance = true
	_set_command_toggle(_walk_button, any_walking, false, any_walking and not all_walking)
	_set_command_toggle(_running_button, any_running, false, any_running and not all_running)
	_set_command_toggle(_sneaking_button, any_sneaking, false, any_sneaking and not all_sneaking)
	_set_command_toggle(_auto_heal_button, any_auto_heal, false, any_auto_heal and not all_auto_heal)
	_set_command_toggle(_auto_burn_rustdead_button, any_auto_burn, false, any_auto_burn and not all_auto_burn)
	_set_command_toggle(_aggressive_button, not mixed_stance and first_stance == 0, false)
	_set_command_toggle(_defensive_button, not mixed_stance and first_stance == 1, false)
	_set_command_toggle(_passive_button, not mixed_stance and first_stance == 2, false)


func _setup_command_bar() -> void:
	if _command_bar_initialized:
		return
	if _walk_button == null or _running_button == null or _sneaking_button == null or _auto_heal_button == null or _auto_burn_rustdead_button == null or _aggressive_button == null or _defensive_button == null or _passive_button == null:
		return
	_set_command_segment_position(_walk_button, SEGMENT_LEFT)
	_set_command_segment_position(_running_button, SEGMENT_MIDDLE)
	_set_command_segment_position(_sneaking_button, SEGMENT_RIGHT)
	_set_command_segment_position(_aggressive_button, SEGMENT_LEFT)
	_set_command_segment_position(_defensive_button, SEGMENT_MIDDLE)
	_set_command_segment_position(_passive_button, SEGMENT_RIGHT)
	_set_command_segment_position(_auto_heal_button, SEGMENT_LEFT)
	_set_command_segment_position(_auto_burn_rustdead_button, SEGMENT_RIGHT)
	_walk_button.pressed.connect(_on_movement_button_pressed.bind(MOVEMENT_MODE_WALK))
	_running_button.pressed.connect(_on_movement_button_pressed.bind(MOVEMENT_MODE_RUN))
	_sneaking_button.pressed.connect(_on_movement_button_pressed.bind(MOVEMENT_MODE_SNEAK))
	_auto_heal_button.toggled.connect(_on_auto_heal_button_toggled)
	_auto_burn_rustdead_button.toggled.connect(_on_auto_burn_rustdead_button_toggled)
	_aggressive_button.pressed.connect(_on_stance_button_pressed.bind(0))
	_defensive_button.pressed.connect(_on_stance_button_pressed.bind(1))
	_passive_button.pressed.connect(_on_stance_button_pressed.bind(2))
	_command_bar_initialized = true


func _set_command_toggle(button: Button, active: bool, disabled: bool, mixed := false) -> void:
	if button == null:
		return
	button.disabled = disabled
	button.set_pressed_no_signal(active)
	_apply_command_button_style(button, active, disabled, mixed)


func _set_command_segment_position(button: Button, segment_position: int) -> void:
	if button != null:
		button.set_meta("command_segment_position", segment_position)


func _apply_command_button_style(button: Button, active: bool, disabled: bool, mixed := false) -> void:
	if button == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.047, 0.043, 0.96)
	style.border_color = Color(0.28, 0.23, 0.16, 1.0)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_right = 3
	style.corner_radius_bottom_left = 3
	match int(button.get_meta("command_segment_position", SEGMENT_SINGLE)):
		SEGMENT_LEFT:
			style.corner_radius_top_right = 0
			style.corner_radius_bottom_right = 0
		SEGMENT_MIDDLE:
			style.corner_radius_top_left = 0
			style.corner_radius_bottom_left = 0
			style.corner_radius_top_right = 0
			style.corner_radius_bottom_right = 0
		SEGMENT_RIGHT:
			style.corner_radius_top_left = 0
			style.corner_radius_bottom_left = 0
	if active:
		style.bg_color = Color(0.22, 0.17, 0.08, 0.98)
		style.border_color = Color(0.95, 0.7, 0.32, 1.0) if not mixed else Color(0.72, 0.56, 0.28, 1.0)
		style.set_border_width_all(2)
	if disabled:
		style.bg_color = Color(0.055, 0.052, 0.049, 0.7)
		style.border_color = Color(0.18, 0.16, 0.13, 1.0)
		style.set_border_width_all(1)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = style.bg_color.lightened(0.08)
	var pressed := style.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.28, 0.21, 0.09, 1.0)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", style)
	button.add_theme_color_override("font_color", Color(0.88, 0.82, 0.68, 1.0) if not disabled else Color(0.38, 0.36, 0.32, 1.0))
	button.add_theme_color_override("font_hover_color", Color(0.98, 0.88, 0.62, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(1.0, 0.88, 0.48, 1.0))
	button.add_theme_font_size_override("font_size", 9 if button.text.length() > 8 else 10)


func _bind_hud_nodes() -> void:
	var hud := hud_layer if hud_layer != null else (root_scene.get_node_or_null("GameHUD") if root_scene != null else null)
	if hud == null:
		return
	_selection_rect = hud.get_node_or_null("SelectionRect") as ColorRect
	_context_menu = hud.get_node_or_null("ContextMenu") as PopupMenu
	var command_rows_path := "HudLayout/BottomHud/RightHud/BottomInfoRow/CommandDock/Margin/CommandColumn/BehaviorRows"
	_walk_button = hud.get_node_or_null(command_rows_path + "/MoveRow/MovementSegment/WalkButton") as Button
	_running_button = hud.get_node_or_null(command_rows_path + "/MoveRow/MovementSegment/RunningButton") as Button
	_sneaking_button = hud.get_node_or_null(command_rows_path + "/MoveRow/MovementSegment/SneakingButton") as Button
	_auto_heal_button = hud.get_node_or_null(command_rows_path + "/AssistRow/AutoHealButton") as Button
	_auto_burn_rustdead_button = hud.get_node_or_null(command_rows_path + "/AssistRow/BurnRustdeadButton") as Button
	_aggressive_button = hud.get_node_or_null(command_rows_path + "/FightRow/CombatSegment/AggressiveButton") as Button
	_defensive_button = hud.get_node_or_null(command_rows_path + "/FightRow/CombatSegment/DefensiveButton") as Button
	_passive_button = hud.get_node_or_null(command_rows_path + "/FightRow/CombatSegment/PassiveButton") as Button


func _pick_ground_hit(screen_position: Vector2) -> Dictionary:
	var result := _raycast_from_screen(screen_position)
	if not result.is_empty():
		var collider = result.get("collider")
		if _projection_from_collider(collider) == null:
			return {"position": result["position"], "normal": result.get("normal", Vector3.UP)}
	var camera := _current_camera()
	if camera == null:
		return {}
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	if absf(ray_direction.y) < 0.0001:
		return {}
	var plane_y := _selection_center(_selected_controllable_actor_ids()).y
	var distance := (plane_y - ray_origin.y) / ray_direction.y
	if distance <= 0.0:
		return {}
	return {"position": ray_origin + ray_direction * distance, "normal": Vector3.UP}


func _raycast_from_screen(screen_position: Vector2) -> Dictionary:
	var camera := _current_camera()
	if camera == null:
		return {}
	var world := camera.get_world_3d()
	if world == null:
		return {}
	var origin := camera.project_ray_origin(screen_position)
	var end := origin + camera.project_ray_normal(screen_position) * max_raycast_distance
	var query := PhysicsRayQueryParameters3D.create(origin, end, command_collision_mask)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	return world.direct_space_state.intersect_ray(query)


func _projection_from_screen_position(screen_position: Vector2) -> Node:
	var result := _raycast_from_screen(screen_position)
	if result.is_empty():
		return null
	return _projection_from_collider(result.get("collider"))


func _projection_from_collider(collider) -> Node:
	var current := collider as Node
	while current != null:
		if current.is_in_group("projected_world_actor"):
			return current
		current = current.get_parent()
	return null


func _project_move_command_target(candidate: Vector3, fallback: Vector3, target_y: float) -> Vector3:
	var camera := _current_camera()
	if camera == null:
		return candidate
	var world_3d := camera.get_world_3d()
	if world_3d == null:
		return candidate
	var navigation_map: RID = world_3d.navigation_map
	if NavigationServer3D.map_get_iteration_id(navigation_map) == 0:
		return candidate
	var closest := NavigationServer3D.map_get_closest_point(navigation_map, candidate)
	if absf(closest.y - target_y) > MOVE_COMMAND_NAV_PROJECTION_VERTICAL_TOLERANCE:
		return fallback
	var horizontal_offset := Vector2(closest.x - candidate.x, closest.z - candidate.z).length()
	if horizontal_offset > move_command_spacing * 1.5:
		return fallback
	return Vector3(closest.x, target_y, closest.z)


func _spawn_move_command_indicator(world_position: Vector3) -> void:
	var instance := MOVE_COMMAND_INDICATOR_SCENE.instantiate()
	if not (instance is Node3D):
		if instance != null:
			instance.queue_free()
		return
	var parent := root_scene if root_scene != null else get_tree().current_scene
	if parent == null:
		(instance as Node3D).queue_free()
		return
	parent.add_child(instance)
	if instance.has_method("setup_at"):
		instance.call("setup_at", world_position)
	else:
		(instance as Node3D).global_position = world_position


func _update_selection_rect(current_position: Vector2) -> void:
	if _selection_rect == null:
		return
	_selection_rect.visible = _is_drag_selecting
	if not _is_drag_selecting:
		return
	var rect := _get_selection_rect(_left_mouse_press_position, current_position)
	_selection_rect.position = rect.position
	_selection_rect.size = rect.size


func _get_selection_rect(start: Vector2, finish: Vector2) -> Rect2:
	var rect_position := Vector2(minf(start.x, finish.x), minf(start.y, finish.y))
	var rect_size := Vector2(absf(finish.x - start.x), absf(finish.y - start.y))
	return Rect2(rect_position, rect_size)


func _get_group_grid_move_offset(member_index: int, selected_count: int, spacing: float) -> Vector3:
	if selected_count <= 1:
		return Vector3.ZERO
	var columns := ceili(sqrt(float(selected_count)))
	var rows := ceili(float(selected_count) / float(columns))
	var column := member_index % columns
	var row := int(float(member_index) / float(columns))
	var x := (float(column) - float(columns - 1) * 0.5) * spacing
	var z := (float(row) - float(rows - 1) * 0.5) * spacing
	return Vector3(x, 0.0, z)


func _horizontal_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()


func _selection_center(actor_ids: Array[String]) -> Vector3:
	if actor_ids.is_empty():
		return Vector3.ZERO
	var center := Vector3.ZERO
	var count := 0
	for actor_id in actor_ids:
		var record := _population_record(actor_id)
		if record.is_empty():
			continue
		center += _record_position(record)
		count += 1
	return center / float(count) if count > 0 else Vector3.ZERO


func _record_position(record: Dictionary) -> Vector3:
	var position = record.get("last_world_position", record.get("world_position", Vector3.ZERO))
	return position if position is Vector3 else Vector3.ZERO


func _record_is_controllable(record: Dictionary) -> bool:
	if record.is_empty():
		return false
	if not bool(record.get("player_controllable", false)):
		return false
	return int(record.get("life_state", 0)) == 0


func _selected_actor_ids() -> Array[String]:
	var selection := _get_selection_controller()
	if selection != null and selection.has_method("get_selected_actor_ids"):
		return selection.call("get_selected_actor_ids")
	if selection != null and selection.has_method("get_selected_actor_id"):
		var actor_id := str(selection.call("get_selected_actor_id"))
		return [actor_id] if not actor_id.is_empty() else []
	return []


func _selected_controllable_actor_ids() -> Array[String]:
	var result: Array[String] = []
	for actor_id in _selected_actor_ids():
		if _record_is_controllable(_population_record(actor_id)):
			result.append(actor_id)
	return result


func _controllable_actor_ids() -> Array[String]:
	var bridge := _get_gecs_world()
	var result: Array[String] = []
	if bridge == null:
		return result
	var records := _get_population_records_core(bridge)
	for actor_id_value in records.keys():
		var record = records[actor_id_value]
		if record is Dictionary and _record_is_controllable(record):
			result.append(str((record as Dictionary).get("actor_id", actor_id_value)))
	return result


func _population_record(actor_id: String) -> Dictionary:
	var bridge := _get_gecs_world()
	if bridge == null:
		return {}
	var record = bridge.call("get_population_record_core", actor_id) if bridge.has_method("get_population_record_core") else (bridge.call("get_population_record", actor_id) if bridge.has_method("get_population_record") else {})
	return record if record is Dictionary else {}


func _upsert_population_record(record: Dictionary) -> Dictionary:
	var bridge := _get_gecs_world()
	if bridge == null:
		return {}
	var updated = bridge.call("upsert_population_record_core", record) if bridge.has_method("upsert_population_record_core") else (bridge.call("upsert_population_record", record) if bridge.has_method("upsert_population_record") else {})
	return updated if updated is Dictionary else {}


func _get_population_records_core(bridge: Node) -> Dictionary:
	if bridge.has_method("get_population_records_core"):
		var core_records = bridge.call("get_population_records_core")
		return core_records if core_records is Dictionary else {}
	if bridge.has_method("get_population_records"):
		var records = bridge.call("get_population_records")
		return records if records is Dictionary else {}
	return {}


func _projection_for_actor(actor_id: String) -> Node:
	var projection_controller := _get_projection_controller()
	if projection_controller != null and projection_controller.has_method("get_projection_for_actor"):
		var projection = projection_controller.call("get_projection_for_actor", actor_id)
		if projection is Node:
			return projection
	return null


func _request_projection_sync() -> void:
	var projection_controller := _get_projection_controller()
	if projection_controller != null and projection_controller.has_method("sync_projections"):
		projection_controller.call("sync_projections")


func _refresh_selection() -> void:
	var selection := _get_selection_controller()
	if selection != null and selection.has_method("refresh_selection_details"):
		selection.call("refresh_selection_details")


func _follow_projection(projection: Node3D) -> void:
	if projection == null or root_scene == null:
		return
	var camera_rig := root_scene.find_child("CameraRig", true, false)
	if camera_rig != null and camera_rig.has_method("follow_target"):
		camera_rig.call("follow_target", projection)


func _current_camera() -> Camera3D:
	var viewport := get_viewport()
	if viewport != null:
		var camera := viewport.get_camera_3d()
		if camera != null:
			return camera
	return root_scene.find_child("Camera3D", true, false) as Camera3D if root_scene != null else null


func _ui_blocks_control() -> bool:
	var hud := hud_layer if hud_layer != null else (root_scene.get_node_or_null("GameHUD") if root_scene != null else null)
	if hud == null:
		return false
	for path in ["PauseOverlay", "ConversationWindow"]:
		var node := hud.get_node_or_null(path) as CanvasItem
		if node != null and node.visible:
			return true
	return false


func _update_last_control_state_from_selection() -> void:
	var selected_ids := _selected_actor_ids()
	var active_ids: Array[String] = []
	for actor_id in selected_ids:
		var record := _population_record(actor_id)
		var move_order: Dictionary = record.get("move_order", {}) if record.get("move_order", {}) is Dictionary else {}
		if bool(move_order.get("active", false)):
			active_ids.append(actor_id)
	_last_control_state = _control_state(not active_ids.is_empty(), "move_order_active" if not active_ids.is_empty() else "idle", {}, active_ids)


func _control_state(active: bool, reason: String, record: Dictionary = {}, actor_ids: Array[String] = []) -> Dictionary:
	var selected_ids := _selected_actor_ids()
	var primary_actor_id := selected_ids[0] if not selected_ids.is_empty() else ""
	return {
		"active": active,
		"reason": reason,
		"actor_id": str(record.get("actor_id", primary_actor_id)),
		"actor_ids": actor_ids.duplicate(),
		"selected_actor_ids": selected_ids.duplicate(),
		"record": record.duplicate(true),
	}


func _get_gecs_world() -> Node:
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("GecsWorldController")
		if local != null:
			return local
	return get_tree().get_first_node_in_group("gecs_world_controller") if is_inside_tree() else null


func _get_projection_controller() -> Node:
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("WorldActorProjectionController")
		if local != null:
			return local
	return get_tree().get_first_node_in_group("world_actor_projection_controller") if is_inside_tree() else null


func _get_selection_controller() -> Node:
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("WorldSelectionController")
		if local != null:
			return local
	return get_tree().get_first_node_in_group("world_selection_controller") if is_inside_tree() else null
