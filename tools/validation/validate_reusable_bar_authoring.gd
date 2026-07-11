extends SceneTree

const TWO_TOWNS_SCENE_PATH := "res://scenes/test_levels/two_towns_road_test.tscn"
const SETTLEMENT_BAR_SCENE_PATH := "res://features/settlements/bridge/settlement_bar.tscn"
const STOOL_SCENE_PATH := "res://features/world/projection/props/stool_chair.tscn"
const BREAD_ITEM_PATH := "res://features/inventory/resources/items/bread.tres"
const FOOD_ITEM_PATH := "res://features/inventory/resources/items/food.tres"
const FACTION_HUMANOID_SCRIPT_PATH := "res://features/actors/projection/humanoid/faction_humanoid.gd"
const FARMER_NAME_PROFILE_PATH := "res://features/world_sim/resources/population_name_profiles/farmer_names.tres"
const BARBER_CONVERSATION_PATH := "res://features/conversation/resources/barber_services.tres"
const CHARACTER_JOBS_WINDOW_SCRIPT_PATH := "res://features/ui/projection/character_jobs_window.gd"
const AI_UTILITY_ADAPTER_SCRIPT_PATH := "res://features/ai/bridge/ai_utility_adapter.gd"

var TWO_TOWNS_SCENE: PackedScene
var SETTLEMENT_BAR_SCENE: PackedScene
var STOOL_SCENE: PackedScene
var BREAD_ITEM: Resource
var FOOD_ITEM: Resource
var FACTION_HUMANOID_SCRIPT: Script
var FARMER_NAME_PROFILE: Resource
var BARBER_CONVERSATION: Resource
var CHARACTER_JOBS_WINDOW_SCRIPT: Script
var AI_UTILITY_ADAPTER_SCRIPT: Script

var _failures: Array[String] = []
var _scene: Node


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	_load_validation_resources()
	_scene = TWO_TOWNS_SCENE.instantiate()
	root.add_child(_scene)
	await _wait_frames(120)
	_validate_bread_inventory_shape()
	_validate_base_bar_scene_staff_authoring()
	_validate_demo_starts_without_bar()
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
	TWO_TOWNS_SCENE = load(TWO_TOWNS_SCENE_PATH) as PackedScene
	SETTLEMENT_BAR_SCENE = load(SETTLEMENT_BAR_SCENE_PATH) as PackedScene
	STOOL_SCENE = load(STOOL_SCENE_PATH) as PackedScene
	BREAD_ITEM = load(BREAD_ITEM_PATH) as Resource
	FOOD_ITEM = load(FOOD_ITEM_PATH) as Resource
	FACTION_HUMANOID_SCRIPT = load(FACTION_HUMANOID_SCRIPT_PATH) as Script
	FARMER_NAME_PROFILE = load(FARMER_NAME_PROFILE_PATH) as Resource
	BARBER_CONVERSATION = load(BARBER_CONVERSATION_PATH) as Resource
	CHARACTER_JOBS_WINDOW_SCRIPT = load(CHARACTER_JOBS_WINDOW_SCRIPT_PATH) as Script
	AI_UTILITY_ADAPTER_SCRIPT = load(AI_UTILITY_ADAPTER_SCRIPT_PATH) as Script


func _cleanup_scene() -> void:
	if _scene != null and is_instance_valid(_scene):
		root.remove_child(_scene)
		_scene.free()
		_scene = null
		await _wait_frames(8)


func _cleanup_validation_resources() -> void:
	TWO_TOWNS_SCENE = null
	SETTLEMENT_BAR_SCENE = null
	STOOL_SCENE = null
	BREAD_ITEM = null
	FOOD_ITEM = null
	FACTION_HUMANOID_SCRIPT = null
	FARMER_NAME_PROFILE = null
	BARBER_CONVERSATION = null
	CHARACTER_JOBS_WINDOW_SCRIPT = null
	AI_UTILITY_ADAPTER_SCRIPT = null


func _validate_demo_starts_without_bar() -> void:
	if _scene.get_node_or_null("Settlements/FarmerCrossing/Bars/FarmerBar") != null:
		_fail("Two-factions demo should not ship with a pre-placed FarmerBar")
	var bars := _scene.get_node_or_null("Settlements/FarmerCrossing/Bars")
	if bars == null:
		_fail("Farmer Crossing should keep an empty Bars container for operator placement")
	var placed_bar := _scene.get_node_or_null("Settlements/FarmerCrossing/Bars/SettlementBar")
	if placed_bar != null and int(placed_bar.get("visitor_capacity")) != 4:
		_fail("Farmer Crossing placed bar should have enough visitor capacity to visibly fill chairs")


func _validate_bread_inventory_shape() -> void:
	if BREAD_ITEM.get("grid_size") != Vector2i(3, 2):
		_fail("Bread should occupy a 3x2 inventory footprint")
	if int(BREAD_ITEM.get("max_stack")) != 1:
		_fail("Bread should not stack in inventory")


func _validate_base_bar_scene_staff_authoring() -> void:
	var bar := SETTLEMENT_BAR_SCENE.instantiate()
	var staff_root := bar.get_node_or_null("Staff")
	if staff_root == null:
		_fail("Base reusable bar scene should keep a Staff root")
	else:
		for staff_name in ["Barkeeper", "Waiter", "Guard", "Barber"]:
			if staff_root.get_node_or_null(staff_name) != null:
				_fail("Base reusable bar scene should not ship authored default Staff/%s" % staff_name)
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
	var bars := _scene.get_node_or_null("Settlements/FarmerCrossing/Bars")
	var townies := _collect_settlement_townies("Settlements/FarmerCrossing/Residents")
	var assigned_waiter := townies[0] if townies.size() > 0 else null
	var assigned_guard := townies[1] if townies.size() > 1 else null
	if bars == null or assigned_waiter == null or assigned_guard == null:
		_fail("Could not find bar container or generated townies for reusable bar validation")
		return
	var waiter_parent := assigned_waiter.get_parent()
	var guard_parent := assigned_guard.get_parent()
	var bar := SETTLEMENT_BAR_SCENE.instantiate()
	bar.name = "OperatorBar"
	bar.set("use_settlement_population_for_staff", false)
	bars.add_child(bar)
	bar.set("display_name", "Operator Test Bar")
	var waiter_paths: Array[NodePath] = [bar.get_path_to(assigned_waiter)]
	var guard_paths: Array[NodePath] = [bar.get_path_to(assigned_guard)]
	bar.set("waiter_count", 2)
	bar.set("assigned_waiter_paths", waiter_paths)
	bar.set("guard_count", 2)
	bar.set("assigned_guard_paths", guard_paths)
	bar.set("has_barber", true)
	bar.set("visitor_capacity", 4)
	if bar.has_method("_repair_authoring_tree"):
		bar.call("_repair_authoring_tree")
	await _wait_frames(20)
	_validate_inferred_defaults(bar)
	_validate_staff(bar, assigned_waiter, assigned_guard, waiter_parent, guard_parent)
	_validate_role_points(bar)
	_validate_furniture_authoring(bar)
	_validate_bar_visit_capacity(bar, assigned_waiter, assigned_guard)
	_validate_player_waiter_order_action(bar)
	_validate_barber_seating(bar)
	_validate_seated_talk_range(bar)
	_validate_barkeeper_stock(bar)
	_validate_waiter_order_job(bar, assigned_waiter, assigned_guard)
	_validate_player_waiter_job_order_priority(bar, assigned_guard)
	await _validate_standalone_bar_stock()
	_validate_scene_authored_layout_source(bar)
	_validate_layout_migration(bar)
	_validate_service_area(bar, assigned_waiter, assigned_guard)
	await _validate_staff_combat_response(bar)


func _validate_inferred_defaults(bar: Node) -> void:
	if str(bar.call("get_facility_id")) != "farmer_crossing.operator_bar":
		_fail("Reusable bar should infer facility_id from settlement id and node name")
	if str(bar.call("_get_staff_id_prefix")) != "npc.farmer_crossing.operator_bar":
		_fail("Reusable bar should infer staff_stable_id_prefix from facility_id")
	if str(bar.call("_get_bar_squad_name")) != "farmer_crossing.operator_bar":
		_fail("Reusable bar should infer staff_squad_name from the facility")
	if str(bar.call("_get_effective_owner_faction_id")) != "Farmers":
		_fail("Reusable bar should infer owner_faction_id from the parent settlement")


func _validate_staff(bar: Node, assigned_waiter: HumanoidCharacter, assigned_guard: HumanoidCharacter, waiter_parent: Node, guard_parent: Node) -> void:
	var barkeeper := bar.get_node_or_null("Staff/Barkeeper") as HumanoidCharacter
	var generated_waiter := bar.get_node_or_null("Staff/Waiter") as HumanoidCharacter
	var generated_guard := bar.get_node_or_null("Staff/Guard") as HumanoidCharacter
	var barber := bar.get_node_or_null("Staff/Barber") as HumanoidCharacter
	if barkeeper == null:
		_fail("Reusable bar should auto-generate a barkeeper")
	if generated_waiter == null:
		_fail("Reusable bar should generate only missing waiter staff")
	if bar.get_node_or_null("Staff/Waiter2") != null:
		_fail("Assigned waiter should count toward waiter_count instead of generating Waiter2")
	if generated_guard == null:
		_fail("Reusable bar should generate only missing guard staff")
	if bar.get_node_or_null("Staff/Guard2") != null:
		_fail("Assigned guard should count toward guard_count instead of generating Guard2")
	if barber == null:
		_fail("has_barber should auto-generate a barber")
	if assigned_waiter.get_parent() != waiter_parent:
		_fail("Assigned waiter should be referenced in place, not reparented into the bar")
	if assigned_guard.get_parent() != guard_parent:
		_fail("Assigned guard should be referenced in place, not reparented into the bar")
	if not str(assigned_waiter.get("member_name")).ends_with("(waiter)"):
		_fail("Assigned waiter should be easy to identify with a waiter role suffix")
	if not str(assigned_guard.get("member_name")).ends_with("(guard)"):
		_fail("Assigned guard should be easy to identify with a guard role suffix")
	for actor in [barkeeper, generated_waiter, generated_guard, barber]:
		if actor == null:
			continue
		if actor.faction_name != "Farmers":
			_fail("Generated bar staff should inherit the bar owner faction")
		if actor.appearance_data == null:
			_fail("Generated bar staff should use the settlement/faction appearance generator")
		var display_name := str(actor.get("member_name"))
		var role := _role_from_display_name(display_name)
		if role.is_empty():
			_fail("Generated bar staff name '%s' should include a role suffix" % display_name)
		if not bool(FARMER_NAME_PROFILE.call("contains_name", _strip_role_suffix(display_name))):
			_fail("Generated bar staff name '%s' should come from the Farmer name profile before the role suffix" % display_name)
		if not str(actor.get("stable_id")).begins_with("npc.farmer_crossing.operator_bar."):
			_fail("Generated bar staff stable ids should use the inferred staff prefix")
		if str(actor.get("squad_name")) != "farmer_crossing.operator_bar":
			_fail("Generated bar staff should infer the facility squad name")
		_validate_staff_perception(actor, role)
	if barber != null:
		if barber.get("conversation_definition") != BARBER_CONVERSATION:
			_fail("Generated barber should expose barber services")
		if not barber.has_method("get_barber_service_price"):
			_fail("Generated barber should use BarberHumanoid behavior")


func _validate_staff_combat_response(bar: Node) -> void:
	var barkeeper := bar.get_node_or_null("Staff/Barkeeper") as HumanoidCharacter
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
	attacker.global_position = barkeeper.global_position + Vector3(1.0, 0.0, 0.0)
	await _wait_frames(4)
	barkeeper.notify_incoming_attack(attacker)
	await _wait_frames(12)
	var responders: Array[HumanoidCharacter] = [barkeeper]
	for role_name in ["Waiter", "Guard", "Barber"]:
		var actor := bar.get_node_or_null("Staff/%s" % role_name) as HumanoidCharacter
		if actor != null:
			responders.append(actor)
	for responder in responders:
		if responder == null or responder.life_state != NpcRules.LifeState.ALIVE:
			continue
		if not responder.is_in_combat() or responder.get_current_combat_target() != attacker:
			_fail("Bar staff %s should enter real combat against an attacker, not only move like a responder" % responder.name)
		responder.disengage_combat_with(attacker)
	attacker.queue_free()


func _validate_role_points(bar: Node) -> void:
	if bar.get_node_or_null("ServicePoints") != null:
		_fail("Reusable bar should use its ShopCounter instead of a barkeeper ServicePoints root")
	if bar.get_node_or_null("WaiterPoints/WaiterPoint") == null or bar.get_node_or_null("WaiterPoints/WaiterPoint2") == null:
		_fail("Reusable bar should derive waiter points from waiter_count")
	if bar.get_node_or_null("GuardPosts/GuardPost") == null or bar.get_node_or_null("GuardPosts/GuardPost2") == null:
		_fail("Reusable bar should derive guard posts from guard_count")
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
		if float(visit_point.get("weight")) < 4.0:
			_fail("Facility visit point should strongly prefer the bar enough to look alive")
		if float(visit_point.get("assignment_min_seconds")) < 25.0 or float(visit_point.get("assignment_max_seconds")) > 35.0:
			_fail("Facility visit point should rotate townie visitors on roughly a 30 second cycle")
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
	var expected_min := 14 if role == "guard" else 5
	var expected_max := 24 if role == "guard" else 12
	if perception < expected_min or perception > expected_max:
		_fail("Generated %s perception %d outside expected %d..%d" % [role, perception, expected_min, expected_max])


func _validate_furniture_authoring(bar: Node) -> void:
	var furniture := bar.get_node_or_null("Furniture")
	if furniture == null:
		_fail("Reusable bar should include one Furniture root")
		return
	for legacy_root in ["Tables", "Stools", "Beds"]:
		if furniture.get_node_or_null(legacy_root) != null:
			_fail("Reusable bar base scene should keep furniture directly under Furniture, not Furniture/%s" % legacy_root)
	for path in ["Furniture/TableA", "Furniture/TableB", "Furniture/TableC", "Furniture/TableD", "Furniture/StoolAFront", "Furniture/StoolBBack", "Furniture/StoolBFront", "Furniture/StoolCBack", "Furniture/StoolCFront", "Furniture/StoolDBack", "Furniture/StoolDFront", "Furniture/BedA", "Furniture/BedC5"]:
		if bar.get_node_or_null(path) == null:
			_fail("Reusable bar should preserve authored furniture at %s" % path)
	_validate_bar_stool_exit_offsets(bar)
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
	var visitor_actor := visitors[0] if visitors.size() > 0 else null
	var rejected_actor := visitors[1] if visitors.size() > 1 else null
	if visitor_actor != null and visit_point != null:
		visitor_actor.stop_seat_assignment()
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
			rejected_actor.stop_seat_assignment()
			var old_position := rejected_actor.global_position
			if bool(visit_point.call("assign_actor", rejected_actor)):
				_fail("Facility visit point should reject visitors when no Furniture chair is open")
			if rejected_actor.global_position.distance_to(old_position) > 0.01:
				_fail("Rejected bar visitor should not be moved to a fallback marker")
		bar.set("furniture_root_path", old_furniture_root)
		visit_point.set("visit_seats_root_path", old_visit_seats_root_path)
		visit_point.set("revisit_cooldown_seconds", old_revisit_cooldown)
		empty_furniture.queue_free()
	direct_seat.queue_free()
	legacy_root.queue_free()


func _validate_bar_stool_exit_offsets(bar: Node) -> void:
	var stool_pairs := {
		"Furniture/StoolAFront": "Furniture/TableA",
		"Furniture/StoolABack": "Furniture/TableA",
		"Furniture/StoolBBack": "Furniture/TableB",
		"Furniture/StoolBFront": "Furniture/TableB",
		"Furniture/StoolCBack": "Furniture/TableC",
		"Furniture/StoolCFront": "Furniture/TableC",
		"Furniture/StoolDBack": "Furniture/TableD",
		"Furniture/StoolDFront": "Furniture/TableD",
	}
	for stool_path in stool_pairs.keys():
		var stool := bar.get_node_or_null(stool_path) as Node3D
		var table := bar.get_node_or_null(str(stool_pairs[stool_path])) as Node3D
		if stool == null or table == null:
			continue
		var seated_offset: Vector3 = stool.get("seated_floor_local_offset")
		var interaction_offset: Vector3 = stool.get("interaction_local_offset")
		var stand_offset: Vector3 = stool.get("stand_local_offset")
		if seated_offset.z < 0.18 or seated_offset.z > 0.3:
			_fail("%s should seat visitors slightly forward on the chair without pushing them into the table; offset=%s" % [stool_path, seated_offset])
		if interaction_offset.z > -0.1:
			_fail("%s should be approached from the aisle side, not the table side; offset=%s" % [stool_path, interaction_offset])
		if stand_offset.z > -0.1:
			_fail("%s should release visitors to the aisle side, not the table side; offset=%s" % [stool_path, stand_offset])
		var table_dir := _flat_vector(table.global_position - stool.global_position)
		var stand_dir := _flat_vector(stool.call("get_stand_position") - stool.global_position)
		if table_dir.length() > 0.01 and stand_dir.length() > 0.01 and table_dir.normalized().dot(stand_dir.normalized()) >= -0.1:
			_fail("%s stand position should be opposite the nearby table" % stool_path)


func _validate_bar_visit_capacity(bar: Node, assigned_waiter: HumanoidCharacter, assigned_guard: HumanoidCharacter) -> void:
	var visit_point := bar.get_node_or_null("ActivityPoints/FacilityVisitPoint")
	if visit_point == null:
		_fail("Reusable bar should have a facility visit point for visitor capacity validation")
		return
	if assigned_waiter != null and bool(visit_point.call("is_available_for", assigned_waiter)):
		_fail("Assigned waiter should not count as a normal townie bar visitor")
	if assigned_guard != null and bool(visit_point.call("is_available_for", assigned_guard)):
		_fail("Assigned guard should not count as a normal townie bar visitor")
	var party_member := _scene.get_node_or_null("PartyMembers/Mira") as HumanoidCharacter
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
		visitor.stop_seat_assignment()
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
	visit_point.call("release_actor", first)
	if first.is_sitting():
		_fail("Released bar visitor should stand up and free the chair")
	if first_seat != null:
		var first_local_stand := first_seat.to_local(first.global_position)
		if first_local_stand.z > -0.35:
			_fail("Released bar visitor should stand on the aisle side of the chair, local=%s" % first_local_stand)
	if bool(visit_point.call("is_available_for", first)):
		_fail("Released bar visitor should have a short cooldown before returning")
	if not bool(visit_point.call("is_available_for", second)) or not bool(visit_point.call("assign_actor", second)):
		_fail("A different townie should be able to take the freed bar visitor slot")
	visit_point.call("release_actor", second)
	bar.set("visitor_capacity", original_capacity)
	if bar.has_method("_repair_authoring_tree"):
		bar.call("_repair_authoring_tree")


func _validate_barber_seating(bar: Node) -> void:
	var barber := bar.get_node_or_null("Staff/Barber") as HumanoidCharacter
	if barber == null:
		return
	barber.stop_seat_assignment()
	var seat = bar.call("_barber_seat_for_actor", barber)
	if seat == null:
		_fail("has_barber should find an existing bar chair for the barber")
		return
	bar.call("_send_barber_to_seat", barber)
	if barber.has_method("_process_seat_interaction"):
		barber.call("_process_seat_interaction")
	if not barber.is_sitting():
		_fail("Barber should sit in a normal bar chair instead of standing at a guard/service marker")
	if seat.has_method("get_sitter") and seat.call("get_sitter") != barber:
		_fail("Barber's chosen chair should be occupied by the barber")
	if seat.has_method("get_seat_position") and barber.global_position.distance_to(seat.call("get_seat_position", barber)) > 0.05:
		_fail("Barber should be positioned at the selected chair's seated position")
	if not str(seat.get_path()).contains("/Furniture/"):
		_fail("Barber should use an existing Furniture chair")
	barber.stop_seat_assignment()


func _validate_seated_talk_range(bar: Node) -> void:
	var talker := bar.get_node_or_null("Staff/Guard") as HumanoidCharacter
	var barber := bar.get_node_or_null("Staff/Barber") as HumanoidCharacter
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
	talker.stop_conversation_interaction()
	barber.stop_conversation_interaction()
	talker.stop_seat_assignment()
	barber.stop_seat_assignment()
	if not talker.sit_at_seat_immediately(talker_seat):
		_fail("Seated talk validation talker should be able to claim a chair")
	elif not barber.sit_at_seat_immediately(barber_seat):
		_fail("Seated talk validation barber should be able to claim a chair")
	else:
		barber.global_position = talker.global_position + Vector3(target_distance, 0.0, 0.0)
		talker.assign_conversation_target(barber, true)
		talker.call("_process_conversation_interaction")
		if not talker.is_sitting():
			_fail("Player-issued seated talk should not stand up when target is within doubled seated range")
		if talker._current_conversation_target != null:
			_fail("Player-issued seated talk should start when target is beyond normal range but within seated range")
		if barber.has_method("release_talker"):
			barber.call("release_talker", talker)
		talker.stop_seat_assignment()
		talker.global_position = barber.global_position + Vector3(target_distance, 0.0, 0.0)
		talker.assign_conversation_target(barber, true)
		talker.call("_process_conversation_interaction")
		if talker._current_conversation_target == null:
			_fail("Standing talker should not get doubled range just because the target is sitting")
	talker.stop_conversation_interaction()
	barber.stop_conversation_interaction()
	if barber.has_method("release_talker"):
		barber.call("release_talker", talker)
	talker.stop_seat_assignment()
	barber.stop_seat_assignment()
	if talker.has_method("_clear_actor_move_target"):
		talker.call("_clear_actor_move_target")
	if barber.has_method("_clear_actor_move_target"):
		barber.call("_clear_actor_move_target")
	talker_seat.queue_free()
	barber_seat.queue_free()


func _validate_barkeeper_stock(bar: Node) -> void:
	var barkeeper := bar.get_node_or_null("Staff/Barkeeper")
	if barkeeper == null:
		return
	var role := barkeeper.get_node_or_null("MerchantRole")
	if role == null:
		_fail("Bar barkeeper should have a MerchantRole")
		return
	var stock_ratio := float(bar.call("_get_effective_stock_ratio"))
	var expected_bread := int(round(12.0 * stock_ratio))
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
	var provider := bar.get_node_or_null("Staff/Barkeeper/JobProvider")
	var customer := bar.get_node_or_null("Staff/Guard") as HumanoidCharacter
	var seats: Array = []
	if service_area != null:
		seats = service_area.call("_collect_seat_nodes")
	if service_area == null or provider == null or customer == null or seats.size() < 2:
		_fail("Waiter order validation could not find service area, provider, customer, or two seats")
		return
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
	_validate_waiter_charisma_xp_curve(provider, job, worker)
	var assignment: Dictionary = provider.call("_assign_worker_to_open_slot", worker, server_job_index)
	if not bool(assignment.get("allowed", false)):
		_fail("Waiter should be able to take the server_shift job for order validation: %s" % str(assignment.get("reason", "")))
		return
	var original_service_delay := float(service_area.get("waiter_service_delay_seconds"))
	var original_prompt_interval := float(service_area.get("waiter_order_prompt_interval_seconds"))
	var original_prompt_jitter := float(service_area.get("waiter_order_prompt_jitter_seconds"))
	if absf(original_prompt_interval - 10.0) > 0.01:
		_fail("Waiter order prompt interval should default to about 10 seconds, got %.2f" % original_prompt_interval)
	if absf(original_prompt_jitter - 3.0) > 0.01:
		_fail("Waiter order prompt jitter should default to about 3 seconds, got %.2f" % original_prompt_jitter)
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
		pacing_customer = bar.get_node_or_null("Staff/Barber") as HumanoidCharacter
	if not _seat_actor_for_waiter_validation(customer, first_seat) or not _seat_actor_for_waiter_validation(pacing_customer, second_seat):
		_fail("Waiter order pacing validation customers should be seated before service")
	else:
		_configure_waiter_check(job, 0.0)
		var before_fail_xp := float(worker.get_skill_xp(SkillRules.ATTRIBUTE_CHARISMA))
		var before_fail_owed := int(record.get("owed_currency", 0))
		_complete_waiter_order(provider, service_area, worker, first_seat, pay_interval + 0.1)
		record = provider.call("_get_worker_record", worker)
		var fail_xp_delta := float(worker.get_skill_xp(SkillRules.ATTRIBUTE_CHARISMA)) - before_fail_xp
		if absf(fail_xp_delta - 5.0) > 0.01:
			_fail("Failed very-low waiter Charisma checks should award half-scale chance XP, got %.2f" % fail_xp_delta)
		if int(record.get("owed_currency", 0)) != before_fail_owed:
			_fail("Failed waiter Charisma checks should not add a tip")
		var chained_claim = service_area.call("claim_waiting_customer_seat", worker)
		if chained_claim != null:
			_fail("Completed waiter orders should start a prompt cooldown instead of chaining immediately to another ready customer")
			service_area.call("release_waiter_customer_service", chained_claim)
		if not bool(first_seat.call("is_waiting_customer_for_service", 0.0, false, true)):
			_fail("Served seated customers should be able to become ready again without leaving the chair")
	customer.stop_seat_assignment()
	if pacing_customer != null:
		pacing_customer.stop_seat_assignment()
	service_area.set("waiter_order_prompt_interval_seconds", 0.0)
	service_area.set("waiter_order_prompt_jitter_seconds", 0.0)
	if not _seat_actor_for_waiter_validation(customer, second_seat):
		_fail("Waiter order validation customer should be seated before service")
		provider.call("pause_worker_job", worker, false)
		_restore_waiter_validation_service_config(service_area, original_service_delay, original_prompt_interval, original_prompt_jitter)
		return
	_configure_waiter_check(job, 1.0)
	var before_success_xp := float(worker.get_skill_xp(SkillRules.ATTRIBUTE_CHARISMA))
	var before_success_owed := int(record.get("owed_currency", 0))
	_complete_waiter_order(provider, service_area, worker, second_seat, pay_interval + 3.0)
	record = provider.call("_get_worker_record", worker)
	var success_xp_delta := float(worker.get_skill_xp(SkillRules.ATTRIBUTE_CHARISMA)) - before_success_xp
	if absf(success_xp_delta - 0.25) > 0.01:
		_fail("Very-high waiter Charisma checks should award tiny half-scale chance XP, got %.2f" % success_xp_delta)
	if int(record.get("owed_currency", 0)) - before_success_owed != 1:
		_fail("Successful waiter Charisma checks should add the configured tip only")
	provider.call("pause_worker_job", worker, false)
	customer.stop_seat_assignment()
	_restore_waiter_validation_service_config(service_area, original_service_delay, original_prompt_interval, original_prompt_jitter)


func _validate_player_waiter_job_order_priority(bar: Node, customer: HumanoidCharacter) -> void:
	var service_area := bar.get_node_or_null("BarServiceArea")
	var provider := bar.get_node_or_null("Staff/Barkeeper/JobProvider")
	var player := _scene.get_node_or_null("PartyMembers/Mira") as HumanoidCharacter
	var bridge := _get_gecs_world()
	var seats: Array = []
	if service_area != null:
		seats = service_area.call("_collect_seat_nodes")
	var server_job_index := _server_shift_job_index(provider) if provider != null else -1
	var guard_job_index := _job_index_for_algorithm(provider, "guard_post") if provider != null else -1
	if service_area == null or provider == null or player == null or customer == null or bridge == null or seats.is_empty() or server_job_index < 0 or guard_job_index < 0:
		_fail("Player waiter job validation could not find service area, provider, bridge, player, customer, seat, server job, or guard job")
		return
	var original_service_delay := float(service_area.get("waiter_service_delay_seconds"))
	var original_prompt_interval := float(service_area.get("waiter_order_prompt_interval_seconds"))
	var original_prompt_jitter := float(service_area.get("waiter_order_prompt_jitter_seconds"))
	service_area.set("waiter_service_delay_seconds", 999.0)
	service_area.set("waiter_order_prompt_interval_seconds", 0.0)
	service_area.set("waiter_order_prompt_jitter_seconds", 0.0)
	player.stop_seat_assignment()
	if not _accept_job_offer(provider, player, server_job_index):
		_fail("Player party worker should be able to accept a durable server_shift contract")
		_restore_waiter_validation_service_config(service_area, original_service_delay, original_prompt_interval, original_prompt_jitter)
		return
	if not _accept_job_offer(provider, player, guard_job_index):
		_fail("Player party worker should be able to accept a durable guard contract alongside waiter")
		_restore_waiter_validation_service_config(service_area, original_service_delay, original_prompt_interval, original_prompt_jitter)
		return
	var waiter_contract := _contract_for_job(bridge.call("get_actor_job_contracts", player), "bar_server")
	var guard_contract := _contract_for_job(bridge.call("get_actor_job_contracts", player), "bar_guard")
	if waiter_contract.is_empty() or guard_contract.is_empty():
		_fail("Accepted waiter and guard jobs should both appear as Mira job contracts")
		_restore_waiter_validation_service_config(service_area, original_service_delay, original_prompt_interval, original_prompt_jitter)
		return
	var jobs: Array = provider.get("jobs")
	var server_job = jobs[server_job_index]
	var pay_interval := maxf(float(server_job.get("pay_interval_seconds")), 0.01)
	player.global_position = service_area.global_position
	var record: Dictionary = provider.call("_get_worker_record", player)
	var owed_before_passive := int(record.get("owed_currency", 0))
	provider.call("process_contracts", pay_interval, pay_interval)
	record = provider.call("_get_worker_record", player)
	if int(record.get("owed_currency", 0)) - owed_before_passive < int(server_job.get("pay_per_interval")):
		_fail("Player party waiter jobs should accrue base wages while Mira is listening in the bar")
	var owed_after_passive := int(record.get("owed_currency", 0))
	var guard_job = provider.call("start_contract_shift", player, guard_contract)
	if guard_job != null:
		provider.call("process_contracts", pay_interval, pay_interval * 2.0)
		record = provider.call("_get_worker_record", player)
		if int(record.get("owed_currency", 0)) != owed_after_passive:
			_fail("Player party waiter base wages should not accrue while Mira is actively working another job")
		provider.call("pause_worker_job", player, false)
	var jobs_window = CHARACTER_JOBS_WINDOW_SCRIPT.new()
	root.add_child(jobs_window)
	jobs_window.call("setup", _scene)
	jobs_window.call("show_for_actor", player)
	var window_contracts: Array = jobs_window.call("_get_contracts")
	if _contract_for_job(window_contracts, "bar_server").is_empty() or _contract_for_job(window_contracts, "bar_guard").is_empty():
		_fail("Mira's Jobs window should show accepted waiter and guard contracts")
	jobs_window.queue_free()
	player.set_move_target(player.global_position + Vector3(1.0, 0.0, 0.0), true)
	if bridge.call("get_actor_job_contracts", player).size() < 2:
		_fail("Player movement orders should not remove durable job contracts")
	player.call("cancel_ai_job")
	player.set("_current_order_type", 0)
	player.set("_order_was_player_issued", false)
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
	service_area.set("waiter_service_delay_seconds", 0.0)
	if not _seat_actor_for_waiter_validation(customer, seat):
		_fail("Player waiter job validation customer should be seated before service")
	else:
		var waiter_ready_status: Dictionary = provider.call("get_contract_work_status", player, waiter_contract)
		if not bool(waiter_ready_status.get("actionable", false)):
			_fail("Player waiter job should become actionable when an NPC customer order is ready")
		var utility_adapter = AI_UTILITY_ADAPTER_SCRIPT.new()
		utility_adapter.setup()
		if not bool(utility_adapter.run_actor_decision(player)):
			var debug_context = utility_adapter.build_context(player)
			var debug_decision = utility_adapter.selector.decide(debug_context, utility_adapter.profile, utility_adapter.target_selector)
			var adapter_bridge = utility_adapter.call("_get_gecs_world", player)
			var adapter_contract_count := 0
			var contract_debug: Array[String] = []
			if adapter_bridge != null and adapter_bridge.has_method("get_actor_job_contracts"):
				var adapter_contracts: Array = adapter_bridge.call("get_actor_job_contracts", player)
				adapter_contract_count = adapter_contracts.size()
				for contract_debug_data in adapter_contracts:
					if not (contract_debug_data is Dictionary):
						continue
					var contract_debug_dict: Dictionary = contract_debug_data
					var resolved_provider = utility_adapter.call("_resolve_contract_provider", player, contract_debug_dict)
					var status_debug: Dictionary = provider.call("get_contract_work_status", player, contract_debug_dict)
					contract_debug.append("%s next=%.2f resolved=%s actionable=%s reason=%s" % [str(contract_debug_dict.get("job_id", "")), float(contract_debug_dict.get("next_shift_time", 0.0)), str(resolved_provider != null), str(status_debug.get("actionable", false)), str(status_debug.get("reason", ""))])
			_fail("Utility AI should start the player waiter contract when an NPC customer order is ready: goal=%s sim=%.2f work=%.2f targets=%d contracts=%d bridge=%s details=%s active=%s" % [str(debug_decision.selected_goal_id), debug_context.sim_time, debug_context.get_fact(&"assigned_work_available", 0.0), debug_context.get_targets(&"work_provider").size(), adapter_contract_count, str(adapter_bridge.get_path() if adapter_bridge != null else NodePath()), str(contract_debug), str(player.call("get_ai_debug_snapshot"))])
		player.global_position = service_area.call("get_waiter_customer_service_position", player, seat)
		provider.call("process_jobs", 0.1, 1.0)
		var claimed_assignment: Dictionary = provider.call("_find_worker_slot", player)
		var claimed_slot: Dictionary = claimed_assignment.get("slot_state", {})
		var claimed_order_id := str(claimed_slot.get("target_service_order_id", ""))
		var claimed_state := str(claimed_slot.get("server_state", ""))
		utility_adapter.run_actor_decision(player)
		claimed_assignment = provider.call("_find_worker_slot", player)
		claimed_slot = claimed_assignment.get("slot_state", {})
		if claimed_order_id.is_empty() or str(claimed_slot.get("target_service_order_id", "")) != claimed_order_id or str(claimed_slot.get("server_state", "")) != claimed_state:
			_fail("Utility AI re-decisions should not pause and restart an already-claimed player waiter order")
		record = provider.call("_get_worker_record", player)
		var owed_before := int(record.get("owed_currency", 0))
		var charisma_xp_before := float(player.get_skill_xp(SkillRules.ATTRIBUTE_CHARISMA))
		_complete_player_waiter_order(provider, service_area, player, seat, 2.0, charisma_xp_before)
		var charisma_xp_delta := float(player.get_skill_xp(SkillRules.ATTRIBUTE_CHARISMA)) - charisma_xp_before
		if charisma_xp_delta <= 0.0:
			var active_assignment: Dictionary = provider.call("_find_worker_slot", player)
			var active_slot: Dictionary = active_assignment.get("slot_state", {})
			var service_position: Vector3 = service_area.call("get_waiter_customer_service_position", player, seat)
			_fail("Player party waiter jobs should complete NPC customer service events and award service XP, state=%s elapsed=%.2f distance=%.2f blocker=%s" % [str(active_slot.get("server_state", "")), float(active_slot.get("server_state_elapsed", 0.0)), player.global_position.distance_to(service_position), str(active_slot.get("last_ai_blocker", ""))])
		record = provider.call("_get_worker_record", player)
		if int(record.get("owed_currency", 0)) < owed_before:
			_fail("Player party waiter order completion should not lose owed wages")
		var xp_after_completion := float(player.get_skill_xp(SkillRules.ATTRIBUTE_CHARISMA))
		var owed_after_completion := int(record.get("owed_currency", 0))
		provider.call("process_jobs", 1.0, 20.0)
		record = provider.call("_get_worker_record", player)
		if float(player.get_skill_xp(SkillRules.ATTRIBUTE_CHARISMA)) != xp_after_completion or int(record.get("owed_currency", 0)) != owed_after_completion:
			_fail("Repeated waiter ticks after completion should not award duplicate Charisma XP or pay")
		if not bool(service_area.call("_is_seat_on_waiter_order_cooldown", seat)):
			_fail("The same served table should enter a cooldown after player-party waiter service")
	if bridge.call("get_actor_job_contracts", player).size() < 2:
		_fail("Completing a player-party waiter order should not remove waiter or guard contracts")
	provider.call("pause_worker_job", player, false)
	customer.stop_seat_assignment()
	_restore_waiter_validation_service_config(service_area, original_service_delay, original_prompt_interval, original_prompt_jitter)


func _complete_player_waiter_order(provider: Node, service_area: Node, worker: HumanoidCharacter, seat, start_time: float, xp_before: float) -> void:
	var sim_time := start_time
	for _attempt in range(8):
		var assignment: Dictionary = provider.call("_find_worker_slot", worker)
		var slot_state: Dictionary = assignment.get("slot_state", {})
		var state := str(slot_state.get("server_state", "idle"))
		var target_seat = slot_state.get("target_service_seat")
		if target_seat == null or not is_instance_valid(target_seat):
			target_seat = seat
		if state == "to_barkeeper" or state == "waiting_at_bar":
			worker.global_position = service_area.call("get_barkeeper_order_position", worker)
		else:
			worker.global_position = service_area.call("get_waiter_customer_service_position", worker, target_seat)
		provider.call("process_jobs", 1.5, sim_time)
		sim_time += 1.5
		if float(worker.get_skill_xp(SkillRules.ATTRIBUTE_CHARISMA)) > xp_before and str(slot_state.get("server_state", "")) == "idle":
			return


func _validate_waiter_charisma_xp_curve(provider: Node, job, worker: HumanoidCharacter) -> void:
	worker.set_skill_level(SkillRules.ATTRIBUTE_CHARISMA, 1)
	var novice_chance := float(provider.call("_server_order_charisma_chance", job, worker))
	if absf(novice_chance - 0.272) > 0.001:
		_fail("Level 1 waiter Charisma check should start as a low chance, got %.3f" % novice_chance)
	var novice_success_xp := float(provider.call("_server_order_charisma_xp", job, novice_chance, true))
	var novice_failure_xp := float(provider.call("_server_order_charisma_xp", job, novice_chance, false))
	if absf(novice_success_xp - 6.0) > 0.01 or absf(novice_failure_xp - 2.25) > 0.01:
		_fail("Level 1 waiter checks should use half-scale low-chance XP, success=%.2f fail=%.2f" % [novice_success_xp, novice_failure_xp])
	worker.set_skill_level(SkillRules.ATTRIBUTE_CHARISMA, 30)
	var skilled_chance := float(provider.call("_server_order_charisma_chance", job, worker))
	if skilled_chance < SkillRules.CHECK_CHANCE_HIGH_MAX:
		_fail("Level 30 waiter Charisma check should be Very High, got %.3f" % skilled_chance)
	var skilled_success_xp := float(provider.call("_server_order_charisma_xp", job, skilled_chance, true))
	if absf(skilled_success_xp - 0.25) > 0.01:
		_fail("Very High waiter checks should become tiny XP, got %.2f" % skilled_success_xp)
	worker.set_skill_level(SkillRules.ATTRIBUTE_CHARISMA, 1)


func _restore_waiter_validation_service_config(service_area: Node, service_delay: float, prompt_interval: float, prompt_jitter: float) -> void:
	if service_area == null:
		return
	service_area.set("waiter_service_delay_seconds", service_delay)
	service_area.set("waiter_order_prompt_interval_seconds", prompt_interval)
	service_area.set("waiter_order_prompt_jitter_seconds", prompt_jitter)


func _seat_actor_for_waiter_validation(actor: HumanoidCharacter, seat) -> bool:
	if actor == null or seat == null:
		return false
	if seat.has_method("get_sitter"):
		var sitter = seat.call("get_sitter")
		if sitter != null and sitter != actor and sitter.has_method("stop_seat_assignment"):
			sitter.call("stop_seat_assignment")
	actor.stop_seat_assignment()
	if seat.has_method("get_interaction_position"):
		actor.global_position = seat.call("get_interaction_position", actor)
	actor.assign_seat_target(seat, false)
	if actor.has_method("_process_seat_interaction"):
		actor.call("_process_seat_interaction")
	return actor.is_sitting()


func _complete_waiter_order(provider: Node, service_area: Node, worker: HumanoidCharacter, seat, start_time: float) -> void:
	worker.global_position = service_area.call("get_waiter_customer_service_position", worker, seat)
	provider.call("process_jobs", 0.1, start_time)
	worker.global_position = service_area.call("get_barkeeper_order_position", worker)
	provider.call("process_jobs", 0.1, start_time + 0.1)
	provider.call("process_jobs", 4.0, start_time + 4.1)
	worker.global_position = service_area.call("get_waiter_customer_service_position", worker, seat)
	provider.call("process_jobs", 0.1, start_time + 4.2)


func _configure_waiter_check(job, chance: float) -> void:
	job.set("server_charisma_base_chance", chance)
	job.set("server_charisma_chance_per_level", 0.0)
	job.set("server_charisma_min_chance", chance)
	job.set("server_charisma_max_chance", chance)


func _validate_player_waiter_order_action(bar: Node) -> void:
	var service_area := bar.get_node_or_null("BarServiceArea")
	var player := _scene.get_node_or_null("PartyMembers/Mira") as HumanoidCharacter
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
	player.stop_seat_assignment()
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
	var bar := SETTLEMENT_BAR_SCENE.instantiate()
	bar.name = "StandaloneStockBar"
	root.add_child(bar)
	bar.set("stock_source", "standalone_fallback")
	bar.set("standalone_stock_ratio", 0.25)
	if bar.has_method("_repair_authoring_tree"):
		bar.call("_repair_authoring_tree")
	await _wait_frames(10)
	var role := bar.get_node_or_null("Staff/Barkeeper/MerchantRole")
	if role == null:
		_fail("Standalone bar should create barkeeper merchant stock")
	else:
		var bread_stock := _merchant_initial_stock_quantity(role, BREAD_ITEM)
		if bread_stock != 3:
			_fail("Standalone bar should use standalone_stock_ratio for bread stock; expected=3 actual=%d" % bread_stock)
	root.remove_child(bar)
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
		_fail("Reusable bar should read guard defaults from settlement_bar.tscn before code fallbacks")
	var scene_bar := SETTLEMENT_BAR_SCENE.instantiate()
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
	if not waiters.has(bar.get_node_or_null("Staff/Waiter")):
		_fail("Generated waiter should be registered with BarServiceArea")
	var guards: Array = service_area.call("get_guard_characters")
	if not guards.has(assigned_guard):
		_fail("Assigned guard should be registered with BarServiceArea")
	if not guards.has(bar.get_node_or_null("Staff/Guard")):
		_fail("Generated guard should be registered with BarServiceArea")


func _indexed_name(base_name: String, index: int) -> String:
	return base_name if index == 0 else "%s%d" % [base_name, index + 1]


func _role_from_display_name(display_name: String) -> String:
	var normalized := display_name.to_lower()
	for role in ["barkeeper", "waiter", "guard", "barber"]:
		if normalized.ends_with("(%s)" % role):
			return role
	return ""


func _strip_role_suffix(display_name: String) -> String:
	var result := display_name.strip_edges()
	for role in ["barkeeper", "waiter", "guard", "barber"]:
		var suffix := " (%s)" % role
		if result.to_lower().ends_with(suffix):
			return result.substr(0, result.length() - suffix.length()).strip_edges()
	return result


func _collect_settlement_townies(path: String) -> Array[HumanoidCharacter]:
	var townies: Array[HumanoidCharacter] = []
	var root_node := _scene.get_node_or_null(path)
	if root_node == null:
		return townies
	for child in root_node.get_children():
		if child is HumanoidCharacter:
			townies.append(child as HumanoidCharacter)
	return townies


func _ensure_validation_townie_visitors(bar: Node, excluded: Array, visitors: Array[HumanoidCharacter], required_count: int) -> void:
	if visitors.size() >= required_count:
		return
	var settlement = bar.call("_get_ancestor_settlement") if bar != null and bar.has_method("_get_ancestor_settlement") else null
	if settlement == null:
		return
	var resident_root = settlement.get_node_or_null(settlement.get("resident_root_path"))
	if resident_root == null:
		return
	while visitors.size() < required_count:
		var actor := CharacterBody3D.new()
		actor.name = "ValidationTownie%d" % (visitors.size() + 1)
		actor.set_script(FACTION_HUMANOID_SCRIPT)
		actor.set("member_name", "Validation Townie %d" % (visitors.size() + 1))
		actor.set("stable_id", "validation.townie.%d" % (visitors.size() + 1))
		actor.set("faction_name", "Farmers")
		actor.set("squad_name", "FarmerCrossing")
		resident_root.add_child(actor)
		if actor is HumanoidCharacter and not excluded.has(actor) and bool(bar.call("can_actor_visit_facility", actor)):
			visitors.append(actor as HumanoidCharacter)


func _collect_townie_visitors(bar: Node, excluded: Array) -> Array[HumanoidCharacter]:
	var visitors: Array[HumanoidCharacter] = []
	var settlement = bar.call("_get_ancestor_settlement") if bar != null and bar.has_method("_get_ancestor_settlement") else null
	if settlement == null:
		return visitors
	var resident_root = settlement.get_node_or_null(settlement.get("resident_root_path"))
	_collect_townie_visitors_recursive(resident_root, bar, excluded, visitors)
	return visitors


func _collect_townie_visitors_recursive(root: Node, bar: Node, excluded: Array, visitors: Array[HumanoidCharacter]) -> void:
	if root == null:
		return
	for child in root.get_children():
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


func _flat_vector(value: Vector3) -> Vector3:
	return Vector3(value.x, 0.0, value.z)


func _get_gecs_world() -> Node:
	return get_first_node_in_group("gecs_world_controller")


func _wait_frames(frame_count: int) -> void:
	for _index in range(frame_count):
		await process_frame


func _fail(message: String) -> void:
	_failures.append(message)
