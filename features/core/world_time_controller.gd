extends Node

class_name WorldTimeController

const SERVICE_ID := &"world_time"

signal time_changed(day_index: int, weekday_name: String, hour: int, minute: int, phase_name: String, speed_label: String)
signal speed_changed(speed_index: int, speed_label: String, speed_scale: float)
signal pause_changed(manual_paused: bool, world_paused: bool)
signal minute_changed(absolute_minute: int, day_index: int, hour: int, minute: int)
signal hour_changed(absolute_hour: int, day_index: int, hour: int)
signal day_changed(day_index: int)

const MINUTES_PER_DAY := 24.0 * 60.0
const SPEED_LABELS: Array[String] = ["Slow", "Normal", "Fast", "Very Fast"]
const SPEED_SCALES: Array[float] = [0.5, 1.0, 3.0, 8.0]
const PAUSE_REASON_MANUAL := "manual"
const PAUSE_REASON_CONVERSATION := "conversation"
const PAUSE_REASON_APPEARANCE_EDITOR := "appearance_editor"

@export_range(0, 23, 1) var start_hour := 6
@export_range(0, 59, 1) var start_minute := 0
@export var real_seconds_per_game_minute := 1.0
@export_range(0, 3, 1) var default_speed_index := 1
@export var server_authoritative_mode := false

var root_scene: Node
var _context: BootstrapContext
var total_world_minutes := 0.0
var speed_index := 1
var _pause_reasons: Dictionary = {}
var _last_emitted_absolute_minute := -1
var _last_boundary_absolute_minute := -1
var _base_physics_ticks_per_second := 60
var _base_max_physics_steps_per_frame := 8


func initialize(context: BootstrapContext) -> void:
	_context = context
	root_scene = context.root_scene
	_apply_authored_start_time()
	sync_world_time_state()


## The WorldRoot above the playing zone authors session spawn options (start
## time in the World dock). Applied at bootstrap only — loading a save
## overwrites through apply_serialized_state afterwards.
func _apply_authored_start_time() -> void:
	var current := root_scene
	while current != null and not (current is WorldRoot):
		current = current.get_parent()
	if current == null:
		return
	var authored_hour = current.get("start_hour")
	var authored_minute = current.get("start_minute")
	if authored_hour == null or authored_minute == null:
		return
	start_hour = clampi(int(authored_hour), 0, 23)
	start_minute = clampi(int(authored_minute), 0, 59)
	total_world_minutes = float(start_hour * 60 + start_minute)
	_last_boundary_absolute_minute = get_absolute_minute()
	_emit_time_changed(true)


func _ready() -> void:
	add_to_group("world_time_controller")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_base_physics_ticks_per_second = Engine.physics_ticks_per_second
	_base_max_physics_steps_per_frame = Engine.max_physics_steps_per_frame
	total_world_minutes = float(start_hour * 60 + start_minute)
	speed_index = clampi(default_speed_index, 0, SPEED_LABELS.size() - 1)
	_last_boundary_absolute_minute = get_absolute_minute()
	_apply_world_speed_state()
	_emit_time_changed(true)
	sync_world_time_state()


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = _base_physics_ticks_per_second
	Engine.max_physics_steps_per_frame = _base_max_physics_steps_per_frame
	var tree := get_tree()
	if tree != null:
		tree.paused = false


func _process(delta: float) -> void:
	if is_world_paused():
		return
	var seconds_per_minute := maxf(real_seconds_per_game_minute, 0.01)
	advance_minutes(delta / seconds_per_minute)


func get_day_index() -> int:
	return WorldTimeFormat.day_index(total_world_minutes)


func get_absolute_minute() -> int:
	return int(floor(total_world_minutes))


func get_absolute_hour() -> int:
	return int(floor(total_world_minutes / 60.0))


func get_weekday_name() -> String:
	return WorldTimeFormat.weekday_name(total_world_minutes)


func get_hour() -> int:
	return WorldTimeFormat.hour(total_world_minutes)


func get_minute() -> int:
	return WorldTimeFormat.minute(total_world_minutes)


func get_day_fraction() -> float:
	return fposmod(total_world_minutes, MINUTES_PER_DAY) / MINUTES_PER_DAY


func get_phase_name() -> String:
	var hour := get_hour()
	if hour >= 5 and hour < 7:
		return "Dawn"
	if hour >= 7 and hour < 12:
		return "Morning"
	if hour >= 12 and hour < 17:
		return "Afternoon"
	if hour >= 17 and hour < 20:
		return "Dusk"
	return "Night"


func get_speed_options() -> Array[String]:
	return SPEED_LABELS.duplicate()


func get_speed_index() -> int:
	return speed_index


func get_speed_label() -> String:
	return SPEED_LABELS[speed_index]


func get_status_speed_label() -> String:
	return "Paused" if is_manual_paused() else get_speed_label()


func get_speed_scale() -> float:
	return SPEED_SCALES[speed_index]


func is_world_paused() -> bool:
	return not _pause_reasons.is_empty()


func is_manual_paused() -> bool:
	return _pause_reasons.has(PAUSE_REASON_MANUAL)


func set_speed_index(value: int) -> void:
	var next_index := clampi(value, 0, SPEED_LABELS.size() - 1)
	if speed_index == next_index:
		return
	speed_index = next_index
	_apply_world_speed_state()
	speed_changed.emit(speed_index, get_speed_label(), get_speed_scale())
	_emit_time_changed(true)
	sync_world_time_state()


func toggle_manual_pause() -> void:
	if is_manual_paused():
		release_pause(PAUSE_REASON_MANUAL)
	else:
		request_pause(PAUSE_REASON_MANUAL)


func request_manual_pause() -> void:
	request_pause(PAUSE_REASON_MANUAL)


func release_manual_pause() -> void:
	release_pause(PAUSE_REASON_MANUAL)


func request_conversation_pause() -> bool:
	return request_pause(PAUSE_REASON_CONVERSATION)


func release_conversation_pause() -> void:
	release_pause(PAUSE_REASON_CONVERSATION)


func request_appearance_editor_pause() -> bool:
	return request_pause(PAUSE_REASON_APPEARANCE_EDITOR)


func release_appearance_editor_pause() -> void:
	release_pause(PAUSE_REASON_APPEARANCE_EDITOR)


func request_pause(reason: String) -> bool:
	if reason.is_empty() or not _should_world_pause_for_reason(reason):
		return false
	if _pause_reasons.has(reason):
		return true
	_pause_reasons[reason] = true
	_apply_world_speed_state()
	pause_changed.emit(is_manual_paused(), is_world_paused())
	_emit_time_changed(true)
	sync_world_time_state()
	return true


func release_pause(reason: String) -> void:
	if reason.is_empty() or not _pause_reasons.has(reason):
		return
	_pause_reasons.erase(reason)
	_apply_world_speed_state()
	pause_changed.emit(is_manual_paused(), is_world_paused())
	_emit_time_changed(true)
	sync_world_time_state()


func advance_minutes(minutes: float) -> void:
	if minutes <= 0.0:
		return
	total_world_minutes += minutes
	_emit_time_boundaries()
	_emit_time_changed(false)
	sync_world_time_state()


func serialize_state() -> Dictionary:
	sync_world_time_state()
	return _current_world_time_state()


func apply_serialized_state(state: Dictionary) -> void:
	if state.is_empty():
		refresh_from_gecs_state()
		return
	_apply_world_time_state(state)
	sync_world_time_state()


func sync_world_time_state() -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("upsert_world_time_state"):
		bridge.call("upsert_world_time_state", _current_world_time_state())


func refresh_from_gecs_state() -> void:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_world_time_state"):
		return
	var state: Dictionary = bridge.call("get_world_time_state")
	if not state.is_empty():
		_apply_world_time_state(state)


func advance_hours(hours: float) -> void:
	advance_minutes(hours * 60.0)


func advance_days(days: float) -> void:
	advance_minutes(days * MINUTES_PER_DAY)


func set_time_of_day(hour: int, minute: int = 0) -> void:
	var clamped_hour := clampi(hour, 0, 23)
	var clamped_minute := clampi(minute, 0, 59)
	var day_start := float(get_day_index()) * MINUTES_PER_DAY
	total_world_minutes = day_start + float(clamped_hour * 60 + clamped_minute)
	_last_boundary_absolute_minute = get_absolute_minute()
	_emit_time_changed(true)
	sync_world_time_state()


func format_time() -> String:
	return WorldTimeFormat.format(total_world_minutes)


func _emit_time_changed(force: bool) -> void:
	var absolute_minute := int(floor(total_world_minutes))
	if not force and absolute_minute == _last_emitted_absolute_minute:
		return
	_last_emitted_absolute_minute = absolute_minute
	time_changed.emit(get_day_index(), get_weekday_name(), get_hour(), get_minute(), get_phase_name(), get_status_speed_label())


func _current_world_time_state() -> Dictionary:
	return {
		"state_id": "world_time",
		"total_world_minutes": total_world_minutes,
		"speed_index": speed_index,
		"real_seconds_per_game_minute": real_seconds_per_game_minute,
		"server_authoritative_mode": server_authoritative_mode,
		"manual_paused": is_manual_paused(),
		"last_emitted_absolute_minute": _last_emitted_absolute_minute,
		"last_boundary_absolute_minute": _last_boundary_absolute_minute,
	}


func _apply_world_time_state(state: Dictionary) -> void:
	total_world_minutes = float(state.get("total_world_minutes", total_world_minutes))
	speed_index = clampi(int(state.get("speed_index", speed_index)), 0, SPEED_LABELS.size() - 1)
	real_seconds_per_game_minute = maxf(float(state.get("real_seconds_per_game_minute", real_seconds_per_game_minute)), 0.01)
	server_authoritative_mode = bool(state.get("server_authoritative_mode", server_authoritative_mode))
	_last_emitted_absolute_minute = int(state.get("last_emitted_absolute_minute", get_absolute_minute()))
	_last_boundary_absolute_minute = int(state.get("last_boundary_absolute_minute", get_absolute_minute()))
	_pause_reasons.clear()
	if bool(state.get("manual_paused", false)):
		_pause_reasons[PAUSE_REASON_MANUAL] = true
	_apply_world_speed_state()
	speed_changed.emit(speed_index, get_speed_label(), get_speed_scale())
	pause_changed.emit(is_manual_paused(), is_world_paused())
	_emit_time_changed(true)


func _get_gecs_world() -> Node:
	return _context.get_optional(GecsWorldController.SERVICE_ID) if _context != null else null


func _apply_world_speed_state() -> void:
	var active_speed_scale := 1.0 if is_world_paused() else get_speed_scale()
	Engine.time_scale = active_speed_scale
	var physics_precision_scale := maxf(active_speed_scale, 1.0)
	Engine.physics_ticks_per_second = max(1, int(roundi(float(_base_physics_ticks_per_second) * physics_precision_scale)))
	Engine.max_physics_steps_per_frame = max(1, int(ceili(float(_base_max_physics_steps_per_frame) * physics_precision_scale)))
	var tree := get_tree()
	if tree != null:
		tree.paused = is_world_paused()


func _should_world_pause_for_reason(reason: String) -> bool:
	if server_authoritative_mode and reason == PAUSE_REASON_CONVERSATION:
		return false
	return true


func _emit_time_boundaries() -> void:
	var current_absolute_minute := get_absolute_minute()
	if _last_boundary_absolute_minute < 0:
		_last_boundary_absolute_minute = current_absolute_minute
		return
	if current_absolute_minute <= _last_boundary_absolute_minute:
		return
	for absolute_minute in range(_last_boundary_absolute_minute + 1, current_absolute_minute + 1):
		var day_index := int(floor(float(absolute_minute) / MINUTES_PER_DAY))
		var minute_of_day := int(fposmod(float(absolute_minute), MINUTES_PER_DAY))
		var hour := int(floor(float(minute_of_day) / 60.0))
		var minute := int(fposmod(float(minute_of_day), 60.0))
		minute_changed.emit(absolute_minute, day_index, hour, minute)
		if minute == 0:
			hour_changed.emit(int(floor(float(absolute_minute) / 60.0)), day_index, hour)
			if minute_of_day == 0:
				day_changed.emit(day_index)
	_last_boundary_absolute_minute = current_absolute_minute
