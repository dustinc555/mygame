extends "res://tests/validation/test_case.gd"

## Generic facility contracts use a fixed world, not a mutable town or hall layout.
## The service job remains a real integration witness for Jobs/GECS lifecycle;
## this does not promise navigation through any particular authored building.
const FIXTURE_SCENE_PATH := "res://tests/validation/fixtures/bar_authoring/world.tscn"
const FIXTURE_BAR_PATH := "res://tests/validation/fixtures/bar_authoring/bar.tscn"
const SETTLEMENT_BAR_SCENE_PATH := "res://features/settlements/bridge/settlement_bar.tscn"
const STOOL_SCENE_PATH := "res://features/world/projection/props/furniture/chair_1.tscn"
const BREAD_ITEM_PATH := "res://features/inventory/resources/items/bread.tres"
const FOOD_ITEM_PATH := "res://features/inventory/resources/items/food.tres"
const FACTION_HUMANOID_SCRIPT_PATH := "res://features/actors/projection/humanoid/faction_humanoid.gd"
const BARBER_CONVERSATION_PATH := "res://features/conversation/resources/barber_services.tres"
const CHARACTER_JOBS_WINDOW_SCRIPT_PATH := "res://features/ui/projection/character_jobs_window.gd"
const ROLE_RESOURCE_PATHS := {
	"barkeeper": "res://features/settlements/resources/roles/barkeeper.tres",
	"waiter": "res://features/settlements/resources/roles/waiter.tres",
	"guard": "res://features/settlements/resources/roles/guard.tres",
	"barber": "res://features/settlements/resources/roles/barber.tres",
}

var FIXTURE_SCENE: PackedScene
var SETTLEMENT_BAR_SCENE: PackedScene
var STOOL_SCENE: PackedScene
var BREAD_ITEM: Resource
var FOOD_ITEM: Resource
var FACTION_HUMANOID_SCRIPT: Script
var BARBER_CONVERSATION: Resource
var CHARACTER_JOBS_WINDOW_SCRIPT: Script
var ROLE_RESOURCES: Dictionary = {}

var _failures: Array[String] = []
var _scene: Node
var _named_staff_before: Dictionary = {}
var _validation_visitor_serial := 0
var _stock_fixture_seeded := false


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	_load_validation_resources()
	_scene = FIXTURE_SCENE.instantiate()
	root.add_child(_scene)
	current_scene = _scene
	if not await _wait_for_world_ready():
		await _cleanup_scene()
		_cleanup_validation_resources()
		quit(1)
		return
	_validate_base_bar_scene_staff_authoring()
	await _validate_operator_instantiated_bar()
	await _cleanup_scene()
	_cleanup_validation_resources()
	if _failures.is_empty():
		print("REUSABLE_BAR_AUTHORING_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("REUSABLE_BAR_AUTHORING_FAILED count=%d" % _failures.size())
	quit(1)


func _load_validation_resources() -> void:
	FIXTURE_SCENE = load(FIXTURE_SCENE_PATH) as PackedScene
	SETTLEMENT_BAR_SCENE = load(SETTLEMENT_BAR_SCENE_PATH) as PackedScene
	STOOL_SCENE = load(STOOL_SCENE_PATH) as PackedScene
	BREAD_ITEM = load(BREAD_ITEM_PATH) as Resource
	FOOD_ITEM = load(FOOD_ITEM_PATH) as Resource
	FACTION_HUMANOID_SCRIPT = load(FACTION_HUMANOID_SCRIPT_PATH) as Script
	BARBER_CONVERSATION = load(BARBER_CONVERSATION_PATH) as Resource
	CHARACTER_JOBS_WINDOW_SCRIPT = load(CHARACTER_JOBS_WINDOW_SCRIPT_PATH) as Script
	for role_id in ROLE_RESOURCE_PATHS:
		ROLE_RESOURCES[role_id] = load(ROLE_RESOURCE_PATHS[role_id]) as FacilityRoleDefinition


func _cleanup_scene() -> void:
	if _scene != null and is_instance_valid(_scene):
		root.remove_child(_scene)
		_scene.free()
		_scene = null
		await _wait_frames(8)


func _cleanup_validation_resources() -> void:
	FIXTURE_SCENE = null
	SETTLEMENT_BAR_SCENE = null
	STOOL_SCENE = null
	BREAD_ITEM = null
	FOOD_ITEM = null
	FACTION_HUMANOID_SCRIPT = null
	BARBER_CONVERSATION = null
	CHARACTER_JOBS_WINDOW_SCRIPT = null
	ROLE_RESOURCES.clear()


func _wait_for_world_ready() -> bool:
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var clock := BootstrapContext.service(WorldTimeController.SERVICE_ID) as WorldTimeController
		var navigation := BootstrapContext.service(WorldNavigationController.SERVICE_ID) as WorldNavigationController
		var settlement := BootstrapContext.service(SettlementController.SERVICE_ID) as SettlementController
		if clock == null or navigation == null or settlement == null:
			continue
		if clock.is_world_paused() or navigation.is_initial_navigation_pending() or not navigation.is_idle():
			continue
		if settlement.get_settlement_state("bar_authoring").is_empty():
			continue
		return true
	_fail("Controlled world must finish real bootstrap, navigation and loading pause before assertions")
	return false


func _validate_base_bar_scene_staff_authoring() -> void:
	var bar := SETTLEMENT_BAR_SCENE.instantiate()
	var staff_root := bar.get_node_or_null("Staff")
	if staff_root == null:
		_fail("Base reusable bar scene should keep a Staff root")
	else:
		for child in staff_root.get_children():
			if child is HumanoidCharacter:
				_fail("Base reusable bar scene should not ship authored staff actors")
	if bar.get_node_or_null("Storage") != null or bar.get_node_or_null("JobProviders") != null:
		_fail("Base reusable bar scene should not ship unused Storage or JobProviders roots")
	if bar.get_node_or_null("ServicePoints") != null:
		_fail("Base reusable bar scene should not ship a redundant barkeeper ServicePoints root")
	var service_area := bar.get_node_or_null("BarServiceArea") as BarServiceArea
	if service_area == null:
		_fail("Base reusable bar scene should contain BarServiceArea")
	else:
		if service_area.get_barkeeper_service_point() != null:
			_fail("Base reusable bar scene should not resolve a counter before furnishing")
		var counter := ShopCounter.new()
		bar.get_node("Furniture").add_child(counter)
		if service_area.get_barkeeper_service_point() != null:
			_fail("BarServiceArea should cache a missing barkeeper counter")
		service_area.refresh_scope()
		if service_area.get_barkeeper_service_point() != counter:
			_fail("BarServiceArea refresh should resolve newly furnished counter")
	bar.free()


func _validate_operator_instantiated_bar() -> void:
	var bars := _scene.get_node_or_null("Town/Bars")
	var townies := _create_named_staff_fixture("bar_authoring")
	var assigned_waiter := townies[0] if townies.size() > 0 else null
	var assigned_guard := townies[1] if townies.size() > 1 else null
	if bars == null or assigned_waiter == null or assigned_guard == null:
		_fail("Could not find bar container or generated townies for reusable bar validation")
		return
	var bar := _instantiate_controlled_bar()
	bar.name = "OperatorBar"
	for named_actor in [assigned_waiter, assigned_guard]:
		_named_staff_before[str(named_actor.stable_id)] = str(named_actor.member_name)
	bar.set("role_slots", _bar_role_slots(assigned_waiter, assigned_guard))
	var furniture := bar.get_node("Furniture")
	var furnishings := furniture.get_children()
	for node in furnishings:
		node.owner = null
		furniture.remove_child(node)
	bars.add_child(bar)
	bar.set("display_name", "Operator Test Bar")
	bar.set("visitor_capacity", 4)
	var inferred_id := str(bar.call("get_facility_id"))
	if inferred_id.is_empty():
		_fail("Parented operator bar must infer a durable facility identity before furnishing")
	bar.set("facility_id", inferred_id)
	_furnish_validation_bar(bar, furnishings)
	if bar.has_method("_repair_authoring_tree"):
		bar.call("_repair_authoring_tree")
	if not _sync_and_realize_bar_assignments(bar):
		return
	await _wait_frames(20)
	await _wait_for_furnished_navigation()
	_validate_inferred_defaults(bar)
	_validate_staff(bar, assigned_waiter, assigned_guard)
	_validate_role_points(bar)
	# Exercise the real approach before visitor-capacity checks deliberately
	# leave two stationary test visitors on the same chair exit point.
	await _validate_barber_seating(bar)
	_validate_furniture_authoring(bar)
	_validate_bar_visit_capacity(bar, assigned_waiter, assigned_guard)
	_validate_player_waiter_order_action(bar)
	_validate_seated_talk_range(bar)
	_validate_barkeeper_stock(bar)
	_validate_waiter_order_job(bar, assigned_waiter, assigned_guard)
	await _validate_party_contract_lifecycle(bar)
	await _validate_standalone_bar_stock()
	_validate_scene_authored_layout_source(bar)
	_validate_layout_migration(bar)
	_validate_service_area(bar, assigned_waiter, assigned_guard)
	await _validate_staff_combat_response(bar)
	_validate_furnishing_identity_and_stock(bar)


func _wait_for_furnished_navigation() -> void:
	var navigation := BootstrapContext.service(WorldNavigationController.SERVICE_ID) as WorldNavigationController
	if navigation == null:
		_fail("Runtime furnished bar requires the real world navigation controller")
		return
	navigation.notify_world_geometry_changed()
	await process_frame
	var deadline := Time.get_ticks_msec() + 30000
	while not navigation.is_idle() and Time.get_ticks_msec() < deadline:
		await process_frame
	if not navigation.is_idle():
		_fail("Authored furnishing navigation must finish its real rebuild before seating checks")
	await physics_frame
	await physics_frame


func _instantiate_controlled_bar(include_furniture := true) -> Node3D:
	var bar := (load(FIXTURE_BAR_PATH) as PackedScene).instantiate() as Node3D
	# The reusable prefab is still checked separately. Its replaceable building
	# shell is not a requirement of Jobs, stock or population authoring.
	var shell := bar.get_node("BuildingSlot/CurrentBuilding")
	shell.get_parent().remove_child(shell)
	shell.free()
	if not include_furniture:
		for child in bar.get_node("Furniture").get_children():
			child.free()
	return bar


func _furnish_validation_bar(bar: Node, furnishings: Array[Node]) -> void:
	# Use the same pre-mount ID stamping as editor furnishing. Layout is authored
	# in the fixture, not solved from a changing hall. Solver coverage lives in
	# validate_facility_furnish; this checks mounted stock/seat/provider consumers.
	var furniture := bar.get_node("Furniture") as Node3D
	var authoring = load("res://addons/world_authoring/facility_tools.gd").new(null)
	for node in furnishings:
		authoring._stamp_furniture_ids(node, bar)
		_prepare_controlled_furnishing_subjects(node)
		furniture.add_child(node)
	authoring.teardown()
	bar.get_node("BarServiceArea").call("refresh_scope")


# Deterministic subject data only; identity still comes from production authoring.
func _prepare_controlled_furnishing_subjects(node: Node) -> void:
	if node is WorldContainer and not _stock_fixture_seeded:
		var bread := InventoryStock.new()
		bread.item_definition = BREAD_ITEM
		bread.quantity = 2
		var fixture_stock: Array[InventoryStock] = [bread]
		node.set("starting_items", fixture_stock)
		_stock_fixture_seeded = true
	if node is TabletopItemSpawner:
		for slot in node.get_children():
			if slot is TabletopItemSlot and not slot.stock_projection:
				slot.spawn_chance = 1.0
	for child in node.get_children():
		_prepare_controlled_furnishing_subjects(child)


func _validate_furnishing_identity_and_stock(bar: Node) -> void:
	var stock := BootstrapContext.service(InventoryStockController.SERVICE_ID) as InventoryStockController
	var lifecycle := BootstrapContext.service(ItemLifecycleController.SERVICE_ID) as ItemLifecycleController
	if stock == null or lifecycle == null:
		_fail("Furnished bar needs actual stock and item-lifecycle services")
		return
	var facility_id := str(bar.get("facility_id"))
	var registered := {}
	for record in stock.get_settlement_container_snapshot("bar_authoring"):
		if str(record.get("facility_id", "")) == facility_id:
			registered[str(record.get("container_id", ""))] = true
	var container_ids := {}
	var surface_ids := {}
	var durable_surface_count := 0
	var pending: Array[Node] = [bar.get_node("Furniture")]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is WorldContainer:
			var container_id := str(node.get("container_id"))
			if container_id.is_empty() or container_ids.has(container_id) or not registered.has(container_id):
				_fail("Generated container must have a unique ID registered to actual facility stock: %s" % container_id)
			container_ids[container_id] = true
		if node is TabletopItemSpawner:
			var surface_id := str(node.call("_get_surface_id"))
			if surface_id.is_empty() or surface_ids.has(surface_id):
				_fail("Generated tabletop must have a unique facility-qualified host ID")
			surface_ids[surface_id] = true
			var durable_slots := 0
			for slot in node.get_children():
				if slot is TabletopItemSlot and not slot.stock_projection and (slot.required_item != null or not slot.optional_items.is_empty()):
					durable_slots += 1
			if durable_slots > 0:
				durable_surface_count += 1
				if lifecycle.get_stack_records_for_host(surface_id).is_empty():
					_fail("Guaranteed tabletop slots must create durable stacks: host=%s resolved=%s node=%s slots=%d" % [surface_id, str(node.get("_resolved_surface_id")), str(node.get_path()), durable_slots])
		for child in node.get_children():
			pending.append(child)
	if container_ids.is_empty() or surface_ids.is_empty() or durable_surface_count == 0 or not _stock_fixture_seeded:
		_fail("Furnishing stock coverage requires real containers and nonempty durable tabletop subjects")
	var before: Dictionary = stock.get_facility_stock_snapshot(facility_id)
	var before_units := 0.0
	for value in (before.get("food_units", {}) as Dictionary).values():
		before_units += float(value)
	var consumed: Dictionary = stock.consume_food_units("bar_authoring", 0.1, facility_id)
	var after: Dictionary = stock.get_facility_stock_snapshot(facility_id)
	var after_units := 0.0
	for value in (after.get("food_units", {}) as Dictionary).values():
		after_units += float(value)
	if (consumed.get("items", {}) as Dictionary).is_empty() or float(consumed.get("food_units", 0.0)) <= 0.0:
		_fail("Authored furnished containers must supply real town stock consumption")
	elif not is_equal_approx(before_units - after_units, float(consumed.food_units)):
		_fail("Facility aggregate must debit exactly the food units consumed from its physical containers")


func _validate_inferred_defaults(bar: Node) -> void:
	if str(bar.call("get_facility_id")) != "bar_authoring.operator_bar":
		_fail("Reusable bar should infer facility_id from settlement id and node name")
	if str(bar.call("_get_staff_id_prefix")) != "npc.bar_authoring.operator_bar":
		_fail("Reusable bar should infer staff_stable_id_prefix from facility_id")
	if str(bar.call("_get_bar_squad_name")) != "bar_authoring.operator_bar":
		_fail("Reusable bar should infer staff_squad_name from the facility")
	if str(bar.call("_get_effective_owner_faction_id")) != "Farmers":
		_fail("Reusable bar should infer owner_faction_id from the parent settlement")


func _validate_staff(bar: Node, assigned_waiter: HumanoidCharacter, assigned_guard: HumanoidCharacter) -> void:
	var barkeeper := _role_actor(bar, "barkeeper")
	var waiters := _role_actors(bar, "waiter")
	var guards := _role_actors(bar, "guard")
	var barber := _role_actor(bar, "barber")
	if barkeeper == null:
		_fail("Reusable bar should realize its barkeeper assignment")
	if waiters.size() != 2 or not waiters.has(assigned_waiter):
		_fail("Reusable bar should realize one named and one Auto waiter assignment")
	if guards.size() != 2 or not guards.has(assigned_guard):
		_fail("Reusable bar should realize one named and one Auto guard assignment")
	if barber == null:
		_fail("Reusable bar should realize its barber assignment")
	var named_waiter_slot := _assignment_slot_for_actor(bar, str(assigned_waiter.get("stable_id")))
	var named_guard_slot := _assignment_slot_for_actor(bar, str(assigned_guard.get("stable_id")))
	if str(named_waiter_slot.get("preferred_actor_id", "")) != str(assigned_waiter.get("stable_id")):
		_fail("Named waiter row should bind its CharacterRecordDefinition actor")
	if str(named_guard_slot.get("preferred_actor_id", "")) != str(assigned_guard.get("stable_id")):
		_fail("Named guard row should bind its CharacterRecordDefinition actor")
	var population := get_first_node_in_group("population_controller")
	for slot in _assignment_slots(bar):
		if not str(slot.get("preferred_actor_id", "")).is_empty() or population == null:
			continue
		var record: Dictionary = population.call("get_actor_record", str(slot.get("occupant_actor_id", "")))
		if str(record.get("generation_source", "")) != "assignment_auto":
			_fail("Auto role row should use an assignment_auto population record: %s" % str(slot.get("slot_id", "")))
	for actor in [assigned_waiter, assigned_guard]:
		var actor_id := str(actor.get("stable_id"))
		if not _named_staff_before.has(actor_id) or _named_staff_before[actor_id] != str(actor.get("member_name")):
			_fail("Staff assignment must preserve the existing permanent actor ID and name")
	var staff: Array[HumanoidCharacter] = [barkeeper, barber]
	staff.append_array(waiters)
	staff.append_array(guards)
	for actor in staff:
		if actor == null:
			continue
		if actor.faction_name != "Farmers":
			_fail("Generated bar staff should inherit the bar owner faction")
		if actor.appearance_data == null:
			_fail("Generated bar staff should use the settlement/faction appearance generator")
		var actor_id := str(actor.get("stable_id"))
		var assignment := _assignment_slot_for_actor(bar, actor_id)
		var role := str(assignment.get("role_id", ""))
		if actor_id.is_empty() or not ROLE_RESOURCE_PATHS.has(role):
			_fail("Bar staff must bind a durable actor ID and declared role, not derive either from display name")
		var record: Dictionary = population.call("get_actor_record", actor_id)
		if record.is_empty() or str(record.get("member_name", "")) != str(actor.get("member_name")):
			_fail("Staff display name must reflect its permanent population record")
		if str(actor.get("squad_name")) != "bar_authoring.operator_bar":
			_fail("Generated bar staff should infer the facility squad name")
		if str(assignment.get("preferred_actor_id", "")).is_empty():
			_validate_staff_perception(actor, role)
	if barber != null:
		if barber.get("conversation_definition") != BARBER_CONVERSATION:
			_fail("Generated barber should expose barber services")
		var appearance_service = load("res://features/actors/projection/appearance/character_appearance_controller.gd").new()
		if not barber.has_meta("barber_service_price") or int(appearance_service.call("_get_barber_price", barber)) != int(barber.get_meta("barber_service_price")):
			_fail("Barber role pricing metadata must be consumed by the real appearance service")
		appearance_service.free()


func _validate_staff_combat_response(bar: Node) -> void:
	var barkeeper := _role_actor(bar, "barkeeper")
	if barkeeper == null:
		return
	var attacker := CharacterBody3D.new()
	attacker.name = "ValidationBarAttacker"
	attacker.set_script(FACTION_HUMANOID_SCRIPT)
	attacker.set("member_name", "Validation Attacker")
	attacker.set("stable_id", "validation.bar_attacker")
	attacker.set("faction_name", "ValidationRaiders")
	attacker.set("squad_name", "ValidationRaiders")
	bar.add_child(attacker)
	var gecs := _get_gecs_world()
	if gecs == null:
		_fail("Combat response fixture requires the real GECS world")
		attacker.queue_free()
		return
	gecs.call("register_actor", attacker, "bar_authoring", {"role_id": "resident"})
	if gecs.call("get_actor_entity", attacker) == null:
		_fail("Combat response attacker must be a registered simulation actor")
	attacker.global_position = barkeeper.global_position + Vector3(1.0, 0.0, 0.0)
	await _wait_frames(4)
	var response_system := _scene.find_child("GameCombatResponseSystem", true, false)
	if response_system == null:
		_fail("Bar staff response needs the real combat response system")
		attacker.queue_free()
		return
	response_system.emit_attack_started(str(attacker.stable_id), str(barkeeper.stable_id), barkeeper.global_position, 0)
	await _wait_frames(12)
	var responders: Array[HumanoidCharacter] = [barkeeper]
	responders.append_array(_role_actors(bar, "waiter"))
	responders.append_array(_role_actors(bar, "guard"))
	var barber := _role_actor(bar, "barber")
	if barber != null:
		responders.append(barber)
	var guard_ids: Array[String] = []
	for responder in responders:
		if responder == null:
			_fail("Bar response-policy validation requires every configured staff actor")
			continue
		var role := str(responder.get_meta("settlement_staff_role", ""))
		var expected_stance := NpcRules.combat_stance_for_role(role)
		if role.is_empty() or responder.combat_stance != expected_stance:
			_fail("Bar staff role stance must use its canonical role, not an indexed display name: actor=%s role=%s expected=%d actual=%d" % [str(responder.name), role, expected_stance, int(responder.combat_stance)])
		if responder.is_private_security() != (role == "guard"):
			_fail("Only authored bar guards should have private-security authority")
		if responder.is_in_group(WorldActor.SETTLEMENT_AUTHORITY_GROUP) or responder.is_in_group(WorldActor.FACTION_SOLDIER_GROUP):
			_fail("Bar staff must not silently become settlement authorities or faction soldiers")
		if role == "guard":
			guard_ids.append(str(responder.stable_id))
	if guard_ids.is_empty():
		_fail("Bar response fixture requires a real private guard")
	var encounter: Dictionary = {}
	for candidate in response_system.get_active_encounters():
		if str(candidate.get("root_aggressor_actor_id", "")) == str(attacker.stable_id) and str(candidate.get("root_defender_actor_id", "")) == str(barkeeper.stable_id):
			encounter = candidate
			break
	if encounter.is_empty():
		_fail("A real attack on the configured barkeeper must produce a live response encounter")
	else:
		var defenders = encounter.get("defender_side_actor_ids", [])
		if not defenders.has(str(barkeeper.stable_id)):
			_fail("Barkeeper must remain the protected encounter participant")
		for guard_id in guard_ids:
			if not defenders.has(guard_id):
				_fail("The bar's authored private guard must join its worker's defense: %s" % guard_id)
	attacker.queue_free()


func _validate_role_points(bar: Node) -> void:
	if bar.get_node_or_null("ServicePoints") != null:
		_fail("Reusable bar should use its ShopCounter instead of a barkeeper ServicePoints root")
	if _generated_role_node_count(bar.get_node_or_null("WaiterPoints"), "waiter") != 2:
		_fail("Reusable bar should derive two waiter points from waiter role slots")
	if _generated_role_node_count(bar.get_node_or_null("GuardPosts"), "guard") != 3:
		_fail("Reusable bar should preserve three authored guard posts while two guard role slots are assigned")
	if bar.get_node_or_null("WaiterPoints/BarberPoint") != null:
		_fail("Barber should be a normal idle bar occupant, not a generated service point")
	var visit_point := bar.get_node_or_null("ActivityPoints/FacilityVisitPoint")
	if visit_point == null:
		_fail("Reusable bar should create one generic facility visit point that scans Furniture seats")
	elif not visit_point.has_method("assign_actor"):
		_fail("Facility visit point should assign bar visitors through seat discovery")
	else:
		if bool(visit_point.get("exclusive")):
			_fail("Facility visit point should not be a per-chair exclusive visitor point")
		var target_path = visit_point.get("target_path")
		if typeof(target_path) == TYPE_NODE_PATH and not target_path.is_empty():
			_fail("Facility visit point should scan seats instead of targeting one hardwired chair")
		var seats_root_path = visit_point.get("visit_seats_root_path")
		if typeof(seats_root_path) != TYPE_NODE_PATH or seats_root_path.is_empty():
			_fail("Facility visit point should scan the reusable bar Furniture root")
	var activity_points := bar.get_node_or_null("ActivityPoints")
	if activity_points != null:
		for point in activity_points.get_children():
			if str(point.name).begins_with("VisitorPoint"):
				_fail("Reusable bar should not generate per-chair VisitorPoint nodes")
	for path in ["WaiterPoints/WaiterPoint", "GuardPosts/GuardPost", "ActivityPoints/FacilityVisitPoint"]:
		var node := bar.get_node_or_null(path)
		if node == null:
			continue
		if not bool(node.get_meta("facility_generated", false)):
			_fail("Generated bar layout node %s should carry migration metadata" % path)


func _validate_staff_perception(actor: HumanoidCharacter, role: String) -> void:
	if actor == null:
		return
	var perception := actor.get_skill_level(SkillRules.ATTRIBUTE_PERCEPTION)
	var population := BootstrapContext.service(PopulationController.SERVICE_ID) as PopulationController
	var record: Dictionary = population.get_actor_record(str(actor.stable_id))
	var levels: Dictionary = record.get("skill_levels", {})
	if not levels.has(SkillRules.ATTRIBUTE_PERCEPTION) or perception != int(levels[SkillRules.ATTRIBUTE_PERCEPTION]):
		_fail("Generated %s perception must match its permanent character-type-backed skill record" % role)


func _validate_furniture_authoring(bar: Node) -> void:
	var furniture := bar.get_node_or_null("Furniture")
	if furniture == null:
		_fail("Reusable bar should include one Furniture root")
		return
	for legacy_root in ["Tables", "Stools", "Beds"]:
		if furniture.get_node_or_null(legacy_root) != null:
			_fail("Reusable bar base scene should keep furniture directly under Furniture, not Furniture/%s" % legacy_root)
	var service: Node = bar.get_node("BarServiceArea")
	var furnished_seats: Array = service.call("_collect_seat_nodes")
	if furnished_seats.size() < int(bar.get("visitor_capacity")):
		_fail("Controlled furnished bar must have actual seats for every visitor")
	if service.call("get_barkeeper_service_point") == null:
		_fail("Controlled furnished bar must discover its generated counter")
	for stale_name in ["TableA2", "StoolABack2", "StoolABack3"]:
		if furniture.get_node_or_null(stale_name) != null:
			_fail("Reusable bar should not keep stale migrated furniture node Furniture/%s" % stale_name)
	for furniture_node in furniture.get_children():
		var furniture_name := str(furniture_node.name)
		if furniture_name.contains("FromTables") or furniture_name.contains("FromStools"):
			_fail("Reusable bar should not keep editor-migrated furniture suffix on Furniture/%s" % furniture_name)
		for child in furniture_node.get_children():
			if str(child.name).begins_with("_") and (child is MeshInstance3D or child is CollisionShape3D):
				_fail("Reusable bar furniture %s should not keep duplicate generated child %s" % [str(furniture_node.name), str(child.name)])
	var service_area := bar.get_node_or_null("BarServiceArea")
	if service_area == null:
		return
	if str(service_area.get("seats_root_path")) != "../Furniture" or str(service_area.get("beds_root_path")) != "../Furniture":
		_fail("BarServiceArea should scan the single Furniture root for seats and beds")
	var direct_seat := STOOL_SCENE.instantiate()
	direct_seat.name = "CopiedValidationSeat"
	furniture.add_child(direct_seat)
	var bar_node := bar as Node3D
	if bar_node != null:
		direct_seat.global_position = bar_node.global_position + Vector3(-30.0, 0.0, -30.0)
	var legacy_root := Node3D.new()
	legacy_root.name = "Stools"
	furniture.add_child(legacy_root)
	var legacy_seat := STOOL_SCENE.instantiate()
	legacy_seat.name = "LegacyValidationSeat"
	legacy_root.add_child(legacy_seat)
	var seats: Array = service_area.call("_collect_seat_nodes")
	if not seats.has(direct_seat):
		_fail("BarServiceArea should discover copied direct Furniture seats")
	if not seats.has(legacy_seat):
		_fail("BarServiceArea should keep discovering seats in old nested furniture folders")
	var visit_point := bar.get_node_or_null("ActivityPoints/FacilityVisitPoint") as Node3D
	var visitors := _collect_townie_visitors(bar, [])
	_ensure_validation_townie_visitors(bar, [], visitors, 2)
	var visitor_actor := visitors[0] if visitors.size() > 0 else null
	var rejected_actor := visitors[1] if visitors.size() > 1 else null
	if visitor_actor != null and visit_point != null:
		visitor_actor.get_interaction().stop_seat_assignment()
		var old_revisit_cooldown := float(visit_point.get("revisit_cooldown_seconds"))
		visit_point.set("revisit_cooldown_seconds", 0.0)
		var old_visit_transform := visit_point.global_transform
		visit_point.global_position = direct_seat.global_position
		if not bool(visit_point.call("assign_actor", visitor_actor)):
			_fail("Facility visit point should assign visitors by scanning open Furniture seats")
		elif direct_seat.has_method("get_sitter") and direct_seat.call("get_sitter") != visitor_actor:
			_fail("Facility visit point should use the copied direct Furniture seat without a per-chair VisitorPoint")
		visit_point.call("release_actor", visitor_actor)
		visit_point.global_transform = old_visit_transform
		var empty_furniture := Node3D.new()
		empty_furniture.name = "EmptyValidationFurniture"
		bar.add_child(empty_furniture)
		var old_furniture_root = bar.get("furniture_root_path")
		var old_visit_seats_root_path = visit_point.get("visit_seats_root_path")
		bar.set("furniture_root_path", NodePath("EmptyValidationFurniture"))
		visit_point.set("visit_seats_root_path", visit_point.get_path_to(empty_furniture))
		if rejected_actor != null and visit_point != null:
			rejected_actor.get_interaction().stop_seat_assignment()
			var old_position := rejected_actor.global_position
			if bool(visit_point.call("assign_actor", rejected_actor)):
				_fail("Facility visit point should reject visitors when no Furniture chair is open")
			if rejected_actor.global_position.distance_to(old_position) > 0.01:
				_fail("Rejected bar visitor should not be moved to a fallback marker")
		bar.set("furniture_root_path", old_furniture_root)
		visit_point.set("visit_seats_root_path", old_visit_seats_root_path)
		visit_point.set("revisit_cooldown_seconds", old_revisit_cooldown)
		empty_furniture.queue_free()
	# Later checks discover furniture immediately, before deferred frees run.
	furniture.remove_child(direct_seat)
	furniture.remove_child(legacy_root)
	direct_seat.queue_free()
	legacy_root.queue_free()


func _validate_bar_visit_capacity(bar: Node, assigned_waiter: HumanoidCharacter, assigned_guard: HumanoidCharacter) -> void:
	var visit_point := bar.get_node_or_null("ActivityPoints/FacilityVisitPoint")
	if visit_point == null:
		_fail("Reusable bar should have a facility visit point for visitor capacity validation")
		return
	if assigned_waiter != null and bool(visit_point.call("is_available_for", assigned_waiter)):
		_fail("Assigned waiter should not count as a normal townie bar visitor")
	if assigned_guard != null and bool(visit_point.call("is_available_for", assigned_guard)):
		_fail("Assigned guard should not count as a normal townie bar visitor")
	var party_member := _scene.get_node_or_null("PartyMembers/Worker") as HumanoidCharacter
	if party_member != null and bool(visit_point.call("is_available_for", party_member)):
		_fail("Party members should not count as normal townie bar visitors")
	var visitors := _collect_townie_visitors(bar, [assigned_waiter, assigned_guard])
	_ensure_validation_townie_visitors(bar, [assigned_waiter, assigned_guard], visitors, 2)
	if visitors.size() < 2:
		_fail("Reusable bar visitor capacity validation needs at least two normal townies")
		return
	var original_capacity := int(bar.get("visitor_capacity"))
	bar.set("visitor_capacity", 1)
	if bar.has_method("_repair_authoring_tree"):
		bar.call("_repair_authoring_tree")
	visit_point = bar.get_node_or_null("ActivityPoints/FacilityVisitPoint")
	var first: HumanoidCharacter = visitors[0]
	var second: HumanoidCharacter = visitors[1]
	for visitor in [first, second]:
		visitor.get_interaction().stop_seat_assignment()
	if not bool(visit_point.call("assign_actor", first)):
		_fail("First normal townie should be able to visit an empty bar")
	var first_seat := _seat_for_sitter(bar, first)
	if int(visit_point.call("get_active_visitor_count")) != 1:
		_fail("Facility visit point should track exactly visitor_capacity active townie visitors")
	var second_position := second.global_position
	if bool(visit_point.call("is_available_for", second)):
		_fail("Facility visit point should be unavailable to extra townies once visitor_capacity is full")
	if bool(visit_point.call("assign_actor", second)):
		_fail("Facility visit point should reject extra townies instead of mosh-pitting at the marker")
	if second.global_position.distance_to(second_position) > 0.01:
		_fail("Rejected townie should not be moved toward the full bar")
	var first_physics_anchor := first.global_position
	visit_point.call("release_actor", first)
	if first.is_sitting():
		_fail("Released bar visitor should stand up and free the chair")
	if first_seat != null:
		if first_seat.call("get_sitter") == first or not first.global_position.is_equal_approx(first_physics_anchor):
			_fail("Released bar visitor must free the chair without teleporting off its validated physics anchor")
	if bool(visit_point.call("is_available_for", first)):
		_fail("Released bar visitor should have a short cooldown before returning")
	if not bool(visit_point.call("is_available_for", second)) or not bool(visit_point.call("assign_actor", second)):
		_fail("A different townie should be able to take the freed bar visitor slot")
	visit_point.call("release_actor", second)
	bar.set("visitor_capacity", original_capacity)
	if bar.has_method("_repair_authoring_tree"):
		bar.call("_repair_authoring_tree")


func _validate_barber_seating(bar: Node) -> void:
	var barber := _role_actor(bar, "barber")
	if barber == null:
		return
	barber.get_interaction().stop_seat_assignment()
	var seat := bar.call("_barber_seat_for_actor", barber) as Node3D
	if seat == null:
		_fail("Assigned barber should find an existing bar chair")
		return
	bar.call("_send_barber_to_seat", barber)
	# Routine duty must physically reach the chair; only initial placement may snap.
	for _frame in range(900):
		if not is_instance_valid(barber) or not is_instance_valid(seat):
			_fail("Barber and chair must stay realized during the seating journey actor_valid=%s seat_valid=%s frame=%d" % [is_instance_valid(barber), is_instance_valid(seat), _frame])
			return
		if barber.is_sitting():
			break
		await physics_frame
	print("BARBER_SEATING_TRACE seated=%s target=%s seat=%s position=%s grant=%s" % [barber.is_sitting(), barber.get_current_seat_target(), seat, barber.global_position, barber.get_meta(&"active_facility_duty", "")])
	if not barber.is_sitting():
		print("BARBER_MOVE_TRACE stand=%s move=%s has_move=%s order=%s velocity=%s" % [barber.get_interaction().current_seat_stand_position, barber.get_move_target(), barber.has_move_target(), barber.get_interaction().current_order_type, barber.velocity])
		for collision_index in barber.get_slide_collision_count():
			print("BARBER_COLLISION_TRACE collider=%s" % barber.get_slide_collision(collision_index).get_collider())
		var actors := BootstrapContext.service(&"actor_query")
		if actors != null:
			for nearby in actors.get_nearby_actors(barber.global_position, 3.0):
				print("BARBER_NEIGHBOR_TRACE actor=%s position=%s seated=%s" % [nearby.stable_id, nearby.global_position, nearby.is_sitting()])
	if not barber.is_sitting():
		_fail("Barber should sit in a normal bar chair instead of standing at a guard/service marker")
	if seat.has_method("get_sitter") and seat.call("get_sitter") != barber:
		_fail("Barber's chosen chair should be occupied by the barber")
	var body := barber.get_body_projection() as Node3D
	# The normal sitting entry blends the body after the physical arrival.
	for _frame in range(180):
		if body == null or body.global_position.distance_to(seat.call("get_seat_position", barber)) <= 0.05:
			break
		await physics_frame
	if body == null or body.global_position.distance_to(seat.call("get_seat_position", barber)) > 0.05:
		_fail("Barber visual body should occupy the selected chair, not teleport its physics root")
	var approach = barber.get_interaction().current_seat_stand_position
	if not (approach is Vector3) or not barber.global_position.is_equal_approx(approach):
		_fail("Barber physics root must remain at the real reachable chair approach")
	if not str(seat.get_path()).contains("/Furniture/"):
		_fail("Barber should use an existing Furniture chair")
	barber.get_interaction().stop_seat_assignment()


func _validate_seated_talk_range(bar: Node) -> void:
	var talker := _role_actor(bar, "guard")
	var barber := _role_actor(bar, "barber")
	var furniture := bar.get_node_or_null("Furniture") as Node3D
	var bar_node := bar as Node3D
	if talker == null or barber == null or furniture == null or bar_node == null:
		_fail("Seated talk range validation could not find a talker, barber, furniture root, or bar node")
		return
	var talker_seat := STOOL_SCENE.instantiate() as Node3D
	var barber_seat := STOOL_SCENE.instantiate() as Node3D
	talker_seat.name = "SeatedTalkValidationSeat"
	barber_seat.name = "SeatedTalkBarberSeat"
	furniture.add_child(talker_seat)
	furniture.add_child(barber_seat)
	var normal_range := float(talker.get("interact_distance"))
	var target_distance := normal_range * 1.5
	talker_seat.global_position = bar_node.global_position + Vector3(0.0, 0.0, 0.0)
	barber_seat.global_position = talker_seat.global_position + Vector3(target_distance, 0.0, 0.0)
	talker.get_interaction().stop_conversation_interaction()
	barber.get_interaction().stop_conversation_interaction()
	talker.get_interaction().stop_seat_assignment()
	barber.get_interaction().stop_seat_assignment()
	var talker_interaction = talker.get_interaction()
	var barber_interaction = barber.get_interaction()
	if talker_interaction == null or not talker_interaction.sit_at_seat_immediately(talker_seat):
		_fail("Seated talk validation talker should be able to claim a chair")
	elif barber_interaction == null or not barber_interaction.sit_at_seat_immediately(barber_seat):
		_fail("Seated talk validation barber should be able to claim a chair")
	else:
		barber.global_position = talker.global_position + Vector3(target_distance, 0.0, 0.0)
		talker.get_interaction().assign_conversation_target(barber, true)
		talker.get_interaction().process_conversation_interaction()
		if not talker.is_sitting():
			_fail("Player-issued seated talk should not stand up when target is within doubled seated range")
		if talker.get_interaction().current_conversation_target != null:
			_fail("Player-issued seated talk should start when target is beyond normal range but within seated range")
		talker.get_interaction().stop_seat_assignment()
		talker.global_position = barber.global_position + Vector3(target_distance, 0.0, 0.0)
		talker.get_interaction().assign_conversation_target(barber, true)
		talker.get_interaction().process_conversation_interaction()
		if talker.get_interaction().current_conversation_target == null:
			_fail("Standing talker should not get doubled range just because the target is sitting")
	talker.get_interaction().stop_conversation_interaction()
	barber.get_interaction().stop_conversation_interaction()
	talker.get_interaction().stop_seat_assignment()
	barber.get_interaction().stop_seat_assignment()
	talker.get_interaction()._clear_actor_move_target()
	barber.get_interaction()._clear_actor_move_target()
	talker_seat.queue_free()
	barber_seat.queue_free()


func _validate_barkeeper_stock(bar: Node) -> void:
	var barkeeper := _role_actor(bar, "barkeeper")
	if barkeeper == null:
		return
	var role := barkeeper.get_node_or_null("MerchantRole")
	if role == null:
		_fail("Bar barkeeper should have a MerchantRole")
		return
	var stock_ratio := float(bar.call("_get_effective_stock_ratio"))
	var expected_bread := int(round(float(bar.get("max_bread_stock")) * stock_ratio))
	var bread_stock := _merchant_initial_stock_quantity(role, BREAD_ITEM)
	if bread_stock != expected_bread:
		_fail("Bar barkeeper bread stock should scale from parent settlement supply; expected=%d actual=%d ratio=%.2f" % [expected_bread, bread_stock, stock_ratio])
	if _merchant_initial_stock_quantity(role, FOOD_ITEM) <= 0:
		_fail("Bar barkeeper should keep generic food in default stock")
	var inventory = role.call("get_shop_inventory") if role.has_method("get_shop_inventory") else null
	if inventory == null or int(inventory.call("count_item", BREAD_ITEM)) <= 0:
		_fail("Bar barkeeper inventory should include bread after stock seeding")
	var custom_stock = role.get("initial_stock")
	for stock in custom_stock:
		if stock != null and stock.get("item_definition") == BREAD_ITEM:
			stock.set("quantity", 99)
			break
	role.set("initial_stock", custom_stock)
	bar.call("_repair_authoring_tree")
	if _merchant_initial_stock_quantity(role, BREAD_ITEM) != 99:
		_fail("Bar stock repair should preserve custom merchant stock quantities")


func _validate_waiter_order_job(bar: Node, worker: HumanoidCharacter, pacing_customer: HumanoidCharacter) -> void:
	if worker == null:
		return
	var service_area := bar.get_node_or_null("BarServiceArea")
	var barkeeper := _role_actor(bar, "barkeeper")
	var provider := barkeeper.get_node_or_null("JobProvider") if barkeeper != null else null
	var customer := _role_actor(bar, "guard")
	var seats: Array = []
	if service_area != null:
		seats = service_area.call("_collect_seat_nodes")
	if service_area == null or provider == null or customer == null or seats.size() < 2:
		_fail("Waiter order validation could not find service area, provider, customer, or two seats")
		return
	# Probability transactions need only their explicitly seated subjects, not
	# whichever staff member a preceding authoring repair happened to seat.
	for seat in seats:
		var sitter = seat.call("get_sitter")
		if is_instance_valid(sitter):
			sitter.get_interaction().stop_seat_assignment()
	var server_job_index := _server_shift_job_index(provider)
	if server_job_index < 0:
		_fail("Bar job provider should expose a server_shift job")
		return
	var jobs: Array = provider.get("jobs")
	var job = jobs[server_job_index]
	job.set("server_tip_on_success", 1)
	job.set("server_charisma_xp_scale", 0.5)
	_validate_waiter_job_offer_text(provider, server_job_index)
	worker.set_skill_level(SkillRules.ATTRIBUTE_CHARISMA, 1)
	# End prior order scenarios before starting independent probability cases.
	provider.call("pause_worker_job", worker, false)
	var assignment: Dictionary = provider.call("_assign_worker_to_open_slot", worker, server_job_index)
	if not bool(assignment.get("allowed", false)):
		_fail("Waiter should be able to take the server_shift job for order validation: %s" % str(assignment.get("reason", "")))
		return
	var original_service_delay := float(service_area.get("waiter_service_delay_seconds"))
	var original_repeat_cooldown := float(service_area.get("waiter_customer_repeat_cooldown_seconds"))
	# Independent probability transactions; repeat cooldown is covered separately.
	service_area.set("waiter_customer_repeat_cooldown_seconds", 0.0)
	var original_prompt_interval := float(service_area.get("waiter_order_prompt_interval_seconds"))
	var original_prompt_jitter := float(service_area.get("waiter_order_prompt_jitter_seconds"))
	service_area.set("waiter_service_delay_seconds", 999.0)
	service_area.set("waiter_order_prompt_interval_seconds", 0.0)
	service_area.set("waiter_order_prompt_jitter_seconds", 0.0)
	var record: Dictionary = provider.call("_get_worker_record", worker)
	var base_owed_before := int(record.get("owed_currency", 0))
	var pay_interval := maxf(float(job.get("pay_interval_seconds")), 0.01)
	provider.call("process_jobs", pay_interval, pay_interval)
	record = provider.call("_get_worker_record", worker)
	if int(record.get("owed_currency", 0)) - base_owed_before < int(job.get("pay_per_interval")):
		_fail("Server shift should accrue base wages while holding the floor")
	service_area.set("waiter_service_delay_seconds", 0.0)
	service_area.set("waiter_order_prompt_interval_seconds", 60.0)
	service_area.set("waiter_order_prompt_jitter_seconds", 0.0)
	var first_seat = seats[0]
	var second_seat = seats[1]
	if pacing_customer == null:
		pacing_customer = _role_actor(bar, "barber")
	if not _seat_actor_for_waiter_validation(customer, first_seat) or not _seat_actor_for_waiter_validation(pacing_customer, second_seat):
		_fail("Waiter order pacing validation customers should be seated before service")
	else:
		_configure_waiter_check(job, 0.0)
		var before_fail_xp := float(worker.get_stats().get_skill_xp(SkillRules.ATTRIBUTE_CHARISMA))
		var before_fail_owed := int(record.get("owed_currency", 0))
		var served_seat := _complete_waiter_order(provider, service_area, worker, pay_interval + 0.1)
		record = provider.call("_get_worker_record", worker)
		var fail_xp_delta := float(worker.get_stats().get_skill_xp(SkillRules.ATTRIBUTE_CHARISMA)) - before_fail_xp
		var expected_fail_xp := SkillRules.get_chance_check_xp(0.0, false, float(job.get("server_charisma_xp_scale")))
		if expected_fail_xp <= 0.0 or absf(fail_xp_delta - expected_fail_xp) > 0.01:
			_fail("Failed very-low waiter Charisma checks should award half-scale chance XP, got %.2f" % fail_xp_delta)
		if int(record.get("owed_currency", 0)) != before_fail_owed:
			_fail("Failed waiter Charisma checks should not add a tip")
		var chained_claim = service_area.call("claim_waiting_customer_seat", worker)
		if chained_claim != null:
			_fail("Completed waiter orders should start a prompt cooldown instead of chaining immediately to another ready customer")
			service_area.call("release_waiter_customer_service", chained_claim)
		if served_seat == null or not bool(served_seat.call("is_waiting_customer_for_service", 0.0, false, true)):
			_fail("Served seated customers should be able to become ready again without leaving the chair")
	customer.get_interaction().stop_seat_assignment()
	if pacing_customer != null:
		pacing_customer.get_interaction().stop_seat_assignment()
	service_area.set("waiter_order_prompt_interval_seconds", 0.0)
	service_area.set("waiter_order_prompt_jitter_seconds", 0.0)
	if not _seat_actor_for_waiter_validation(customer, second_seat):
		_fail("Waiter order validation customer should be seated before service")
		provider.call("pause_worker_job", worker, false)
		_restore_waiter_validation_service_config(service_area, original_service_delay, original_prompt_interval, original_prompt_jitter, original_repeat_cooldown)
		return
	_configure_waiter_check(job, 1.0)
	var before_success_xp := float(worker.get_stats().get_skill_xp(SkillRules.ATTRIBUTE_CHARISMA))
	var before_success_owed := int(record.get("owed_currency", 0))
	var successful_seat := _complete_waiter_order(provider, service_area, worker, pay_interval + 3.0)
	if successful_seat != second_seat:
		_fail("Success transaction must serve the controlled customer, not an unrelated table")
	record = provider.call("_get_worker_record", worker)
	var success_xp_delta := float(worker.get_stats().get_skill_xp(SkillRules.ATTRIBUTE_CHARISMA)) - before_success_xp
	var expected_success_xp := SkillRules.get_chance_check_xp(1.0, true, float(job.get("server_charisma_xp_scale")))
	if expected_success_xp <= 0.0 or absf(success_xp_delta - expected_success_xp) > 0.01:
		_fail("Very-high waiter Charisma checks should award tiny half-scale chance XP, got %.2f" % success_xp_delta)
	if int(record.get("owed_currency", 0)) - before_success_owed != 1:
		_fail("Successful waiter Charisma checks should add the configured tip only")
	provider.call("pause_worker_job", worker, false)
	customer.get_interaction().stop_seat_assignment()
	_restore_waiter_validation_service_config(service_area, original_service_delay, original_prompt_interval, original_prompt_jitter, original_repeat_cooldown)


func _create_service_customer() -> HumanoidCharacter:
	var population := BootstrapContext.service(PopulationController.SERVICE_ID) as PopulationController
	var settlement := BootstrapContext.service(SettlementController.SERVICE_ID) as SettlementController
	var census := BootstrapContext.service(SettlementCensus.SERVICE_ID) as SettlementCensus
	var realizer := BootstrapContext.service(PopulationCharacterRealizer.SERVICE_ID) as PopulationCharacterRealizer
	var town := _scene.get_node("Town")
	var context: Dictionary = census._generation_context(settlement.get_settlement_definition("bar_authoring"), 371)
	context["role_id"] = "resident"
	var record := population.ensure_authored_record("bar_authoring", "validation.bar_customer", 1, context, {
		"member_name": "Validation Bar Customer", "role_id": "resident", "available_for_work": false,
	})
	return realizer.realize_actor(str(record.actor_id), town, town, "ValidationBarCustomer") as HumanoidCharacter


func _validate_party_contract_lifecycle(bar: Node) -> void:
	# A working town guard resumes its post and is not a stable service customer.
	var customer := _create_service_customer()
	var service_area := bar.get_node_or_null("BarServiceArea")
	var barkeeper := _role_actor(bar, "barkeeper")
	var provider := barkeeper.get_node_or_null("JobProvider") if barkeeper != null else null
	var player := _scene.get_node_or_null("PartyMembers/Worker") as HumanoidCharacter
	var bridge := _get_gecs_world()
	var seats: Array = []
	if service_area != null:
		seats = service_area.call("_collect_seat_nodes")
	var server_job_index := _server_shift_job_index(provider) if provider != null else -1
	var guard_job_index := _job_index_for_algorithm(provider, "guard_post") if provider != null else -1
	if service_area == null or provider == null or player == null or customer == null or bridge == null or seats.is_empty() or server_job_index < 0 or guard_job_index < 0:
		_fail("Player waiter job validation could not find service area, provider, bridge, player, customer, seat, server job, or guard job")
		return
	var ranked_jobs := BootstrapContext.service(JobSystemController.SERVICE_ID) as JobSystemController
	if ranked_jobs == null:
		_fail("Player waiter fixture requires the ranked-job controller")
		return
	var previous_jobs_enabled := ranked_jobs.is_actor_jobs_enabled(player)
	var original_service_delay := float(service_area.get("waiter_service_delay_seconds"))
	var original_prompt_interval := float(service_area.get("waiter_order_prompt_interval_seconds"))
	var original_prompt_jitter := float(service_area.get("waiter_order_prompt_jitter_seconds"))
	service_area.set("waiter_service_delay_seconds", 999.0)
	service_area.set("waiter_order_prompt_interval_seconds", 0.0)
	service_area.set("waiter_order_prompt_jitter_seconds", 0.0)
	player.get_interaction().stop_seat_assignment()
	# Rejoin the live scheduler clock after the previous explicit wage ticks.
	provider.call("set_sim_time", float(ranked_jobs.get("_sim_time")))
	if not _accept_job_offer(provider, player, server_job_index):
		_fail("Player party worker should be able to accept a durable server_shift contract")
		ranked_jobs.set_actor_jobs_enabled(player, previous_jobs_enabled)
		_restore_waiter_validation_service_config(service_area, original_service_delay, original_prompt_interval, original_prompt_jitter)
		return
	if not _accept_job_offer(provider, player, guard_job_index):
		_fail("Player party worker should be able to accept a durable guard contract alongside waiter")
		ranked_jobs.set_actor_jobs_enabled(player, previous_jobs_enabled)
		_restore_waiter_validation_service_config(service_area, original_service_delay, original_prompt_interval, original_prompt_jitter)
		return
	var waiter_contract := _contract_for_job(bridge.call("get_actor_job_contracts", player), "bar_server")
	var guard_contract := _contract_for_job(bridge.call("get_actor_job_contracts", player), "bar_guard")
	if waiter_contract.is_empty() or guard_contract.is_empty():
		_fail("Accepted waiter and guard jobs should both appear as the party worker job contracts")
		ranked_jobs.set_actor_jobs_enabled(player, previous_jobs_enabled)
		_restore_waiter_validation_service_config(service_area, original_service_delay, original_prompt_interval, original_prompt_jitter)
		return
	_rank_contract_first(ranked_jobs, player, waiter_contract)
	var jobs: Array = provider.get("jobs")
	var server_job = jobs[server_job_index]
	var pay_interval := maxf(float(server_job.get("pay_interval_seconds")), 0.01)
	ranked_jobs.set_actor_jobs_enabled(player, false)
	player.global_position = service_area.global_position
	player.stop_movement()
	# Let real spatial state catch up before asking Utility AI for work facts.
	await _wait_frames(2)
	if not ranked_jobs.set_actor_jobs_enabled(player, true):
		_fail("Player waiter fixture must explicitly enable its accepted ranked jobs")
		return
	var record: Dictionary = provider.call("_get_worker_record", player)
	var owed_before_passive := int(record.get("owed_currency", 0))
	provider.call("process_contracts", pay_interval, pay_interval)
	record = provider.call("_get_worker_record", player)
	if int(record.get("owed_currency", 0)) - owed_before_passive < int(server_job.get("pay_per_interval")):
		_fail("Player party waiter jobs should accrue base wages while the party worker is listening in the bar")
	var owed_after_passive := int(record.get("owed_currency", 0))
	var guard_job = provider.call("start_contract_shift", player, guard_contract)
	if guard_job != null:
		provider.call("process_contracts", pay_interval, pay_interval * 2.0)
		record = provider.call("_get_worker_record", player)
		if int(record.get("owed_currency", 0)) != owed_after_passive:
			_fail("Player party waiter base wages should not accrue while the party worker is actively working another job")
		provider.call("pause_worker_job", player, false)
	var jobs_window = CHARACTER_JOBS_WINDOW_SCRIPT.new()
	root.add_child(jobs_window)
	jobs_window.call("setup", _scene)
	jobs_window.call("show_for_actor", player)
	var window_contracts: Array = jobs_window.call("_get_contracts")
	if _contract_for_job(window_contracts, "bar_server").is_empty() or _contract_for_job(window_contracts, "bar_guard").is_empty():
		_fail("The party worker's Jobs window should show accepted waiter and guard contracts")
	jobs_window.queue_free()
	player.set_move_target(player.global_position + Vector3(1.0, 0.0, 0.0), true)
	if bridge.call("get_actor_job_contracts", player).size() < 2:
		_fail("Player movement orders should not remove durable job contracts")
	player.stop_movement()
	if player.has_active_player_order() or player.has_move_target() or player.get_current_order_type() != InteractionCapability.ORDER_TYPE_NONE:
		_fail("Stopping the controlled movement order must clear navigation and player-order authority before idle-work checks")
	var waiter_idle_status: Dictionary = provider.call("get_contract_work_status", player, waiter_contract)
	var guard_status: Dictionary = provider.call("get_contract_work_status", player, guard_contract)
	if bool(waiter_idle_status.get("actionable", false)):
		_fail("Player waiter job should be passive when no NPC order is ready")
	if not bool(guard_status.get("actionable", false)):
		_fail("Guard job should remain actionable while higher-priority waiter has no order")
	for point in service_area.call("get_waiter_service_points"):
		if point != null and point.has_method("get_assigned_worker") and point.call("get_assigned_worker") == player:
			_fail("Player party waiter jobs should not claim or idle at NPC waiter points")
	var seat = seats[0]
	# Isolate this order from automatic next-contract dispatch while the real
	# GECS work driver continues running on physics ticks.
	var scheduler_was_processing := ranked_jobs.is_processing()
	ranked_jobs.set_process(false)
	service_area.set("waiter_service_delay_seconds", 0.0)
	if not _seat_actor_for_waiter_validation(customer, seat):
		_fail("Player waiter job validation customer should be seated before service")
	else:
		var waiter_ready_status: Dictionary = provider.call("get_contract_work_status", player, waiter_contract)
		if not bool(waiter_ready_status.get("actionable", false)):
			_fail("Player waiter job should become actionable when an NPC customer order is ready")
		if ranked_jobs._resolve_contract_provider(waiter_contract) != provider:
			_fail("Dynamically realized facility provider must register with the shared Jobs authority")
		if not ranked_jobs.dispatch_actor_work(player):
			_fail("Ranked-job dispatcher should start the explicitly prioritized waiter contract: %s" % str(provider.call("get_contract_work_status", player, waiter_contract)))
		var ai = bridge.get_actor_entity(player).get_component(CGameAiState)
		if ai == null or ai.active_job == null or ai.active_driver == null or ai.active_job_id != str(waiter_contract.contract_id):
			_fail("Ranked waiter dispatch must install the real GECS job and driver, not only a provider slot")
		var claimed_assignment: Dictionary = {}
		var claimed_slot: Dictionary = {}
		for _frame in range(180):
			claimed_assignment = provider.call("_find_worker_slot", player)
			claimed_slot = claimed_assignment.get("slot_state", {})
			if not str(claimed_slot.get("target_service_order_id", "")).is_empty():
				break
			await physics_frame
		var claimed_order_id := str(claimed_slot.get("target_service_order_id", ""))
		var claimed_state := str(claimed_slot.get("server_state", ""))
		ranked_jobs.dispatch_actor_work(player)
		claimed_assignment = provider.call("_find_worker_slot", player)
		claimed_slot = claimed_assignment.get("slot_state", {})
		if claimed_order_id.is_empty() or str(claimed_slot.get("target_service_order_id", "")) != claimed_order_id or str(claimed_slot.get("server_state", "")) != claimed_state:
			_fail("Ranked-job re-dispatch should not pause and restart an already-claimed player waiter order")
		record = provider.call("_get_worker_record", player)
		var owed_before := int(record.get("owed_currency", 0))
		var charisma_xp_before := float(player.get_stats().get_skill_xp(SkillRules.ATTRIBUTE_CHARISMA))
		await _complete_player_waiter_order(provider, player, charisma_xp_before)
		var charisma_xp_delta := float(player.get_stats().get_skill_xp(SkillRules.ATTRIBUTE_CHARISMA)) - charisma_xp_before
		if charisma_xp_delta <= 0.0:
			var active_assignment: Dictionary = provider.call("_find_worker_slot", player)
			var active_slot: Dictionary = active_assignment.get("slot_state", {})
			var service_position: Vector3 = service_area.call("get_waiter_customer_service_position", player, seat)
			_fail("Player party waiter jobs should complete NPC customer service events and award service XP, state=%s elapsed=%.2f distance=%.2f blocker=%s" % [str(active_slot.get("server_state", "")), float(active_slot.get("server_state_elapsed", 0.0)), player.global_position.distance_to(service_position), str(active_slot.get("last_ai_blocker", ""))])
		record = provider.call("_get_worker_record", player)
		if int(record.get("owed_currency", 0)) < owed_before:
			_fail("Player party waiter order completion should not lose owed wages")
		var xp_after_completion := float(player.get_stats().get_skill_xp(SkillRules.ATTRIBUTE_CHARISMA))
		var owed_after_completion := int(record.get("owed_currency", 0))
		provider.call("process_jobs", 1.0, 20.0)
		record = provider.call("_get_worker_record", player)
		if float(player.get_stats().get_skill_xp(SkillRules.ATTRIBUTE_CHARISMA)) != xp_after_completion or int(record.get("owed_currency", 0)) != owed_after_completion:
			_fail("Repeated waiter ticks after completion should not award duplicate Charisma XP or pay")
		if not bool(service_area.call("_is_seat_on_waiter_order_cooldown", seat)):
			_fail("The same served table should enter a cooldown after player-party waiter service")
	if bridge.call("get_actor_job_contracts", player).size() < 2:
		_fail("Completing a player-party waiter order should not remove waiter or guard contracts")
	# Isolate terminal/provider probes even if the physical service assertion failed.
	provider.cancel_work_for_actor(player)
	customer.get_interaction().stop_seat_assignment()
	# Other seated customers can create waiter offers. The guard lifecycle
	# specifically requires guard duty, so make that the explicit first rank.
	_rank_contract_first(ranked_jobs, player, guard_contract)
	var ai_state = bridge.get_actor_entity(player).get_component(CGameAiState)
	var lifecycle_dispatched := ranked_jobs.dispatch_actor_work(player)
	if not lifecycle_dispatched:
		_fail("The explicitly first-ranked actionable guard contract must dispatch")
	if lifecycle_dispatched:
		var post = await _await_guard_claim(provider, player)
		if post == null or ai_state.active_job == null:
			_fail("Lifecycle probe must start an actual guard contract and claim")
		else:
			print("BAR_GUARD_CLAIM actor=", player.stable_id, " post=", post.get_path())
			ai_state.finish_job(AiTaskStep.StepStatus.CANCELLED)
			if player.get_active_job_provider() != null or not (provider.call("_find_worker_slot", player) as Dictionary).is_empty() or post.get_assigned_worker() == player:
				_fail("GECS terminal cancellation must release the already-claimed guard slot and post")
			provider.cancel_work_for_actor(player)
			if not ranked_jobs.dispatch_actor_work(player) or await _await_guard_claim(provider, player) == null:
				_fail("Guard must reacquire an actual post after GECS cancellation")
		ranked_jobs.cancel_work_for_actor(player)
		if not (provider.call("_find_worker_slot", player) as Dictionary).is_empty() or player.get_active_job_provider() != null or ai_state.active_job != null:
			_fail("Shared Jobs cancellation must clear the facility slot and real GECS driver")
		if post != null and post.get_assigned_worker() == player:
			_fail("Cancelled facility duty must release its guard-post reservation")
		# A failed cancellation is still reported; clean the fixture before exit.
		provider.call("pause_worker_job", player, false)
		if ai_state.active_job != null:
			ai_state.finish_job(AiTaskStep.StepStatus.CANCELLED)
		if not ranked_jobs.dispatch_actor_work(player):
			_fail("Cancelled facility contract must be reacquirable without rehiring")
		ranked_jobs.prepare_actor_for_derealization(player)
		if not (provider.call("_find_worker_slot", player) as Dictionary).is_empty() or player.get_active_job_provider() != null or ai_state.active_job != null:
			_fail("Shared worker derealization must release facility work before actor destruction")
		provider.call("pause_worker_job", player, false)
		if ai_state.active_job != null:
			ai_state.finish_job(AiTaskStep.StepStatus.CANCELLED)
	else:
		_fail("The explicitly first-ranked actionable guard contract must dispatch")
	await _validate_contract_provider_lod(bar, provider, player, guard_contract)
	ranked_jobs.set_actor_jobs_enabled(player, previous_jobs_enabled)
	ranked_jobs.set_process(scheduler_was_processing)
	_restore_waiter_validation_service_config(service_area, original_service_delay, original_prompt_interval, original_prompt_jitter)


func _rank_contract_first(jobs: JobSystemController, worker: HumanoidCharacter, contract: Dictionary) -> void:
	var entry_id := ""
	for row in jobs.get_actor_ranked_jobs(worker):
		if str(row.get("contract_id", "")) == str(contract.get("contract_id", "")):
			entry_id = str(row.get("entry_id", ""))
	if entry_id.is_empty():
		_fail("Accepted contract must expose a ranked entry: %s" % contract)
		return
	var budget := jobs.get_actor_ranked_jobs(worker).size()
	while jobs.get_actor_job_entry_rank(worker, entry_id) > 0 and budget > 0:
		if not jobs.move_actor_job_entry(worker, entry_id, -1):
			break
		budget -= 1
	if jobs.get_actor_job_entry_rank(worker, entry_id) != 0:
		_fail("The selected contract must be first in actual automatic dispatch policy: %s" % entry_id)


func _validate_contract_provider_lod(bar: Node, provider: Node, worker: HumanoidCharacter, contract: Dictionary) -> void:
	var jobs := BootstrapContext.service(JobSystemController.SERVICE_ID) as JobSystemController
	var bridge := _get_gecs_world()
	var ai = bridge.get_actor_entity(worker).get_component(CGameAiState)
	if not jobs.dispatch_actor_work(worker):
		_fail("READY cancellation fixture must accept the real ranked contract")
		return
	ai.finish_job(AiTaskStep.StepStatus.CANCELLED)
	if worker.get_active_job_provider() != null or not (provider.call("_find_worker_slot", worker) as Dictionary).is_empty():
		_fail("Cancelling before the first GECS tick must release the accepted slot")
		provider.cancel_work_for_actor(worker)
	if not jobs.dispatch_actor_work(worker) or await _await_guard_claim(provider, worker) == null:
		_fail("Replacement fixture requires a real claimed guard post")
		return
	var old_job = ai.active_job
	ai.finish_job(AiTaskStep.StepStatus.CANCELLED)
	if not jobs.dispatch_actor_work(worker):
		_fail("Guard replacement must start without rehiring")
		return
	var replacement = ai.active_job
	provider.call("_release_ai_assignment", int(old_job.data.get("provider_assignment_generation", 0)))
	if ai.active_job != replacement or worker.get_active_job_provider() != provider:
		_fail("Old terminal cleanup must not erase a newer same-provider claim")
	var post = await _await_guard_claim(provider, worker)
	if post == null:
		_fail("Provider LOD fixture requires a real reserved guard post")
		return
	var owner_actor = provider.get_parent()
	var owner_id := str(owner_actor.stable_id)
	var owner_instance := owner_actor.get_instance_id()
	var provider_instance := provider.get_instance_id()
	var earned := int((provider.call("_get_worker_record", worker) as Dictionary).get("owed_currency", 0))
	var settlements := BootstrapContext.service(SettlementController.SERVICE_ID) as SettlementController
	var owner_slot := _assignment_slot_for_actor(bar, owner_id)
	if owner_slot.is_empty() or earned <= 0:
		_fail("Provider LOD must preserve a durable owner and real earned service wages")
		return
	settlements.derealize_assignment_slot("bar_authoring", "employment", str(owner_slot.slot_id))
	await _wait_frames(3)
	if is_instance_valid(provider) or worker.get_active_job_provider() != null or ai.active_job != null or post.get_assigned_worker() == worker or worker.has_move_target():
		_fail("Destroying the provider owner must release slot, driver, guard post and movement")
	if jobs._resolve_contract_provider(contract) != null:
		_fail("Removed provider must not remain dispatchable")
	if not settlements.realize_assignment_slot("bar_authoring", "employment", str(owner_slot.slot_id)):
		_fail("The same durable provider owner must re-realize")
		return
	bar.call("_repair_authoring_tree")
	await _wait_frames(3)
	var new_owner := _role_actor(bar, "barkeeper")
	var new_provider := new_owner.get_node_or_null("JobProvider") if new_owner != null else null
	if new_owner == null or str(new_owner.stable_id) != owner_id or new_owner.get_instance_id() == owner_instance or new_provider == null or new_provider.get_instance_id() == provider_instance:
		_fail("Provider round trip must replace both nodes, retaining the durable barkeeper identity")
		return
	if int((new_provider.call("_get_worker_record", worker) as Dictionary).get("owed_currency", 0)) != earned:
		_fail("Provider re-realization must retain earned wages from canonical GECS records")
	if jobs._resolve_contract_provider(contract) != new_provider or not jobs.dispatch_actor_work(worker) or await _await_guard_claim(new_provider, worker) == null:
		_fail("Existing contract must reacquire a post after same-owner provider re-realization: resolved=%s status=%s provider=%s active=%s record=%s" % [str(jobs._resolve_contract_provider(contract) == new_provider), str(new_provider.get_contract_work_status(worker, contract)), str(worker.get_active_job_provider()), str(ai.active_job_id), str(new_provider.call("_get_worker_record", worker))])
	jobs.cancel_work_for_actor(worker)
	print("BAR_PROVIDER_LOD owner=", owner_id, " earned=", earned, " replacement=", new_provider.get_instance_id())


func _await_guard_claim(provider: Node, worker: HumanoidCharacter) -> Node:
	for _frame in range(180):
		var assignment: Dictionary = provider.call("_find_worker_slot", worker)
		var post = (assignment.get("slot_state", {}) as Dictionary).get("target_guard_post")
		if is_instance_valid(post) and post.get_assigned_worker() == worker:
			return post
		await physics_frame
	return null


func _complete_player_waiter_order(provider: Node, worker: HumanoidCharacter, xp_before: float) -> void:
	# The real GECS driver must walk customer -> bar -> customer and complete.
	# Transaction-only helpers elsewhere deliberately do not claim navigation proof.
	var origin := worker.global_position
	var max_displacement := 0.0
	var states: Dictionary = {}
	var navigation = worker.get_node("NavigationAgent3D")
	var arrivals: Dictionary = {"reached": 0, "failed": 0, "samples": []}
	var on_arrival := func(reached: bool) -> void:
		var key := "reached" if reached else "failed"
		arrivals[key] += 1
		if arrivals.samples.size() < 6:
			arrivals.samples.append({"reached": reached, "state": _waiter_motion_snapshot(worker)})
	navigation.movement_finished.connect(on_arrival)
	for _frame in range(1800):
		var assignment: Dictionary = provider.call("_find_worker_slot", worker)
		if assignment.is_empty():
			break
		var service_state := str((assignment.get("slot_state", {}) as Dictionary).get("server_state", ""))
		if service_state == "waiting_at_bar" and not states.has(service_state) and worker.has_move_target():
			_fail("Arriving at the bar must stop travel before timed preparation")
		states[service_state] = true
		await physics_frame
		max_displacement = maxf(max_displacement, worker.global_position.distance_to(origin))
	navigation.movement_finished.disconnect(on_arrival)
	for required in ["to_barkeeper", "waiting_at_bar", "delivering"]:
		if not states.has(required):
			_fail("Real waiter driver must traverse service state: %s" % required)
	print("BAR_PHYSICAL_SERVICE displacement=", max_displacement, " states=", states.keys(), " xp_delta=", float(worker.get_stats().get_skill_xp(SkillRules.ATTRIBUTE_CHARISMA)) - xp_before, " position=", worker.global_position, " move_target=", worker.get_move_target(), " has_target=", worker.has_move_target(), " velocity=", worker.velocity)
	print("BAR_MOVEMENT_RECEIPTS ", JSON.stringify(arrivals))
	if float(worker.get_stats().get_skill_xp(SkillRules.ATTRIBUTE_CHARISMA)) <= xp_before:
		print("BAR_MOTION_BLOCKER ", JSON.stringify(_waiter_motion_snapshot(worker)))
	if max_displacement < 0.5:
		_fail("Live ranked waiter driver must physically travel between the customer and barkeeper")
	var ai = _get_gecs_world().get_actor_entity(worker).get_component(CGameAiState)
	if float(worker.get_stats().get_skill_xp(SkillRules.ATTRIBUTE_CHARISMA)) > xp_before and ai != null and ai.active_job != null:
		_fail("Completed waiter service must clear the authoritative GECS job and driver")


func _waiter_motion_snapshot(worker: HumanoidCharacter) -> Dictionary:
	return preload("res://tests/validation/helpers/navigation_fixture.gd").actor_motion_snapshot(worker)


func _restore_waiter_validation_service_config(service_area: Node, service_delay: float, prompt_interval: float, prompt_jitter: float, repeat_cooldown := -1.0) -> void:
	if service_area == null:
		return
	service_area.set("waiter_service_delay_seconds", service_delay)
	if repeat_cooldown >= 0.0:
		service_area.set("waiter_customer_repeat_cooldown_seconds", repeat_cooldown)
	service_area.set("waiter_order_prompt_interval_seconds", prompt_interval)
	service_area.set("waiter_order_prompt_jitter_seconds", prompt_jitter)


func _seat_actor_for_waiter_validation(actor: HumanoidCharacter, seat) -> bool:
	if actor == null or seat == null:
		return false
	if seat.has_method("get_sitter"):
		var sitter = seat.call("get_sitter")
		if sitter != null and sitter != actor:
			sitter.get_interaction().stop_seat_assignment()
	actor.get_interaction().stop_seat_assignment()
	if seat.has_method("get_interaction_position"):
		actor.global_position = seat.call("get_interaction_position", actor)
	actor.get_interaction().assign_seat_target(seat, false)
	var approach = actor.get_interaction().current_seat_stand_position
	if not (approach is Vector3) or not (approach as Vector3).is_finite():
		_fail("Controlled service seat needs a physically reachable approach: %s" % str(seat.get_path()))
		return false
	actor.global_position = approach
	actor.get_interaction().process_seat_interaction()
	return actor.is_sitting()


func _complete_waiter_order(provider: Node, service_area: Node, worker: HumanoidCharacter, start_time: float) -> Node:
	# NPC table service owns a target seat, unlike keyed player-party orders.
	# Let the actual NPC algorithm claim it instead of reserving a player order.
	var seat: Node = null
	var tick_seconds := 0.25
	var tick_budget := int(ceil(float(provider.SERVER_ORDER_PREP_SECONDS) / tick_seconds)) + 8
	var state := ""
	for tick in range(tick_budget):
		var assignment: Dictionary = provider.call("_find_worker_slot", worker)
		var slot: Dictionary = assignment.get("slot_state", {})
		var active_seat = slot.get("target_service_seat")
		state = str(slot.get("server_state", ""))
		if active_seat != null:
			if seat != null and active_seat != seat:
				_fail("Waiter probability case must finish one claimed table before changing customers")
				return null
			seat = active_seat
		if seat != null and active_seat == null and state == provider.SERVER_STATE_IDLE:
			return seat
		if state in [provider.SERVER_STATE_TO_BARKEEPER, provider.SERVER_STATE_WAITING_AT_BAR]:
			worker.global_position = service_area.call("get_barkeeper_order_position", worker)
		elif seat != null:
			worker.global_position = service_area.call("get_waiter_customer_service_position", worker, seat)
		provider.call("process_jobs", tick_seconds, start_time + float(tick) * tick_seconds)
	_fail("NPC table service must complete through the real state machine within its preparation budget: state=%s claimed=%s" % [state, str(seat != null)])
	return null


func _configure_waiter_check(job, chance: float) -> void:
	job.set("server_charisma_base_chance", chance)
	job.set("server_charisma_chance_per_level", 0.0)
	job.set("server_charisma_min_chance", chance)
	job.set("server_charisma_max_chance", chance)


func _validate_player_waiter_order_action(bar: Node) -> void:
	var service_area := bar.get_node_or_null("BarServiceArea")
	var player := _scene.get_node_or_null("PartyMembers/Worker") as HumanoidCharacter
	var seats: Array = []
	if service_area != null:
		seats = service_area.call("_collect_seat_nodes")
	if service_area == null or player == null or seats.is_empty():
		_fail("Player waiter order validation could not find service area, player, or seats")
		return
	var seat = seats[0]
	var original_service_delay := float(service_area.get("waiter_service_delay_seconds"))
	service_area.set("waiter_service_delay_seconds", 0.0)
	if not _seat_actor_for_waiter_validation(player, seat):
		_fail("Player should be able to sit in a bar seat before calling a waiter")
		service_area.set("waiter_service_delay_seconds", original_service_delay)
		return
	if player.call("get_current_seat_target") != seat:
		_fail("Seated player should expose the current seat target for inspector actions")
	if seat.has_method("get_bar_service_area") and seat.call("get_bar_service_area") != service_area:
		_fail("Bar seat should expose its owning service area")
	if not bool(service_area.call("can_call_waiter_for_customer", player)):
		_fail("Seated player should be able to call a same-bar waiter")
	service_area.call("_process_waiter_service")
	if not bool(service_area.call("can_call_waiter_for_customer", player)):
		_fail("Waiters should not automatically re-prompt seated players without the Order action")
	var player_position := player.global_position
	var result: Dictionary = service_area.call("call_waiter_for_customer", player)
	if not bool(result.get("allowed", false)):
		_fail("Order action should call a waiter for a seated player: %s" % str(result.get("message", "")))
	elif service_area.get("_active_service_customer") != player:
		_fail("Order action should start waiter service for the seated player without moving the player to the waiter")
	if player.global_position.distance_to(player_position) > 0.01:
		_fail("Order action should keep the player seated while the waiter comes to the table")
	service_area.call("release_waiter_customer_service", seat)
	service_area.call("_clear_waiter_service")
	player.get_interaction().stop_seat_assignment()
	service_area.set("waiter_service_delay_seconds", original_service_delay)


func _server_shift_job_index(provider: Node) -> int:
	return _job_index_for_algorithm(provider, "server_shift")


func _job_index_for_algorithm(provider: Node, algorithm_id: String) -> int:
	if provider == null:
		return -1
	var jobs: Array = provider.get("jobs")
	for index in range(jobs.size()):
		var job = jobs[index]
		if job != null and str(job.get("algorithm_id")) == algorithm_id:
			return index
	return -1


func _accept_job_offer(provider: Node, worker: HumanoidCharacter, job_index: int) -> bool:
	if provider == null or worker == null or job_index < 0:
		return false
	var request: Dictionary = provider.call("handle_conversation_option", worker, {"job_provider_action": "request_job", "job_index": job_index})
	if bool(request.get("end_conversation", true)):
		return false
	var accepted: Dictionary = provider.call("handle_conversation_option", worker, {"job_provider_action": "accept_job_offer", "job_index": job_index})
	return bool(accepted.get("end_conversation", false))


func _contract_for_job(contracts: Array, job_id: String) -> Dictionary:
	for contract in contracts:
		if contract is Dictionary and str(contract.get("job_id", "")) == job_id:
			return contract
	return {}


func _validate_waiter_job_offer_text(provider: Node, job_index: int) -> void:
	var jobs: Array = provider.get("jobs")
	var job = jobs[job_index] if job_index >= 0 and job_index < jobs.size() else null
	var offer := str(provider.call("_build_job_offer_text", job)).to_lower()
	if not offer.contains("every %d seconds" % int(job.get("pay_interval_seconds"))):
		_fail("Waiter job offer should describe base interval pay")
	if not offer.contains("tip"):
		_fail("Waiter job offer should describe customer tips")
	if offer.contains("per completed order"):
		_fail("Waiter job offer should not describe completed orders as the base wage")
	var accept := str(provider.call("_build_job_accept_text", job)).to_lower()
	if accept.contains("per completed order"):
		_fail("Waiter job accept text should not imply per-order wages")


func _validate_standalone_bar_stock() -> void:
	var bar := _instantiate_controlled_bar(false)
	bar.name = "StandaloneStockBar"
	bar.set("role_slots", [_role_slot("proprietor", "barkeeper")])
	var bars := _scene.get_node_or_null("Town/Bars")
	if bars == null:
		_fail("Standalone stock validation needs the controlled town bar container")
		bar.free()
		return
	bars.add_child(bar)
	bar.set("stock_source", "standalone_fallback")
	bar.set("standalone_stock_ratio", 0.25)
	if bar.has_method("_repair_authoring_tree"):
		bar.call("_repair_authoring_tree")
	if not _sync_and_realize_bar_assignments(bar):
		bars.remove_child(bar)
		bar.queue_free()
		return
	await _wait_frames(10)
	var barkeeper := _role_actor(bar, "barkeeper")
	var role := barkeeper.get_node_or_null("MerchantRole") if barkeeper != null else null
	if role == null:
		_fail("Standalone bar should create barkeeper merchant stock")
	else:
		var bread_stock := _merchant_initial_stock_quantity(role, BREAD_ITEM)
		var expected := int(round(float(bar.get("max_bread_stock")) * float(bar.get("standalone_stock_ratio"))))
		if bread_stock != expected:
			_fail("Standalone bar should scale authored stock capacity by its explicit ratio; expected=%d actual=%d" % [expected, bread_stock])
	bars.remove_child(bar)
	bar.queue_free()


func _merchant_initial_stock_quantity(role: Node, item: Resource) -> int:
	if role == null or item == null:
		return 0
	var initial_stock: Array = role.get("initial_stock")
	for stock in initial_stock:
		if stock != null and stock.get("item_definition") == item:
			return int(stock.get("quantity"))
	return 0


func _validate_layout_migration(bar: Node) -> void:
	var default_post := bar.get_node_or_null("GuardPosts/GuardPost") as Node3D
	var custom_post := bar.get_node_or_null("GuardPosts/GuardPost2") as Node3D
	if default_post == null or custom_post == null:
		return
	var expected_default := default_post.transform
	var old_default := expected_default.translated_local(Vector3(0.5, 0.0, 0.0))
	default_post.transform = old_default
	default_post.set_meta("facility_last_default_transform", old_default)
	default_post.set_meta("facility_layout_custom", false)
	custom_post.transform = custom_post.transform.translated_local(Vector3(1.25, 0.0, 0.0))
	var custom_transform := custom_post.transform
	bar.call("_repair_authoring_tree")
	if default_post.transform.origin.distance_to(expected_default.origin) > 0.01:
		_fail("Uncustomized generated guard posts should migrate to new default transforms")
	if custom_post.transform.origin.distance_to(custom_transform.origin) > 0.01:
		_fail("Customized generated guard posts should keep their authored transform")


func _validate_scene_authored_layout_source(bar: Node) -> void:
	var fallback := Transform3D(Basis(), Vector3(999.0, 999.0, 999.0))
	var authored: Transform3D = bar.call("_layout_default_transform", NodePath("GuardPosts"), "GuardPost", fallback)
	if authored.origin.distance_to(fallback.origin) < 0.01:
		_fail("Reusable bar should read guard defaults from its authored scene before code fallbacks")
	var scene_bar := (load(bar.scene_file_path) as PackedScene).instantiate()
	var scene_guard := scene_bar.get_node("GuardPosts/GuardPost") as Node3D
	if authored.origin.distance_to(scene_guard.transform.origin) > 0.01:
		_fail("Reusable bar guard default should match the editable scene guard post")
	scene_bar.free()


func _validate_service_area(bar: Node, assigned_waiter: HumanoidCharacter, assigned_guard: HumanoidCharacter) -> void:
	var service_area := bar.get_node_or_null("BarServiceArea")
	if service_area == null:
		_fail("Reusable bar should include a BarServiceArea")
		return
	var waiters: Array = service_area.call("get_waiter_characters")
	if not waiters.has(assigned_waiter):
		_fail("Assigned waiter should be registered with BarServiceArea")
	for waiter in _role_actors(bar, "waiter"):
		if not waiters.has(waiter):
			_fail("Every waiter assignment should be registered with BarServiceArea")
	var guards: Array = service_area.call("get_guard_characters")
	if not guards.has(assigned_guard):
		_fail("Assigned guard should be registered with BarServiceArea")
	for guard in _role_actors(bar, "guard"):
		if not guards.has(guard):
			_fail("Every guard assignment should be registered with BarServiceArea")


func _bar_role_slots(named_waiter: HumanoidCharacter, named_guard: HumanoidCharacter) -> Array[FacilityRoleSlotDefinition]:
	return [
		_role_slot("proprietor", "barkeeper"),
		_role_slot("server_named", "waiter", _character_definition(named_waiter)),
		_role_slot("server_auto", "waiter"),
		_role_slot("security_named", "guard", _character_definition(named_guard)),
		_role_slot("security_auto", "guard"),
		_role_slot("barber_auto", "barber"),
	]


func _role_slot(slot_id: String, role_id: String, named_character: CharacterRecordDefinition = null) -> FacilityRoleSlotDefinition:
	var slot := FacilityRoleSlotDefinition.new()
	slot.slot_id = slot_id
	slot.role = ROLE_RESOURCES.get(role_id) as FacilityRoleDefinition
	slot.named_character = named_character
	return slot


func _character_definition(actor: HumanoidCharacter) -> CharacterRecordDefinition:
	var definition := CharacterRecordDefinition.new()
	definition.actor_id = str(actor.get("stable_id"))
	definition.member_name = str(actor.get("member_name"))
	return definition


func _sync_and_realize_bar_assignments(bar: Node) -> bool:
	var settlement := get_first_node_in_group("settlement_controller")
	var population := get_first_node_in_group("population_controller")
	if settlement == null or population == null:
		_fail("Reusable bar assignment validation needs settlement and population controllers")
		return false
	settlement.call("_sync_settlement_assignment_slots", "bar_authoring")
	var slots: Array = settlement.call("get_facility_assignment_slots", str(bar.call("get_facility_id")), "employment")
	if slots.size() != (bar.get("role_slots") as Array).size():
		_fail("Reusable bar should register every authored role slot; expected=%d actual=%d" % [(bar.get("role_slots") as Array).size(), slots.size()])
		return false
	for slot_value in slots:
		var slot: Dictionary = slot_value
		if not str(slot.get("occupant_actor_id", "")).is_empty():
			continue
		var actor_id := str(slot.get("preferred_actor_id", "")).strip_edges()
		if actor_id.is_empty():
			var census := BootstrapContext.service(SettlementCensus.SERVICE_ID) as SettlementCensus
			var definition: SettlementDefinition = settlement.call("get_settlement_definition", "bar_authoring")
			var base_context: Dictionary = census._generation_context(definition, 373)
			var generation_context: Dictionary = census._assignment_generation_context(definition, base_context, slot)
			var filler: Dictionary = population.call("ensure_assignment_filler_record", "bar_authoring", slot, generation_context)
			actor_id = str(filler.get("actor_id", ""))
		if not actor_id.is_empty():
			settlement.call("assign_actor_to_assignment_slot", "bar_authoring", "employment", str(slot.get("slot_id", "")), actor_id)
	settlement.call("bootstrap_assignments", "bar_authoring")
	slots = settlement.call("get_facility_assignment_slots", str(bar.call("get_facility_id")), "employment")
	for slot_value in slots:
		var slot: Dictionary = slot_value
		if str(slot.get("occupant_actor_id", "")).is_empty():
			_fail("Reusable bar role slot should have a durable population assignment: %s" % str(slot.get("slot_id", "")))
			return false
		if not bool(settlement.call("realize_assignment_slot", "bar_authoring", "employment", str(slot.get("slot_id", "")))):
			_fail("Reusable bar role slot should realize through SettlementController: %s" % str(slot.get("slot_id", "")))
			return false
	bar.call("_repair_authoring_tree")
	return true


func _assignment_slots(bar: Node, role_id := "") -> Array[Dictionary]:
	var settlement := get_first_node_in_group("settlement_controller")
	var result: Array[Dictionary] = []
	if settlement == null:
		return result
	for slot_value in settlement.call("get_facility_assignment_slots", str(bar.call("get_facility_id")), "employment"):
		var slot: Dictionary = slot_value
		if role_id.is_empty() or str(slot.get("role_id", "")) == role_id:
			result.append(slot)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("role_index", 0)) < int(b.get("role_index", 0)))
	return result


func _assignment_slot_for_actor(bar: Node, actor_id: String) -> Dictionary:
	for slot in _assignment_slots(bar):
		if str(slot.get("occupant_actor_id", "")) == actor_id:
			return slot
	return {}


func _role_actors(bar: Node, role_id: String) -> Array[HumanoidCharacter]:
	var actors: Array[HumanoidCharacter] = []
	var population := get_first_node_in_group("population_controller")
	if population == null:
		return actors
	for slot in _assignment_slots(bar, role_id):
		var actor_id := str(slot.get("occupant_actor_id", ""))
		var record: Dictionary = population.call("get_actor_record", actor_id)
		if record.is_empty():
			_fail("Bar assignment occupant should have a durable population record: %s" % actor_id)
			continue
		var actor := population.call("get_live_actor", actor_id) as HumanoidCharacter
		if actor == null:
			_fail("Bar assignment occupant should have a live actor projection: %s" % actor_id)
			continue
		actors.append(actor)
	return actors


func _role_actor(bar: Node, role_id: String, role_index := 0) -> HumanoidCharacter:
	var actors := _role_actors(bar, role_id)
	return actors[role_index] if role_index >= 0 and role_index < actors.size() else null


func _generated_role_node_count(root_node: Node, role_id: String) -> int:
	var count := 0
	if root_node == null:
		return count
	for child in root_node.get_children():
		if bool(child.get_meta("facility_generated", false)) and str(child.get_meta("facility_role", "")) == role_id:
			count += 1
	return count


# A staffing test must not depend on surplus demo census residents or LOD.
# Mint protected authored records through the real population/census path,
# realize them, then prove later named-slot assignment preserves that identity.
func _create_named_staff_fixture(settlement_id: String) -> Array[HumanoidCharacter]:
	var actors: Array[HumanoidCharacter] = []
	var population := BootstrapContext.service(PopulationController.SERVICE_ID) as PopulationController
	var settlement := BootstrapContext.service(SettlementController.SERVICE_ID) as SettlementController
	var census := BootstrapContext.service(SettlementCensus.SERVICE_ID) as SettlementCensus
	var realizer := BootstrapContext.service(PopulationCharacterRealizer.SERVICE_ID) as PopulationCharacterRealizer
	var town := _scene.get_node_or_null("Town")
	if population == null or settlement == null or census == null or realizer == null or town == null:
		_fail("Named staff fixture requires the real initialized population/census/realizer services and town")
		return actors
	var definition := settlement.get_settlement_definition(settlement_id)
	var context: Dictionary = census._generation_context(definition, 371)
	for index in range(2):
		var record: Dictionary = population.ensure_authored_record(settlement_id, "validation.named_bar_staff", index + 1, context, {
			"member_name": "Validation Named Staff %d" % index,
			"available_for_work": false,
		})
		if record.is_empty():
			_fail("Authored named staff fixture must create a permanent record")
			continue
		var actor := realizer.realize_actor(str(record.actor_id), town, town, "ValidationNamedStaff%d" % index) as HumanoidCharacter
		if actor == null:
			_fail("Authored named record must realize using the actual town character profile")
		else:
			actors.append(actor)
	return actors


func _ensure_validation_townie_visitors(bar: Node, excluded: Array, visitors: Array[HumanoidCharacter], required_count: int) -> void:
	if visitors.size() >= required_count:
		return
	var town := _scene.get_node("Town")
	var resident_root := town.get_node(str(town.get("resident_root_path")))
	var population := BootstrapContext.service(PopulationController.SERVICE_ID) as PopulationController
	var settlement := BootstrapContext.service(SettlementController.SERVICE_ID) as SettlementController
	var census := BootstrapContext.service(SettlementCensus.SERVICE_ID) as SettlementCensus
	var realizer := BootstrapContext.service(PopulationCharacterRealizer.SERVICE_ID) as PopulationCharacterRealizer
	var context: Dictionary = census._generation_context(settlement.get_settlement_definition("bar_authoring"), 371)
	context["role_id"] = "resident"
	for _index in range(required_count - visitors.size()):
		_validation_visitor_serial += 1
		var record := population.ensure_authored_record("bar_authoring", "validation.bar_visitor", _validation_visitor_serial, context, {
			"member_name": "Validation Visitor %d" % _validation_visitor_serial,
			"role_id": "resident", "available_for_work": false,
		})
		var actor := realizer.realize_actor(str(record.actor_id), town, resident_root, "ValidationVisitor%d" % _validation_visitor_serial) as HumanoidCharacter
		if actor != null and not excluded.has(actor) and bool(bar.call("can_actor_visit_facility", actor)):
			visitors.append(actor)
		else:
			_fail("Canonical resident fixture must be eligible for a facility visit")
	if visitors.size() != required_count:
		_fail("Visitor fixture must provide every required real resident")


func _collect_townie_visitors(bar: Node, excluded: Array) -> Array[HumanoidCharacter]:
	var visitors: Array[HumanoidCharacter] = []
	var settlement = bar.call("_get_ancestor_settlement") if bar != null and bar.has_method("_get_ancestor_settlement") else null
	if settlement == null:
		return visitors
	var resident_root = settlement.get_node_or_null(settlement.get("resident_root_path"))
	_collect_townie_visitors_recursive(resident_root, bar, excluded, visitors)
	return visitors


func _collect_townie_visitors_recursive(subtree: Node, bar: Node, excluded: Array, visitors: Array[HumanoidCharacter]) -> void:
	if subtree == null:
		return
	for child in subtree.get_children():
		var actor := child as HumanoidCharacter
		if actor != null and not excluded.has(actor) and bool(bar.call("can_actor_visit_facility", actor)):
			visitors.append(actor)
		_collect_townie_visitors_recursive(child, bar, excluded, visitors)


func _seat_for_sitter(bar: Node, actor: HumanoidCharacter) -> Node3D:
	if bar == null or actor == null:
		return null
	var service_area := bar.get_node_or_null("BarServiceArea")
	if service_area == null:
		return null
	var seats: Array = service_area.call("_collect_seat_nodes")
	for seat in seats:
		if seat is Node3D and seat.has_method("get_sitter") and seat.call("get_sitter") == actor:
			return seat as Node3D
	return null


func _get_gecs_world() -> Node:
	return get_first_node_in_group("gecs_world_controller")


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await physics_frame


func _fail(message: String) -> void:
	_failures.append(message)
