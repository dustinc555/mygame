extends Node3D

@export var lifetime := 0.7
@export var rise_height := 0.9
@export var end_scale := 0.45

@onready var ring_mesh: MeshInstance3D = $Ring
@onready var arrow_root: Node3D = $Arrow

var _elapsed := 0.0
var _start_position := Vector3.ZERO
var _start_scale := Vector3.ONE
var _ring_material := StandardMaterial3D.new()
var _arrow_material := StandardMaterial3D.new()


func setup_at(world_position: Vector3) -> void:
	_start_position = world_position
	global_position = world_position


func _ready() -> void:
	if _start_position == Vector3.ZERO:
		_start_position = global_position
	_start_scale = scale
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_material.albedo_color = Color(1.0, 0.82, 0.3, 0.95)
	ring_mesh.material_override = _ring_material

	_arrow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arrow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_arrow_material.albedo_color = Color(1.0, 0.93, 0.62, 0.98)
	for child in arrow_root.get_children():
		if child is MeshInstance3D:
			child.material_override = _arrow_material


func _process(delta: float) -> void:
	_elapsed += delta
	var t := minf(_elapsed / lifetime, 1.0)
	var eased := 1.0 - pow(1.0 - t, 3.0)

	global_position = _start_position + Vector3(0.0, rise_height * eased, 0.0)
	scale = _start_scale.lerp(Vector3(end_scale, end_scale, end_scale), eased)

	_ring_material.albedo_color.a = lerpf(0.95, 0.0, eased)
	_arrow_material.albedo_color.a = lerpf(0.98, 0.0, eased)

	var ring_scale := lerpf(0.65, 1.8, eased)
	ring_mesh.scale = Vector3(ring_scale, 1.0, ring_scale)
	arrow_root.rotation.y += delta * 2.4

	if t >= 1.0:
		queue_free()
