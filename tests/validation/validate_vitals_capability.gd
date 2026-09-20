extends "res://tests/validation/test_case.gd"

## Focused sanity check for VitalsCapability state resolution.
## Run: python3 tests/run_validation.py --jobs 1 --filter validate_vitals_capability
##
## Verifies: KO/coma/dying thresholds, death timer, blood-zero unconscious,
## and the StatsCapability toughness signal refreshing max blood.


var _checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: Array[String] = []

	_validate_ko_threshold(failures)
	_validate_coma_threshold(failures)
	_validate_dying_threshold_and_timer(failures)
	_validate_blood_zero_unconscious(failures)
	_validate_blood_death_threshold(failures)
	_validate_toughness_signal_refreshes_max_blood(failures)

	if failures.is_empty():
		print("PASS: VitalsCapability state resolution sane (%d checks)" % _checks)
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		quit(1)


func _validate_ko_threshold(failures: Array[String]) -> void:
	var context := _make_actor_context()
	var vitals := context["vitals"] as VitalsCapability
	vitals.set_blunt_damage(vitals.max_hp)
	_expect(failures, "hp <= 0 enters unconscious", vitals.life_state == NpcRules.LifeState.UNCONSCIOUS)
	(context["actor"] as WorldActor).free()


func _validate_coma_threshold(failures: Array[String]) -> void:
	var context := _make_actor_context()
	var vitals := context["vitals"] as VitalsCapability
	var coma_wounds := vitals.max_hp - vitals.get_coma_point(vitals.max_hp) + 1.0
	vitals.set_blunt_damage(coma_wounds)
	_expect(failures, "hp <= coma point enters recovery coma", vitals.life_state == NpcRules.LifeState.RECOVERY_COMA)
	(context["actor"] as WorldActor).free()


func _validate_dying_threshold_and_timer(failures: Array[String]) -> void:
	var context := _make_actor_context()
	var vitals := context["vitals"] as VitalsCapability
	var death_wounds := vitals.max_hp - vitals.get_death_point(vitals.max_hp)
	vitals.set_blunt_damage(death_wounds)
	_expect(failures, "hp <= death point enters dying", vitals.life_state == NpcRules.LifeState.DYING)
	vitals.process_dying(vitals.get_dying_seconds() + 0.1)
	_expect(failures, "dying timer expiry enters dead", vitals.life_state == NpcRules.LifeState.DEAD)
	(context["actor"] as WorldActor).free()


func _validate_blood_zero_unconscious(failures: Array[String]) -> void:
	var context := _make_actor_context()
	var vitals := context["vitals"] as VitalsCapability
	vitals.set_blood(0.0)
	_expect(failures, "blood <= 0 enters unconscious", vitals.life_state == NpcRules.LifeState.UNCONSCIOUS)
	(context["actor"] as WorldActor).free()


func _validate_blood_death_threshold(failures: Array[String]) -> void:
	var context := _make_actor_context()
	var vitals := context["vitals"] as VitalsCapability
	vitals.set_blood(vitals.get_blood_death_point())
	_expect(failures, "blood <= blood death point enters dying", vitals.life_state == NpcRules.LifeState.DYING)
	(context["actor"] as WorldActor).free()


func _validate_toughness_signal_refreshes_max_blood(failures: Array[String]) -> void:
	var context := _make_actor_context(100.0, 100.0, 80.0, 80.0, 80.0)
	var actor := context["actor"] as WorldActor
	var stats := context["stats"] as StatsCapability

	stats.set_skill_level(SkillRules.ATTRIBUTE_TOUGHNESS, 40)
	var expected_max := SkillRules.get_max_blood_for_toughness(80.0, 40.0)
	_expect(failures, "toughness signal refreshes max blood", absf(actor.max_blood - expected_max) <= 0.01)
	_expect(failures, "full blood refills to refreshed max", absf(actor.blood - actor.max_blood) <= 0.01)

	var wounded_blood := actor.max_blood * 0.5
	actor.blood = wounded_blood
	stats.set_skill_level(SkillRules.ATTRIBUTE_TOUGHNESS, 80)
	var expected_higher_max := SkillRules.get_max_blood_for_toughness(80.0, 80.0)
	_expect(failures, "second toughness signal refreshes higher max blood", absf(actor.max_blood - expected_higher_max) <= 0.01)
	_expect(failures, "wounded blood stays wounded after toughness refresh", absf(actor.blood - wounded_blood) <= 0.01)
	actor.free()


func _make_actor_context(initial_max_hp := 100.0, initial_hp := 100.0, initial_base_max_blood := 0.0, initial_max_blood := 100.0, initial_blood := 100.0) -> Dictionary:
	var actor := WorldActor.new()
	actor.max_hp = initial_max_hp
	actor.hp = initial_hp
	actor.base_max_blood = initial_base_max_blood
	actor.max_blood = initial_max_blood
	actor.blood = initial_blood
	root.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	return {
		"actor": actor,
		"stats": actor.get_stats(),
		"vitals": actor.get_vitals(),
	}


func _expect(failures: Array[String], label: String, condition: bool) -> void:
	_checks += 1
	if not condition:
		failures.append(label)
