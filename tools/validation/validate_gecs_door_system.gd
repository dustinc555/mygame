extends SceneTree

var _gecs_world: Node
var _doors: Node
var _results: Array[Dictionary] = []
var _ecs_placeholder: Node
var _projected_door: Node
var _projected_blocker: StaticBody3D
var _interactions: Node
var _actor: Node3D


class DoorActuator extends Node3D:
	var stable_id := ""
	var member_name := "Door Validator"
	var faction_name := ""
	var squad_name := ""
	var hostile_factions := PackedStringArray()
	var player_party_member := false
	var inventory = null
	var _has_move_target := false
	var _move_target := Vector3.ZERO
	var lockpick_level := 50
	var dexterity_level := 1
	var awarded_lockpick_xp := 0.0

	func set_move_target(target: Vector3, _issued_by_player := true) -> void:
		_move_target = target
		_has_move_target = true
		global_position = target

	func has_move_target() -> bool:
		return _has_move_target

	func get_move_target() -> Vector3:
		return _move_target

	func get_skill_level(skill_id: String) -> int:
		return dexterity_level if skill_id == SkillRules.ATTRIBUTE_DEXTERITY else lockpick_level

	func add_skill_xp(_skill_id: String, amount: float, _reason := "") -> int:
		awarded_lockpick_xp += amount
		return 0


func _init() -> void:
	if not Engine.has_singleton("ECS"):
		_ecs_placeholder = Node.new()
		Engine.register_singleton("ECS", _ecs_placeholder)
	call_deferred("_run")


func _run() -> void:
	var root := Node.new()
	root.name = "DoorValidationRoot"
	get_root().add_child(root)
	var context := BootstrapContext.new(root)
	var gecs_world_script = load("res://features/core/gecs_world_controller.gd")
	var door_controller_script = load("res://features/doors/sim/door_controller.gd")
	_gecs_world = gecs_world_script.new()
	_gecs_world.name = "GecsWorldController"
	root.add_child(_gecs_world)
	context.register(&"gecs_world", _gecs_world)
	_gecs_world.initialize(context)
	_register_actor(root, "validator.actor")
	_doors = door_controller_script.new()
	root.add_child(_doors)
	context.register(&"doors", _doors)
	BootstrapContext.active = context
	_doors.initialize(context)
	var interaction_controller_script = load("res://features/doors/bridge/door_interaction_controller.gd")
	_interactions = interaction_controller_script.new()
	root.add_child(_interactions)
	context.register(&"door_interactions", _interactions)
	_interactions.initialize(context)
	_doors.door_command_resolved.connect(func(result: Dictionary) -> void: _results.append(result))
	_validate_facility_door_policy()
	await _setup_projected_access_door(root)
	_validate_lock_and_access()
	_validate_npc_auto_open()
	_validate_scheduled_duty()
	_validate_lockpick_gate_and_chance()
	_validate_exit_policies()
	_expect(_doors._command_entity_by_id.is_empty(), "Resolved commands must not accumulate.")
	print("GECS_DOOR_SYSTEM_OK")
	root.free()
	BootstrapContext.active = null
	if _ecs_placeholder != null and is_instance_valid(_ecs_placeholder):
		_ecs_placeholder.free()
	quit()


func _validate_facility_door_policy() -> void:
	_doors.configure_building_doors("validation.facility", {
		"authorized_actor_ids": PackedStringArray(["validator.actor"]),
		"authorized_faction_ids": PackedStringArray(["validation.faction"]),
		"initial_state": "open",
	})
	_doors.register_door({
		"door_id": "validation.facility.front",
		"building_id": "validation.facility",
		"default_locked": true,
		"authorized_key_ids": PackedStringArray(["validation.key"]),
	})
	var initial: Dictionary = _doors.get_door_state("validation.facility.front")
	_expect(bool(initial.get("is_open", false)) and not bool(initial.get("is_locked", true)), "Facility Start Open must apply to a pristine door record.")
	_expect(initial.get("authorized_actor_ids", PackedStringArray()) == PackedStringArray(["validator.actor"]), "Private facility policy must authorize its owner actor.")
	_expect(initial.get("authorized_faction_ids", PackedStringArray()) == PackedStringArray(["validation.faction"]), "Private facility policy must authorize its owner faction.")
	_expect(_run_command("validator.actor", "validation.facility.front", "close", {}).get("result_code") == "closed", "Facility policy fixture must close through normal door commands.")
	_doors.configure_building_doors("validation.facility", {
		"authorized_actor_ids": PackedStringArray(["replacement.actor"]),
		"authorized_faction_ids": PackedStringArray(["replacement.faction"]),
		"initial_state": "open",
	})
	var replaced: Dictionary = _doors.get_door_state("validation.facility.front")
	_expect(not bool(replaced.get("is_open", true)), "Repeated facility sync must not reapply Start Open after gameplay changes state.")
	_expect(replaced.get("authorized_actor_ids", PackedStringArray()) == PackedStringArray(["replacement.actor"]), "Facility ownership turnover must remove the old owner actor.")
	_expect(replaced.get("authorized_key_ids", PackedStringArray()) == PackedStringArray(["validation.key"]), "Facility policy must preserve per-door key authorization.")
	_doors.configure_building_doors("validation.facility", {"public_access": true, "keeper_actor_id": "validator.actor"})
	var public_state: Dictionary = _doors.get_door_state("validation.facility.front")
	_expect(public_state.get("authorized_actor_ids", PackedStringArray()) == PackedStringArray(["validator.actor"]), "Public facility policy must retain keeper lock authority.")
	_expect((public_state.get("authorized_faction_ids", PackedStringArray()) as PackedStringArray).is_empty(), "Public facility policy must clear faction restrictions.")
	_expect(_run_command("validator.actor", "validation.facility.front", "lock", {}).get("result_code") == "locked", "Public facility keeper must lock its scheduled door.")
	_expect(_run_command("validator.actor", "validation.facility.front", "unlock", {}).get("result_code") == "unlocked", "Public facility keeper must unlock its scheduled door.")
	_doors.configure_building_doors("validation.locked_facility", {"initial_state": "locked"})
	_doors.register_door({"door_id": "validation.locked_facility.front", "building_id": "validation.locked_facility"})
	var locked: Dictionary = _doors.get_door_state("validation.locked_facility.front")
	_expect(bool(locked.get("is_locked", false)) and not bool(locked.get("is_open", true)), "Locked initial state must be closed and locked.")
	_doors.configure_building_doors("validation.closed_facility", {"initial_state": "closed"})
	_doors.register_door({"door_id": "validation.closed_facility.front", "building_id": "validation.closed_facility", "default_open": true, "default_locked": true})
	var closed: Dictionary = _doors.get_door_state("validation.closed_facility.front")
	_expect(not bool(closed.get("is_open", true)) and not bool(closed.get("is_locked", true)), "Closed initial state must be closed and unlocked.")
	_doors.configure_building_doors("validation.default_facility", {"initial_state": "door_default"})
	_doors.register_door({"door_id": "validation.default_facility.front", "building_id": "validation.default_facility", "default_open": true})
	var door_default: Dictionary = _doors.get_door_state("validation.default_facility.front")
	_expect(bool(door_default.get("is_open", false)) and not bool(door_default.get("is_locked", true)), "Door Default initial state must preserve DoorDefinition defaults.")


func _register_actor(root: Node, actor_id: String) -> void:
	_actor = DoorActuator.new()
	_actor.stable_id = actor_id
	root.add_child(_actor)
	_gecs_world.register_actor(_actor)


func _setup_projected_access_door(root: Node) -> void:
	_doors.register_door({
		"door_id": "validation.access",
		"default_locked": true,
		"authorized_actor_ids": ["validator.actor"],
		"scheduled_actor_id": "validator.actor",
		"scheduled_open_hour": 8,
		"scheduled_close_hour": 21,
	})
	var door_scene = load("res://scenes/building_pieces/quaternius/medieval_village_woodbrick/door_wood_flat.tscn")
	_projected_door = door_scene.instantiate()
	_projected_door.door_id = "validation.access"
	root.add_child(_projected_door)
	_projected_blocker = _projected_door.get_node("ClosedBlocker") as StaticBody3D
	await process_frame
	var locked_actions: Array = _projected_door.get_world_context_actions(_actor)
	_expect(locked_actions.size() == 2 and str(locked_actions[0].get("key", "")) == "unlock" and str(locked_actions[1].get("key", "")) == "lockpick", "Locked doors must expose unlock and lockpick player actions.")


func _validate_lock_and_access() -> void:
	_expect(_run_command("validator.actor", "validation.access", "open", {}).get("result_code") == "locked", "Locked doors must reject open commands.")
	_expect(_run_command("validator.actor", "validation.access", "unlock", {}).get("result_code") == "unlocked", "Authorized actors must unlock doors.")
	_expect(_run_interaction_command("open").get("result_code") == "opened", "Unlocked doors must open through the interaction bridge.")
	_expect(_projected_blocker.get_parent() == _projected_door and _projected_blocker.collision_layer == 0, "Opening must disable the projected collision blocker without changing nav geometry.")
	_expect(_run_command("validator.actor", "validation.access", "lock", {}).get("result_code") == "must_close_before_locking", "Open doors must not lock.")
	_expect(_run_command("validator.actor", "validation.access", "close", {}).get("result_code") == "closed", "Open doors must close.")
	_expect(_projected_blocker.get_parent() == _projected_door and _projected_blocker.collision_layer == 8, "Closing must restore runtime-only door collision.")
	_expect(_run_command("validator.actor", "validation.access", "lock", {}).get("result_code") == "locked", "Authorized actors must lock closed doors.")
	_doors.register_door({
		"door_id": "validation.law_access",
		"default_locked": true,
		"authorized_actor_ids": ["resident.actor"],
	})
	_expect(_run_command("validator.actor", "validation.law_access", "unlock", {"active_law_response": true}).get("result_code") == "unlocked", "Dispatched law responders must receive temporary private-door authority.")


func _validate_lockpick_gate_and_chance() -> void:
	_doors.register_door({
		"door_id": "validation.lockpick",
		"default_locked": true,
		"lock_tier_id": "very_hard",
	})
	var ineligible := _run_command("validator.actor", "validation.lockpick", "lockpick", {
		"lockpick_skill_level": 49.0,
		"has_required_lockpick": true,
	})
	_expect(ineligible.get("result_code") == "lockpick_ineligible", "Very Hard locks must reject Lockpicking below 50.")
	var result := _run_command("validator.actor", "validation.lockpick", "lockpick", {
		"lockpick_skill_level": 50.0,
		"has_required_lockpick": true,
	})
	_expect(is_equal_approx(float(result.get("chance", 0.0)), 0.01), "Lockpicking 50 must attempt Very Hard locks at 1%.")
	_expect(result.get("result_code") == "lockpick_failed" or result.get("result_code") == "lockpicked", "Eligible lockpick must resolve through a chance result.")


func _validate_npc_auto_open() -> void:
	var sides: Array = _projected_door.get_interaction_positions()
	_expect(sides.size() == 2, "Door projections must author two interaction sides.")
	_actor.global_position = sides[0]
	_actor._move_target = sides[1]
	_actor._has_move_target = true
	_expect(_interactions._actor_is_trying_to_cross_door(_actor, _projected_door), "NPC crossing setup must cross the door plane.")
	_expect(bool(_doors.get_door_state("validation.access").get("is_locked", false)), "NPC crossing setup must begin with a locked door.")
	_expect(_interactions._snapshot_has_authorized_access(_interactions._actor_snapshot(_actor, _projected_door), _doors.get_door_state("validation.access"), "validator.actor"), "Authorized NPCs must recognize door access.")
	_expect(_interactions._active_command_by_actor_door.is_empty(), "NPC crossing must start without an active door command.")
	_expect(_interactions.request_npc_auto_open(_actor, _projected_door), "NPC crossing must queue an automatic door command.")
	for _step in range(16):
		_interactions._physics_process(0.0)
		_gecs_world.world.process(0.1)
		if bool(_doors.get_door_state("validation.access").get("is_open", false)):
			break
	_expect(bool(_doors.get_door_state("validation.access").get("is_open", false)), "Authorized NPCs must unlock and open required building doors.")
	_expect(_actor._has_move_target and _actor._move_target == sides[1], "NPCs must resume their original route after opening a door.")


func _validate_scheduled_duty() -> void:
	_doors._on_world_hour_changed(21, 0, 21)
	for _step in range(24):
		_interactions._physics_process(0.0)
		_gecs_world.world.process(0.1)
		if bool(_doors.get_door_state("validation.access").get("is_locked", false)):
			break
	var closed_state: Dictionary = _doors.get_door_state("validation.access")
	_expect(not bool(closed_state.get("is_open", true)), "Scheduled close must shut the door via the configured NPC.")
	_expect(bool(closed_state.get("is_locked", false)), "Scheduled close must lock up after shutting the door.")
	_doors._on_world_hour_changed(8, 0, 8)
	for _step in range(24):
		_interactions._physics_process(0.0)
		_gecs_world.world.process(0.1)
		if bool(_doors.get_door_state("validation.access").get("is_open", false)):
			break
	var opened_state: Dictionary = _doors.get_door_state("validation.access")
	_expect(not bool(opened_state.get("is_locked", true)), "Scheduled open must unlock via the configured NPC.")
	_expect(bool(opened_state.get("is_open", false)), "Scheduled open must swing the door open for business.")


func _validate_exit_policies() -> void:
	_doors.register_door({"door_id": "validation.exit_free", "default_locked": true, "exit_policy": "free_exit"})
	_expect(_run_command("validator.actor", "validation.exit_free", "open", {"from_inside": true}).get("result_code") == "opened", "free_exit locks must always open from inside.")
	_expect(_run_command("validator.actor", "validation.exit_free", "close", {}).get("result_code") == "closed", "free_exit doors must close normally.")
	_expect(bool(_doors.get_door_state("validation.exit_free").get("is_locked", false)), "free_exit doors must re-lock behind the leaver on close.")
	_doors.register_door({"door_id": "validation.exit_cell", "default_locked": true, "exit_policy": "symmetric"})
	_expect(_run_command("validator.actor", "validation.exit_cell", "open", {"from_inside": true}).get("result_code") == "locked", "symmetric locks must bind from inside (jail cells hold).")
	_doors.register_door({"door_id": "validation.exit_cell_open", "exit_policy": "symmetric"})
	_expect(_run_command("validator.actor", "validation.exit_cell_open", "open", {"from_inside": true}).get("result_code") == "opened", "Unlocked symmetric doors must open for anyone, prisoners included.")
	_doors.register_door({"door_id": "validation.exit_authorized", "exit_policy": "authorized_exit"})
	_expect(_run_command("validator.actor", "validation.exit_authorized", "open", {"from_inside": true}).get("result_code") == "exit_denied", "authorized_exit doors must deny unauthorized leavers even when unlocked.")
	_expect(_run_command("validator.actor", "validation.exit_authorized", "open", {}).get("result_code") == "opened", "authorized_exit doors must admit inbound traffic normally when unlocked.")


func _run_command(actor_id: String, door_id: String, action: String, snapshot: Dictionary) -> Dictionary:
	var submission: Dictionary = _doors.submit_command(actor_id, door_id, action, snapshot)
	_expect(bool(submission.get("accepted", false)), "%s command must be accepted." % action)
	var command_id := str(submission.get("command_id", ""))
	_expect(bool(_doors.begin_command(command_id).get("started", false)), "%s command must begin." % action)
	var result_count := _results.size()
	for _step in range(64):
		_gecs_world.world.process(0.1)
		if _results.size() > result_count:
			return _results.back()
	push_error("Door command did not resolve: %s" % command_id)
	quit(1)
	return {}


func _run_interaction_command(action: String) -> Dictionary:
	var result_count := _results.size()
	_expect(_interactions.request_actor_action(_actor, _projected_door, action, true), "%s interaction must be accepted." % action)
	_interactions._physics_process(0.0)
	for _step in range(8):
		_gecs_world.world.process(0.1)
		if _results.size() > result_count:
			return _results.back()
	push_error("Door interaction did not resolve: %s" % action)
	quit(1)
	return {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
