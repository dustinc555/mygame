extends RefCounted
var failures: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _camera_state(stage) -> Array:
	return [stage.focus, stage.yaw, stage.pitch, stage.distance, stage.camera.fov]

func _custom_camera(stage) -> void:
	stage.focus = Vector3(0.13, 0.72, -0.21)
	stage.camera.fov = 33.0
	stage.set_view(1.23, 0.31, 2.73)

func _camera_cases(viewer) -> void:
	var stage = viewer.stage
	check(viewer._camera_initialized, "First body initializes camera")
	check(stage.focus.is_equal_approx(viewer.actor.get_body_projection().get_visual_local_bounds().get_center()), "Initial body auto-framed")
	check(is_equal_approx(stage.ruler.meters_to_feet(0.3048), 1.0), "Exact international foot conversion")
	check(is_equal_approx(stage.ruler.meters_to_feet(1.0), 3.280839895), "Meter conversion")
	stage.set_body_reference(AABB(Vector3(-0.3, 0.42, -0.2), Vector3(0.6, 2.3, 0.4)))
	check(is_equal_approx(stage.ruler.ground_y, 0.42), "Ruler zero uses nonzero foot clearance")
	check(is_equal_approx(stage.floor_mesh.position.y, 0.405), "Floor below foot datum")
	check(stage.ruler.upper_extent >= 2.3, "Ruler covers body extent")
	for angle in [0.0, 1.2, 3.1]:
		stage.set_view(angle, 0.35, 3.5)
		var body_mark := Vector3(0, 1.42, 0)
		var body_screen: Vector2 = stage.camera.unproject_position(body_mark)
		var expected_y: float = body_screen.y * stage.ruler.size.y / stage.camera.get_viewport().get_visible_rect().size.y
		check(absf(expected_y - stage.ruler.project_height(1.0)) < 0.01, "Ruler gutter projects body-plane height while orbiting")
	var toggle_camera := _camera_state(stage)
	viewer.ruler_toggle.button_pressed = false
	check(not stage.ruler.visible, "Toggle hides ruler")
	check(_camera_state(stage) == toggle_camera, "Hiding ruler preserves camera")
	viewer.ruler_toggle.button_pressed = true
	check(stage.ruler.visible, "Toggle restores ruler")
	check(_camera_state(stage) == toggle_camera, "Showing ruler preserves camera")
	var missing_seen := false
	for race_index in viewer.catalog.races.size():
		viewer.set_view_mode("Full body")
		_custom_camera(stage)
		var before := _camera_state(stage)
		viewer.select_race(race_index)
		check(_camera_state(stage) == before, "Race switch retains full camera")
		for body_index in viewer.catalog.bodies(viewer.selected_race).size():
			viewer.select_body(body_index)
			check(_camera_state(stage) == before, "Body switch retains full camera")
			for mode in ["Right hand", "Left hand"]:
				viewer.set_view_mode(mode)
				_custom_camera(stage)
				var hand_before := _camera_state(stage)
				viewer.select_body(body_index)
				check(_camera_state(stage).slice(1) == hand_before.slice(1), "Hand rebuild retains angle/zoom/FOV")
				var socket = viewer.actor.get_body_projection().get_visual_root().find_child("RightHandGrip" if mode == "Right hand" else "LeftHandGrip", true, false)
				if socket == null:
					missing_seen = true
					check(stage.tracking == null and _camera_state(stage) == hand_before, "Missing socket freezes complete camera")
					check(viewer.status.text == "No hand socket authored for this body.", "Missing socket warning")
				else:
					check(stage.tracking == socket and stage.focus.is_equal_approx(socket.global_position), "Hand reacquired on new body")
					# A real wearable can replace the skeleton/socket, unlike a no-op None.
					for item in viewer.catalog.items:
						if item.equip_slot == "weapon" or not viewer.incompatibility(item, item.equip_slot).is_empty(): continue
						viewer.equip_item(item, item.equip_slot)
						check(_camera_state(stage).slice(1) == hand_before.slice(1), "Wearable rebuild retains hand camera")
						var new_socket = viewer.actor.get_body_projection().get_visual_root().find_child("RightHandGrip" if mode == "Right hand" else "LeftHandGrip", true, false)
						check(stage.tracking == new_socket, "Wearable reacquires current socket")
						viewer.equip_item(null, item.equip_slot)
						break
					viewer.equip_item(null, "weapon")
					check(_camera_state(stage).slice(1) == hand_before.slice(1), "Hand equip retains angle/zoom/FOV")
					stage.track_hand(null)
					var lost := _camera_state(stage)
					stage._process(0.0)
					check(stage.tracking == null and _camera_state(stage) == lost, "Lost tracking keeps camera")
			viewer.set_view_mode("Full body")
			check(stage.tracking == null and stage.camera.fov == 40, "Explicit Full body reframes")
			check(stage.focus.is_equal_approx(viewer.actor.get_body_projection().get_visual_local_bounds().get_center()), "Explicit Full body focuses bounds")
			_custom_camera(stage)
			before = _camera_state(stage)
	check(missing_seen, "Production missing-socket case exercised")
	viewer.set_view_mode("Right hand")
	for race_index in viewer.catalog.races.size():
		_custom_camera(stage)
		var before := _camera_state(stage)
		viewer.select_race(race_index)
		check(_camera_state(stage).slice(1) == before.slice(1), "Hand race switch retains angle/zoom/FOV")
		if stage.tracking == null:
			check(_camera_state(stage) == before, "Hand to socketless race preserves full view")
		else:
			check(stage.focus.is_equal_approx(stage.tracking.global_position), "Hand race switch reacquires target")
	viewer.set_view_mode("Full body")

func run(tree: SceneTree) -> void:
	var viewer = load("res://tools/outfitter/outfitter.tscn").instantiate()
	tree.root.add_child(viewer)
	await tree.process_frame
	check(not viewer.stage.ruler.get_global_rect().intersects(viewer.stage.get_global_rect()), "Ruler never overlaps character viewport")
	_camera_cases(viewer)
	var ids: Array[String] = []
	var all_paths: Array[String] = []
	for item in viewer.catalog.items:
		check(not all_paths.has(item.resource_path), "Unique item path")
		all_paths.append(item.resource_path)
	var expected := 0
	for path in viewer.catalog.resource_paths(viewer.catalog.ITEMS):
		var item := load(path) as ItemDefinition
		if item != null and item.is_equippable(): expected += 1
	check(expected == all_paths.size(), "All catalog equipment enumerated")
	var body_count := 0
	var accepted := 0
	var denied := 0
	for race_index in viewer.catalog.races.size():
		viewer.select_race(race_index)
		ids.append(viewer.selected_race.race_id)
		var bodies: Array = viewer.catalog.bodies(viewer.selected_race)
		for body_index in bodies.size():
			viewer.select_body(body_index)
			body_count += 1
			var actor: WorldActor = viewer.actor
			var body := actor.get_body_projection()
			check(body != null and body.get_visual_root() != null, "Real production projection: " + viewer.selected_race.race_id)
			check(actor.get_script() == viewer.catalog.actor_script_for(viewer.selected_race, viewer.selected_body), "Production actor class")
			check(body.get_resolved_body_archetype() == bodies[body_index], "Canonical saved body identity")
			check(load(viewer.selected_body.resource_path) == viewer.selected_body, "Saved body, not synthesized")
			check(actor.get("appearance_data").character_race == viewer.selected_race, "Canonical race identity")
			viewer.filter_equipment("")
			check(viewer.equipment_list.item_count == expected, "Empty search includes all")
			viewer.filter_equipment("nonexistent-outfitter-item")
			check(viewer.equipment_list.item_count == 0, "Search filters")
			viewer.filter_equipment("")
			check(viewer.equipment_list.item_count == expected, "Clear search restores all")
			var player := body.get_primary_animation_player()
			check(player != null, "Production animation player")
			check(viewer.select_animation("Idle"), "Idle available")
			for item in viewer.catalog.items:
				var slot: String = item.equip_slot
				var can := actor.get_equipment().can_equip_item_to_slot(item, slot)
				var previous := actor.get_equipped_item(slot)
				var camera_before := _camera_state(viewer.stage)
				var ground_before: float = viewer.stage.ruler.ground_y
				check(viewer.equip_item(item, slot) == can, "Compatibility: " + item.item_id)
				if can:
					accepted += 1
					check(actor.get_equipped_item(slot) == item, "Real equipped definition")
					if body is HumanoidBodyProjection and slot == "weapon" and item.get_equipped_scene_for_body_archetype(viewer.selected_body) != null:
						check(body.get_visual_root().find_child("EquippedWeaponVisual", true, false) != null, "Mounted production weapon")
					check(viewer.equip_item(null, slot), "None removes equipment")
					check(actor.get_equipped_item(slot) == null, "None clears capability")
					if body is HumanoidBodyProjection and slot == "weapon":
						check(body.get_visual_root().find_child("EquippedWeaponVisual", true, false) == null, "None removes mounted weapon")
				else:
					denied += 1
					check(actor.get_equipped_item(slot) == previous, "Denied equip preserves previous")
				check(_camera_state(viewer.stage) == camera_before, "Equip/remove retains full camera")
				check(viewer.stage.ruler.ground_y == ground_before, "Equipment leaves ground datum unchanged")
				player = body.get_primary_animation_player()
				check(viewer.selected_animation == "Idle" and player.current_animation == "Idle", "Equip retains animation")
			check(player.get_animation("Idle").loop_mode == Animation.LOOP_LINEAR, "Selected animation loops")
			check(viewer.set_view_mode("Full body"), "Full-body view")
			viewer.select_body(body_index)
			check(viewer.selected_animation == "Idle", "Rebuild retains selection")
			await tree.process_frame
	ids.sort()
	var expected_ids: Array[String] = []
	for race in PopulationAppearanceProfile._get_available_races(): expected_ids.append(race.race_id)
	expected_ids.sort()
	check(ids == expected_ids, "All registered races")
	check(accepted > 0 and denied > 0, "Both compatibility branches exercised")
	viewer.queue_free()
	await tree.process_frame
	print("OUTFITTER_RESULT races=%s bodies=%d items=%d accepted=%d denied=%d checks=%d failures=%d" % [ids, body_count, expected, accepted, denied, checks, failures.size()])
	tree.quit(0 if failures.is_empty() else 1)
