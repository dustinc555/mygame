extends SceneTree

## Display-only contract: real projection, controls, actions and authored slots.
## Assignment-service responses are controlled; this does not run staff AI.

const PROJECTION_SCRIPT := preload("res://features/ui/projection/facility_people_projection.gd")

var _failed := false


class AssignmentService extends Node:
	var snapshots: Dictionary
	var last_identity: Array[String] = []

	func get_facility_people_snapshot(_building_id: String, _facility_id: String, _settlement_id: String) -> Dictionary:
		last_identity = [_building_id, _facility_id, _settlement_id]
		return snapshots.get(_facility_id, {})


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
	var target := FacilityTarget.new()
	target.display_name = "Mixed Hall"
	var other_target := FacilityTarget.new()
	other_target.facility_id = "facility.other"
	other_target.display_name = "Workshop"
	# Same building/settlement, different facilities: query/cache identity matters.
	for fixture in [target, other_target]:
		get_root().add_child(fixture)
		fixture.add_to_group("world_building")
	var primary_roster := {
		"display_name": "Mixed Hall",
		"role_count": 3,
		"rows": [
			{"slot_id": "home.1", "group": "residence", "role_id": "resident", "actor_id": "actor.mara", "character_name": "Mara", "source": "named"},
			{"slot_id": "work.1", "group": "employment", "role_id": "steward", "actor_id": "actor.mara", "character_name": "Mara", "source": "auto"},
			{"slot_id": "work.2", "group": "employment", "role_id": "guard", "actor_id": "", "character_name": "", "source": ""},
		],
	}
	# Match SettlementController.get_facility_people_snapshot(), including role_id.
	service.snapshots[target.facility_id] = primary_roster
	service.snapshots[other_target.facility_id] = {
		"display_name": "Workshop",
		"role_count": 2,
		"rows": [
			{"slot_id": "craft.1", "group": "employment", "role_id": "crafter", "actor_id": "actor.cinder", "character_name": "Cinder", "source": "named"},
			{"slot_id": "craft.2", "group": "employment", "role_id": "crafter", "actor_id": "actor.noor", "character_name": "Noor", "source": "auto"},
		],
	}
	var primary_rows := [["Resident", "Mara", "Named"], ["Steward", "Mara", "Auto"], ["Guard", "Vacant", ""]]
	var secondary_rows := [["Crafter", "Cinder", "Named"], ["Crafter", "Noor", "Auto"]]
	var projection: RefCounted = PROJECTION_SCRIPT.new()
	projection.call("setup", service)
	var snapshot: Dictionary = projection.call("get_snapshot", target)
	_assert(projection.call("get_action_label", target) == "People 2 / 3", "Button summary must count filled role slots")
	_assert(snapshot.get("unique_person_count") == 1, "Mixed residence and employment must count one actor once")
	_assert(snapshot.get("filled_role_count") == 2, "One actor may truthfully fill two role rows")
	_assert((snapshot.get("rows") as Array).size() == 3, "Every expected role row must remain visible")
	_assert(_row(snapshot, "work.2").get("character_name") == "Vacant", "Unfilled roles must be Vacant")
	_assert(_row(snapshot, "home.1").get("role") == "Resident", "Current role_id must produce the role label")
	_assert(_row(snapshot, "home.1").get("source") == "Named", "Named assignment source must be normalized")
	_assert(_row(snapshot, "work.1").get("source") == "Auto", "Automatic assignment source must be normalized")
	var hud := CanvasLayer.new()
	get_root().add_child(hud)
	var controller = load("res://features/ui/bridge/humanoid_details_controller.gd").new()
	controller.facility_people_projection = projection
	controller.hud_layer = hud
	var action_button := Button.new()
	hud.add_child(action_button)
	controller.action_buttons.append(action_button)
	# Reuse the same visible window in both directions; stale rows must not survive.
	for selected in [target, other_target, target]:
		var opened := _open_people(controller, projection, selected, action_button)
		await process_frame
		_assert(service.last_identity == [selected.building_id, selected.facility_id, selected.settlement_id], "People query must use the selected facility's complete identity")
		if selected == target:
			_assert_window(opened, selected, "2 / 3 roles filled", ["Mara"], primary_rows, false)
		else:
			_assert(action_button.text == "People 2 / 2", "Switching facility must refresh the People button summary")
			_assert_window(opened, selected, "2 / 2 roles filled", ["Cinder", "Noor"], secondary_rows, false)
	var facility_count := 0
	for file in DirAccess.get_files_at("res://features/settlements/resources/facilities"):
		if not file.ends_with(".tres"):
			continue
		var definition := load("res://features/settlements/resources/facilities/" + file) as Resource
		_assert(definition != null, "Catalog facility definition must load: " + file)
		if definition == null or not bool(definition.get("catalog_enabled")):
			continue
		var scene := load(str(definition.get("scene_path"))) as PackedScene
		_assert(scene != null, "Every catalog facility must load for People action test")
		if scene == null:
			continue
		var facility := scene.instantiate()
		facility.set("facility_id", "people.ui." + str(definition.get_id()))
		var roster := primary_roster.duplicate(true)
		roster["display_name"] = str(facility.get("display_name"))
		service.snapshots[facility.get("facility_id")] = roster
		var opened := _open_people(controller, projection, facility, action_button)
		_assert(service.last_identity[1] == str(facility.get("facility_id")), "Different facilities must query their distinct durable identity instead of reusing cached fake target")
		_assert_window(opened, facility, "2 / 3 roles filled", ["Mara"], primary_rows, false)
		facility_count += 1
		facility.free()
	_assert(facility_count > 0, "People matrix must exercise real catalog facilities")
	projection.call("setup", null)
	var authored := _authored_facility_fixture()
	var authored_fallback: Dictionary = projection.call("get_snapshot", authored)
	_assert(authored_fallback.get("role_count") == 2 and authored_fallback.get("filled_role_count") == 0, "Missing service must use authored role slots instead of unrelated housing capacity")
	_assert(authored_fallback.get("unique_person_count") == 0, "Preferred named characters must not be invented as assigned occupants")
	_assert(_row(authored_fallback, "facility.authored.home").get("group") == "residence" and _row(authored_fallback, "facility.authored.work").get("group") == "employment", "Authored role slot identities and domains must survive unavailable assignment state")
	var authored_window := _open_people(controller, projection, authored, action_button)
	await process_frame
	_assert(action_button.text == "People 0 / 2", "Authored vacant roles must be reflected in the People action")
	_assert_window(authored_window, authored, "0 / 2 roles filled", [], [["Resident", "Vacant", ""], ["Guard", "Vacant", ""]], true)
	# Keep generic building capacity as a separate supported fallback.
	var fallback: Dictionary = projection.call("get_snapshot", target)
	_assert(fallback.get("role_count") == 2 and fallback.get("filled_role_count") == 0, "Missing service must show authored capacity without invented assignments")
	_assert(projection.call("get_action_label", target) == "People 0 / 2", "Missing service button must remain truthful")
	var window := _open_people(controller, projection, target, action_button)
	await process_frame
	_assert_window(window, target, "0 / 2 roles filled", [], [["Resident", "Vacant", ""], ["Resident", "Vacant", ""]], true)
	controller.free()
	hud.free()
	authored.free()
	target.free()
	other_target.free()
	service.free()
	if _failed:
		quit(1)
		return
	print("FACILITY_PEOPLE_UI_OK")
	quit()


func _open_people(controller: Node, projection: RefCounted, target: Node, button: Button) -> Control:
	controller.set("current_target", target)
	var actions: Array = controller.call("_get_world_target_actions", target)
	_assert(actions.size() == 1 and actions[0].key == "people", "Facility must receive the People action in the single-button fixture")
	if actions.size() != 1 or actions[0].key != "people":
		return null
	controller.call("_set_actions", actions)
	controller.call("_on_action_button_pressed", button)
	var window := projection.get("_window") as Control
	_assert(window != null and window.visible, "Real details-controller action must open People window")
	return window


func _assert_window(window: Control, target: Node, summary: String, people: Array[String], expected_rows: Array, unavailable: bool) -> void:
	if window == null:
		return # _open_people records the failure before returning null.
	_assert(window.get("target") == target, "People window must follow the selected target")
	_assert((window.get("title_label") as Label).text == "%s People" % target.get("display_name"), "People window must display the selected facility title")
	_assert((window.get("summary_label") as Label).text.contains(summary), "People window must display the selected roster's role counts")
	var names := "People: %s" % ", ".join(people) if not people.is_empty() else "People: None"
	_assert((window.get("unique_people_label") as Label).text == names, "People window must replace the previous facility's names")
	_assert((window.get("availability_label") as Label).visible == unavailable, "People window must disclose only unavailable assignment state")
	var rendered_rows: Array = []
	for child in (window.get("rows_root") as Control).get_children():
		# _render queues replaced rows for end-of-frame deletion.
		if not (child is HBoxContainer) or child.is_queued_for_deletion():
			continue
		var values: Array[String] = []
		for label in child.get_children():
			values.append((label as Label).text)
		rendered_rows.append(values)
	_assert(rendered_rows.size() == expected_rows.size(), "People window must not retain rows from the previous facility")
	for row in expected_rows:
		_assert(rendered_rows.count(row) == expected_rows.count(row), "People window must render the expected role/person/source rows: %s" % str(row))


func _authored_facility_fixture() -> Node:
	var facility = load("res://features/settlements/bridge/settlement_facility.gd").new()
	facility.facility_id = "facility.authored"
	facility.display_name = "Authored Hall"
	# Deliberately differs from two authored slots so the wrong fallback cannot pass.
	facility.housing_capacity = 7
	for definition in [["home", "resident", "residence"], ["work", "guard", "employment"]]:
		var role = load("res://features/settlements/resources/facility_role_definition.gd").new()
		role.role_id = definition[1]
		role.assignment_domain = definition[2]
		role.assignment_exclusivity_group = definition[2]
		var slot = load("res://features/settlements/resources/facility_role_slot_definition.gd").new()
		slot.slot_id = definition[0]
		slot.role = role
		var character = load("res://features/world_sim/resources/character_record_definition.gd").new()
		character.actor_id = "actor.preferred"
		character.member_name = "Preferred Person"
		slot.named_character = character
		facility.role_slots.append(slot)
	return facility


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
