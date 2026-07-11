extends SceneTree

## S3 gate for the vitals -> GECS ownership flip (architecture/combat/VITALS_GECS_MIGRATION.md).
## Proves the shared VitalsStateMachine reproduces every VitalsCapability life-state transition on a
## CGameActorVitals component, and that GameVitalsSystem honors the LOD gate + decrements the window.
## Deterministic, no scene. Oracle: features/actors/bridge/capabilities/vitals_capability.gd.
## Run: godot --headless --path . --script res://tools/validation/validate_vitals_system.gd
##
## With max_hp=max_blood=100, toughness=0: coma_point=-10, death_point=-100, blood_death=-100,
## dying_seconds=20. Those anchors are what the edge cases below are built around.

const C_VITALS_PATH := "res://features/actors/sim/c_game_actor_vitals.gd"
const C_VITALS_INPUTS_PATH := "res://features/actors/sim/c_game_actor_vitals_inputs.gd"
const VITALS_SYSTEM_PATH := "res://features/actors/sim/game_vitals_system.gd"
const VSM_PATH := "res://features/actors/sim/vitals_state_machine.gd"

var C_VITALS
var C_VITALS_INPUTS
var VITALS_SYSTEM
var VSM  # VitalsStateMachine; loaded at runtime so this gate does not depend on the global class cache.
var _registered_ecs := false


func _initialize() -> void:
	_ensure_ecs_singleton()
	C_VITALS = load(C_VITALS_PATH)
	C_VITALS_INPUTS = load(C_VITALS_INPUTS_PATH)
	VITALS_SYSTEM = load(VITALS_SYSTEM_PATH)
	VSM = load(VSM_PATH)

	var failures: Array[String] = []
	const ALIVE := NpcRules.LifeState.ALIVE
	const UNCONSCIOUS := NpcRules.LifeState.UNCONSCIOUS
	const COMA := NpcRules.LifeState.RECOVERY_COMA
	const DYING := NpcRules.LifeState.DYING
	const DEAD := NpcRules.LifeState.DEAD

	# --- recalculate: hp derives from wounds; healthy actor stays ALIVE. ---
	var v := _new_vitals({"blunt_damage": 30.0})
	VSM.recalculate(v, 0.0)
	_expect(failures, "hp = max_hp - wounds", is_equal_approx(v.hp, 70.0))
	_expect(failures, "healthy stays ALIVE", v.life_state == ALIVE)

	# --- recalculate thresholds: unconscious < coma < dying as hp falls. ---
	v = _new_vitals({"blunt_damage": 105.0})  # hp = -5 in (-10, 0]
	VSM.recalculate(v, 0.0)
	_expect(failures, "hp -5 -> UNCONSCIOUS", v.life_state == UNCONSCIOUS)

	v = _new_vitals({"blunt_damage": 120.0})  # hp = -20 in (-100, -10]
	VSM.recalculate(v, 0.0)
	_expect(failures, "hp -20 -> RECOVERY_COMA", v.life_state == COMA)

	v = _new_vitals({"blunt_damage": 250.0})  # hp = -150 <= death_point -100
	VSM.recalculate(v, 0.0)
	_expect(failures, "hp -150 -> DYING", v.life_state == DYING)
	_expect(failures, "DYING arms timer to dying_seconds", is_equal_approx(v.dying_timer_remaining, 20.0))

	# --- dying timer arms ONLY on the edge (re-recalc must not reset a partly-spent clock). ---
	v.dying_timer_remaining = 5.0
	VSM.recalculate(v, 0.0)
	_expect(failures, "re-enter DYING does not re-arm timer", is_equal_approx(v.dying_timer_remaining, 5.0))

	# --- ALIVE only out of a recoverable downed state; non-downed unchanged. ---
	v = _new_vitals({"life_state": UNCONSCIOUS, "blunt_damage": 0.0})  # hp back to 100
	VSM.recalculate(v, 0.0)
	_expect(failures, "downed + healthy hp -> ALIVE", v.life_state == ALIVE)

	# --- bleeding drains blood and can drive ALIVE -> DYING in one tick. ---
	v = _new_vitals({"blood": 5.0, "bleed_rate": 1000.0})
	VSM.process_bleeding(v, 0.0, 1.0)  # loss = 1000*0.18 = 180 -> blood clamps to -100
	_expect(failures, "bleeding clamps blood to -max_blood", is_equal_approx(v.blood, -100.0))
	_expect(failures, "fatal blood loss -> DYING", v.life_state == DYING)

	# --- dying countdown reaches zero -> DEAD. ---
	v = _new_vitals({"life_state": DYING, "hp": -150.0, "dying_timer_remaining": 0.1})
	VSM.process_dying(v, 0.2)
	_expect(failures, "lethal dying timer expiry -> DEAD", v.life_state == DEAD)
	_expect(failures, "dead clamps timer to 0", is_equal_approx(v.dying_timer_remaining, 0.0))

	# --- dying but no longer lethal -> stabilises into coma, not death. ---
	v = _new_vitals({"life_state": DYING, "hp": 50.0, "blood": 50.0, "dying_timer_remaining": 10.0})
	VSM.process_dying(v, 0.2)
	_expect(failures, "non-lethal dying -> RECOVERY_COMA", v.life_state == COMA)
	_expect(failures, "coma stabilise leaves timer untouched", is_equal_approx(v.dying_timer_remaining, 10.0))

	# --- recovery heals wounds and lifts a downed actor back to ALIVE. ---
	v = _new_vitals({"life_state": UNCONSCIOUS, "blunt_damage": 5.0})
	VSM.process_recovery(v, 0.0, 10.0, 1.0)  # healing_step 10 clears the 5 blunt
	_expect(failures, "recovery clears wound", is_equal_approx(v.blunt_damage, 0.0))
	_expect(failures, "recovered downed actor -> ALIVE", v.life_state == ALIVE)

	# --- recovery with no healing rate is a no-op (preserves the node's early-out). ---
	v = _new_vitals({"life_state": UNCONSCIOUS, "blunt_damage": 5.0})
	VSM.process_recovery(v, 0.0, 0.0, 1.0)
	_expect(failures, "no healing -> wound unchanged", is_equal_approx(v.blunt_damage, 5.0))
	_expect(failures, "no healing -> still UNCONSCIOUS", v.life_state == UNCONSCIOUS)

	# --- GameVitalsSystem: robots are skipped (node owns their death model until S5). ---
	var system = VITALS_SYSTEM.new()
	var robot := _new_vitals({"blood": 100.0, "bleed_rate": 1000.0, "death_profile": CGameActorVitals.DeathProfile.ROBOT})
	var robot_inp = C_VITALS_INPUTS.new()
	system.process([null], [[robot], [robot_inp]], 0.05)
	_expect(failures, "robot death_profile not simulated", is_equal_approx(robot.blood, 100.0))

	# --- GameVitalsSystem: realized humanoids (default profile) ARE simulated. ---
	var live := _new_vitals({"blood": 100.0, "bleed_rate": 1000.0})
	var live_inp = C_VITALS_INPUTS.new()
	system.process([null], [[live], [live_inp]], 0.05)
	_expect(failures, "humanoid profile simulated (bled)", live.blood < 100.0)

	# --- Rest commands are consumed only on fixed ticks and permit exact voluntary transitions. ---
	var rest_system = VITALS_SYSTEM.new()
	var resting := _new_vitals({})
	var rest_input = C_VITALS_INPUTS.new()
	rest_input.pending_rest_state = NpcRules.LifeState.ASLEEP
	rest_system.process([null], [[resting], [rest_input]], 0.049)
	_expect(failures, "rest request waits for fixed tick", resting.life_state == ALIVE)
	rest_system.process([null], [[resting], [rest_input]], 0.001)
	_expect(failures, "fixed tick applies ALIVE -> ASLEEP", resting.life_state == NpcRules.LifeState.ASLEEP)
	_expect(failures, "sleep request is consumed once", rest_input.pending_rest_state == -1)
	rest_input.pending_rest_state = ALIVE
	rest_system.process([null], [[resting], [rest_input]], 0.05)
	_expect(failures, "fixed tick applies ASLEEP -> ALIVE", resting.life_state == ALIVE)
	var downed := _new_vitals({"life_state": UNCONSCIOUS})
	var downed_input = C_VITALS_INPUTS.new()
	downed_input.healing_rate = 0.0
	downed_input.pending_rest_state = ALIVE
	rest_system.process([null], [[downed], [downed_input]], 0.05)
	_expect(failures, "rest wake cannot revive unconscious actor", downed.life_state == UNCONSCIOUS)
	_expect(failures, "rejected wake request is consumed", downed_input.pending_rest_state == -1)

	_teardown_ecs_singleton()
	if failures.is_empty():
		print("PASS validate_vitals_system (26 checks)")
	else:
		for f in failures:
			push_error(f)
		print("FAIL validate_vitals_system: %d failures" % failures.size())
	quit(failures.size())


func _new_vitals(overrides: Dictionary) -> Object:
	var v = C_VITALS.new()
	for key in overrides:
		v.set(key, overrides[key])
	return v


func _ensure_ecs_singleton() -> void:
	if Engine.has_singleton("ECS"):
		return
	var placeholder := Node.new()
	placeholder.name = "ECS"
	Engine.register_singleton("ECS", placeholder)
	_registered_ecs = true


func _teardown_ecs_singleton() -> void:
	if _registered_ecs:
		Engine.unregister_singleton("ECS")


func _expect(failures: Array[String], label: String, cond: bool) -> void:
	if not cond:
		failures.append(label)
