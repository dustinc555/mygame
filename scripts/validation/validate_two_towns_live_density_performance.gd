extends SceneTree

const TWO_TOWNS_SCENE := preload("res://scenes/test_levels/two_towns_road_test.tscn")

var _failures: Array[String] = []
var _scene: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_scene = TWO_TOWNS_SCENE.instantiate()
	root.add_child(_scene)
	await _wait_frames(180)
	_validate_dense_cluster_stays_live()
	await _validate_root_town_guards_use_population()
	_validate_query_spatial_cache()
	_validate_query_performance_smoke()
	_validate_budgeted_controllers()
	await _validate_daily_growth_to_capacity()
	await _validate_soft_cap_and_population_shrink()
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
	if farmer_residents.size() < 2:
		_fail("Farmer Crossing should bootstrap generated unassigned townies in the live cluster")
	if raider_residents.size() < 2:
		_fail("Raider Camp should bootstrap generated unassigned townies in the live cluster")
	_validate_bootstrap_state("farmer_crossing", 16, 13, 11, 2)
	_validate_bootstrap_state("raider_camp", 6, 4, 2, 2)
	for spawner in get_nodes_in_group("population_spawner"):
		if spawner != null and spawner.has_method("needs_population_realization_resync") and bool(spawner.call("needs_population_realization_resync")):
			_fail("Full-town population spawners should not require recurring realization resync")
			break


func _validate_bootstrap_state(settlement_id: String, expected_max: int, expected_population: int, expected_assigned: int, expected_available: int) -> void:
	var settlement_controller := _get_controller("settlement_controller")
	if settlement_controller == null or not settlement_controller.has_method("get_settlement_state"):
		_fail("SettlementController missing for bootstrap state validation")
		return
	var state: Dictionary = settlement_controller.call("get_settlement_state", settlement_id)
	if int(state.get("max_occupancy", -1)) != expected_max:
		_fail("%s should derive max population from buildings; expected=%d actual=%d" % [settlement_id, expected_max, int(state.get("max_occupancy", -1))])
	if int(state.get("population_target", -1)) != expected_max:
		_fail("%s population target should equal building capacity" % settlement_id)
	if int(state.get("population", -1)) != expected_population:
		_fail("%s should bootstrap staff plus two unassigned townies; expected=%d actual=%d" % [settlement_id, expected_population, int(state.get("population", -1))])
	if int(state.get("population_assigned", -1)) != expected_assigned:
		_fail("%s assigned population mismatch; expected=%d actual=%d" % [settlement_id, expected_assigned, int(state.get("population_assigned", -1))])
	if int(state.get("population_available", -1)) != expected_available:
		_fail("%s should keep two unassigned bootstrap townies" % settlement_id)


func _validate_root_town_guards_use_population() -> void:
	var farmer_town := _scene.get_node_or_null("Settlements/FarmerCrossing")
	var world_time := _scene.get_node_or_null("GameBootstrap/WorldTimeController")
	var settlement_controller := _get_controller("settlement_controller")
	if farmer_town == null or world_time == null or settlement_controller == null:
		_fail("Root town guard validation needs FarmerCrossing, WorldTimeController, and SettlementController")
		return
	var initial_guard_count := _count_root_town_guards(farmer_town)
	farmer_town.set("guard_count", 1)
	await _wait_frames(4)
	if _count_root_town_guards(farmer_town) > initial_guard_count:
		_fail("Setting SettlementTown.guard_count should not direct-create root guard actors before population staffing runs")
		return
	world_time.call("advance_hours", 1.0)
	await _wait_frames(30)
	if _count_root_town_guards(farmer_town) != initial_guard_count + 1:
		_fail("Root town guards should be filled by claiming generated settlement population")
	var state: Dictionary = settlement_controller.call("get_settlement_state", "farmer_crossing")
	if int(state.get("population_assigned", 0)) < 12:
		_fail("Root town guard should count as assigned settlement population")


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
	if elapsed_usec > 250000:
		_fail("Spatial actor queries should stay within dense-town smoke budget; elapsed_usec=%d" % elapsed_usec)


func _validate_budgeted_controllers() -> void:
	var activity := _get_controller("settlement_activity_controller")
	if activity == null:
		_fail("SettlementActivityController missing for live density validation")
	else:
		if int(activity.get("resident_budget_per_tick")) <= 0 or int(activity.get("resident_budget_per_tick")) > 16:
			_fail("SettlementActivityController should use a small resident assignment budget for dense live towns")
		if float(activity.get("activity_point_cache_seconds")) <= 0.0:
			_fail("SettlementActivityController should cache activity point discovery")
	for town in get_nodes_in_group("settlement_town"):
		if town != null and float(town.get("guard_assignment_interval_seconds")) < 0.1:
			_fail("Settlement guard assignment should be throttled instead of per-frame")
			break


func _validate_daily_growth_to_capacity() -> void:
	var settlement_controller := _get_controller("settlement_controller")
	var world_time := _scene.get_node_or_null("GameBootstrap/WorldTimeController")
	if settlement_controller == null or world_time == null:
		_fail("Daily growth validation needs SettlementController and WorldTimeController")
		return
	var before: Dictionary = settlement_controller.call("get_settlement_state", "farmer_crossing")
	var before_population := int(before.get("population", 0))
	var target_population := int(before.get("population_target", before_population))
	world_time.call("advance_days", 1.0)
	await _wait_frames(8)
	var after: Dictionary = settlement_controller.call("get_settlement_state", "farmer_crossing")
	var expected_population: int = mini(target_population, before_population + 1)
	if int(after.get("population", 0)) != expected_population:
		_fail("Supplied towns should grow by one NPC per day until max capacity; expected=%d actual=%d" % [expected_population, int(after.get("population", 0))])


func _validate_soft_cap_and_population_shrink() -> void:
	var settlement_controller := _get_controller("settlement_controller")
	if settlement_controller == null or not settlement_controller.has_method("set_population_total"):
		_fail("Soft-cap validation needs SettlementController.set_population_total")
		return
	var before: Dictionary = settlement_controller.call("get_settlement_state", "farmer_crossing")
	var target := int(before.get("population_target", 0))
	var assigned := int(before.get("population_assigned", 0))
	var resident_records_before := _count_generated_records("farmer_crossing", "npc.farmer_crossing", "resident")
	settlement_controller.call("set_population_total", "farmer_crossing", target + 5, "validation_over_capacity")
	await _wait_frames(30)
	var over_state: Dictionary = settlement_controller.call("get_settlement_state", "farmer_crossing")
	if int(over_state.get("population", 0)) != target + 5:
		_fail("Building capacity should be a soft max; over-capacity population should not be clamped down")
	var resident_records_over := _count_generated_records("farmer_crossing", "npc.farmer_crossing", "resident")
	if resident_records_over > resident_records_before:
		_fail("Over-capacity towns should not auto-generate additional resident records; before=%d after=%d" % [resident_records_before, resident_records_over])
	settlement_controller.call("set_population_total", "farmer_crossing", assigned, "validation_population_drop")
	await _wait_frames(30)
	var resident_records_after_drop := _count_generated_records("farmer_crossing", "npc.farmer_crossing", "resident")
	if resident_records_after_drop != 0:
		_fail("Generated resident records should shrink when available population drops to zero; actual=%d" % resident_records_after_drop)
	var live_residents_after_drop := _count_live_spawner_residents("Settlements/FarmerCrossing/Residents")
	if live_residents_after_drop != 0:
		_fail("Generated live residents should be removed when available population drops to zero; actual=%d" % live_residents_after_drop)


func _get_controller(group_name: String) -> Node:
	var nodes := get_nodes_in_group(group_name)
	return nodes[0] as Node if not nodes.is_empty() else null


func _count_root_town_guards(town: Node) -> int:
	if town == null:
		return 0
	var guards: Array = town.call("get_guard_actors") if town.has_method("get_guard_actors") else []
	return guards.size()


func _count_generated_records(settlement_id: String, generation_source: String, role_id: String) -> int:
	var population := _get_controller("population_controller")
	if population == null or not population.has_method("get_records_for_settlement"):
		return 0
	var count := 0
	for record in population.call("get_records_for_settlement", settlement_id):
		if not (record is Dictionary):
			continue
		if str(record.get("generation_source", "")) == generation_source and str(record.get("role_id", "")) == role_id:
			count += 1
	return count


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
