extends SceneTree
## Normal scene startup protects demo content and all farming module wiring.
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var game = load("res://scenes/test_levels/farming_test.tscn").instantiate()
	root.add_child(game)
	var deadline := Time.get_ticks_msec() + 10000
	var farm: Node
	while Time.get_ticks_msec() < deadline:
		await process_frame
		farm = BootstrapContext.service(&"farming")
		if farm != null and not farm.get_plots().is_empty(): break
	_expect(farm != null and not farm.get_plots().is_empty(), "normal lifecycle creates durable starter field")
	var module = load("res://features/farming/farming_module.gd")
	var specs: Array = module.SIM + module.BRIDGE
	_expect(specs.size() == 5, "all five farming services including obstruction are declared")
	for spec in specs:
		var service: Node = BootstrapContext.service(spec.service)
		_expect(service != null and service.get_script() == spec.script and game.is_ancestor_of(service), "bootstrap installs the authoritative %s service" % spec.name)
	for path in ["GameBootstrap", "PartyManager", "FarmWaterSource", "FarmSeedProcessor", "CanvasLayer/Buttons/AdvanceTime", "CanvasLayer/Buttons/Rain"]:
		_expect(game.get_node_or_null(path) != null, "demo instantiates %s" % path)
	_expect(game.get_node("Floor").is_in_group("terrain"), "demo floor is registered terrain")
	_expect(game.get_node("CanvasLayer/Buttons/AdvanceTime").pressed.is_connected(game._advance_time), "time control is wired during startup")
	for removed in ["PlanField", "Instructions", "Status"]:
		_expect(game.get_node("CanvasLayer").find_child(removed, true, false) == null, "obsolete instructional control is absent: %s" % removed)
	if farm != null and not farm.get_plots().is_empty():
		var plot: Dictionary = farm.get_plots().values()[0]
		_expect(plot.cells.size() == 12 and plot.cells["1:1"].state == "blocked", "starter field has twelve cells and exact blocked rock square")
		for key in ["1:0", "2:0", "3:0", "3:1", "3:2"]:
			_expect(plot.cells[key].state == "tilled" and plot.cells[key].soil_created, "starter preworked cell %s has physical soil" % key)
		_expect(plot.cells["0:0"].state == "untilled" and not plot.cells["0:0"].soil_created, "manual-work target is not pre-completed")
	# Normal scene startup also starts asynchronous portrait captures. Let
	# those ready-time tasks finish before explicitly freeing the scene.
	await process_frame
	await process_frame
	game.free()
	for failure in failures: push_error(failure)
	print("FARMING_TEST_LEVEL_OK" if failures.is_empty() else "FARMING_TEST_LEVEL_FAILED")
	quit(0 if failures.is_empty() else 1)
func _expect(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
