extends SceneTree

## Uses the actual saved World1, actor, granary, terrain and shared tile baker.
## No source settings or caches are modified. --cached skips the local rebake;
## --case=<id> selects one independently reset approach for a tight red loop.
## godot --headless --path . --script res://tools/validation/validate_granary_navigation.gd
const WORLD_PATH := "res://scenes/worlds/world1/world1.tscn"
const CASES_PATH := "res://tools/validation/granary_navigation_cases.gd"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world: Node = load(WORLD_PATH).instantiate()
	root.add_child(world)
	current_scene = world
	var runner: Node = load(CASES_PATH).new()
	world.add_child(runner)
	var case_filter := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			case_filter = argument.trim_prefix("--case=")
	runner.start(case_filter, not OS.get_cmdline_user_args().has("--cached"))
	var result: Dictionary = await runner.finished
	var path := "/tmp/hermes-granary-navigation-result.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "\t"))
		file.close()
	for failure in result["failures"]:
		printerr(failure)
	print("GRANARY_NAVIGATION_%s cases=%d failures=%d" % [
		"OK" if result["passed"] else "FAILED", result["cases"].size(), result["failures"].size()])
	quit(0 if result["passed"] else 1)
