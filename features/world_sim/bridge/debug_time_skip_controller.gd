extends Node

## Debug orchestration only: the canonical clock and its ordinary subscribers
## own every consequence. No farm-success shortcut, durable LOD override or teleport.
const SERVICE_ID := &"debug_time_skip"
const PAUSE_REASON := "debug_time_skip"
const MAX_MINUTES := 525600.0
# Bound wall CPU, not game duration: cheap half-second steps should not
# force extra UI frames. Simulation callbacks remain strictly chronological.
const STEPS_PER_FRAME := 512
const FRAME_BUDGET_USEC := 16000
const HANDOFF_FRAME_LIMIT := 600

signal status_changed(message: String, active: bool)
signal finished(completed: bool, advanced_minutes: float, message: String)

var _clock: Node
var _lod: Node
var _offscreen_tickers: Array[Node] = []
var _phase := ""
var _start_minutes := 0.0
var _target_minutes := 0.0
var _saved_speed := 1
var _saved_manual_pause := false
var _saved_tree_paused := false
var _handoff_frames := 0
var _completed := false
var _message := ""
var _last_result: Dictionary = {}

func initialize(context: BootstrapContext) -> void:
	_clock = context.get_optional(&"world_time")
	_lod = context.get_optional(&"population_realization")
	for service_id in [&"world_sim_squad", &"faction_world_sim", &"encounter"]:
		var ticker := context.get_optional(service_id)
		if ticker != null:
			_offscreen_tickers.append(ticker)
	process_mode = Node.PROCESS_MODE_ALWAYS

func is_active() -> bool:
	return not _phase.is_empty()

func get_last_result() -> Dictionary:
	return _last_result.duplicate(true)

func request_skip(amount: float, unit: String) -> Dictionary:
	if is_active():
		return {"accepted": false, "message": "A time skip is already running."}
	if not is_finite(amount) or amount <= 0.0 or unit not in ["Hours", "Days"]:
		return {"accepted": false, "message": "Enter a positive number of Hours or Days."}
	var minutes := amount * (60.0 if unit == "Hours" else 1440.0)
	if not is_finite(minutes) or minutes > MAX_MINUTES:
		return {"accepted": false, "message": "Skip at most 365 days at a time."}
	if not is_instance_valid(_clock) or not is_instance_valid(_lod):
		return {"accepted": false, "message": "World simulation is unavailable."}
	if bool(_lod.call("is_far_simulation_active")) or bool(_lod.call("is_realization_loading_active")):
		return {"accepted": false, "message": "Wait for population loading to finish."}
	_saved_speed = int(_clock.call("get_speed_index"))
	_saved_manual_pause = bool(_clock.call("is_manual_paused"))
	_saved_tree_paused = get_tree().paused
	_start_minutes = float(_clock.get("total_world_minutes"))
	_target_minutes = _start_minutes + minutes
	if not bool(_clock.call("request_pause", PAUSE_REASON)):
		return {"accepted": false, "message": "Cannot pause live simulation."}
	if not bool(_lod.call("begin_far_simulation", self)):
		_clock.call("release_pause", PAUSE_REASON)
		if _saved_tree_paused:
			get_tree().paused = true
		return {"accepted": false, "message": "Cannot hand off population."}
	_phase = "unloading"
	_handoff_frames = 0
	_completed = false
	_message = "Unloading nearby simulation…"
	status_changed.emit(_message, true)
	return {"accepted": true, "message": _message}

func cancel() -> void:
	if is_active() and _phase != "restoring":
		_begin_restore(false, "Cancelled; elapsed simulation is kept.")

func _process(_delta: float) -> void:
	if not is_active():
		return
	if not is_instance_valid(_clock) or not is_instance_valid(_lod):
		_release_session()
		return
	match _phase:
		"unloading":
			_handoff_frames += 1
			if bool(_lod.call("step_projection_handoff")):
				# queue_free() and GECS unregister must settle before any clock step.
				_phase = "settling"
			elif _handoff_frames >= HANDOFF_FRAME_LIMIT:
				_begin_restore(false, "Rejected: some NPCs could not hand off to world simulation.")
		"settling":
			_phase = "advancing"
		"advancing":
			var deadline := Time.get_ticks_usec() + FRAME_BUDGET_USEC
			for step in STEPS_PER_FRAME:
				var current := float(_clock.get("total_world_minutes"))
				var remaining := _target_minutes - current
				if remaining <= 0.000001:
					_begin_restore(true, "Time skip complete.")
					break
				# Never emit historical boundaries with a future canonical clock.
				# Includes the first/last fractional minute without rounding duration.
				var next_boundary := floorf(current) + 1.0
				var seconds_per_minute := maxf(float(_clock.get("real_seconds_per_game_minute")), 0.01)
				# Real-time-driven world systems retain their normal half-second
				# cadence. Never substitute one giant delta or skip their plugins.
				var minutes := minf(minf(remaining, next_boundary - current), 0.5 / seconds_per_minute)
				_clock.call("advance_minutes", minutes)
				for ticker in _offscreen_tickers:
					if is_instance_valid(ticker):
						ticker.call("advance_offscreen_seconds", minutes * seconds_per_minute)
				if _phase != "advancing" or Time.get_ticks_usec() >= deadline:
					break
			if _phase == "advancing":
				status_changed.emit("Skipping: %.1f / %.1f hours" % [(float(_clock.get("total_world_minutes")) - _start_minutes) / 60.0, (_target_minutes - _start_minutes) / 60.0], true)
		"restoring":
			_handoff_frames += 1
			if bool(_lod.call("step_projection_handoff")):
				_release_session()
			elif _handoff_frames >= HANDOFF_FRAME_LIMIT:
				_completed = false
				_message = "Time advanced; nearby population could not fully reload."
				_release_session()

func _begin_restore(completed: bool, message: String) -> void:
	_completed = completed
	_message = message
	_phase = "restoring"
	_handoff_frames = 0
	if is_instance_valid(_lod):
		_lod.call("end_far_simulation", self)
	status_changed.emit("Restoring nearby simulation…", true)

func _release_session() -> void:
	if not is_active():
		return
	if is_instance_valid(_lod):
		_lod.call("end_far_simulation", self)
	var advanced := 0.0
	if is_instance_valid(_clock) and _clock.is_inside_tree():
		advanced = float(_clock.get("total_world_minutes")) - _start_minutes
		_clock.call("set_speed_index", _saved_speed)
		if _saved_manual_pause:
			_clock.call("request_manual_pause")
		else:
			_clock.call("release_manual_pause")
		_clock.call("release_pause", PAUSE_REASON)
		if _saved_tree_paused and not bool(_clock.call("is_world_paused")):
			get_tree().paused = true
	_phase = ""
	_last_result = {"completed": _completed, "advanced_minutes": advanced, "message": _message}
	status_changed.emit(_message, false)
	finished.emit(_completed, advanced, _message)

func _exit_tree() -> void:
	_completed = false
	_message = "Time skip stopped during teardown."
	_release_session()
