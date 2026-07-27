extends SceneTree

const TWO_TOWNS_SCENE_PATH := "res://scenes/test_levels/two_towns_road_test.tscn"
const SETTLEMENT_JAIL_SCENE_PATH := "res://features/settlements/bridge/settlement_jail.tscn"
const JAIL_CELL_SCENE_PATH := "res://features/world/projection/props/furniture/jail_cell.tscn"
const PRISONER_LOCKER_SCENE_PATH := "res://features/world/projection/containers/prisoner_locker_container.tscn"
const SETTLEMENT_GUARD_POST_SCRIPT_PATH := "res://features/settlements/bridge/venues/settlement_guard_post.gd"
const BANDAGE := preload("res://features/inventory/resources/items/bandage.tres")
const HATCHET := preload("res://features/inventory/resources/items/hatchet.tres")

var _failures: Array[String] = []
var _scene: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_scene = (load(TWO_TOWNS_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_scene)
	await _wait_frames(160)
	_validate_population_role_ledger()
	await _validate_delayed_town_guard_replacement()
	await _validate_private_bar_guard()
	await _validate_jail_authoring()
	if _failures.is_empty():
		print("SETTLEMENT_LABOR_AUTHORITY_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SETTLEMENT_LABOR_AUTHORITY_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_population_role_ledger() -> void:
	var controller := _get_settlement_controller()
	if controller == null:
		_fail("SettlementController should exist in bootstrapped town scene")
		return
	var state: Dictionary = controller.call("get_settlement_state", "farmer_crossing")
	if not state.has("assignment_slots") or not state.has("assignment_vacancies"):
		_fail("Settlement state should expose assignment slots and vacancies")
		return
	var expected_available: int = max(0, int(state.get("population", 0)) - _employment_assignment_count(state))
	if int(controller.call("get_available_population", "farmer_crossing")) != expected_available:
		_fail("Available population should equal total population minus occupied employment slots")


func _validate_delayed_town_guard_replacement() -> void:
	var controller: Node = _get_settlement_controller()
	var population: Node = _get_population_controller()
	if controller == null or population == null:
		_fail("Could not find settlement or population controller for guard replacement validation")
		return
	controller.call("_sync_settlement_assignment_slots", "farmer_crossing")
	controller.call("bootstrap_assignments", "farmer_crossing")
	await _wait_frames(8)
	var before: Dictionary = controller.call("get_settlement_state", "farmer_crossing")
	var guard_slot := _find_occupied_assignment_slot(before, "guard", "settlement_authority")
	var guard_actor_id := str(guard_slot.get("occupant_actor_id", ""))
	var guard_record: Dictionary = population.call("get_actor_record", guard_actor_id)
	if guard_record.is_empty():
		_fail("Settlement-authority guard assignment should have a permanent population occupant")
		return
	controller.call("derealize_assignment_slot", "farmer_crossing", str(guard_slot.get("assignment_domain", "employment")), str(guard_slot.get("slot_id", "")))
	population.call("mark_record_dead", guard_actor_id)
	controller.call("_sync_settlement_assignment_slots", "farmer_crossing")
	var after_death: Dictionary = controller.call("get_settlement_state", "farmer_crossing")
	var assignment_key := "%s:%s" % [str(guard_slot.get("assignment_domain", "employment")), str(guard_slot.get("slot_id", ""))]
	if not (after_death.get("assignment_vacancies", {}) as Dictionary).has(assignment_key):
		_fail("Dead town guard should create an assignment vacancy")
	var vacated_slot: Dictionary = (after_death.get("assignment_slots", {}) as Dictionary).get(assignment_key, {})
	if not str(vacated_slot.get("occupant_actor_id", "")).is_empty():
		_fail("Dead town guard assignment should be vacant until its replacement delay elapses")
	var vacancies: Dictionary = (after_death.get("assignment_vacancies", {}) as Dictionary).duplicate(true)
	var due_vacancy: Dictionary = (vacancies.get(assignment_key, {}) as Dictionary).duplicate(true)
	if int(due_vacancy.get("replacement_due_minute", 0)) <= int(due_vacancy.get("vacant_since_minute", 0)):
		_fail("Dead staff vacancy should honor its authored replacement delay")
	due_vacancy["replacement_due_minute"] = 0
	vacancies[assignment_key] = due_vacancy
	var due_state: Dictionary = controller.settlement_states["farmer_crossing"]
	due_state["assignment_vacancies"] = vacancies
	controller.settlement_states["farmer_crossing"] = due_state
	controller.call("bootstrap_assignments", "farmer_crossing")
	await _wait_frames(12)
	var replaced_state: Dictionary = controller.call("get_settlement_state", "farmer_crossing")
	var replacement_slot: Dictionary = (replaced_state.get("assignment_slots", {}) as Dictionary).get(assignment_key, {})
	if not str(replacement_slot.get("occupant_actor_id", "")).is_empty():
		_fail("Due guard vacancy should remain open without an unassigned civilian")
	if not (replaced_state.get("assignment_vacancies", {}) as Dictionary).has(assignment_key):
		_fail("Unfilled guard vacancy should remain durable after its replacement delay")
	if int(controller.call("get_available_population", "farmer_crossing")) != 0:
		_fail("Dead staff should not count as available settlement population")


func _validate_private_bar_guard() -> void:
	var controller := _get_settlement_controller()
	var population := _get_population_controller()
	if controller == null or population == null:
		_fail("Private bar guard validation needs settlement and population controllers")
		return
	var state: Dictionary = controller.call("get_settlement_state", "farmer_crossing")
	var guard_slot := _find_occupied_assignment_slot(state, "guard", "private_security")
	var guard_record: Dictionary = population.call("get_actor_record", str(guard_slot.get("occupant_actor_id", "")))
	if guard_record.is_empty():
		_fail("Bar guard role slot should have a permanent population occupant")
	elif str(guard_record.get("role_id", "")) != "guard":
		_fail("Private-security assignment should persist the guard role")
	elif str((guard_record.get("equipment_slots", {}) as Dictionary).get(ItemDefinition.EQUIP_SLOT_WEAPON, "")) != HATCHET.resource_path:
		_fail("Bar guard record should equip a hatchet")
	elif _record_item_count(guard_record, BANDAGE.resource_path) != 1:
		_fail("Bar guard record should carry one bandage")


func _validate_jail_authoring() -> void:
	var jail := (load(SETTLEMENT_JAIL_SCENE_PATH) as PackedScene).instantiate()
	var furniture := Node3D.new()
	furniture.name = "Furniture"
	jail.add_child(furniture)
	var cell := (load(JAIL_CELL_SCENE_PATH) as PackedScene).instantiate()
	cell.name = "AuthoredCell"
	furniture.add_child(cell)
	var locker := (load(PRISONER_LOCKER_SCENE_PATH) as PackedScene).instantiate()
	locker.name = "AuthoredLocker"
	locker.set("container_id", "validation.jail.prisoner_locker")
	furniture.add_child(locker)
	var guard_post := Node3D.new()
	guard_post.name = "AuthoredGuardPost"
	guard_post.set_script(load(SETTLEMENT_GUARD_POST_SCRIPT_PATH))
	furniture.add_child(guard_post)
	root.add_child(jail)
	await _wait_frames(4)
	var slot_specs: Array = jail.call("get_assignment_slot_specs")
	if not _has_role_slot(slot_specs, "warden", "settlement_authority"):
		_fail("Settlement jail should author a settlement-authority warden role slot")
	if not _has_role_slot(slot_specs, "guard", "settlement_authority"):
		_fail("Settlement jail should author a settlement-authority guard role slot")
	if jail.get_node_or_null("GuardPosts") != null or jail.get_node_or_null("Cells") != null:
		_fail("Settlement jail should not create designated furniture roots")
	if not jail.has_method("get_guard_posts") or not jail.call("get_guard_posts").has(guard_post):
		_fail("Settlement jail should discover authored guard-post furniture")
	if not jail.has_method("get_cells") or not jail.call("get_cells").has(cell):
		_fail("Settlement jail should discover authored cell furniture")
	if not jail.has_method("get_prisoner_locker") or jail.call("get_prisoner_locker") != locker:
		_fail("Settlement jail should discover authored prisoner-locker furniture")
	var record: Dictionary = jail.call("get_facility_record", "test_settlement")
	if str(record.get("function_id", "")) != "jail":
		_fail("Jail facility record should report jail function_id")
	if int(record.get("prisoner_capacity", 0)) != 1:
		_fail("Jail facility record should report authored single-cell capacity")
	jail.queue_free()


func _get_settlement_controller() -> Node:
	return root.find_child("SettlementController", true, false)


func _get_population_controller() -> Node:
	return root.find_child("PopulationController", true, false)


func _employment_assignment_count(state: Dictionary) -> int:
	var count := 0
	for slot_value in (state.get("assignment_slots", {}) as Dictionary).values():
		var slot: Dictionary = slot_value
		if str(slot.get("assignment_domain", "")) == "employment" and not str(slot.get("occupant_actor_id", "")).is_empty():
			count += max(0, int(slot.get("population_cost", 1)))
	return count


func _find_occupied_assignment_slot(state: Dictionary, role_id: String, authority_scope: String) -> Dictionary:
	for slot_value in (state.get("assignment_slots", {}) as Dictionary).values():
		var slot: Dictionary = slot_value
		if str(slot.get("role_id", "")) == role_id and str(slot.get("authority_scope", "")) == authority_scope and not str(slot.get("occupant_actor_id", "")).is_empty():
			return slot
	return {}


func _has_role_slot(slot_specs: Array, role_id: String, authority_scope: String) -> bool:
	for slot_value in slot_specs:
		var slot: Dictionary = slot_value
		if str(slot.get("role_id", "")) == role_id and str(slot.get("authority_scope", "")) == authority_scope:
			return true
	return false


func _record_item_count(record: Dictionary, item_path: String) -> int:
	var count := 0
	for entry_value in record.get("inventory_entries", []) as Array:
		var entry: Dictionary = entry_value
		if str(entry.get("item_id", "")) == item_path:
			count += int(entry.get("count", 0))
	return count


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _fail(message: String) -> void:
	_failures.append(message)
