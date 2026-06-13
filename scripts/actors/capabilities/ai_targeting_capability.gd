extends "res://scripts/actors/capabilities/actor_capability.gd"

class_name AiTargetingCapability

const COMBAT_COORDINATOR = preload("res://scripts/characters/combat_coordinator.gd")
const AI_JOB_SCRIPT = preload("res://scripts/ai/ai_job.gd")

const MAX_COMBAT_TARGET_CANDIDATES := 16
const MAX_COMBAT_QUERY_CANDIDATES := 32
const MAX_COMBAT_SUPPORT_TARGETS := 6
const MAX_COMBAT_ASSIST_NOTIFY_RECIPIENTS := 12
const ORDER_TYPE_HEAL := 8


func _init() -> void:
	super._init(&"ai_targeting")


func should_consider_combat_retarget() -> bool:
	if _life_state() != NpcRules.LifeState.ALIVE:
		return false
	if _call_bool("_has_active_player_order"):
		return false
	if _call_bool("_is_active_ai_combat_player_issued"):
		return false
	if _call_int("_get_active_ai_job_type", [], 0) == AI_JOB_SCRIPT.JobType.LAW_ARREST:
		return false
	var active_target := _active_combat_target()
	if active_target == null:
		return false
	if _call_bool("_is_combat_resolution_busy"):
		return false
	return _life_state_of(active_target) == NpcRules.LifeState.ALIVE


func try_reconfigure_close_combat_target() -> bool:
	if _life_state() != NpcRules.LifeState.ALIVE or _call_bool("_has_active_player_order"):
		return false
	if _call_bool("_is_combat_resolution_busy"):
		return false
	var active_target := _active_combat_target()
	if active_target != null \
			and absf(_position_of(active_target).y - _position().y) <= _actor_float("move_target_vertical_tolerance", 0.75) \
			and _horizontal_distance_to(_position_of(active_target)) <= _attack_range():
		return false
	if active_target == null and not should_seek_combat_target():
		return false
	var close_target := find_closest_hostile(_close_hostile_retarget_radius())
	if close_target == null:
		return false
	if active_target == close_target:
		return false
	if active_target != null and should_keep_current_target_over_close_hostile(active_target, close_target):
		return false
	return _call_bool("assign_attack_target", [close_target, false, false, false])


func should_keep_current_target_over_close_hostile(active_target: Node, close_target: Node) -> bool:
	if not _is_valid_active_combat_target(active_target):
		return false
	if absf(_position_of(active_target).y - _position().y) > _actor_float("move_target_vertical_tolerance", 0.75):
		return false
	var active_distance := _horizontal_distance_to(_position_of(active_target))
	var close_distance := _horizontal_distance_to(_position_of(close_target))
	return active_distance <= close_distance + _attack_range()


func should_seek_combat_target() -> bool:
	if _call_bool("is_protected_from_combat"):
		return false
	if _call_bool("_has_active_player_order"):
		return false
	if _call_bool("is_law_sentence_moving"):
		return false
	if _actor_int("_current_order_type", 0) == ORDER_TYPE_HEAL:
		return false
	if _call_bool("is_carrying_someone") or _node_property("_carried_by") != null:
		return false
	if _active_combat_target() != null:
		return false
	if _combat_stance() == NpcRules.CombatStance.PASSIVE and _actor_int("_last_direct_attacker_id", 0) == 0:
		return false
	return true


func find_ai_target() -> Node:
	if _combat_stance() == NpcRules.CombatStance.PASSIVE:
		return get_last_direct_attacker_target()
	var close_target := find_closest_hostile(_close_hostile_retarget_radius())
	if close_target != null:
		return close_target
	if _combat_stance() == NpcRules.CombatStance.DEFENSIVE:
		var self_defense_target := get_last_direct_attacker_target()
		if self_defense_target != null:
			return self_defense_target
		return find_defensive_assist_target()
	return find_nearest_hostile(_actor_float("aggressive_scan_radius", NpcRules.AGGRO_RANGE))


func get_last_direct_attacker_target() -> Node:
	var attacker_id := _actor_int("_last_direct_attacker_id", 0)
	if attacker_id == 0:
		return null
	var attacker := _call_node("_find_humanoid_by_instance_id", [attacker_id])
	return attacker if _is_valid_combat_target(attacker) else null


func find_defensive_assist_target() -> Node:
	var candidate_entries: Array = []
	var seen_target_ids := {}
	if not _is_inside_tree():
		return null
	var witness_radius := _combat_witness_radius()
	var witness_radius_squared := witness_radius * witness_radius
	for node in get_query_actors(_position(), witness_radius, true):
		if node == actor or not _is_alive_combat_actor(node):
			continue
		if _position().distance_squared_to(_position_of(node)) > witness_radius_squared:
			continue
		var ally_target := _current_combat_target_of(node)
		if not (_is_valid_combat_target(ally_target) and _should_help_against(node, ally_target, true)):
			continue
		var target_id: int = ally_target.get_instance_id()
		if seen_target_ids.has(target_id):
			continue
		seen_target_ids[target_id] = true
		append_bounded_nearest_candidate(candidate_entries, ally_target, _position().distance_squared_to(_position_of(ally_target)), MAX_COMBAT_TARGET_CANDIDATES)
	var candidates := candidate_entries_to_actors(candidate_entries)
	return COMBAT_COORDINATOR.choose_target(actor, candidates, _combat_switch_radius()) as Node


func find_nearest_hostile(scan_radius: float) -> Node:
	var candidate_entries: Array = []
	var radius_squared := scan_radius * scan_radius
	for node in get_query_actors(_position(), scan_radius, true):
		if node == actor or not _is_valid_combat_target(node):
			continue
		if not _has_hostility_with(node):
			continue
		var distance_squared := _position().distance_squared_to(_position_of(node))
		if distance_squared > radius_squared:
			continue
		if not _can_see_actor_for_combat(node):
			continue
		append_bounded_nearest_candidate(candidate_entries, node, distance_squared, MAX_COMBAT_TARGET_CANDIDATES)
	var candidates := candidate_entries_to_actors(candidate_entries)
	return COMBAT_COORDINATOR.choose_target(actor, candidates, scan_radius) as Node


func find_closest_hostile(scan_radius: float, same_level_only := true) -> Node:
	var best_target: Node
	var best_distance_squared := INF
	var radius_squared := scan_radius * scan_radius
	for node in get_query_actors(_position(), scan_radius, true):
		if node == actor or not _is_valid_combat_target(node):
			continue
		if same_level_only and absf(_position_of(node).y - _position().y) > _actor_float("move_target_vertical_tolerance", 0.75):
			continue
		if not _has_hostility_with(node):
			continue
		if not _can_see_actor_for_combat(node):
			continue
		var offset := _position_of(node) - _position()
		offset.y = 0.0
		var distance_squared := offset.length_squared()
		if distance_squared > radius_squared or distance_squared >= best_distance_squared:
			continue
		best_distance_squared = distance_squared
		best_target = node
	return best_target


func try_start_self_defense(attacker: Node) -> void:
	if attacker == null or not _is_valid_combat_target(attacker):
		return
	if _life_state() != NpcRules.LifeState.ALIVE or _call_bool("is_protected_from_combat"):
		return
	if _call_bool("_is_player_order_to_avoid_combat"):
		return
	if should_keep_active_target_against_self_defense(attacker):
		return
	if _active_combat_target() != attacker:
		_call_void("_clear_combat_target_for_direct_self_defense")
	join_defense_against(attacker)


func should_keep_active_target_against_self_defense(attacker: Node) -> bool:
	var active_target := _active_combat_target()
	if active_target == null or active_target == attacker:
		return false
	if _call_bool("_is_player_attack_order_for", [active_target]):
		return true
	if not _is_valid_active_combat_target(active_target):
		return false
	if absf(_position_of(active_target).y - _position().y) > _actor_float("move_target_vertical_tolerance", 0.75):
		return false
	return _horizontal_distance_to(_position_of(active_target)) <= _call_float("_get_combat_settle_band_distance", [active_target], _attack_range())


func notify_defensive_allies_of_attack(attacker: Node) -> void:
	var support_radius := maxf(_combat_witness_radius(), _actor_float("combat_support_target_spread_radius", NpcRules.COMBAT_WITNESS_RANGE))
	var support_targets := get_support_target_candidates(attacker, support_radius)
	var notify_entries: Array = []
	var notify_radius := support_radius
	var notify_radius_squared := notify_radius * notify_radius
	for node in get_query_actors(_position(), notify_radius, true):
		if node == actor or not _is_alive_combat_actor(node):
			continue
		var distance_squared := _position().distance_squared_to(_position_of(node))
		if distance_squared > notify_radius_squared:
			continue
		if not _node_call_bool(node, "_should_help_against", [actor, attacker, true]):
			continue
		append_bounded_nearest_candidate(notify_entries, node, distance_squared, MAX_COMBAT_ASSIST_NOTIFY_RECIPIENTS)
	for responder in candidate_entries_to_actors(notify_entries):
		_node_call_void(responder, "_respond_to_ally_under_attack", [actor, attacker, support_targets])
	_call_void("_notify_settlement_alarm_of_attack", [attacker])


func notify_defensive_allies_of_engagement(target: Node) -> void:
	var support_radius := maxf(_combat_witness_radius(), _actor_float("combat_support_target_spread_radius", NpcRules.COMBAT_WITNESS_RANGE))
	var support_targets := get_support_target_candidates(target, support_radius)
	var notify_entries: Array = []
	var notify_radius := support_radius
	var notify_radius_squared := notify_radius * notify_radius
	for node in get_query_actors(_position(), notify_radius, true):
		if node == actor or not _is_alive_combat_actor(node):
			continue
		var distance_squared := _position().distance_squared_to(_position_of(node))
		if distance_squared > notify_radius_squared:
			continue
		if not _node_call_bool(node, "_should_help_against", [actor, target, false]):
			continue
		append_bounded_nearest_candidate(notify_entries, node, distance_squared, MAX_COMBAT_ASSIST_NOTIFY_RECIPIENTS)
	for responder in candidate_entries_to_actors(notify_entries):
		_node_call_void(responder, "_respond_to_ally_engagement", [actor, target, support_targets])


func respond_to_ally_under_attack(ally: Node, attacker: Node, support_targets: Array = []) -> void:
	if ally == null or attacker == null:
		return
	if _life_state() != NpcRules.LifeState.ALIVE:
		return
	if _combat_stance() == NpcRules.CombatStance.PASSIVE:
		return
	if not _should_help_against(ally, attacker, true):
		return
	var target := choose_support_target(attacker, support_targets, maxf(_combat_switch_radius(), _actor_float("combat_support_target_spread_radius", NpcRules.COMBAT_WITNESS_RANGE)))
	var defense_target = target if target != null else attacker
	if defense_target != null:
		join_defense_against(defense_target)


func respond_to_ally_engagement(ally: Node, target: Node, support_targets: Array = []) -> void:
	if ally == null or target == null:
		return
	if _life_state() != NpcRules.LifeState.ALIVE:
		return
	if _combat_stance() == NpcRules.CombatStance.PASSIVE:
		return
	if not _should_help_against(ally, target, false):
		return
	var support_target := choose_support_target(target, support_targets, maxf(_combat_switch_radius(), _actor_float("combat_support_target_spread_radius", NpcRules.COMBAT_WITNESS_RANGE)))
	var defense_target = support_target if support_target != null else target
	if defense_target != null:
		join_defense_against(defense_target)


func get_support_target_candidates(primary_target: Node, radius: float) -> Array:
	var candidates: Array = []
	if primary_target == null or not is_instance_valid(primary_target):
		return candidates
	candidates.append(primary_target)
	var candidate_entries: Array = []
	var seen_target_ids := {}
	seen_target_ids[primary_target.get_instance_id()] = true
	var radius_squared := radius * radius
	for node in get_query_actors(_position_of(primary_target), radius, true):
		if not _is_alive_combat_actor(node) or node == primary_target:
			continue
		var candidate_id: int = node.get_instance_id()
		if seen_target_ids.has(candidate_id):
			continue
		if _position_of(primary_target).distance_squared_to(_position_of(node)) > radius_squared:
			continue
		seen_target_ids[candidate_id] = true
		append_bounded_nearest_candidate(candidate_entries, node, _position_of(primary_target).distance_squared_to(_position_of(node)), maxi(MAX_COMBAT_SUPPORT_TARGETS - 1, 0))
	candidates.append_array(candidate_entries_to_actors(candidate_entries))
	return candidates


func choose_support_target(primary_target: Node, candidates: Array, scan_radius: float) -> Node:
	if primary_target == null or not is_instance_valid(primary_target):
		return null
	var viable_targets: Array = []
	for candidate_value in candidates:
		var candidate := candidate_value as Node
		if candidate == null or candidate == actor or not _is_valid_combat_target(candidate):
			continue
		if not _has_hostility_with(candidate):
			continue
		if not viable_targets.has(candidate):
			viable_targets.append(candidate)
	if viable_targets.is_empty():
		return primary_target if _is_valid_combat_target(primary_target) and _has_hostility_with(primary_target) else null
	var effective_scan_radius := maxf(scan_radius, _position().distance_to(_position_of(primary_target)) + _attack_range() + 2.0)
	var chosen := COMBAT_COORDINATOR.choose_target(actor, viable_targets, effective_scan_radius) as Node
	if chosen != null:
		return chosen
	return primary_target if _is_valid_combat_target(primary_target) and _has_hostility_with(primary_target) else null


func join_defense_against(threat: Node) -> void:
	if threat == null or not is_instance_valid(threat) or _life_state_of(threat) != NpcRules.LifeState.ALIVE:
		return
	if _call_bool("_is_player_order_to_avoid_combat"):
		return
	_call_void("mark_hostile", [threat])
	_node_call_void(threat, "mark_hostile", [actor])
	_call_void("_record_player_combat_reputation", [threat])
	var active_target := _active_combat_target()
	if active_target != null and active_target != threat:
		if should_keep_active_target_against_self_defense(threat):
			return
		if not COMBAT_COORDINATOR.should_switch_target(actor, active_target, threat, _combat_switch_radius()):
			return
	_call_bool("assign_attack_target", [threat, false, false, false])


func get_query_actors(query_position: Vector3 = Vector3.ZERO, radius := -1.0, include_party := true) -> Array:
	var query_controller := _query_controller()
	if query_controller != null:
		if radius >= 0.0 and query_controller.has_method("get_nearby_actors"):
			return query_controller.call("get_nearby_actors", query_position, radius, include_party)
		if query_controller.has_method("get_alive_actors"):
			return query_controller.call("get_alive_actors", include_party)
	if not _is_inside_tree():
		return []
	var tree := (actor as Node).get_tree()
	var combat_actors := tree.get_nodes_in_group(COMBAT_COORDINATOR.COMBAT_ACTOR_GROUP)
	return combat_actors if not combat_actors.is_empty() else tree.get_nodes_in_group("npc_character")


func get_query_actors_limited(query_position: Vector3, radius: float, max_count: int, include_party := true) -> Array:
	var query_controller := _query_controller()
	if query_controller != null and radius >= 0.0 and query_controller.has_method("get_nearby_actors_limited"):
		return query_controller.call("get_nearby_actors_limited", query_position, radius, max_count, include_party)
	var entries: Array = []
	var radius_squared := radius * radius
	for node in get_query_actors(query_position, radius, include_party):
		if not (node is Node3D):
			continue
		var distance_squared := query_position.distance_squared_to((node as Node3D).global_position)
		if distance_squared > radius_squared:
			continue
		append_bounded_nearest_candidate(entries, node, distance_squared, max_count)
	return candidate_entries_to_actors(entries)


func append_bounded_nearest_candidate(entries: Array, candidate: Node, distance_squared: float, max_count: int) -> void:
	if candidate == null or max_count <= 0:
		return
	var entry := {"target": candidate, "distance_squared": distance_squared}
	for index in range(entries.size()):
		var existing: Dictionary = entries[index] if entries[index] is Dictionary else {}
		if distance_squared < float(existing.get("distance_squared", INF)):
			entries.insert(index, entry)
			if entries.size() > max_count:
				entries.remove_at(entries.size() - 1)
			return
	entries.append(entry)
	if entries.size() > max_count:
		entries.remove_at(entries.size() - 1)


func candidate_entries_to_actors(entries: Array) -> Array:
	var result: Array = []
	for entry_value in entries:
		var entry: Dictionary = entry_value if entry_value is Dictionary else {}
		var target := entry.get("target") as Node
		if target != null and is_instance_valid(target):
			result.append(target)
	return result


func _query_controller() -> Node:
	if actor != null and is_instance_valid(actor) and actor.has_method("_get_runtime_controller"):
		return actor.call("_get_runtime_controller", "actor_query_controller") as Node
	return null


func _should_help_against(protected_actor: Node, threat: Node, allow_public_intervention: bool) -> bool:
	return _call_bool("_should_help_against", [protected_actor, threat, allow_public_intervention])


func _is_valid_combat_target(target: Node) -> bool:
	if target == null or not is_instance_valid(target) or not (target is Node3D):
		return false
	if _life_state_of(target) != NpcRules.LifeState.ALIVE:
		return false
	return not _node_call_bool(target, "is_protected_from_combat")


func _is_valid_active_combat_target(target: Node) -> bool:
	return _is_valid_combat_target(target) and _has_hostility_with(target) and _can_see_actor_for_combat(target)


func _is_alive_combat_actor(target: Node) -> bool:
	return target != null and is_instance_valid(target) and target is Node3D and _life_state_of(target) == NpcRules.LifeState.ALIVE


func _has_hostility_with(target: Node) -> bool:
	return _call_bool("has_hostility_with", [target])


func _can_see_actor_for_combat(target: Node) -> bool:
	return _call_bool("can_see_actor_for_combat", [target], true)


func _active_combat_target() -> Node:
	if actor != null and is_instance_valid(actor) and actor.has_method("get_current_combat_target"):
		return actor.call("get_current_combat_target") as Node
	return null


func _current_combat_target_of(target: Node) -> Node:
	if target != null and is_instance_valid(target) and target.has_method("get_current_combat_target"):
		return target.call("get_current_combat_target") as Node
	return null


func _position() -> Vector3:
	return (actor as Node3D).global_position if actor is Node3D else Vector3.ZERO


func _position_of(target: Node) -> Vector3:
	return (target as Node3D).global_position if target is Node3D else Vector3.ZERO


func _horizontal_distance_to(world_position: Vector3) -> float:
	var offset := world_position - _position()
	offset.y = 0.0
	return offset.length()


func _attack_range() -> float:
	return _call_float("get_attack_range", [], _actor_float("attack_range", 1.0))


func _close_hostile_retarget_radius() -> float:
	return _call_float("_get_effective_combat_attack_range", [], _attack_range()) + 0.65


func _combat_witness_radius() -> float:
	return maxf(_actor_float("assist_scan_radius", NpcRules.ASSIST_RANGE), _actor_float("combat_witness_radius", NpcRules.COMBAT_WITNESS_RANGE))


func _combat_switch_radius() -> float:
	return maxf(maxf(_actor_float("assist_scan_radius", NpcRules.ASSIST_RANGE), _actor_float("aggressive_scan_radius", NpcRules.AGGRO_RANGE)), _actor_float("combat_witness_radius", NpcRules.COMBAT_WITNESS_RANGE))


func _combat_stance() -> int:
	return _actor_int("combat_stance", NpcRules.CombatStance.DEFENSIVE)


func _life_state() -> int:
	return _actor_int("life_state", NpcRules.LifeState.DEAD)


func _life_state_of(target: Node) -> int:
	if target == null or not is_instance_valid(target):
		return NpcRules.LifeState.DEAD
	var value = target.get("life_state")
	return int(value) if value != null else NpcRules.LifeState.DEAD


func _actor_float(property_name: String, fallback: float) -> float:
	if actor == null or not is_instance_valid(actor):
		return fallback
	var value = actor.get(property_name)
	return float(value) if value != null else fallback


func _actor_int(property_name: String, fallback: int) -> int:
	if actor == null or not is_instance_valid(actor):
		return fallback
	var value = actor.get(property_name)
	return int(value) if value != null else fallback


func _actor_bool(property_name: String, fallback: bool) -> bool:
	if actor == null or not is_instance_valid(actor):
		return fallback
	var value = actor.get(property_name)
	return bool(value) if value != null else fallback


func _node_property(property_name: String):
	return actor.get(property_name) if actor != null and is_instance_valid(actor) else null


func _call_void(method_name: StringName, args: Array = []) -> void:
	if actor != null and is_instance_valid(actor) and actor.has_method(method_name):
		actor.callv(method_name, args)


func _call_bool(method_name: StringName, args: Array = [], fallback := false) -> bool:
	if actor != null and is_instance_valid(actor) and actor.has_method(method_name):
		return bool(actor.callv(method_name, args))
	return fallback


func _call_float(method_name: StringName, args: Array = [], fallback := 0.0) -> float:
	if actor != null and is_instance_valid(actor) and actor.has_method(method_name):
		return float(actor.callv(method_name, args))
	return fallback


func _call_int(method_name: StringName, args: Array = [], fallback := 0) -> int:
	if actor != null and is_instance_valid(actor) and actor.has_method(method_name):
		return int(actor.callv(method_name, args))
	return fallback


func _call_node(method_name: StringName, args: Array = []) -> Node:
	if actor != null and is_instance_valid(actor) and actor.has_method(method_name):
		return actor.callv(method_name, args) as Node
	return null


func _node_call_void(target: Node, method_name: StringName, args: Array = []) -> void:
	if target != null and is_instance_valid(target) and target.has_method(method_name):
		target.callv(method_name, args)


func _node_call_bool(target: Node, method_name: StringName, args: Array = [], fallback := false) -> bool:
	if target != null and is_instance_valid(target) and target.has_method(method_name):
		return bool(target.callv(method_name, args))
	return fallback


func _is_inside_tree() -> bool:
	return actor != null and actor is Node and (actor as Node).is_inside_tree()
