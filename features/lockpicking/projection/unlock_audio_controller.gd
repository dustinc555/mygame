extends Node

const SERVICE_ID := &"unlock_audio"
const CUE := preload("res://features/lockpicking/resources/unlock_sound_cue.gd")
@export var cue: CUE = preload("res://features/lockpicking/resources/unlock_success_sound.tres")

var _locks: Node
var _doors: Node
var _targets: Node
var _previous_path := ""
var _rng := RandomNumberGenerator.new()

func initialize(context: BootstrapContext) -> void:
	teardown()
	_locks = context.get_optional(&"lockpicking")
	_doors = context.get_optional(&"doors")
	_targets = context.get_optional(&"lockpick_interactions")
	if is_instance_valid(_locks):
		_locks.object_unlocked.connect(_on_lock_unlocked)
	if is_instance_valid(_doors):
		_doors.door_unlocked.connect(_on_door_unlocked)
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(false)

func teardown() -> void:
	if is_instance_valid(_locks) and _locks.object_unlocked.is_connected(_on_lock_unlocked):
		_locks.object_unlocked.disconnect(_on_lock_unlocked)
	if is_instance_valid(_doors) and _doors.door_unlocked.is_connected(_on_door_unlocked):
		_doors.door_unlocked.disconnect(_on_door_unlocked)
	_locks = null
	_doors = null
	_targets = null
	_previous_path = ""
	for voice in get_children():
		voice.free()

func _exit_tree() -> void:
	teardown()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		for voice in get_children():
			voice.stop()
			voice.stream = null

func _on_door_unlocked(door_id: String) -> void:
	_on_lock_unlocked("door:%s" % door_id)

func _on_lock_unlocked(lock_id: String) -> void:
	if not is_inside_tree() or get_tree().paused or cue == null or not is_instance_valid(_targets):
		return
	var target = _targets.get_registered_target(lock_id)
	if target == null:
		return
	_play_at(target.get_lockpick_contact())

## Capture the position, not the disposable object. Only unlock events do work.
func _play_at(position: Vector3) -> void:
	var listener := get_viewport().get_camera_3d()
	var distance := maxf(1.0, cue.max_distance_m)
	if listener == null or not position.is_finite() or listener.global_position.distance_squared_to(position) >= distance * distance:
		return
	var path := cue.choose_path(_previous_path, _rng)
	var stream := cue.get_stream(path)
	if stream == null:
		return
	var limit := clampi(cue.max_voices, 1, 32)
	while get_child_count() > limit:
		get_child(0).free()
	var player: AudioStreamPlayer3D
	for voice in get_children():
		if not voice.playing:
			player = voice
			break
	if player == null and get_child_count() < limit:
		player = AudioStreamPlayer3D.new()
		add_child(player)
		player.finished.connect(_on_voice_finished.bind(player))
	if player == null:
		player = get_child(0)
	move_child(player, get_child_count() - 1)
	player.stop()
	player.stream = stream
	player.global_position = position
	player.volume_db = cue.volume_db
	player.pitch_scale = cue.choose_pitch(_rng)
	player.bus = cue.bus if AudioServer.get_bus_index(cue.bus) >= 0 else &"Master"
	player.unit_size = maxf(0.1, cue.unit_size_m)
	player.max_distance = distance
	player.set_meta("clip_path", path)
	_previous_path = path
	player.play()

func _on_voice_finished(player: AudioStreamPlayer3D) -> void:
	player.stream = null
