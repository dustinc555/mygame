extends SceneTree

const TWO_TOWNS_SCENE := preload("res://scenes/test_levels/two_towns_road_test.tscn")
const SETTLEMENT_BAR_SCENE := preload("res://features/settlements/bridge/settlement_bar.tscn")
const SETTLEMENT_JAIL_SCENE := preload("res://features/settlements/bridge/settlement_jail.tscn")
const JAIL_CELL_SCENE := preload("res://features/world/projection/props/furniture/jail_cell.tscn")
const PRISONER_LOCKER_SCENE := preload("res://features/world/projection/containers/prisoner_locker_container.tscn")
const SETTLEMENT_GUARD_POST_SCRIPT := preload("res://features/settlements/bridge/venues/settlement_guard_post.gd")
const BANDAGE := preload("res://features/inventory/resources/items/bandage.tres")
const HATCHET := preload("res://features/inventory/resources/items/hatchet.tres")

var _failures: Array[String] = []
var _scene: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_scene = TWO_TOWNS_SCENE.instantiate()
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
	if not state.has("population_available") or not state.has("population_assigned"):
		_fail("Settlement state should expose available and assigned population")
		return
	var expected_available: int = max(0, int(state.get("population", 0)) - int(state.get("population_assigned", 0)))
	if int(state.get("population_available", -1)) != expected_available:
		_fail("Available population should equal total population minus assigned staff")


func _validate_delayed_town_guard_replacement() -> void:
	var controller: Node = _get_settlement_controller()
	var world_time: Node = _get_world_time_controller()
	var town: Node = _scene.get_node_or_null("Settlements/FarmerCrossing")
	if controller == null or world_time == null or town == null:
		_fail("Could not find controller, world time, or FarmerCrossing for guard replacement validation")
		return
	town.set("guard_count", 1)
	if town.has_method("_repair_guard_authoring_tree"):
		town.call("_repair_guard_authoring_tree")
	await _wait_frames(4)
	controller.call("_sync_settlement_staff_slots", "farmer_crossing")
	controller.call("bootstrap_staff_vacancies", "farmer_crossing")
	await _wait_frames(8)
	controller.call("_sync_settlement_staff_slots", "farmer_crossing")
	var guard := town.get_node_or_null("Guards/Guard") as HumanoidCharacter
	if guard == null:
		_fail("Town guard role should claim a generated resident as a guard actor")
		return
	var before: Dictionary = controller.call("get_settlement_state", "farmer_crossing")
	if not guard.has_method("is_settlement_authority") or not bool(guard.call("is_settlement_authority")):
		_fail("Town guard should be settlement authority")
	guard.set("life_state", NpcRules.LifeState.DEAD)
	controller.call("_sync_settlement_staff_slots", "farmer_crossing")
	var after_death: Dictionary = controller.call("get_settlement_state", "farmer_crossing")
	if int(after_death.get("population", 0)) != int(before.get("population", 0)) - 1:
		_fail("Killing a staffed town guard should reduce total settlement population once")
	if (after_death.get("staff_vacancies", {}) as Dictionary).is_empty():
		_fail("Dead town guard should create a staff vacancy")
	if town.get_node_or_null("Guards/Guard2") != null:
		_fail("Dead town guard should not be instantly replaced")
	world_time.call("advance_days", 8.0)
	await _wait_frames(12)
	var guards: Array = town.call("get_guard_actors")
	if guards.is_empty():
		_fail("Delayed guard vacancy should refill after enough world time when population is available")


func _validate_private_bar_guard() -> void:
	var bar := SETTLEMENT_BAR_SCENE.instantiate()
	root.add_child(bar)
	bar.set("guard_count", 1)
	if bar.has_method("_repair_authoring_tree"):
		bar.call("_repair_authoring_tree")
	await _wait_frames(4)
	var guard := bar.get_node_or_null("Staff/Guard") as HumanoidCharacter
	if guard == null:
		_fail("Reusable bar should generate a private guard")
	elif guard.has_method("is_settlement_authority") and bool(guard.call("is_settlement_authority")):
		_fail("Bar guard should not be settlement authority")
	elif not guard.has_method("is_private_security") or not bool(guard.call("is_private_security")):
		_fail("Bar guard should be tagged private security")
	elif guard.get_equipped_item(ItemDefinition.EQUIP_SLOT_WEAPON) != HATCHET:
		_fail("Bar guard should spawn with a hatchet")
	elif guard.inventory == null or guard.inventory.count_item(BANDAGE) != 1:
		_fail("Bar guard should carry one bandage")
	bar.queue_free()


func _validate_jail_authoring() -> void:
	var jail := SETTLEMENT_JAIL_SCENE.instantiate()
	var furniture := Node3D.new()
	furniture.name = "Furniture"
	jail.add_child(furniture)
	var cell := JAIL_CELL_SCENE.instantiate()
	cell.name = "AuthoredCell"
	furniture.add_child(cell)
	var locker := PRISONER_LOCKER_SCENE.instantiate()
	locker.name = "AuthoredLocker"
	furniture.add_child(locker)
	var guard_post := Node3D.new()
	guard_post.name = "AuthoredGuardPost"
	guard_post.set_script(SETTLEMENT_GUARD_POST_SCRIPT)
	furniture.add_child(guard_post)
	root.add_child(jail)
	await _wait_frames(4)
	if jail.get_node_or_null("Staff/Warden") == null:
		_fail("Settlement jail should create a warden")
	if jail.get_node_or_null("Staff/Guard") == null:
		_fail("Settlement jail should create guards")
	if jail.get_node_or_null("GuardPosts") != null or jail.get_node_or_null("Cells") != null:
		_fail("Settlement jail should not create designated furniture roots")
	if not jail.has_method("get_guard_posts") or not jail.call("get_guard_posts").has(guard_post):
		_fail("Settlement jail should discover authored guard-post furniture")
	if not jail.has_method("get_cells") or not jail.call("get_cells").has(cell):
		_fail("Settlement jail should discover authored cell furniture")
	if not jail.has_method("get_prisoner_locker") or jail.call("get_prisoner_locker") != locker:
		_fail("Settlement jail should discover authored prisoner-locker furniture")
	var warden := jail.get_node_or_null("Staff/Warden") as HumanoidCharacter
	if warden == null or not warden.has_method("is_settlement_authority") or not bool(warden.call("is_settlement_authority")):
		_fail("Jail warden should be settlement authority")
	var record: Dictionary = jail.call("get_facility_record", "test_settlement")
	if str(record.get("function_id", "")) != "jail":
		_fail("Jail facility record should report jail function_id")
	if int(record.get("prisoner_capacity", 0)) != 1:
		_fail("Jail facility record should report authored single-cell capacity")
	jail.queue_free()


func _get_settlement_controller() -> Node:
	return root.find_child("SettlementController", true, false)


func _get_world_time_controller() -> Node:
	return root.find_child("WorldTimeController", true, false)


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _fail(message: String) -> void:
	_failures.append(message)
