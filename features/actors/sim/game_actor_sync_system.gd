extends "res://addons/gecs/ecs/system.gd"

class_name GameActorSyncSystem

## Dynamic state bridge. Identity/faction/settlement copies are event-driven;
## movement and medical synchronization remain independent of that profile.
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

var _profile_bindings: Dictionary = {}


func bind_actor(entity: Entity, actor: WorldActor, restore_saved_profile := false) -> void:
	unbind_actor(actor)
	if restore_saved_profile:
		_restore_profile(entity, actor)
	var callback := _sync_profile.bind(weakref(entity), weakref(actor))
	_profile_bindings[actor.get_instance_id()] = callback
	actor.simulation_profile_changed.connect(callback)
	actor.tree_exiting.connect(unbind_actor.bind(actor), CONNECT_ONE_SHOT)
	if not restore_saved_profile:
		callback.call()


func unbind_actor(actor: WorldActor) -> void:
	var id := actor.get_instance_id()
	if not _profile_bindings.has(id):
		return
	var callback: Callable = _profile_bindings[id]
	if actor.simulation_profile_changed.is_connected(callback):
		actor.simulation_profile_changed.disconnect(callback)
	var on_exit := unbind_actor.bind(actor)
	if actor.tree_exiting.is_connected(on_exit):
		actor.tree_exiting.disconnect(on_exit)
	_profile_bindings.erase(id)


func _restore_profile(entity: Entity, actor: WorldActor) -> void:
	# Restore while disconnected: the old body's fields cannot overwrite the
	# loaded components, including when a later edit changes only one field.
	var identity: CGameActorIdentity = entity.get_component(C_IDENTITY)
	var faction: CGameActorFaction = entity.get_component(C_FACTION)
	var settlement: CGameActorSettlement = entity.get_component(C_SETTLEMENT)
	actor.stable_id = identity.stable_id
	actor.member_name = identity.member_name
	actor.set_settlement_authority(identity.authority_scopes.has("settlement_authority"))
	WorldActor.set_profile_metadata(actor, &"actor_record_id", identity.actor_id)
	WorldActor.set_profile_metadata(actor, &"actor_role_id", identity.role_id)
	WorldActor.set_profile_metadata(actor, &"settlement_id", settlement.settlement_id)
	WorldActor.set_profile_metadata(actor, &"party_id", faction.party_id if not faction.party_id.is_empty() else null)
	actor.faction_name = faction.faction_id
	actor.squad_name = faction.squad_name
	actor.hostile_factions = faction.hostile_faction_ids
	actor.combat_stance = faction.combat_stance
	actor.player_party_member = faction.player_party_member


func _sync_profile(entity_ref: WeakRef, actor_ref: WeakRef) -> void:
	var entity := entity_ref.get_ref() as Entity
	var actor := actor_ref.get_ref() as WorldActor
	if entity == null or actor == null or actor.is_queued_for_deletion():
		return
	_sync_identity(entity.get_component(C_IDENTITY), actor)
	_sync_faction(entity.get_component(C_FACTION), actor)
	_sync_settlement(entity.get_component(C_SETTLEMENT), actor)


func query() -> QueryBuilder:
	return q.with_all([C_NODE, C_SPATIAL, C_VITALS, C_VITALS_INPUTS]).iterate([C_NODE, C_SPATIAL, C_VITALS, C_VITALS_INPUTS])


func process(entities: Array, components: Array, _delta: float) -> void:
	var nodes: Array = components[0]
	var spatials: Array = components[1]
	var vitals: Array = components[2]
	var vitals_inputs: Array = components[3]
	for index in range(entities.size()):
		var actor := _resolve_actor(nodes[index] as CGameActorNode)
		if actor == null:
			entities[index].enabled = false
			continue
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
	if actor.is_in_group("settlement_authority") and not component.authority_scopes.has("settlement_authority"):
		component.authority_scopes.append("settlement_authority")


func _sync_faction(component: CGameActorFaction, actor: WorldActor) -> void:
	if component == null:
		return
	component.faction_id = actor.faction_name.strip_edges()
	component.party_id = str(actor.get_meta("party_id", "")).strip_edges()
	component.squad_name = actor.squad_name
	component.hostile_faction_ids = actor.hostile_factions
	component.combat_stance = actor.combat_stance
	component.player_party_member = actor.player_party_member
	component.player_order_active = actor.has_active_player_order()


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
	if not is_robot:
		vitals.bind_authoritative_state(component)
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
	var revision := stats.get_vitals_inputs_revision()
	var source_id := stats.get_instance_id()
	if not component.dirty and component.stats_source_instance_id == source_id and component.stats_inputs_revision == revision:
		return
	component.toughness = stats.get_stat_value("toughness")
	component.healing_rate = stats.get_stat_value("healing_rate")
	component.stats_source_instance_id = source_id
	component.stats_inputs_revision = revision
	component.dirty = false
