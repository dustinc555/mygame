extends "res://tests/validation/test_case.gd"

## Focused sanity check for CustodyCapability wiring.
## Run: python3 tests/run_validation.py --filter validate_custody_capability
##
## Verifies: WorldActor owns no custody container state, routes containment
## through CustodyCapability, and exposes combat protection while contained.


var _checks := 0

func _initialize() -> void:
	_run_validation.call_deferred()


func _run_validation() -> void:
	var failures: Array[String] = []

	_validate_custody_state_machine(failures)

	if failures.is_empty():
		print("PASS: CustodyCapability (%d checks)" % _checks)
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

	actor.set_move_target(Vector3(20, 0, 0), true)
	actor.enter_cell_custody(cell, Vector3(4.0, 0.0, -2.0), Vector3(0.0, 1.5, 0.0))
	_expect(failures, "custody cancels movement", not actor.has_move_target())
	_expect(failures, "enter sets contained", actor.is_in_cell_custody())
	_expect(failures, "contained actor protected", actor.is_protected_from_combat())

	actor.exit_cell_custody(Vector3(8.0, 0.0, 3.0), Vector3(0.0, -0.5, 0.0))
	_expect(failures, "exit clears contained and protection", not actor.is_in_cell_custody() and not actor.is_protected_from_combat())

	actor.enter_cell_custody(cell, Vector3.ZERO, Vector3.ZERO)
	cell.free()
	_expect(failures, "freed cell removes protection without invalid casts", not actor.is_in_cell_custody() and not actor.is_protected_from_combat() and actor.get_custody().get_container() == null)
	actor.free()


func _make_actor(actor_name: String) -> WorldActor:
	var actor := WorldActor.new()
	actor.name = actor_name
	root.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	return actor


func _expect(failures: Array[String], label: String, condition: bool) -> void:
	_checks += 1
	if not condition:
		failures.append(label)
