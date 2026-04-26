extends Node3D

const MOVE_COMMAND_INDICATOR_SCENE = preload("res://scenes/world/move_command_indicator.tscn")

const FREE_CAMERA_PITCH := -0.65
const FOLLOW_CAMERA_HEIGHT := 1.35
const ORBIT_MIN_PITCH := -1.2
const ORBIT_MAX_PITCH := -0.2
const GROUND_Y := 0.0

@export var free_camera_move_speed := 14.0
@export var camera_zoom_step := 1.0
@export var camera_min_distance := 4.0
@export var camera_max_distance := 36.0
@export var orbit_sensitivity := 0.01
@export var move_command_spacing := 1.4
@export var drag_select_threshold := 12.0

var party_members: Array[PartyMember] = []
var portrait_buttons: Array[Button] = []
var camera_anchor := Vector3.ZERO
var camera_yaw := deg_to_rad(45.0)
var camera_pitch := FREE_CAMERA_PITCH
var camera_distance := 11.0
var is_orbiting := false
var is_left_mouse_down := false
var is_drag_selecting := false
var left_mouse_press_position := Vector2.ZERO
var left_mouse_press_double_click := false

@onready var party_root: Node3D = $PartyMembers
@onready var party_manager: PartyManager = $PartyManager
@onready var camera_rig: Node3D = $CameraRig
@onready var camera_pivot: Node3D = $CameraRig/CameraPivot
@onready var camera: Camera3D = $CameraRig/CameraPivot/Camera3D
@onready var selection_rect: ColorRect = $CanvasLayer/SelectionRect
@onready var avery_portrait: Button = $CanvasLayer/PortraitBar/PortraitRow/AveryPortrait
@onready var bram_portrait: Button = $CanvasLayer/PortraitBar/PortraitRow/BramPortrait
@onready var cora_portrait: Button = $CanvasLayer/PortraitBar/PortraitRow/CoraPortrait


func _ready() -> void:
	for child in party_root.get_children():
		if child is PartyMember:
			party_members.append(child)

	party_manager.set_party_members(party_members)
	party_manager.selection_changed.connect(_update_portraits)
	party_manager.follow_changed.connect(_update_portraits)

	portrait_buttons = [avery_portrait, bram_portrait, cora_portrait]
	for index in range(min(party_members.size(), portrait_buttons.size())):
		var member: PartyMember = party_members[index]
		var button: Button = portrait_buttons[index]
		_configure_portrait_button(button)
		button.text = member.member_name
		button.gui_input.connect(_on_portrait_gui_input.bind(member))

	if not party_members.is_empty():
		party_manager.select_only(party_members[0])

	camera_anchor = _get_anchor_position()
	_apply_camera_transform()
	_update_portraits()


func _process(delta: float) -> void:
	var move_input := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)

	if party_manager.followed_member != null and move_input.length() > 0.0:
		_clear_follow_target()

	if party_manager.followed_member == null and move_input.length() > 0.0:
		var move_basis := Basis(Vector3.UP, camera_yaw)
		var move_direction := move_basis * Vector3(move_input.x, 0.0, move_input.y)
		if move_direction.length() > 0.0:
			camera_anchor += move_direction.normalized() * free_camera_move_speed * delta

	if party_manager.followed_member != null:
		camera_anchor = _get_anchor_position()

	if move_input.length() > 0.0 or party_manager.followed_member != null:
		_apply_camera_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_distance = max(camera_min_distance, camera_distance - camera_zoom_step)
			_apply_camera_transform()
			return

		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_distance = min(camera_max_distance, camera_distance + camera_zoom_step)
			_apply_camera_transform()
			return

		if event.button_index == MOUSE_BUTTON_MIDDLE:
			is_orbiting = event.pressed
			return

		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			is_left_mouse_down = true
			is_drag_selecting = false
			left_mouse_press_position = event.position
			left_mouse_press_double_click = event.double_click
			_update_selection_rect(event.position)
			return

		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_handle_left_mouse_release(event.position)
			return

		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_issue_move_command(event.position)
			return

	if event is InputEventMouseMotion and is_left_mouse_down:
		if not is_drag_selecting and left_mouse_press_position.distance_to(event.position) >= drag_select_threshold:
			is_drag_selecting = true
		if is_drag_selecting:
			_update_selection_rect(event.position)

	if event is InputEventMouseMotion and is_orbiting:
		camera_yaw -= event.relative.x * orbit_sensitivity
		camera_pitch = clamp(camera_pitch - event.relative.y * orbit_sensitivity, ORBIT_MIN_PITCH, ORBIT_MAX_PITCH)
		_apply_camera_transform()


func _handle_left_mouse_release(screen_position: Vector2) -> void:
	if not is_left_mouse_down:
		return

	if is_drag_selecting:
		_apply_drag_selection()
	else:
		_handle_world_selection(screen_position, left_mouse_press_double_click)

	is_left_mouse_down = false
	is_drag_selecting = false
	left_mouse_press_double_click = false
	selection_rect.visible = false


func _handle_world_selection(screen_position: Vector2, should_follow: bool) -> void:
	var member := _pick_party_member(screen_position)
	if member == null:
		party_manager.clear_selection()
		return

	if Input.is_key_pressed(KEY_ALT):
		party_manager.add_selection(member)
	else:
		party_manager.select_only(member)

	if should_follow:
		_set_follow_target(member)


func _apply_drag_selection() -> void:
	var rect := _get_selection_rect(left_mouse_press_position, get_viewport().get_mouse_position())
	var drag_selected: Array[PartyMember] = []
	for member in party_members:
		var sample_position := member.global_position + Vector3(0.0, 1.0, 0.0)
		if camera.is_position_behind(sample_position):
			continue
		var screen_point := camera.unproject_position(sample_position)
		if rect.has_point(screen_point):
			drag_selected.append(member)

	if Input.is_key_pressed(KEY_ALT):
		var merged_selection := party_manager.selected_members.duplicate()
		for member in drag_selected:
			if not merged_selection.has(member):
				merged_selection.append(member)
		party_manager.set_selection(merged_selection)
		return

	party_manager.set_selection(drag_selected)


func _pick_party_member(screen_position: Vector2) -> PartyMember:
	var result := _raycast_from_screen(screen_position)
	if result.is_empty():
		return null

	var collider: Object = result["collider"]
	if collider is PartyMember:
		return collider
	return null


func _issue_move_command(screen_position: Vector2) -> void:
	if party_manager.selected_members.is_empty():
		return

	var target_variant: Variant = _pick_ground_position(screen_position)
	if target_variant == null:
		return

	var target: Vector3 = target_variant
	_spawn_move_command_indicator(target)
	var center := Vector3.ZERO
	for member in party_manager.selected_members:
		center += member.global_position
	center /= party_manager.selected_members.size()

	for member in party_manager.selected_members:
		var offset := member.global_position - center
		offset.y = 0.0
		if offset.length() > move_command_spacing:
			offset = offset.normalized() * move_command_spacing
		member.set_move_target(target + offset)


func _pick_ground_position(screen_position: Vector2) -> Variant:
	var result := _raycast_from_screen(screen_position)
	if not result.is_empty():
		var collider: Object = result["collider"]
		if not (collider is PartyMember):
			return result["position"]

	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	if absf(ray_direction.y) < 0.0001:
		return null

	var distance := (GROUND_Y - ray_origin.y) / ray_direction.y
	if distance <= 0.0:
		return null
	return ray_origin + ray_direction * distance


func _raycast_from_screen(screen_position: Vector2) -> Dictionary:
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_end := ray_origin + camera.project_ray_normal(screen_position) * 500.0
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	return get_world_3d().direct_space_state.intersect_ray(query)


func _spawn_move_command_indicator(target: Vector3) -> void:
	var indicator := MOVE_COMMAND_INDICATOR_SCENE.instantiate()
	if indicator is Node3D:
		indicator.position = target
		add_child(indicator)
		if indicator.has_method("setup_at"):
			indicator.setup_at(target)


func _set_follow_target(member: PartyMember) -> void:
	party_manager.set_followed_member(member)
	camera_anchor = _get_anchor_position()
	_apply_camera_transform()


func _clear_follow_target() -> void:
	if party_manager.followed_member == null:
		return
	camera_anchor = _get_anchor_position()
	party_manager.clear_followed_member()
	_apply_camera_transform()


func _update_portraits() -> void:
	for index in range(min(party_members.size(), portrait_buttons.size())):
		var member: PartyMember = party_members[index]
		var button: Button = portrait_buttons[index]
		var is_selected := member.is_selected
		var is_followed := member.is_focused
		var label := member.member_name
		if is_followed:
			label = "[Follow] %s" % label
		elif is_selected:
			label = "[Selected] %s" % label
		button.text = label
		if is_selected or is_followed:
			_set_button_style(button, Color(0.26, 0.22, 0.12, 0.98), Color(1.0, 0.88, 0.45, 1.0), 3)
		else:
			_set_button_style(button, Color(0.16, 0.16, 0.18, 0.96), Color(0.34, 0.34, 0.38, 1.0), 1)


func _update_selection_rect(current_position: Vector2) -> void:
	selection_rect.visible = is_drag_selecting
	if not is_drag_selecting:
		return

	var rect := _get_selection_rect(left_mouse_press_position, current_position)
	selection_rect.position = rect.position
	selection_rect.size = rect.size


func _get_selection_rect(start: Vector2, finish: Vector2) -> Rect2:
	var rect_position := Vector2(minf(start.x, finish.x), minf(start.y, finish.y))
	var rect_size := Vector2(absf(finish.x - start.x), absf(finish.y - start.y))
	return Rect2(rect_position, rect_size)


func _get_anchor_position() -> Vector3:
	if party_manager.followed_member != null:
		return party_manager.followed_member.global_position + Vector3(0.0, FOLLOW_CAMERA_HEIGHT, 0.0)
	return camera_anchor


func _apply_camera_transform() -> void:
	camera_rig.global_position = _get_anchor_position()
	camera_rig.rotation = Vector3(0.0, camera_yaw, 0.0)
	camera_pivot.rotation = Vector3(camera_pitch, 0.0, 0.0)
	camera.position = Vector3(0.0, 0.0, camera_distance)


func _on_portrait_gui_input(event: InputEvent, member: PartyMember) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.is_key_pressed(KEY_ALT):
			party_manager.add_selection(member)
		else:
			party_manager.select_only(member)

		if event.double_click:
			_set_follow_target(member)


func _configure_portrait_button(button: Button) -> void:
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92, 1.0))
	button.add_theme_color_override("font_hover_color", Color(0.92, 0.92, 0.92, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.92, 0.92, 0.92, 1.0))
	button.add_theme_color_override("font_focus_color", Color(0.92, 0.92, 0.92, 1.0))
	button.add_theme_color_override("font_disabled_color", Color(0.92, 0.92, 0.92, 1.0))
	_set_button_style(button, Color(0.16, 0.16, 0.18, 0.96), Color(0.34, 0.34, 0.38, 1.0), 1)


func _set_button_style(button: Button, background: Color, border: Color, border_width: int) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("focus", style)
