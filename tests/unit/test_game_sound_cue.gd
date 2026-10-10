extends GutTest

const CUE_PATH := "res://features/audio/resources/game_sound_cue.gd"


func _new_cue():
	if not FileAccess.file_exists(CUE_PATH):
		return null
	return load(CUE_PATH).new()


func test_variations_do_not_immediately_repeat_the_same_recording() -> void:
	var cue = _new_cue()
	assert_not_null(cue, "The shared sound cue must exist")
	if cue == null:
		return
	cue.paths = PackedStringArray(["res://first.wav", "res://second.wav", "res://third.wav"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 73
	var previous := "res://first.wav"
	for index in range(30):
		var chosen: String = cue.choose_path(previous, rng)
		assert_true(cue.paths.has(chosen))
		assert_ne(chosen, previous)
		previous = chosen


func test_empty_and_duplicate_variations_are_safe() -> void:
	var cue = _new_cue()
	var rng := RandomNumberGenerator.new()
	assert_eq(cue.choose_path("", rng), "")
	cue.paths = PackedStringArray(["", "res://only.wav", "res://only.wav"])
	assert_eq(cue.choose_path("res://only.wav", rng), "res://only.wav")
	cue.paths.append("res://other.wav")
	for index in range(10):
		assert_eq(cue.choose_path("res://only.wav", rng), "res://other.wav")


func test_pitch_uses_authored_bounds_even_when_reversed() -> void:
	var cue = _new_cue()
	assert_true(cue.has_method("choose_pitch"), "Sound cues must choose bounded pitch")
	if not cue.has_method("choose_pitch"):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	cue.pitch_min = 1.1
	cue.pitch_max = 0.9
	for index in range(20):
		assert_between(cue.choose_pitch(rng), 0.9, 1.1)
	cue.pitch_min = 1.0
	cue.pitch_max = 1.0
	assert_eq(cue.choose_pitch(rng), 1.0)


func test_missing_local_audio_is_silent_and_can_be_rehydrated() -> void:
	var cue = _new_cue()
	assert_true(cue.has_method("get_stream"), "Sound cues must load optional licensed audio")
	if not cue.has_method("get_stream"):
		return
	var path := "user://game_sound_cue_test.tres"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	assert_null(cue.get_stream(""))
	assert_null(cue.get_stream(path))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = 8000
	stream.data = PackedByteArray([128, 140, 128, 116])
	assert_eq(ResourceSaver.save(stream, path), OK)
	var loaded: AudioStream = cue.get_stream(path)
	assert_not_null(loaded)
	assert_same(cue.get_stream(path), loaded, "A cue must reuse its decoded stream")
	DirAccess.remove_absolute(path)
