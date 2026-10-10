@tool
extends "res://features/audio/resources/game_sound_cue.gd"

## Cached, project-local PCM loop preparation; never changes the imported cue.
## Source import: mono, uncompressed 16-bit WAV, loop disabled. Files remain optional.
@export_range(0.0, 2.0, 0.01, "suffix:s") var edge_trim_seconds := 0.5
@export_range(0.005, 0.5, 0.005, "suffix:s") var crossfade_seconds := 0.08

var _loop_cache: Dictionary = {}


func get_loop_stream(path: String) -> AudioStreamWAV:
	var source := get_stream(path) as AudioStreamWAV
	if source == null or source.format != AudioStreamWAV.FORMAT_16_BITS:
		return null
	var cached: Dictionary = _loop_cache.get(path, {})
	if cached.get("source") == source and cached.get("trim") == edge_trim_seconds and cached.get("fade") == crossfade_seconds:
		return cached.loop
	var channels := 2 if source.stereo else 1
	var frame_bytes := channels * 2
	var source_data := source.data
	var source_frames := source_data.size() / frame_bytes
	if source_frames < 16 or source.mix_rate <= 0:
		return null
	var trim := mini(maxi(0, roundi(edge_trim_seconds * source.mix_rate)), source_frames / 4)
	var data := source_data.slice(trim * frame_bytes, (source_frames - trim) * frame_bytes)
	var frames := data.size() / frame_bytes
	# loop_end is exclusive. Leave the final stored frame outside the loop.
	var end := frames - 1
	var fade := clampi(roundi(crossfade_seconds * source.mix_rate), 2, end / 4)
	for frame in range(fade):
		var weight := float(frame) / float(fade - 1)
		for channel in range(channels):
			var head_offset := (frame * channels + channel) * 2
			var tail_offset := ((end - fade + frame) * channels + channel) * 2
			var head := data.decode_s16(head_offset)
			var tail := data.decode_s16(tail_offset)
			data.encode_s16(tail_offset, roundi(lerpf(tail, head, weight)))
	var loop := source.duplicate() as AudioStreamWAV
	loop.data = data
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_begin = fade
	loop.loop_end = end
	_loop_cache[path] = {"source": source, "trim": edge_trim_seconds, "fade": crossfade_seconds, "loop": loop}
	return loop
