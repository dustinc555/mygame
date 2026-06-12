extends "res://scripts/characters/humanoid_character.gd"

class_name RustdeadHumanoidCharacter

const RUSTDEAD_RACE = preload("res://resources/character_races/rustdead.tres")
const RUSTDEAD_APPEARANCE_DATA_SCRIPT = preload("res://scripts/character_appearance/character_appearance_data.gd")
const RUSTDEAD_TIER_LIBRARY = preload("res://scripts/characters/rustdead_tier_library.gd")

const RUSTDEAD_IDLE_ANIMATION_NAME := "Zombie_Idle"
const RUSTDEAD_WALK_ANIMATION_NAME := "Zombie_Walk_Fwd"
const RUSTDEAD_RUN_ANIMATION_NAME := "Zombie_Run_Fwd"
const RUSTDEAD_BITE_ANIMATION_NAME := "Zombie_Bite"
const RUSTDEAD_SCRATCH_ANIMATION_NAME := "Zombie_Scratch"
const RUSTDEAD_SPAWN_ANIMATION_NAME := "Zombie_Spawn"
const RUSTDEAD_ANIMATION_NAMES: Array[String] = [
	RUSTDEAD_IDLE_ANIMATION_NAME,
	RUSTDEAD_WALK_ANIMATION_NAME,
	RUSTDEAD_RUN_ANIMATION_NAME,
	RUSTDEAD_BITE_ANIMATION_NAME,
	RUSTDEAD_SCRATCH_ANIMATION_NAME,
	RUSTDEAD_SPAWN_ANIMATION_NAME,
]
@export var fresh_skin_color := Color(0.64, 0.19, 0.16, 1.0)
@export var cinder_burn_duration_seconds := 2.0
@export var rustdead_tier_definition: Resource
@export var rustdead_tier_id := "fresh"
@export_range(0.0, 2.0, 0.01) var rustdead_passive_bonus := 0.2

var _cinder_burn_remaining := 0.0
var _cinder_burn_attacker: HumanoidCharacter
var _allow_cinder_true_death := false
var _is_cinder_burned := false


func _ready() -> void:
	_ensure_rustdead_humanoid_defaults()
	super._ready()


func _exit_tree() -> void:
	super._exit_tree()


func _process(delta: float) -> void:
	_process_cinder_burn(delta)
	super._process(delta)


func _create_body_projection() -> BodyProjection:
	return RustdeadBodyProjection.new()


func _get_rustdead_body_projection() -> RustdeadBodyProjection:
	return (_body as RustdeadBodyProjection) if _body != null and is_instance_valid(_body) else null


func requires_fire_to_die() -> bool:
	return true


func set_rustdead_tier_definition(tier_definition: Resource) -> void:
	rustdead_tier_definition = tier_definition
	_apply_rustdead_tier_definition()


func get_rustdead_tier_definition() -> Resource:
	return rustdead_tier_definition


func get_rustdead_tier_id() -> String:
	return rustdead_tier_id


func get_rustdead_passive_bonus() -> float:
	return maxf(0.0, rustdead_passive_bonus)


func can_be_destroyed_by_cinder() -> bool:
	return is_downed_state() and not is_fire_destruction_in_progress()


func is_fire_destruction_in_progress() -> bool:
	return _cinder_burn_remaining > 0.0


func is_cinder_burned() -> bool:
	return _is_cinder_burned


func has_cinder_burned_visuals() -> bool:
	var body := _get_rustdead_body_projection()
	return body != null and body.has_cinder_burned_visuals()


func begin_cinder_burn(attacker: HumanoidCharacter = null) -> bool:
	if not can_be_destroyed_by_cinder():
		return false
	_cinder_burn_attacker = attacker
	_cinder_burn_remaining = maxf(0.05, cinder_burn_duration_seconds)
	_downed_recover_delay_remaining = maxf(_downed_recover_delay_remaining, _cinder_burn_remaining + 1.0)
	if _is_getting_up:
		_cancel_get_up()
	_is_cinder_burned = true
	var body := _get_rustdead_body_projection()
	if body != null:
		body.begin_cinder_burn_visuals()
	_enter_cinder_dead_state_in_place()
	if body != null:
		body.spawn_cinder_burn_effect(_cinder_burn_remaining, cinder_burn_duration_seconds)
	_show_world_notice("Burning", Color(1.0, 0.45, 0.12, 1.0), 1.6)
	state_changed.emit()
	return true


func force_kill(attacker: HumanoidCharacter = null) -> void:
	if _allow_cinder_true_death:
		super.force_kill(attacker)
		return
	if life_state == NpcRules.LifeState.DEAD:
		return
	var lethal_wounds := max_hp - get_death_point(max_hp)
	var current_wounds := get_total_wound_damage()
	if current_wounds < lethal_wounds:
		_current_blunt_damage += lethal_wounds - current_wounds
	blood = minf(blood, 0.0)
	_recalculate_vitals()
	if not is_downed_state():
		_enter_unconscious_state()


func _should_enter_dead_state_from_vitals() -> bool:
	return false


func _should_enter_dying_state_from_vitals() -> bool:
	return false


func _is_downed_recovery_locked() -> bool:
	return is_fire_destruction_in_progress()


func _ensure_rustdead_humanoid_defaults() -> void:
	character_race = RUSTDEAD_RACE
	_apply_rustdead_tier_definition()
	if appearance_data == null:
		appearance_data = RUSTDEAD_APPEARANCE_DATA_SCRIPT.new()
	elif appearance_data.has_method("make_copy"):
		appearance_data = appearance_data.make_copy()
	appearance_data.character_race = RUSTDEAD_RACE
	if appearance_data.visual_body_type == APPEARANCE_VISUAL_BODY_TYPE_AUTO:
		appearance_data.visual_body_type = visual_body_type
	if not bool(appearance_data.skin_color_customized):
		appearance_data.skin_color_customized = true
		appearance_data.skin_color = fresh_skin_color
	appearance_data.eyebrow_style = null


func _apply_rustdead_tier_definition() -> void:
	if rustdead_tier_definition == null:
		rustdead_tier_definition = RUSTDEAD_TIER_LIBRARY.get_tier_by_id(rustdead_tier_id)
	if rustdead_tier_definition == null:
		rustdead_tier_definition = RUSTDEAD_TIER_LIBRARY.get_default_tier()
	if rustdead_tier_definition != null:
		rustdead_tier_id = str(rustdead_tier_definition.call("get_id")) if rustdead_tier_definition.has_method("get_id") else rustdead_tier_id
		rustdead_passive_bonus = maxf(0.0, float(rustdead_tier_definition.get("passive_bonus")))


func _build_unarmed_combat_animation_set():
	var animation_set = COMBAT_ANIMATION_SET_SCRIPT.new()
	animation_set.stance_id = UNARMED_STANCE_ID
	animation_set.idle_animation_name = RUSTDEAD_IDLE_ANIMATION_NAME
	animation_set.block_animation_name = ""
	animation_set.fallback_hit_reaction_names = PackedStringArray([HIT_CHEST_ANIMATION_NAME, HIT_HEAD_ANIMATION_NAME, HIT_STOMACH_ANIMATION_NAME])
	animation_set.attacks = [
		_make_combat_attack("rustdead_bite", [RUSTDEAD_BITE_ANIMATION_NAME], 1.15, 0.52, [HIT_HEAD_ANIMATION_NAME, HIT_CHEST_ANIMATION_NAME]),
		_make_combat_attack("rustdead_scratch", [RUSTDEAD_SCRATCH_ANIMATION_NAME], 1.0, 0.48, [HIT_CHEST_ANIMATION_NAME, HIT_STOMACH_ANIMATION_NAME]),
	]
	return animation_set


func _collect_stat_modifiers() -> Array:
	var modifiers := super._collect_stat_modifiers()
	var bonus := get_rustdead_passive_bonus()
	if bonus <= 0.0:
		return modifiers
	var multiplier := 1.0 + bonus
	modifiers.append({"stat": "healing_rate", "mul": multiplier})
	modifiers.append({"stat": "blood_recovery_rate", "mul": multiplier})
	if _is_unarmed_combat_stance():
		modifiers.append({"stat": "attack_damage", "mul": multiplier})
		modifiers.append({"stat": "cut_ratio", "mul": multiplier})
	return modifiers


func _process_cinder_burn(delta: float) -> void:
	if _cinder_burn_remaining <= 0.0:
		return
	_cinder_burn_remaining = maxf(0.0, _cinder_burn_remaining - delta)
	_downed_recover_delay_remaining = maxf(_downed_recover_delay_remaining, _cinder_burn_remaining + 0.5)
	var body := _get_rustdead_body_projection()
	if body != null:
		body.update_cinder_burn_visuals(_cinder_burn_remaining, cinder_burn_duration_seconds)
	if _cinder_burn_remaining <= 0.0:
		_finish_cinder_burn()


func _finish_cinder_burn() -> void:
	var body := _get_rustdead_body_projection()
	if body != null:
		body.finish_cinder_burn_visuals()
	_cinder_burn_attacker = null
	_show_world_notice("Burned", Color(0.9, 0.28, 0.08, 1.0), 1.6)


func _enter_cinder_dead_state_in_place() -> void:
	if life_state == NpcRules.LifeState.DEAD:
		return
	_report_murder_crime_if_needed()
	var previous_state := life_state
	life_state = NpcRules.LifeState.DEAD
	_notify_law_order_actor_death()
	_cancel_get_up()
	COMBAT_COORDINATOR.release_character(self)
	running = false
	_clear_actor_move_target()
	_clear_combat_resolution_state()
	if _carried_character != null:
		drop_carried_character()
	if _active_job_provider != null and _active_job_provider.has_method("pause_worker_job"):
		_active_job_provider.pause_worker_job(self, false)
	velocity = Vector3.ZERO
	life_state_changed.emit(previous_state, life_state)
	died.emit(self)
	state_changed.emit()
