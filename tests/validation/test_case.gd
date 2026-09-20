extends Node
## Common entry for tests that need the real project autoloads and extensions.
## Loaded by test_host.tscn after startup, never as a custom main loop.
## The small SceneTree aliases keep existing assertion bodies independent of the host.

var root: Window:
	get: return get_tree().root
var current_scene: Node:
	get: return get_tree().current_scene
	set(value): get_tree().current_scene = value
var paused: bool:
	get: return get_tree().paused
	set(value): get_tree().paused = value
var process_frame: Signal:
	get: return get_tree().process_frame
var physics_frame: Signal:
	get: return get_tree().physics_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Godot still locks the root while attaching the host scene. Start after
	# that operation so cases can install real bootstrap/world siblings.
	_initialize.call_deferred()


func _initialize() -> void:
	pass


func _exit_tree() -> void:
	_finalize()


func _finalize() -> void:
	pass


func get_root() -> Window:
	return get_tree().root


func create_timer(seconds: float, process_always := true, process_in_physics := false, ignore_time_scale := false) -> SceneTreeTimer:
	return get_tree().create_timer(seconds, process_always, process_in_physics, ignore_time_scale)


func get_nodes_in_group(group: StringName) -> Array[Node]:
	return get_tree().get_nodes_in_group(group)


func get_first_node_in_group(group: StringName) -> Node:
	return get_tree().get_first_node_in_group(group)


func quit(code := 0) -> void:
	get_tree().quit(code)
