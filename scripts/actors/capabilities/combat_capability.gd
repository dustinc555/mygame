extends "res://scripts/actors/capabilities/actor_capability.gd"

class_name CombatCapability

const COMBAT_COORDINATOR = preload("res://scripts/characters/combat_coordinator.gd")

var cooldown_remaining := 0.0
var action_active := false
var action_names: Array[String] = []
var action_index := 0
var action_clip_remaining := 0.0
var action_remaining := 0.0
var action_impact_remaining := 0.0
var action_has_impacted := false
var action_target: Node
var action_attack_id := ""
var action_hit_reaction_names: Array[String] = []
var action_blunt_damage := 0.0
var action_cut_damage := 0.0
var action_is_critical := false
var reaction_remaining := 0.0
var reaction_source: Node


func _init() -> void:
	super._init(&"combat")


func teardown() -> void:
	clear_all_state()
	super.teardown()


func process_cooldown(delta: float) -> void:
	if cooldown_remaining > 0.0:
		cooldown_remaining = maxf(0.0, cooldown_remaining - delta)


func process_action_state(delta: float) -> void:
	if reaction_remaining > 0.0:
		reaction_remaining = maxf(0.0, reaction_remaining - delta)
		if reaction_remaining <= 0.0:
			reaction_source = null
	if not action_active:
		return
	if _get_actor_life_state() != NpcRules.LifeState.ALIVE:
		clear_action()
		return

	action_remaining = maxf(0.0, action_remaining - delta)
	action_clip_remaining = maxf(0.0, action_clip_remaining - delta)
	if not action_has_impacted:
		action_impact_remaining -= delta
		if action_impact_remaining <= 0.0:
			resolve_action_impact()

	if action_clip_remaining <= 0.0 and action_index < action_names.size() - 1:
		action_index += 1
		play_current_action_clip()
		return

	if action_remaining <= 0.0:
		if not action_has_impacted:
			resolve_action_impact()
		finish_action()


func start_attack(target: Node) -> void:
	if not is_ready():
		return
	if actor == null or not is_instance_valid(actor) or target == null or not is_instance_valid(target):
		return
	if actor.has_method("_get_active_combat_target") and actor.call("_get_active_combat_target") != target:
		COMBAT_COORDINATOR.register_combat_target(actor, target)
		if actor.has_method("_invalidate_combat_slot_role_cache"):
			actor.call("_invalidate_combat_slot_role_cache")
	var animation_set = actor.call("_get_current_combat_animation_set") if actor.has_method("_get_current_combat_animation_set") else null
	var attack = actor.call("_choose_combat_attack", animation_set) if actor.has_method("_choose_combat_attack") else null
	if attack == null:
		start_default_timed_attack(target)
		return

	var next_action_names: Array[String] = attack.get_animation_names()
	var timing := _get_combat_action_timing(next_action_names, float(attack.impact_ratio))
	var action_seconds := float(timing.get("total_seconds", _get_default_action_seconds()))
	if not COMBAT_COORDINATOR.try_begin_exchange(actor, target, action_seconds):
		return
	if actor.has_method("get_body_projection"):
		var body = actor.call("get_body_projection")
		if body != null and body.has_method("stop_clip"):
			body.call("stop_clip", true)
	_spend_attack_cost()
	_award_attack_xp()
	action_names = next_action_names
	action_index = 0
	action_clip_remaining = float(timing.get("first_clip_seconds", 0.0))
	action_remaining = action_seconds
	action_impact_remaining = float(timing.get("impact_seconds", action_seconds))
	action_has_impacted = false
	action_target = target
	action_attack_id = str(attack.attack_id)
	action_hit_reaction_names = attack.get_hit_reaction_names()
	var action_damage := _roll_attack_damage()
	action_blunt_damage = float(action_damage.get("blunt_damage", 0.0))
	action_cut_damage = float(action_damage.get("cut_damage", 0.0))
	action_is_critical = bool(action_damage.get("critical", false))
	action_active = true
	cooldown_remaining = _get_attack_cooldown_seconds()
	play_current_action_clip()


func start_default_timed_attack(target: Node) -> void:
	if not is_ready():
		return
	if actor == null or not is_instance_valid(actor) or target == null or not is_instance_valid(target):
		return
	var timing := _get_combat_action_timing([], _get_default_impact_ratio())
	var action_seconds := float(timing.get("total_seconds", _get_default_action_seconds()))
	if not COMBAT_COORDINATOR.try_begin_exchange(actor, target, action_seconds):
		return
	_spend_attack_cost()
	_award_attack_xp()
	action_names.clear()
	action_index = 0
	action_clip_remaining = 0.0
	action_remaining = action_seconds
	action_impact_remaining = float(timing.get("impact_seconds", action_seconds))
	action_has_impacted = false
	action_target = target
	action_attack_id = ""
	action_hit_reaction_names.clear()
	var action_damage := _roll_attack_damage()
	action_blunt_damage = float(action_damage.get("blunt_damage", 0.0))
	action_cut_damage = float(action_damage.get("cut_damage", 0.0))
	action_is_critical = bool(action_damage.get("critical", false))
	action_active = true
	cooldown_remaining = _get_attack_cooldown_seconds()


func receive_attack(attacker: Node, blunt_damage: float, cut_damage: float, attack_id: String = "", hit_reaction_names: Array[String] = [], is_critical := false) -> String:
	if actor == null or not is_instance_valid(actor) or attacker == null or not is_instance_valid(attacker) or _get_actor_life_state() == NpcRules.LifeState.DEAD:
		return "ignored"
	if _actor_call_bool("is_protected_from_combat"):
		return "ignored"
	var nonlethal_arrest := _actor_call_bool("_is_nonlethal_authority_arrest_attack", [attacker])
	if _get_actor_life_state() == NpcRules.LifeState.ASLEEP and actor.has_method("wake_up_from_rest"):
		actor.call("wake_up_from_rest", false)
	if _get_actor_life_state() == NpcRules.LifeState.ALIVE:
		_actor_call_void("_break_stealth_for_combat")
	_actor_call_void("mark_hostile", [attacker])
	if attacker.has_method("mark_hostile"):
		attacker.call("mark_hostile", actor)
	_set_actor_property("_last_direct_attacker_id", attacker.get_instance_id())
	if not _actor_call_bool("_is_incoming_law_arrest", [attacker]):
		_actor_call_void("_notify_defensive_allies_of_attack", [attacker])
	_actor_call_void("_face_character", [attacker])
	_actor_call_void("_remember_combat_attack_impulse", [attacker, blunt_damage + cut_damage])
	var can_actively_defend := _get_actor_life_state() == NpcRules.LifeState.ALIVE and not _get_actor_bool_property("_is_getting_up")
	var incoming_hit_score := _call_float(attacker, "get_combat_hit_score", [], 0.0)
	if can_actively_defend and _roll_resolution_chance() > _call_float(attacker, "get_combat_hit_chance", [actor], 1.0):
		_spend_fatigue(NpcRules.FATIGUE_DODGE_COST)
		_actor_call_void("add_skill_xp", [SkillRules.ATTRIBUTE_DEXTERITY, 0.35, "combat_dodge"])
		_actor_call_void("_show_world_notice", ["Dodge", Color(0.74, 0.94, 1.0, 1.0)])
		_actor_call_void("_try_start_self_defense", [attacker])
		return "dodged"
	var final_blunt := maxf(blunt_damage, 0.0)
	var final_cut := maxf(cut_damage, 0.0)
	if can_actively_defend and _roll_resolution_chance() <= _actor_call_float("get_combat_block_chance", [incoming_hit_score], 0.0):
		_spend_fatigue(NpcRules.FATIGUE_BLOCK_COST)
		if _actor_call_bool("has_combat_shield"):
			_actor_call_void("add_skill_xp", [SkillRules.COMBAT_SHIELDS, 0.25, "combat_block"])
		else:
			_actor_call_void("add_skill_xp", [_actor_call_string("get_combat_weapon_skill_id", [], SkillRules.COMBAT_UNARMED), 0.15, "combat_parry"])
		_actor_call_void("add_skill_xp", [SkillRules.ATTRIBUTE_TOUGHNESS, 0.12, "combat_block"])
		var combat_block_damage_multiplier := _actor_call_float("get_combat_block_damage_multiplier", [], 1.0)
		final_blunt *= combat_block_damage_multiplier
		final_cut *= combat_block_damage_multiplier
		var blocked_grit_damage := _actor_call_dictionary("apply_toughness_grit", [final_blunt, final_cut])
		final_blunt = float(blocked_grit_damage.get("blunt_damage", 0.0))
		final_cut = float(blocked_grit_damage.get("cut_damage", 0.0))
		if nonlethal_arrest:
			var arrest_damage := _actor_call_dictionary("_clamp_nonlethal_arrest_damage", [final_blunt, final_cut])
			final_blunt = float(arrest_damage.get("blunt", 0.0))
			final_cut = 0.0
		prepare_reaction(attacker)
		var has_shield_block := _actor_call_bool("has_combat_shield")
		play_reaction(_actor_call_string("_pick_combat_block_reaction_clip", [has_shield_block], ""))
		COMBAT_COORDINATOR.extend_character_lock(actor, reaction_remaining + 0.05)
		_actor_call_void("_show_world_notice", ["Shield Block" if has_shield_block else "Parry", Color(0.86, 0.9, 1.0, 1.0)])
		_apply_resolved_damage(final_blunt, final_cut)
		_actor_call_void("_try_start_self_defense", [attacker])
		return "blocked"
	if can_actively_defend:
		prepare_reaction(attacker)
		play_reaction(_actor_call_string("_pick_combat_hit_reaction_clip", [attack_id, hit_reaction_names], ""))
		COMBAT_COORDINATOR.extend_character_lock(actor, reaction_remaining + 0.05)
	var grit_damage := _actor_call_dictionary("apply_toughness_grit", [final_blunt, final_cut])
	final_blunt = float(grit_damage.get("blunt_damage", 0.0))
	final_cut = float(grit_damage.get("cut_damage", 0.0))
	if nonlethal_arrest:
		var arrest_damage := _actor_call_dictionary("_clamp_nonlethal_arrest_damage", [final_blunt, final_cut])
		final_blunt = float(arrest_damage.get("blunt", 0.0))
		final_cut = 0.0
	_apply_resolved_damage(final_blunt, final_cut)
	_actor_call_void("_show_world_notice", ["Critical Hit" if is_critical else "Hit", Color(1.0, 0.42, 0.42, 1.0)])
	_actor_call_void("_try_start_self_defense", [attacker])
	return "hit"


func play_current_action_clip() -> void:
	if action_index < 0 or action_index >= action_names.size():
		return
	var animation_name := action_names[action_index]
	if actor != null and is_instance_valid(actor) and actor.has_method("_play_combat_action_clip"):
		action_clip_remaining = float(actor.call("_play_combat_action_clip", animation_name))


func resolve_action_impact() -> void:
	action_has_impacted = true
	if action_target == null or not is_instance_valid(action_target):
		return
	var target_life_state = action_target.get("life_state")
	if target_life_state != null and int(target_life_state) != NpcRules.LifeState.ALIVE:
		return
	if actor != null and is_instance_valid(actor) and actor.has_method("_face_character"):
		actor.call("_face_character", action_target)
	if action_target.has_method("receive_attack"):
		action_target.call(
			"receive_attack",
			actor,
			action_blunt_damage,
			action_cut_damage,
			action_attack_id,
			action_hit_reaction_names,
			action_is_critical
		)


func finish_action() -> void:
	clear_action()


func clear_action() -> void:
	action_active = false
	action_names.clear()
	action_index = 0
	action_clip_remaining = 0.0
	action_remaining = 0.0
	action_impact_remaining = 0.0
	action_has_impacted = false
	action_target = null
	action_attack_id = ""
	action_hit_reaction_names.clear()
	action_blunt_damage = 0.0
	action_cut_damage = 0.0
	action_is_critical = false


func prepare_reaction(attacker: Node) -> void:
	if action_active:
		clear_action()
	reaction_source = attacker
	if actor != null and is_instance_valid(actor) and actor.has_method("_face_character"):
		actor.call("_face_character", attacker)


func play_reaction(animation_name: String) -> bool:
	reaction_remaining = 0.0
	if animation_name.is_empty():
		reaction_source = null
		return false
	if action_active:
		clear_action()
	if actor == null or not is_instance_valid(actor) or not actor.has_method("_play_combat_reaction_clip"):
		reaction_source = null
		return false
	var next_reaction_seconds := float(actor.call("_play_combat_reaction_clip", animation_name))
	if next_reaction_seconds <= 0.0:
		reaction_source = null
		return false
	reaction_remaining = next_reaction_seconds
	return true


func clear_reaction() -> void:
	reaction_remaining = 0.0
	reaction_source = null


func clear_for_actor(other: Node = null) -> void:
	if other == null:
		clear_all_state()
		return
	if other == null or action_target == other:
		clear_action()
	if other == null or reaction_source == other:
		clear_reaction()


func clear_all_state() -> void:
	cooldown_remaining = 0.0
	clear_action()
	clear_reaction()


func is_busy() -> bool:
	return action_active or reaction_remaining > 0.0


func is_ready() -> bool:
	return not is_busy() and cooldown_remaining <= 0.0


func get_focus_actor() -> Node:
	if reaction_source != null and is_instance_valid(reaction_source):
		return reaction_source
	if action_target != null and is_instance_valid(action_target):
		return action_target
	return null


func _get_combat_action_timing(next_action_names: Array[String], impact_ratio: float) -> Dictionary:
	if actor != null and is_instance_valid(actor) and actor.has_method("_get_combat_action_timing"):
		return actor.call("_get_combat_action_timing", next_action_names, impact_ratio) as Dictionary
	var action_seconds := _get_default_action_seconds()
	return {
		"total_seconds": action_seconds,
		"first_clip_seconds": 0.0,
		"impact_seconds": clampf(action_seconds * impact_ratio, 0.05, maxf(0.05, action_seconds - 0.03)),
	}


func _roll_attack_damage() -> Dictionary:
	if actor != null and is_instance_valid(actor) and actor.has_method("_roll_combat_action_damage"):
		return actor.call("_roll_combat_action_damage") as Dictionary
	if actor != null and is_instance_valid(actor) and actor.has_method("roll_combat_attack_damage"):
		return actor.call("roll_combat_attack_damage") as Dictionary
	return {"blunt_damage": 0.0, "cut_damage": 0.0, "critical": false}


func _spend_attack_cost() -> void:
	if actor != null and is_instance_valid(actor) and actor.has_method("_spend_fatigue"):
		actor.call("_spend_fatigue", NpcRules.FATIGUE_ATTACK_COST)


func _award_attack_xp() -> void:
	if actor != null and is_instance_valid(actor) and actor.has_method("_award_combat_attack_xp"):
		actor.call("_award_combat_attack_xp")


func _get_attack_cooldown_seconds() -> float:
	if actor != null and is_instance_valid(actor) and actor.has_method("get_stat_value"):
		return maxf(0.2, float(actor.call("get_stat_value", "attack_cooldown")))
	return 0.2


func _get_actor_life_state() -> int:
	if actor == null or not is_instance_valid(actor):
		return NpcRules.LifeState.DEAD
	var value = actor.get("life_state")
	return int(value) if value != null else NpcRules.LifeState.ALIVE


func _get_default_action_seconds() -> float:
	if actor != null and is_instance_valid(actor) and actor.has_method("_get_default_combat_action_seconds"):
		return float(actor.call("_get_default_combat_action_seconds"))
	return 0.45


func _get_default_impact_ratio() -> float:
	if actor != null and is_instance_valid(actor) and actor.has_method("_get_default_combat_impact_ratio"):
		return float(actor.call("_get_default_combat_impact_ratio"))
	return 0.45


func _apply_resolved_damage(final_blunt: float, final_cut: float) -> void:
	_add_actor_float("_current_blunt_damage", final_blunt)
	_add_actor_float("_current_open_cut_damage", final_cut)
	_actor_call_void("_add_bleeding_from_cut", [final_blunt, final_cut])
	_actor_call_void("_on_resolved_damage", [final_blunt, final_cut])
	_actor_call_void("_award_toughness_xp", [final_blunt + final_cut])
	_actor_call_void("_recalculate_vitals")


func _spend_fatigue(amount: float) -> void:
	if actor != null and is_instance_valid(actor) and actor.has_method("_spend_fatigue"):
		actor.call("_spend_fatigue", amount)


func _roll_resolution_chance() -> float:
	if actor != null and is_instance_valid(actor) and actor.has_method("_roll_combat_resolution_chance"):
		return float(actor.call("_roll_combat_resolution_chance"))
	return randf()


func _add_actor_float(property_name: String, amount: float) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	actor.set(property_name, float(actor.get(property_name)) + amount)


func _set_actor_property(property_name: String, value) -> void:
	if actor != null and is_instance_valid(actor):
		actor.set(property_name, value)


func _get_actor_bool_property(property_name: String) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	var value = actor.get(property_name)
	return bool(value) if value != null else false


func _actor_call_void(method_name: StringName, args: Array = []) -> void:
	if actor != null and is_instance_valid(actor) and actor.has_method(method_name):
		actor.callv(method_name, args)


func _actor_call_bool(method_name: StringName, args: Array = [], fallback := false) -> bool:
	if actor != null and is_instance_valid(actor) and actor.has_method(method_name):
		return bool(actor.callv(method_name, args))
	return fallback


func _actor_call_float(method_name: StringName, args: Array = [], fallback := 0.0) -> float:
	if actor != null and is_instance_valid(actor) and actor.has_method(method_name):
		return float(actor.callv(method_name, args))
	return fallback


func _actor_call_string(method_name: StringName, args: Array = [], fallback := "") -> String:
	if actor != null and is_instance_valid(actor) and actor.has_method(method_name):
		return str(actor.callv(method_name, args))
	return fallback


func _actor_call_dictionary(method_name: StringName, args: Array = []) -> Dictionary:
	if actor != null and is_instance_valid(actor) and actor.has_method(method_name):
		return actor.callv(method_name, args) as Dictionary
	return {}


func _call_float(target: Node, method_name: StringName, args: Array = [], fallback := 0.0) -> float:
	if target != null and is_instance_valid(target) and target.has_method(method_name):
		return float(target.callv(method_name, args))
	return fallback
