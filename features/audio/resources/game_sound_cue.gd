@tool
extends Resource
class_name GameSoundCue

## A small group of interchangeable recordings. Paths keep licensed, local-only
## audio optional without making resource/script loading fail on a fresh checkout.
@export var cue_id: StringName = &""
@export_file("*.wav", "*.ogg") var paths: PackedStringArray = PackedStringArray()
@export_range(-60.0, 6.0, 0.5) var volume_db := -6.0
@export_range(0.5, 2.0, 0.01) var pitch_min := 0.98
@export_range(0.5, 2.0, 0.01) var pitch_max := 1.02

var _stream_cache: Dictionary = {}


func choose_path(previous_path: String, rng: RandomNumberGenerator) -> String:
	var candidates: PackedStringArray = PackedStringArray()
	for path: String in paths:
		if not path.is_empty() and path != previous_path and not candidates.has(path):
			candidates.append(path)
	if candidates.is_empty():
		for path: String in paths:
			if not path.is_empty():
				return path
		return ""
	return candidates[rng.randi_range(0, candidates.size() - 1)]


func choose_pitch(rng: RandomNumberGenerator) -> float:
	var low := clampf(minf(pitch_min, pitch_max), 0.5, 2.0)
	var high := clampf(maxf(pitch_min, pitch_max), low, 2.0)
	return rng.randf_range(low, high)


func get_stream(path: String) -> AudioStream:
	if _stream_cache.has(path):
		return _stream_cache[path] as AudioStream
	if path.is_empty() or not ResourceLoader.exists(path, "AudioStream"):
		return null
	var stream := ResourceLoader.load(path, "AudioStream") as AudioStream
	if stream != null:
		_stream_cache[path] = stream
	return stream
