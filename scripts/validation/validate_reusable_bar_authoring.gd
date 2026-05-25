extends SceneTree

const TWO_TOWNS_SCENE := preload("res://scenes/test_levels/two_towns_road_test.tscn")
const SETTLEMENT_BAR_SCENE := preload("res://scenes/world_sim/settlement_bar.tscn")
const STOOL_SCENE := preload("res://scenes/world/props/stool_chair.tscn")
const BREAD_ITEM := preload("res://resources/items/bread.tres")
const FOOD_ITEM := preload("res://resources/items/food.tres")
const FARMER_NAME_PROFILE := preload("res://resources/world_sim/population_name_profiles/farmer_names.tres")
const BARBER_CONVERSATION := preload("res://resources/conversations/barber_services.tres")

var _failures: Array[String] = []
var _scene: Node


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	_scene = TWO_TOWNS_SCENE.instantiate()
	root.add_child(_scene)
	await _wait_frames(120)
	_validate_bread_inventory_shape()
	_validate_demo_starts_without_bar()
	await _validate_operator_instantiated_bar()
	if _failures.is_empty():
		print("REUSABLE_BAR_AUTHORING_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("REUSABLE_BAR_AUTHORING_FAILED count=%d" % _failures.size())
	quit(1)


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


func _validate_operator_instantiated_bar() -> void:
	var bars := _scene.get_node_or_null("Settlements/FarmerCrossing/Bars")
	var assigned_waiter := _scene.get_node_or_null("Settlements/FarmerCrossing/Residents/FarmerA") as HumanoidCharacter
	var assigned_guard := _scene.get_node_or_null("Settlements/FarmerCrossing/Residents/FarmerB") as HumanoidCharacter
	if bars == null or assigned_waiter == null or assigned_guard == null:
		_fail("Could not find bar container or assigned NPCs for reusable bar validation")
		return
	var waiter_parent := assigned_waiter.get_parent()
	var guard_parent := assigned_guard.get_parent()
	var bar := SETTLEMENT_BAR_SCENE.instantiate()
	bar.name = "OperatorBar"
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
	_validate_bar_loiter_capacity(bar, assigned_waiter, assigned_guard)
	_validate_barber_seating(bar)
	_validate_seated_talk_range(bar)
	_validate_barkeeper_stock(bar)
	_validate_waiter_order_job(bar, assigned_waiter)
	await _validate_standalone_bar_stock()
	_validate_scene_authored_layout_source(bar)
	_validate_layout_migration(bar)
	_validate_service_area(bar, assigned_waiter, assigned_guard)


func _validate_inferred_defaults(bar: Node) -> void:
	if str(bar.call("get_facility_id")) != "farmer_crossing.operator_bar":
		_fail("Reusable bar should infer facility_id from settlement id and node name")
	if str(bar.call("_get_staff_id_prefix")) != "npc.farmer_crossing.operator_bar":
		_fail("Reusable bar should infer staff_stable_id_prefix from facility_id")
	if str(bar.call("_get_bar_squad_name")) != "FarmerCrossing":
		_fail("Reusable bar should infer staff_squad_name from the parent settlement")
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
		if str(actor.get("squad_name")) != "FarmerCrossing":
			_fail("Generated bar staff should infer the settlement squad name")
		_validate_staff_perception(actor, role)
	if barber != null:
		if barber.get("conversation_definition") != BARBER_CONVERSATION:
			_fail("Generated barber should expose barber services")
		if not barber.has_method("get_barber_service_price"):
			_fail("Generated barber should use BarberHumanoid behavior")


func _validate_role_points(bar: Node) -> void:
	if bar.get_node_or_null("ServicePoints/BarkeeperCounterPoint") == null:
		_fail("Reusable bar should create a barkeeper point")
	if bar.get_node_or_null("ServicePoints/WaiterPoint") == null or bar.get_node_or_null("ServicePoints/WaiterPoint2") == null:
		_fail("Reusable bar should derive waiter points from waiter_count")
	if bar.get_node_or_null("GuardPosts/GuardPost") == null or bar.get_node_or_null("GuardPosts/GuardPost2") == null:
		_fail("Reusable bar should derive guard posts from guard_count")
	if bar.get_node_or_null("ServicePoints/BarberPoint") != null:
		_fail("Barber should be a normal idle bar occupant, not a generated service point")
	var loiter_point := bar.get_node_or_null("ActivityPoints/BarLoiterPoint")
	if loiter_point == null:
		_fail("Reusable bar should create one bar loiter activity point that scans Furniture seats")
	elif not loiter_point.has_method("assign_actor"):
		_fail("Bar loiter point should assign actors through bar seat discovery")
	else:
		if bool(loiter_point.get("exclusive")):
			_fail("Bar loiter point should not be a per-chair exclusive visitor point")
		if float(loiter_point.get("weight")) < 4.0:
			_fail("Bar loiter point should strongly prefer the bar enough to look alive")
		if float(loiter_point.get("assignment_min_seconds")) < 25.0 or float(loiter_point.get("assignment_max_seconds")) > 35.0:
			_fail("Bar loiter point should rotate townie visitors on roughly a 30 second cycle")
		var target_path = loiter_point.get("target_path")
		if typeof(target_path) == TYPE_NODE_PATH and not target_path.is_empty():
			_fail("Bar loiter point should scan seats instead of targeting one hardwired chair")
	var activity_points := bar.get_node_or_null("ActivityPoints")
	if activity_points != null:
		for point in activity_points.get_children():
			if str(point.name).begins_with("VisitorPoint"):
				_fail("Reusable bar should not generate per-chair VisitorPoint nodes")
	for path in ["ServicePoints/BarkeeperCounterPoint", "ServicePoints/WaiterPoint", "GuardPosts/GuardPost", "ActivityPoints/BarLoiterPoint"]:
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
	var loiter_actor := bar.get_node_or_null("Staff/Guard") as HumanoidCharacter
	if loiter_actor != null:
		loiter_actor.stop_seat_assignment()
		if not bool(bar.call("assign_loitering_actor", loiter_actor, direct_seat.global_position)):
			_fail("Bar loitering should assign visitors by scanning open Furniture seats")
		elif direct_seat.has_method("get_sitter") and direct_seat.call("get_sitter") != loiter_actor:
			_fail("Bar loitering should use the copied direct Furniture seat without a per-chair VisitorPoint")
		loiter_actor.stop_seat_assignment()
		var empty_furniture := Node3D.new()
		empty_furniture.name = "EmptyValidationFurniture"
		bar.add_child(empty_furniture)
		var old_furniture_root = bar.get("furniture_root_path")
		bar.set("furniture_root_path", NodePath("EmptyValidationFurniture"))
		var old_position := loiter_actor.global_position
		if bool(bar.call("assign_loitering_actor", loiter_actor, old_position + Vector3(5.0, 0.0, 5.0))):
			_fail("Bar loitering should reject visitors when no Furniture chair is open")
		if loiter_actor.global_position.distance_to(old_position) > 0.01:
			_fail("Rejected bar loitering actor should not be moved to a fallback marker")
		bar.set("furniture_root_path", old_furniture_root)
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


func _validate_bar_loiter_capacity(bar: Node, assigned_waiter: HumanoidCharacter, assigned_guard: HumanoidCharacter) -> void:
	var loiter_point := bar.get_node_or_null("ActivityPoints/BarLoiterPoint")
	if loiter_point == null:
		_fail("Reusable bar should have a bar loiter point for visitor capacity validation")
		return
	if assigned_waiter != null and bool(loiter_point.call("is_available_for", assigned_waiter)):
		_fail("Assigned waiter should not count as a normal townie bar visitor")
	if assigned_guard != null and bool(loiter_point.call("is_available_for", assigned_guard)):
		_fail("Assigned guard should not count as a normal townie bar visitor")
	var party_member := _scene.get_node_or_null("PartyMembers/Mira") as HumanoidCharacter
	if party_member != null and bool(loiter_point.call("is_available_for", party_member)):
		_fail("Party members should not count as normal townie bar visitors")
	var visitors := _collect_townie_visitors(bar, [assigned_waiter, assigned_guard])
	if visitors.size() < 3:
		_fail("Reusable bar visitor capacity validation needs at least three normal townies")
		return
	var original_capacity := int(bar.get("visitor_capacity"))
	bar.set("visitor_capacity", 2)
	if bar.has_method("_repair_authoring_tree"):
		bar.call("_repair_authoring_tree")
	loiter_point = bar.get_node_or_null("ActivityPoints/BarLoiterPoint")
	var first: HumanoidCharacter = visitors[0]
	var second: HumanoidCharacter = visitors[1]
	var third: HumanoidCharacter = visitors[2]
	for visitor in [first, second, third]:
		visitor.stop_seat_assignment()
	if not bool(loiter_point.call("assign_actor", first)):
		_fail("First normal townie should be able to visit an empty bar")
	if not bool(loiter_point.call("assign_actor", second)):
		_fail("Second normal townie should be able to fill the bar visitor capacity")
	var first_seat := _seat_for_sitter(bar, first)
	if int(loiter_point.call("get_active_visitor_count")) != 2:
		_fail("Bar loiter point should track exactly visitor_capacity active townie visitors")
	var third_position := third.global_position
	if bool(loiter_point.call("is_available_for", third)):
		_fail("Bar loiter point should be unavailable to extra townies once visitor_capacity is full")
	if bool(loiter_point.call("assign_actor", third)):
		_fail("Bar loiter point should reject extra townies instead of mosh-pitting at the marker")
	if third.global_position.distance_to(third_position) > 0.01:
		_fail("Rejected townie should not be moved toward the full bar")
	loiter_point.call("release_actor", first)
	if first.is_sitting():
		_fail("Released bar visitor should stand up and free the chair")
	if first_seat != null:
		var first_local_stand := first_seat.to_local(first.global_position)
		if first_local_stand.z > -0.35:
			_fail("Released bar visitor should stand on the aisle side of the chair, local=%s" % first_local_stand)
	if bool(loiter_point.call("is_available_for", first)):
		_fail("Released bar visitor should have a short cooldown before returning")
	if not bool(loiter_point.call("is_available_for", third)) or not bool(loiter_point.call("assign_actor", third)):
		_fail("A different townie should be able to take the freed bar visitor slot")
	loiter_point.call("release_actor", second)
	loiter_point.call("release_actor", third)
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


func _validate_waiter_order_job(bar: Node, worker: HumanoidCharacter) -> void:
	if worker == null:
		return
	var service_area := bar.get_node_or_null("BarServiceArea")
	var provider := bar.get_node_or_null("Staff/Barkeeper/JobProvider")
	var customer := bar.get_node_or_null("Staff/Guard") as HumanoidCharacter
	var seat = null
	if service_area != null:
		var seats: Array = service_area.call("_collect_seat_nodes")
		if not seats.is_empty():
			seat = seats[0]
	if service_area == null or provider == null or customer == null or seat == null:
		_fail("Waiter order validation could not find service area, provider, customer, or seat")
		return
	service_area.set("waiter_service_delay_seconds", 0.0)
	if seat.has_method("get_interaction_position"):
		customer.global_position = seat.call("get_interaction_position", customer)
	customer.assign_seat_target(seat, false)
	if customer.has_method("_process_seat_interaction"):
		customer.call("_process_seat_interaction")
	if not customer.is_sitting():
		_fail("Waiter order validation customer should be seated before service")
		return
	var server_job_index := _server_shift_job_index(provider)
	if server_job_index < 0:
		_fail("Bar job provider should expose a server_shift job")
		customer.stop_seat_assignment()
		return
	_validate_waiter_job_offer_text(provider, server_job_index)
	var before_xp := float(worker.get_skill_xp(SkillRules.ATTRIBUTE_CHARISMA))
	var assignment: Dictionary = provider.call("_assign_worker_to_open_slot", worker, server_job_index)
	if not bool(assignment.get("allowed", false)):
		_fail("Waiter should be able to take the server_shift job for order validation: %s" % str(assignment.get("reason", "")))
		customer.stop_seat_assignment()
		return
	worker.global_position = service_area.call("get_waiter_customer_service_position", worker, seat)
	provider.call("process_jobs", 0.1, 0.1)
	worker.global_position = service_area.call("get_barkeeper_order_position", worker)
	provider.call("process_jobs", 0.1, 0.2)
	provider.call("process_jobs", 2.0, 2.2)
	worker.global_position = service_area.call("get_waiter_customer_service_position", worker, seat)
	provider.call("process_jobs", 0.1, 2.3)
	var record: Dictionary = provider.call("_get_worker_record", worker)
	if int(record.get("owed_currency", 0)) <= 0:
		_fail("Completed waiter orders should create per-order pay instead of passive wages")
	if float(worker.get_skill_xp(SkillRules.ATTRIBUTE_CHARISMA)) <= before_xp:
		_fail("Completed waiter orders should award small charisma XP")
	provider.call("pause_worker_job", worker, false)
	customer.stop_seat_assignment()


func _server_shift_job_index(provider: Node) -> int:
	var jobs: Array = provider.get("jobs")
	for index in range(jobs.size()):
		var job = jobs[index]
		if job != null and str(job.get("algorithm_id")) == "server_shift":
			return index
	return -1


func _validate_waiter_job_offer_text(provider: Node, job_index: int) -> void:
	var jobs: Array = provider.get("jobs")
	var job = jobs[job_index] if job_index >= 0 and job_index < jobs.size() else null
	var offer := str(provider.call("_build_job_offer_text", job)).to_lower()
	if not offer.contains("per completed order"):
		_fail("Waiter job offer should describe per-order pay")
	if offer.contains("every 20 seconds") or offer.contains("every %d seconds" % int(job.get("pay_interval_seconds"))):
		_fail("Waiter job offer should not describe passive interval pay")
	var accept := str(provider.call("_build_job_accept_text", job)).to_lower()
	if accept.contains("every"):
		_fail("Waiter job accept text should not imply interval pay")


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
		if actor != null and not excluded.has(actor) and bool(bar.call("can_actor_visit_as_townie", actor)):
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


func _wait_frames(frame_count: int) -> void:
	for _index in range(frame_count):
		await process_frame


func _fail(message: String) -> void:
	_failures.append(message)
