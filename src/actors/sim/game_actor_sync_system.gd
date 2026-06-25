extends "res://addons/gecs/ecs/system.gd"

class_name GameActorSyncSystem

const C_NODE = preload("res://src/actors/bridge/c_game_actor_node.gd")
const C_IDENTITY = preload("res://src/actors/sim/c_game_actor_identity.gd")
const C_FACTION = preload("res://src/actors/sim/c_game_actor_faction.gd")
const C_SETTLEMENT = preload("res://src/actors/sim/c_game_actor_settlement.gd")
const C_SPATIAL = preload("res://src/actors/sim/c_game_actor_spatial.gd")
const C_VITALS = preload("res://src/actors/sim/c_game_actor_vitals.gd")


func query() -> QueryBuilder:
	return q.with_all([C_NODE, C_IDENTITY, C_FACTION, C_SETTLEMENT, C_SPATIAL, C_VITALS]).iterate([C_NODE, C_IDENTITY, C_FACTION, C_SETTLEMENT, C_SPATIAL, C_VITALS])


func process(entities: Array, components: Array, _delta: float) -> void:
	var nodes: Array = components[0]
	var identities: Array = components[1]
	var factions: Array = components[2]
	var settlements: Array = components[3]
	var spatials: Array = components[4]
	var vitals: Array = components[5]
	for index in range(entities.size()):
		var actor_component = nodes[index]
		var actor := _resolve_actor(actor_component)
		if actor == null:
			entities[index].enabled = false
			continue
		_sync_identity(identities[index], actor)
		_sync_faction(factions[index], actor)
		_sync_settlement(settlements[index], actor)
		_sync_spatial(spatials[index], actor)
		_sync_vitals(vitals[index], actor)


func _resolve_actor(actor_component) -> Node:
	if actor_component == null:
		return null
	var actor = actor_component.get_actor() if actor_component.has_method("get_actor") else actor_component.actor
	if actor != null and is_instance_valid(actor):
		return actor as Node
	if actor_component.actor_path != NodePath():
		actor = get_node_or_null(actor_component.actor_path)
		if actor != null:
			actor_component.actor = actor
			actor_component.instance_id = actor.get_instance_id()
			return actor as Node
	return null


func _sync_identity(component, actor: Node) -> void:
	if component == null:
		return
	var stable_id = actor.get("stable_id")
	if stable_id != null and not str(stable_id).strip_edges().is_empty():
		component.stable_id = str(stable_id).strip_edges()
		component.actor_id = component.stable_id
	elif actor.has_meta("actor_record_id"):
		component.actor_id = str(actor.get_meta("actor_record_id")).strip_edges()
	var member_name = actor.get("member_name")
	if member_name != null:
		component.member_name = str(member_name)
	if actor.has_meta("actor_role_id"):
		component.role_id = str(actor.get_meta("actor_role_id"))
	elif actor.has_meta("settlement_staff_role"):
		component.role_id = str(actor.get_meta("settlement_staff_role"))


func _sync_faction(component, actor: Node) -> void:
	if component == null:
		return
	var faction = actor.get("faction_name")
	if faction != null:
		component.faction_id = str(faction).strip_edges()
	var squad = actor.get("squad_name")
	if squad != null:
		component.squad_name = str(squad)
	var hostile = actor.get("hostile_factions")
	if hostile is PackedStringArray:
		component.hostile_faction_ids = hostile
	elif hostile is Array:
		component.hostile_faction_ids = PackedStringArray(hostile)
	var stance = actor.get("combat_stance")
	if stance != null:
		component.combat_stance = int(stance)
	var party = actor.get("player_party_member")
	if party != null:
		component.player_party_member = bool(party)


func _sync_settlement(component, actor: Node) -> void:
	if component == null:
		return
	if actor.has_meta("settlement_id"):
		component.settlement_id = str(actor.get_meta("settlement_id"))
	if actor.has_meta("actor_record_id"):
		component.realization_state = "realized"
		component.live_node_path = actor.get_path() if actor.is_inside_tree() else NodePath()


func _sync_spatial(component, actor: Node) -> void:
	if component == null or not (actor is Node3D):
		return
	component.last_world_position = component.world_position
	component.world_position = (actor as Node3D).global_position
	component.position_initialized = true


func _sync_vitals(component, actor: Node) -> void:
	if component == null:
		return
	var life_state = actor.get("life_state")
	if life_state != null:
		component.life_state = int(life_state)
	var hp = actor.get("hp")
	if hp != null:
		component.hp = float(hp)
	var max_hp = actor.get("max_hp")
	if max_hp != null:
		component.max_hp = float(max_hp)
	var blood = actor.get("blood")
	if blood != null:
		component.blood = float(blood)
	var max_blood = actor.get("max_blood")
	if max_blood != null:
		component.max_blood = float(max_blood)
