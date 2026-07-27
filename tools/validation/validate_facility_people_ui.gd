extends SceneTree

const PROJECTION_SCRIPT := preload("res://features/ui/projection/facility_people_projection.gd")

var _failed := false


class AssignmentService extends Node:
	var snapshot: Dictionary

	func get_facility_people_snapshot(_building_id: String, _facility_id: String, _settlement_id: String) -> Dictionary:
		return snapshot


class FacilityTarget extends Node:
	var building_id := "building.test"
	var facility_id := "facility.test"
	var settlement_id := "settlement.test"
	var display_name := "Test Facility"
	var housing_capacity := 2


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var service := AssignmentService.new()
	service.snapshot = {
		"display_name": "Mixed Hall",
		"rows": [
			{"slot_id": "home.1", "group": "residence", "role": "Resident", "actor_id": "actor.mara", "character_name": "Mara", "source": "named"},
			{"slot_id": "bar.1", "group": "employment", "role": "Barkeeper", "actor_id": "actor.mara", "character_name": "Mara", "source": "auto"},
			{"slot_id": "bar.2", "group": "employment", "role": "Server"},
		],
	}
	var projection: RefCounted = PROJECTION_SCRIPT.new()
	projection.call("setup", service)
	var target := FacilityTarget.new()
	get_root().add_child(target)
	target.add_to_group("world_building")
	var snapshot: Dictionary = projection.call("get_snapshot", target)
	_assert(projection.call("get_action_label", target) == "People 2 / 3", "Button summary must count filled role slots")
	_assert(snapshot.get("unique_person_count") == 1, "Mixed residence and employment must count one actor once")
	_assert(snapshot.get("filled_role_count") == 2, "One actor may truthfully fill two role rows")
	_assert((snapshot.get("rows") as Array).size() == 3, "Every expected role row must remain visible")
	_assert(_row(snapshot, "bar.2").get("character_name") == "Vacant", "Unfilled roles must be Vacant")
	_assert(_row(snapshot, "home.1").get("source") == "Named", "Named assignment source must be normalized")
	_assert(_row(snapshot, "bar.1").get("source") == "Auto", "Automatic assignment source must be normalized")
	for type_id in ["home", "bar", "jail", "shop", "farm", "mine", "storage", "guard", "social", "generic"]:
		target.set("display_name", "%s Facility" % type_id.capitalize())
		_assert(str(projection.call("get_action_label", target)).begins_with("People "), "%s facility must expose a truthful People summary" % type_id)
	var controller_source := FileAccess.get_file_as_string("res://features/ui/bridge/humanoid_details_controller.gd")
	_assert(controller_source.contains("if _is_building_target(target):\n\t\tactions.append({\"key\": ACTION_PEOPLE"), "Every building/facility target must receive the People action without a type allowlist")
	projection.call("setup", null)
	var fallback: Dictionary = projection.call("get_snapshot", target)
	_assert(fallback.get("role_count") == 2 and fallback.get("filled_role_count") == 0, "Missing service must show authored capacity without invented assignments")
	_assert(projection.call("get_action_label", target) == "People 0 / 2", "Missing service button must remain truthful")
	var hud := CanvasLayer.new()
	get_root().add_child(hud)
	var window := projection.call("create_window", hud) as Control
	window.call("show_for_target", target)
	await process_frame
	_assert(window.visible, "People action must open a HUD view")
	_assert((window.get("summary_label") as Label).text.contains("0 / 2 roles filled"), "People view must show role fill summary")
	_assert((window.get("unique_people_label") as Label).text == "People: None", "People view must render a deduplicated person list")
	_assert((window.get("availability_label") as Label).visible, "Fallback view must disclose unavailable assignment state")
	hud.free()
	target.free()
	service.free()
	if _failed:
		quit(1)
		return
	print("FACILITY_PEOPLE_UI_OK")
	quit()


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)


func _row(snapshot: Dictionary, slot_id: String) -> Dictionary:
	for row in snapshot.get("rows", []):
		if str((row as Dictionary).get("slot_id", "")) == slot_id:
			return row
	return {}
