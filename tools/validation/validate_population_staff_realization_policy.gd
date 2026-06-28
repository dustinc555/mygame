extends SceneTree

const TWO_TOWNS_SCENE_PATH := "res://scenes/test_levels/two_towns_road_test.tscn"
const AI_UTILITY_ADAPTER_PATH := "res://features/ai/bridge/ai_utility_adapter.gd"
const COMBAT_COORDINATOR_PATH := "res://features/combat/bridge/combat_coordinator.gd"
const SKIN_TEXTURE_BUILDER_PATH := "res://features/actors/projection/appearance/skin_texture_builder.gd"

var _failures: Array[String] = []
var _scene: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_scene = _instantiate_scene()
	if _scene == null:
		_fail("Two towns scene missing for staff realization validation")
		_finish()
		return
	var farmer_town := _scene.get_node_or_null("Settlements/FarmerCrossing")
	if farmer_town != null:
		farmer_town.set("actor_realization_policy", "important_plus_near")
	farmer_town = null
	root.add_child(_scene)
	await _wait_frames(180)
	_validate_staff_fills_under_non_full_policy()
	await _cleanup_scene()
	_finish()


func _instantiate_scene() -> Node:
	var scene_resource := load(TWO_TOWNS_SCENE_PATH) as PackedScene
	return scene_resource.instantiate() if scene_resource != null else null


func _finish() -> void:
	if _failures.is_empty():
		print("POPULATION_STAFF_REALIZATION_POLICY_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("POPULATION_STAFF_REALIZATION_POLICY_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_staff_fills_under_non_full_policy() -> void:
	var settlement_controller := _get_controller("settlement_controller")
	if settlement_controller == null or not settlement_controller.has_method("get_settlement_state"):
		_fail("SettlementController missing for staff realization validation")
		return
	var state: Dictionary = settlement_controller.call("get_settlement_state", "farmer_crossing")
	var required_staff := int(state.get("population_required_staff", 0))
	var assigned_staff := int(state.get("population_assigned", 0))
	var vacancies: Dictionary = state.get("staff_vacancies", {})
	if required_staff <= 0:
		_fail("Farmer Crossing should expose required staff slots")
	if assigned_staff < required_staff:
		_fail("Non-full realization policy should still realize enough residents to fill staff; required=%d assigned=%d" % [required_staff, assigned_staff])
	if not vacancies.is_empty():
		_fail("Staff vacancies should not deadlock under important_plus_near policy; vacancies=%d" % vacancies.size())
	var population := _get_controller("population_controller")
	if population == null or not population.has_method("get_records_for_settlement"):
		_fail("PopulationController missing for staff record validation")
		return
	var staff_record_count := 0
	for record in population.call("get_records_for_settlement", "farmer_crossing"):
		if not (record is Dictionary):
			continue
		if ["barkeeper", "waiter", "guard", "barber", "warden", "ruler"].has(str(record.get("role_id", ""))):
			staff_record_count += 1
	if staff_record_count < required_staff:
		_fail("Claimed staff should update generated population records to staff roles; records=%d required=%d" % [staff_record_count, required_staff])


func _get_controller(group_name: String) -> Node:
	var nodes := get_nodes_in_group(group_name)
	return nodes[0] as Node if not nodes.is_empty() else null


func _fail(message: String) -> void:
	_failures.append(message)


func _wait_frames(frame_count: int) -> void:
	for _index in range(frame_count):
		await process_frame


func _cleanup_scene() -> void:
	if _scene != null and is_instance_valid(_scene):
		root.remove_child(_scene)
		_scene.free()
	_scene = null
	await process_frame
	await physics_frame
	_cleanup_runtime_state()
	await _wait_frames(20)


func _cleanup_runtime_state() -> void:
	var combat_coordinator = load(COMBAT_COORDINATOR_PATH)
	if combat_coordinator != null and combat_coordinator.has_method("reset_all_state"):
		combat_coordinator.reset_all_state()
	var ai_utility_adapter = load(AI_UTILITY_ADAPTER_PATH)
	if ai_utility_adapter != null and ai_utility_adapter.has_method("clear_runtime_caches"):
		ai_utility_adapter.clear_runtime_caches()
	var skin_texture_builder = load(SKIN_TEXTURE_BUILDER_PATH)
	if skin_texture_builder != null and skin_texture_builder.has_method("clear_runtime_caches"):
		skin_texture_builder.clear_runtime_caches()
