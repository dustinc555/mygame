extends Node

class_name FixedTickSimRunner

const DEFAULT_TICK_RATE_HZ := 30.0
const ACCUMULATOR_EPSILON := 0.000001

@export_range(1.0, 240.0, 1.0) var tick_rate_hz := DEFAULT_TICK_RATE_HZ
@export var auto_start := true
@export var target_path: NodePath = NodePath("..")
@export var update_method := "update_sim"
@export var command_method := "apply_sim_commands"
@export var snapshot_method := "get_sim_state"

var running := false
var tick_count := 0

var _accumulator := 0.0
var _pending_commands: Array[Dictionary] = []
var _last_snapshot: Dictionary = {}
var _last_tick_time_usec := 0.0
var _total_tick_time_usec := 0.0


func _ready() -> void:
	add_to_group("fixed_tick_sim_runner")
	running = auto_start


func _process(delta: float) -> void:
	if running:
		advance_time(delta)


func start() -> void:
	running = true


func stop() -> void:
	running = false


func reset() -> void:
	tick_count = 0
	_accumulator = 0.0
	_pending_commands.clear()
	_last_snapshot.clear()
	_last_tick_time_usec = 0.0
	_total_tick_time_usec = 0.0


func advance_time(elapsed_seconds: float) -> int:
	if elapsed_seconds <= 0.0:
		return 0
	_accumulator += elapsed_seconds
	var fixed_delta := get_fixed_delta()
	var ticks_run := 0
	while _accumulator + ACCUMULATOR_EPSILON >= fixed_delta:
		_run_fixed_tick(fixed_delta)
		_accumulator -= fixed_delta
		if absf(_accumulator) <= ACCUMULATOR_EPSILON:
			_accumulator = 0.0
		ticks_run += 1
	return ticks_run


func queue_command(command: Dictionary) -> void:
	_pending_commands.append(command.duplicate(true))


func get_fixed_delta() -> float:
	return 1.0 / maxf(tick_rate_hz, 1.0)


func get_tick_count() -> int:
	return tick_count


func get_average_tick_time_usec() -> float:
	return _total_tick_time_usec / maxf(float(tick_count), 1.0)


func get_average_tick_time_ms() -> float:
	return get_average_tick_time_usec() / 1000.0


func get_last_tick_time_usec() -> float:
	return _last_tick_time_usec


func get_snapshot() -> Dictionary:
	return _last_snapshot.duplicate(true)


func get_pending_command_count() -> int:
	return _pending_commands.size()


func get_metrics() -> Dictionary:
	return {
		"tick_rate_hz": tick_rate_hz,
		"fixed_delta": get_fixed_delta(),
		"tick_count": tick_count,
		"accumulator_seconds": _accumulator,
		"pending_command_count": _pending_commands.size(),
		"last_tick_time_usec": _last_tick_time_usec,
		"last_tick_time_ms": _last_tick_time_usec / 1000.0,
		"average_tick_time_usec": get_average_tick_time_usec(),
		"average_tick_time_ms": get_average_tick_time_ms(),
	}


func _run_fixed_tick(fixed_delta: float) -> void:
	var started_at_usec := Time.get_ticks_usec()
	var target := _get_tick_target()
	var commands := _drain_command_buffer()
	if target != null:
		if not commands.is_empty() and target.has_method(command_method):
			target.call(command_method, commands)
		if target.has_method(update_method):
			target.call(update_method, fixed_delta)
		_capture_snapshot(target)
	tick_count += 1
	_last_tick_time_usec = float(Time.get_ticks_usec() - started_at_usec)
	_total_tick_time_usec += _last_tick_time_usec


func _get_tick_target() -> Node:
	if target_path == NodePath():
		return null
	return get_node_or_null(target_path)


func _drain_command_buffer() -> Array[Dictionary]:
	var commands := _pending_commands.duplicate(true)
	_pending_commands.clear()
	return commands


func _capture_snapshot(target: Node) -> void:
	if target.has_method(snapshot_method):
		var snapshot = target.call(snapshot_method)
		_last_snapshot = snapshot.duplicate(true) if snapshot is Dictionary else {}
