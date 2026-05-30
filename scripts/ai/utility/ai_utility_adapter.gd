extends RefCounted

class_name AiUtilityAdapter

const DEFAULT_PROFILE := preload("res://resources/ai/utility_profiles/default_humanoid.tres")
const AI_JOB_SCRIPT := preload("res://scripts/ai/ai_job.gd")
const AI_UTILITY_GOAL_SELECTOR_SCRIPT := preload("res://scripts/ai/utility/ai_utility_goal_selector.gd")
const AI_UTILITY_TARGET_SELECTOR_SCRIPT := preload("res://scripts/ai/utility/ai_utility_target_selector.gd")
const AI_UTILITY_CONTEXT_SCRIPT := preload("res://scripts/ai/utility/ai_utility_context.gd")
const AI_UTILITY_JOB_FACTORY_SCRIPT := preload("res://scripts/ai/utility/ai_utility_job_factory.gd")

var profile: AiUtilityProfile = DEFAULT_PROFILE
var selector := AI_UTILITY_GOAL_SELECTOR_SCRIPT.new()
var target_selector := AI_UTILITY_TARGET_SELECTOR_SCRIPT.new()
var job_factory := AI_UTILITY_JOB_FACTORY_SCRIPT.new()
# Opt-in section timing for utility AI decisions. Use with the demo benchmark as
# `--utility-profile` when chasing humanoid `_process` regressions.
static var _debug_profile_enabled := OS.get_cmdline_args().has("--utility-profile")
static var _debug_profile_calls := 0
static var _debug_profile_totals: Dictionary = {}


func setup(target_profile: AiUtilityProfile = null) -> void:
	profile = target_profile if target_profile != null else DEFAULT_PROFILE


func run_actor_decision(actor: Node) -> bool:
	var profile_last_usec := Time.get_ticks_usec() if _debug_profile_enabled else 0
	if actor == null or not is_instance_valid(actor) or profile == null:
		return false
	if _actor_life_state(actor) != NpcRules.LifeState.ALIVE:
		_clear_goal_intent(actor)
		return false
	var context := build_context(actor)
	if _debug_profile_enabled:
		profile_last_usec = _debug_profile_checkpoint("build_context", profile_last_usec)
	var decision := selector.decide(context, profile, target_selector)
	if _debug_profile_enabled:
		profile_last_usec = _debug_profile_checkpoint("selector", profile_last_usec)
	if not decision.is_valid():
		if _debug_profile_enabled:
			_debug_profile_finish()
		return false
	_sync_goal_intent(actor, context, decision)
	if _debug_profile_enabled:
		profile_last_usec = _debug_profile_checkpoint("sync_goal", profile_last_usec)
	var realized := realize_decision(actor, context, decision)
	if _debug_profile_enabled:
		_debug_profile_checkpoint("realize", profile_last_usec)
		_debug_profile_finish()
	return realized


func build_context(actor: Node) -> AiUtilityContext:
	var profile_last_usec := Time.get_ticks_usec() if _debug_profile_enabled else 0
	var context = AI_UTILITY_CONTEXT_SCRIPT.new()
	context.actor = actor
	context.entity_id = _actor_key(actor)
	context.profile_id = profile.profile_id if profile != null else "default_humanoid"
	context.position = (actor as Node3D).global_position if actor is Node3D else Vector3.ZERO
	context.sim_time = _get_sim_time(actor)
	context.lod_tier = int(actor.get_meta("ai_lod_tier", 1)) if actor.has_meta("ai_lod_tier") else 1
	if _debug_profile_enabled:
		profile_last_usec = _debug_profile_checkpoint("context.init", profile_last_usec)
	_apply_goal_state(context, actor)
	if _debug_profile_enabled:
		profile_last_usec = _debug_profile_checkpoint("context.goal_state", profile_last_usec)
	_apply_vital_facts(context, actor)
	if _debug_profile_enabled:
		profile_last_usec = _debug_profile_checkpoint("context.vitals", profile_last_usec)
	_apply_order_facts(context, actor)
	if _debug_profile_enabled:
		profile_last_usec = _debug_profile_checkpoint("context.orders", profile_last_usec)
	_apply_combat_target_context(context, actor)
	if _debug_profile_enabled:
		profile_last_usec = _debug_profile_checkpoint("context.combat", profile_last_usec)
	_apply_heal_target_context(context, actor)
	if _debug_profile_enabled:
		profile_last_usec = _debug_profile_checkpoint("context.heal", profile_last_usec)
	_apply_work_context(context, actor)
	if _debug_profile_enabled:
		profile_last_usec = _debug_profile_checkpoint("context.work", profile_last_usec)
	context.set_fact(&"idle_bias", 0.2)
	return context


static func _debug_profile_checkpoint(section_name: String, previous_usec: int) -> int:
	var now_usec := Time.get_ticks_usec()
	_debug_profile_totals[section_name] = int(_debug_profile_totals.get(section_name, 0)) + now_usec - previous_usec
	return now_usec


static func _debug_profile_finish() -> void:
	_debug_profile_calls += 1
	if _debug_profile_calls < 40:
		return
	var rows: Array = []
	for section_name in _debug_profile_totals.keys():
		rows.append([section_name, int(_debug_profile_totals[section_name])])
	rows.sort_custom(func(a, b): return int(a[1]) > int(b[1]))
	for row in rows:
		print("UTILITY_PROFILE %s usec=%d avg_per_decision=%.3f" % [str(row[0]), int(row[1]), float(row[1]) / float(_debug_profile_calls)])
	_debug_profile_enabled = false


func realize_decision(actor: Node, context: AiUtilityContext, decision: AiUtilityDecisionResult) -> bool:
	var goal_id := decision.selected_goal_id
	if goal_id == &"self_defense":
		return _realize_self_defense(actor, decision)
	if goal_id == &"heal":
		return _realize_heal(actor, decision)
	if goal_id == &"assigned_work":
		return _realize_job(actor, decision, "job_provider")
	if goal_id == context.current_goal_id:
		return false
	return _realize_job(actor, decision, str(decision.goal.source_id))


func _apply_goal_state(context: AiUtilityContext, actor: Node) -> void:
	var bridge := _get_gecs_world(actor)
	var goal_state := {}
	if bridge != null and bridge.has_method("get_actor_goal_intent"):
		goal_state = bridge.call("get_actor_goal_intent", actor, true)
	context.current_goal_id = StringName(str(goal_state.get("goal_id", "")))
	context.current_goal_started_at = float(goal_state.get("started_at", 0.0))
	context.current_goal_lock_until = float(goal_state.get("lock_until", 0.0))
	context.current_target_entity_id = str(goal_state.get("target_entity_id", ""))
	context.goal_cooldowns = (goal_state.get("goal_cooldowns", {}) as Dictionary).duplicate(true)


func _apply_vital_facts(context: AiUtilityContext, actor: Node) -> void:
	if actor is HumanoidCharacter:
		var humanoid := actor as HumanoidCharacter
		var humanoid_max_hp := maxf(humanoid.max_hp, 0.01)
		var humanoid_max_blood := maxf(humanoid.max_blood, 0.01)
		var humanoid_health_ratio := clampf(humanoid.hp / humanoid_max_hp, 0.0, 1.0)
		var humanoid_blood_ratio := clampf(humanoid.blood / humanoid_max_blood, 0.0, 1.0)
		var humanoid_damage := 1.0 - minf(humanoid_health_ratio, humanoid_blood_ratio)
		context.set_fact(&"alive", 1.0 if humanoid.life_state == NpcRules.LifeState.ALIVE else 0.0)
		context.set_fact(&"health", humanoid_health_ratio)
		context.set_fact(&"blood", humanoid_blood_ratio)
		context.set_fact(&"damage", humanoid_damage)
		context.set_fact(&"critical_damage", inverse_lerp(0.35, 0.9, humanoid_damage))
		return
	var state := _actor_state(actor)
	var hp := float(state.get("hp", _actor_float(actor, "hp", 100.0)))
	var max_hp := maxf(float(state.get("max_hp", _actor_float(actor, "max_hp", 100.0))), 0.01)
	var blood := float(state.get("blood", _actor_float(actor, "blood", 100.0)))
	var max_blood := maxf(float(state.get("max_blood", _actor_float(actor, "max_blood", 100.0))), 0.01)
	var health_ratio := clampf(hp / max_hp, 0.0, 1.0)
	var blood_ratio := clampf(blood / max_blood, 0.0, 1.0)
	var damage := 1.0 - minf(health_ratio, blood_ratio)
	context.set_fact(&"alive", 1.0 if int(state.get("life_state", _actor_life_state(actor))) == NpcRules.LifeState.ALIVE else 0.0)
	context.set_fact(&"health", health_ratio)
	context.set_fact(&"blood", blood_ratio)
	context.set_fact(&"damage", damage)
	context.set_fact(&"critical_damage", inverse_lerp(0.35, 0.9, damage))


func _apply_order_facts(context: AiUtilityContext, actor: Node) -> void:
	if actor is HumanoidCharacter:
		var humanoid := actor as HumanoidCharacter
		var humanoid_has_player_order := humanoid._order_was_player_issued and humanoid._current_order_type != 0
		context.set_fact(&"no_player_order", 0.0 if humanoid_has_player_order else 1.0)
		context.set_fact(&"player_party_member", 1.0 if humanoid.player_party_member else 0.0)
		return
	var order_was_player_issued := bool(actor.get("_order_was_player_issued")) if _has_property(actor, "_order_was_player_issued") else false
	var current_order_type := int(actor.get("_current_order_type")) if _has_property(actor, "_current_order_type") else -1
	var has_player_order := order_was_player_issued and current_order_type != 0
	var player_party := bool(actor.call("is_player_party_member")) if actor.has_method("is_player_party_member") else bool(actor.get("player_party_member")) if _has_property(actor, "player_party_member") else false
	context.set_fact(&"no_player_order", 0.0 if has_player_order else 1.0)
	context.set_fact(&"player_party_member", 1.0 if player_party else 0.0)


func _apply_combat_target_context(context: AiUtilityContext, actor: Node) -> void:
	var target = null
	if actor is HumanoidCharacter:
		var humanoid := actor as HumanoidCharacter
		target = humanoid._get_active_combat_target()
		if target == null and humanoid._should_seek_combat_target():
			target = humanoid._find_ai_target()
	else:
		target = _call_object(actor, "_get_active_combat_target")
		if target == null and _call_bool(actor, "_should_seek_combat_target"):
			target = _call_object(actor, "_find_ai_target")
	if target == null:
		context.set_fact(&"threat", 0.0)
		context.set_fact(&"can_self_defend", 0.0)
		return
	var score := _distance_score(context.position, target)
	context.set_fact(&"threat", 1.0)
	context.set_fact(&"can_self_defend", 1.0)
	context.set_targets(&"combat_target", [_target_candidate(target, score, "combat target")])


func _apply_heal_target_context(context: AiUtilityContext, actor: Node) -> void:
	var target = null
	if actor is HumanoidCharacter:
		var humanoid := actor as HumanoidCharacter
		if humanoid._should_seek_auto_heal_target():
			target = humanoid._find_auto_heal_target()
	elif _call_bool(actor, "_should_seek_auto_heal_target"):
		target = _call_object(actor, "_find_auto_heal_target")
	if target == null:
		context.set_fact(&"heal_need", 0.0)
		return
	var score := _heal_target_score(actor, target)
	context.set_fact(&"heal_need", score)
	context.set_targets(&"heal_target", [_target_candidate(target, score, "heal target")])


func _apply_work_context(context: AiUtilityContext, actor: Node) -> void:
	var provider = actor.call("get_active_job_provider") if actor.has_method("get_active_job_provider") else null
	var candidates: Array = []
	var has_contracts := false
	var bridge := _get_gecs_world(actor)
	if bridge != null and bridge.has_method("get_actor_job_contracts"):
		for contract in bridge.call("get_actor_job_contracts", actor):
			if not (contract is Dictionary):
				continue
			var contract_data: Dictionary = contract
			if str(contract_data.get("status", "active")) != "active":
				continue
			has_contracts = true
			var metadata: Dictionary = contract_data.get("metadata", {}) if contract_data.get("metadata", {}) is Dictionary else {}
			var player_party_contract := bool(metadata.get("player_party_member", false))
			var next_shift := float(contract_data.get("next_shift_time", 0.0))
			if next_shift > context.sim_time and not player_party_contract:
				continue
			var contract_provider := _resolve_contract_provider(actor, contract_data)
			if contract_provider == null:
				continue
			var work_status := _contract_work_status(actor, contract_provider, contract_data)
			if not bool(work_status.get("actionable", true)):
				continue
			var priority_score := clampf(1.0 - float(contract_data.get("priority_order", 0)) * 0.12, 0.25, 1.0)
			var candidate := _target_candidate(contract_provider, priority_score, str(work_status.get("reason", "job contract")))
			candidate["contract"] = contract_data.duplicate(true)
			candidate["work_status"] = work_status.duplicate(true)
			candidates.append(candidate)
	if candidates.is_empty() and not has_contracts and provider != null and is_instance_valid(provider):
		candidates.append(_target_candidate(provider, 1.0, "active work shift"))
	if candidates.is_empty():
		context.set_fact(&"assigned_work_available", 0.0)
		return
	context.set_fact(&"assigned_work_available", 1.0)
	context.set_targets(&"work_provider", candidates)


func _realize_self_defense(actor: Node, decision: AiUtilityDecisionResult) -> bool:
	if decision.target == null or not is_instance_valid(decision.target):
		return false
	var active_target = _call_object(actor, "_get_active_combat_target")
	if active_target == decision.target:
		return false
	if actor.has_method("assign_attack_target"):
		var result = actor.call("assign_attack_target", decision.target, false, true, false)
		return not (result is bool and result == false)
	return _realize_job(actor, decision, str(decision.goal.source_id))


func _realize_heal(actor: Node, decision: AiUtilityDecisionResult) -> bool:
	if decision.target == null or not is_instance_valid(decision.target):
		return false
	if _has_property(actor, "_current_heal_target") and actor.get("_current_heal_target") == decision.target:
		return false
	if actor.has_method("assign_heal_target"):
		actor.call("assign_heal_target", decision.target, false)
		return true
	return false


func _realize_job(actor: Node, decision: AiUtilityDecisionResult, active_source_id := "") -> bool:
	var contract: Dictionary = decision.target_data.get("contract", {}) if decision.target_data.get("contract", {}) is Dictionary else {}
	var selected_contract_id := str(contract.get("contract_id", ""))
	if not active_source_id.is_empty() and actor.has_method("has_active_ai_job_from_source") and bool(actor.call("has_active_ai_job_from_source", active_source_id)):
		if selected_contract_id.is_empty() or _active_job_matches_contract(actor, selected_contract_id):
			return false
		_pause_active_work_shift(actor)
		if actor.has_method("cancel_ai_job"):
			actor.call("cancel_ai_job", active_source_id)
	if not actor.has_method("request_ai_job"):
		return false
	var job = job_factory.create_job(decision, actor)
	if job == null:
		return false
	return bool(actor.call("request_ai_job", job))


func _contract_work_status(actor: Node, provider: Node, contract: Dictionary) -> Dictionary:
	if provider != null and provider.has_method("get_contract_work_status"):
		return provider.call("get_contract_work_status", actor, contract)
	return {"actionable": true, "reason": "job contract"}


func _active_job_matches_contract(actor: Node, contract_id: String) -> bool:
	if actor == null or contract_id.is_empty() or not actor.has_method("get_ai_debug_snapshot"):
		return false
	var snapshot: Dictionary = actor.call("get_ai_debug_snapshot")
	var active_job: Dictionary = snapshot.get("active_job", {}) if snapshot.get("active_job", {}) is Dictionary else {}
	var active_job_id := str(active_job.get("job_id", snapshot.get("job_id", "")))
	return active_job_id == contract_id


func _pause_active_work_shift(actor: Node) -> void:
	if actor == null or not actor.has_method("get_active_job_provider"):
		return
	var provider = actor.call("get_active_job_provider")
	if provider != null and is_instance_valid(provider) and provider.has_method("pause_worker_job"):
		provider.call("pause_worker_job", actor, false)


func _sync_goal_intent(actor: Node, context: AiUtilityContext, decision: AiUtilityDecisionResult) -> void:
	var bridge := _get_gecs_world(actor)
	if bridge == null or not bridge.has_method("set_actor_goal_intent"):
		return
	var goal := decision.goal
	bridge.call("set_actor_goal_intent", actor, {
		"profile_id": context.profile_id,
		"selected_goal_id": str(decision.selected_goal_id),
		"selected_score": decision.selected_score,
		"selected_at": context.sim_time,
		"target_entity_id": decision.target_entity_id,
		"target_position": decision.target_position,
		"has_target_position": decision.has_target_position,
		"executor_key": str(decision.executor_key),
		"source_id": goal.source_id,
		"lock_seconds": goal.lock_seconds,
		"cooldown_seconds": goal.cooldown_seconds,
		"runtime_summary": decision.get_runtime_summary(),
		"debug_breakdown": decision.to_dictionary(true),
	})


func _clear_goal_intent(actor: Node) -> void:
	var bridge := _get_gecs_world(actor)
	if bridge != null and bridge.has_method("clear_actor_goal_intent"):
		bridge.call("clear_actor_goal_intent", actor)


func _actor_state(actor: Node) -> Dictionary:
	var bridge := _get_gecs_world(actor)
	var actor_id := _actor_key(actor)
	if bridge != null and not actor_id.is_empty() and bridge.has_method("get_actor_state"):
		return bridge.call("get_actor_state", actor_id)
	return {}


func _actor_key(actor: Node) -> String:
	if actor == null:
		return ""
	var stable_id = actor.get("stable_id")
	if stable_id != null and not str(stable_id).strip_edges().is_empty():
		return str(stable_id).strip_edges()
	if actor.has_meta("actor_record_id"):
		return str(actor.get_meta("actor_record_id"))
	return str(actor.get_instance_id())


func _actor_life_state(actor: Node) -> int:
	return int(actor.get("life_state")) if _has_property(actor, "life_state") else NpcRules.LifeState.ALIVE


func _actor_float(actor: Node, property_name: String, default_value: float) -> float:
	return float(actor.get(property_name)) if _has_property(actor, property_name) else default_value


func _get_sim_time(actor: Node) -> float:
	var sim_time := -1.0
	var scheduler := _get_controller(actor, "ai_scheduler_controller")
	if scheduler != null:
		if scheduler.has_method("get_sim_time"):
			return float(scheduler.call("get_sim_time"))
		if _has_property(scheduler, "_sim_time"):
			return float(scheduler.get("_sim_time"))
	var job_system := _get_controller(actor, "job_system_controller")
	if job_system != null:
		if job_system.has_method("get_sim_time"):
			sim_time = maxf(sim_time, float(job_system.call("get_sim_time")))
		elif _has_property(job_system, "_sim_time"):
			sim_time = maxf(sim_time, float(job_system.get("_sim_time")))
	var bridge := _get_gecs_world(actor)
	if bridge != null and bridge.has_method("get_job_system_state"):
		var job_state: Dictionary = bridge.call("get_job_system_state")
		if not job_state.is_empty():
			sim_time = maxf(sim_time, float(job_state.get("sim_time", 0.0)))
	return sim_time if sim_time >= 0.0 else float(Time.get_ticks_msec()) / 1000.0


func _get_gecs_world(actor: Node) -> Node:
	return _get_controller(actor, "gecs_world_controller")


func _get_controller(actor: Node, group_name: String) -> Node:
	if actor == null or not actor.is_inside_tree():
		return null
	if actor.has_method("_get_runtime_controller"):
		var cached_controller := actor.call("_get_runtime_controller", group_name) as Node
		if cached_controller != null:
			return cached_controller
	var current := actor
	while current != null:
		for child in current.get_children():
			if child is Node and (child as Node).is_in_group(group_name):
				return child as Node
		current = current.get_parent()
	var tree := actor.get_tree()
	return tree.get_first_node_in_group(group_name) if tree != null else null


func _call_bool(actor: Node, method_name: String) -> bool:
	return bool(actor.call(method_name)) if actor != null and actor.has_method(method_name) else false


func _call_object(actor: Node, method_name: String):
	return actor.call(method_name) if actor != null and actor.has_method(method_name) else null


func _resolve_contract_provider(actor: Node, contract: Dictionary) -> Node:
	if actor == null or not actor.is_inside_tree():
		return null
	var provider_paths: Array[NodePath] = []
	var provider_path: NodePath = contract.get("provider_path", NodePath())
	if provider_path != NodePath():
		provider_paths.append(provider_path)
	var provider_id := str(contract.get("provider_id", ""))
	if not provider_id.is_empty():
		provider_paths.append(NodePath(provider_id))
	for path in provider_paths:
		var provider := actor.get_node_or_null(path)
		if provider != null:
			return provider
		provider = actor.get_tree().root.get_node_or_null(path)
		if provider != null:
			return provider
	for provider in actor.get_tree().get_nodes_in_group("job_provider"):
		if provider is Node and str((provider as Node).get_path()) == provider_id:
			return provider as Node
	return null


func _target_candidate(target, score: float, reason: String) -> Dictionary:
	return {
		"target": target,
		"entity_id": _target_key(target),
		"position": (target as Node3D).global_position if target is Node3D else Vector3.ZERO,
		"score": clampf(score, 0.0, 1.0),
		"reason": reason,
	}


func _target_key(target) -> String:
	if target is Node:
		var stable_id = target.get("stable_id")
		if stable_id != null and not str(stable_id).strip_edges().is_empty():
			return str(stable_id).strip_edges()
		if target.has_meta("actor_record_id"):
			return str(target.get_meta("actor_record_id"))
		if target.has_method("get_activity_id"):
			return str(target.call("get_activity_id"))
		if target.is_inside_tree():
			return str(target.get_path())
		return str(target.get_instance_id())
	return str(target)


func _distance_score(origin: Vector3, target) -> float:
	if not (target is Node3D):
		return 1.0
	var distance := origin.distance_to((target as Node3D).global_position)
	return clampf(1.0 - distance / 48.0, 0.1, 1.0)


func _heal_target_score(_actor: Node, target) -> float:
	if target == null:
		return 0.0
	if target.has_method("get_total_wound_damage"):
		var wounds := float(target.call("get_total_wound_damage"))
		var bleeding := float(target.call("get_bleed_rate")) if target.has_method("get_bleed_rate") else 0.0
		return clampf((wounds + bleeding * 75.0) / 100.0, 0.05, 1.0)
	if target is Node:
		var hp := float(target.get("hp")) if _has_property(target, "hp") else 100.0
		var max_hp := maxf(float(target.get("max_hp")) if _has_property(target, "max_hp") else 100.0, 0.01)
		return clampf(1.0 - hp / max_hp, 0.05, 1.0)
	return 0.0


func _has_property(object: Object, property_name: String) -> bool:
	if object == null:
		return false
	for property in object.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false
