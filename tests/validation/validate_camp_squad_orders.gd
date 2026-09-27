extends "res://tests/validation/test_case.gd"

## Real debug menu -> camp population -> shared movement/combat, including
## off-camera travel, destruction/recreation and the full world-save boundary.
const FIXTURE = preload("res://tests/validation/helpers/navigation_fixture.gd")
const CAMP_ID := "orders.camp"
const TOWN_ID := "orders.town"
const DESTINATION := Vector3(45, 0, 0)
const SAVE_PATH := "user://camp-squad-orders.tres"
var _failed := false
var _impacts: Array = []
var _fighter_ids: Array = []

func _initialize() -> void:
	var world = FIXTURE.new()
	root.add_child(world)
	world.add_floor(Vector3(180, 1, 180))
	var floor_mesh := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(180, 0.1, 180)
	floor_mesh.mesh = mesh
	floor_mesh.position.y = -0.06
	world.add_child(floor_mesh)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	world.add_child(sun)
	var defender = world.add_actor("orders.defender", DESTINATION)
	if not _check(await world.boot(), "normal bootstrap and navigation ready"):
		_finish(world)
		return
	var context := BootstrapContext.active
	var gecs := context.require(&"gecs_world")
	var population := context.require(&"population")
	var camps := context.require(&"camps")
	var lod := context.require(&"population_realization")
	var clock := context.require(&"world_time")
	var status := context.require(&"world_status")
	clock.set_time_of_day(12)
	var marker := CampMarker.new()
	marker.camp_id = CAMP_ID
	marker.camp_size = 0
	marker.squad_count = 1
	marker.squad_size = 1
	marker.roaming_radius = 10.0
	marker.position = Vector3(-35, 0, 0)
	world.add_child(marker)
	gecs.upsert_settlement_state(TOWN_ID, {"display_name": "Target Town", "faction_id": "Player", "world_position": DESTINATION, "radius": 10.0})
	if not _check(await world.wait_until(func(): return not gecs.get_camp_state(CAMP_ID).is_empty() and not paused, 30), "camp generated and loading released"):
		_finish(world)
		return
	var camera: Camera3D = world.get_node("CameraRig/CameraPivot/Camera3D")
	camera.position = Vector3(-20, 28, 32)
	camera.look_at(Vector3(-20, 0, 0))
	var resolution := world.find_child("GameCombatResolutionSystem", true, false)
	resolution.impact_resolved.connect(func(attacker: String, target: String, _sequence: int, outcome: String, damage: float):
		if attacker in _fighter_ids or target in _fighter_ids:
			_impacts.append({"attacker": attacker, "target": target, "outcome": outcome, "damage": damage}))
	# Use the actual Escape entry, not a separate debug harness UI.
	await _key(get_viewport(), KEY_ESCAPE)
	var entry: Button
	for button in status.escape_menu_debug_buttons.get_children():
		if button.text == "Debug - World Sim":
			entry = button
	if not _check(entry != null and entry.is_visible_in_tree(), "Escape exposes Debug - World Sim"):
		_finish(world)
		return
	await _click(entry)
	var debug: Control = status.debug_menu
	if not _check(debug.is_window_open("World Sim"), "pointer opens World Sim"):
		_finish(world)
		return
	# Close the pause menu while retaining the independent debug window.
	await _key(get_viewport(), KEY_ESCAPE)
	var panel: Control = debug.find_child("CampAttack", true, false)
	var from: OptionButton = panel.find_child("FromCamp", true, false)
	var to: OptionButton = panel.find_child("ToTown", true, false)
	await _choose_first(from)
	await _choose_first(to)
	if not _check(from.get_selected_metadata() == CAMP_ID and to.get_selected_metadata() == TOWN_ID, "dropdowns select actual camp and town IDs"):
		_finish(world)
		return
	var count: SpinBox = panel.find_child("FighterCount", true, false)
	count.get_line_edit().text = "3"
	var spawn: Button = panel.find_child("SpawnAttack", true, false)
	var scroll: ScrollContainer = debug.find_child("ActionScroll", true, false)
	scroll.ensure_control_visible(spawn)
	await process_frame
	await _click(spawn)
	var squads: Array = gecs.get_world_sim_squads().filter(func(squad): return str(squad.objective) == "assault")
	if not _check(squads.size() == 1 and int(squads[0].member_count) == 3, "pointer submission creates exactly the requested fighters"):
		print("ORDER_UI_STATE ", panel.find_child("CommandStatus", true, false).text)
		_finish(world)
		return
	var squad_id := str(squads[0].squad_id)
	var records: Array = population.get_records_for_squad(squad_id)
	var ids: Array = records.map(func(record): return str(record.actor_id))
	_fighter_ids = ids
	_check(ids.size() == 3, "squad consists of real population records")
	for frame in 4:
		await process_frame
	var feedback: Label = panel.find_child("CommandStatus", true, false)
	_check(scroll.get_global_rect().encloses(feedback.get_global_rect()), "command result is visible without scrolling")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.test-results/world-sim-menu.png")
	debug.toggle_window("World Sim")
	if not _check(await world.wait_until(func(): return _all_live(population, ids), 30), "all requested fighters realize normally"):
		_finish(world)
		return
	var positions: Dictionary = {}
	var instances: Dictionary = {}
	var appearances: Dictionary = {}
	var equipment: Dictionary = {}
	for id in ids:
		var actor: Node3D = population.get_live_actor(id)
		positions[id] = actor.global_position
		instances[id] = actor.get_instance_id()
		appearances[id] = population.get_actor_record(id).appearance
		equipment[id] = population.get_actor_record(id).equipment_slots
		_check(actor.global_position.distance_to(marker.global_position) < 12.0, "fighter starts at its source camp " + id)
	if not _check(await world.wait_until(func(): return _all_moved_toward_town(population, ids, positions), 25), "every fighter physically advances toward the town"):
		_diagnose(population, ids)
		_finish(world)
		return
	# Actual camera LOD: destroy projected actors, let the normal mover advance
	# the durable squad, then save/load and return to the same members.
	lod.set_realization_retention_seconds(0.0)
	camera.position += Vector3(1000, 0, 0)
	if not _check(await world.wait_until(func(): return ids.all(func(id): return population.get_live_actor(id) == null), 10), "leaving camera range destroys squad bodies"):
		_finish(world)
		return
	var offscreen_start: Vector3 = _squad(gecs, squad_id).position
	_check(await world.wait_until(func(): return _squad(gecs, squad_id).position.distance_to(offscreen_start) > 3.0, 8), "ordinary offscreen mover continues the same objective")
	var simulation := context.require(WorldSimulationController.SERVICE_ID)
	_check(simulation.save_world_to_file(SAVE_PATH), "full world save succeeds")
	var saved: Dictionary = _squad(gecs, squad_id)
	var changed := saved.duplicate(true)
	changed.target_position = Vector3.ZERO
	changed.objective = "patrol"
	gecs.upsert_world_sim_squad(changed)
	_check(simulation.load_world_from_file(SAVE_PATH), "full world load succeeds")
	for frame in 4:
		await process_frame
	var restored := _squad(gecs, squad_id)
	_check(restored.objective == "assault" and restored.target_position == DESTINATION and restored.target_settlement_id == TOWN_ID, "saved explicit order survives lifecycle restoration")
	_check(population.get_records_for_squad(squad_id).map(func(record): return str(record.actor_id)) == ids, "load retains roster instead of rerolling it")
	camera.position = Vector3(-5, 28, 32)
	camera.look_at(Vector3(5, 0, 0))
	if not _check(await world.wait_until(func(): return _all_live(population, ids), 30), "same squad re-realizes on camera return"):
		_finish(world)
		return
	positions.clear()
	for id in ids:
		var actor: Node3D = population.get_live_actor(id)
		_check(actor.get_instance_id() != int(instances[id]), "new body for saved identity " + id)
		_check(population.get_actor_record(id).appearance == appearances[id], "race and appearance retained " + id)
		_check(population.get_actor_record(id).equipment_slots == equipment[id], "weapons retained " + id)
		positions[id] = actor.global_position
	_check(await world.wait_until(func(): return _all_moved_toward_town(population, ids, positions), 25), "all re-created actors resume physical travel")
	if not _check(await world.wait_until(func(): return not _impacts.is_empty(), 45), "arriving fighters engage through the normal combat system"):
		_diagnose(population, ids)
	print("ORDER_COMBAT_IMPACTS ", _impacts)
	_check(is_instance_valid(defender), "target-town defender remains a normal actor")
	# A second command after load must not reuse the saved squad's IDs.
	var next: Dictionary = camps.spawn_attack_squad(CAMP_ID, TOWN_ID, 1)
	_check(next.ok and next.squad_id != squad_id, "subsequent command allocates a distinct durable squad")
	_finish(world)

func _squad(gecs: Node, id: String) -> Dictionary:
	for squad in gecs.get_world_sim_squads():
		if str(squad.squad_id) == id:
			return squad
	return {}

func _all_live(population: Node, ids: Array) -> bool:
	return ids.all(func(id): return is_instance_valid(population.get_live_actor(id)))

func _all_moved_toward_town(population: Node, ids: Array, starts: Dictionary) -> bool:
	for id in ids:
		var actor: Node3D = population.get_live_actor(id)
		if not is_instance_valid(actor) or actor.global_position.distance_to(DESTINATION) >= starts[id].distance_to(DESTINATION) - 3.0:
			return false
	return true

func _diagnose(population: Node, ids: Array) -> void:
	for id in ids:
		var actor = population.get_live_actor(id)
		if is_instance_valid(actor):
			print("ORDER_MOTION ", id, " ", FIXTURE.actor_motion_snapshot(actor))

func _choose_first(picker: OptionButton) -> void:
	await _click(picker)
	var popup := picker.get_popup()
	if not _check(popup.visible, "pointer opens " + str(picker.name)):
		return
	# Route through the parent viewport: embedded popups handle window input
	# before their own viewport's GUI dispatch. Direct popup.push_input skips it.
	for attempt in picker.item_count:
		if popup.get_focused_item() == 1:
			break
		await _key(picker.get_viewport(), KEY_DOWN)
	await _key(picker.get_viewport(), KEY_ENTER)

func _key(viewport: Viewport, code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		viewport.push_input(event, true)
		await process_frame

func _click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	get_viewport().push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		get_viewport().push_input(event, true)
		await process_frame

func _check(value: bool, label: String) -> bool:
	print("SQUAD_ORDER_CHECK ", "PASS " if value else "FAIL ", label)
	_failed = _failed or not value
	return value

func _finish(world: Node) -> void:
	print("CAMP_SQUAD_ORDERS_RESULT ", "FAIL" if _failed else "PASS")
	world.dispose()
	await process_frame
	quit(1 if _failed else 0)
