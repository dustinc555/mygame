extends "res://tests/validation/test_case.gd"

const TEST_CAPABILITY_SCRIPT = preload("res://tests/validation/helpers/test_actor_capability.gd")
var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var actor := WorldActor.new()
	actor.name = "CapabilityScaffoldActor"
	var replaced = TEST_CAPABILITY_SCRIPT.new()
	var capability = TEST_CAPABILITY_SCRIPT.new()
	actor.add_capability(replaced)
	actor.add_capability(capability)
	_expect(actor.get_capability(&"test") == capability and actor.has_capability(&"test"), "Declaration uses one capability per id (subclass replacement)")
	_expect(capability.setup_calls == 0 and replaced.setup_calls == 0, "Declaring capabilities does not bind them before enter_tree")
	root.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	_expect(capability.setup_calls == 1 and capability.actor == actor and capability.setup_actor == actor, "Normal enter_tree binds exactly once")
	_expect(capability.ready_calls == 1 and replaced.ready_calls == 0, "Only registered capability receives ready")
	actor._process(0.25)
	_expect(capability.process_calls == 1 and is_equal_approx(capability.process_delta, 0.25), "Enabled process receives real actor tick")
	capability.enabled = false
	actor._process(0.5)
	actor._physics_process(0.5)
	_expect(capability.process_calls == 1 and capability.physics_process_calls == 0, "Disabled hooks skipped")
	capability.enabled = true
	actor._physics_process(0.125)
	_expect(capability.physics_process_calls == 1 and is_equal_approx(capability.physics_delta, 0.125), "Enabled physics receives real actor tick")
	actor.free()
	_expect(capability.teardown_calls == 1 and capability.actor == null, "Exit tears down exactly once and clears binding")
	print("ACTOR_CAPABILITY_SCAFFOLD_%s" % ("OK" if _failures == 0 else "FAILED"))
	quit(0 if _failures == 0 else 1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
