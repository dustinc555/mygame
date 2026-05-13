extends Camera3D


@export var move_speed := 16.0
@export var fast_multiplier := 3.0
@export var mouse_sensitivity := 0.0025

var _yaw := 0.0
var _pitch := 0.0


func _ready() -> void:
	current = true
	_yaw = rotation.y
	_pitch = rotation.x
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-88.0), deg_to_rad(88.0))
		rotation = Vector3(_pitch, _yaw, 0.0)


func _process(delta: float) -> void:
	var input := Vector3.ZERO
	input.x = float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
	input.y = float(Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE)) - float(Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_CTRL))
	input.z = float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	if input.length_squared() <= 0.0:
		return

	var speed := move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= fast_multiplier
	var direction := (global_transform.basis * input.normalized())
	global_position += direction * speed * delta
