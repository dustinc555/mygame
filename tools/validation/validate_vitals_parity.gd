extends SceneTree

## S4 PRE-FLIP SAFETY NET (architecture/combat/VITALS_GECS_MIGRATION.md). Before GameVitalsSystem is
## made authoritative, prove the GECS path (CGameActorVitals + VitalsStateMachine) produces field-for-
## field IDENTICAL results to a REAL node VitalsCapability under the same operations. This upgrades the
## hand-computed checks in validate_vitals_system.gd to parity against the actual oracle code, so the
## flip is a move of ownership, not of meaning.
##
## Run: godot --headless --path . --script res://tools/validation/validate_vitals_parity.gd
##
## Each scenario applies the same op to BOTH a capability and a component, then asserts every durable
## vitals field matches. The component mirrors the two apply-paths the S4 resolution system will use:
##   apply_resolved_damage(b,c) -> v.blunt_damage += max(b,0); v.open_cut_damage += max(c,0); recalculate
##   per-tick process()         -> VitalsStateMachine.tick(v, toughness, healing_rate, delta)

const C_VITALS_PATH := "res://features/actors/sim/c_game_actor_vitals.gd"
const VSM_PATH := "res://features/actors/sim/vitals_state_machine.gd"
const SYNC_PATH := "res://features/actors/sim/game_actor_sync_system.gd"

var C_VITALS
var VSM
var SYNC
var _registered_ecs := false


func _initialize() -> void:
	_ensure_ecs_singleton()
	C_VITALS = load(C_VITALS_PATH)
	VSM = load(VSM_PATH)
	SYNC = load(SYNC_PATH)

	var failures: Array[String] = []

	# --- Scenario A: a fatal blunt hit -> DYING, then ride the dying countdown to DEAD. ---
	var a := _new_pair(100.0, 100.0, 100.0)
	_apply_damage(a, 250.0, 0.0)  # hp -150 -> DYING, timer armed
	_assert_parity(failures, "A: fatal blunt -> DYING", a)
	for i in range(6):
		_tick(a, 5.0)  # 6 * 5s = 30s > dying_seconds(0)=20 -> DEAD partway through
		_assert_parity(failures, "A: dying tick %d" % i, a)

	# --- Scenario B: bleeding drains blood across many ticks -> DYING -> DEAD. ---
	var b := _new_pair(100.0, 100.0, 100.0)
	_set_bleed(b, 6.0, 2.0)  # rate + burst
	for i in range(40):
		_tick(b, 0.5)
		_assert_parity(failures, "B: bleed tick %d" % i, b)

	# --- Scenario C: wounds drop to coma/unconscious, then recovery heals back over time. ---
	var c := _new_pair(100.0, 100.0, 100.0)
	_apply_damage(c, 108.0, 0.0)  # hp -8 -> UNCONSCIOUS
	_assert_parity(failures, "C: KO from wounds", c)
	for i in range(60):
		_tick(c, 0.5)
		_assert_parity(failures, "C: recovery tick %d" % i, c)

	# --- Scenario D: mixed blunt + cut + bleed burst, interleaved damage and ticks. ---
	var d := _new_pair(100.0, 100.0, 100.0)
	_apply_damage(d, 20.0, 15.0)
	_assert_parity(failures, "D: mixed wound apply", d)
	_set_bleed(d, 3.0, 5.0)
	for i in range(20):
		_tick(d, 0.4)
		if i == 8:
			_apply_damage(d, 40.0, 10.0)  # a second hit mid-stream
		_assert_parity(failures, "D: interleaved tick %d" % i, d)

	_free_pairs([a, b, c, d])

	# --- The reverse-sync BRIDGE: prove the component's truth reaches the node + its consumers. ---
	_test_sync_bridge(failures)

	_teardown_ecs_singleton()
	if failures.is_empty():
		print("PASS validate_vitals_parity (%d assertions: parity + sync-bridge)" % _assertions)
	else:
		for f in failures:
			push_error(f)
		print("FAIL validate_vitals_parity: %d mismatches" % failures.size())
	quit(failures.size())


# --- pair construction: a real capability + a component seeded to match it -------------------------

func _new_pair(max_hp: float, max_blood: float, blood: float) -> Dictionary:
	var actor := WorldActor.new()
	actor.max_hp = max_hp
	actor.hp = max_hp
	actor.base_max_blood = 0.0
	actor.max_blood = max_blood
	actor.blood = blood
	actor._create_actor_capabilities()
	for capability in actor._capabilities.values():
		(capability as ActorCapability).setup(actor)
	for capability in actor._capabilities.values():
		(capability as ActorCapability).ready()
	var vitals := actor.get_vitals() as VitalsCapability
	var stats := actor.get_stats()
	var toughness: float = stats.get_stat_value("toughness")
	var healing: float = stats.get_stat_value("healing_rate")
	var comp = C_VITALS.new()
	comp.life_state = vitals.life_state
	comp.hp = vitals.hp
	comp.max_hp = vitals.max_hp
	comp.blood = vitals.blood
	comp.max_blood = vitals.max_blood
	comp.base_max_blood = vitals.base_max_blood
	comp.blunt_damage = vitals.blunt_damage
	comp.open_cut_damage = vitals.open_cut_damage
	comp.bandaged_cut_damage = vitals.bandaged_cut_damage
	comp.bleed_rate = vitals.bleed_rate
	comp.bleed_burst_rate = vitals.bleed_burst_rate
	comp.recovery_multiplier = vitals.recovery_multiplier
	comp.dying_timer_remaining = vitals.dying_timer_remaining
	return {"actor": actor, "vitals": vitals, "comp": comp, "toughness": toughness, "healing": healing}


func _apply_damage(pair: Dictionary, blunt: float, cut: float) -> void:
	var vitals := pair["vitals"] as VitalsCapability
	vitals.apply_resolved_damage(blunt, cut)
	var v = pair["comp"]
	v.blunt_damage += maxf(blunt, 0.0)
	v.open_cut_damage += maxf(cut, 0.0)
	VSM.recalculate(v, pair["toughness"])


func _set_bleed(pair: Dictionary, rate: float, burst: float) -> void:
	var vitals := pair["vitals"] as VitalsCapability
	vitals.set_bleed_rate(rate)
	vitals.set_bleed_burst_rate(burst)
	pair["comp"].bleed_rate = rate
	pair["comp"].bleed_burst_rate = burst


func _tick(pair: Dictionary, delta: float) -> void:
	# Call the per-phase methods directly (same order as VSM.tick). The capability's process() wrapper is
	# now observer-gated for system-owned humanoids (S4), but the per-phase logic is unchanged and is the
	# real parity oracle.
	var v := pair["vitals"] as VitalsCapability
	v.process_bleeding(delta)
	v.process_dying(delta)
	v.process_recovery(delta)
	VSM.tick(pair["comp"], pair["toughness"], pair["healing"], delta)


var _assertions := 0


func _assert_parity(failures: Array[String], label: String, pair: Dictionary) -> void:
	_assertions += 1
	var v := pair["vitals"] as VitalsCapability
	var c = pair["comp"]
	if v.life_state != c.life_state:
		failures.append("%s: life_state %d != %d" % [label, v.life_state, c.life_state])
	_close(failures, label, "hp", v.hp, c.hp)
	_close(failures, label, "blood", v.blood, c.blood)
	_close(failures, label, "blunt", v.blunt_damage, c.blunt_damage)
	_close(failures, label, "open_cut", v.open_cut_damage, c.open_cut_damage)
	_close(failures, label, "bandaged", v.bandaged_cut_damage, c.bandaged_cut_damage)
	_close(failures, label, "bleed_rate", v.bleed_rate, c.bleed_rate)
	_close(failures, label, "bleed_burst", v.bleed_burst_rate, c.bleed_burst_rate)
	_close(failures, label, "dying_timer", v.dying_timer_remaining, c.dying_timer_remaining)


func _close(failures: Array[String], label: String, field: String, a: float, b: float) -> void:
	if absf(a - b) > 0.0001:
		failures.append("%s: %s %f != %f" % [label, field, a, b])


func _test_sync_bridge(failures: Array[String]) -> void:
	var sync = SYNC.new()

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
	robot._create_actor_capabilities()
	for capability in robot._capabilities.values():
		(capability as ActorCapability).setup(robot)
	for capability in robot._capabilities.values():
		(capability as ActorCapability).ready()
	return robot


func _expect(failures: Array[String], label: String, cond: bool) -> void:
	_assertions += 1
	if not cond:
		failures.append(label)


func _free_pairs(pairs: Array) -> void:
	for pair in pairs:
		(pair["actor"] as WorldActor).free()


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
