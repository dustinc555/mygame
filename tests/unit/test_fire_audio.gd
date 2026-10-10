extends GutTest

const TORCH := preload("res://features/world/projection/props/lighting/wall_torch.tscn")
const POOL_PATH := "res://features/audio/projection/fire_audio_voices.gd"

var _temporary_audio_paths: Array[String] = []


func after_each() -> void:
	get_tree().paused = false
	for path in _temporary_audio_paths:
		DirAccess.remove_absolute(path)
	_temporary_audio_paths.clear()


func _audio_world(with_listener := true) -> Dictionary:
	assert_true(FileAccess.file_exists(POOL_PATH), "Fire playback must have a shared bounded voice owner")
	if not FileAccess.file_exists(POOL_PATH):
		return {}
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.audio_listener_enable_3d = true
	add_child_autofree(viewport)
	var pool = load(POOL_PATH).new()
	pool.name = "FireAudioVoices"
	pool.settings = load("res://features/audio/resources/fire_audio_settings.tres").duplicate(true)
	var cue = load("res://features/audio/resources/fire_loop_cue.gd").new()
	var source := AudioStreamWAV.new()
	source.format = AudioStreamWAV.FORMAT_16_BITS
	source.mix_rate = 8000
	var data := PackedByteArray()
	data.resize(32000)
	for frame in range(16000):
		data.encode_s16(frame * 2, roundi(sin(frame * 0.2) * 1000.0))
	source.data = data
	var path := "user://fire_playback_%s.tres" % source.get_instance_id()
	assert_eq(ResourceSaver.save(source, path), OK)
	_temporary_audio_paths.append(path)
	cue.paths = PackedStringArray([path])
	cue.volume_db = -24.0
	pool.settings.small_flame = cue
	pool.settings.campfire = cue.duplicate(true)
	pool.settings.campfire.volume_db = -10.0
	viewport.add_child(pool)
	var listener: AudioListener3D
	if with_listener:
		listener = AudioListener3D.new()
		viewport.add_child(listener)
		listener.make_current()
	return {"viewport": viewport, "pool": pool, "listener": listener}


func test_real_light_transitions_start_and_stop_native_loop_playback() -> void:
	var world := _audio_world()
	if world.is_empty():
		return
	var fixture = TORCH.instantiate()
	world.viewport.add_child(fixture)
	await get_tree().process_frame
	world.pool.refresh()
	var audio := fixture.get_node("FireAudio") as AudioStreamPlayer3D
	assert_true(audio.playing, "A nearby lit fire must actually play")
	assert_not_null(audio.get_stream_playback())
	assert_eq((audio.stream as AudioStreamWAV).loop_mode, AudioStreamWAV.LOOP_FORWARD)
	var playback := audio.get_stream_playback()
	fixture._apply_hour(20)
	world.pool.refresh()
	assert_same(audio.get_stream_playback(), playback, "Repeated lit updates do not restart the loop")
	fixture._apply_hour(12)
	assert_false(audio.playing, "Daytime stops immediately, not on a later poll")
	fixture._apply_hour(20)
	world.pool.refresh()
	assert_true(audio.playing)
	assert_eq(audio.attenuation_model, AudioStreamPlayer3D.ATTENUATION_DISABLED)
	assert_eq(audio.attenuation_filter_db, 0.0)
	assert_eq(audio.max_distance, world.pool.settings.small_flame_distance_m)


func test_furnace_plays_only_during_its_real_burn_effect() -> void:
	var world := _audio_world()
	if world.is_empty():
		return
	var furnace = load("res://features/world/bridge/props/body_furnace.tscn").instantiate()
	world.viewport.add_child(furnace)
	await get_tree().process_frame
	var audio := furnace.get_node_or_null("FireAudio") as AudioStreamPlayer3D
	assert_not_null(audio, "A furnace needs audio tied to its actual active burn, not its name")
	if audio == null:
		return
	world.pool.refresh()
	assert_false(audio.playing, "An idle furnace must be silent on realization")
	var carrier := HumanoidCharacter.new()
	carrier.process_mode = Node.PROCESS_MODE_DISABLED
	world.viewport.add_child(carrier)
	var body := HumanoidCharacter.new()
	body.process_mode = Node.PROCESS_MODE_DISABLED
	world.viewport.add_child(body)
	body.get_vitals().set_life_state(NpcRules.LifeState.DEAD)
	assert_true(furnace.place_carried_body(carrier, body), "Existing accepted-body mechanics activate the fire")
	world.pool.refresh()
	assert_true(audio.playing)
	assert_true(furnace.get_node("BurnEffect").visible)
	furnace._process(furnace.burn_seconds + 1.0)
	assert_false(audio.playing)
	assert_false(furnace.get_node("BurnEffect").visible)
	assert_true(body.is_queued_for_deletion(), "Audio does not change body consumption")



func test_authored_fire_follows_real_light_state() -> void:
	var fixture = TORCH.instantiate()
	add_child_autofree(fixture)
	await get_tree().process_frame
	var audio := fixture.get_node_or_null("FireAudio") as AudioStreamPlayer3D
	assert_not_null(audio, "Authored fire furniture needs a positional loop child")
	if audio == null:
		return
	assert_true(fixture.is_fire_active())
	fixture._apply_hour(12)
	assert_false(fixture.is_fire_active())
	assert_false(audio.playing, "The actual daytime light transition must silence fire")
	fixture._apply_hour(20)
	assert_true(fixture.is_fire_active())


func test_listener_absence_distance_and_camera_fallback() -> void:
	var world := _audio_world(false)
	var fixture = TORCH.instantiate()
	world.viewport.add_child(fixture)
	await get_tree().process_frame
	var audio := fixture.get_node("FireAudio") as AudioStreamPlayer3D
	world.pool.refresh()
	assert_false(audio.playing, "No listener must not allocate audible voices")
	var camera := Camera3D.new()
	world.viewport.add_child(camera)
	camera.make_current()
	world.pool.refresh()
	assert_true(audio.playing, "Godot's current camera is a valid listener fallback")
	camera.position = Vector3(100, 0, 0)
	world.pool.refresh()
	assert_false(audio.playing, "Far emitters are stopped, not merely mixed inaudibly")
	camera.position = Vector3.ZERO
	world.pool.refresh()
	assert_true(audio.playing)
	world.viewport.audio_listener_enable_3d = false
	world.pool.refresh()
	assert_false(audio.playing)


func test_wall_torch_mix_is_quieter_and_shorter_without_changing_campfires() -> void:
	var settings = load("res://features/audio/resources/fire_audio_settings.tres")
	assert_almost_eq(db_to_linear(settings.small_flame.volume_db) / db_to_linear(-10.0), 0.8, 0.0001, "Wall torches use 80 percent of the previous gain")
	assert_eq(settings.campfire.volume_db, -10.0)
	for spec: Dictionary in [
		{"scene": TORCH, "radius": 6.0, "volume_db": settings.small_flame.volume_db},
		{"scene": load("res://features/camps/projection/fire_pit.tscn"), "radius": 33.0, "volume_db": -10.0},
		{"scene": load("res://features/camps/projection/campfire_tripod.tscn"), "radius": 33.0, "volume_db": -10.0},
	]:
		var world := _audio_world()
		# Keep test-owned PCM while exercising the saved production gain settings.
		world.pool.settings.small_flame.volume_db = settings.small_flame.volume_db
		var fixture: Node3D = spec.scene.instantiate()
		world.viewport.add_child(fixture)
		await get_tree().process_frame
		var audio := fixture.get_node("FireAudio") as AudioStreamPlayer3D
		world.listener.global_position = audio.global_position + Vector3(spec.radius * 0.5, 0, 0)
		world.pool.refresh()
		assert_true(audio.playing, "Fire is active within its own range")
		assert_almost_eq(audio.volume_db, spec.volume_db, 0.00001, "The saved gain reaches native playback without inherited torch offsets on campfires")
		assert_eq(audio.max_distance, spec.radius, "Native attenuation and voice selection use the same authored range")
		world.listener.global_position = audio.global_position + Vector3(spec.radius - 0.1, 0, 0)
		world.pool.refresh()
		assert_true(audio.playing)
		world.listener.global_position = audio.global_position + Vector3(spec.radius, 0, 0)
		world.pool.refresh()
		assert_false(audio.playing, "The new range still bounds playback")


func test_small_flame_mixed_output_fades_within_its_reduced_range() -> void:
	var world := _audio_world(false)
	var bus_index := AudioServer.bus_count
	AudioServer.add_bus()
	var bus_name := "FireMixTest%s" % get_instance_id()
	AudioServer.set_bus_name(bus_index, bus_name)
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(bus_index, capture)
	world.pool.settings.bus = bus_name
	var camera := Camera3D.new()
	world.viewport.add_child(camera)
	camera.make_current()
	var fixture = TORCH.instantiate()
	world.viewport.add_child(fixture)
	await get_tree().process_frame
	var audio := fixture.get_node("FireAudio") as AudioStreamPlayer3D
	var levels: Array[float] = []
	for distance in [0.25, 4.0, 5.5, 6.0]:
		camera.global_position = audio.global_position + Vector3(0, 0, distance)
		world.pool.refresh()
		# Let native spatial mixing settle, then discard samples from the old position.
		await get_tree().create_timer(0.15).timeout
		capture.clear_buffer()
		await get_tree().create_timer(0.15).timeout
		var samples := capture.get_buffer(capture.get_frames_available())
		assert_gt(samples.size(), 0, "Measure real mixed samples, not just the playing flag")
		var peak := 0.0
		for sample in samples:
			peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
		levels.append(peak)
	assert_gt(levels[0], 0.0)
	assert_gt(levels[1], levels[0] * 0.25, "At 4 m the torch retains useful output, rather than stacked inverse-distance/filter silence")
	assert_gt(levels[2], levels[0] * 0.04, "A listener just within the reduced range still receives fire output")
	assert_lt(levels[2], levels[1], "The sound still fades with distance")
	assert_lt(levels[3], 0.00000001, "The 6 m cutoff silences the actual mix")
	fixture._set_lit(false)
	AudioServer.remove_bus(bus_index)


func test_voice_budget_chooses_near_fires_and_releases_destroyed_voices() -> void:
	var world := _audio_world()
	world.pool.settings.max_audible_fires = 2
	var fixtures: Array[Node3D] = []
	for index in range(5):
		var fixture = TORCH.instantiate()
		fixture.position.x = index + 1
		world.viewport.add_child(fixture)
		fixtures.append(fixture)
	await get_tree().process_frame
	world.pool.refresh()
	for index in range(5):
		assert_eq(fixtures[index].get_node("FireAudio").playing, index < 2)
	fixtures[0].queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	world.pool.refresh()
	assert_true(fixtures[2].get_node("FireAudio").playing, "A removed fire releases its voice")
	var playing := 0
	for index in range(1, 5):
		if fixtures[index].get_node("FireAudio").playing:
			playing += 1
	assert_eq(playing, 2)
	world.pool.settings.max_audible_fires = 1
	world.pool.refresh()
	assert_true(fixtures[1].get_node("FireAudio").playing)
	assert_false(fixtures[2].get_node("FireAudio").playing, "The shared Inspector limit changes real playback")


func test_pause_resume_and_tree_reentry_do_not_leak_or_duplicate_playback() -> void:
	var world := _audio_world()
	var fixture = TORCH.instantiate()
	world.viewport.add_child(fixture)
	await get_tree().process_frame
	world.pool.refresh()
	var audio := fixture.get_node("FireAudio") as AudioStreamPlayer3D
	# Spatial playback is submitted in the physics phase. Pause an active
	# native voice, not the queued play() request from the process frame above.
	await get_tree().physics_frame
	await get_tree().process_frame
	var playback := audio.get_stream_playback()
	assert_true(playback.is_playing(), "Native playback has started before testing pause")
	assert_true(audio.playing)
	get_tree().paused = true
	assert_true(audio.stream_paused)
	get_tree().paused = false
	assert_false(audio.stream_paused)
	assert_same(audio.get_stream_playback(), playback, "Native pause resumes rather than relights")
	world.viewport.remove_child(fixture)
	assert_false(audio.playing)
	world.viewport.add_child(fixture)
	await get_tree().process_frame
	world.pool.refresh()
	assert_true(audio.playing, "Re-realization binds to the current semantic state")
	assert_eq(fixture.get_signal_connection_list("fire_active_changed").size(), 1)


func test_missing_files_and_opted_out_fixtures_remain_silent() -> void:
	var world := _audio_world()
	world.pool.settings.small_flame.paths = PackedStringArray(["res://missing_licensed_fire.wav"])
	var fixture = TORCH.instantiate()
	world.viewport.add_child(fixture)
	await get_tree().process_frame
	world.pool.refresh()
	var audio := fixture.get_node("FireAudio") as AudioStreamPlayer3D
	assert_false(audio.playing)
	assert_null(audio.stream)
	audio.fire_kind = 0
	world.pool.settings.small_flame = world.pool.settings.campfire
	world.pool.refresh()
	assert_false(audio.playing)
	for scene in ["candle_1", "candle_2", "candle_3", "candlestick"]:
		var candle = load("res://features/world/projection/props/lighting/%s.tscn" % scene).instantiate()
		world.viewport.add_child(candle)
		assert_null(candle.get_node_or_null("FireAudio"), "Unselected fixtures are not inferred from light or appearance")


func test_campfire_scenes_use_larger_mix_and_fixture_level_is_live() -> void:
	var world := _audio_world()
	var torch = TORCH.instantiate()
	world.viewport.add_child(torch)
	for path in ["fire_pit", "campfire_tripod"]:
		var camp = load("res://features/camps/projection/%s.tscn" % path).instantiate()
		world.viewport.add_child(camp)
		await get_tree().process_frame
		world.pool.refresh()
		var audio := camp.get_node("FireAudio") as AudioStreamPlayer3D
		assert_true(audio.playing)
		assert_eq(audio.fire_kind, 2)
		assert_eq(audio.attenuation_model, AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE, "The campfire mix is unchanged")
		assert_eq(audio.attenuation_filter_db, -24.0)
		assert_gt(audio.max_distance, torch.get_node("FireAudio").max_distance)
		assert_gt(audio.volume_db, torch.get_node("FireAudio").volume_db)
		var playback := audio.get_stream_playback()
		audio.fire_level_db = -7.0
		world.pool.refresh()
		assert_eq(audio.volume_db, -17.0, "Fixture level offsets the shared campfire cue")
		assert_same(audio.get_stream_playback(), playback, "Level tuning does not reset the loop")
		camp._apply_hour(12)
		assert_false(audio.playing)


func test_canonical_world_clock_drives_fire_without_visual_visibility_guessing() -> void:
	var previous_context := BootstrapContext.active
	var context := BootstrapContext.new()
	var clock := WorldTimeController.new()
	clock.start_hour = 12
	add_child_autofree(clock)
	clock.set_process(false)
	context.register(WorldTimeController.SERVICE_ID, clock)
	BootstrapContext.active = context
	var world := _audio_world()
	var fixture = TORCH.instantiate()
	world.viewport.add_child(fixture)
	await get_tree().process_frame
	world.pool.refresh()
	var audio := fixture.get_node("FireAudio") as AudioStreamPlayer3D
	assert_false(audio.playing, "A daytime realization does not play a lighting sound")
	clock.advance_hours(20 - 12)
	world.pool.refresh()
	assert_true(audio.playing)
	fixture.get_light_node().visible = false
	fixture.visible = false
	world.pool.refresh()
	assert_true(audio.playing, "LOD and roof cutaways must not extinguish an actual fire")
	clock.advance_hours(24 - 20 + 7)
	assert_false(audio.playing)
	fixture.always_on = true
	clock.advance_hours(12 - 7)
	world.pool.refresh()
	assert_true(audio.playing, "Always-on preserves the existing clock override")
	BootstrapContext.active = previous_context


func test_authored_licensed_recordings_are_valid_if_locally_imported() -> void:
	var settings = load("res://features/audio/resources/fire_audio_settings.tres")
	var verified := 0
	for cue in [settings.small_flame, settings.campfire]:
		for path in cue.paths:
			if not ResourceLoader.exists(path, "AudioStream"):
				assert_null(cue.get_loop_stream(path), "Uninstalled licensed assets are optional")
				continue
			var source: AudioStreamWAV = cue.get_stream(path)
			assert_not_null(source)
			assert_false(source.stereo, "Spatial fire imports must be mono")
			assert_eq(source.format, AudioStreamWAV.FORMAT_16_BITS)
			assert_eq(source.loop_mode, AudioStreamWAV.LOOP_DISABLED)
			var original_data := source.data
			var loop: AudioStreamWAV = cue.get_loop_stream(path)
			assert_not_null(loop)
			assert_ne(source, loop)
			assert_eq(loop.loop_mode, AudioStreamWAV.LOOP_FORWARD)
			assert_gt(loop.loop_begin, 0)
			assert_gt(loop.loop_end, loop.loop_begin)
			assert_true(source.data == original_data, "Imported PCM remains unchanged")
			var world := _audio_world()
			var only_this_recording = cue.duplicate(true)
			only_this_recording.paths = PackedStringArray([path])
			world.pool.settings.small_flame = only_this_recording
			var fixture = TORCH.instantiate()
			world.viewport.add_child(fixture)
			await get_tree().process_frame
			world.pool.refresh()
			assert_true(fixture.get_node("FireAudio").playing, path)
			fixture._set_lit(false)
			verified += 1
	gut.p("Locally imported licensed fire recordings exercised: %d / 3" % verified)


func test_loop_preparation_crossfades_interior_without_changing_source() -> void:
	var path := "res://features/audio/resources/fire_loop_cue.gd"
	assert_true(FileAccess.file_exists(path), "Fire loops need safe cached preparation")
	if not FileAccess.file_exists(path):
		return
	var cue = load(path).new()
	var source := AudioStreamWAV.new()
	source.format = AudioStreamWAV.FORMAT_16_BITS
	source.mix_rate = 8000
	var data := PackedByteArray()
	data.resize(32000)
	for frame in range(16000):
		data.encode_s16(frame * 2, frame - 8000)
	source.data = data
	var sample_path := "user://fire_loop_source.tres"
	assert_eq(ResourceSaver.save(source, sample_path), OK)
	cue.paths = PackedStringArray([sample_path])
	cue.edge_trim_seconds = 0.1
	cue.crossfade_seconds = 0.02
	var loop: AudioStreamWAV = cue.get_loop_stream(sample_path)
	assert_not_null(loop)
	assert_ne(loop, source)
	assert_eq(loop.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	assert_eq(loop.loop_begin, 160)
	assert_lt(loop.loop_end, loop.data.size() / 2)
	assert_lt(loop.get_length(), source.get_length(), "Silent file edges are excluded")
	assert_true(source.data == data, "Original PCM is unchanged")
	assert_eq(source.loop_mode, AudioStreamWAV.LOOP_DISABLED)
	var cached_source: AudioStreamWAV = cue.get_stream(sample_path)
	assert_true(cached_source.data == data, "Even the cue's shared decoded source is untouched")
	assert_eq(cached_source.loop_mode, AudioStreamWAV.LOOP_DISABLED)
	assert_same(loop, cue.get_loop_stream(sample_path), "Preparation is cached per recording")
	var seam_step := absi(loop.data.decode_s16((loop.loop_end - 1) * 2) - loop.data.decode_s16(loop.loop_begin * 2))
	assert_lte(seam_step, 2, "Crossfade leads into the next interior sample instead of a discontinuity")
	DirAccess.remove_absolute(sample_path)
