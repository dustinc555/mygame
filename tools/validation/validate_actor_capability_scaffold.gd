extends SceneTree

const WORLD_ACTOR_SCRIPT = preload("res://src/actors/bridge/world_actor.gd")
const TEST_CAPABILITY_SCRIPT = preload("res://tools/validation/helpers/test_actor_capability.gd")

var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var actor := WORLD_ACTOR_SCRIPT.new() as WorldActor
	actor.name = "CapabilityScaffoldActor"
	var capability = TEST_CAPABILITY_SCRIPT.new()

	if not actor.has_method("add_actor_capability"):
		_fail("Expected actor to expose add_actor_capability")
	if not bool(actor.call("add_actor_capability", capability)):
		_fail("Expected first capability registration to succeed")
	if bool(actor.call("add_actor_capability", TEST_CAPABILITY_SCRIPT.new())):
		_fail("Expected duplicate capability registration to fail")
	if actor.call("get_actor_capability", &"test") != capability:
		_fail("Expected capability lookup to return registered instance")
	if not bool(actor.call("has_actor_capability", &"test")):
		_fail("Expected capability id to be registered")
	if capability.setup_calls != 1 or capability.setup_actor != actor or capability.actor != actor:
		_fail("Expected capability setup to bind actor exactly once")

	root.add_child(actor)
	await process_frame
	if capability.ready_calls != 1:
		_fail("Expected capability ready hook after actor enters tree")

	actor.call("_process_actor_capabilities", 0.25)
	if capability.process_calls != 1 or not is_equal_approx(capability.process_delta, 0.25):
		_fail("Expected enabled process hook to run once")

	capability.enabled = false
	actor.call("_process_actor_capabilities", 0.5)
	actor.call("_physics_process_actor_capabilities", 0.5)
	if capability.process_calls != 1 or capability.physics_process_calls != 0:
		_fail("Expected disabled capability hooks to be skipped")

	capability.enabled = true
	actor.call("_physics_process_actor_capabilities", 0.125)
	if capability.physics_process_calls != 1 or not is_equal_approx(capability.physics_delta, 0.125):
		_fail("Expected enabled physics hook to run once")

	actor.queue_free()
	await process_frame
	if capability.teardown_calls != 1 or capability.actor != null:
		_fail("Expected capability teardown to clear actor exactly once")

	if _failures == 0:
		print("ACTOR_CAPABILITY_SCAFFOLD_OK")
		quit(0)
	else:
		print("ACTOR_CAPABILITY_SCAFFOLD_FAILED count=%d" % _failures)
		quit(1)


func _fail(message: String) -> void:
	_failures += 1
	push_error(message)
