extends SceneTree

## Validates the timed food effect: eating starts a single effect that drips
## the item's nutrition_value into hunger over FOOD_EFFECT_DURATION_SECONDS,
## a second eat is blocked while the effect runs, and hunger drain stays
## paused until it expires. Bread (150 points / 180s) must recover exactly
## a bar and a half for a base character.
##
## Run: godot --headless --path . --script res://tools/validation/validate_food_effect.gd

const BREAD := preload("res://features/inventory/resources/items/bread.tres")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_bread_resource()
	_validate_effect_lifecycle()
	if _failures.is_empty():
		print("FOOD_EFFECT_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("FOOD_EFFECT_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_bread_resource() -> void:
	if BREAD == null:
		_fail("Bread resource should load")
		return
	if not is_equal_approx(BREAD.nutrition_value, 150.0):
		_fail("Bread nutrition_value should be 150 (a bar and a half), got %.1f" % BREAD.nutrition_value)


func _validate_effect_lifecycle() -> void:
	var needs := NeedsCapability.new()
	needs.hunger_enabled = true
	needs.hunger_stage = NpcRules.HungerStage.STARVING
	needs.hunger = 50.0

	if not needs.start_food_effect(BREAD.nutrition_value, NpcRules.FOOD_EFFECT_DURATION_SECONDS):
		_fail("start_food_effect should accept when no effect is active")
	if needs.start_food_effect(BREAD.nutrition_value, NpcRules.FOOD_EFFECT_DURATION_SECONDS):
		_fail("start_food_effect should refuse while an effect is active")
	if not needs.is_food_effect_active():
		_fail("is_food_effect_active should report true right after eating")
	var expected_rate := BREAD.nutrition_value / NpcRules.FOOD_EFFECT_DURATION_SECONDS
	if absf(needs.get_food_effect_rate() - expected_rate) > 0.001:
		_fail("Effect rate should be %.4f pts/s, got %.4f" % [expected_rate, needs.get_food_effect_rate()])

	# Half the duration: 75 points. STARVING 50 crosses a stage to HUNGRY 25.
	_tick(needs, NpcRules.FOOD_EFFECT_DURATION_SECONDS * 0.5)
	if needs.hunger_stage != NpcRules.HungerStage.HUNGRY or absf(needs.hunger - 25.0) > 1.0:
		_fail("Mid-effect should be HUNGRY 25/100, got stage=%d hunger=%.2f" % [needs.hunger_stage, needs.hunger])
	if not needs.is_food_effect_active():
		_fail("Effect should still be active at half duration")

	# Remaining half: 75 more points. 150 total from STARVING 50 is exactly a
	# bar and a half, landing on the HUNGRY 100 boundary (stages only walk
	# back when recovery crosses past 100, not on the boundary itself).
	_tick(needs, NpcRules.FOOD_EFFECT_DURATION_SECONDS * 0.5)
	if needs.is_food_effect_active():
		_fail("Effect should expire after the full duration")
	if needs.hunger_stage != NpcRules.HungerStage.HUNGRY or absf(needs.hunger - 100.0) > 1.0:
		_fail("Post-effect should be HUNGRY 100/100, got stage=%d hunger=%.2f" % [needs.hunger_stage, needs.hunger])
	if not needs.start_food_effect(BREAD.nutrition_value, NpcRules.FOOD_EFFECT_DURATION_SECONDS):
		_fail("Eating should unblock once the previous effect expired")


func _tick(needs: NeedsCapability, seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.0:
		var step := minf(0.25, remaining)
		needs.process_needs(step)
		remaining -= step


func _fail(message: String) -> void:
	_failures.append(message)
