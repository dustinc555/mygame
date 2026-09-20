extends Node
## One normal scene entry for dependency-heavy feature tests. Autoloads are
## initialized by Godot before _ready; loading the test here avoids --script's
## eager-compilation path and does not invent a second ECS world or singleton.

func _ready() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1 or not arguments[0].begins_with("res://tests/validation/") or arguments[0].contains(".."):
		push_error("Usage: test_host.tscn -- res://tests/validation/validate_feature.gd")
		get_tree().quit(2)
		return
	var test_script = load(arguments[0])
	if test_script == null or not test_script.can_instantiate():
		push_error("Test script could not be loaded: %s" % arguments[0])
		get_tree().quit(1)
		return
	var test = test_script.new()
	if not test is Node:
		if test != null and not test is RefCounted:
			test.free()
		push_error("Hosted test must extend tests/validation/test_case.gd")
		get_tree().quit(1)
		return
	add_child(test)
