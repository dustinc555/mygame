extends "res://addons/gecs/ecs/system.gd"

class_name GameCombatStateSyncSystem

# S2.0: one-way node -> component sync of combat decision inputs, so the batched combat
# systems (S2.1/S2.3) can read packed data instead of reflecting into the node per candidate.
# Register AFTER GameActorSyncSystem and BEFORE the combat systems.

const C_NODE = preload("res://scripts/ecs/components/c_game_actor_node.gd")
const C_CONFIG = preload("res://scripts/ecs/components/c_game_combat_config.gd")
const C_STATE = preload("res://scripts/ecs/components/c_game_combat_state.gd")

static var config_sync_interval_frames := 120
static var _config_sync_frames_remaining := 0
static var profile_enabled := OS.get_cmdline_args().has("--gecs-combat-profile")
static var _profile_calls := 0
static var _profile_usec := 0


func query() -> QueryBuilder:
	return q.with_all([C_NODE, C_CONFIG, C_STATE]).iterate([C_NODE, C_CONFIG, C_STATE])


func process(entities: Array, components: Array, _delta: float) -> void:
	var profile_start := Time.get_ticks_usec() if profile_enabled else 0
	var nodes: Array = components[0]
	var configs: Array = components[1]
	var states: Array = components[2]
	var sync_config := _config_sync_frames_remaining <= 0
	if sync_config:
		_config_sync_frames_remaining = maxi(config_sync_interval_frames, 1)
	else:
		_config_sync_frames_remaining -= 1
	for index in range(entities.size()):
		var actor := _resolve_actor(nodes[index])
		if actor == null:
			continue
		if sync_config:
			_sync_config(configs[index], actor)
		_sync_state(states[index], actor)
	_record_profile(profile_start, sync_config)


func _resolve_actor(actor_component) -> Node:
	if actor_component == null:
		return null
	var actor = actor_component.get_actor() if actor_component.has_method("get_actor") else actor_component.actor
	return actor as Node if actor != null and is_instance_valid(actor) else null


func _sync_config(component, actor: Node) -> void:
	if component == null:
		return
	if actor.has_method("get_attack_range"):
		component.attack_range = maxf(float(actor.call("get_attack_range")), 0.0)
	else:
		component.attack_range = _num(actor.get("attack_range"), component.attack_range)
	component.aggro_scan_radius = _num(actor.get("aggressive_scan_radius"), component.aggro_scan_radius)
	component.assist_scan_radius = _num(actor.get("assist_scan_radius"), component.assist_scan_radius)
	component.witness_radius = _num(actor.get("combat_witness_radius"), component.witness_radius)
	component.squad_assist_radius = _num(actor.get("combat_squad_assist_radius"), component.squad_assist_radius)
	component.move_target_vertical_tolerance = _num(actor.get("move_target_vertical_tolerance"), component.move_target_vertical_tolerance)
	component.navigation_agent_radius = _num(actor.get("navigation_agent_radius"), component.navigation_agent_radius)
	component.active_attack_slots = int(_num(actor.get("combat_active_attack_slots"), component.active_attack_slots))
	component.combat_stance = int(_num(actor.get("combat_stance"), component.combat_stance))
	if actor.has_method("is_protected_from_combat"):
		component.protected_from_combat = bool(actor.call("is_protected_from_combat"))
	component.attack_cooldown_seconds = _num(actor.get("attack_cooldown_seconds"), component.attack_cooldown_seconds)
	if actor.has_method("get_stat_value"):
		component.attack_cooldown_seconds = maxf(float(actor.call("get_stat_value", "attack_cooldown")), 0.2)
	if actor.has_method("get_combat_damage"):
		var damage: Dictionary = actor.call("get_combat_damage") as Dictionary
		component.blunt_damage = maxf(float(damage.get("blunt_damage", component.blunt_damage)), 0.0)
		component.cut_damage = maxf(float(damage.get("cut_damage", component.cut_damage)), 0.0)
	if actor.has_method("get_combat_hit_score"):
		component.hit_score = float(actor.call("get_combat_hit_score"))
	if actor.has_method("get_combat_dodge_score"):
		component.dodge_score = float(actor.call("get_combat_dodge_score"))
	if actor.has_method("get_combat_block_score"):
		component.block_score = float(actor.call("get_combat_block_score"))
	if actor.has_method("get_combat_block_damage_multiplier"):
		component.block_damage_multiplier = clampf(float(actor.call("get_combat_block_damage_multiplier")), 0.0, 1.0)
	if actor.has_method("get_combat_crit_chance"):
		component.crit_chance = clampf(float(actor.call("get_combat_crit_chance")), 0.0, 1.0)
	if actor.has_method("get_stat_value"):
		component.toughness = maxf(float(actor.call("get_stat_value", "toughness")), 0.0)
	if actor.has_method("has_combat_shield"):
		component.has_shield = bool(actor.call("has_combat_shield"))
	if actor.has_method("get_combat_weapon_skill_id"):
		component.weapon_skill_id = str(actor.call("get_combat_weapon_skill_id"))
	component.move_speed = _num(actor.get("move_speed"), component.move_speed)
	if actor.has_method("get_stat_value"):
		component.move_speed *= maxf(float(actor.call("get_stat_value", "move_speed_multiplier")), 0.0)
	component.movement_acceleration = _num(actor.get("acceleration"), component.movement_acceleration)


func _sync_state(component, actor: Node) -> void:
	if component == null:
		return
	var target = actor.call("get_current_combat_target") if actor.has_method("get_current_combat_target") else null
	component.current_target_id = target.get_instance_id() if target != null and is_instance_valid(target) else 0
	component.current_target_actor_id = _actor_id(target)
	var last_attacker = actor.get("_last_direct_attacker_id")
	component.last_direct_attacker_id = int(last_attacker) if last_attacker != null else 0
	var attacker_node = instance_from_id(component.last_direct_attacker_id) if component.last_direct_attacker_id != 0 else null
	component.last_direct_attacker_actor_id = _actor_id(attacker_node as Node)
	var sneaking = actor.get("sneaking")
	component.sneaking = bool(sneaking) if sneaking != null else false
	var grudges = actor.get("_personal_hostile_ids")
	if grudges is Dictionary:
		var ids := PackedInt64Array()
		var actor_ids := PackedStringArray()
		for key in grudges.keys():
			var instance_id := int(key)
			ids.append(instance_id)
			var hostile_actor := instance_from_id(instance_id) as Node
			var hostile_actor_id := _actor_id(hostile_actor)
			if not hostile_actor_id.is_empty():
				actor_ids.append(hostile_actor_id)
		component.personal_hostile_ids = ids
		component.personal_hostile_actor_ids = actor_ids


func _num(value, fallback: float) -> float:
	return float(value) if value != null else fallback


func _actor_id(actor: Node) -> String:
	if actor == null or not is_instance_valid(actor):
		return ""
	var stable = actor.get("stable_id")
	if stable != null and not str(stable).strip_edges().is_empty():
		return str(stable).strip_edges()
	if actor.has_meta("actor_record_id"):
		return str(actor.get_meta("actor_record_id")).strip_edges()
	return ""


func _record_profile(profile_start: int, sync_config: bool) -> void:
	if not profile_enabled:
		return
	_profile_calls += 1
	_profile_usec += Time.get_ticks_usec() - profile_start
	if _profile_calls >= 240:
		print("GECS_COMBAT_PROFILE state_sync avg_usec=%.2f calls=%d last_sync_config=%s" % [float(_profile_usec) / float(_profile_calls), _profile_calls, str(sync_config)])
		_profile_calls = 0
		_profile_usec = 0
