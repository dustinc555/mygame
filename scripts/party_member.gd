extends CharacterBody3D

class_name PartyMember

@export var member_name := "Party Member"
@export var base_color := Color(0.7, 0.7, 0.7, 1.0)
@export var selected_color := Color(1.0, 0.88, 0.48, 1.0)
@export var focused_color := Color(1.0, 0.97, 0.7, 1.0)
@export var move_speed := 4.5
@export var acceleration := 10.0

var is_selected := false
var is_focused := false
var _move_target := Vector3.ZERO
var _has_move_target := false

@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var selection_ring: MeshInstance3D = $SelectionRing

var _body_material := StandardMaterial3D.new()
var _ring_material := StandardMaterial3D.new()


func _ready() -> void:
	add_to_group("party_member")
	_body_material.roughness = 0.85
	_body_material.albedo_color = base_color
	body_mesh.material_override = _body_material

	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	selection_ring.material_override = _ring_material
	_update_visuals()


func _physics_process(delta: float) -> void:
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	if _has_move_target:
		var to_target := _move_target - global_position
		to_target.y = 0.0
		if to_target.length() <= 0.1:
			_has_move_target = false
			horizontal_velocity = Vector3.ZERO
		else:
			var direction := to_target.normalized()
			horizontal_velocity = horizontal_velocity.lerp(direction * move_speed, min(1.0, acceleration * delta))
			look_at(global_position + direction, Vector3.UP)
	else:
		horizontal_velocity = horizontal_velocity.lerp(Vector3.ZERO, min(1.0, acceleration * delta))

	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	move_and_slide()


func set_selected(value: bool) -> void:
	is_selected = value
	_update_visuals()


func set_focused(value: bool) -> void:
	is_focused = value
	_update_visuals()


func set_move_target(target: Vector3) -> void:
	_move_target = target
	_has_move_target = true


func _update_visuals() -> void:
	var body_color := base_color
	if is_selected:
		body_color = base_color.lerp(selected_color, 0.4)
	if is_focused:
		body_color = body_color.lerp(focused_color, 0.45)
	_body_material.albedo_color = body_color

	selection_ring.visible = is_selected or is_focused
	if is_focused:
		_ring_material.albedo_color = focused_color
	elif is_selected:
		_ring_material.albedo_color = selected_color
