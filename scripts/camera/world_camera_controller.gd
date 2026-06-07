extends Node3D

class_name WorldCameraController

@export var pivot_path := NodePath("CameraPivot")
@export var camera_path := NodePath("CameraPivot/Camera3D")
@export var party_root_path := NodePath("../PartyMembers")
@export_range(0.1, 400.0, 0.1) var move_speed := 42.0
@export_range(1.0, 8.0, 0.1) var fast_move_multiplier := 2.5
@export_range(0.001, 0.02, 0.0005) var orbit_sensitivity := 0.004
@export_range(0.1, 10.0, 0.1) var keyboard_rotate_speed := 2.4
@export_range(2.0, 160.0, 0.5) var min_zoom_distance := 8.0
@export_range(2.0, 240.0, 0.5) var max_zoom_distance := 70.0
@export_range(0.5, 20.0, 0.25) var zoom_step := 4.0
@export_range(0.1, 30.0, 0.1) var follow_smoothing := 12.0
@export var follow_offset := Vector3.ZERO
@export_range(0.0, 10000.0, 10.0) var max_raycast_distance := 2000.0
@export_flags_3d_physics var selection_collision_mask := 0xFFFFFFFF
@export var respect_player_control := true
@export var initial_pitch_degrees := -55.0
@export var min_pitch_degrees := -82.0
@export var max_pitch_degrees := -18.0

var _pivot: Node3D
var _camera: Camera3D
var _yaw := 0.0
var _pitch := deg_to_rad(-55.0)
var _zoom_distance := 24.0
var _orbiting := false
var _follow_target: Node3D


func _ready() -> void:
	_pivot = get_node_or_null(pivot_path) as Node3D
	_camera = get_node_or_null(camera_path) as Camera3D
	if _camera == null:
		_camera = find_child("Camera3D", true, false) as Camera3D
	if _camera != null:
		_camera.current = true
		_zoom_distance = clampf(absf(_camera.position.z), min_zoom_distance, max_zoom_distance)
	_yaw = rotation.y
	_pitch = deg_to_rad(clampf(initial_pitch_degrees, min_pitch_degrees, max_pitch_degrees))
	_apply_camera_transform()


func _unhandled_input(event: InputEvent) -> void:
	if _camera == null:
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
		return
	if event is InputEventMouseMotion and _orbiting:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * orbit_sensitivity
		_pitch = clampf(_pitch - motion.relative.y * orbit_sensitivity, deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))
		_apply_camera_transform()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		_handle_key(event as InputEventKey)


func _process(delta: float) -> void:
	if _camera == null:
		return
	var control_blocks_free_camera := _player_control_blocks_free_camera()
	var keyboard_rotation := _keyboard_rotation_input()
	if not is_zero_approx(keyboard_rotation):
		if not control_blocks_free_camera:
			_clear_follow_target()
		_yaw += keyboard_rotation * keyboard_rotate_speed * delta
		_apply_camera_transform()
	var movement := _free_move_input()
	if movement.length_squared() > 0.0 and not control_blocks_free_camera:
		_clear_follow_target()
		_move_free_camera(movement.normalized(), delta)
		return
	_update_follow(delta)


func follow_target(target: Node3D) -> void:
	_follow_target = target


func clear_follow_target() -> void:
	_clear_follow_target()


func focus_world_position(world_position: Vector3) -> void:
	_clear_follow_target()
	global_position = world_position


func get_follow_target() -> Node3D:
	return _follow_target if _follow_target != null and is_instance_valid(_follow_target) else null


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		_orbiting = event.pressed
		get_viewport().set_input_as_handled()
		return
	if not event.pressed:
		return
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			_zoom(-zoom_step)
			get_viewport().set_input_as_handled()
		MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(zoom_step)
			get_viewport().set_input_as_handled()
		MOUSE_BUTTON_LEFT:
			if event.double_click:
				_focus_from_screen_position(event.position)
				get_viewport().set_input_as_handled()


func _handle_key(event: InputEventKey) -> void:
	if not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F:
			var target := _default_follow_target()
			if target != null:
				follow_target(target)
				get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if get_follow_target() != null:
				_clear_follow_target()
				get_viewport().set_input_as_handled()


func _keyboard_rotation_input() -> float:
	return float(Input.is_key_pressed(KEY_E)) - float(Input.is_key_pressed(KEY_Q))


func _free_move_input() -> Vector3:
	return Vector3(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		0.0,
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)


func _move_free_camera(input: Vector3, delta: float) -> void:
	var right := global_transform.basis.x
	var forward := global_transform.basis.z
	right.y = 0.0
	forward.y = 0.0
	right = right.normalized()
	forward = forward.normalized()
	var speed := move_speed * (fast_move_multiplier if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	global_position += (right * input.x + forward * input.z).normalized() * speed * delta


func _update_follow(delta: float) -> void:
	var target := get_follow_target()
	if target == null:
		_clear_follow_target()
		return
	var target_position := target.global_position + follow_offset
	var weight := 1.0 - exp(-follow_smoothing * delta)
	global_position = global_position.lerp(target_position, clampf(weight, 0.0, 1.0))


func _focus_from_screen_position(screen_position: Vector2) -> void:
	var hit := _raycast_screen_position(screen_position)
	if hit.is_empty():
		return
	var target := _focus_node_from_collider(hit.get("collider"))
	if target != null:
		follow_target(target)
		return
	if hit.get("position") is Vector3:
		focus_world_position(hit["position"])


func _raycast_screen_position(screen_position: Vector2) -> Dictionary:
	var world := get_world_3d()
	if world == null or _camera == null:
		return {}
	var origin := _camera.project_ray_origin(screen_position)
	var end := origin + _camera.project_ray_normal(screen_position) * max_raycast_distance
	var query := PhysicsRayQueryParameters3D.create(origin, end, selection_collision_mask)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	return world.direct_space_state.intersect_ray(query)


func _focus_node_from_collider(collider) -> Node3D:
	var current := collider as Node
	while current != null:
		if current is Node3D and _is_focus_candidate(current):
			return current as Node3D
		current = current.get_parent()
	return null


func _is_focus_candidate(node: Node) -> bool:
	if node == self or node == _pivot or node == _camera:
		return false
	return node is CharacterBody3D or node.is_in_group("projected_world_actor") or node.is_in_group("character_authoring_actor") or node.is_in_group("world_container") or node.is_in_group("settlement_town")


func _default_follow_target() -> Node3D:
	for group_name in ["selected_actor", "selected_party_member", "party_member"]:
		var from_group := _first_node3d_in_group(group_name)
		if from_group != null:
			return from_group
	var party_root := get_node_or_null(party_root_path)
	if party_root != null:
		for child in party_root.get_children():
			if child is Node3D:
				return child as Node3D
	return null


func _first_node3d_in_group(group_name: String) -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group(group_name):
		if node is Node3D:
			return node as Node3D
	return null


func _player_control_blocks_free_camera() -> bool:
	if not respect_player_control or not is_inside_tree():
		return false
	for controller in get_tree().get_nodes_in_group("world_player_control_controller"):
		if controller != null and controller.has_method("blocks_camera_free_movement") and bool(controller.call("blocks_camera_free_movement")):
			return true
	return false


func _zoom(amount: float) -> void:
	_zoom_distance = clampf(_zoom_distance + amount, min_zoom_distance, max_zoom_distance)
	_apply_camera_transform()


func _apply_camera_transform() -> void:
	rotation.y = _yaw
	if _pivot != null:
		_pivot.rotation = Vector3(_pitch, 0.0, 0.0)
	if _camera != null:
		_camera.position = Vector3(0.0, 0.0, _zoom_distance)


func _clear_follow_target() -> void:
	_follow_target = null
