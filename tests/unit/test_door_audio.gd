extends GutTest

const DOOR := preload("res://features/doors/projection/world_door.gd")
const CUE := preload("res://features/audio/resources/game_sound_cue.gd")
const TEST_PATH := "test://door_movement.wav"

var _previous_context: BootstrapContext


func before_each() -> void:
	_previous_context = BootstrapContext.active
	BootstrapContext.active = null


func after_each() -> void:
	get_tree().paused = false
	BootstrapContext.active = _previous_context


func _door_world() -> Dictionary:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.audio_listener_enable_3d = true
	add_child_autofree(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0, 4, 5)
	camera.make_current()
	var cue = CUE.new()
	cue.paths = PackedStringArray([TEST_PATH])
	cue.volume_db = -8.0
	cue.pitch_min = 1.0
	cue.pitch_max = 1.0
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 8000
	var data := PackedByteArray()
	data.resize(16000)
	for frame in range(8000):
		data.encode_s16(frame * 2, roundi(sin(frame * 0.2) * 1000.0))
	stream.data = data
	cue._stream_cache[TEST_PATH] = stream
	var door = DOOR.new()
	door.movement_sound = cue
	viewport.add_child(door)
	return {"viewport": viewport, "camera": camera, "door": door, "cue": cue, "stream": stream}


func test_opening_starts_positional_playback() -> void:
	var world := _door_world()
	world.door.apply_door_state({"is_open": false}, false)
	world.door.apply_door_state({"is_open": true})
	var audio := world.door.get_node_or_null("MovementSound") as AudioStreamPlayer3D
	assert_not_null(audio, "An actual open transition must create positional playback")
	if audio == null:
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(audio.playing)
	assert_not_null(audio.get_stream_playback())
	assert_true(audio.get_stream_playback().is_playing())
	assert_same(audio.stream, world.stream)
	assert_eq(audio.global_position, world.door.global_position)
	assert_eq(audio.pitch_scale, 1.0)
	assert_eq(audio.volume_db, -8.0)


func test_closing_uses_the_same_recording() -> void:
	var world := _door_world()
	world.door.apply_door_state({"is_open": true}, false)
	assert_null(world.door.get_node_or_null("MovementSound"), "Restoring an open door is silent")
	world.door.apply_door_state({"is_open": false})
	var audio := world.door.get_node_or_null("MovementSound") as AudioStreamPlayer3D
	assert_not_null(audio)
	if audio == null:
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(audio.get_stream_playback().is_playing())
	assert_same(audio.stream, world.stream)


func test_repeated_state_and_lock_only_updates_do_not_restart_playback() -> void:
	var world := _door_world()
	world.door.door_id = "audio.test"
	world.door.apply_door_state({"is_open": false}, false)
	world.door._on_door_state_changed("another.door", {"is_open": true})
	assert_null(world.door.get_node_or_null("MovementSound"))
	world.door._on_door_state_changed("audio.test", {"is_open": true})
	var audio := world.door.get_node("MovementSound") as AudioStreamPlayer3D
	await get_tree().physics_frame
	await get_tree().physics_frame
	var playback := audio.get_stream_playback()
	world.door._on_door_state_changed("audio.test", {"is_open": true, "is_locked": false})
	assert_same(audio.get_stream_playback(), playback, "Repeated state must not restart a sound")
	audio.stop()
	world.door.apply_door_state({"is_open": false}, false)
	world.door._on_door_state_changed("audio.test", {"is_open": false, "is_locked": true})
	assert_false(audio.playing, "Locking is not door movement")
	world.door._on_door_state_changed("audio.test", {"is_open": false, "is_locked": false})
	assert_false(audio.playing, "Unlocking is not door movement")


func test_registration_with_initial_open_facility_is_silent() -> void:
	var world := _door_world()
	var context := BootstrapContext.new(world.viewport)
	var gecs := GecsWorldController.new()
	world.viewport.add_child(gecs)
	context.register(&"gecs_world", gecs)
	gecs.initialize(context)
	gecs.set_process(false)
	var doors := DoorController.new()
	world.viewport.add_child(doors)
	context.register(&"doors", doors)
	doors.initialize(context)
	BootstrapContext.active = context
	doors.configure_building_doors("audio.building", {"initial_state": "open"})
	world.door.door_id = "audio.initial"
	world.door.building_id = "audio.building"
	world.door._register_with_door_system()
	assert_true(doors.get_door_state("audio.initial").is_open)
	assert_true(world.door._is_open)
	assert_null(world.door.get_node_or_null("MovementSound"), "Registration emits state synchronously; this must not make startup audible")
	# A later controller edge still takes the same production signal path.
	doors.door_state_changed.emit("audio.initial", {"is_open": false})
	var audio := world.door.get_node_or_null("MovementSound") as AudioStreamPlayer3D
	assert_not_null(audio)
	if audio != null:
		assert_true(audio.playing)
	world.door.free()


func test_missing_recording_and_disabled_cue_leave_door_functional() -> void:
	var world := _door_world()
	world.cue._stream_cache.clear()
	world.cue.paths = PackedStringArray(["res://missing_door_recording.wav"])
	world.door.apply_door_state({"is_open": true})
	assert_true(world.door._is_open)
	assert_null(world.door.get_node_or_null("MovementSound"))
	world.door.movement_sound = null
	world.door.apply_door_state({"is_open": false})
	assert_false(world.door._is_open)
	assert_null(world.door.get_node_or_null("MovementSound"))


func test_inspector_controls_reach_playback_and_reversals_reuse_one_voice() -> void:
	var world := _door_world()
	world.door.apply_door_state({"is_open": true})
	var audio := world.door.get_node("MovementSound") as AudioStreamPlayer3D
	world.cue.volume_db = -18.0
	world.door.sound_max_distance_m = 22.0
	world.door.sound_unit_size_m = 7.0
	for index in range(20):
		world.door.apply_door_state({"is_open": index % 2 == 1})
	assert_same(world.door.get_node("MovementSound"), audio)
	assert_eq(world.door.find_children("*", "AudioStreamPlayer3D", false, false).size(), 1)
	assert_eq(audio.max_polyphony, 1)
	assert_eq(audio.volume_db, -18.0)
	assert_eq(audio.max_distance, 22.0)
	assert_eq(audio.unit_size, 7.0)
	assert_eq(audio.pitch_scale, 1.0)
	world.door.position = Vector3(12, 1, -8)
	assert_eq(audio.global_position, world.door.global_position)


func test_pause_and_projection_destruction_release_native_playback() -> void:
	var world := _door_world()
	world.door.apply_door_state({"is_open": true})
	var audio := world.door.get_node("MovementSound") as AudioStreamPlayer3D
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(audio.get_stream_playback().is_playing())
	get_tree().paused = true
	assert_true(audio.stream_paused)
	audio.stop()
	world.door.apply_door_state({"is_open": false})
	assert_false(audio.playing, "No queued door sound while paused")
	get_tree().paused = false
	world.door.apply_door_state({"is_open": true})
	assert_true(audio.playing)
	world.door.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(is_instance_valid(audio))
	var replacement = DOOR.new()
	replacement.movement_sound = world.cue
	world.viewport.add_child(replacement)
	replacement.apply_door_state({"is_open": true}, false)
	assert_null(replacement.get_node_or_null("MovementSound"), "Restored projections do not replay old motion")
	replacement.apply_door_state({"is_open": false})
	assert_true(replacement.get_node("MovementSound").playing)
