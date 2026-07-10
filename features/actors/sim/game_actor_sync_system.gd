extends "res://addons/gecs/ecs/system.gd"

class_name GameActorSyncSystem

## Mirrors live WorldActor node state into GECS components each tick.
##
## Reads are TYPED off WorldActor (Phase 3 — no more actor.get("...") duck-typing).
## `get_meta`/`has_meta` remain: node metadata is a legitimate Godot API, not the
## forbidden method/property reflection.

const C_NODE = preload("res://features/actors/bridge/c_game_actor_node.gd")
const C_IDENTITY = preload("res://features/actors/sim/c_game_actor_identity.gd")
const C_FACTION = preload("res://features/actors/sim/c_game_actor_faction.gd")
const C_SETTLEMENT = preload("res://features/actors/sim/c_game_actor_settlement.gd")
const C_SPATIAL = preload("res://features/actors/sim/c_game_actor_spatial.gd")
const C_VITALS = preload("res://features/actors/sim/c_game_actor_vitals.gd")
const C_VITALS_INPUTS = preload("res://features/actors/sim/c_game_actor_vitals_inputs.gd")


func query() -> QueryBuilder:
	return q.with_all([C_NODE, C_IDENTITY, C_FACTION, C_SETTLEMENT, C_SPATIAL, C_VITALS, C_VITALS_INPUTS]).iterate([C_NODE, C_IDENTITY, C_FACTION, C_SETTLEMENT, C_SPATIAL, C_VITALS, C_VITALS_INPUTS])


func process(entities: Array, components: Array, _delta: float) -> void:
	var nodes: Array = components[0]
	var identities: Array = components[1]
	var factions: Array = components[2]
	var settlements: Array = components[3]
	var spatials: Array = components[4]
	var vitals: Array = components[5]
	var vitals_inputs: Array = components[6]
	for index in range(entities.size()):
		var actor := _resolve_actor(nodes[index] as CGameActorNode)
		if actor == null:
			entities[index].enabled = false
			continue
		_sync_identity(identities[index] as CGameActorIdentity, actor)
		_sync_faction(factions[index] as CGameActorFaction, actor)
		_sync_settlement(settlements[index] as CGameActorSettlement, actor)
		_sync_spatial(spatials[index] as CGameActorSpatial, actor)
		_sync_vitals(vitals[index] as CGameActorVitals, actor)
		_sync_vitals_inputs(vitals_inputs[index] as CGameActorVitalsInputs, actor)


func _resolve_actor(actor_component: CGameActorNode) -> WorldActor:
	if actor_component == null:
		return null
	var actor := actor_component.get_actor()
	if actor != null and is_instance_valid(actor):
		return actor as WorldActor
	if actor_component.actor_path != NodePath():
		actor = get_node_or_null(actor_component.actor_path)
		if actor != null:
			actor_component.actor = actor
			actor_component.instance_id = actor.get_instance_id()
			return actor as WorldActor
	return null


func _sync_identity(component: CGameActorIdentity, actor: WorldActor) -> void:
	if component == null:
		return
	var stable_id := actor.stable_id.strip_edges()
	if not stable_id.is_empty():
		component.stable_id = stable_id
		component.actor_id = stable_id
	elif actor.has_meta("actor_record_id"):
		component.actor_id = str(actor.get_meta("actor_record_id")).strip_edges()
	component.member_name = actor.member_name
	if actor.has_meta("actor_role_id"):
		component.role_id = str(actor.get_meta("actor_role_id"))
	elif actor.has_meta("settlement_staff_role"):
		component.role_id = str(actor.get_meta("settlement_staff_role"))


func _sync_faction(component: CGameActorFaction, actor: WorldActor) -> void:
	if component == null:
		return
	component.faction_id = actor.faction_name.strip_edges()
	component.squad_name = actor.squad_name
	component.hostile_faction_ids = actor.hostile_factions
	component.combat_stance = actor.combat_stance
	component.player_party_member = actor.player_party_member


func _sync_settlement(component: CGameActorSettlement, actor: WorldActor) -> void:
	if component == null:
		return
	if actor.has_meta("settlement_id"):
		component.settlement_id = str(actor.get_meta("settlement_id"))
	if actor.has_meta("actor_record_id"):
		component.realization_state = "realized"
		component.live_node_path = actor.get_path() if actor.is_inside_tree() else NodePath()


func _sync_spatial(component: CGameActorSpatial, actor: WorldActor) -> void:
	if component == null:
		return
	component.last_world_position = component.world_position
	component.world_position = actor.global_position
	component.position_initialized = true


func _sync_vitals(component: CGameActorVitals, actor: WorldActor) -> void:
	# S4 FLIP: for realized HUMANOIDS the GECS component is now the vitals truth (GameVitalsSystem owns
	# it). This sync therefore runs in TWO directions: node-authored max/profile fields always flow
	# node->component; the simulated fields flow node->component once (the seed) and component->node
	# thereafter. Robots/quadbots keep node authority (S5) so they stay a pure node->component mirror.
	if component == null:
		return
	var vitals := actor.get_vitals()
	if vitals == null:
		return
	# death_profile is the single source for "who owns this actor's vitals". We branch on the actor's
	# typed virtual get_death_profile() (data), NOT `actor is RobotActor` (a GECS-system->live-node-class
	# reference = truth-rule violation). Unblocked once quadbot was de-staled — see cleanup.md S5.
	component.death_profile = actor.get_death_profile() as CGameActorVitals.DeathProfile
	var is_robot := component.death_profile == CGameActorVitals.DeathProfile.ROBOT
	# Node authors max/base + the recovery modifier (refresh_max_blood_from_toughness lives node-side);
	# the system reads these as thresholds, so they always flow node->component.
	component.max_hp = actor.max_hp
	component.max_blood = actor.max_blood
	component.base_max_blood = vitals.base_max_blood
	component.recovery_multiplier = vitals.recovery_multiplier
	if is_robot or not component.vitals_seeded:
		# ROBOT (node-owned), OR the one-time seed of a system-owned humanoid: mirror node->component.
		# The seed transfers a pre-wounded / non-default / loaded actor's REAL state into the freshly
		# created (defaults) component before the reverse branch below takes over.
		component.life_state = actor.life_state
		component.hp = actor.hp
		component.blood = actor.blood
		component.blunt_damage = vitals.blunt_damage
		component.open_cut_damage = vitals.open_cut_damage
		component.bandaged_cut_damage = vitals.bandaged_cut_damage
		component.bleed_rate = vitals.bleed_rate
		component.bleed_burst_rate = vitals.bleed_burst_rate
		component.dying_timer_remaining = vitals.dying_timer_remaining
		if not is_robot:
			component.vitals_seeded = true
		return
	# HUMANOID, seeded: component is the truth -> reflect onto the capability's RAW fields (NOT the
	# WorldActor.* properties, whose setters would re-run recalculate_vitals node-side). Copying every
	# field keeps any stray node-side recalc deriving the same life_state, so the node cannot diverge.
	vitals.hp = component.hp
	vitals.blood = component.blood
	vitals.blunt_damage = component.blunt_damage
	vitals.open_cut_damage = component.open_cut_damage
	vitals.bandaged_cut_damage = component.bandaged_cut_damage
	vitals.bleed_rate = component.bleed_rate
	vitals.bleed_burst_rate = component.bleed_burst_rate
	vitals.dying_timer_remaining = component.dying_timer_remaining
	# Drive the transition through the capability so it emits state_changed/died exactly once (the one
	# real consumer is the command-bar refresh; death is also polled off life_state).
	vitals._set_life_state(component.life_state)


func _sync_vitals_inputs(component: CGameActorVitalsInputs, actor: WorldActor) -> void:
	if component == null:
		return
	# Node authors the vitals inputs (the one legitimate node->component direction). These are cached
	# here so GameVitalsSystem (S3+) can keep simulating after derealization without a live node.
	component.held_externally = actor.is_carried()
	var stats := actor.get_stats()
	if stats == null:
		return
	component.toughness = stats.get_stat_value("toughness")
	component.healing_rate = stats.get_stat_value("healing_rate")
	component.dirty = false
