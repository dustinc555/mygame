extends SceneTree

const HUMANOID_SCRIPT = preload("res://src/actors/projection/humanoid/humanoid_character.gd")
const FLOAT_TOLERANCE := 0.001

var _failures: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	_validate_registration()
	_validate_scheduled_hunger_tick()
	_validate_bleeding_ticks_every_process()
	_validate_carried_actor_skip()
	if _failures.is_empty():
		print("NEEDS_CAPABILITY_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("NEEDS_CAPABILITY_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_registration() -> void:
	var actor := _make_actor()
	var capability = actor.get_actor_capability(&"needs")
	if capability == null:
		_fail("Expected humanoid to register NeedsCapability")
	elif not capability.has_method("process_actor_needs"):
		_fail("Expected NeedsCapability to expose process_actor_needs")
	actor.free()


func _validate_scheduled_hunger_tick() -> void:
	var actor := _make_actor()
	var capability = actor.get_actor_capability(&"needs")
	actor.hunger_enabled = true
	actor.fatigue_enabled = false
	actor.hunger = 100.0
	actor.hunger_stage = NpcRules.HungerStage.WELL_NOURISHED
	actor.hunger_drain_rate = 10.0
	capability.call("configure", 0.25, 0.0)
	capability.call("set_tick_remaining", 0.25)
	capability.call("process_actor_needs", 0.10)
	if absf(actor.hunger - 100.0) > FLOAT_TOLERANCE:
		_fail("Scheduled needs tick ran before interval elapsed hunger=%.3f" % actor.hunger)
	capability.call("process_actor_needs", 0.15)
	var expected_hunger := 100.0 - actor.get_stat_value("hunger_drain_rate") * NpcRules.WORLD_HUNGER_DRAIN_MULTIPLIER * 0.25
	if absf(actor.hunger - expected_hunger) > FLOAT_TOLERANCE:
		_fail("Scheduled hunger tick mismatch got=%.3f expected=%.3f" % [actor.hunger, expected_hunger])
	actor.free()


func _validate_bleeding_ticks_every_process() -> void:
	var actor := _make_actor()
	var capability = actor.get_actor_capability(&"needs")
	actor.hunger_enabled = false
	actor.fatigue_enabled = false
	actor.blood = 100.0
	actor.max_blood = 100.0
	actor._bleed_rate = 10.0
	capability.call("process_actor_needs", 0.5)
	var expected_blood := 100.0 - 10.0 * NpcRules.BLEED_TO_BLOOD_RATE * 0.5
	if absf(actor.blood - expected_blood) > FLOAT_TOLERANCE:
		_fail("Bleeding tick mismatch got=%.3f expected=%.3f" % [actor.blood, expected_blood])
	actor.free()


func _validate_carried_actor_skip() -> void:
	var carrier := _make_actor()
	var actor := _make_actor()
	var capability = actor.get_actor_capability(&"needs")
	actor.hunger_enabled = true
	actor.fatigue_enabled = false
	actor.hunger = 100.0
	actor.hunger_drain_rate = 10.0
	actor.blood = 100.0
	actor.max_blood = 100.0
	actor._bleed_rate = 10.0
	actor._carried_by = carrier
	capability.call("set_tick_remaining", 0.0)
	capability.call("process_actor_needs", 1.0)
	if absf(actor.hunger - 100.0) > FLOAT_TOLERANCE:
		_fail("Carried actor hunger should not tick hunger=%.3f" % actor.hunger)
	if absf(actor.blood - 100.0) > FLOAT_TOLERANCE:
		_fail("Carried actor bleeding should not tick blood=%.3f" % actor.blood)
	actor.free()
	carrier.free()


func _make_actor() -> HumanoidCharacter:
	var actor := HUMANOID_SCRIPT.new() as HumanoidCharacter
	actor.call("_setup_actor_capabilities")
	return actor


func _fail(message: String) -> void:
	_failures.append(message)
