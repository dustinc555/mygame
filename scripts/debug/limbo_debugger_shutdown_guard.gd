extends Node


var _unregistered := false


func _exit_tree() -> void:
	_unregister_limbo_capture()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_unregister_limbo_capture()


func _unregister_limbo_capture() -> void:
	if _unregistered:
		return
	_unregistered = true
	# LimboAI registers this capture through Godot's wrapper; remove it before wrapper teardown.
	if EngineDebugger.has_capture("limboai"):
		EngineDebugger.unregister_message_capture("limboai")
