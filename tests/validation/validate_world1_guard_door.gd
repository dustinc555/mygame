extends "res://tests/validation/test_case.gd"

## The old World1 whitelist selected no guard (public bar access belongs to
## its keeper). Isolate the actual contract: an eligible live NPC must open
## a closed, unscheduled door in stride, resume its route and cross it.
var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world = load("res://tests/validation/helpers/navigation_fixture.gd").new()
	root.add_child(world)
	world.add_floor()
	var door: Node3D = world.add_door("validation.npc.crossing")
	var npc: CharacterBody3D = world.add_actor("validation.eligible.npc", Vector3(0.5142, 0.5, -4), false)
	_expect(await world.boot(), "navigation/bootstrap must settle")
	var doors = BootstrapContext.service(&"doors")
	var results: Array[Dictionary] = []
	doors.door_command_resolved.connect(func(result: Dictionary): results.append(result))
	doors.configure_building_doors(door.building_id, {"initial_state": "closed", "authorized_actor_ids": PackedStringArray([npc.stable_id])})
	var state: Dictionary = doors.get_door_state(door.door_id)
	_expect(not state.is_empty() and not state.is_open and not state.kept_open and int(state.scheduled_open_hour) < 0, "fixture begins closed with no schedule that could open it")
	_expect(not npc.is_player_party_member() and npc.has_method("set_move_target") and not npc.has_move_target(), "subject is an available live NPC, not an arbitrary busy roster actor")
	var target := Vector3(0.5142, 0.1, 4)
	_expect(await world.walk(npc, target), "NPC physically crosses the requested door and finishes its resumed route")
	var npc_opened := false
	for result in results:
		if result.actor_id == npc.stable_id and result.door_id == door.door_id and result.result_code == "opened":
			npc_opened = true
	_expect(npc_opened and doors.get_door_state(door.door_id).is_open, "this NPC, not a timer, completed the closed-to-open transition")
	await _validate_carrier_door(world, npc, door, doors, results)
	world.dispose()
	await process_frame
	print("GUARD_DOOR_%s" % ("OK" if _failures.is_empty() else "FAILED"))
	quit(0 if _failures.is_empty() else 1)

func _validate_carrier_door(world, npc: HumanoidCharacter, door: Node3D, doors: Node, results: Array[Dictionary]) -> void:
	# A door is a prerequisite of placement, not a replacement for that order.
	# Keep a real carried body, cell, navigation route and closed physics leaf.
	for action in ["close", "lock"]:
		var submitted: Dictionary = doors.submit_command(npc.stable_id, door.door_id, action)
		_expect(bool(submitted.get("accepted", false)), "carrier fixture door command is accepted: %s" % action)
		if not bool(submitted.get("accepted", false)):
			return
		doors.begin_command(str(submitted.command_id))
		var completed: bool = await world.wait_until(func() -> bool: return str(doors.get_door_state(door.door_id).active_command_id).is_empty(), 2.0)
		_expect(completed, "carrier fixture completes door %s before testing passage" % action)
	_expect(not doors.get_door_state(door.door_id).is_open and doors.get_door_state(door.door_id).is_locked, "carrier starts against an actually closed, locked door")
	var cell := load("res://features/world/projection/props/furniture/jail_cell.tscn").instantiate() as JailCell
	cell.cell_id = "validation.carrier.cell"
	cell.position = Vector3(0.5142, 0.0, 6.0)
	world.add_child(cell)
	var passenger: HumanoidCharacter = world.add_actor("validation.carried.prisoner", Vector3(0.5142, 0.5, -4.0), false)
	await physics_frame
	passenger.force_unconscious()
	npc.global_position = Vector3(0.5142, 0.5, -4.0)
	npc._attach_carried_character(passenger)
	_expect(npc.get_carry().get_carried_character() == passenger and passenger.get_carry().get_carrier() == npc, "fixture establishes reciprocal physical carry")
	var interaction := npc.get_interaction()
	interaction.assign_place_carried_in_cell_target(cell, false)
	var destination := npc.get_move_target()
	_expect(interaction.current_order_type == InteractionCapability.ORDER_TYPE_PLACE_IN_CELL and interaction.current_place_cell_target == cell, "fixture owns the real cell placement order")
	npc.set_move_target(Vector3(9.0, 0.1, -3.0), false)
	_expect(npc.get_move_target().is_equal_approx(destination), "an unrelated ambient post move cannot replace the carrier's route")
	var bridge := BootstrapContext.service(DoorInteractionController.SERVICE_ID) as DoorInteractionController
	_expect(not bridge.request_npc_auto_open(npc, door), "a distant priority carrier cannot perform a remote door command")
	_expect(npc.get_move_target().is_equal_approx(destination) and interaction.current_place_cell_target == cell, "refused distant door approach preserves cell ownership and route")
	npc.global_position = Vector3(0.5142, 0.1, -1.0)
	doors.configure_building_doors(door.building_id, {"authorized_actor_ids": PackedStringArray(["validation.someone_else"])})
	_expect(not bridge.request_npc_auto_open(npc, door), "carrying grants no access to a foreign locked door")
	_expect(doors.get_door_state(door.door_id).is_locked and not doors.get_door_state(door.door_id).is_open, "denied access preserves the actual locked blocker")
	doors.configure_building_doors(door.building_id, {"authorized_actor_ids": PackedStringArray([npc.stable_id])})
	var result_start := results.size()
	var accepted := bridge.request_npc_auto_open(npc, door)
	print("CARRIER_DOOR_SUBMISSION accepted=%s order=%d destination=%s results=%s" % [accepted, interaction.current_order_type, npc.get_move_target(), JSON.stringify(results.slice(result_start))])
	_expect(accepted, "authorized in-range carrier must begin unlocking without replacing its placement order")
	if not accepted:
		return
	_expect(interaction.current_order_type == InteractionCapability.ORDER_TYPE_PLACE_IN_CELL and interaction.current_place_cell_target == cell and npc.get_move_target().is_equal_approx(destination), "door submission preserves exact cell order and movement destination")
	var opened: bool = await world.wait_until(func() -> bool: return bool(doors.get_door_state(door.door_id).is_open), 3.0)
	_expect(opened, "the carrier completes unlock and open through the door authority")
	_expect(interaction.current_order_type == InteractionCapability.ORDER_TYPE_PLACE_IN_CELL and interaction.current_place_cell_target == cell and npc.get_carry().get_carried_character() == passenger, "door resolution retains the same carrier, passenger and cell assignment")
	var placed: bool = await world.wait_until(func() -> bool: return passenger.is_in_cell_custody(), 16.0)
	_expect(placed and cell.has_occupant(passenger), "same carrier physically crosses the doorway and places the exact prisoner in the assigned cell")
	_expect(npc.global_position.z > 0.6 and npc.get_carry().get_carried_character() == null and passenger.get_carry().get_carrier() == null, "completed passage releases both carry links only at intake")
	var transitions: Array[String] = []
	for result in results.slice(result_start):
		if result.actor_id == npc.stable_id and result.door_id == door.door_id:
			transitions.append(str(result.result_code))
	_expect(transitions == ["unlocked", "opened"], "the exact carrier produces only the required unlock/open receipts")
	print("CARRIER_DOOR_COMPLETION placed=%s position=%s transitions=%s" % [placed, npc.global_position, transitions])

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)
