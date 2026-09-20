extends "res://tests/validation/test_case.gd"

## Needs owns hunger/fatigue. Medical ticks are exercised in validate_vitals_system.
var _failures: Array[String] = []
var _checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var actor := WorldActor.new()
	root.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	var needs := actor.get_needs()
	_expect(needs != null and actor.get_capability(&"needs") == needs, "normal lifecycle registers needs")
	needs.configure_enabled(true, false)
	needs.hunger = 100.0
	needs.hunger_stage = NpcRules.HungerStage.WELL_NOURISHED
	needs.configure(0.25, 0.0)
	needs.set_tick_remaining(0.25)
	needs.process(0.10)
	_close(needs.hunger, 100.0, "scheduled tick waits")
	needs.process(0.15)
	_close(needs.hunger, 100.0 - actor.get_stat_value("hunger_drain_rate") * NpcRules.WORLD_HUNGER_DRAIN_MULTIPLIER * 0.25, "scheduled tick conserves accumulated time")
	# A downed/carried actor still consumes food; being held only prevents revival.
	actor.get_vitals().set_life_state(NpcRules.LifeState.UNCONSCIOUS)
	var before := needs.hunger
	needs.process_needs(1.0)
	_expect(needs.hunger < before, "downed actor remains hungry")
	actor.get_vitals().set_life_state(NpcRules.LifeState.ALIVE)
	needs.configure_enabled(false, true)
	var gains := {}
	for state in ["idle", "stuck_running", "walking", "running", "working", "sitting", "asleep"]:
		needs.fatigue = 50.0
		needs.fatigue_stage = NpcRules.FatigueStage.WELL_RESTED
		actor.get_vitals().set_life_state(NpcRules.LifeState.ASLEEP if state == "asleep" else NpcRules.LifeState.ALIVE)
		needs.set_activity(state in ["walking", "running"], state in ["stuck_running", "running"], state == "sitting", state == "working")
		needs.process_needs(1.0)
		gains[state] = needs.fatigue - 50.0
		_expect(is_finite(gains[state]), "%s gain finite" % state)
	_expect(gains.idle > 0.0 and gains.stuck_running == gains.idle, "stuck running recovers like idle")
	_expect(gains.walking > 0.0 and gains.walking < gains.idle, "walking recovery slower than idle")
	_expect(gains.running < 0.0 and gains.working < 0.0, "running and actual work drain fatigue")
	_expect(gains.sitting > gains.idle and gains.asleep > gains.sitting, "sleep > sitting > idle recovery")
	needs.hunger = 5.0
	needs.hunger_stage = NpcRules.HungerStage.WELL_NOURISHED
	needs.apply_hunger_delta(-10.0)
	_expect(needs.hunger_stage == NpcRules.HungerStage.HUNGRY, "drain advances hunger stage")
	_close(needs.hunger, 95.0, "drain carries excess across stage")
	needs.apply_hunger_delta(10.0)
	_expect(needs.hunger_stage == NpcRules.HungerStage.WELL_NOURISHED, "recovery reverses hunger stage")
	_close(needs.hunger, 5.0, "recovery carries excess across stage")
	actor.free()
	_test_combat_costs()
	for failure in _failures:
		push_error(failure)
	print("NEEDS_CAPABILITY_%s checks=%d" % ["OK" if _failures.is_empty() else "FAILED", _checks])
	quit(0 if _failures.is_empty() else 1)

func _test_combat_costs() -> void:
	var actor := HumanoidCharacter.new()
	root.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	for outcome in ["attack", "dodged", "blocked"]:
		actor.fatigue_enabled = true
		actor.fatigue = 50.0
		if outcome == "attack":
			actor.on_system_combat_attack_started(null, PackedStringArray())
		else:
			actor.play_system_combat_hit_reaction(null, outcome, "test", PackedStringArray(), false, false, true, 0.0)
		var cost: float = NpcRules.FATIGUE_ATTACK_COST if outcome == "attack" else (NpcRules.FATIGUE_DODGE_COST if outcome == "dodged" else NpcRules.FATIGUE_BLOCK_COST)
		_close(actor.fatigue, 50.0 - cost, "resolved %s spends exact fatigue cost" % outcome)
		if outcome != "attack":
			actor.fatigue = 50.0
			actor.play_system_combat_hit_reaction(null, outcome, "test", PackedStringArray(), false, false, false, 0.0)
			_close(actor.fatigue, 50.0, "inactive defense does not spend %s cost" % outcome)
	actor.free()


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)

func _close(actual: float, expected: float, label: String) -> void:
	_expect(is_finite(actual) and is_finite(expected) and absf(actual - expected) <= 0.001, label)
