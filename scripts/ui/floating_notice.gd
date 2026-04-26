extends Control

class_name FloatingNotice

@export var lifetime := 1.25

@onready var label: Label = $Label

var _elapsed := 0.0


func show_message(message: String) -> void:
	label.text = message
	_elapsed = 0.0
	visible = true
	modulate = Color(1.0, 1.0, 1.0, 1.0)


func _process(delta: float) -> void:
	if not visible:
		return
	_elapsed += delta
	var t := minf(_elapsed / lifetime, 1.0)
	var offset := lerpf(0.0, -10.0, t)
	position.y = 18.0 + offset
	modulate.a = 1.0 - t
	if t >= 1.0:
		visible = false
