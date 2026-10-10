extends AudioStreamPlayer3D

## Projection-only fire loop. Its parent owns the actual fire/light state.
const FireVoices = preload("res://features/audio/projection/fire_audio_voices.gd")
const FireSettings = preload("res://features/audio/resources/fire_audio_settings.gd")

@export_enum("Silent", "Small Flame", "Campfire") var fire_kind := 0:
	set(value):
		fire_kind = clampi(value, 0, 2)
		stream = null
		_sync_registration()
@export_range(-40.0, 6.0, 0.5) var fire_level_db := 0.0

var _source: Node
var _voices: Node
var _fire_active := false
var _rng := RandomNumberGenerator.new()
var _previous_path := ""
var _cue: Resource


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		# Fire ambience pauses even inside an always-processing UI/test host.
		process_mode = Node.PROCESS_MODE_PAUSABLE
		_rng.randomize()
		_bind_source.call_deferred()


func _bind_source() -> void:
	if not is_inside_tree():
		return
	_source = get_parent()
	if not _source.has_signal("fire_active_changed") or not _source.has_method("is_fire_active"):
		return
	var viewport := get_viewport()
	_voices = viewport.get_node_or_null("FireAudioVoices")
	if _voices == null:
		_voices = FireVoices.new()
		_voices.name = "FireAudioVoices"
		viewport.add_child(_voices)
	if not _source.is_connected("fire_active_changed", _on_fire_active_changed):
		_source.connect("fire_active_changed", _on_fire_active_changed)
	_on_fire_active_changed(bool(_source.call("is_fire_active")))


func _exit_tree() -> void:
	if is_instance_valid(_source) and _source.is_connected("fire_active_changed", _on_fire_active_changed):
		_source.disconnect("fire_active_changed", _on_fire_active_changed)
	if is_instance_valid(_voices):
		_voices.unregister_emitter(self)
	_voices = null
	stop()
	_fire_active = false


func _on_fire_active_changed(active: bool) -> void:
	_fire_active = active
	_sync_registration()


func _sync_registration() -> void:
	if not is_instance_valid(_voices):
		return
	if _fire_active and fire_kind != 0:
		_voices.register_emitter(self)
	else:
		_voices.unregister_emitter(self)


func play_fire(settings: FireSettings) -> void:
	if not _fire_active or fire_kind == 0 or not can_process():
		stop()
		return
	var cue := settings.cue_for_kind(fire_kind)
	if cue == null:
		stop()
		return
	if _cue != cue:
		stop()
		stream = null
		_cue = cue
	bus = settings.bus if AudioServer.get_bus_index(settings.bus) >= 0 else &"Master"
	volume_db = clampf(cue.volume_db + fire_level_db, -80.0, 6.0)
	# max_distance already supplies a linear fade. Quiet torch crackle cannot
	# also take inverse-distance loss and the native -24 dB muffling filter:
	# the normal elevated camera then receives effectively silent output.
	var small_flame := fire_kind == 1
	attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED if small_flame else AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	attenuation_filter_db = 0.0 if small_flame else -24.0
	unit_size = maxf(0.1, settings.unit_size_m)
	max_distance = settings.distance_for_kind(fire_kind)
	max_polyphony = 1
	if playing:
		return
	if stream == null:
		var path := cue.choose_path(_previous_path, _rng)
		stream = cue.get_loop_stream(path)
		if stream == null:
			return
		_previous_path = path
		pitch_scale = cue.choose_pitch(_rng)
	var loop := stream as AudioStreamWAV
	# Begin inside the loop, not at the recording's lighting/startup transient.
	var start := float(loop.loop_begin) / loop.mix_rate
	var end := float(loop.loop_end - 1) / loop.mix_rate
	play(_rng.randf_range(start, end))
