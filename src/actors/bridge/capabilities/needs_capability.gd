extends "res://src/actors/bridge/capabilities/actor_capability.gd"

class_name NeedsCapability

var process_interval_seconds := 0.25
var process_jitter_seconds := 0.08

var _tick_accumulated := 0.0
var _tick_remaining := 0.0


func _init() -> void:
	super._init(&"needs")
	process_enabled = true


func configure(interval_seconds: float, jitter_seconds: float) -> void:
	process_interval_seconds = maxf(0.0, interval_seconds)
	process_jitter_seconds = maxf(0.0, jitter_seconds)


func set_tick_remaining(seconds: float) -> void:
	_tick_accumulated = 0.0
	_tick_remaining = maxf(0.0, seconds)


func process(delta: float) -> void:
	process_actor_needs(delta)


func process_actor_needs(delta: float) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	if actor.has_method("is_carried") and bool(actor.call("is_carried")):
		return
	process_scheduled_needs(delta)
	_call_actor_tick("_process_bleeding", delta)
	_call_actor_tick("_process_dying", delta)
	_call_actor_tick("_process_recovery", delta)


func process_scheduled_needs(delta: float) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	if actor.has_method("_has_scheduled_needs_work") and not bool(actor.call("_has_scheduled_needs_work")):
		_tick_accumulated = 0.0
		_tick_remaining = 0.0
		return
	_tick_accumulated += delta
	_tick_remaining -= delta
	if _tick_remaining > 0.0:
		return
	var tick_delta := _tick_accumulated
	_tick_accumulated = 0.0
	_tick_remaining = process_interval_seconds + _get_process_jitter()
	_call_actor_tick("_process_needs", tick_delta)


func _get_process_jitter() -> float:
	if process_jitter_seconds <= 0.0:
		return 0.0
	if actor != null and is_instance_valid(actor) and actor.has_method("_get_needs_process_jitter"):
		return clampf(float(actor.call("_get_needs_process_jitter")), 0.0, process_jitter_seconds)
	return randf_range(0.0, process_jitter_seconds)


func _call_actor_tick(method_name: StringName, delta: float) -> void:
	if actor != null and is_instance_valid(actor) and actor.has_method(method_name):
		actor.call(method_name, delta)
