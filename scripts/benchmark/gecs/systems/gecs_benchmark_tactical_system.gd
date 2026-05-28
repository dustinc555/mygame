extends "res://addons/gecs/ecs/system.gd"

class_name GecsBenchmarkTacticalSystem

const C_TRANSFORM = preload("res://scripts/benchmark/gecs/components/c_benchmark_transform.gd")
const C_AGENT = preload("res://scripts/benchmark/gecs/components/c_benchmark_agent.gd")
const C_VITALS = preload("res://scripts/benchmark/gecs/components/c_benchmark_vitals.gd")

@export var retarget_interval := 0.35
@export var engagement_damage := 3.0
@export var hp_reset_floor := 15.0

var total_engagements := 0
var total_target_updates := 0


func query() -> QueryBuilder:
	return q.with_all([C_TRANSFORM, C_AGENT, C_VITALS]).iterate([C_TRANSFORM, C_AGENT, C_VITALS])


func process(entities: Array, components: Array, delta: float) -> void:
	if entities.is_empty():
		return
	var transforms: Array = components[0]
	var agents: Array = components[1]
	var vitals: Array = components[2]
	var alive_by_team := _collect_alive_by_team(agents, vitals)
	var index_by_entity := {}
	for index in range(entities.size()):
		index_by_entity[entities[index]] = index
	for index in range(entities.size()):
		var agent := agents[index] as CBenchmarkAgent
		var vital := vitals[index] as CBenchmarkVitals
		if agent == null or vital == null or vital.hp <= 0.0:
			continue
		agent.cooldown_remaining = maxf(0.0, agent.cooldown_remaining - delta)
		agent.retarget_remaining -= delta
		var target_index := _current_target_index(agent, index_by_entity, vitals)
		if target_index < 0 or agent.retarget_remaining <= 0.0:
			target_index = _nearest_hostile_index(index, transforms, agents, alive_by_team)
			if target_index >= 0:
				agent.target_entity = entities[target_index]
				agent.retarget_remaining = retarget_interval + (float(index % 11) * 0.01)
				total_target_updates += 1
			else:
				agent.target_entity = null
				agent.retarget_remaining = retarget_interval
		if target_index >= 0:
			_update_engagement(index, target_index, transforms, agents, vitals)
		else:
			var transform := transforms[index] as CBenchmarkTransform
			if transform != null:
				agent.target_position = transform.position
	_apply_damage(vitals)


func _collect_alive_by_team(agents: Array, vitals: Array) -> Dictionary:
	var alive_by_team := {}
	for index in range(agents.size()):
		var agent := agents[index] as CBenchmarkAgent
		var vital := vitals[index] as CBenchmarkVitals
		if agent == null or vital == null or vital.hp <= 0.0:
			continue
		if not alive_by_team.has(agent.team):
			alive_by_team[agent.team] = []
		alive_by_team[agent.team].append(index)
	return alive_by_team


func _current_target_index(agent: CBenchmarkAgent, index_by_entity: Dictionary, vitals: Array) -> int:
	if agent.target_entity == null or not is_instance_valid(agent.target_entity):
		return -1
	if not index_by_entity.has(agent.target_entity):
		return -1
	var target_index: int = int(index_by_entity[agent.target_entity])
	var target_vital := vitals[target_index] as CBenchmarkVitals
	if target_vital == null or target_vital.hp <= 0.0:
		return -1
	return target_index


func _nearest_hostile_index(index: int, transforms: Array, agents: Array, alive_by_team: Dictionary) -> int:
	var agent := agents[index] as CBenchmarkAgent
	var transform := transforms[index] as CBenchmarkTransform
	if agent == null or transform == null:
		return -1
	var best_index := -1
	var best_distance_sq := INF
	for team_value in alive_by_team.keys():
		if int(team_value) == agent.team:
			continue
		for candidate_index in alive_by_team[team_value]:
			var candidate_transform := transforms[candidate_index] as CBenchmarkTransform
			if candidate_transform == null:
				continue
			var distance_sq := transform.position.distance_squared_to(candidate_transform.position)
			if distance_sq < best_distance_sq:
				best_distance_sq = distance_sq
				best_index = candidate_index
	return best_index


func _update_engagement(index: int, target_index: int, transforms: Array, agents: Array, vitals: Array) -> void:
	var transform := transforms[index] as CBenchmarkTransform
	var agent := agents[index] as CBenchmarkAgent
	var target_transform := transforms[target_index] as CBenchmarkTransform
	var target_vital := vitals[target_index] as CBenchmarkVitals
	if transform == null or agent == null or target_transform == null or target_vital == null:
		return
	var to_target := target_transform.position - transform.position
	to_target.y = 0.0
	var distance := to_target.length()
	if distance > agent.attack_range:
		var direction := to_target.normalized() if distance > 0.001 else Vector3.FORWARD
		agent.target_position = target_transform.position - (direction * agent.attack_range * 0.85)
		agent.target_position.y = transform.position.y
		return
	agent.target_position = transform.position
	if agent.cooldown_remaining > 0.0:
		return
	target_vital.pending_damage += engagement_damage
	agent.cooldown_remaining = agent.attack_cooldown_seconds
	agent.engagement_count += 1
	total_engagements += 1


func _apply_damage(vitals: Array) -> void:
	for vital_value in vitals:
		var vital := vital_value as CBenchmarkVitals
		if vital == null or vital.pending_damage <= 0.0:
			continue
		vital.hp = maxf(0.0, vital.hp - vital.pending_damage)
		vital.damage_taken += vital.pending_damage
		vital.pending_damage = 0.0
		if vital.hp <= hp_reset_floor:
			vital.hp = vital.max_hp
