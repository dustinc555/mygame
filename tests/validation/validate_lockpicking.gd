extends "res://tests/validation/test_case.gd"
## Real bootstrap, offline/local baker, native actor navigation and saved item art.
## No teleports or manual steering after the initial authored spawn.
const FIXTURE := preload("res://tests/validation/helpers/navigation_fixture.gd")
const PICKS := preload("res://features/lockpicking/sim/lockpick_rules.gd")
var failures: Array[String] = []
var world
var mira: HumanoidCharacter
var tomas: HumanoidCharacter
var bridge: Node
var locks: Node
var ui: WorldInteractionController
var motion_camera: Camera3D

func _initialize() -> void:
	world = FIXTURE.new()
	root.add_child(world)
	world.add_floor(Vector3(24, 1, 24))
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	floor_mesh.mesh.size = Vector2(24, 24)
	world.add_child(floor_mesh)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	world.add_child(light)
	var cage: JailCell = load("res://features/world/projection/props/furniture/jail_cell.tscn").instantiate()
	cage.cell_id = "lockpick.validation"
	world.add_child(cage)
	var locker: PrisonerLocker = load("res://features/world/projection/containers/prisoner_locker_container.tscn").instantiate()
	locker.container_id = "lockpick.validation.locker"
	locker.position = Vector3(4, 0, 0)
	world.add_child(locker)
	var door: WorldDoor = load("res://scenes/building_pieces/quaternius/medieval_village_woodbrick/door_wood_flat.tscn").instantiate()
	door.door_id = "lockpick.validation.door"
	door.position = Vector3(-4, 0, 0)
	door.door_definition = door.door_definition.duplicate()
	door.door_definition.default_locked = true
	door.exit_policy_override = "symmetric"
	world.add_child(door)
	mira = add_character("mira", Vector3(.383,-.39,4.0))
	tomas = add_character("tomas", Vector3(3,-.39,4.0))
	var navigation_ready: bool = await world.boot()
	# A native software render can spend the first frame compiling materials.
	# Give that startup work a separate budget; do not relax movement checks.
	if not navigation_ready and DisplayServer.get_name() != "headless":
		navigation_ready = await world.wait_ready(120.0)
	if not navigation_ready:
		check(false, "Production navigation did not become ready")
		finish()
		return
	bridge = BootstrapContext.service(&"lockpick_interactions")
	locks = BootstrapContext.service(&"lockpicking")
	ui = BootstrapContext.service(&"world_interaction")
	check(bridge != null and locks != null, "Production bootstrap installs both lockpicking services")
	# Freeze the failure chance for this success/lifecycle route. Unit regressions
	# cover actual fixed-seed failures/wear; do not retry random work until green.
	locks.settings = locks.settings.duplicate()
	locks.settings.careful_risk = 0.0
	mira.set_skill_level(SkillRules.SUBTERFUGE_LOCKPICKING, 1.0)
	check(PICKS.find_pick(mira.inventory) != null and PICKS.find_pick(tomas.inventory) != null, "Mira and Tomas hydrate their authored starting picks")
	check(cage.assign_prisoner(tomas), "Tomas fits in the actual cage")
	tomas.enter_cell_custody(cage, cage.get_prisoner_position(tomas), cage.get_prisoner_rotation(tomas))
	check(tomas.is_in_cell_custody(), "Custody is active before unlocking")
	check(cage.get_world_context_actions(mira).size() == 2, "Carried pick exposes careful and rushed actions")
	cage.perform_world_context_action("pick_lock", [mira])
	check(not mira.is_actively_lockpicking(), "Approach is not work")
	var start := mira.global_position
	if not await world.wait_until(func(): return mira.is_actively_lockpicking(), 15.0):
		print("LOCKPICK_APPROACH_FAILURE ", FIXTURE.actor_motion_snapshot(mira))
		check(false, "Actor must physically reach the cage and start picking")
		finish()
		return
	check(mira.global_position.distance_to(start) > 1.0, "Production navigation moved the actor, not the validator")
	check(mira.get_lockpick_progress_ratio() == 0.0, "Starting an attempt does not earn a pin")
	var first_attempt_start := Time.get_ticks_msec()
	await capture_work_motion(mira, "female")
	check(await world.wait_until(func(): return mira.get_lockpick_progress_ratio() > .1, 45.0), "A novice completes a slow timed attempt")
	var first_attempt_seconds := (Time.get_ticks_msec() - first_attempt_start) / 1000.0
	check(first_attempt_seconds >= 19.0, "Level-one picking must not race through attempts")
	print("LOCKPICK_NOVICE_FIRST_PASS_SECONDS=", first_attempt_seconds)
	ui._update_progress_bars()
	var bar: ProgressBar = ui.work_progress_bars.get(mira)
	check(bar != null and bar.visible, "Shared gray attempt bar remains visible")
	check(not bar.has_theme_stylebox_override("fill"), "Picking does not replace the shared gray work style")
	check(is_equal_approx(bar.value, snappedf(mira.get_lockpick_attempt_progress_ratio() * 100.0, bar.step)), "Gray bar follows attempt time at the shared bar's native precision")
	var earned := bar.get_node_or_null("LockProgress") as Control
	check(earned != null and earned.visible and not earned is ProgressBar, "Earned progress is a lock symbol, not another bar")
	if earned != null:
		check(earned.get("completed_pins") == 1, "One passed attempt lights one lock pin")
	check(is_equal_approx(mira.get_lockpick_progress_ratio(), 1.0 / 3.0), "First pass earns one third, not elapsed-time progress")
	check(mira.get_body_projection()._lockpick_pose._prop.visible, "Real inventory pick is visible in the hand")
	var hidden_equipment: Array = mira.get_body_projection()._lockpick_pose._hidden.duplicate()
	check(hidden_equipment.size() == 2, "Authored sword and shield both participate in work visibility")
	for record in hidden_equipment:
		check(not record.node.get_ref().visible, "Held equipment is hidden, not unequipped")
	var progress := mira.get_lockpick_progress_ratio()
	mira.set_move_target(Vector3(3,0,3))
	ui._update_progress_bars()
	check(not mira.is_actively_lockpicking() and not bar.visible and (earned == null or not earned.visible), "Move order immediately ends pose, timer and lock symbol")
	for record in hidden_equipment:
		check(record.node.get_ref().visible == record.visible, "Interrupted work restores previous equipment visibility")
	check(is_equal_approx(float(locks.get_state("cell:lockpick.validation").progress), progress), "Interruption retains progress")
	await capture_rise(mira, "female")
	check(await world.wait_until(func(): return not mira.has_move_target(), 12.0), "Replacement move remains usable")
	# The novice attempt above proves real pacing; use explicit experts for the
	# remaining multi-target lifecycle, without changing production timing.
	mira.set_skill_level(SkillRules.SUBTERFUGE_LOCKPICKING, 100.0)
	tomas.set_skill_level(SkillRules.SUBTERFUGE_LOCKPICKING, 1.0)
	cage.perform_world_context_action("pick_lock", [mira])
	check(await world.wait_until(func(): return not cage.is_locked, 40.0), "Resumed physical work unlocks the cage")
	check(not tomas.is_in_cell_custody() and cage.occupant_ids.is_empty(), "Picked cage releases actual custody and assignment")
	check(not mira.is_actively_lockpicking(), "Completion removes pose")
	check(cage.get_world_context_actions(mira).is_empty(), "Unlocked cage has no pick actions")
	check(locker.is_locked and locker.get_world_context_actions(mira).size() == 2, "Locked prisoner storage uses shared tool-gated actions")
	locker.perform_world_context_action("pick_lock", [tomas])
	check(await world.wait_until(func(): return tomas.is_actively_lockpicking(), 15.0), "Male actor physically approaches prisoner storage")
	await capture_work_motion(tomas, "male")
	tomas.set_skill_level(SkillRules.SUBTERFUGE_LOCKPICKING, 100.0)
	check(await world.wait_until(func(): return not locker.is_locked, 40.0), "Shared work unlocks the real prisoner locker")
	await capture_rise(tomas, "male")
	var doors := BootstrapContext.service(&"doors")
	check(doors.get_door_state(door.door_id).is_locked, "Door starts locked")
	door.perform_world_context_action("pick_lock", [mira])
	check(await world.wait_until(func(): return mira.is_actively_lockpicking(), 15.0), "Actor physically approaches the door")
	check(await world.wait_until(func(): return not doors.get_door_state(door.door_id).is_locked, 40.0), "Shared work unlocks the real door")
	var gecs := BootstrapContext.service(&"gecs_world")
	check(gecs.save_gecs_world("user://lockpick_runtime.tres"), "Save actual GECS world")
	check(gecs.load_gecs_world("user://lockpick_runtime.tres"), "Reload actual GECS world")
	bridge.register_target(cage)
	check(not cage.is_locked and bridge._sessions.is_empty(), "Saved unlock restores without stale work claims")
	bridge.register_target(locker)
	door._register_with_door_system()
	check(not locker.is_locked and not doors.get_door_state(door.door_id).is_locked, "Locker and door unlocks also survive GECS reload")
	print("LOCKPICK_LIVE end=",mira.global_position," released=",not tomas.is_in_cell_custody()," saved_unlock=",not cage.is_locked)
	finish()

func capture_work_motion(actor: HumanoidCharacter, label: String) -> void:
	var body := actor.get_body_projection()
	var skeleton := body.get_skeleton()
	var hand := skeleton.find_bone("hand_r")
	var pelvis := skeleton.find_bone("pelvis")
	var low := INF
	var high := -INF
	var initial_hand := Transform3D.IDENTITY
	var hand_moved := false
	var loop_samples := 0
	var saw_enter := false
	if DisplayServer.get_name() != "headless":
		# A dedicated proof camera avoids the normal orbit controller resetting
		# our close view on the next process frame. The real actor is untouched.
		if motion_camera == null:
			motion_camera = Camera3D.new()
			motion_camera.fov = 40.0
			world.add_child(motion_camera)
		motion_camera.global_position = actor.global_position + Vector3(2.8, 2.8, 3.0)
		motion_camera.look_at(actor.global_position + Vector3(0, 0.8, -.25))
		motion_camera.make_current()
	for frame in range(36):
		await get_tree().create_timer(0.1, false).timeout
		check(actor.is_actively_lockpicking(), "%s work remains active throughout motion sample" % label)
		var clip := body.get_current_clip()
		saw_enter = saw_enter or clip == HumanoidBodyProjection.KNEELING_WORK_ENTER
		if loop_samples > 0:
			check(clip == HumanoidBodyProjection.KNEELING_WORK_LOOP, "%s does not replay descent or rise between cycles" % label)
		if clip == HumanoidBodyProjection.KNEELING_WORK_LOOP:
			var height := skeleton.get_bone_global_pose(pelvis).origin.y
			low = minf(low, height)
			high = maxf(high, height)
			if loop_samples == 0:
				initial_hand = skeleton.get_bone_global_pose(hand)
			else:
				hand_moved = hand_moved or not skeleton.get_bone_global_pose(hand).is_equal_approx(initial_hand)
			loop_samples += 1
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.test-results/lockpicking-%s-%02d.png" % [label, frame])
	check(hand_moved, "%s hand moves through the authored work clip" % label)
	check(saw_enter and loop_samples >= 10, "%s enters once then samples multiple work cycles" % label)
	check(high - low < 0.08, "%s stays physically kneeling during work" % label)
	print("LOCKPICK_KNEEL ", label, " loop_samples=", loop_samples, " pelvis_range=", high - low)

func capture_rise(actor: HumanoidCharacter, label: String) -> void:
	var body := actor.get_body_projection()
	check(body.get_current_clip() == HumanoidBodyProjection.KNEELING_WORK_EXIT, "%s disengagement starts the rise" % label)
	for frame in range(10):
		await get_tree().create_timer(0.15, false).timeout
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.test-results/lockpicking-%s-rise-%02d.png" % [label, frame])
	check(body.get_current_clip() not in [HumanoidBodyProjection.KNEELING_WORK_LOOP, HumanoidBodyProjection.KNEELING_WORK_EXIT], "%s finishes rising and releases ordinary animation" % label)

func add_character(id: String, at: Vector3) -> HumanoidCharacter:
	var record: Resource = load("res://features/actors/resources/characters/%s.tres" % id)
	var actor: HumanoidCharacter = load(FIXTURE.ACTOR_PATH).instantiate()
	actor.stable_id = id
	actor.member_name = record.member_name
	actor.appearance_data = PopulationController.appearance_from_record(record.appearance)
	actor.starting_skill_levels = record.skill_levels.duplicate(true)
	actor.set_meta("population_inventory_entries", record.inventory_entries.duplicate(true))
	for item_path in record.equipment_slots.values(): actor.starting_equipment.append(load(item_path))
	actor.position = at
	var members: Node = world.get_node_or_null("PartyMembers")
	if members == null:
		members = Node3D.new()
		members.name = "PartyMembers"
		world.add_child(members)
	members.add_child(actor)
	return actor

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func finish() -> void:
	world.dispose()
	await process_frame
	await process_frame
	print("LOCKPICKING_LIVE_%s failures=%d" % ["OK" if failures.is_empty() else "FAILED", failures.size()])
	quit(0 if failures.is_empty() else 1)
