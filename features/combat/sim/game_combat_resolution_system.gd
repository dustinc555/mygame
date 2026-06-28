extends "res://addons/gecs/ecs/system.gd"

class_name GameCombatResolutionSystem

const C_NODE = preload("res://features/actors/bridge/c_game_actor_node.gd")
const C_IDENTITY = preload("res://features/actors/sim/c_game_actor_identity.gd")
const C_SPATIAL = preload("res://features/actors/sim/c_game_actor_spatial.gd")
const C_VITALS = preload("res://features/actors/sim/c_game_actor_vitals.gd")
const C_CONFIG = preload("res://features/combat/sim/c_game_combat_config.gd")
const C_ACTION = preload("res://features/combat/sim/c_game_combat_action.gd")
const C_SLOT = preload("res://features/combat/sim/c_game_combat_slot_state.gd")

const COMBAT_RANGE_HYSTERESIS := 0.18
const FIXED_COMBAT_TICK_SECONDS := 1.0 / 20.0
# Max sim stagger from an incoming hit/block. Presentation clips may run longer.
const MAX_REACTION_HOLD_SECONDS := 0.45
const MAX_FIXED_STEPS_PER_FRAME := 5
const FIGHT_STATE_FIGHTING := 3
# Ceremony pause between exchange turns in a pair. THE combat pacing knob: veterans
# should trade deliberate, readable blows over minutes, not flail (was 0.28, which
# made 20v20 fights resolve in ~10 seconds).
const TURN_HANDOFF_WAIT_SECONDS := 1.4

static var profile_enabled := OS.get_cmdline_args().has("--gecs-combat-profile")
static var _profile_calls := 0
static var _profile_usec := 0
var _fixed_accumulator := 0.0


func query() -> QueryBuilder:
	return q.with_all([C_NODE, C_IDENTITY, C_SPATIAL, C_VITALS, C_CONFIG, C_ACTION, C_SLOT]).iterate(
		[C_NODE, C_IDENTITY, C_SPATIAL, C_VITALS, C_CONFIG, C_ACTION, C_SLOT])


func process(_entities: Array, components: Array, delta: float) -> void:
	var profile_start := Time.get_ticks_usec() if profile_enabled else 0
	var nodes: Array = components[0]
	var identities: Array = components[1]
	var spatials: Array = components[2]
	var vitals: Array = components[3]
	var configs: Array = components[4]
	var actions: Array = components[5]
	var slots: Array = components[6]
	var count := nodes.size()
	if count == 0:
		return
	var actor_index_by_id := {}
	var process_frame := Engine.get_process_frames()
	for i in range(count):
		var identity = identities[i]
		if identity != null and not str(identity.actor_id).is_empty():
			actor_index_by_id[str(identity.actor_id)] = i
	var incoming_fighting_by_actor_id := _build_incoming_fighting_pairs(identities, slots, count)

	_fixed_accumulator = minf(_fixed_accumulator + maxf(delta, 0.0), FIXED_COMBAT_TICK_SECONDS * float(MAX_FIXED_STEPS_PER_FRAME))
	var fixed_steps := 0
	while _fixed_accumulator >= FIXED_COMBAT_TICK_SECONDS and fixed_steps < MAX_FIXED_STEPS_PER_FRAME:
		for i in range(count):
			_update_action(i, FIXED_COMBAT_TICK_SECONDS, nodes, identities, spatials, vitals, configs, actions, slots, actor_index_by_id)

		for i in range(count):
			_try_start_slot_action(i, nodes, identities, spatials, vitals, configs, actions, slots, actor_index_by_id, incoming_fighting_by_actor_id)
		_fixed_accumulator -= FIXED_COMBAT_TICK_SECONDS
		fixed_steps += 1

	for i in range(count):
		_write_node_state(i, process_frame, nodes, actions, actor_index_by_id)
	_record_profile(profile_start)


func _update_action(index: int, delta: float, nodes: Array, identities: Array, spatials: Array, vitals: Array, configs: Array, actions: Array, slots: Array, actor_index_by_id: Dictionary) -> void:
	# Tick the shared turn-token wait off our own slot every resolution step. The canonical owner
	# of a pair (see _canonical_tempo_owner_index) is always one of the two fighters, so its own
	# update guarantees the wait elapses regardless of slot state — no reliance on the slot system.
	var slot = slots[index]
	if slot != null:
		slot.tempo_wait_remaining = maxf(0.0, float(slot.tempo_wait_remaining) - delta)
	var action = actions[index]
	if action == null:
		return
	action.cooldown_remaining = maxf(0.0, action.cooldown_remaining - delta)
	action.reaction_remaining = maxf(0.0, action.reaction_remaining - delta)
	if action.reaction_remaining <= 0.0:
		action.reaction_source_actor_id = ""
	if not action.action_active:
		return
	var vit = vitals[index]
	if vit == null or vit.life_state != NpcRules.LifeState.ALIVE:
		_clear_action(action)
		return
	action.action_remaining = maxf(0.0, action.action_remaining - delta)
	action.action_clip_remaining = maxf(0.0, action.action_clip_remaining - delta)
	if not action.action_has_impacted:
		action.action_impact_remaining -= delta
		if action.action_impact_remaining <= 0.0:
			_resolve_action_impact(index, nodes, identities, spatials, vitals, configs, actions, slots, actor_index_by_id)
	if action.action_clip_remaining <= 0.0 and action.action_index < action.action_names.size() - 1:
		action.action_index += 1
		var actor := _actor_from_node_component(nodes[index])
		if actor != null and actor.has_method("play_system_combat_action_clip"):
			action.action_clip_remaining = maxf(0.0, float(actor.call("play_system_combat_action_clip", str(action.action_names[action.action_index]))))
	if action.action_remaining <= 0.0:
		_handoff_pair_turn(_actor_id_at(index, identities), str(action.action_target_actor_id), slots, identities, actor_index_by_id)
		_clear_action(action)


func _try_start_slot_action(index: int, nodes: Array, identities: Array, spatials: Array, vitals: Array, configs: Array, actions: Array, slots: Array, actor_index_by_id: Dictionary, incoming_fighting_by_actor_id: Dictionary) -> void:
	var actor := _actor_from_node_component(nodes[index])
	var action = actions[index]
	var cfg = configs[index]
	var vit = vitals[index]
	if actor == null or action == null or cfg == null or vit == null:
		return
	if vit.life_state != NpcRules.LifeState.ALIVE or action.action_active or action.reaction_remaining > 0.0 or action.cooldown_remaining > 0.0:
		return
	var pair := _fighting_pair_for_actor(index, identities, slots, incoming_fighting_by_actor_id)
	if pair.is_empty():
		return
	var target_actor_id := str(pair.get("target_id", ""))
	if target_actor_id.is_empty():
		return
	if not actor_index_by_id.has(target_actor_id):
		return
	var target_index: int = actor_index_by_id[target_actor_id]
	var target_vit = vitals[target_index]
	var target_cfg = configs[target_index]
	var target_action = actions[target_index]
	if target_vit == null or target_cfg == null or target_vit.life_state != NpcRules.LifeState.ALIVE or target_cfg.protected_from_combat:
		return
	# Only a target mid-swing blocks the exchange. A target mid-REACTION stays
	# attackable — waiting out reactions gridlocks group fights where someone in
	# the pile is always staggering (their own attack is still gated above).
	if target_action != null and bool(target_action.action_active):
		return
	var actor_id := _actor_id_at(index, identities)
	var tempo_owner_index := _canonical_tempo_owner_index(index, actor_id, target_index, target_actor_id)
	if not _pair_turn_is_ready(tempo_owner_index, actor_id, target_actor_id, slots, index, target_index, configs):
		return
	if not _slot_pair_is_fighting(actor_id, target_actor_id, spatials, configs, slots, actor_index_by_id):
		return
	var target_actor := _actor_from_node_component(nodes[target_index])
	var spec := actor.call("get_system_combat_attack_spec") as Dictionary if actor.has_method("get_system_combat_attack_spec") else {}
	_start_action(action, actor, target_actor, target_actor_id, cfg, spec)
	_mark_pair_attacking(tempo_owner_index, slots)


func _start_action(action, actor: Node, target_actor: Node, target_actor_id: String, cfg, spec: Dictionary) -> void:
	var total_seconds := maxf(float(spec.get("total_seconds", 0.45)), 0.05)
	action.action_active = true
	action.action_target_actor_id = target_actor_id
	action.action_remaining = total_seconds
	action.action_impact_remaining = clampf(float(spec.get("impact_seconds", total_seconds * 0.45)), 0.01, total_seconds)
	action.action_has_impacted = false
	action.action_names = spec.get("animation_names", PackedStringArray()) as PackedStringArray
	action.action_index = 0
	action.action_attack_id = str(spec.get("attack_id", ""))
	action.action_hit_reaction_names = spec.get("hit_reaction_names", PackedStringArray()) as PackedStringArray
	var blunt := maxf(float(cfg.blunt_damage), 0.0)
	var cut := maxf(float(cfg.cut_damage), 0.0)
	action.action_is_critical = randf() <= clampf(float(cfg.crit_chance), 0.0, 1.0)
	if action.action_is_critical:
		var crit_multiplier := randf_range(2.0, 3.0)
		var crit := CombatMath.apply_crit(blunt, cut, crit_multiplier)
		blunt = float(crit["blunt_damage"])
		cut = float(crit["cut_damage"])
	action.action_blunt_damage = blunt
	action.action_cut_damage = cut
	action.cooldown_remaining = maxf(float(cfg.attack_cooldown_seconds), 0.2)
	var clip_seconds := 0.0
	if actor != null and actor.has_method("on_system_combat_attack_started"):
		clip_seconds = float(actor.call("on_system_combat_attack_started", target_actor, action.action_names))
	action.action_clip_remaining = maxf(clip_seconds, float(spec.get("first_clip_seconds", 0.0)))


func _resolve_action_impact(attacker_index: int, nodes: Array, identities: Array, spatials: Array, vitals: Array, configs: Array, actions: Array, slots: Array, actor_index_by_id: Dictionary) -> void:
	var action = actions[attacker_index]
	if action == null or action.action_has_impacted:
		return
	action.action_has_impacted = true
	var target_actor_id := str(action.action_target_actor_id)
	if target_actor_id.is_empty() or not actor_index_by_id.has(target_actor_id):
		return
	if not _slot_pair_is_usable(_actor_id_at(attacker_index, identities), target_actor_id, spatials, configs, slots, actor_index_by_id):
		return
	var target_index: int = actor_index_by_id[target_actor_id]
	var target_vit = vitals[target_index]
	if target_vit == null or target_vit.life_state == NpcRules.LifeState.DEAD:
		return
	var attacker_actor := _actor_from_node_component(nodes[attacker_index])
	var target_actor := _actor_from_node_component(nodes[target_index])
	if attacker_actor == null or target_actor == null:
		return
	var attacker_cfg = configs[attacker_index]
	var target_cfg = configs[target_index]
	var incoming := _transform_incoming_damage(target_actor, attacker_actor, action.action_blunt_damage, action.action_cut_damage)
	var blunt := float(incoming.get("blunt_damage", 0.0))
	var cut := float(incoming.get("cut_damage", 0.0))
	var receive_context := _prepare_receive_attack(target_actor, attacker_actor, blunt, cut)
	if not bool(receive_context.get("accepted", true)):
		return
	var can_actively_defend := bool(receive_context.get("can_actively_defend", true))
	# Consequence propagation: any resolved swing refreshes both grudges (live
	# fights never decay mid-duel) and alerts the victim's nearby faction-mates —
	# aggressive allies (guards) converge and pursue; defensive allies fight only
	# if it reaches them; passive allies never join.
	var target_wa := target_actor as WorldActor
	var attacker_wa := attacker_actor as WorldActor
	if target_wa != null and attacker_wa != null:
		target_wa.mark_hostile(attacker_wa)
		attacker_wa.mark_hostile(target_wa)
		_alert_faction_allies(target_index, attacker_index, target_wa, attacker_wa, nodes, spatials, vitals, configs)
	var outcome := "hit"
	var final_blunt := blunt
	var final_cut := cut
	var hit_chance := CombatMath.hit_chance(float(attacker_cfg.hit_score), float(target_cfg.dodge_score))
	if can_actively_defend and randf() > hit_chance:
		outcome = "dodged"
		final_blunt = 0.0
		final_cut = 0.0
	else:
		var block_chance := CombatMath.defense_chance(float(target_cfg.block_score), float(attacker_cfg.hit_score))
		if can_actively_defend and randf() <= block_chance:
			outcome = "blocked"
			var blocked := CombatMath.apply_block_mitigation(final_blunt, final_cut, clampf(float(target_cfg.block_damage_multiplier), 0.0, 1.0))
			final_blunt = float(blocked["blunt_damage"])
			final_cut = float(blocked["cut_damage"])
		var grit := CombatMath.apply_toughness_grit(final_blunt, final_cut, float(target_cfg.toughness))
		final_blunt = float(grit.get("blunt_damage", 0.0))
		final_cut = float(grit.get("cut_damage", 0.0))
		var clamped := _clamp_final_damage(target_actor, attacker_actor, final_blunt, final_cut)
		final_blunt = float(clamped.get("blunt_damage", 0.0))
		final_cut = float(clamped.get("cut_damage", 0.0))
	var reaction_seconds := 0.0
	if target_vit.death_profile == CGameActorVitals.DeathProfile.HUMANOID:
		# S4 FLIP: realized humanoid vitals are GECS-owned. Deal the resolved damage straight into the
		# component (the exact mutation apply_resolved_damage did node-side) and re-derive life_state via
		# the shared state machine. GameVitalsSystem (registered right after this) then runs bleeding/
		# dying/recovery; GameActorSyncSystem reflects the result back onto the node for display/signals.
		target_vit.blunt_damage += maxf(final_blunt, 0.0)
		target_vit.open_cut_damage += maxf(final_cut, 0.0)
		VitalsStateMachine.recalculate(target_vit, float(target_cfg.toughness))
		# Presentation only: outcome text + reaction clip on the node; damage stays component-owned.
		var reacting_actor := target_actor as WorldActor
		if reacting_actor != null:
			reaction_seconds = reacting_actor.play_system_combat_hit_reaction(attacker_actor, outcome, action.action_attack_id, action.action_hit_reaction_names, action.action_is_critical, bool(target_cfg.has_shield), can_actively_defend, final_blunt + final_cut)
	elif target_actor.has_method("handle_system_combat_resolution"):
		# Robots/quadbots keep their node-side death model (S5) — unchanged reflected path.
		reaction_seconds = float(target_actor.call("handle_system_combat_resolution", attacker_actor, outcome, action.action_attack_id, action.action_hit_reaction_names, action.action_is_critical, bool(target_cfg.has_shield), final_blunt, final_cut, can_actively_defend))
	if reaction_seconds > 0.0:
		var target_action = actions[target_index]
		if target_action != null:
			_clear_action(target_action)
			# The sim owns pacing: hold the victim only for a short stagger even when the
			# presentation clip runs longer (the clip keeps playing on the node). Holding
			# for full clip lengths gridlocks group fights — attackers refuse to swing at
			# a reacting target, so overlapping reactions freeze everyone.
			target_action.reaction_remaining = minf(reaction_seconds, MAX_REACTION_HOLD_SECONDS)
			target_action.reaction_source_actor_id = str(identities[attacker_index].actor_id) if identities[attacker_index] != null else ""


func _alert_faction_allies(target_index: int, attacker_index: int, target_wa: WorldActor, attacker_wa: WorldActor, nodes: Array, spatials: Array, vitals: Array, configs: Array) -> void:
	var faction := str(target_wa.faction_name).strip_edges()
	if faction.is_empty():
		return
	var victim_position: Vector3 = spatials[target_index].world_position
	for j in range(nodes.size()):
		if j == target_index or j == attacker_index:
			continue
		var vit = vitals[j]
		var cfg = configs[j]
		if vit == null or cfg == null or vit.life_state != NpcRules.LifeState.ALIVE or cfg.protected_from_combat:
			continue
		if int(cfg.combat_stance) == NpcRules.CombatStance.PASSIVE:
			continue
		# Defensive allies defend what's next to them (assist range); aggressive
		# responders — guards — react to violence they can witness (witness range).
		var assist_radius := float(cfg.assist_scan_radius)
		if int(cfg.combat_stance) == NpcRules.CombatStance.AGGRESSIVE:
			assist_radius = maxf(assist_radius, float(cfg.witness_radius))
		if assist_radius <= 0.0:
			continue
		var spatial = spatials[j]
		if spatial == null or spatial.world_position.distance_squared_to(victim_position) > assist_radius * assist_radius:
			continue
		var ally := _actor_from_node_component(nodes[j]) as WorldActor
		if ally == null or str(ally.faction_name).strip_edges() != faction:
			continue
		ally.mark_hostile(attacker_wa)


func _build_incoming_fighting_pairs(identities: Array, slots: Array, count: int) -> Dictionary:
	var incoming := {}
	for i in range(count):
		var slot = slots[i]
		if slot == null or int(slot.slot_state) != FIGHT_STATE_FIGHTING:
			continue
		var target_id := str(slot.slot_target_actor_id)
		var actor_id := _actor_id_at(i, identities)
		if target_id.is_empty() or actor_id.is_empty():
			continue
		var attackers: Array = incoming.get(target_id, [])
		attackers.append({"target_id": actor_id, "owner_index": i})
		incoming[target_id] = attackers
	return incoming


func _fighting_pair_for_actor(index: int, identities: Array, slots: Array, incoming_fighting_by_actor_id: Dictionary) -> Dictionary:
	var slot = slots[index]
	if slot != null and int(slot.slot_state) == FIGHT_STATE_FIGHTING and not str(slot.slot_target_actor_id).is_empty():
		return {"target_id": str(slot.slot_target_actor_id), "owner_index": index}
	var actor_id := _actor_id_at(index, identities)
	var incoming: Array = incoming_fighting_by_actor_id.get(actor_id, [])
	return incoming[0] as Dictionary if not incoming.is_empty() and incoming[0] is Dictionary else {}


func _slot_pair_is_fighting(actor_id: String, target_actor_id: String, spatials: Array, configs: Array, slots: Array, actor_index_by_id: Dictionary) -> bool:
	if actor_id.is_empty() or target_actor_id.is_empty() or not actor_index_by_id.has(actor_id) or not actor_index_by_id.has(target_actor_id):
		return false
	var actor_index: int = actor_index_by_id[actor_id]
	var target_index: int = actor_index_by_id[target_actor_id]
	return _slot_points_to(actor_index, target_actor_id, spatials, configs, slots, target_index) or _slot_points_to(target_index, actor_id, spatials, configs, slots, actor_index)


func _slot_pair_is_usable(actor_id: String, target_actor_id: String, spatials: Array, configs: Array, slots: Array, actor_index_by_id: Dictionary) -> bool:
	if actor_id.is_empty() or target_actor_id.is_empty() or not actor_index_by_id.has(actor_id) or not actor_index_by_id.has(target_actor_id):
		return false
	var actor_index: int = actor_index_by_id[actor_id]
	var target_index: int = actor_index_by_id[target_actor_id]
	return _slot_points_to(actor_index, target_actor_id, spatials, configs, slots, target_index) or _slot_points_to(target_index, actor_id, spatials, configs, slots, actor_index)


func _slot_points_to(slot_owner_index: int, target_actor_id: String, spatials: Array, configs: Array, slots: Array, target_index: int) -> bool:
	var slot = slots[slot_owner_index]
	if slot == null or str(slot.slot_target_actor_id) != target_actor_id:
		return false
	if int(slot.slot_state) != FIGHT_STATE_FIGHTING:
		return false
	var cfg = configs[slot_owner_index]
	if cfg != null and absf(spatials[slot_owner_index].world_position.y - spatials[target_index].world_position.y) > float(cfg.move_target_vertical_tolerance):
		return false
	return _horizontal_distance(spatials[slot_owner_index].world_position, spatials[target_index].world_position) <= float(slot.leash_distance)


func _pair_turn_is_ready(pair_owner_index: int, actor_id: String, partner_id: String, slots: Array, actor_index: int, partner_index: int, configs: Array) -> bool:
	if pair_owner_index < 0 or pair_owner_index >= slots.size():
		return false
	var slot = slots[pair_owner_index]
	if slot == null:
		return false
	var tempo := str(slot.tempo_actor_id)
	# Claim the shared turn token if it is unowned or points at someone outside this pair (a stale
	# id left over from a previous fight). Without this, a stale token blocks BOTH fighters forever
	# — the "stuck staring at each other, never attacking" deadlock. The FIRST turn of a fresh
	# engagement goes to a dexterity-weighted initiative roll (see architecture/combat/initiative.md);
	# afterwards the token alternates via _handoff_pair_turn.
	if tempo.is_empty() or (tempo != actor_id and tempo != partner_id):
		slot.tempo_actor_id = _roll_initiative(actor_id, partner_id, actor_index, partner_index, configs)
		slot.tempo_wait_remaining = 0.0
		tempo = str(slot.tempo_actor_id)
	# N-v-1 pile rule (initiative.md): the token can sit with a partner whose OWN
	# fight is against someone else — they only ever swing in their own pair, so
	# they would hold this pair's turn forever (each attacker in the pile got ONE
	# hit, then froze; the outnumbered fighter mowed everyone down unopposed).
	# The waiting attacker inherits the turn; the pacing wait still applies, so
	# the crowd lands exchanges on the shared cadence — being outnumbered is a
	# death sentence, not a veto.
	if tempo == partner_id and not _actor_fights_target(partner_index, actor_id, slots):
		slot.tempo_actor_id = actor_id
		tempo = actor_id
	return tempo == actor_id and float(slot.tempo_wait_remaining) <= 0.0


func _actor_fights_target(index: int, target_actor_id: String, slots: Array) -> bool:
	if index < 0 or index >= slots.size():
		return false
	var slot = slots[index]
	return slot != null and int(slot.slot_state) == FIGHT_STATE_FIGHTING and str(slot.slot_target_actor_id) == target_actor_id


## initiative.md: weighted random by max(1, dexterity). The doc's initiative-credit
## fairness term applies when >2 contenders queue on one defender; the pair token
## only ever has two, where the weighted roll alone matches the intent.
func _roll_initiative(actor_id: String, partner_id: String, actor_index: int, partner_index: int, configs: Array) -> String:
	var actor_dex := 1.0
	var partner_dex := 1.0
	if actor_index >= 0 and actor_index < configs.size() and configs[actor_index] != null:
		actor_dex = maxf(1.0, float(configs[actor_index].dexterity))
	if partner_index >= 0 and partner_index < configs.size() and configs[partner_index] != null:
		partner_dex = maxf(1.0, float(configs[partner_index].dexterity))
	return actor_id if randf() < actor_dex / (actor_dex + partner_dex) else partner_id


func _mark_pair_attacking(pair_owner_index: int, slots: Array) -> void:
	if pair_owner_index < 0 or pair_owner_index >= slots.size():
		return
	var slot = slots[pair_owner_index]
	if slot != null:
		slot.state_seconds = 0.0


func _handoff_pair_turn(attacker_id: String, target_id: String, slots: Array, _identities: Array, actor_index_by_id: Dictionary) -> void:
	if attacker_id.is_empty() or target_id.is_empty() or not actor_index_by_id.has(attacker_id) or not actor_index_by_id.has(target_id):
		return
	var attacker_index: int = actor_index_by_id[attacker_id]
	var target_index: int = actor_index_by_id[target_id]
	var owner_index := _canonical_tempo_owner_index(attacker_index, attacker_id, target_index, target_id)
	if owner_index < 0 or owner_index >= slots.size():
		return
	var slot = slots[owner_index]
	if slot == null:
		return
	# Pass the turn to the partner on the SAME canonical slot both fighters read.
	slot.tempo_actor_id = target_id
	slot.tempo_wait_remaining = maxf(float(slot.tempo_wait_remaining), TURN_HANDOFF_WAIT_SECONDS)
	slot.state_seconds = 0.0


func _canonical_tempo_owner_index(a_index: int, a_actor_id: String, b_index: int, b_actor_id: String) -> int:
	# Deterministic shared owner for a fighting pair: the lower actor_id (index tie-break). Both
	# fighters resolve the SAME slot for the turn token, so a handoff written by one is read by the
	# other. The old per-actor-slot scheme crossed the token and deadlocked clean 1v1 duels.
	if a_actor_id == b_actor_id:
		return mini(a_index, b_index)
	return a_index if a_actor_id < b_actor_id else b_index


func _actor_id_at(index: int, identities: Array) -> String:
	var identity = identities[index]
	return str(identity.actor_id) if identity != null else ""


func _write_node_state(index: int, process_frame: int, nodes: Array, actions: Array, actor_index_by_id: Dictionary) -> void:
	var actor := _actor_from_node_component(nodes[index])
	var action = actions[index]
	if actor == null or action == null:
		return
	var focus_id := 0
	var focus_actor_id := str(action.reaction_source_actor_id) if action.reaction_remaining > 0.0 else str(action.action_target_actor_id)
	if not focus_actor_id.is_empty() and actor_index_by_id.has(focus_actor_id):
		var focus_actor := _actor_from_node_component(nodes[int(actor_index_by_id[focus_actor_id])])
		focus_id = focus_actor.get_instance_id() if focus_actor != null else 0
	var world_actor := actor as WorldActor
	if world_actor != null:
		world_actor.set_system_combat_bridge(process_frame, bool(action.action_active), float(action.reaction_remaining), float(action.cooldown_remaining), focus_id)
	elif actor.has_method("set"):
		actor.set("_system_combat_action_active", bool(action.action_active))
		actor.set("_system_combat_reaction_remaining", float(action.reaction_remaining))
		actor.set("_system_combat_cooldown_remaining", float(action.cooldown_remaining))
		actor.set("_system_combat_focus_id", focus_id)


func _actor_from_node_component(node_component) -> Node:
	if node_component == null:
		return null
	var actor = node_component.get_actor() if node_component.has_method("get_actor") else node_component.actor
	return actor as Node if actor != null and is_instance_valid(actor) else null


func _clear_action(action) -> void:
	action.action_active = false
	action.action_target_actor_id = ""
	action.action_remaining = 0.0
	action.action_impact_remaining = 0.0
	action.action_has_impacted = false
	action.action_names = PackedStringArray()
	action.action_index = 0
	action.action_clip_remaining = 0.0
	action.action_attack_id = ""
	action.action_hit_reaction_names = PackedStringArray()
	action.action_blunt_damage = 0.0
	action.action_cut_damage = 0.0
	action.action_is_critical = false


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var offset := b - a
	offset.y = 0.0
	return offset.length()


func _transform_incoming_damage(target_actor: Node, attacker_actor: Node, blunt: float, cut: float) -> Dictionary:
	if target_actor != null and target_actor.has_method("transform_system_incoming_damage"):
		return target_actor.call("transform_system_incoming_damage", attacker_actor, blunt, cut) as Dictionary
	return {"blunt_damage": maxf(blunt, 0.0), "cut_damage": maxf(cut, 0.0)}


func _prepare_receive_attack(target_actor: Node, attacker_actor: Node, blunt: float, cut: float) -> Dictionary:
	if target_actor != null and target_actor.has_method("prepare_system_combat_receive_attack"):
		return target_actor.call("prepare_system_combat_receive_attack", attacker_actor, blunt, cut) as Dictionary
	return {"accepted": target_actor != null and attacker_actor != null, "can_actively_defend": true}


func _clamp_final_damage(target_actor: Node, attacker_actor: Node, blunt: float, cut: float) -> Dictionary:
	if target_actor != null and target_actor.has_method("clamp_system_final_combat_damage"):
		return target_actor.call("clamp_system_final_combat_damage", attacker_actor, blunt, cut) as Dictionary
	return {"blunt_damage": maxf(blunt, 0.0), "cut_damage": maxf(cut, 0.0)}


func _record_profile(profile_start: int) -> void:
	if not profile_enabled:
		return
	_profile_calls += 1
	_profile_usec += Time.get_ticks_usec() - profile_start
	if _profile_calls >= 240:
		print("GECS_COMBAT_PROFILE resolution avg_usec=%.2f calls=%d" % [float(_profile_usec) / float(_profile_calls), _profile_calls])
		_profile_calls = 0
		_profile_usec = 0
