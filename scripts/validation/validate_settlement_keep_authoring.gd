extends SceneTree

const SETTLEMENT_KEEP_SCENE := preload("res://scenes/world_sim/settlement_keep.tscn")
const KEEP_BUILDING_SCENE := preload("res://scenes/world/buildings/settlement_keep_building.tscn")
const MAYOR_CHAIR_SCENE := preload("res://scenes/world/props/keep/mayor_chair.tscn")
const RAIDER_CHAIR_SCENE := preload("res://scenes/world/props/keep/raider_chair.tscn")
const RULER_CONVERSATION := preload("res://resources/conversations/town_ruler.tres")
const FARMER_APPEARANCE_PROFILE := preload("res://resources/world_sim/population_appearance_profiles/farmer_peasant.tres")
const FARMER_NAME_PROFILE := preload("res://resources/world_sim/population_name_profiles/farmer_names.tres")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var keep := SETTLEMENT_KEEP_SCENE.instantiate()
	keep.set("population_appearance_profile", FARMER_APPEARANCE_PROFILE)
	keep.set("population_name_profile", FARMER_NAME_PROFILE)
	root.add_child(keep)
	await process_frame
	await process_frame
	if keep == null:
		_fail("Settlement keep scene should instantiate")
	else:
		if str(keep.get("facility_type")) != "keep":
			_fail("Settlement keep should use keep facility_type")
		if keep.get_node_or_null("BuildingSlot/CurrentBuilding") == null:
			_fail("Settlement keep should auto-create a default keep hall building")
		else:
			_validate_keep_building(keep.get_node("BuildingSlot/CurrentBuilding"))
		if keep.get_node_or_null("Furniture/PlanningTable") == null:
			_fail("Settlement keep should include the authored planning table")
		elif keep.get_node_or_null("Furniture/PlanningTable/Model") == null:
			_fail("Planning table wrapper should instance the Meshy model")
		if keep.get_node_or_null("Furniture/RulerChair") == null:
			_fail("Settlement keep should include a ruler chair")
		elif not keep.get_node("Furniture/RulerChair").has_method("claim_sitter"):
			_fail("Ruler chair should be a sittable seat wrapper")
		elif str(keep.get_node("Furniture/RulerChair").get_meta("keep_chair_style", "")) != "mayor":
			_fail("Base keep ruler chair should be the mayor/throne style")
		if keep.get_node_or_null("Staff/Ruler") == null:
			_fail("Settlement keep should generate a ruler actor")
		elif keep.get_node("Staff/Ruler").get("conversation_definition") != RULER_CONVERSATION:
			_fail("Generated ruler should use the town ruler conversation")
		elif keep.get_node("Staff/Ruler").has_method("is_sitting") and not bool(keep.get_node("Staff/Ruler").call("is_sitting")):
			_fail("Generated ruler should sit in the ruler chair")
		else:
			_validate_ruler_seating(keep)
			_validate_profiled_staff_actor(keep.get_node("Staff/Ruler"), "Ruler", FARMER_NAME_PROFILE, "Generated ruler")
		if keep.get_node_or_null("Staff/Guard") == null or keep.get_node_or_null("Staff/Guard2") == null:
			_fail("Settlement keep should generate default guards")
		else:
			_validate_profiled_staff_actor(keep.get_node("Staff/Guard"), "guard", FARMER_NAME_PROFILE, "Generated guard")
			_validate_profiled_staff_actor(keep.get_node("Staff/Guard2"), "guard", FARMER_NAME_PROFILE, "Generated guard 2")
			_validate_guard_post_preserves_combat(keep, keep.get_node("Staff/Guard") as HumanoidCharacter, keep.get_node_or_null("Staff/Ruler") as HumanoidCharacter)
		if keep.get_node_or_null("GuardPosts/GuardPost") == null or keep.get_node_or_null("GuardPosts/GuardPost2") == null:
			_fail("Settlement keep should generate guard posts")
		elif not keep.get_node("GuardPosts/GuardPost").has_method("claim_worker"):
			_fail("Keep guard posts should use the bar-style guard post marker script")
		if keep.get_node_or_null("ActivityPoints") != null or keep.get_node_or_null("ServicePoints") != null or keep.get_node_or_null("Storage") != null or keep.get_node_or_null("JobProviders") != null:
			_fail("Settlement keep should not create unused generic roots")
		if not keep.has_method("get_facility_record"):
			_fail("Settlement keep should expose a facility record")
		else:
			var record: Dictionary = keep.call("get_facility_record", "test_settlement")
			if str(record.get("function_id", "")) != "keep":
				_fail("Settlement keep record should report keep function_id")
			if int(record.get("planning_table_count", 0)) != 1:
				_fail("Settlement keep record should report its planning table")
			if int(record.get("ruler_count", 0)) != 1:
				_fail("Settlement keep record should report its ruler")
			if int(record.get("guard_count", 0)) != 2:
				_fail("Settlement keep record should report default guards")
			if int(record.get("guard_post_count", 0)) != 2:
				_fail("Settlement keep record should report default guard posts")
			if record.has("audience_point_count"):
				_fail("Settlement keep record should not report audience points")
		_validate_dynamic_guard_post_count(keep)
		_validate_base_layout_is_serialized()
	_validate_wrappers()
	if _failures.is_empty():
		print("SETTLEMENT_KEEP_AUTHORING_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SETTLEMENT_KEEP_AUTHORING_FAILED count=%d" % _failures.size())
	quit(1)


func _fail(message: String) -> void:
	_failures.append(message)


func _validate_keep_building(building: Node) -> void:
	if str(building.get("display_name")) != "Keep Hall":
		_fail("Keep building should identify as Keep Hall")
	if str(building.get("access_mode")) != "public":
		_fail("Keep building should be public by default")
	var back_wall := building.get_node_or_null("BackWallMesh") as MeshInstance3D
	var wall_mesh := back_wall.mesh as BoxMesh if back_wall != null else null
	if wall_mesh == null or wall_mesh.size.y < 3.7:
		_fail("Keep hall walls should be roughly one-third taller than the current bar walls")
	if building.get_node_or_null("InteriorArea/InteriorAreaShape") == null:
		_fail("Keep building should have an interior area")
	building.call("set_visibility_for_camera", true, building.to_global(Vector3(0.0, 4.0, 8.0)), null)
	var floor_hit: Variant = building.call("project_click_to_active_level", building.to_global(Vector3(0.0, 8.0, 0.0)), -building.global_transform.basis.y.normalized())
	if not (floor_hit is Vector3):
		_fail("Hidden keep roof clicks should project onto the interior floor")
	elif absf(building.to_local(floor_hit as Vector3).y - 0.1) > 0.01:
		_fail("Hidden keep roof click projection should land near floor height, not roof height")


func _validate_wrappers() -> void:
	var building = KEEP_BUILDING_SCENE.instantiate()
	if building == null or not building.has_method("set_visibility_for_camera"):
		_fail("Keep building wrapper should instance as a WorldBuilding")
	if building != null:
		building.queue_free()
	var mayor_chair = MAYOR_CHAIR_SCENE.instantiate()
	if mayor_chair == null or not mayor_chair.has_method("claim_sitter") or mayor_chair.get_node_or_null("Model") == null:
		_fail("Mayor chair wrapper should be a sittable Meshy model")
	else:
		var model := mayor_chair.get_node("Model") as Node3D
		if model == null or absf(model.scale.x - 1.4) > 0.01:
			_fail("Mayor chair should be scaled to the intended throne size")
		if absf(float(mayor_chair.get("seated_yaw_offset_degrees"))) > 0.01:
			_fail("Mayor chair should seat the ruler facing out from the chair")
	if mayor_chair != null:
		mayor_chair.queue_free()
	var raider_chair = RAIDER_CHAIR_SCENE.instantiate()
	if raider_chair == null or not raider_chair.has_method("claim_sitter") or raider_chair.get_node_or_null("Model") == null:
		_fail("Raider chair wrapper should be a sittable Meshy model")
	else:
		var raider_model := raider_chair.get_node("Model") as Node3D
		if raider_model == null or absf(raider_model.scale.x - 1.35) > 0.01:
			_fail("Raider chair should be scaled up for the boss keep")
		if absf(float(raider_chair.get("seated_yaw_offset_degrees")) - 155.0) > 0.01:
			_fail("Raider chair should compensate for its visual facing offset")
	if raider_chair != null:
		raider_chair.queue_free()
	if RULER_CONVERSATION == null or str(RULER_CONVERSATION.get("conversation_id")) != "conv.town.ruler":
		_fail("Town ruler conversation should be available")


func _validate_base_layout_is_serialized() -> void:
	_assert_file_contains("res://scenes/world_sim/settlement_keep.tscn", "metadata/keep_generated", "Base keep scene should serialize editable generated layout metadata like the bar")
	_assert_file_contains("res://scenes/world_sim/settlement_keep.tscn", "parent=\"GuardPosts\"", "Base keep scene should serialize editable guard post markers")
	_assert_file_contains("res://scenes/world_sim/settlement_keep.tscn", "bar_guard_post.gd", "Base keep guard posts should use bar-style marker script")
	_assert_file_contains("res://scenes/world_sim/settlement_keep.tscn", "metadata/keep_last_default_transform = Transform3D(0.9998561, 0, -0.016963685", "Ruler chair metadata should preserve the authored rotation")
	_assert_file_does_not_contain("res://scenes/world_sim/settlement_keep.tscn", "AudiencePoint", "Base keep scene should not serialize audience points")
	_assert_file_does_not_contain("res://scenes/world_sim/settlement_keep.tscn", "activity_id = \"settlement_keep.audience", "Base keep scene should not serialize audience activities")
	_assert_file_does_not_contain("res://scenes/world_sim/settlement_keep.tscn", "[node name=\"ActivityPoints\"", "Base keep scene should not include unused ActivityPoints root")
	_assert_file_does_not_contain("res://scenes/world_sim/settlement_keep.tscn", "[node name=\"ServicePoints\"", "Base keep scene should not include unused ServicePoints root")
	_assert_file_does_not_contain("res://scenes/world_sim/settlement_keep.tscn", "[node name=\"Storage\"", "Base keep scene should not include unused Storage root")
	_assert_file_does_not_contain("res://scenes/world_sim/settlement_keep.tscn", "[node name=\"JobProviders\"", "Base keep scene should not include unused JobProviders root")
	_assert_file_does_not_contain("res://scenes/world_sim/settlement_keep.tscn", "[node name=\"Ruler\" type=\"CharacterBody3D\" parent=\"Staff\"]", "Base keep scene should not serialize the generated ruler actor")
	_assert_file_does_not_contain("res://scenes/world_sim/settlement_keep.tscn", "[node name=\"Guard\" type=\"CharacterBody3D\" parent=\"Staff\"]", "Base keep scene should not serialize generated guard actors")
	_assert_file_does_not_contain("res://scenes/world_sim/settlement_keep.tscn", "parent=\"Staff/Ruler\"", "Base keep scene should not serialize generated staff actor children")
	_assert_file_does_not_contain("res://scenes/world_sim/settlement_keep.tscn", "parent=\"Staff/Guard\"", "Base keep scene should not serialize generated guard actor children")
	_assert_file_does_not_contain("res://scenes/test_levels/two_towns_road_test.tscn", "Keeps/MayorHouse/GuardPosts", "Farmer keep should rely on generated guard posts instead of serialized children")
	_assert_file_does_not_contain("res://scenes/test_levels/two_towns_road_test.tscn", "Keeps/BossHut/GuardPosts", "Raider keep should rely on generated guard posts instead of serialized children")


func _validate_ruler_seating(keep: Node) -> void:
	var ruler := keep.get_node_or_null("Staff/Ruler") as Node3D
	var chair := keep.get_node_or_null("Furniture/RulerChair") as Node3D
	if ruler == null or chair == null or not chair.has_method("get_seat_position"):
		return
	var expected_position: Vector3 = chair.call("get_seat_position", ruler)
	if ruler.global_position.distance_to(expected_position) > 0.05:
		_fail("Generated ruler should sit on the ruler chair seat position")
	if chair.has_method("get_seat_rotation"):
		var expected_rotation: Vector3 = chair.call("get_seat_rotation", ruler)
		if _yaw_delta_abs(ruler.rotation.y, expected_rotation.y) > 0.02:
			_fail("Generated ruler should face the same direction as the mayor chair seat")


func _validate_profiled_staff_actor(actor: Node, expected_suffix: String, name_profile: Resource, label: String) -> void:
	if actor == null:
		_fail("%s should exist" % label)
		return
	if actor.get("appearance_data") == null:
		_fail("%s should use the settlement/faction appearance profile" % label)
	var display_name := str(actor.get("member_name"))
	var suffix := " (%s)" % expected_suffix
	if not display_name.ends_with(suffix):
		_fail("%s name should include role/title suffix %s" % [label, suffix])
	var base_name := _strip_role_suffix(display_name)
	if base_name in ["Ruler", "Mayor", "Boss", "Guard", "Mayor Guard", "Keep Guard"]:
		_fail("%s should not keep generic placeholder name '%s'" % [label, base_name])
	elif name_profile == null or not name_profile.has_method("contains_name") or not bool(name_profile.call("contains_name", base_name)):
		_fail("%s name '%s' should come from the population name profile" % [label, display_name])
	if not _actor_has_equipped_slot(actor, "chest"):
		_fail("%s should have clothing from the population appearance profile" % label)
	var perception := int(actor.call("get_skill_level", SkillRules.ATTRIBUTE_PERCEPTION)) if actor.has_method("get_skill_level") else 0
	var expected_min := 90 if expected_suffix == "guard" else 5
	var expected_max := 100 if expected_suffix == "guard" else 12
	if perception < expected_min or perception > expected_max:
		_fail("%s perception %d outside expected %d..%d" % [label, perception, expected_min, expected_max])


func _actor_has_equipped_slot(actor: Node, slot_name: String) -> bool:
	return actor != null and actor.has_method("get_equipped_item") and actor.call("get_equipped_item", slot_name) != null


func _strip_role_suffix(display_name: String) -> String:
	var result := display_name.strip_edges()
	var suffix_start := result.rfind(" (")
	if suffix_start >= 0 and result.ends_with(")"):
		return result.substr(0, suffix_start).strip_edges()
	return result


func _yaw_delta_abs(left: float, right: float) -> float:
	return absf(wrapf(left - right, -PI, PI))


func _assert_file_contains(path: String, needle: String, message: String) -> void:
	var contents := FileAccess.get_file_as_string(path)
	if not contents.contains(needle):
		_fail(message)


func _validate_dynamic_guard_post_count(keep: Node) -> void:
	keep.set("guard_post_count", 4)
	if keep.has_method("_repair_authoring_tree"):
		keep.call("_repair_authoring_tree")
	var post := keep.get_node_or_null("GuardPosts/GuardPost4")
	if post == null or not post.has_method("claim_worker"):
		_fail("Increasing keep guard_post_count should create bar-style guard post markers")


func _validate_guard_post_preserves_combat(keep: Node, guard: HumanoidCharacter, target: HumanoidCharacter) -> void:
	if keep == null or guard == null or target == null:
		_fail("Keep guard-post combat validation requires keep, guard, and target")
		return
	if not keep.has_method("_process_guard_post_assignment"):
		_fail("Keep should expose guard-post assignment for validation")
		return
	var original_transform := guard.global_transform
	guard.disengage_combat_with(target)
	target.disengage_combat_with(guard)
	guard.global_position = original_transform.origin + Vector3(8.0, 0.0, 0.0)
	guard.assign_attack_target(target, false, false, false)
	keep.call("_process_guard_post_assignment", guard)
	if guard.get_current_combat_target() != target or not guard.is_in_combat():
		_fail("Keep guard-post assignment should not cancel active combat")
	guard.disengage_combat_with(target)
	target.disengage_combat_with(guard)
	guard.global_transform = original_transform
	guard.velocity = Vector3.ZERO


func _assert_file_does_not_contain(path: String, needle: String, message: String) -> void:
	var contents := FileAccess.get_file_as_string(path)
	if contents.contains(needle):
		_fail(message)
