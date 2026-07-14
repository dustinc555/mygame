extends "res://features/actors/bridge/capabilities/actor_capability.gd"

class_name NeedsCapability

## Owns one concern: hunger and fatigue needs.
##
## Reads attribute-modified rates through a typed StatsCapability handle and life
## state through a typed VitalsCapability handle (both bound by the actor at
## creation — same inversion as CarryCapability, so this file never names an
## actor class). Activity flags (moving/running/sitting/working) are pushed as
## data by the actuator each tick. No reflection.
##
## Stage model (preserved from the pre-migration actor): each need is a 0..100
## meter inside a stage; draining past 0 advances the stage and refills the
## meter, recovering past 100 walks the stage back. Bottoming out the final
## stage clamps at 0 — the lethal/unconscious consequences stay with the vitals
## systems and are wired there deliberately, not here.

var hunger_enabled := false
var fatigue_enabled := true
var hunger := 100.0
var fatigue := 100.0
var hunger_stage: int = NpcRules.HungerStage.WELL_NOURISHED
var fatigue_stage: int = NpcRules.FatigueStage.WELL_RESTED

var process_interval_seconds := 0.25
var process_jitter_seconds := 0.08

## Activity snapshot pushed by the actor's actuator each physics tick.
var activity_moving := false
var activity_running := false
var activity_sitting := false
var activity_working := false

## Active food effect: nutrition drips into hunger at a fixed rate until the
## timer runs out. Only one effect at a time; eating is blocked while active.
var food_effect_rate := 0.0
var food_effect_remaining_seconds := 0.0

var _stats: StatsCapability
var _vitals: VitalsCapability
var _tick_accumulated := 0.0
var _tick_remaining := 0.0


func _init() -> void:
	super._init(&"needs")
	process_enabled = true


func bind_stats(stats: StatsCapability) -> void:
	_stats = stats


func bind_vitals(vitals: VitalsCapability) -> void:
	_vitals = vitals


func teardown() -> void:
	_stats = null
	_vitals = null
	super.teardown()


func configure_enabled(next_hunger_enabled: bool, next_fatigue_enabled: bool) -> void:
	hunger_enabled = next_hunger_enabled
	fatigue_enabled = next_fatigue_enabled


func configure(interval_seconds: float, jitter_seconds: float) -> void:
	process_interval_seconds = maxf(0.0, interval_seconds)
	process_jitter_seconds = maxf(0.0, jitter_seconds)


func set_tick_remaining(seconds: float) -> void:
	_tick_accumulated = 0.0
	_tick_remaining = maxf(0.0, seconds)


func set_activity(moving: bool, running: bool, sitting: bool, working: bool) -> void:
	activity_moving = moving
	activity_running = running
	activity_sitting = sitting
	activity_working = working


func process(delta: float) -> void:
	_tick_accumulated += delta
	_tick_remaining -= delta
	if _tick_remaining > 0.0:
		return
	var tick_delta := _tick_accumulated
	_tick_accumulated = 0.0
	_tick_remaining = process_interval_seconds + _get_process_jitter()
	process_needs(tick_delta)


func process_needs(tick_delta: float) -> void:
	var life_state := _life_state()
	if hunger_enabled:
		if food_effect_remaining_seconds > 0.0:
			var effect_step := minf(tick_delta, food_effect_remaining_seconds)
			food_effect_remaining_seconds -= effect_step
			apply_hunger_delta(food_effect_rate * effect_step)
			if food_effect_remaining_seconds <= 0.0:
				food_effect_rate = 0.0
		else:
			apply_hunger_delta(-_stat_value("hunger_drain_rate") * NpcRules.WORLD_HUNGER_DRAIN_MULTIPLIER * tick_delta)
	if fatigue_enabled:
		var fatigue_delta := 0.0
		if life_state == NpcRules.LifeState.ASLEEP:
			fatigue_delta = _stat_value("fatigue_recovery_rate") * NpcRules.FATIGUE_SLEEP_RECOVERY_MULTIPLIER * tick_delta
		elif life_state != NpcRules.LifeState.ALIVE:
			fatigue_delta = _stat_value("fatigue_recovery_rate") * tick_delta
		elif activity_working:
			fatigue_delta = -NpcRules.FATIGUE_WORK_DRAIN * tick_delta
		elif activity_running and activity_moving:
			fatigue_delta = -NpcRules.FATIGUE_RUN_DRAIN * tick_delta
		elif activity_sitting:
			fatigue_delta = _stat_value("fatigue_recovery_rate") * NpcRules.FATIGUE_SIT_RECOVERY_MULTIPLIER * tick_delta
		elif activity_moving:
			fatigue_delta = _stat_value("fatigue_recovery_rate") * NpcRules.FATIGUE_WALK_RECOVERY_MULTIPLIER * tick_delta
		else:
			fatigue_delta = _stat_value("fatigue_recovery_rate") * tick_delta
		apply_fatigue_delta(fatigue_delta)


## Positive amounts recover, negative amounts drain. Crossing 0 advances the
## hunger stage and refills the meter; crossing 100 walks the stage back.
func apply_hunger_delta(amount: float) -> void:
	if is_zero_approx(amount):
		return
	var remaining := amount
	while not is_zero_approx(remaining):
		if remaining > 0.0:
			var recovery_step := minf(remaining, 100.0 - hunger)
			hunger += recovery_step
			remaining -= recovery_step
			if hunger >= 100.0 and hunger_stage > NpcRules.HungerStage.WELL_NOURISHED and remaining > 0.0:
				hunger_stage -= 1
				hunger = 0.0
				continue
			break
		var drain_step := minf(-remaining, hunger)
		hunger -= drain_step
		remaining += drain_step
		if hunger <= 0.0 and hunger_stage < NpcRules.HungerStage.STARVING:
			hunger_stage += 1
			hunger = 100.0
			continue
		break
	hunger = clampf(hunger, 0.0, 100.0)


func apply_fatigue_delta(amount: float) -> void:
	if is_zero_approx(amount):
		return
	var remaining := amount
	while not is_zero_approx(remaining):
		if remaining > 0.0:
			var recovery_step := minf(remaining, 100.0 - fatigue)
			fatigue += recovery_step
			remaining -= recovery_step
			if fatigue >= 100.0 and fatigue_stage > NpcRules.FatigueStage.WELL_RESTED and remaining > 0.0:
				fatigue_stage -= 1
				fatigue = 0.0
				continue
			break
		var drain_step := minf(-remaining, fatigue)
		fatigue -= drain_step
		remaining += drain_step
		if fatigue <= 0.0 and fatigue_stage < NpcRules.FatigueStage.EXHAUSTED:
			fatigue_stage += 1
			fatigue = 100.0
			continue
		break
	fatigue = clampf(fatigue, 0.0, 100.0)


func is_food_effect_active() -> bool:
	return food_effect_remaining_seconds > 0.0


## Total nutrition points spread evenly across the duration. Refuses while an
## effect is already running — one food at a time.
func start_food_effect(total_points: float, duration_seconds: float) -> bool:
	if is_food_effect_active() or total_points <= 0.0 or duration_seconds <= 0.0:
		return false
	food_effect_rate = total_points / duration_seconds
	food_effect_remaining_seconds = duration_seconds
	return true


## Hunger points per second the active effect grants; 0 when no effect runs.
func get_food_effect_rate() -> float:
	return food_effect_rate if is_food_effect_active() else 0.0


func get_hunger_stage_label() -> String:
	return NpcRules.get_hunger_stage_label(hunger_stage)


func get_fatigue_stage_label() -> String:
	return NpcRules.get_fatigue_stage_label(fatigue_stage)


func _stat_value(stat_name: String) -> float:
	return _stats.get_stat_value(stat_name) if _stats != null else 0.0


func _life_state() -> int:
	return _vitals.life_state if _vitals != null else NpcRules.LifeState.ALIVE


func _get_process_jitter() -> float:
	if process_jitter_seconds <= 0.0:
		return 0.0
	return randf_range(0.0, process_jitter_seconds)
