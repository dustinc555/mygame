extends "res://addons/gecs/ecs/system.gd"

class_name GameCombatScoreSystem

# S2.0b: derives the packed combat SCORES (CGameCombatConfig) from the SOURCE stats the node
# authored (CGameCombatLoadout), using CombatMath as the single owner of the arithmetic. This is
# the typed replacement for the dead `get_combat_*` reflection in GameCombatStateSyncSystem: the
# node pushes source stats; this system turns them into the scores the resolution/targeting hot
# path reads. Dirty-gated, so it costs nothing for actors whose loadout has not changed.
#
# Register AFTER the loadout is authored and BEFORE GameCombatResolutionSystem.

const C_LOADOUT = preload("res://features/combat/sim/c_game_combat_loadout.gd")
const C_CONFIG = preload("res://features/combat/sim/c_game_combat_config.gd")


func query() -> QueryBuilder:
	return q.with_all([C_LOADOUT, C_CONFIG]).iterate([C_LOADOUT, C_CONFIG])


func process(entities: Array, components: Array, _delta: float) -> void:
	var loadouts: Array = components[0]
	var configs: Array = components[1]
	for index in range(entities.size()):
		var loadout = loadouts[index]
		var config = configs[index]
		if loadout == null or config == null or not loadout.dirty:
			continue
		_derive(loadout, config)
		loadout.dirty = false


func _derive(loadout, config) -> void:
	# Offensive scores — pure CombatMath from source stats.
	config.hit_score = CombatMath.hit_score(loadout.weapon_skill_level, loadout.dexterity)
	config.dodge_score = CombatMath.dodge_score(loadout.dexterity)
	config.dexterity = loadout.dexterity
	config.crit_chance = CombatMath.crit_chance(loadout.weapon_skill_level, loadout.dexterity)

	# Base damage profile (pre-crit/block/grit; resolution applies those downstream).
	var damage := CombatMath.base_damage(
		loadout.blunt_base,
		loadout.cut_base,
		loadout.weapon_skill_level,
		loadout.strength,
		loadout.dexterity
	)
	config.blunt_damage = damage["blunt_damage"]
	config.cut_damage = damage["cut_damage"]

	# Defense score (block.md): shield-block leans on the shields skill + strength; parry leans on
	# weapon skill + dexterity. Which applies depends on whether a shield is equipped.
	if loadout.has_shield:
		config.block_score = CombatMath.shield_block_score(
			loadout.shields_skill_level, loadout.strength, loadout.shield_block_bonus
		)
	else:
		config.block_score = CombatMath.parry_score(
			loadout.weapon_skill_level, loadout.dexterity, loadout.weapon_parry_bonus
		)

	# Passthrough fields the hot path also reads.
	config.block_damage_multiplier = loadout.block_damage_multiplier
	config.has_shield = loadout.has_shield
	config.toughness = loadout.toughness
	config.weapon_skill_id = loadout.weapon_skill_id
