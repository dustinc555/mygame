extends GutTest

const STATE_PATH := "res://features/world_map/sim/c_map_exploration_state.gd"

func test_revealing_ground_is_local_permanent_and_handles_negative_coordinates() -> void:
	assert_true(ResourceLoader.exists(STATE_PATH), "Saved exploration must be implemented")
	if not ResourceLoader.exists(STATE_PATH):
		return
	var state = load(STATE_PATH).new()
	assert_false(state.is_discovered(Vector2(-20, -20)))
	var changed: Array = state.reveal_circle(Vector2(-20, -20), 36.0)
	assert_gt(changed.size(), 0)
	assert_true(state.is_discovered(Vector2(-20, -20)))
	assert_false(state.is_discovered(Vector2(80, 80)))
	assert_eq(state.reveal_circle(Vector2(-20, -20), 36.0).size(), 0, "Standing still does not change the map")
	state.reveal_circle(Vector2(500, 500), 36.0)
	assert_true(state.is_discovered(Vector2(-20, -20)), "Leaving does not erase exploration")
	var restored = load(STATE_PATH).new()
	restored.apply_state(state.to_state())
	assert_true(restored.is_discovered(Vector2(-20, -20)))
	assert_true(restored.is_discovered(Vector2(500, 500)))
	assert_false(restored.is_discovered(Vector2(80, 80)))

func test_party_exploration_uses_gecs_save_and_survives_projection_loss() -> void:
	var controller_path := "res://features/world_map/bridge/map_exploration_controller.gd"
	assert_true(ResourceLoader.exists(controller_path), "Party travel must drive saved discovery")
	if not ResourceLoader.exists(controller_path):
		return
	var root := Node3D.new()
	add_child(root)
	var context := BootstrapContext.new(root)
	var gecs := GecsWorldController.new()
	root.add_child(gecs)
	context.register(GecsWorldController.SERVICE_ID, gecs)
	gecs.initialize(context)
	gecs.set_process(false)
	var party := PartyManager.new()
	party.name = "PartyManager"
	root.add_child(party)
	var actor := HumanoidCharacter.new()
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.stable_id = "map.test.scout"
	root.add_child(actor)
	party.register_party_member(actor)
	var exploration = load(controller_path).new()
	root.add_child(exploration)
	exploration.initialize(context)
	exploration.set_physics_process(false)
	exploration.observe_party()
	assert_true(exploration.state.is_discovered(Vector2.ZERO))
	assert_false(exploration.state.is_discovered(Vector2(900, 900)))
	assert_true(gecs.save_gecs_world("user://map-exploration.tres"))
	actor.position = Vector3(900, 0, 900)
	exploration.observe_party()
	assert_true(exploration.state.is_discovered(Vector2(900, 900)))
	assert_true(gecs.load_gecs_world("user://map-exploration.tres"))
	assert_true(exploration.state.is_discovered(Vector2.ZERO))
	assert_false(exploration.state.is_discovered(Vector2(900, 900)), "Loading restores saved knowledge, not unsaved discovery")
	actor.free()
	exploration.observe_party()
	assert_false(exploration.is_observed(Vector2.ZERO))
	assert_true(exploration.state.is_discovered(Vector2.ZERO))
	root.queue_free()
	await get_tree().process_frame

func test_sparse_mask_matches_negative_chunks_and_does_not_reveal_other_ground() -> void:
	var state = load(STATE_PATH).new()
	var mask = load("res://features/world_map/projection/map_discovery_mask.gd")
	state.reveal_circle(Vector2(-8, -8), 48)
	for area in [Rect2(-256, -256, 512, 512), Rect2(-32, -32, 32, 32), Rect2(-4096, -4096, 8192, 8192)]:
		var image: Image = mask.render(state, area, 128)
		var point := Vector2i((Vector2(-8, -8) - area.position) / area.size * 128)
		assert_gt(image.get_pixelv(point).r, 0.0, "Known ground survives map scale changes")
	var untouched: Image = mask.render(state, Rect2(1024, 1024, 256, 256), 128)
	assert_eq(untouched.get_pixel(64, 64).r, 0.0)

func test_remembered_building_does_not_track_remote_changes() -> void:
	var world := Node3D.new()
	add_child(world)
	var source = load("res://features/world_map/bridge/map_world_source.gd").new()
	var exploration = load("res://features/world_map/bridge/map_exploration_controller.gd").new()
	world.add_child(exploration)
	exploration.set_physics_process(false)
	exploration.state = load(STATE_PATH).new()
	exploration.feature_source = source
	exploration.observers.append(Vector2.ZERO)
	var building := WorldBuilding.new()
	building.building_id = "remembered.house"
	world.add_child(building)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	building.add_child(mesh)
	source.register_node(building)
	exploration.refresh_observed_features()
	assert_true(exploration.state.known_features.has("building:remembered.house"))
	exploration.observers.assign([Vector2(1000, 1000)])
	building.position.x = 200
	source.register_node(building)
	exploration.refresh_observed_features()
	assert_eq(exploration.state.known_features["building:remembered.house"]["world"], Vector2.ZERO, "Unseen movement does not leak into remembered map")
	exploration.observers.assign([Vector2.ZERO])
	exploration.refresh_observed_features()
	assert_false(exploration.state.known_features.has("building:remembered.house"), "Revisiting confirms the old building is gone")
	source.dispose()
	world.queue_free()
	await get_tree().process_frame
