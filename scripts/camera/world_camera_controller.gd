extends Node3D

class_name WorldCameraController

const FREE_CAMERA_PITCH := -0.65
const FOLLOW_CAMERA_HEIGHT := 1.35
const ORBIT_MIN_PITCH := -1.2
const ORBIT_MAX_PITCH := 1.15
const GROUND_Y := 0.0
const CAMERA_FLOOR_CLEARANCE := 0.35

@export var pivot_path := NodePath("CameraPivot")
@export var camera_path := NodePath("CameraPivot/Camera3D")
@export var free_camera_move_speed := 14.0
@export var camera_zoom_step := 1.0
@export var camera_min_distance := 2.0
@export var camera_max_distance := 36.0
@export var orbit_sensitivity := 0.01
@export_range(0.0, 0.5, 0.005) var follow_smoothing_seconds := 0.08

var camera_anchor := Vector3.ZERO
var camera_yaw := deg_to_rad(45.0)
var camera_pitch := FREE_CAMERA_PITCH
var camera_distance := 11.0
var is_orbiting := false

var _pivot: Node3D
var _camera: Camera3D
var _follow_target: Node3D
var _projection_controller: Node
var _focused_actor_id := ""


func _ready() -> void:
	_pivot = get_node_or_null(pivot_path) as Node3D
	_camera = get_node_or_null(camera_path) as Camera3D
	if _camera == null:
		_camera = find_child("Camera3D", true, false) as Camera3D
	if _camera != null:
		_camera.current = true
	camera_anchor = global_position
	camera_distance = clampf(camera_distance, camera_min_distance, camera_max_distance)
	_apply_camera_transform()


func _process(delta: float) -> void:
	if _camera == null:
		return
	var input_delta := delta / maxf(Engine.time_scale, 0.001)
	var move_input := Vector2.ZERO
	if not _is_text_input_focused():
		move_input = Vector2(
			float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
			float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
		)
	if get_follow_target() != null and move_input.length() > 0.0:
		_clear_follow_target()
	if get_follow_target() == null and move_input.length() > 0.0:
		var move_basis := Basis(Vector3.UP, camera_yaw)
		var move_direction := move_basis * Vector3(move_input.x, 0.0, move_input.y)
		if move_direction.length() > 0.0:
			camera_anchor += move_direction.normalized() * free_camera_move_speed * input_delta
	if get_follow_target() != null:
		camera_anchor = _smoothed_follow_anchor(input_delta)
	if move_input.length() > 0.0 or get_follow_target() != null:
		_apply_camera_transform()


func _unhandled_input(event: InputEvent) -> void:
	if _camera == null:
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
			camera_distance = maxf(camera_min_distance, camera_distance - camera_zoom_step)
			_apply_camera_transform()
			get_viewport().set_input_as_handled()
			return
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
			camera_distance = minf(camera_max_distance, camera_distance + camera_zoom_step)
			_apply_camera_transform()
			get_viewport().set_input_as_handled()
			return
		if mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
			is_orbiting = mouse_event.pressed
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and is_orbiting:
		var motion := event as InputEventMouseMotion
		camera_yaw -= motion.relative.x * orbit_sensitivity
		camera_pitch = clampf(camera_pitch - motion.relative.y * orbit_sensitivity, ORBIT_MIN_PITCH, ORBIT_MAX_PITCH)
		_apply_camera_transform()
		get_viewport().set_input_as_handled()


func follow_target(target: Node3D) -> void:
	_follow_target = target if target != null and is_instance_valid(target) else null
	_sync_focused_actor()
	if _follow_target == null:
		return
	camera_anchor = _follow_target_anchor_position()
	_apply_camera_transform()


func clear_follow_target() -> void:
	_clear_follow_target()


func focus_world_position(world_position: Vector3) -> void:
	_clear_follow_target()
	camera_anchor = world_position
	_apply_camera_transform()


func get_follow_target() -> Node3D:
	return _follow_target if _follow_target != null and is_instance_valid(_follow_target) else null


func get_focused_actor_id() -> String:
	return _focused_actor_id


func _get_anchor_position() -> Vector3:
	var target := get_follow_target()
	if target != null:
		return _follow_target_anchor_position()
	return camera_anchor


func _follow_target_anchor_position() -> Vector3:
	var target := get_follow_target()
	if target != null:
		return target.global_position + Vector3(0.0, FOLLOW_CAMERA_HEIGHT, 0.0)
	return camera_anchor


func _smoothed_follow_anchor(delta: float) -> Vector3:
	_sync_follow_target_projection(delta)
	var target_anchor := _follow_target_anchor_position()
	if follow_smoothing_seconds <= 0.0:
		return target_anchor
	var ratio := 1.0 - exp(-maxf(delta, 0.0) / follow_smoothing_seconds)
	var next_anchor := camera_anchor.lerp(target_anchor, clampf(ratio, 0.0, 1.0))
	return target_anchor if next_anchor.distance_squared_to(target_anchor) <= 0.0001 else next_anchor


func _apply_camera_transform() -> void:
	global_position = camera_anchor
	rotation = Vector3(0.0, camera_yaw, 0.0)
	if _pivot != null:
		_pivot.rotation = Vector3(camera_pitch, 0.0, 0.0)
	if _camera != null:
		_camera.rotation = Vector3.ZERO
		_camera.position = Vector3(0.0, 0.0, camera_distance)
		_clamp_camera_above_floor()


func _clamp_camera_above_floor() -> void:
	if _camera == null:
		return
	var minimum_camera_y := GROUND_Y + CAMERA_FLOOR_CLEARANCE
	if _camera.global_position.y >= minimum_camera_y:
		return
	var adjusted_position := _camera.global_position
	adjusted_position.y = minimum_camera_y
	_camera.global_position = adjusted_position


func _clear_follow_target() -> void:
	_follow_target = null
	_sync_focused_actor()
	_apply_camera_transform()


func _sync_focused_actor() -> void:
	var previous_actor_id := _focused_actor_id
	_focused_actor_id = _actor_id_for_node(get_follow_target())
	if previous_actor_id == _focused_actor_id:
		_update_projection_focus(_focused_actor_id, true)
		return
	_update_projection_focus(previous_actor_id, false)
	_update_projection_focus(_focused_actor_id, true)


func _update_projection_focus(actor_id: String, focused: bool) -> void:
	if actor_id.strip_edges().is_empty() or not is_inside_tree():
		return
	var projection_controller := _get_projection_controller()
	if projection_controller == null or not projection_controller.has_method("get_projection_for_actor"):
		return
	var projection = projection_controller.call("get_projection_for_actor", actor_id)
	if projection != null and projection.has_method("set_focused"):
		projection.call("set_focused", focused)


func _sync_follow_target_projection(delta: float) -> void:
	var target := get_follow_target()
	if target == null:
		return
	var actor_id := _actor_id_for_node(target)
	if actor_id.is_empty():
		return
	var projection_controller := _get_projection_controller()
	if projection_controller != null and projection_controller.has_method("sync_projection_transform_for_actor"):
		projection_controller.call("sync_projection_transform_for_actor", actor_id, delta)


func _get_projection_controller() -> Node:
	if _projection_controller != null and is_instance_valid(_projection_controller):
		return _projection_controller
	if not is_inside_tree():
		return null
	_projection_controller = get_tree().get_first_node_in_group("world_actor_projection_controller")
	return _projection_controller


func _actor_id_for_node(node: Node) -> String:
	var current := node
	while current != null:
		var actor_id = current.get("actor_id")
		if actor_id != null and not str(actor_id).strip_edges().is_empty():
			return str(actor_id).strip_edges()
		if current.has_meta("actor_id"):
			var meta_actor_id := str(current.get_meta("actor_id")).strip_edges()
			if not meta_actor_id.is_empty():
				return meta_actor_id
		current = current.get_parent()
	return ""


func _is_text_input_focused() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit
