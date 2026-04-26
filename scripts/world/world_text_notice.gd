extends Node3D

@export var lifetime := 1.0
@export var rise_height := 0.4

@onready var label: Label3D = $Label3D

var _elapsed := 0.0
var _start_position := Vector3.ZERO


func setup(world_position: Vector3, message: String, color: Color = Color(1.0, 0.28, 0.28, 1.0)) -> void:
	_start_position = world_position
	global_position = world_position
	label.text = message
	label.modulate = color


func _ready() -> void:
	if _start_position == Vector3.ZERO:
		_start_position = global_position


func _process(delta: float) -> void:
	_elapsed += delta
	var t := minf(_elapsed / lifetime, 1.0)
	global_position = _start_position + Vector3(0.0, rise_height * t, 0.0)
	label.modulate.a = 1.0 - t
	if t >= 1.0:
		queue_free()
