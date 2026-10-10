extends GutTest

const WORLD_MODULE := preload("res://features/world/world_module.gd")
const BOOTSTRAP := preload("res://features/core/game_bootstrap.gd")
const PROFILE := preload("res://features/audio/resources/ambient_music_profile.gd")
var _native_warning_acknowledged := false

class MusicReceiver extends Node:
	var current_profile: Resource
	var deliveries: Array = []

	func set_music_profile(profile: Resource) -> void:
		current_profile = profile
		deliveries.append(profile)


func test_startup_delivers_camera_zones_music_without_player_lookup() -> void:
	var fixture := _fixture()
	if fixture.is_empty():
		return
	assert_same(fixture.receiver.current_profile, fixture.first.ambient_music)
	assert_eq(fixture.receiver.deliveries.size(), 1)
	assert_eq(fixture.receiver.current_profile.tracks, PackedStringArray(["res://uninstalled_music/first.ogg"]))


func test_camera_crossing_updates_profile_and_leaving_all_zones_clears_it() -> void:
	var fixture := _fixture()
	if fixture.is_empty():
		return
	_move(fixture, Vector3(256, 100, 32))
	assert_same(fixture.receiver.current_profile, fixture.second.ambient_music)
	_move(fixture, Vector3(512, 100, 32))
	assert_null(fixture.receiver.current_profile)
	_move(fixture, Vector3(255.99, -100, 32))
	assert_same(fixture.receiver.current_profile, fixture.first.ambient_music, "Zone geography ignores altitude")
	assert_eq(fixture.receiver.deliveries.size(), 4)


func test_motion_within_zone_and_camera_orbit_do_not_redeliver_profile() -> void:
	var fixture := _fixture()
	if fixture.is_empty():
		return
	_move(fixture, Vector3(255.9, 10, 255.9))
	fixture.camera.camera_distance = 80.0
	fixture.camera.camera_yaw = 0.0
	fixture.camera._apply_camera_transform()
	assert_gt(fixture.camera.camera.global_position.z, 256.0, "Actual camera crosses the edge while its focus stays put")
	assert_same(fixture.receiver.current_profile, fixture.first.ambient_music)
	assert_eq(fixture.receiver.deliveries.size(), 1)


func test_active_profile_edits_publish_but_inactive_edits_do_not() -> void:
	var fixture := _fixture()
	if fixture.is_empty():
		return
	var replacement := PROFILE.new()
	replacement.tracks = PackedStringArray(["res://uninstalled_music/replacement.ogg"])
	fixture.second.ambient_music = replacement
	assert_eq(fixture.receiver.deliveries.size(), 1)
	fixture.first.ambient_music = replacement
	assert_same(fixture.receiver.current_profile, replacement)
	assert_eq(fixture.receiver.deliveries.size(), 2)
	_move(fixture, Vector3(300, 10, 32))
	assert_eq(fixture.receiver.deliveries.size(), 2, "Shared profiles are not restarted at a zone boundary")
	fixture.second.ambient_music = null
	assert_null(fixture.receiver.current_profile)
	fixture.first.ambient_music = PROFILE.new()
	assert_eq(fixture.receiver.deliveries.size(), 3, "Departed zone has been disconnected")


func test_removing_zone_clears_music_without_camera_motion() -> void:
	var fixture := _fixture()
	if fixture.is_empty():
		return
	fixture.first.queue_free()
	await get_tree().process_frame
	assert_null(fixture.receiver.current_profile)
	assert_null(fixture.zones.get_zone_at_position(Vector3(32, 10, 32)))
	_move(fixture, Vector3(300, 10, 32))
	assert_same(fixture.receiver.current_profile, fixture.second.ambient_music)


func test_late_terrain_and_negative_region_are_discovered_without_motion() -> void:
	var fixture := _fixture()
	if fixture.is_empty():
		return
	_move(fixture, Vector3(-1, 10, 32))
	assert_null(fixture.receiver.current_profile)
	_terrain(fixture.first, fixture.camera.camera, Vector3(-256, 0, 0))
	await get_tree().process_frame
	assert_same(fixture.receiver.current_profile, fixture.first.ambient_music)
	assert_null(fixture.zones.get_zone_at_position(Vector3(-256.01, 0, 32)))
	assert_same(fixture.zones.get_zone_at_position(Vector3(-256, 0, 32)), fixture.first)


func test_native_region_changes_refresh_stationary_camera() -> void:
	var fixture := _fixture()
	if fixture.is_empty():
		return
	_move(fixture, Vector3(600, 10, 32))
	assert_null(fixture.receiver.current_profile)
	var height := Image.create(256, 256, false, Image.FORMAT_RF)
	height.fill(Color(12, 0, 0))
	fixture.terrain.data.import_images([height, null, null], Vector3(512, 0, 0), 0.0, 1.0)
	await get_tree().process_frame
	assert_same(fixture.receiver.current_profile, fixture.first.ambient_music)
	fixture.terrain.queue_free()
	await get_tree().process_frame
	assert_null(fixture.receiver.current_profile)


func test_zone_source_teardown_clears_profile() -> void:
	var fixture := _fixture()
	if fixture.is_empty():
		return
	fixture.zones.queue_free()
	await get_tree().process_frame
	assert_null(fixture.receiver.current_profile)
	_move(fixture, Vector3(300, 10, 32))
	assert_null(fixture.receiver.current_profile)


func test_retiring_bridge_cannot_clear_replacement_worlds_profile() -> void:
	var fixture := _fixture()
	if fixture.is_empty():
		return
	var replacement = fixture.bridge.get_script().new()
	fixture.world.add_child(replacement)
	replacement.initialize(fixture.context)
	fixture.bridge.queue_free()
	await get_tree().process_frame
	assert_same(fixture.receiver.current_profile, fixture.first.ambient_music)
	_move(fixture, Vector3(300, 10, 32))
	assert_same(fixture.receiver.current_profile, fixture.second.ambient_music)
	replacement.queue_free()
	await get_tree().process_frame
	assert_null(fixture.receiver.current_profile)


func test_freed_player_and_missing_optional_player_are_safe() -> void:
	var fixture := _fixture()
	if fixture.is_empty():
		return
	fixture.receiver.queue_free()
	await get_tree().process_frame
	_move(fixture, Vector3(300, 10, 32))
	var without_player = fixture.bridge.get_script().new()
	fixture.world.add_child(without_player)
	without_player.initialize(BootstrapContext.new(fixture.first))
	assert_same(fixture.zones.get_current_zone(), fixture.second)


func _move(fixture: Dictionary, position: Vector3) -> void:
	fixture.camera.camera_anchor = position
	fixture.camera._apply_camera_transform()


func _fixture() -> Dictionary:
	var zone_script: Script
	var bridge_script: Script
	for spec in WORLD_MODULE.BRIDGE:
		if spec.service == &"world_zones":
			zone_script = spec.script
	for module in BOOTSTRAP.MODULES:
		for spec in module.BRIDGE:
			if spec.service == &"zone_music":
				bridge_script = spec.script
	assert_not_null(zone_script, "Bootstrap must install the camera-zone source")
	assert_not_null(bridge_script, "Bootstrap must install profile delivery to the player")
	if zone_script == null or bridge_script == null:
		return {}
	var world := WorldRoot.new()
	add_child_autofree(world)
	var first := Zone.new()
	first.name = "FirstZone"
	first.ambient_music = PROFILE.new()
	first.ambient_music.tracks = PackedStringArray(["res://uninstalled_music/first.ogg"])
	world.add_child(first)
	var second := Zone.new()
	second.name = "SecondZone"
	second.ambient_music = PROFILE.new()
	second.ambient_music.tracks = PackedStringArray(["res://uninstalled_music/second.ogg"])
	world.add_child(second)
	var camera_source := WorldInteractionController.new()
	camera_source.set_process(false)
	world.add_child(camera_source)
	camera_source.party_manager = PartyManager.new()
	world.add_child(camera_source.party_manager)
	camera_source.camera_rig = Node3D.new()
	world.add_child(camera_source.camera_rig)
	camera_source.camera_pivot = Node3D.new()
	camera_source.camera_rig.add_child(camera_source.camera_pivot)
	camera_source.camera = Camera3D.new()
	camera_source.camera_pivot.add_child(camera_source.camera)
	camera_source.camera_anchor = Vector3(32, 10, 32)
	camera_source._apply_camera_transform()
	var terrain = _terrain(first, camera_source.camera, Vector3.ZERO)
	var second_terrain = _terrain(second, camera_source.camera, Vector3(256, 0, 0))
	var context := BootstrapContext.new(first)
	context.register(WorldInteractionController.SERVICE_ID, camera_source)
	var zones = zone_script.new()
	world.add_child(zones)
	context.register(zone_script.SERVICE_ID, zones)
	zones.initialize(context)
	var receiver := MusicReceiver.new()
	add_child_autofree(receiver)
	context.register(bridge_script.MUSIC_PLAYER_SERVICE_ID, receiver)
	var bridge = bridge_script.new()
	world.add_child(bridge)
	bridge.initialize(context)
	return {"world": world, "first": first, "second": second, "camera": camera_source,
		"terrain": terrain, "second_terrain": second_terrain, "zones": zones,
		"receiver": receiver, "bridge": bridge, "context": context}


func _terrain(zone: Zone, camera: Camera3D, origin: Vector3):
	var terrain = ClassDB.instantiate("Terrain3D")
	terrain.region_size = 256
	terrain.collision_mode = 0
	zone.add_child(terrain)
	terrain.set_camera(camera)
	terrain.set_physics_process(false)
	var height := Image.create(256, 256, false, Image.FORMAT_RF)
	height.fill(Color(12, 0, 0))
	terrain.data.import_images([height, null, null], origin, 0.0, 1.0)
	for error in get_errors():
		if not _native_warning_acknowledged and error.contains_text("instance_reset_physics_interpolation() is deprecated."):
			assert_engine_error("instance_reset_physics_interpolation() is deprecated.")
			_native_warning_acknowledged = true
	return terrain
