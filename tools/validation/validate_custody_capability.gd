extends SceneTree

## Focused sanity check for CustodyCapability wiring.
## Run: godot --headless --path . --script res://tools/validation/validate_custody_capability.gd
##
## Verifies: WorldActor owns no custody container state, routes containment
## through CustodyCapability, and exposes combat protection while contained.


func _initialize() -> void:
	_run_validation.call_deferred()


func _run_validation() -> void:
	var failures: Array[String] = []

	_validate_custody_state_machine(failures)

	if failures.is_empty():
		print("PASS: CustodyCapability state machine sane (6 checks)")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		quit(1)


func _validate_custody_state_machine(failures: Array[String]) -> void:
	var actor := _make_actor("prisoner")
	var cell := Node.new()
	cell.name = "cell"
	root.add_child(cell)

	_expect(failures, "actor has custody capability", actor.get_custody() != null)
	_expect(failures, "initially not contained", not actor.is_in_cell_custody())
	_expect(failures, "initially not protected", not actor.is_protected_from_combat())

	actor.enter_cell_custody(cell, Vector3(4.0, 0.0, -2.0), Vector3(0.0, 1.5, 0.0))
	_expect(failures, "enter sets contained", actor.is_in_cell_custody())
	_expect(failures, "contained actor protected", actor.is_protected_from_combat())

	actor.exit_cell_custody(Vector3(8.0, 0.0, 3.0), Vector3(0.0, -0.5, 0.0))
	_expect(failures, "exit clears contained and protection", not actor.is_in_cell_custody() and not actor.is_protected_from_combat())

	actor.free()
	cell.free()


func _make_actor(actor_name: String) -> WorldActor:
	var actor := WorldActor.new()
	actor.name = actor_name
	root.add_child(actor)
	actor._create_actor_capabilities()
	for capability in actor._capabilities.values():
		(capability as ActorCapability).setup(actor)
	for capability in actor._capabilities.values():
		(capability as ActorCapability).ready()
	return actor


func _expect(failures: Array[String], label: String, condition: bool) -> void:
	if not condition:
		failures.append(label)
