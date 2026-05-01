@tool
extends EditorPlugin

const JOB_PROVIDER_INSPECTOR = preload("res://addons/job_authoring/job_provider_inspector.gd")

var _inspector_plugin


func _enter_tree() -> void:
	_inspector_plugin = JOB_PROVIDER_INSPECTOR.new(self)
	add_inspector_plugin(_inspector_plugin)


func _exit_tree() -> void:
	if _inspector_plugin != null:
		remove_inspector_plugin(_inspector_plugin)
		_inspector_plugin = null
