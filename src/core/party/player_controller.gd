extends CharacterBody3D

@export var move_speed := 6.0
@export var acceleration := 10.0
@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.002

var gravity := ProjectSettings.get_setting("physics/3d/default_gravity") as float

@onready var head: Node3D = $Head


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_key_pressed(KEY_SPACE):
		velocity.y = jump_velocity

	var input_dir := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)

	var direction := (global_transform.basis.x * input_dir.x) + (global_transform.basis.z * input_dir.y)
	direction.y = 0.0
	direction = direction.normalized()

	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var target_velocity := direction * move_speed
	horizontal_velocity = horizontal_velocity.lerp(target_velocity, min(1.0, acceleration * delta))

	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z

	move_and_slide()
