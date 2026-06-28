extends SceneTree

## Integration gate for Phase 1: proves CGameCombatLoadout -> GameCombatScoreSystem -> CGameCombatConfig
## derives the packed scores via CombatMath, with the dirty-gate working. Deterministic, no scene.
## Run: godot --headless --path . --script res://tools/validation/validate_combat_score_pipeline.gd

const C_LOADOUT_PATH := "res://features/combat/sim/c_game_combat_loadout.gd"
const C_CONFIG_PATH := "res://features/combat/sim/c_game_combat_config.gd"
const SCORE_SYSTEM_PATH := "res://features/combat/sim/game_combat_score_system.gd"

var C_LOADOUT
var C_CONFIG
var SCORE_SYSTEM
var _registered_ecs := false


func _initialize() -> void:
	_ensure_ecs_singleton()
	C_LOADOUT = load(C_LOADOUT_PATH)
	C_CONFIG = load(C_CONFIG_PATH)
	SCORE_SYSTEM = load(SCORE_SYSTEM_PATH)

	var failures: Array[String] = []
	var system = SCORE_SYSTEM.new()

	# --- Case 1: unarmed, no shield. Scores must equal CombatMath of the source stats. ---
	var loadout = C_LOADOUT.new()
	loadout.weapon_skill_level = 5.0
	loadout.dexterity = 8.0
	loadout.strength = 10.0
	loadout.toughness = 10.0
	loadout.blunt_base = 2.5
	loadout.cut_base = 0.0
	loadout.has_shield = false
	loadout.weapon_parry_bonus = 0.0
	loadout.shields_skill_level = 3.0
	loadout.shield_block_bonus = 0.0
	loadout.block_damage_multiplier = 0.4
	loadout.weapon_skill_id = "combat.unarmed"
	loadout.dirty = true
	var config = C_CONFIG.new()
	system.process([null], [[loadout], [config]], 0.0)

	_expect(failures, "hit_score == CombatMath", is_equal_approx(config.hit_score, CombatMath.hit_score(5.0, 8.0)))
	_expect(failures, "dodge_score == CombatMath", is_equal_approx(config.dodge_score, CombatMath.dodge_score(8.0)))
	_expect(failures, "crit_chance == CombatMath", is_equal_approx(config.crit_chance, CombatMath.crit_chance(5.0, 8.0)))
	var dmg := CombatMath.base_damage(2.5, 0.0, 5.0, 10.0, 8.0)
	_expect(failures, "blunt_damage == CombatMath", is_equal_approx(config.blunt_damage, dmg["blunt_damage"]))
	_expect(failures, "cut_damage == CombatMath", is_equal_approx(config.cut_damage, dmg["cut_damage"]))
	_expect(failures, "block_score uses parry (no shield)", is_equal_approx(config.block_score, CombatMath.parry_score(5.0, 8.0, 0.0)))
	_expect(failures, "block_damage_multiplier passthrough", is_equal_approx(config.block_damage_multiplier, 0.4))
	_expect(failures, "toughness passthrough", is_equal_approx(config.toughness, 10.0))
	_expect(failures, "has_shield passthrough", config.has_shield == false)
	_expect(failures, "weapon_skill_id passthrough", config.weapon_skill_id == "combat.unarmed")
	_expect(failures, "dirty cleared after derive", loadout.dirty == false)

	# --- Case 2: shield equipped -> block_score uses shield-block branch. ---
	var loadout2 = C_LOADOUT.new()
	loadout2.has_shield = true
	loadout2.shields_skill_level = 4.0
	loadout2.strength = 10.0
	loadout2.shield_block_bonus = 1.0
	loadout2.dirty = true
	var config2 = C_CONFIG.new()
	system.process([null], [[loadout2], [config2]], 0.0)
	_expect(failures, "block_score uses shield-block (shield)", is_equal_approx(config2.block_score, CombatMath.shield_block_score(4.0, 10.0, 1.0)))

	# --- Case 3: dirty-gate. A non-dirty loadout must NOT be recomputed. ---
	var loadout3 = C_LOADOUT.new()
	loadout3.dirty = false
	var config3 = C_CONFIG.new()
	config3.hit_score = -999.0
	system.process([null], [[loadout3], [config3]], 0.0)
	_expect(failures, "dirty-gate skips clean loadout", is_equal_approx(config3.hit_score, -999.0))

	_teardown_ecs_singleton()
	if failures.is_empty():
		print("PASS validate_combat_score_pipeline (13 checks)")
	else:
		for f in failures:
			push_error(f)
		print("FAIL validate_combat_score_pipeline: %d failures" % failures.size())
	quit(failures.size())


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
