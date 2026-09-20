extends "res://tests/validation/test_case.gd"

## Authoritative life-state transitions, fixed rest requests, carried recovery and
## node/component synchronization. Consolidates the useful former migration parity gate.
## Run: python3 tests/run_validation.py --filter validate_vitals_system

const C_VITALS_PATH := "res://features/actors/sim/c_game_actor_vitals.gd"
const C_VITALS_INPUTS_PATH := "res://features/actors/sim/c_game_actor_vitals_inputs.gd"
const VITALS_SYSTEM_PATH := "res://features/actors/sim/game_vitals_system.gd"
const VSM_PATH := "res://features/actors/sim/vitals_state_machine.gd"

var C_VITALS
var C_VITALS_INPUTS
var VITALS_SYSTEM
var VSM  # VitalsStateMachine; loaded at runtime so this gate does not depend on the global class cache.
var _checks := 0


func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
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

	system.free()
	rest_system.free()
	_test_sync_bridge(failures)
	_test_authoritative_sequences(failures)
	_test_component_projection_sequences(failures)
	if failures.is_empty():
		print("PASS validate_vitals_system (%d checks)" % _checks)
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


func _new_pair(max_hp: float, max_blood: float, blood: float) -> Dictionary:
	var actor := WorldActor.new()
	actor.max_hp = max_hp
	actor.hp = max_hp
	actor.base_max_blood = 0.0
	actor.max_blood = max_blood
	actor.blood = blood
	root.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	return {"actor": actor, "vitals": actor.get_vitals(), "comp": C_VITALS.new()}

func _test_sync_bridge(failures: Array[String]) -> void:
	var sync = GameActorSyncSystem.new()

	# 1) REVERSE: a seeded component that says DEAD must drive the NODE dead through the delegating
	#    getter (actor.life_state -> vitals.life_state) and fire died/state_changed — the exact paths
	#    the settlement death poll and the command-bar refresh read. This is the load-bearing bridge.
	var p := _new_pair(100.0, 100.0, 100.0)
	var actor := p["actor"] as WorldActor
	var comp = p["comp"]
	comp.vitals_seeded = true
	comp.life_state = NpcRules.LifeState.DEAD
	comp.hp = -200.0
	comp.blood = -200.0
	var probe := {"died": false, "state": false}
	actor.died.connect(func(_a): probe["died"] = true)
	actor.state_changed.connect(func(): probe["state"] = true)
	sync._sync_vitals(comp, actor)
	_expect(failures, "reverse: actor.life_state getter reflects DEAD", actor.life_state == NpcRules.LifeState.DEAD)
	_expect(failures, "reverse: actor.hp getter reflects component", absf(actor.hp - (-200.0)) <= 0.0001)
	_expect(failures, "reverse: died fired (settlement death-poll path)", probe["died"])
	_expect(failures, "reverse: state_changed fired (command-bar path)", probe["state"])
	actor.free()

	# 2) SEED-ONCE: a fresh (defaults) component first mirrors a pre-wounded node, flips vitals_seeded,
	#    then reverses on the next sync (prevents clobbering a pre-wounded/loaded actor to defaults).
	var p2 := _new_pair(100.0, 100.0, 100.0)
	var actor2 := p2["actor"] as WorldActor
	var vitals2 := p2["vitals"] as VitalsCapability
	vitals2.set_blunt_damage(30.0)
	var fresh = C_VITALS.new()
	sync._sync_vitals(fresh, actor2)
	_expect(failures, "seed: fresh component seeded from node wounds", absf(fresh.blunt_damage - 30.0) <= 0.0001)
	_expect(failures, "seed: vitals_seeded flips true", fresh.vitals_seeded)
	fresh.blunt_damage = 0.0
	sync._sync_vitals(fresh, actor2)
	_expect(failures, "reverse-after-seed: component clears the node wound", absf(vitals2.blunt_damage - 0.0) <= 0.0001)
	actor2.life_state = NpcRules.LifeState.ASLEEP
	sync._sync_vitals(fresh, actor2)
	_expect(failures, "reverse-after-seed: node rest state cannot overwrite component", fresh.life_state == NpcRules.LifeState.ALIVE)
	_expect(failures, "reverse-after-seed: component rest state restores node", actor2.life_state == NpcRules.LifeState.ALIVE)
	actor2.free()

	# 3) ROBOT: a RobotActor stays node-owned (death_profile == ROBOT) so GameVitalsSystem skips it.
	var robot := _make_robot()
	var rcomp = C_VITALS.new()
	sync._sync_vitals(rcomp, robot)
	_expect(failures, "robot: death_profile stamped ROBOT", rcomp.death_profile == CGameActorVitals.DeathProfile.ROBOT)
	robot.free()

	sync.free()


func _make_robot() -> WorldActor:
	var robot := RobotActor.new()
	robot.max_hp = 100.0
	robot.hp = 100.0
	robot.max_blood = 100.0
	robot.blood = 100.0
	root.add_child(robot)
	robot.set_process(false)
	robot.set_physics_process(false)
	return robot


func _test_authoritative_sequences(failures: Array[String]) -> void:
	var system := GameVitalsSystem.new()
	var v := CGameActorVitals.new()
	var inp := CGameActorVitalsInputs.new()
	inp.healing_rate = 0.0
	v.blunt_damage = 250.0
	VitalsStateMachine.recalculate(v, 0.0)
	for _tick in range(401):
		system.process([null], [[v], [inp]], 0.05)
	_expect(failures, "fatal wounds reach terminal death through fixed system ticks", v.life_state == NpcRules.LifeState.DEAD and v.dying_timer_remaining == 0.0)
	v = CGameActorVitals.new()
	v.blunt_damage = 108.0
	VitalsStateMachine.recalculate(v, 0.0)
	inp.healing_rate = 10.0
	inp.held_externally = true
	for _tick in range(240):
		system.process([null], [[v], [inp]], 0.05)
	_expect(failures, "held actor heals but remains downed", v.blunt_damage == 0.0 and v.life_state == NpcRules.LifeState.UNCONSCIOUS)
	v.bleed_rate = 10.0
	var blood_before := v.blood
	inp.healing_rate = 0.0
	system.process([null], [[v], [inp]], 0.05)
	_expect(failures, "carried actors do not gain bleeding immunity", is_finite(v.blood) and v.blood < blood_before)
	inp.held_externally = false
	inp.healing_rate = 10.0
	system.process([null], [[v], [inp]], 0.05)
	_expect(failures, "released healed actor recovers", v.life_state == NpcRules.LifeState.ALIVE)
	var mixed := CGameActorVitals.new()
	mixed.blunt_damage = 20.0
	mixed.open_cut_damage = 15.0
	mixed.bandaged_cut_damage = 5.0
	mixed.bleed_rate = 3.0
	mixed.bleed_burst_rate = 5.0
	for _tick in range(20):
		system.process([null], [[mixed], [inp]], 0.05)
	_expect(failures, "mixed wounds heal and clot through authoritative system", is_finite(mixed.hp) and mixed.blunt_damage < 20.0 and mixed.open_cut_damage < 15.0 and mixed.bandaged_cut_damage < 5.0 and mixed.bleed_burst_rate < 5.0)
	system.free()


func _test_component_projection_sequences(failures: Array[String]) -> void:
	# The former migration gate drove a second, now-unused local medical loop.
	# Instead compare EVERY observable medical field to its single GECS owner
	# throughout those same fatal, bleeding, recovery and second-hit sequences.
	var sync := GameActorSyncSystem.new()
	for scenario in [
		{"label": "fatal blunt", "blunt": 250.0, "cut": 0.0, "bleed": 0.0, "heal": 0.0, "ticks": 450, "state": NpcRules.LifeState.DEAD},
		{"label": "fatal bleeding", "blunt": 0.0, "cut": 0.0, "bleed": 100.0, "heal": 0.0, "ticks": 650, "state": NpcRules.LifeState.DEAD},
		{"label": "unconscious recovery", "blunt": 108.0, "cut": 0.0, "bleed": 0.0, "heal": 10.0, "ticks": 240, "state": NpcRules.LifeState.ALIVE},
		{"label": "mixed second hit", "blunt": 20.0, "cut": 15.0, "bleed": 3.0, "heal": 2.0, "ticks": 160, "state": NpcRules.LifeState.ALIVE},
	]:
		var pair := _new_pair(100.0, 100.0, 100.0)
		var actor: WorldActor = pair.actor
		var component: CGameActorVitals = pair.comp
		var observer := actor.get_vitals()
		sync._sync_vitals(component, actor)
		component.blunt_damage = scenario.blunt
		component.open_cut_damage = scenario.cut
		component.bleed_rate = scenario.bleed
		component.bleed_burst_rate = 5.0 if scenario.label == "mixed second hit" else 0.0
		VitalsStateMachine.recalculate(component, 0.0)
		var system := GameVitalsSystem.new()
		var inputs := CGameActorVitalsInputs.new()
		inputs.healing_rate = scenario.heal
		for tick in range(scenario.ticks):
			if scenario.label == "mixed second hit" and tick == 64:
				component.blunt_damage += 40.0
				component.open_cut_damage += 10.0
				VitalsStateMachine.recalculate(component, 0.0)
			system.process([null], [[component], [inputs]], 0.05)
			sync._sync_vitals(component, actor)
			_expect(failures, "%s tick %d life-state bridge" % [scenario.label, tick], observer.life_state == component.life_state)
			for field in ["hp", "blood", "blunt_damage", "open_cut_damage", "bandaged_cut_damage", "bleed_rate", "bleed_burst_rate", "dying_timer_remaining"]:
				var actual := float(observer.get(field))
				var expected := float(component.get(field))
				_expect(failures, "%s tick %d %s" % [scenario.label, tick, field], is_finite(actual) and is_finite(expected) and absf(actual - expected) < 0.0001)
		_expect(failures, "%s completed expected terminal state" % scenario.label, component.life_state == scenario.state)
		system.free()
		actor.free()
	sync.free()


func _expect(failures: Array[String], label: String, cond: bool) -> void:
	_checks += 1
	if not cond:
		failures.append(label)
