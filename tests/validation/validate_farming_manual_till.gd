extends "res://tests/validation/test_case.gd"
## Production designation, revision and timed-work sequence; fake storage/actor
## isolate this contract from navigation and disk persistence.
const PLACEMENT_BRIDGE = preload("res://features/farming/bridge/farm_placement_bridge.gd")
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var fixtures = load("res://tests/validation/validate_farm_controller.gd")
	var actors = load("res://tests/validation/validate_container_tool_loans.gd")
	var farm := FarmController.new()
	var work := FarmWorkBridge.new()
	var placement = PLACEMENT_BRIDGE.new()
	var gecs = fixtures.FakeGecs.new()
	var territory = fixtures.FakeTerritory.new()
	var actor = actors.FakeActor.new()
	actor.faction_name = "Player"
	actor.equipment.equip_item_to_slot(load("res://features/inventory/resources/items/hoe.tres"), "weapon", "manual.hoe")
	for node in [gecs, territory, farm, work, placement, actor]: root.add_child(node)
	farm._gecs = gecs
	farm._territory = territory
	for crop_id in farm.CROP_PATHS: farm._crops[crop_id] = load(farm.CROP_PATHS[crop_id])
	work._farm = farm
	placement._farm = farm
	placement._farm_work = work
	var rectangle: Dictionary = placement.manual_till_grid(Vector3.ZERO, Vector3(2.5, 0.0, 1.25), 1.25)
	_expect(rectangle.positions.size() == 6 and rectangle.dimensions == Vector2i(3, 2), "drag creates a complete rectangle, not a painted path")
	var positions: Array[Vector3] = [Vector3.ZERO, Vector3(1.25, 0, 0), Vector3(2.5, 0, 0), Vector3(3.75, 0, 0)]
	placement._target_actor = actor
	_expect(placement._submit_manual_till_positions(positions, positions[0]) == "4 cells designated", "public designation creates all four requests without a Jobs scheduler")
	var key: int = actor.get_instance_id()
	var first: Dictionary = work._assignments.get(key, {}).duplicate(true)
	_expect(not first.is_empty() and first.get("command_targets", []).size() == 3, "active sequence retains three pending targets")
	var plot_id: String = first.get("plot_id", "")
	var targets: Array = [{"plot_id": plot_id, "cell_key": first.get("cell_key", ""), "request_revision": first.get("request_revision", -1)}]
	targets.append_array(first.get("command_targets", []))
	for target in targets:
		var request: Dictionary = farm.get_cell_work(plot_id, target.cell_key)
		_expect(request.get("request_revision", -1) == target.request_revision and PackedStringArray(request.get("allowed_actor_ids", [])) == PackedStringArray([actor.stable_id]), "every target has its own current actor-reserved request")
	actor.global_position = first.get("expected_target", Vector3.ZERO)
	work._process_assignment(key, float(first.get("required_seconds", 0.0)) * 2.0)
	var completed: Dictionary = farm.get_plot(plot_id).cells.get(first.get("cell_key", ""), {})
	_expect(completed.get("state", "") == "tilled" and completed.get("soil_created", false), "normal bridge elapsed work tills exact first target")
	var continued: Dictionary = work._assignments.get(key, {})
	_expect(continued.get("cell_key", "") != first.get("cell_key", "") and continued.get("command_targets", []).size() == 2, "Jobs-off completion continues with two more pending requests")
	work.cancel_work_for_actor(actor)
	_expect(not work.has_active_work_for_actor(actor) and not actor.has_meta("active_settlement_work"), "interruption clears active assignment and actor work ownership")
	for target in targets:
		_expect(farm.get_cell_work(plot_id, target.cell_key).is_empty(), "cancellation withdraws every remaining target, not only the current cell")
	_expect(farm.get_plot(plot_id).cells[first.cell_key].soil_created, "cancellation keeps already completed physical soil")
	# A stale first snapshot is skipped, not allowed to erase its newer request.
	var order: Dictionary = farm.prepare_manual_till(positions, actor, positions[0])
	var stale_targets: Array = order.get("targets", []).duplicate(true)
	_expect(stale_targets.size() == 3, "only the three unfinished cells remain eligible")
	if stale_targets.size() == 3:
		stale_targets[0].request_revision += 1
		_expect(work.assign_cell_sequence(stale_targets, actor) == "3 cells queued", "stale first snapshot does not prevent valid later reservations")
		_expect(work._assignments.get(key, {}).get("cell_key", "") == stale_targets[1].cell_key, "sequence starts the first actually current target")
		work.cancel_work_for_actor(actor)
		_expect(not farm.get_cell_work(plot_id, stale_targets[0].cell_key).is_empty(), "cleanup cannot withdraw a request using a stale revision")
	# Non-skippable eligibility failure must clean all newly reserved requests.
	order = farm.prepare_manual_till(positions, actor, positions[0])
	actor.equipment.unequip_item_from_slot("weapon")
	_expect(work.assign_cell_sequence(order.get("targets", []), actor).begins_with("Cannot"), "missing hoe rejects first target")
	for target in order.get("targets", []):
		_expect(farm.get_cell_work(target.plot_id, target.cell_key).is_empty(), "failed first assignment cancels all its pending reservations")
	for node in [placement, work, actor, farm, territory, gecs]: node.free()
	for failure in failures: push_error(failure)
	print("FARMING_MANUAL_TILL_OK" if failures.is_empty() else "FARMING_MANUAL_TILL_FAILED")
	quit(0 if failures.is_empty() else 1)
func _expect(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
