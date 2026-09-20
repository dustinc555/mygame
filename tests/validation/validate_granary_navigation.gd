extends SceneTree

## Controlled uneven ground, actual hall/steps, actor and shared tile baker.
## No source settings or caches are modified;
## --case=<id> selects one independently reset approach for a tight red loop.
## godot --headless --path . --script res://tests/validation/validate_granary_navigation.gd
const WORLD_PATH := "res://tests/validation/fixtures/granary_navigation/granary_navigation.tscn"
const CASES_PATH := "res://tests/validation/granary_navigation_cases.gd"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world: Node = load(WORLD_PATH).instantiate()
	# Always bake this controlled collision, never consume a saved cache.
	world.scene_file_path = ""
	root.add_child(world)
	current_scene = world
	if not await world.boot():
		printerr("GRANARY_NAVIGATION_FAILED fixture bootstrap/navigation did not become ready")
		world.queue_free()
		await process_frame
		quit(1)
		return
	var runner: Node = load(CASES_PATH).new()
	world.add_child(runner)
	var case_filter := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			case_filter = argument.trim_prefix("--case=")
	runner.start(case_filter, true)
	var result: Dictionary = await runner.finished
	if case_filter.is_empty() and result["passed"]:
		# Reuse the same case object without repeating twelve routes. An empty
		# selection is a deliberate refusal: it must not inherit old case rows
		# or mutate the previous report's arrays, and cleanup must restore the
		# borrowed live actor even on that unsuccessful run.
		var borrowed: CharacterBody3D = runner.get("_actor")
		# Hold ordinary physics only for this cleanup/refusal check, so natural
		# floor settling during readiness does not change its independent oracle.
		var physics_before := borrowed.is_physics_processing()
		borrowed.set_physics_process(false)
		var before := borrowed.global_transform
		var velocity_before := borrowed.velocity
		runner.start("not_a_real_case", false)
		var refused: Dictionary = await runner.finished
		if refused["passed"] or not refused["cases"].is_empty() or result["cases"].size() != 12:
			result["passed"] = false
			result["failures"].append("Reusable helper must reset cases and refuse an empty selection without erasing its previous report")
		if borrowed.global_transform != before or borrowed.velocity != velocity_before:
			result["passed"] = false
			result["failures"].append("Unsuccessful reused helper must restore the borrowed actor transform and velocity")
		if not refused["cleanup"]["actor_restored"]:
			result["passed"] = false
			result["failures"].append("Unsuccessful reused helper must restore the complete borrowed movement state")
		result["reuse_cleanup"] = {"refused_empty_selection": not refused["passed"] and refused["cases"].is_empty(),
			"previous_case_count": result["cases"].size(), "actor_restored": borrowed.global_transform == before and borrowed.velocity == velocity_before,
			"cleanup": refused["cleanup"]}
		borrowed.set_physics_process(physics_before)
	var path := "user://granary-navigation-result.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "\t"))
		file.close()
	for failure in result["failures"]:
		printerr(failure)
	print("GRANARY_NAVIGATION_%s cases=%d failures=%d" % [
		"OK" if result["passed"] else "FAILED", result["cases"].size(), result["failures"].size()])
	world.queue_free()
	await process_frame
	quit(0 if result["passed"] else 1)
