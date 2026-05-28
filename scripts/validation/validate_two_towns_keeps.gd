extends SceneTree

const TWO_TOWNS_SCENE := preload("res://scenes/test_levels/two_towns_road_test.tscn")
const FARMER_NAME_PROFILE := preload("res://resources/world_sim/population_name_profiles/farmer_names.tres")
const RAIDER_NAME_PROFILE := preload("res://resources/world_sim/population_name_profiles/raider_names.tres")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := TWO_TOWNS_SCENE.instantiate()
	root.add_child(scene)
	await _wait_frames(120)
	_validate_keep(scene, "Settlements/FarmerCrossing", "MayorHouse", "Mayor", "Farmers", 2, "mayor")
	_validate_raider_jail_replaced_keep(scene)
	scene.queue_free()
	await process_frame
	if _failures.is_empty():
		print("TWO_TOWNS_KEEPS_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("TWO_TOWNS_KEEPS_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_keep(scene: Node, town_path: String, keep_name: String, expected_title: String, expected_faction: String, expected_guards: int, expected_chair_style: String) -> void:
	var town := scene.get_node_or_null(town_path)
	if town == null:
		_fail("Missing town %s" % town_path)
		return
	var keep := town.get_node_or_null("Keeps/%s" % keep_name)
	if keep == null:
		_fail("Missing keep %s/%s" % [town_path, keep_name])
		return
	if str(keep.get("facility_type")) != "keep":
		_fail("%s should be a keep facility" % keep_name)
	if str(keep.get("ruler_title")) != expected_title:
		_fail("%s should use ruler title %s" % [keep_name, expected_title])
	if str(keep.get("owner_faction_id")) != expected_faction:
		_fail("%s should be owned by %s" % [keep_name, expected_faction])
	if str(keep.get("ruler_chair_style")) != expected_chair_style:
		_fail("%s should use %s chair style" % [keep_name, expected_chair_style])
	if int(keep.get("guard_post_count")) != 0:
		_fail("%s should let default guard posts follow guard_count unless explicitly overridden" % keep_name)
	if keep.get_node_or_null("BuildingSlot/CurrentBuilding") == null:
		_fail("%s should have a generated keep hall" % keep_name)
	if keep.get_node_or_null("Furniture/PlanningTable") == null:
		_fail("%s should have a planning table" % keep_name)
	if keep.get_node_or_null("Furniture/RulerChair") == null:
		_fail("%s should have a ruler chair" % keep_name)
	var ruler := keep.get_node_or_null("Staff/Ruler")
	if ruler == null:
		_fail("%s should generate a ruler actor" % keep_name)
	elif ruler.has_method("is_sitting") and not bool(ruler.call("is_sitting")):
		_fail("%s ruler should sit in the ruler chair" % keep_name)
	else:
		_validate_ruler_seating(keep, keep_name)
		_validate_profiled_staff_actor(ruler, expected_title, _name_profile_for_faction(expected_faction), "%s ruler" % keep_name, false, expected_chair_style)
	for guard_index in range(expected_guards):
		var guard := keep.get_node_or_null(_indexed_staff_path("Guard", guard_index))
		_validate_profiled_staff_actor(guard, "guard", _name_profile_for_faction(expected_faction), "%s guard %d" % [keep_name, guard_index + 1], true, expected_chair_style)
	var record: Dictionary = keep.call("get_facility_record", town.call("get_settlement_id") if town.has_method("get_settlement_id") else "")
	if int(record.get("guard_count", 0)) != expected_guards:
		_fail("%s should report %d guards" % [keep_name, expected_guards])
	if int(record.get("guard_post_count", 0)) != expected_guards:
		_fail("%s should report %d guard posts" % [keep_name, expected_guards])
	if record.has("audience_point_count"):
		_fail("%s should not report audience points" % keep_name)
	var facility_records: Array = town.call("get_facility_records") if town.has_method("get_facility_records") else []
	if not _records_include_facility(facility_records, str(record.get("facility_id", ""))):
		_fail("%s should be discoverable through SettlementTown facility roots" % keep_name)


func _validate_raider_jail_replaced_keep(scene: Node) -> void:
	var town := scene.get_node_or_null("Settlements/RaiderCamp")
	if town == null:
		_fail("Missing RaiderCamp")
		return
	if town.get_node_or_null("Keeps/BossHut") != null:
		_fail("Raider Camp should no longer ship with a BossHut keep")
	var jail := town.get_node_or_null("Facilities/SettlementJail")
	if jail == null:
		_fail("Raider Camp should use a jail as its only civic facility")
		return
	var record: Dictionary = jail.call("get_facility_record", town.call("get_settlement_id") if town.has_method("get_settlement_id") else "")
	if str(record.get("function_id", "")) != "jail":
		_fail("Raider Camp civic facility should report jail function_id")
	if int(record.get("warden_count", 0)) != 1 or int(record.get("jail_guard_count", 0)) != 1:
		_fail("Raider jail jobs should be filled from generated town population at bootstrap")


func _records_include_facility(records: Array, facility_id: String) -> bool:
	for record in records:
		if record is Dictionary and str(record.get("facility_id", "")) == facility_id:
			return true
	return false


func _validate_ruler_seating(keep: Node, keep_name: String) -> void:
	var ruler := keep.get_node_or_null("Staff/Ruler") as Node3D
	var chair := keep.get_node_or_null("Furniture/RulerChair") as Node3D
	if ruler == null or chair == null or not chair.has_method("get_seat_position"):
		return
	var expected_position: Vector3 = chair.call("get_seat_position", ruler)
	if ruler.global_position.distance_to(expected_position) > 0.05:
		_fail("%s ruler should sit on the chair seat position" % keep_name)
	if chair.has_method("get_seat_rotation"):
		var expected_rotation: Vector3 = chair.call("get_seat_rotation", ruler)
		if absf(wrapf(ruler.rotation.y - expected_rotation.y, -PI, PI)) > 0.02:
			_fail("%s ruler should face the chair seat direction" % keep_name)


func _validate_profiled_staff_actor(actor: Node, expected_suffix: String, name_profile: Resource, label: String, require_weapon: bool, expected_chair_style: String) -> void:
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
	if base_name in ["Ruler", "Mayor", "Boss", "Guard", "Mayor Guard", "Boss Guard", "Keep Guard"]:
		_fail("%s should not keep generic placeholder name '%s'" % [label, base_name])
	elif name_profile == null or not name_profile.has_method("contains_name") or not bool(name_profile.call("contains_name", base_name)):
		_fail("%s name '%s' should come from the faction population name profile" % [label, display_name])
	if not _actor_has_equipped_slot(actor, "chest"):
		_fail("%s should have clothing from the faction appearance profile" % label)
	if require_weapon and not _actor_has_equipped_slot(actor, "weapon"):
		_fail("%s should inherit settlement guard equipment" % label)
	var perception := int(actor.call("get_skill_level", SkillRules.ATTRIBUTE_PERCEPTION)) if actor.has_method("get_skill_level") else 0
	var elite_mayor_guard := expected_suffix == "guard" and expected_chair_style == "mayor"
	var expected_min := 90 if elite_mayor_guard else 14 if expected_suffix == "guard" else 5
	var expected_max := 100 if elite_mayor_guard else 24 if expected_suffix == "guard" else 12
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


func _name_profile_for_faction(faction_id: String) -> Resource:
	return RAIDER_NAME_PROFILE if faction_id == "Raiders" else FARMER_NAME_PROFILE


func _indexed_staff_path(base_name: String, index: int) -> NodePath:
	return NodePath("Staff/%s" % (base_name if index == 0 else "%s%d" % [base_name, index + 1]))


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _fail(message: String) -> void:
	_failures.append(message)
