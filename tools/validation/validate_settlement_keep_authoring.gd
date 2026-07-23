extends SceneTree

const KEEP_SCENE_PATH := "res://features/settlements/bridge/settlement_keep.tscn"
const KEEP_SOURCE_PATH := "res://features/settlements/bridge/settlement_keep.gd"
const KEEP_RULES_PATH := "res://features/settlements/resources/furnishing/keep.tres"
const FURNISHER_PATH := "res://features/world/projection/props/furnishing/facility_furnisher.gd"
const DESK_PATH := "res://features/world/projection/props/furniture/ruler_planning_desk.tscn"
const SEAT_PATH := "res://features/world/projection/props/furniture/ruler_seat.tscn"
const POST_PATH := "res://features/settlements/bridge/venues/facility_guard_post.tscn"
const OFFICE_PATH := "res://features/world/projection/props/furnishing/vignettes/ruler_office.tscn"
const DEFAULT_SHELL_PATH := "res://features/world/projection/buildings/shells/modular/medium_wood_hall.tscn"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_sources()
	_validate_recipe_authoring()
	var keep_scene := load(KEEP_SCENE_PATH) as PackedScene
	var keep = keep_scene.instantiate() if keep_scene != null else null
	if keep == null:
		_fail("Settlement Keep scene must instantiate")
		_finish()
		return
	root.add_child(keep)
	await process_frame
	_validate_empty_template(keep)
	_validate_empty_discovery(keep)
	_validate_nested_discovery(keep)
	_validate_actor_subtree_exclusion(keep)
	_validate_effective_ownership(keep)
	_validate_missing_furniture(keep_scene)
	_validate_furnish_output(keep)
	keep.queue_free()
	await process_frame
	_finish()


func _validate_sources() -> void:
	var source := FileAccess.get_file_as_string(KEEP_SOURCE_PATH)
	var scene := FileAccess.get_file_as_string(KEEP_SCENE_PATH)
	for forbidden in ["func _process(", "auto_create_planning_table", "auto_create_ruler_chair", "@export_range(0, 12, 1) var guard_post_count", "keep_generated", "_ensure_planning", "_ensure_ruler", "_ensure_guard", "Furniture/PlanningTable", "Furniture/RulerChair", "mayor_chair", "raider_chair", "bar_guard_post"]:
		_assert(not source.contains(forbidden), "Keep source retains forbidden legacy symbol: %s" % forbidden)
	for forbidden in ["PlanningTable", "RulerChair", "keep_generated", "mayor_chair", "raider_chair", "bar_guard_post"]:
		_assert(not scene.contains(forbidden), "Keep template must not serialize %s" % forbidden)
	_assert(scene.contains("[node name=\"GuardPosts\"") and scene.contains("[node name=\"GuardPost2\""), "Keep template must author visible guard stand spots")
	_assert(source.contains("refresh_facility_capabilities"), "Keep must expose explicit capability refresh")
	_assert(source.contains("node is WorldActor"), "Keep discovery must skip actor subtrees")
	_assert(source.contains("supports_facility_role"), "Keep discovery must use facility role capability")
	_assert(source.contains("ruler.get_interaction()") and source.contains("interaction.sit_at_seat_immediately(seat)"), "Keep must seat its ruler through InteractionCapability")
	_assert(not source.contains("ruler.has_method(\"sit_at_seat_immediately\")"), "Keep must not call removed actor-owned seating API")
	var controller_source := FileAccess.get_file_as_string("res://features/settlements/bridge/settlement_controller.gd")
	var slot_source := FileAccess.get_file_as_string("res://features/settlements/sim/c_game_staff_slot.gd")
	_assert(not controller_source.contains("owner_path") and not slot_source.contains("owner_path") and not slot_source.contains("worker_path"), "durable staff state must not store scene paths")
	_assert(controller_source.contains("owner_id") and slot_source.contains("owner_id"), "durable staff state must resolve role owners by stable ID")


func _validate_recipe_authoring() -> void:
	var rules = load(KEEP_RULES_PATH)
	_assert(rules != null, "Keep furnish rules must resolve")
	if rules == null:
		return
	_assert(rules.required_cluster_scenes.size() == 1, "Keep must require exactly one office vignette")
	if rules.required_cluster_scenes.size() == 1:
		_assert(rules.required_cluster_scenes[0].resource_path == OFFICE_PATH, "Keep required cluster must be ruler_office")
	_assert(rules.utility_scenes.is_empty(), "Keep furnishing must never generate or move guard stand spots")
	var office_scene := load(OFFICE_PATH) as PackedScene
	var office = office_scene.instantiate() if office_scene != null else null
	_assert(office != null, "Ruler office vignette must instantiate")
	if office == null:
		return
	var role_desk := _find_role_node(office, "ruler", true)
	var role_seat := _find_role_node(office, "ruler", false)
	_assert(role_desk != null, "Ruler office must contain a ruler-role workstation")
	_assert(role_seat != null, "Ruler office must contain a ruler-role seat")
	_assert(office.get("footprint_meters") == Vector2(3.2, 3.4), "Ruler office must keep its authored footprint")
	office.free()


func _validate_empty_template(keep: Node) -> void:
	var furniture := keep.get_node_or_null("Furniture")
	_assert(furniture != null and furniture.get_child_count() == 0, "Keep template Furniture must be empty")
	_assert(keep.get_node_or_null("Staff") != null and keep.get_node("Staff").get_child_count() == 0, "Keep template Staff must be empty")
	var guard_post := keep.get_node_or_null("GuardPosts/GuardPost") as Node3D
	var guard_post_2 := keep.get_node_or_null("GuardPosts/GuardPost2") as Node3D
	_assert(guard_post != null and guard_post_2 != null, "Keep template must contain two authored guard stand spots")
	if guard_post != null and guard_post_2 != null:
		_assert(guard_post.transform.is_equal_approx(Transform3D(Basis(Vector3.UP, deg_to_rad(25.0)), Vector3(-4.4, 0.05, 3.9))), "GuardPost must preserve its reviewed transform")
		_assert(guard_post_2.transform.is_equal_approx(Transform3D(Basis(Vector3.UP, deg_to_rad(-25.0)), Vector3(4.4, 0.05, 3.9))), "GuardPost2 must preserve its reviewed transform")
	var building := keep.get_node_or_null("BuildingSlot/CurrentBuilding")
	_assert(building != null and building.scene_file_path == DEFAULT_SHELL_PATH, "Keep must start with the global medium wood hall shell")
	_assert(str(keep.get("door_access_policy")) == "private", "Keep must explicitly author private owner access")
	_assert(str(keep.call("get_property_owner_role_id")) == "ruler", "Keep door and property ownership must resolve through the ruler slot")
	_assert(building != null and str(building.get("access_state")) == "private", "Keep must stamp private access onto its neutral shell")


func _validate_empty_discovery(keep: Node) -> void:
	keep.call("refresh_facility_capabilities")
	_assert(keep.call("get_ruler_workstation") == null, "Empty furniture must have no ruler workstation")
	_assert((keep.call("get_ruler_seats") as Array).is_empty(), "Empty furniture must have no ruler seats")
	_assert((keep.call("get_guard_posts") as Array).size() == 2, "Empty furniture must retain authored guard stand spots")
	_assert(keep.get_node("Furniture").get_child_count() == 0, "Capability refresh must not generate furniture")


func _validate_nested_discovery(keep: Node) -> void:
	var furniture := keep.get_node("Furniture")
	var outer := Node3D.new()
	outer.name = "RenamedOfficeWing"
	var inner := Node3D.new()
	inner.name = "NestedCapabilityBucket"
	furniture.add_child(outer)
	outer.add_child(inner)
	var desk := (load(DESK_PATH) as PackedScene).instantiate()
	desk.name = "NotAPlanningTable"
	inner.add_child(desk)
	var seat := (load(SEAT_PATH) as PackedScene).instantiate()
	seat.name = "NotARulerChair"
	inner.add_child(seat)
	var posts := Node3D.new()
	posts.name = "ArbitraryNestedPosts"
	outer.add_child(posts)
	for index in 2:
		var post := (load(POST_PATH) as PackedScene).instantiate()
		post.name = "WatchMarker%d" % index
		posts.add_child(post)
	keep.call("refresh_facility_capabilities")
	_assert(keep.call("get_ruler_workstation") == desk, "Renamed nested ruler workstation must be discovered")
	_assert((keep.call("get_ruler_seats") as Array).has(seat), "Renamed nested ruler seat must be discovered")
	_assert((keep.call("get_guard_posts") as Array).size() == 4, "Authored and nested facility guard posts must be discovered")
	var record: Dictionary = keep.call("get_facility_record", "validation")
	_assert(int(record.get("ruler_workstation_count", 0)) == 1, "Facility record must report discovered ruler workstation")
	_assert(int(record.get("ruler_seat_count", 0)) == 1, "Facility record must report discovered ruler seat")
	_assert(int(record.get("guard_post_count", 0)) == 4, "Facility record must report discovered posts")


func _validate_actor_subtree_exclusion(keep: Node) -> void:
	var actor_script := load("res://features/actors/bridge/world_actor.gd")
	var actor = actor_script.new()
	var hidden_post := (load(POST_PATH) as PackedScene).instantiate()
	actor.add_child(hidden_post)
	var before := (keep.call("get_guard_posts") as Array).size()
	keep.call("_collect_facility_capabilities", actor)
	_assert((keep.call("get_guard_posts") as Array).size() == before, "Furniture under WorldActor must be ignored")
	actor.free()


func _validate_effective_ownership(keep: Node) -> void:
	var settlement_definition_script := load("res://features/world_sim/resources/settlement_definition.gd")
	var definition = settlement_definition_script.new()
	definition.set("faction_definition", load("res://features/factions/resources/factions/farmers.tres"))
	var anchor := SettlementAnchor.new()
	anchor.set("settlement_definition", definition)
	keep.get_parent().remove_child(keep)
	anchor.add_child(keep)
	root.add_child(anchor)
	var expected := str(definition.get("faction_definition").get("faction_id"))
	_assert(not expected.is_empty(), "Ownership fixture faction must resolve")
	_assert(str(keep.call("get_property_owner_faction")) == expected, "Keep property owner faction must inherit the effective settlement faction")
	var record: Dictionary = keep.call("get_facility_record", "validation")
	_assert(str(record.get("owner_faction_id", "")) == expected, "Keep facility record must use effective inherited faction")
	anchor.remove_child(keep)
	root.add_child(keep)
	anchor.queue_free()


func _validate_missing_furniture(keep_scene: PackedScene) -> void:
	var keep = keep_scene.instantiate()
	var furniture := keep.get_node_or_null("Furniture")
	if furniture != null:
		keep.remove_child(furniture)
		furniture.free()
	root.add_child(keep)
	keep.call("refresh_facility_capabilities")
	_assert(keep.get_node_or_null("Furniture") == null, "Missing Furniture root must not be generated")
	_assert(keep.call("get_ruler_workstation") == null and (keep.call("get_guard_posts") as Array).size() == 2, "Missing Furniture root must retain authored guard stand spots")
	keep.queue_free()


func _validate_furnish_output(keep: Node) -> void:
	var building := keep.get_node_or_null("BuildingSlot/CurrentBuilding") as Node3D
	var rules = load(KEEP_RULES_PATH)
	var furnisher = load(FURNISHER_PATH).new()
	var placements: Array = furnisher.call("furnish", building, rules, 7)
	_assert(not placements.is_empty(), "Keep furnish pass must succeed: %s" % str(furnisher.call("last_error")))
	var office_count := 0
	for placement in placements:
		var scene: PackedScene = placement.get("scene")
		if scene != null and scene.resource_path == OFFICE_PATH:
			office_count += 1
	_assert(office_count == 1, "Keep furnish pass must place ruler office exactly once")
	_assert(placements.all(func(placement: Dictionary): return (placement.get("scene") as PackedScene).resource_path != POST_PATH), "Keep furnish pass must not place guard stand spots")


func _find_role_node(node: Node, role_id: String, workstation: bool) -> Node:
	if node.has_method("supports_facility_role") and bool(node.call("supports_facility_role", role_id)):
		if workstation and node.has_method("get_staff_stand_position"):
			return node
		if not workstation and node.has_method("claim_sitter"):
			return node
	for child in node.get_children():
		var found := _find_role_node(child, role_id, workstation)
		if found != null:
			return found
	return null


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("SETTLEMENT_KEEP_AUTHORING_OK")
	else:
		print("SETTLEMENT_KEEP_AUTHORING_FAILED count=%d" % _failures.size())
	quit(0 if _failures.is_empty() else 1)
