extends GutTest

const AUDIO_PATH := "res://features/lockpicking/projection/unlock_audio_controller.gd"
const LOCKS := preload("res://features/lockpicking/sim/lockpicking_controller.gd")
const BRIDGE := preload("res://features/lockpicking/bridge/lockpick_interaction_controller.gd")


class LockContainer extends WorldContainer:
	func _ready() -> void:
		pass

var context: BootstrapContext
var gecs: GecsWorldController
var doors: DoorController
var locks: Node
var bridge: Node
var audio: Node
var bag: InventoryData
var camera: Camera3D
var previous_context: BootstrapContext

func before_each() -> void:
	previous_context = BootstrapContext.active
	BootstrapContext.active = null
	context = BootstrapContext.new(self)
	gecs = GecsWorldController.new()
	add_child_autofree(gecs)
	context.register(&"gecs_world", gecs)
	gecs.initialize(context)
	gecs.set_process(false)
	doors = DoorController.new()
	add_child_autofree(doors)
	context.register(&"doors", doors)
	doors.initialize(context)
	locks = LOCKS.new()
	add_child_autofree(locks)
	context.register(&"lockpicking", locks)
	locks.initialize(context)
	locks.settings = locks.settings.duplicate()
	locks.settings.careful_risk = 0.0
	bridge = BRIDGE.new()
	add_child_autofree(bridge)
	context.register(&"lockpick_interactions", bridge)
	bridge.initialize(context)
	bag = InventoryData.new()
	bag.entries.append(bag.create_entry(load("res://features/inventory/resources/items/lockpick_fine.tres"), Vector2i.ZERO))
	camera = Camera3D.new()
	add_child_autofree(camera)
	camera.current = true
	if ResourceLoader.exists(AUDIO_PATH):
		audio = load(AUDIO_PATH).new()
		add_child_autofree(audio)
		audio.initialize(context)
		var cue = audio.cue.duplicate()
		cue.paths = PackedStringArray(["synthetic_a", "synthetic_b"])
		cue.pitch_min = 1.0
		cue.pitch_max = 1.0
		var sample := AudioStreamWAV.new()
		sample.format = AudioStreamWAV.FORMAT_8_BITS
		sample.mix_rate = 8000
		var pcm := PackedByteArray()
		pcm.resize(8000)
		pcm.fill(140)
		sample.data = pcm
		for path in cue.paths:
			cue._stream_cache[path] = sample
		audio.cue = cue

func after_each() -> void:
	get_tree().paused = false
	BootstrapContext.active = previous_context

func _container(id := "test") -> WorldContainer:
	var target: WorldContainer = load("res://features/world/projection/containers/container.tscn").instantiate()
	target.set_script(LockContainer)
	target.container_id = id
	target.is_locked = true
	add_child_autofree(target)
	target.position = Vector3(1.0, 0.0, -2.0)
	bridge.register_target(target)
	return target

func _complete(id: String) -> Dictionary:
	assert_true(locks.claim(id, "picker", bag, "careful").accepted)
	return locks.advance(id, "picker", bag, 100.0, 100.0, 120.0)

func _voices() -> Array:
	return audio.get_children().filter(func(node): return node is AudioStreamPlayer3D)

func test_completed_container_unlock_starts_one_positional_voice() -> void:
	assert_not_null(audio, "Successful unlock audio is not implemented")
	if audio == null:
		return
	var target := _container()
	assert_true(_voices().is_empty(), "Registration is not a successful unlock")
	assert_true(_complete("container:test").complete)
	assert_false(target.is_locked)
	assert_eq(_voices().size(), 1)
	if _voices().is_empty():
		return
	var voice: AudioStreamPlayer3D = _voices()[0]
	assert_eq(voice.global_position, target.get_lockpick_contact())
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(voice.playing)
	assert_true(voice.get_stream_playback().is_playing(), "The real native voice starts")
	assert_eq(voice.pitch_scale, 1.0)

func _door(id := "test", extra: Dictionary = {}) -> WorldDoor:
	var record := {"door_id": id, "default_locked": true, "authorized_key_ids": ["test_key"]}
	record.merge(extra, true)
	doors.register_door(record)
	var target := WorldDoor.new()
	add_child_autofree(target)
	target.door_id = id
	target.position = Vector3(2.0, 0.0, -2.0)
	target._door_controller = doors
	bridge.register_target(target)
	return target

func _command(id: String, action: String, snapshot: Dictionary = {}) -> Dictionary:
	if gecs.world.get_entity_by_id("actor:picker") == null:
		var actor = load("res://addons/gecs/ecs/entity.gd").new()
		actor.id = "actor:picker"
		gecs.world.add_entity(actor, [])
	var results: Array[Dictionary] = []
	var callback := func(result: Dictionary): results.append(result)
	doors.door_command_resolved.connect(callback)
	var request := doors.submit_command("picker", id, action, snapshot)
	assert_true(request.accepted)
	if request.accepted:
		doors.begin_command(request.command_id)
		gecs.world.process(0.1)
	doors.door_command_resolved.disconnect(callback)
	assert_eq(results.size(), 1)
	return results[0] if not results.is_empty() else {}

func test_key_unlock_plays_once_but_refusal_repeat_and_plain_open_do_not() -> void:
	var target := _door()
	assert_eq(_command("test", "unlock").get("result_code"), "access_denied")
	assert_true(_voices().is_empty())
	assert_eq(_command("test", "unlock", {"actor_key_ids": ["test_key"]}).get("result_code"), "unlocked")
	assert_eq(_voices().size(), 1, "The authorized key unlock produces one sound")
	if _voices().is_empty(): return
	assert_eq(_voices()[0].global_position, target.get_lockpick_contact())
	assert_eq(_command("test", "unlock").get("result_code"), "already_unlocked")
	assert_eq(_command("test", "open").get("result_code"), "opened")
	assert_eq(_voices().size(), 1, "No duplicate unlock for already-unlocked or opening")

func test_picked_door_plays_once_after_authoritative_completion() -> void:
	_door()
	assert_false(doors.complete_lockpick("test", 0))
	assert_true(_voices().is_empty())
	assert_true(_complete("door:test").complete)
	assert_false(doors.get_door_state("test").is_locked)
	assert_eq(_voices().size(), 1, "Door and lock-work notifications must not double-play")

func test_free_exit_unlock_and_scheduled_unlock_are_audible() -> void:
	_door("exit")
	assert_eq(_command("exit", "open", {"from_inside": true}).get("result_code"), "opened")
	assert_eq(_voices().size(), 1)
	_door("scheduled", {"scheduled_open_hour": 9, "scheduled_close_hour": 17})
	doors._on_world_hour_changed(9, 0, 9)
	assert_false(doors.get_door_state("scheduled").is_locked)
	assert_eq(_voices().size(), 2)

func test_cage_uses_the_same_success_sound() -> void:
	var cage := JailCell.new()
	cage.cell_id = "sound_test"
	add_child_autofree(cage)
	bridge.register_target(cage)
	assert_true(_complete("cell:sound_test").complete)
	assert_false(cage.is_locked)
	assert_eq(_voices().size(), 1)
	assert_eq(_voices()[0].global_position, cage.get_lockpick_contact())

func test_partial_cancelled_and_tool_lost_work_remain_silent() -> void:
	_container()
	assert_true(locks.claim("container:test", "picker", bag, "careful").accepted)
	assert_false(locks.advance("container:test", "picker", bag, 100.0, 100.0, 0.5).complete)
	locks.release("container:test", "picker")
	assert_false(locks.advance("container:test", "picker", bag, 100.0, 100.0, 120.0).accepted)
	assert_true(locks.claim("container:test", "picker", bag, "careful").accepted)
	bag.entries.clear()
	assert_false(locks.advance("container:test", "picker", bag, 100.0, 100.0, 120.0).accepted)
	assert_true(_voices().is_empty())

func test_restoration_registration_and_initial_door_configuration_are_silent() -> void:
	var target := _container()
	assert_true(_complete("container:test").complete)
	assert_true(gecs.save_gecs_world("user://unlock_audio.tres"))
	audio.initialize(context)
	assert_true(gecs.load_gecs_world("user://unlock_audio.tres"))
	bridge.register_target(target)
	assert_false(target.is_locked)
	assert_true(_voices().is_empty())
	doors.configure_building_doors("initial", {"initial_state": "open"})
	_door("initial", {"building_id": "initial"})
	assert_false(doors.get_door_state("initial").is_locked)
	assert_true(_voices().is_empty())

func test_random_choices_do_not_repeat_and_voice_count_is_bounded() -> void:
	_container()
	audio.cue.max_voices = 2
	audio._rng.seed = 17
	var previous := ""
	var chosen := {}
	for i in range(12):
		if i > 0: locks.relock("container:test")
		assert_true(_complete("container:test").complete)
		var latest: AudioStreamPlayer3D = _voices().back()
		var path: String = latest.get_meta("clip_path")
		assert_ne(path, previous)
		assert_true(path in audio.cue.paths)
		assert_lte(_voices().size(), 2)
		chosen[path] = true
		previous = path
	assert_eq(chosen.size(), 2)

func test_authored_volume_distance_and_voice_limit_reach_native_playback() -> void:
	_container()
	audio.cue.volume_db = -17.0
	audio.cue.max_distance_m = 60.0
	audio.cue.unit_size_m = 9.0
	assert_true(_complete("container:test").complete)
	var voice: AudioStreamPlayer3D = _voices()[0]
	assert_eq(voice.volume_db, -17.0)
	assert_eq(voice.max_distance, 60.0)
	assert_eq(voice.unit_size, 9.0)
	locks.relock("container:test")
	audio.cue.max_voices = 1
	assert_true(_complete("container:test").complete)
	assert_eq(_voices().size(), 1)

func test_missing_audio_far_target_and_missing_listener_do_not_block_unlock() -> void:
	var target := _container()
	audio.cue.paths = PackedStringArray(["res://missing_unlock.wav"])
	assert_true(_complete("container:test").complete)
	assert_false(target.is_locked)
	assert_true(_voices().is_empty())
	audio.cue.paths = PackedStringArray(["synthetic_a"])
	locks.relock("container:test")
	target.position = Vector3(1000, 0, 0)
	assert_true(_complete("container:test").complete)
	assert_true(_voices().is_empty())
	locks.relock("container:test")
	target.position = Vector3.ZERO
	camera.free()
	assert_true(_complete("container:test").complete)
	assert_true(_voices().is_empty())

func test_destroyed_projection_is_silent_and_replacement_can_play() -> void:
	var target := _container()
	assert_true(locks.claim("container:test", "picker", bag, "careful").accepted)
	target.free()
	assert_true(locks.advance("container:test", "picker", bag, 100.0, 100.0, 120.0).complete)
	assert_true(_voices().is_empty())
	target = _container()
	assert_false(target.is_locked)
	locks.relock("container:test")
	assert_true(_complete("container:test").complete)
	assert_eq(_voices().size(), 1)
	target.free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(_voices()[0].get_stream_playback().is_playing(), "A started voice owns its captured position, not its target")

func test_reinitialization_disconnects_old_sources_and_pause_drops_sound() -> void:
	audio.initialize(context)
	audio.initialize(context)
	assert_eq(locks.get_signal_connection_list("object_unlocked").size(), 1)
	assert_eq(doors.get_signal_connection_list("door_unlocked").size(), 1)
	_container()
	assert_true(_complete("container:test").complete)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(_voices()[0].get_stream_playback().is_playing())
	get_tree().paused = true
	assert_false(_voices()[0].playing)
	locks.relock("container:test")
	assert_true(_complete("container:test").complete)
	assert_false(_voices()[0].playing)
	get_tree().paused = false
	assert_false(_voices()[0].playing, "Resume must not replay stale unlocks")
	audio.initialize(BootstrapContext.new(self))
	assert_eq(locks.get_signal_connection_list("object_unlocked").size(), 0)
	assert_eq(doors.get_signal_connection_list("door_unlocked").size(), 0)
	assert_true(_voices().is_empty())

func test_finished_voice_releases_its_stream() -> void:
	_container()
	var stream: AudioStreamWAV = audio.cue._stream_cache.synthetic_a
	stream.data = stream.data.slice(0, 800)
	assert_true(_complete("container:test").complete)
	var voice: AudioStreamPlayer3D = _voices()[0]
	await wait_until(func(): return voice.stream == null, 1.0)
	assert_null(voice.stream)

func test_all_selected_vendor_recordings_produce_native_output_when_installed() -> void:
	var authored = load("res://features/lockpicking/resources/unlock_success_sound.tres")
	assert_eq(authored.paths.size(), 5)
	for path: String in authored.paths:
		assert_true("unlock" in path.get_file().to_lower() or "open" in path.get_file().to_lower())
		if not ResourceLoader.exists(path):
			pending("Licensed local-only unlock recordings are not installed")
			return
	var target := _container()
	camera.position = Vector3(0, 10, 10)
	var bus_index := AudioServer.bus_count
	AudioServer.add_bus()
	var bus_name := "UnlockAudioTest%s" % get_instance_id()
	AudioServer.set_bus_name(bus_index, bus_name)
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(bus_index, capture)
	audio.cue = authored.duplicate()
	audio.cue.bus = bus_name
	audio.cue.max_voices = 1
	for path: String in authored.paths:
		var stream := ResourceLoader.load(path, "AudioStreamWAV", ResourceLoader.CACHE_MODE_IGNORE) as AudioStreamWAV
		assert_not_null(stream)
		if stream == null: continue
		assert_gt(stream.get_length(), 0.0)
		assert_false(stream.stereo)
		assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_DISABLED)
		audio.cue.paths = PackedStringArray([path])
		locks.relock("container:test")
		capture.clear_buffer()
		assert_true(_complete("container:test").complete)
		assert_false(target.is_locked)
		assert_eq(_voices().size(), 1)
		if _voices().is_empty(): continue
		var voice: AudioStreamPlayer3D = _voices()[0]
		await get_tree().physics_frame
		await get_tree().physics_frame
		assert_true(voice.get_stream_playback().is_playing())
		assert_eq(voice.get_meta("clip_path"), path)
		await get_tree().create_timer(0.3).timeout
		var peak := 0.0
		for sample in capture.get_buffer(capture.get_frames_available()):
			peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
		assert_gt(peak, 0.000001, "The imported recording reaches the actual mix at elevated camera distance")
		print("UNLOCK_IMPORTED ", JSON.stringify({"path": path, "seconds": stream.get_length(), "peak": peak}))
		voice.stop()
		await get_tree().create_timer(0.05).timeout
	AudioServer.remove_bus(bus_index)
