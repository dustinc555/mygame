extends "res://tests/validation/test_case.gd"

const TWO_TOWNS_SCENE := preload("res://scenes/test_levels/two_towns_road_test.tscn")

var _failures: Array[String] = []
var _scene: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_scene = TWO_TOWNS_SCENE.instantiate()
	_set_actor_realization_policy("Settlements/FarmerCrossing", "full_town")
	_set_actor_realization_policy("Settlements/RaiderCamp", "full_town")
	root.add_child(_scene)
	for _frame in range(600):
		var context := BootstrapContext.active
		if context != null and context.get_optional(&"population") != null and context.get_optional(&"settlement") != null:
			if not context.get_optional(&"settlement").get_settlement_state("farmer_crossing").get("assignment_slots", {}).is_empty(): break
		await process_frame
	var population: Node = BootstrapContext.active.require(&"population")
	for town_name in ["FarmerCrossing", "RaiderCamp"]:
		var town: Node = _scene.get_node("Settlements/" + town_name)
		var spawner: Node = town.get_node("Residents")
		var generated: Array = population.ensure_generated_population(town.get_settlement_id(), "census", 12, spawner.call("_build_population_generation_context", 0))
		if generated.size() != 12: _fail("Dense query fixture needs twelve generated people per town")
		spawner.call("_spawn_missing_residents")
	var context := BootstrapContext.active
	for id in ["farmer_crossing", "raider_camp"]:
		context.require(&"settlement_census").call("_reconcile_population", context.require(&"settlement"), population, id)
	for _frame in range(900):
		if _count_live_spawner_residents("Settlements/FarmerCrossing/Residents") >= 12 and _count_live_spawner_residents("Settlements/RaiderCamp/Residents") >= 12: break
		await process_frame
	for _frame in range(600):
		var pending := false
		for spawner in get_nodes_in_group("population_spawner"):
			pending = pending or bool(spawner.needs_population_realization_resync())
		if not pending: break
		await process_frame
	_validate_dense_cluster_stays_live()
	# Vacancy/replacement behavior is exercised by validate_settlement_labor_authority.
	_validate_query_spatial_cache()
	_validate_query_performance_smoke()
	_validate_budgeted_controllers()
	await _validate_current_census_tick()
	await _validate_scalar_count_preserves_people()
	_scene.free()
	await process_frame
	if _failures.is_empty():
		print("TWO_TOWNS_LIVE_DENSITY_PERFORMANCE_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("TWO_TOWNS_LIVE_DENSITY_PERFORMANCE_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_dense_cluster_stays_live() -> void:
	var farmer_town := _scene.get_node_or_null("Settlements/FarmerCrossing")
	var raider_town := _scene.get_node_or_null("Settlements/RaiderCamp")
	if farmer_town == null or raider_town == null:
		_fail("Two-town density validation needs both settlements")
		return
	if str(farmer_town.get("actor_realization_policy")) != "full_town" or str(raider_town.get("actor_realization_policy")) != "full_town":
		_fail("Two close neighboring towns should remain full_town live clusters")
	var farmer_residents: Array = farmer_town.call("get_resident_characters") if farmer_town.has_method("get_resident_characters") else []
	var raider_residents: Array = raider_town.call("get_resident_characters") if raider_town.has_method("get_resident_characters") else []
	if farmer_residents.size() < 12:
		_fail("Farmer Crossing should bootstrap generated unassigned townies in the live cluster")
	if raider_residents.size() < 12:
		_fail("Raider Camp should bootstrap generated unassigned townies in the live cluster")
	_validate_bootstrap_state("farmer_crossing")
	_validate_bootstrap_state("raider_camp")
	for spawner in get_nodes_in_group("population_spawner"):
		if spawner != null and spawner.has_method("needs_population_realization_resync") and bool(spawner.call("needs_population_realization_resync")):
			_fail("Full-town population spawners should not require recurring realization resync")
			break


func _validate_bootstrap_state(settlement_id: String) -> void:
	var settlement := _get_controller("settlement_controller")
	var population := _get_controller("population_controller")
	if settlement == null or population == null:
		_fail("Dense-town census requires registered services")
		return
	var state: Dictionary = settlement.get_settlement_state(settlement_id)
	var alive: int = population.count_alive_records_for_settlement(settlement_id)
	if alive <= 0 or int(state.get("population", -1)) != alive:
		_fail("%s census must equal actual living permanent people; state=%s alive=%d" % [settlement_id, state.get("population"), alive])
	var assigned := 0
	for slot in (state.get("assignment_slots", {}) as Dictionary).values():
		if slot.get("assignment_domain") == "employment" and not str(slot.get("occupant_actor_id", "")).is_empty():
			assigned += maxi(0, int(slot.get("population_cost", 1)))
	if int(state.get("population_assigned", -1)) != assigned or int(state.get("population_available", -1)) != maxi(0, alive - assigned):
		_fail("%s census availability must count occupied employment, not residences twice" % settlement_id)


func _validate_query_spatial_cache() -> void:
	var query := _get_controller("actor_query_controller")
	if query == null:
		_fail("ActorQueryController missing for live density validation")
		return
	var nearby: Array = query.call("get_nearby_humanoids", Vector3.ZERO, 120.0, true)
	if nearby.size() < 20:
		_fail("Spatial nearby query should return the live two-town humanoid cluster; count=%d" % nearby.size())
	var summary: Dictionary = query.call("serialize_state") if query.has_method("serialize_state") else {}
	if int(summary.get("spatial_cell_count", 0)) <= 0:
		_fail("ActorQueryController should populate spatial cells for nearby queries")


func _validate_query_performance_smoke() -> void:
	var query := _get_controller("actor_query_controller")
	if query == null or not query.has_method("get_nearby_humanoids"):
		return
	var started_usec := Time.get_ticks_usec()
	for _index in range(100):
		query.call("get_nearby_humanoids", Vector3.ZERO, 120.0, true)
	var elapsed_usec := Time.get_ticks_usec() - started_usec
	print("DENSITY_QUERY_SMOKE queries=100 elapsed_usec=%d live_actors=%d (not FPS)" % [elapsed_usec, query.get_nearby_humanoids(Vector3.ZERO, 120.0, true).size()])
	if elapsed_usec > 250000:
		_fail("Spatial actor queries should stay within dense-town smoke budget; elapsed_usec=%d" % elapsed_usec)


func _validate_budgeted_controllers() -> void:
	var realization := _get_controller("population_realization_controller")
	if realization == null:
		_fail("PopulationRealizationController missing for live density validation")
	else:
		if int(realization.get("spawner_budget_per_tick")) <= 0 or int(realization.get("spawner_budget_per_tick")) > 16:
			_fail("Population realization should use a bounded spawner budget")
		if float(realization.get("realization_resync_interval_seconds")) <= 0.0:
			_fail("Population realization should be timer-driven instead of per-frame resync")


func _validate_current_census_tick() -> void:
	# Growth is intentionally a design TODO, not a fabricated +1/day simulation.
	var settlement := _get_controller("settlement_controller")
	var population := _get_controller("population_controller")
	var world_time := _scene.find_child("WorldTimeController", true, false)
	var before_ids := _record_ids(population.get_records_for_settlement("farmer_crossing"))
	world_time.advance_days(1.0)
	await process_frame
	var after_ids := _record_ids(population.get_records_for_settlement("farmer_crossing"))
	if before_ids != after_ids:
		_fail("Current daily census must not invent or delete permanent people while growth is unimplemented")
	if int(settlement.get_settlement_state("farmer_crossing").get("population", -1)) != int(population.count_alive_records_for_settlement("farmer_crossing")):
		_fail("Daily tick must reconcile the census to durable living records")


func _validate_scalar_count_preserves_people() -> void:
	var settlement := _get_controller("settlement_controller")
	var population := _get_controller("population_controller")
	var census := _get_controller("settlement_census")
	var before: Array = population.get_records_for_settlement("farmer_crossing")
	var before_ids := _record_ids(before)
	for requested_count in [before.size() + 5, 0]:
		settlement.set_population_total("farmer_crossing", requested_count, "validation_scalar_only")
		await process_frame
		if _record_ids(population.get_records_for_settlement("farmer_crossing")) != before_ids:
			_fail("Scalar population edits must not mint or delete permanent people")
	census.call("_reconcile_population", settlement, population, "farmer_crossing")
	if int(settlement.get_settlement_state("farmer_crossing").get("population", -1)) != int(population.count_alive_records_for_settlement("farmer_crossing")):
		_fail("Durable records must restore the scalar census after a count-only edit")


func _record_ids(records: Array) -> Array[String]:
	var result: Array[String] = []
	for record in records: result.append(str(record.get("actor_id", "")))
	result.sort()
	return result


func _get_controller(group_name: String) -> Node:
	var nodes := get_nodes_in_group(group_name)
	return nodes[0] as Node if not nodes.is_empty() else null


func _set_actor_realization_policy(path: NodePath, policy: String) -> void:
	var town := _scene.get_node_or_null(path)
	if town != null:
		town.set("actor_realization_policy", policy)


func _count_live_spawner_residents(spawner_path: NodePath) -> int:
	var spawner := _scene.get_node_or_null(spawner_path)
	if spawner == null:
		return 0
	var count := 0
	for child in spawner.get_children():
		if child.has_method("assign_attack_target"):
			count += 1
	return count


func _fail(message: String) -> void:
	_failures.append(message)


func _wait_frames(frame_count: int) -> void:
	for _index in range(frame_count):
		await process_frame
