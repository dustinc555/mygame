extends Node

## One disposable voice budget per Viewport, created by its first fire child.
## No simulation/service state: emitters register on lit transitions and leave on exit.
const FireSettings = preload("res://features/audio/resources/fire_audio_settings.gd")
@export var settings: FireSettings = preload("res://features/audio/resources/fire_audio_settings.tres")

var _emitters: Array[AudioStreamPlayer3D] = []
var _timer: Timer
var _refresh_queued := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_timer = Timer.new()
	_timer.ignore_time_scale = true
	_timer.timeout.connect(refresh)
	add_child(_timer)


func register_emitter(emitter: AudioStreamPlayer3D) -> void:
	if not _emitters.has(emitter):
		_emitters.append(emitter)
	if _timer.is_stopped():
		_timer.start(maxf(0.1, settings.listener_refresh_seconds))
	request_refresh()


func unregister_emitter(emitter: AudioStreamPlayer3D) -> void:
	emitter.stop()
	_emitters.erase(emitter)
	if _emitters.is_empty():
		_timer.stop()
	else:
		request_refresh()


func request_refresh() -> void:
	if not _refresh_queued:
		_refresh_queued = true
		refresh.call_deferred()


func refresh() -> void:
	_refresh_queued = false
	if not is_inside_tree() or get_tree().paused:
		return
	_timer.wait_time = maxf(0.1, settings.listener_refresh_seconds)
	var viewport := get_viewport()
	var listener: Node3D = viewport.get_audio_listener_3d()
	if listener == null:
		listener = viewport.get_camera_3d()
	var candidates: Array[Dictionary] = []
	if listener != null and viewport.audio_listener_enable_3d:
		for emitter in _emitters:
			if not is_instance_valid(emitter) or not emitter.is_inside_tree() or emitter.is_queued_for_deletion() or not emitter.can_process():
				continue
			var radius := settings.distance_for_kind(emitter.fire_kind)
			var distance_sq := listener.global_position.distance_squared_to(emitter.global_position)
			if distance_sq >= radius * radius:
				continue
			var retention := clampf(settings.voice_retention_ratio, 0.5, 1.0) if emitter.playing else 1.0
			candidates.append({"emitter": emitter, "rank": distance_sq * retention * retention})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.rank < b.rank)
	var selected: Array[AudioStreamPlayer3D] = []
	for candidate in candidates:
		if selected.size() >= clampi(settings.max_audible_fires, 1, 32):
			break
		selected.append(candidate.emitter)
	# Stop losers before starting winners, keeping the hard cap during transitions.
	for emitter in _emitters:
		if is_instance_valid(emitter) and not selected.has(emitter):
			emitter.stop()
	for emitter in selected:
		emitter.play_fire(settings)


func _exit_tree() -> void:
	for emitter in _emitters:
		if is_instance_valid(emitter):
			emitter.stop()
	_emitters.clear()
