extends "res://features/actors/bridge/capabilities/actor_capability.gd"

class_name StatsCapability

## Owns one concern: actor stats and skills.
##
## Holds the raw skill/attribute levels (ActorSkillSet, with the shared XP curve)
## and resolves effective stat values through the fixed modifier layers from
## `architecture/core_attributes/README.md`:
##
##   raw stat -> racial -> body/cybernetic -> equipment -> injury/condition -> final
##
## TEMPLATE NOTE (this is the first real capability — later ones copy this shape):
##   - State lives here, not on the actor node.
##   - It reaches another capability (Equipment) through ONE typed handle acquired
##     in `ready()`. The dependency is one-directional and acyclic: Stats reads
##     Equipment; Equipment never reads Stats. No reflection, no `has_method`.
##   - It does NOT call other capabilities back. Cross-capability reactions go out
##     as a signal (`skill_level_changed`) that interested capabilities connect to.
##     This is what keeps the graph free of cycles.

const ACTOR_SKILL_SET_SCRIPT = preload("res://features/skills/resources/actor_skill_set.gd")
const XP_FLUSH_INTERVAL_SECONDS := 1.0

## Emitted when a skill/attribute level changes. VitalsCapability connects to
## refresh toughness-derived max blood.
signal skill_level_changed(skill_id: String)
## Emitted for any level or XP change so persistence can mirror full progress.
signal skill_progress_changed(skill_id: String)

# --- Raw skill/attribute storage -------------------------------------------

var skill_set: ActorSkillSet
var starting_skill_levels: Dictionary = {}

# --- Base stat config (authored defaults; override via configure_base_stats) -
# Defaults preserved from the pre-migration WorldActor so combat math is unchanged.

var base_attack_damage := 18.0
var attack_range := 1.15
var attack_cooldown_seconds := 1.2
var attack_cut_ratio := 0.05
var base_dodge_chance := 0.08
var base_block_chance := 0.06
var block_damage_multiplier := 0.4
var hunger_drain_rate := 0.08

# --- Internal --------------------------------------------------------------

var _equipment: EquipmentCapability
var _starting_skill_levels_applied := false
var _pending_progress_signal_by_skill: Dictionary = {}
var _pending_level_signal_by_skill: Dictionary = {}
var _xp_flush_remaining := XP_FLUSH_INTERVAL_SECONDS


func _init() -> void:
	super._init(&"stats")


func ready() -> void:
	# One typed handle to the equipment layer. Acyclic: Stats -> Equipment only.
	_equipment = actor.get_capability(&"equipment") as EquipmentCapability
	_ensure_skill_set()


func teardown() -> void:
	flush_pending_xp()
	_equipment = null
	skill_set = null
	super.teardown()


func physics_process(delta: float) -> void:
	_xp_flush_remaining -= delta
	if _xp_flush_remaining <= 0.0:
		flush_pending_xp()

# ---------------------------------------------------------------------------
# Authoring / save injection
# ---------------------------------------------------------------------------

func set_skill_set(value: ActorSkillSet) -> void:
	skill_set = value
	_starting_skill_levels_applied = false
	_ensure_skill_set()


func configure_base_stats(config: Dictionary) -> void:
	base_attack_damage = float(config.get("base_attack_damage", base_attack_damage))
	attack_range = float(config.get("attack_range", attack_range))
	attack_cooldown_seconds = float(config.get("attack_cooldown_seconds", attack_cooldown_seconds))
	attack_cut_ratio = float(config.get("attack_cut_ratio", attack_cut_ratio))
	base_dodge_chance = float(config.get("base_dodge_chance", base_dodge_chance))
	base_block_chance = float(config.get("base_block_chance", base_block_chance))
	block_damage_multiplier = float(config.get("block_damage_multiplier", block_damage_multiplier))
	hunger_drain_rate = float(config.get("hunger_drain_rate", hunger_drain_rate))

# ---------------------------------------------------------------------------
# Skills (raw levels + XP) — delegate to ActorSkillSet
# ---------------------------------------------------------------------------

func get_skill_level(skill_id: String) -> int:
	_ensure_skill_set()
	return skill_set.get_skill_level(skill_id)


func set_skill_level(skill_id: String, level: int, clear_xp := true) -> void:
	flush_pending_xp()
	_ensure_skill_set()
	skill_set.set_skill_level(skill_id, level, clear_xp)
	skill_level_changed.emit(skill_id)
	skill_progress_changed.emit(skill_id)


func add_skill_xp(skill_id: String, amount: float, reason := "") -> int:
	if skill_id.is_empty() or amount <= 0.0:
		return 0
	_ensure_skill_set()
	var levels := skill_set.add_skill_xp(skill_id, amount, reason)
	if _pending_progress_signal_by_skill.is_empty():
		_xp_flush_remaining = XP_FLUSH_INTERVAL_SECONDS
		physics_process_enabled = true
	_pending_progress_signal_by_skill[skill_id] = true
	if levels > 0:
		_pending_level_signal_by_skill[skill_id] = true
	return levels


func flush_pending_xp() -> int:
	if _pending_progress_signal_by_skill.is_empty():
		_xp_flush_remaining = XP_FLUSH_INTERVAL_SECONDS
		physics_process_enabled = false
		return 0
	var pending_progress := _pending_progress_signal_by_skill
	var pending_levels := _pending_level_signal_by_skill
	_pending_progress_signal_by_skill = {}
	_pending_level_signal_by_skill = {}
	_xp_flush_remaining = XP_FLUSH_INTERVAL_SECONDS
	physics_process_enabled = false
	for skill_id_value in pending_progress.keys():
		var skill_id := str(skill_id_value)
		if pending_levels.has(skill_id_value):
			skill_level_changed.emit(skill_id)
		skill_progress_changed.emit(skill_id)
	return pending_levels.size()


func hydrate_skill_progress(skill_levels: Dictionary, skill_xp: Dictionary) -> void:
	_pending_progress_signal_by_skill.clear()
	_pending_level_signal_by_skill.clear()
	_xp_flush_remaining = XP_FLUSH_INTERVAL_SECONDS
	physics_process_enabled = false
	_ensure_skill_set()
	var skill_ids := {}
	for skill_id in skill_levels:
		skill_ids[str(skill_id)] = true
	for skill_id in skill_xp:
		skill_ids[str(skill_id)] = true
	for skill_id in skill_ids:
		skill_set.set_skill_progress(str(skill_id), int(skill_levels.get(skill_id, SkillRules.DEFAULT_LEVEL)), float(skill_xp.get(skill_id, 0.0)))


func get_skill_xp(skill_id: String) -> float:
	_ensure_skill_set()
	return skill_set.get_skill_xp(skill_id)


func get_skill_xp_to_next(skill_id: String) -> float:
	_ensure_skill_set()
	return skill_set.get_skill_xp_to_next(skill_id)


func get_skill_progress_ratio(skill_id: String) -> float:
	_ensure_skill_set()
	return skill_set.get_skill_progress_ratio(skill_id)


func get_skill_entry_snapshot(skill_id: String) -> Dictionary:
	_ensure_skill_set()
	return skill_set.get_entry_snapshot(skill_id)

# ---------------------------------------------------------------------------
# Effective stat resolution (the layered model)
# ---------------------------------------------------------------------------

func get_stat_value(stat_name: String, include_secondary_modifiers: bool = true) -> float:
	var value := _get_base_stat_value(stat_name)
	if include_secondary_modifiers:
		value = _apply_layer(value, stat_name, _racial_modifiers())
		value = _apply_layer(value, stat_name, _body_modifiers())
		value = _apply_layer(value, stat_name, _equipment_modifiers())
		value = _apply_layer(value, stat_name, _injury_modifiers())
	return _clamp_stat(stat_name, value)


## Applies one layer's modifiers for a single stat.
## Layer math: value = (value + sum(add)) * prod(mul). Item modifiers carry both
## additive and multiplicative terms, so this preserves pre-migration combat math
## exactly when only the equipment layer is populated. The per-layer `(1 + sum)`
## form in core_attributes/README.md is the eventual target once every layer is a
## pure multiplier; see plans/migration.md for the reconciliation note.
func _apply_layer(value: float, stat_name: String, modifiers: Array) -> float:
	var additive := 0.0
	var multiplier := 1.0
	for modifier in modifiers:
		if String(modifier.get("stat", "")) != stat_name:
			continue
		additive += float(modifier.get("add", 0.0))
		multiplier *= float(modifier.get("mul", 1.0))
	return (value + additive) * multiplier

# --- Modifier layer sources (each returns Array of {stat, add, mul}) --------

func _racial_modifiers() -> Array:
	# TODO Phase 2+: pull from the actor's race definition.
	return []


func _body_modifiers() -> Array:
	# TODO Phase 2+: pull from the actor's body archetype / cybernetics.
	return []


func _equipment_modifiers() -> Array:
	return _equipment.get_stat_modifiers() if _equipment != null else []


func _injury_modifiers() -> Array:
	# TODO Phase 2+: pull from VitalsCapability wound/condition state.
	return []

# --- Base values + clamps (ported faithfully from pre-migration WorldActor) --

func _get_base_stat_value(stat_name: String) -> float:
	match stat_name:
		"attack_damage":
			return base_attack_damage
		"attack_range":
			return attack_range
		"strength":
			return float(get_skill_level(SkillRules.ATTRIBUTE_STRENGTH))
		"dexterity":
			return float(get_skill_level(SkillRules.ATTRIBUTE_DEXTERITY))
		"toughness":
			return float(get_skill_level(SkillRules.ATTRIBUTE_TOUGHNESS))
		"perception":
			return float(get_skill_level(SkillRules.ATTRIBUTE_PERCEPTION))
		"stealth":
			return float(get_skill_level(SkillRules.SUBTERFUGE_SNEAKING))
		"attack_cooldown":
			return attack_cooldown_seconds
		"cut_ratio":
			return attack_cut_ratio
		"dodge_chance":
			return base_dodge_chance + SkillRules.get_diminishing_bonus(float(get_skill_level(SkillRules.ATTRIBUTE_DEXTERITY)), 0.18, 45.0)
		"block_chance":
			return base_block_chance
		"block_damage_multiplier":
			return block_damage_multiplier
		"weapon_parry_bonus", "shield_block_bonus":
			return 0.0
		"move_speed_multiplier":
			return 1.0
		"run_speed_multiplier":
			return NpcRules.RUN_SPEED_MULTIPLIER + SkillRules.get_diminishing_bonus(float(get_skill_level(SkillRules.MOVEMENT_RUNNING)), 0.42, 55.0)
		"hunger_drain_rate":
			var endurance_hunger_reduction := SkillRules.get_diminishing_bonus(float(get_skill_level(SkillRules.ATTRIBUTE_ENDURANCE)), 0.16, 65.0)
			return hunger_drain_rate * (1.0 - endurance_hunger_reduction)
		"fatigue_recovery_rate":
			return NpcRules.FATIGUE_IDLE_RECOVERY + SkillRules.get_diminishing_bonus(float(get_skill_level(SkillRules.ATTRIBUTE_ENDURANCE)), 0.9, 60.0)
		"healing_rate":
			return NpcRules.BASE_HEAL_RATE
	return 0.0


func _clamp_stat(stat_name: String, value: float) -> float:
	match stat_name:
		"dodge_chance", "block_chance", "cut_ratio":
			return clampf(value, 0.0, 0.95)
		"block_damage_multiplier":
			return clampf(value, 0.0, 1.0)
		"attack_cooldown":
			return maxf(0.2, value)
		"move_speed_multiplier", "run_speed_multiplier", "attack_damage", "attack_range", "strength", "dexterity", "toughness", "perception", "stealth", "hunger_drain_rate", "fatigue_recovery_rate", "healing_rate", "weapon_parry_bonus", "shield_block_bonus":
			return maxf(0.0, value)
	return value

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _ensure_skill_set() -> void:
	if skill_set == null:
		skill_set = ACTOR_SKILL_SET_SCRIPT.new() as ActorSkillSet
	_apply_starting_skill_levels_if_needed()


## Merge + immediately apply starting skill levels authored AFTER `ready()` already ran
## (e.g. an actor that seeds its own defaults post-`super._ready()`, like QuadBotCharacter).
## Without this, levels set after the one-shot apply in ready() are silently ignored.
func apply_starting_skill_levels(levels: Dictionary) -> void:
	for skill_id_value in levels.keys():
		starting_skill_levels[skill_id_value] = levels[skill_id_value]
	_starting_skill_levels_applied = false
	_apply_starting_skill_levels_if_needed()


func _apply_starting_skill_levels_if_needed() -> void:
	if _starting_skill_levels_applied or skill_set == null:
		return
	_starting_skill_levels_applied = true
	for skill_id_value in starting_skill_levels.keys():
		var skill_id := str(skill_id_value)
		if skill_id.is_empty():
			continue
		skill_set.set_skill_level(skill_id, int(starting_skill_levels[skill_id_value]))
