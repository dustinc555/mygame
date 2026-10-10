extends GutTest
## Exercise the normal Outfitter controls and production actors, not a preview catalog.

const OUTFITTER := preload("res://tools/outfitter/outfitter.tscn")
const CATALOG := preload("res://tools/outfitter/outfitter_catalog.gd")
const HUMAN := preload("res://features/actors/resources/character_races/human.tres")
const JACKET := preload("res://features/inventory/resources/items/traveler_leather_jacket.tres")
const SWORD := preload("res://features/inventory/resources/items/iron_sword.tres")
static var _resource_cache: RefCounted

func before_all() -> void:
	# Retain immutable saved assets for the GUT process, like the preloads above.
	# Releasing the catalog here makes later clothing scripts decode it all again.
	# Each test still creates fresh actors, controls, and fitted mesh instances.
	if _resource_cache == null:
		_resource_cache = CATALOG.new()

func after_each() -> void:
	await get_tree().process_frame

func test_build_control_selects_authored_human_scenes_without_changing_body_identity() -> void:
	var viewer = add_child_autofree(OUTFITTER.instantiate())
	viewer.race_select.item_selected.emit(viewer.catalog.races.find(HUMAN))
	var builds := viewer.get("build_select") as OptionButton
	assert_not_null(builds, "Normal Outfitter exposes the authored Build choices")
	if builds == null: return
	assert_true(builds.is_visible_in_tree())
	assert_eq(_option_labels(builds), ["Regular", "Heroic", "Teen"])
	for body_index in viewer.catalog.bodies(HUMAN).size():
		viewer.body_select.item_selected.emit(body_index)
		var canonical: Resource = viewer.catalog.bodies(HUMAN)[body_index]
		for sample in [["Regular", 23, 1, "regular_visual_scene"], ["Heroic", 23, 60, "heroic_visual_scene"], ["Teen", 15, 1, "teen_visual_scene"]]:
			builds.item_selected.emit(_option_labels(builds).find(sample[0]))
			var appearance: CharacterAppearanceData = viewer.actor.appearance_data
			assert_same(viewer.selected_body, canonical)
			assert_same(appearance.body_archetype, canonical)
			assert_same(appearance.character_race, HUMAN)
			assert_eq(appearance.visual_age_years, sample[1])
			assert_eq(appearance.visual_toughness_level, sample[2])
			var projection: BodyProjection = viewer.actor.get_body_projection()
			assert_same(projection.get_resolved_body_archetype(), canonical)
			var expected_scene: PackedScene = canonical.get(sample[3])
			assert_eq(projection.get_visual_root().get_child(0).scene_file_path, expected_scene.resource_path)
			assert_false(viewer.actor.is_processing())
			assert_false(viewer.actor.is_physics_processing())

func test_normal_outfitter_keeps_animated_female_boots_above_its_floor() -> void:
	var viewer = _human_viewer()
	var female := load("res://features/actors/resources/character_body_archetypes/human_female.tres")
	viewer.select_body(viewer._body_options.find(female))
	var boots := load("res://features/inventory/resources/items/traveler_hide_boots.tres") as ItemDefinition
	assert_true(viewer.equip_item(boots, "feet"))
	var projection: HumanoidBodyProjection = viewer.actor.get_body_projection()
	var player := projection.get_primary_animation_player()
	var floor_y: float = viewer.stage.floor_mesh.global_position.y
	for pose in [["Idle", 0.0], ["Walk", 0.25], ["Walk", 0.65]]:
		viewer.select_animation(pose[0])
		player.seek(pose[1], true)
		player.pause()
		# Keep the ordinary viewer's actor mode and let production processing run.
		await get_tree().process_frame
		await get_tree().process_frame
		assert_ne(viewer.actor.process_mode, Node.PROCESS_MODE_DISABLED)
		var points := projection._footwear_support.posed_points(projection._character_skeleton)
		assert_false(points.is_empty(), "Normal viewer must actually run sole support")
		var lowest := INF
		for point in points: lowest = minf(lowest, point.y)
		assert_between(lowest - floor_y, 0.001, 0.02, "Animated soles must meet the visible studio floor")
		assert_almost_eq(viewer.stage.floor_mesh.global_position.y, floor_y, 0.00001, "Floor stays fixed through poses")

func test_build_change_restores_loadout_animation_and_full_body_camera() -> void:
	var viewer = _human_viewer()
	var clip := _non_idle_animation(viewer.animation_select)
	assert_false(clip.is_empty(), "Exercise a named animation other than the default Idle")
	assert_true(viewer.select_animation(clip))
	assert_true(viewer.equip_item(JACKET, "chest"))
	assert_true(viewer.equip_item(SWORD, "weapon"))
	viewer.select_slot("chest")
	viewer.search.text = "Traveler"
	viewer.filter_equipment(viewer.search.text)
	_set_custom_camera(viewer.stage)
	var camera_before := _camera_state(viewer.stage)
	for label in ["Heroic", "Teen", "Regular"]:
		var old_actor: WorldActor = viewer.actor
		var old_actor_id := old_actor.get_instance_id()
		await _select_build(viewer, label)
		assert_ne(viewer.actor.get_instance_id(), old_actor_id)
		if is_instance_valid(old_actor):
			assert_null(old_actor.get_parent(), "Once ready, the previous actor leaves the studio immediately")
			assert_true(old_actor.is_queued_for_deletion())
		assert_same(viewer.actor.get_parent(), viewer.stage.world)
		assert_same(viewer.actor.get_equipped_item("chest"), JACKET)
		assert_same(viewer.actor.get_equipped_item("weapon"), SWORD)
		var visual: Node3D = viewer.actor.get_body_projection().get_visual_root()
		var expected_scene: PackedScene = viewer.selected_body.get(label.to_lower() + "_visual_scene")
		assert_eq(visual.get_child(0).scene_file_path, expected_scene.resource_path, "Restoring wearables retains the selected body context")
		assert_not_null(visual.get_node_or_null("Equipped_Chest"))
		assert_not_null(visual.find_child("EquippedWeaponVisual", true, false))
		var player: AnimationPlayer = viewer.actor.get_body_projection().get_primary_animation_player()
		assert_eq(viewer.selected_animation, clip)
		assert_eq(player.current_animation, clip)
		assert_eq(player.get_animation(clip).loop_mode, Animation.LOOP_LINEAR)
		assert_eq(_camera_state(viewer.stage), camera_before)
		assert_eq(viewer.selected_slot, "chest")
		assert_eq(viewer.search.text, "Traveler")
		await get_tree().process_frame
		assert_false(is_instance_valid(old_actor), "Replacement releases the old production actor")
	assert_true(viewer.equip_item(null, "chest"))
	assert_null(viewer.actor.get_equipped_item("chest"))
	assert_same(viewer.actor.get_equipped_item("weapon"), SWORD)

func test_build_choice_survives_compatible_race_and_sex_reselection() -> void:
	var viewer = _human_viewer()
	for label in ["Heroic", "Teen"]:
		await _select_build(viewer, label)
		for body_index in viewer.catalog.bodies(HUMAN).size():
			viewer.body_select.item_selected.emit(body_index)
			assert_eq(viewer.build_select.get_item_text(viewer.build_select.selected), label)
			assert_eq(viewer.selected_build, label.to_lower())
			var canonical: Resource = viewer.selected_body
			viewer.race_select.item_selected.emit(viewer.catalog.races.find(HUMAN))
			assert_same(viewer.selected_body, canonical)
			assert_eq(viewer.build_select.get_item_text(viewer.build_select.selected), label)
			assert_same(viewer.actor.appearance_data.body_archetype, canonical)

func test_unvaried_authored_bodies_hide_build_control_and_reset_to_regular_context() -> void:
	var viewer = _human_viewer()
	await _select_build(viewer, "Heroic")
	var checked := 0
	for race_index in viewer.catalog.races.size():
		var race: Resource = viewer.catalog.races[race_index]
		var bodies: Array[Resource] = viewer.catalog.bodies(race)
		for body_index in bodies.size():
			var body := bodies[body_index]
			if body.heroic_visual_scene != null or body.teen_visual_scene != null: continue
			viewer.race_select.item_selected.emit(race_index)
			viewer.body_select.item_selected.emit(body_index)
			assert_false(viewer.build_select.is_visible_in_tree())
			assert_eq(_option_labels(viewer.build_select), ["Regular"])
			assert_eq(viewer.selected_build, "regular")
			assert_same(viewer.actor.appearance_data.body_archetype, body)
			assert_eq(viewer.actor.appearance_data.visual_age_years, 23)
			assert_eq(viewer.actor.appearance_data.visual_toughness_level, 1)
			assert_eq(viewer.body_select.item_count, bodies.size())
			checked += 1
	assert_gt(checked, 0, "Exercise actual supported races without authored build variants")
	viewer.race_select.item_selected.emit(viewer.catalog.races.find(HUMAN))
	assert_true(viewer.build_select.is_visible_in_tree())
	assert_eq(_option_labels(viewer.build_select), ["Regular", "Heroic", "Teen"])

func test_build_change_reacquires_hand_target_without_resetting_orbit_or_zoom() -> void:
	var viewer = _human_viewer()
	assert_true(viewer.equip_item(SWORD, "weapon"))
	for side in ["Right", "Left"]:
		assert_true(viewer.set_view_mode(side + " hand"))
		_set_custom_camera(viewer.stage)
		var camera_before := _camera_state(viewer.stage)
		for label in ["Heroic", "Teen", "Regular"]:
			var old_socket: Node3D = viewer.stage.tracking
			await _select_build(viewer, label)
			var visual: Node3D = viewer.actor.get_body_projection().get_visual_root()
			var socket := visual.find_child(side + "HandGrip", true, false) as Node3D
			assert_not_null(socket)
			assert_ne(socket, old_socket)
			assert_same(viewer.stage.tracking, socket)
			assert_eq(viewer.stage.focus, socket.global_position)
			assert_eq(_camera_state(viewer.stage).slice(1), camera_before.slice(1))
			assert_same(viewer.actor.get_equipped_item("weapon"), SWORD)
			await get_tree().process_frame
			assert_false(is_instance_valid(old_socket))

func test_unavailable_animation_name_is_not_replaced_on_build_change() -> void:
	var viewer = _human_viewer()
	viewer.selected_animation = "Missing inspection clip"
	await _select_build(viewer, "Teen")
	assert_eq(viewer.selected_animation, "Missing inspection clip")
	assert_eq(viewer.animation_select.get_item_text(viewer.animation_select.selected), "Missing inspection clip (unavailable)")
	assert_false(viewer.actor.get_body_projection().get_primary_animation_player().is_playing())

func test_invalid_build_indices_leave_actor_and_context_unchanged() -> void:
	var viewer = _human_viewer()
	await _select_build(viewer, "Teen")
	var actor: WorldActor = viewer.actor
	for index in [-1, viewer.build_select.item_count]:
		viewer.build_select.item_selected.emit(index)
		assert_same(viewer.actor, actor)
		assert_eq(viewer.selected_build, "teen")
		assert_eq(actor.appearance_data.visual_age_years, 15)

func test_catalog_keeps_default_context_and_falls_back_for_unknown_build() -> void:
	var catalog = CATALOG.new()
	var body: Resource = HUMAN.default_male_archetype
	var default_actor = autofree(catalog.create_actor(HUMAN, body))
	var unknown_actor = autofree(catalog.create_actor(HUMAN, body, "unknown"))
	for actor in [default_actor, unknown_actor]:
		assert_same(actor.appearance_data.body_archetype, body)
		assert_eq(actor.appearance_data.visual_age_years, 23)
		assert_eq(actor.appearance_data.visual_toughness_level, 1)

func test_equipment_list_only_shows_selected_slot_even_while_searching() -> void:
	var viewer = _human_viewer()
	var boots := load("res://features/inventory/resources/items/traveler_hide_boots.tres") as ItemDefinition
	var pants := load("res://features/inventory/resources/items/traveler_trousers.tres") as ItemDefinition
	for sample in [["feet", boots, pants], ["legs", pants, boots]]:
		viewer.slot_select.item_selected.emit(viewer._slots.find(sample[0]))
		assert_has(viewer._visible_items, sample[1])
		assert_does_not_have(viewer._visible_items, sample[2], "Other slots are excluded, not merely grayed out")
		assert_does_not_have(viewer._visible_items, JACKET)
		viewer.search.text = "Traveler"
		viewer.search.text_changed.emit(viewer.search.text)
		assert_has(viewer._visible_items, sample[1])
		assert_does_not_have(viewer._visible_items, sample[2], "Search stays inside the selected slot")
		viewer.search.text = "no matching equipment fixture"
		viewer.search.text_changed.emit(viewer.search.text)
		assert_eq(viewer.equipment_list.item_count, 0)
		viewer.search.clear()
		viewer.search.text_changed.emit("")


func test_shared_clothing_equip_preserves_body_animation_and_other_slots() -> void:
	var viewer = _human_viewer()
	var pants := load("res://features/inventory/resources/items/traveler_trousers.tres") as ItemDefinition
	assert_true(viewer.equip_item(JACKET, "chest"))
	var body: HumanoidBodyProjection = viewer.actor.get_body_projection()
	var visual_id := body.get_visual_root().get_instance_id()
	var jacket_id := body.get_visual_root().get_node("Equipped_Chest").get_instance_id()
	var player := body.get_primary_animation_player()
	var player_id := player.get_instance_id()
	var skeleton_id := body._character_skeleton.get_instance_id()
	assert_true(viewer.select_animation("Walk"))
	player.seek(0.31, true)
	player.pause()
	for equipped in [true, false]:
		if equipped: viewer.actor.equip_item_to_slot(pants, "legs")
		else: viewer.actor.unequip_item_from_slot("legs")
		var visual := body.get_visual_root()
		assert_eq(visual.get_instance_id(), visual_id, "Changing a garment retains the body")
		assert_eq(body._character_skeleton.get_instance_id(), skeleton_id, "Skinning stays on the same live skeleton")
		assert_eq(visual.get_node("Equipped_Chest").get_instance_id(), jacket_id, "Unchanged clothing is not rebuilt")
		assert_eq(body.get_primary_animation_player().get_instance_id(), player_id)
		assert_eq(visual.has_node("Equipped_Legs"), equipped)
		assert_same(viewer.actor.get_equipped_item("chest"), JACKET)
		if is_instance_valid(player):
			assert_false(player.is_playing())
			assert_almost_eq(player.current_animation_position, 0.31, 0.0001)


func test_batched_clothing_keeps_live_skinning_and_preview_visibility_across_human_builds() -> void:
	var viewer = _human_viewer()
	var pants := load("res://features/inventory/resources/items/traveler_trousers.tres") as ItemDefinition
	var boots := load("res://features/inventory/resources/items/traveler_hide_boots.tres") as ItemDefinition
	for body_index in viewer.catalog.bodies(HUMAN).size():
		viewer.body_select.item_selected.emit(body_index)
		for label in ["Regular", "Heroic", "Teen"]:
			await _select_build(viewer, label)
			var body: HumanoidBodyProjection = viewer.actor.get_body_projection()
			var visual := body.get_visual_root()
			var skeleton := body.get_skeleton()
			body.set_preview_clothes_visible(false)
			viewer.actor.get_equipment().begin_equipment_update_batch()
			viewer.actor.equip_item_to_slot(pants, "legs")
			viewer.actor.equip_item_to_slot(boots, "feet")
			viewer.actor.equip_item_to_slot(SWORD, "weapon")
			viewer.actor.get_equipment().end_equipment_update_batch()
			assert_same(body.get_visual_root(), visual)
			assert_same(body.get_skeleton(), skeleton)
			for slot in ["Legs", "Feet"]:
				var clothing := visual.get_node("Equipped_" + slot) as Node3D
				assert_false(clothing.visible)
				var meshes: Array[MeshInstance3D] = []
				body._collect_mesh_instances(clothing, meshes)
				assert_gt(meshes.size(), 0)
				for mesh in meshes:
					assert_not_null(mesh.skin)
					assert_same(mesh.get_node(mesh.skeleton), skeleton)
			assert_not_null(visual.find_child("EquippedWeaponVisual", true, false))
			body.set_preview_clothes_visible(true)
			assert_true(visual.get_node("Equipped_Legs").visible)

func test_outfitter_equip_retains_paused_inspection_frame() -> void:
	var viewer = _human_viewer()
	viewer.select_slot("chest")
	assert_true(viewer.select_animation("Walk"))
	var player: AnimationPlayer = viewer.actor.get_body_projection().get_primary_animation_player()
	player.seek(0.31, true)
	player.pause()
	for item in [JACKET, null]:
		assert_true(viewer.equip_item(item, "chest"))
		assert_same(viewer.actor.get_body_projection().get_primary_animation_player(), player)
		assert_false(player.is_playing(), "Equipping does not restart a paused inspection")
		assert_almost_eq(player.current_animation_position, 0.31, 0.0001)
		var selected: PackedInt32Array = viewer.equipment_list.get_selected_items()
		if item == null: assert_true(selected.is_empty())
		else: assert_eq(selected, PackedInt32Array([viewer._visible_items.find(item)]))


func test_rustdead_new_clothing_keeps_burned_presentation() -> void:
	var race := load("res://features/actors/resources/character_races/rustdead.tres")
	var actor: WorldActor = _resource_cache.create_actor(race, race.default_male_archetype)
	add_child_autofree(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	var body := actor.get_body_projection() as RustdeadBodyProjection
	assert_not_null(body)
	actor.get_vitals().life_state = NpcRules.LifeState.DEAD
	body.apply_cinder_burned_visuals()
	var jacket := JACKET.duplicate(false) as ItemDefinition
	jacket.compatible_races = PackedStringArray()
	actor.equip_item_to_slot(jacket, "chest")
	var clothing := body.get_visual_root().get_node_or_null("Equipped_Chest")
	assert_not_null(clothing)
	if clothing == null: return
	assert_true(body._node_has_cinder_burned_material(clothing), "An incremental garment inherits the actor's burned presentation")
	actor.unequip_item_from_slot("chest")
	assert_false(is_instance_valid(clothing))
	assert_true(body.has_cinder_burned_visuals())
	body.clear_cinder_burned_visuals()
	assert_false(body.has_cinder_burned_visuals())


func test_cold_build_selection_keeps_ui_live_and_latest_choice_wins() -> void:
	var viewer = _human_viewer()
	var jacket := _cold_jacket("user://outfitter_cold_build.tscn")
	assert_true(viewer.equip_item(jacket, "chest"))
	var original: WorldActor = viewer.actor
	viewer.build_select.item_selected.emit(viewer._build_options.find("heroic"))
	assert_same(viewer.actor, original, "Cold fits load before replacing the actor, without blocking this input callback")
	viewer.build_select.item_selected.emit(viewer._build_options.find("regular"))
	await _drain_fits(viewer)
	assert_eq(viewer.selected_build, "regular", "A superseded load must not switch the body afterward")
	assert_same(viewer.actor.get_equipped_item("chest"), jacket)
	DirAccess.remove_absolute("user://outfitter_cold_build.tscn")

func test_cold_equipment_requests_are_independent_per_slot() -> void:
	var viewer = _human_viewer()
	var path := "user://outfitter_cold_equip.tscn"
	var jacket := _cold_jacket(path, "regular")
	viewer._request_equip(jacket, "chest")
	assert_null(viewer.actor.get_equipped_item("chest"), "An uncached choice yields instead of blocking")
	viewer._request_equip(SWORD, "weapon")
	await _drain_fits(viewer)
	assert_same(viewer.actor.get_equipped_item("chest"), jacket, "Equipping another slot does not discard the pending garment")
	assert_same(viewer.actor.get_equipped_item("weapon"), SWORD)
	DirAccess.remove_absolute(path)

func test_removing_a_slot_cancels_its_pending_cold_equipment() -> void:
	var viewer = _human_viewer()
	var path := "user://outfitter_cancel_equip.tscn"
	var jacket := _cold_jacket(path, "regular")
	viewer._request_equip(jacket, "chest")
	viewer._request_equip(null, "chest")
	await _drain_fits(viewer)
	assert_null(viewer.actor.get_equipped_item("chest"))
	assert_false(viewer._loadout.has("chest"))
	DirAccess.remove_absolute(path)

func test_pending_build_resumes_after_viewer_remount() -> void:
	var viewer = _human_viewer()
	var path := "user://outfitter_remount_build.tscn"
	var jacket := _cold_jacket(path)
	assert_true(viewer.equip_item(jacket, "chest"))
	viewer.select_slot("chest")
	viewer.build_select.item_selected.emit(viewer._build_options.find("heroic"))
	assert_true(viewer._building)
	assert_true(viewer.equipment_list.is_item_disabled(0), "Do not accept clothes against the old body while its replacement loads")
	var old_loader = viewer._fit_loader
	var parent: Node = viewer.get_parent()
	parent.remove_child(viewer)
	parent.add_child(viewer)
	await get_tree().process_frame
	await _drain_fits(viewer)
	assert_eq(viewer.selected_build, "heroic")
	assert_same(viewer.actor.get_equipped_item("chest"), jacket)
	assert_false(viewer.equipment_list.is_item_disabled(0))
	assert_true(old_loader._closed)
	assert_false(old_loader._running)
	assert_true(old_loader._scenes.is_empty())
	DirAccess.remove_absolute(path)

func test_missing_fit_keeps_actor_and_restores_build_controls() -> void:
	var viewer = _human_viewer()
	var path := "user://outfitter_missing_build.tscn"
	var jacket := _cold_jacket(path)
	DirAccess.remove_absolute(path)
	assert_true(viewer.equip_item(jacket, "chest"))
	var original: WorldActor = viewer.actor
	var heroic: int = viewer._build_options.find("heroic")
	viewer.build_select.select(heroic)
	viewer.build_select.item_selected.emit(heroic)
	await _drain_fits(viewer)
	assert_same(viewer.actor, original)
	assert_eq(viewer.build_select.get_item_text(viewer.build_select.selected), "Regular")
	assert_false(viewer._building)
	assert_false(viewer.remove_button.disabled)
	assert_true(viewer.status.text.contains("Could not load clothing"))
	assert_same(viewer.actor.get_equipped_item("chest"), jacket)

func test_failed_native_fit_request_is_released() -> void:
	var viewer = _human_viewer()
	var path := "user://outfitter_broken_fit.tscn"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("[gd_scene format=3]\n[node name=\"Broken\" type=\"Node3D\"]\nposition = broken\n")
	file.close()
	var paths: Array[String] = [path]
	viewer._fit_loader.request(paths, get_tree())
	await _drain_fits(viewer)
	assert_eq(viewer._fit_loader.failed_path(paths), path)
	assert_eq(ResourceLoader.load_threaded_get_status(path), ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "Even failed native requests are consumed, not leaked")
	assert_engine_error("Parse Error")
	assert_engine_error("Failed loading resource")
	DirAccess.remove_absolute(path)

func _cold_jacket(path: String, build: String = "heroic") -> ItemDefinition:
	# Tiny uncached saved scene isolates the loading lifecycle, not garment fit.
	var node := MeshInstance3D.new()
	node.mesh = BoxMesh.new()
	var scene := PackedScene.new()
	assert_eq(scene.pack(node), OK)
	node.free()
	assert_eq(ResourceSaver.save(scene, path), OK)
	var item := JACKET.duplicate(false) as ItemDefinition
	item.equipped_visuals = []
	for source: Resource in JACKET.equipped_visuals:
		var visual := source.duplicate(false)
		visual.body_fits = source.body_fits.duplicate()
		visual.body_fits[HUMAN.default_male_archetype.get(build + "_visual_scene").resource_path] = path
		item.equipped_visuals.append(visual)
	return item

func _drain_fits(viewer) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while viewer._fit_loader._running and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert_false(viewer._fit_loader._running, "Bounded completion of requested native loads")


func test_bone_sliders_change_live_clothed_skeleton_without_rebuilding() -> void:
	var viewer = _human_viewer()
	var sliders = viewer.get("bone_sliders")
	assert_not_null(sliders, "Normal Outfitter exposes the creator's four bone sliders")
	if sliders == null: return
	var properties := ["height_slider", "shoulder_width_slider", "arm_length_slider", "neck_length_slider"]
	assert_eq(sliders.size(), properties.size())
	var pants := load("res://features/inventory/resources/items/traveler_trousers.tres") as ItemDefinition
	assert_true(viewer.equip_item(pants, "legs"))
	assert_true(viewer.select_animation("Walk"))
	var original: WorldActor = viewer.actor
	var body := original.get_body_projection() as HumanoidBodyProjection
	var skeleton := body.get_skeleton()
	var visual := body.get_visual_root()
	var clothing := visual.get_node("Equipped_Legs")
	var player := body.get_primary_animation_player()
	player.seek(0.31, true)
	player.pause()
	_set_custom_camera(viewer.stage)
	var camera_before := _camera_state(viewer.stage)
	for property in properties:
		var slider: HSlider = sliders[property]
		assert_eq(slider.min_value, -1.0)
		assert_eq(slider.max_value, 1.0)
		assert_eq(slider.step, 0.01)
		for value in [-1.0, 1.0, 0.0]:
			slider.value = value
			assert_eq(original.appearance_data.get(property), value)
			assert_eq(body.appearance_data.get(property), value)
			assert_same(viewer.actor, original)
			assert_same(body.get_visual_root(), visual)
			assert_same(visual.get_node("Equipped_Legs"), clothing)
			assert_same(body.get_skeleton(), skeleton)
			assert_same(body.get_primary_animation_player(), player)
			assert_false(player.is_playing())
			assert_almost_eq(player.current_animation_position, 0.31, 0.0001)
			assert_eq(_camera_state(viewer.stage), camera_before)
			var samples: Dictionary = {
				"height_slider": ["calf_l", Vector3(0, 0.024, 0)],
				"shoulder_width_slider": ["clavicle_l", Vector3(0.020, 0, 0)],
				"arm_length_slider": ["lowerarm_l", Vector3(0, 0.018, 0)],
				"neck_length_slider": ["Head", Vector3(0, 0.018, 0)],
			}
			var bone_name: String = samples[property][0]
			var bone := skeleton.find_bone(bone_name)
			var base: Vector3 = viewer.selected_body.bone_pose_position_offsets.get(bone_name, Vector3.ZERO)
			var expected: Vector3 = skeleton.get_bone_rest(bone).origin + base + samples[property][1] * value
			assert_lt(skeleton.get_bone_pose_position(bone).distance_to(expected), 0.00001, "Slider changes the actual bone, including reset")
	var meshes := clothing.find_children("*", "MeshInstance3D", true, false)
	assert_gt(meshes.size(), 0)
	for mesh: MeshInstance3D in meshes:
		assert_same(mesh.get_node(mesh.skeleton), skeleton, "Clothing follows the modified skeleton")

func test_bone_sliders_survive_animation_build_changes_and_reset() -> void:
	var viewer = _human_viewer()
	viewer.bone_sliders["height_slider"].value = 1.0
	viewer.bone_sliders["shoulder_width_slider"].value = -0.5
	for build in ["Regular", "Heroic", "Teen"]:
		await _select_build(viewer, build)
		assert_eq(viewer.actor.appearance_data.height_slider, 1.0)
		assert_eq(viewer.actor.appearance_data.shoulder_width_slider, -0.5)
		var body := viewer.actor.get_body_projection() as HumanoidBodyProjection
		var skeleton := body.get_skeleton()
		assert_true(viewer.select_animation("Walk"))
		var player := body.get_primary_animation_player()
		for step in 3:
			player.advance(0.17)
			var calf := skeleton.find_bone("calf_l")
			var base: Vector3 = viewer.selected_body.bone_pose_position_offsets.get("calf_l", Vector3.ZERO)
			var expected := skeleton.get_bone_rest(calf).origin + base + Vector3(0, 0.024, 0)
			assert_lt(skeleton.get_bone_pose_position(calf).distance_to(expected), 0.00001, "Animation must not undo the slider")
	viewer.reset_bones_button.pressed.emit()
	for property: String in viewer.bone_sliders:
		assert_eq(viewer.bone_sliders[property].value, 0.0)
		assert_eq(viewer.actor.appearance_data.get(property), 0.0)
		assert_eq(viewer.actor.get_body_projection().appearance_data.get(property), 0.0)

func _human_viewer():
	var viewer = add_child_autofree(OUTFITTER.instantiate())
	viewer.race_select.item_selected.emit(viewer.catalog.races.find(HUMAN))
	return viewer

func _select_build(viewer, label: String) -> void:
	var index := _option_labels(viewer.build_select).find(label)
	assert_gte(index, 0, "Build is available: " + label)
	viewer.build_select.item_selected.emit(index)
	var deadline := Time.get_ticks_msec() + 10000
	while viewer._building and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert_false(viewer._building, "The selected build finished loading")

func _non_idle_animation(option: OptionButton) -> String:
	for clip in _option_labels(option):
		if clip not in ["Idle", "RESET"]: return clip
	return ""

func _set_custom_camera(stage) -> void:
	stage.focus = Vector3(0.13, 0.72, -0.21)
	stage.camera.fov = 33.0
	stage.set_view(1.23, 0.31, 2.73)

func _camera_state(stage) -> Array:
	return [stage.focus, stage.yaw, stage.pitch, stage.distance, stage.camera.fov]

func _option_labels(option: OptionButton) -> Array[String]:
	var labels: Array[String] = []
	for index in option.item_count: labels.append(option.get_item_text(index))
	return labels
