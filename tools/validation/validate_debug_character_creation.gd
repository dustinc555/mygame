extends Node

class FakeAppearanceController:
	extends Node
	signal creation_completed(draft_appearance, character_name, age_years, request_id: StringName)
	signal creation_cancelled(request_id: StringName)
	var opened_request := &""
	func open_creation_editor(request_id: StringName = &"") -> bool:
		opened_request = request_id
		return true

class FakePopulationController:
	extends Node
	var records := {}
	func register_actor(actor: HumanoidCharacter, _settlement_id := "", context := {}) -> Dictionary:
		var record := {
			"id": actor.stable_id,
			"party_id": str(actor.get_meta("party_id", "")),
			"birth_day_index": int(actor.get_meta("population_birth_day_index", CharacterAgeRules.UNKNOWN_BIRTH_DAY)),
			"role_id": str(context.get("role_id", "")),
		}
		records[actor.stable_id] = record
		return record

class FakeGecsWorld:
	extends Node
	var registered_ids: Array[String] = []
	var fail_registration := false
	func register_actor(actor: HumanoidCharacter, _settlement_id := "", _context := {}) -> String:
		if fail_registration:
			return ""
		registered_ids.append(actor.stable_id)
		return actor.stable_id
	func unregister_actor(actor: HumanoidCharacter) -> void:
		registered_ids.erase(actor.stable_id)

class FakeWorldTime:
	extends Node
	const DAY_INDEX := 5000
	func get_day_index() -> int:
		return DAY_INDEX

class FakeCharacterEditor:
	extends Control
	func open_for_actor(_actor, _mode: String) -> void:
		show()


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene_root := Node3D.new()
	get_tree().get_root().add_child(scene_root)
	var party_root := Node3D.new()
	party_root.name = "PartyMembers"
	party_root.position = Vector3(7.0, 1.0, -3.0)
	scene_root.add_child(party_root)
	var party_manager := PartyManager.new()
	party_manager.name = "PartyManager"
	scene_root.add_child(party_manager)
	var appearance := FakeAppearanceController.new()
	var population := FakePopulationController.new()
	var gecs := FakeGecsWorld.new()
	var world_time := FakeWorldTime.new()
	var context := BootstrapContext.new(scene_root, null)
	context.register(DebugCharacterCreationController.APPEARANCE_SERVICE_ID, appearance)
	context.register(DebugCharacterCreationController.POPULATION_SERVICE_ID, population)
	context.register(DebugCharacterCreationController.GECS_WORLD_SERVICE_ID, gecs)
	context.register(DebugCharacterCreationController.WORLD_TIME_SERVICE_ID, world_time)
	BootstrapContext.active = context
	var creation := DebugCharacterCreationController.new()
	scene_root.add_child(creation)
	creation.initialize(context)
	var completion_results: Array[bool] = []
	creation.creation_finished.connect(func(success: bool, _message: String, _actor: WorldActor) -> void: completion_results.append(success))
	var real_appearance_controller := CharacterAppearanceController.new()
	scene_root.add_child(real_appearance_controller)
	var fake_editor := FakeCharacterEditor.new()
	real_appearance_controller.add_child(fake_editor)
	real_appearance_controller.editor_window = fake_editor
	fake_editor.hide()
	if not real_appearance_controller.open_creation_editor(&"owner") or real_appearance_controller.open_creation_editor():
		_fail("An active creation transaction can be overwritten")
		return
	real_appearance_controller.call("_on_editor_cancel_requested")
	var debug_menu := DebugMenu.new()
	scene_root.add_child(debug_menu)
	if not debug_menu.get_window_titles().has("Farming Debug"):
		_fail("Debug menu does not expose Farming Debug")
		return
	if not debug_menu.get_window_titles().has("Create Character"):
		_fail("Debug menu does not expose Create Character")
		return
	debug_menu.toggle_window("Create Character")
	await get_tree().process_frame
	if not debug_menu.is_window_open("Create Character") or debug_menu.get("_character_creation_status").text != "No active world camera.":
		_fail("Create Character menu item did not invoke its action")
		return
	debug_menu.toggle_window("Create Character")
	var spawn_position := Vector3(12.0, 3.0, -8.0)
	if not creation.open_at(spawn_position) or appearance.opened_request != DebugCharacterCreationController.REQUEST_ID:
		_fail("Debug action did not open the scoped full creator request")
		return
	appearance.creation_completed.emit(CharacterAppearanceData.new(), "Debug Creator Test", 42, appearance.opened_request)
	if party_manager.party_members.size() != 1:
		_fail("Confirmed character did not join the player party")
		return
	var member := party_manager.party_members[0] as HumanoidCharacter
	if member == null or member.member_name != "Debug Creator Test":
		_fail("Created party member identity is wrong")
		return
	if party_manager.selected_members.size() != 1 or party_manager.selected_members[0] != member:
		_fail("Created character was not selected")
		return
	if member.global_position != spawn_position:
		_fail("Created character spawned at the wrong position")
		return
	var record: Dictionary = population.records.get(member.stable_id, {})
	if record.is_empty() or str(record.get("party_id", "")) != PartyManager.PLAYER_PARTY_ID or str(record.get("role_id", "")) != "player_party":
		_fail("Created character has no durable player-party record")
		return
	if CharacterAgeRules.age_years(int(record["birth_day_index"]), FakeWorldTime.DAY_INDEX) != 42:
		_fail("Created character birth day does not preserve creator age")
		return
	if not gecs.registered_ids.has(member.stable_id):
		_fail("Created character was not registered with GECS")
		return
	var count_before_cancel := party_manager.party_members.size()
	var records_before_cancel := population.records.size()
	var gecs_before_cancel := gecs.registered_ids.size()
	if not creation.open_at(spawn_position + Vector3.RIGHT):
		_fail("Second debug creator request did not open")
		return
	appearance.creation_cancelled.emit(appearance.opened_request)
	if party_manager.party_members.size() != count_before_cancel or population.records.size() != records_before_cancel or gecs.registered_ids.size() != gecs_before_cancel or completion_results.back():
		_fail("Cancelling character creation changed durable state")
		return
	gecs.fail_registration = true
	if not creation.open_at(spawn_position + Vector3.RIGHT * 2.0):
		_fail("Request remained orphaned after cancellation")
		return
	appearance.creation_completed.emit(CharacterAppearanceData.new(), "Failed GECS Test", 42, appearance.opened_request)
	if party_manager.party_members.size() != count_before_cancel or population.records.size() != records_before_cancel or completion_results.back():
		_fail("GECS registration failure was reported as successful")
		return
	gecs.fail_registration = false
	if not creation.open_at(spawn_position + Vector3.RIGHT * 3.0):
		_fail("Request remained orphaned after failed registration")
		return
	appearance.creation_cancelled.emit(appearance.opened_request)
	print("DEBUG_CHARACTER_CREATION_OK")
	BootstrapContext.active = null
	scene_root.queue_free()
	await get_tree().process_frame
	get_tree().quit()


func _fail(message: String) -> void:
	push_error("DEBUG_CHARACTER_CREATION_FAILED: %s" % message)
	get_tree().quit(1)
