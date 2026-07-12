@tool
extends EditorPlugin

const SKILLS_MANAGER_DOCK := preload("res://addons/skills_manager/skills_manager_dock.gd")

var _dock: Control


func _enter_tree() -> void:
	_dock = SKILLS_MANAGER_DOCK.new(self)
	add_control_to_bottom_panel(_dock, "Skills")


func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_bottom_panel(_dock)
		_dock.queue_free()
		_dock = null
