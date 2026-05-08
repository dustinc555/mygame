extends Node

class_name WorldTimeController

signal time_changed(day_index: int, weekday_name: String, hour: int, minute: int, phase_name: String, speed_label: String)
signal speed_changed(speed_index: int, speed_label: String, speed_scale: float)

const MINUTES_PER_DAY := 24.0 * 60.0
const WEEKDAYS: Array[String] = ["Mon", "Tues", "Wed", "Thurs", "Fri", "Sat", "Sun"]
const SPEED_LABELS: Array[String] = ["Slow", "Normal", "Fast", "Very Fast"]
const SPEED_SCALES: Array[float] = [0.5, 1.0, 4.0, 12.0]

@export_range(0, 23, 1) var start_hour := 8
@export_range(0, 59, 1) var start_minute := 0
@export var real_seconds_per_game_minute := 1.0
@export_range(0, 3, 1) var default_speed_index := 1

var total_world_minutes := 0.0
var speed_index := 1
var _last_emitted_absolute_minute := -1


func _ready() -> void:
	total_world_minutes = float(start_hour * 60 + start_minute)
	speed_index = clampi(default_speed_index, 0, SPEED_LABELS.size() - 1)
	_emit_time_changed(true)


func _process(delta: float) -> void:
	var seconds_per_minute := maxf(real_seconds_per_game_minute, 0.01)
	total_world_minutes += delta / seconds_per_minute * get_speed_scale()
	_emit_time_changed(false)


func get_day_index() -> int:
	return int(floor(total_world_minutes / MINUTES_PER_DAY))


func get_weekday_name() -> String:
	return WEEKDAYS[get_day_index() % WEEKDAYS.size()]


func get_hour() -> int:
	return int(floor(fposmod(total_world_minutes, MINUTES_PER_DAY) / 60.0))


func get_minute() -> int:
	return int(floor(fposmod(total_world_minutes, 60.0)))


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


func get_speed_scale() -> float:
	return SPEED_SCALES[speed_index]


func set_speed_index(value: int) -> void:
	var next_index := clampi(value, 0, SPEED_LABELS.size() - 1)
	if speed_index == next_index:
		return
	speed_index = next_index
	speed_changed.emit(speed_index, get_speed_label(), get_speed_scale())
	_emit_time_changed(true)


func format_time() -> String:
	return "%s %02d:%02d" % [get_weekday_name(), get_hour(), get_minute()]


func _emit_time_changed(force: bool) -> void:
	var absolute_minute := int(floor(total_world_minutes))
	if not force and absolute_minute == _last_emitted_absolute_minute:
		return
	_last_emitted_absolute_minute = absolute_minute
	time_changed.emit(get_day_index(), get_weekday_name(), get_hour(), get_minute(), get_phase_name(), get_speed_label())
