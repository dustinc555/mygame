extends "res://addons/gecs/ecs/system.gd"

class_name GameCombatTargetingSystem

# S2.1: batched, reflection-free combat target selection over packed component arrays.
# Writes C_COMBAT_STATE.system_target_id and, during the node-to-system transition, the
# transient node bridge `_system_target_id` consumed by legacy node AI.
#
# Run order: AFTER GameCombatStateSyncSystem (needs fresh config/state), BEFORE ai_job/node AI.

const C_NODE = preload("res://scripts/ecs/components/c_game_actor_node.gd")
const C_IDENTITY = preload("res://scripts/ecs/components/c_game_actor_identity.gd")
const C_SPATIAL = preload("res://scripts/ecs/components/c_game_actor_spatial.gd")
const C_VITALS = preload("res://scripts/ecs/components/c_game_actor_vitals.gd")
const C_FACTION = preload("res://scripts/ecs/components/c_game_actor_faction.gd")
const C_CONFIG = preload("res://scripts/ecs/components/c_game_combat_config.gd")
const C_STATE = preload("res://scripts/ecs/components/c_game_combat_state.gd")
const C_SLOT = preload("res://scripts/ecs/components/c_game_combat_slot_state.gd")

const FIGHT_STATE_SEEKING_SLOT := 2
const FIGHT_STATE_FIGHTING := 3
const SHADOW_REPORT_INTERVAL := 120
const TARGET_CELL_SIZE := 6.0
const MAX_TARGET_OCCUPANT_CHECKS := 128
const MAX_TARGET_CANDIDATE_CHECKS := 32
const FORMATION_ENGAGEMENT_SCAN_RADIUS_CAP := 48.0
const TARGET_PRESSURE_SCORE_MULTIPLIER := 4.0
const CURRENT_TARGET_STICKINESS := 1.15
const MUTUAL_TARGET_BONUS := 0.45

static var shadow_enabled := false
static var default_targeting_interval_seconds := 0.5
static var _report_calls := 0
static var _cmp_total := 0
static var _cmp_match := 0


func query() -> QueryBuilder:
	return q.with_all([C_NODE, C_IDENTITY, C_SPATIAL, C_VITALS, C_FACTION, C_CONFIG, C_STATE, C_SLOT]).iterate(
		[C_NODE, C_IDENTITY, C_SPATIAL, C_VITALS, C_FACTION, C_CONFIG, C_STATE, C_SLOT])


func process(entities: Array, components: Array, _delta: float) -> void:
	var nodes: Array = components[0]
	var identities: Array = components[1]
	var spatials: Array = components[2]
	var vitals: Array = components[3]
	var factions: Array = components[4]
	var configs: Array = components[5]
	var states: Array = components[6]
	var slots: Array = components[7]
	var count := entities.size()
	if count == 0:
		return
	var alive_value := NpcRules.LifeState.ALIVE
	var process_frame := Engine.get_process_frames()
	var due_flags := PackedByteArray()
	due_flags.resize(count)
	var any_due := false
	for i in range(count):
		var state_i = states[i]
		if state_i == null:
			continue
		var node_actor_i = nodes[i].actor if nodes[i] != null else null
		var vit_i = vitals[i]
		var cfg_i = configs[i]
		if vit_i == null or cfg_i == null or vit_i.life_state != alive_value or cfg_i.protected_from_combat:
			state_i.system_target_id = 0
			state_i.system_target_actor_id = ""
			state_i.system_target_retarget_remaining = 0.0
			_write_node_target(node_actor_i, 0, process_frame)
			continue
		state_i.system_target_retarget_remaining = maxf(float(state_i.system_target_retarget_remaining) - maxf(_delta, 0.0), 0.0)
		if state_i.system_target_retarget_remaining > 0.0:
			_write_node_target(node_actor_i, int(state_i.system_target_id), process_frame)
			continue
		due_flags[i] = 1
		any_due = true
		state_i.system_target_retarget_remaining = _next_retarget_seconds(cfg_i)
	if not any_due:
		return

	# Cache the node instance id per entity once (used for hostility-by-grudge, stickiness, shadow compare).
	var instance_ids := PackedInt64Array()
	instance_ids.resize(count)
	var actor_ids := PackedStringArray()
	actor_ids.resize(count)
	var index_by_actor_id := {}
	var spatial_buckets := {}
	for i in range(count):
		var node_actor = nodes[i].actor if nodes[i] != null else null
		var iid: int = node_actor.get_instance_id() if node_actor != null and is_instance_valid(node_actor) else 0
		instance_ids[i] = iid
		actor_ids[i] = str(identities[i].actor_id) if identities[i] != null else ""
		if not actor_ids[i].is_empty():
			index_by_actor_id[actor_ids[i]] = i
		_add_spatial_bucket(spatial_buckets, spatials[i].world_position, i)
	var hostile_relation_pairs := _build_hostile_relation_pairs(factions, count)
	var pressure_by_target_actor_id := _build_current_target_pressure(states, count)

	for i in range(count):
		if due_flags[i] == 0:
			continue
		var state_i = states[i]
		if state_i == null:
			continue
		var previous_system_target_actor_id := str(state_i.system_target_actor_id)
		state_i.system_target_id = 0
		state_i.system_target_actor_id = ""
		var node_actor = nodes[i].actor if nodes[i] != null else null
		var vit_i = vitals[i]
		var cfg_i = configs[i]
		if vit_i == null or cfg_i == null or vit_i.life_state != alive_value or cfg_i.protected_from_combat:
			_write_node_target(node_actor, 0, process_frame)
			continue
		var pos_i: Vector3 = spatials[i].world_position
		var fac_i = factions[i]
		var actor_id_i := actor_ids[i]
		var current_target_actor_id := previous_system_target_actor_id
		if current_target_actor_id.is_empty():
			current_target_actor_id = str(state_i.current_target_actor_id)
		var grudges_i: PackedInt64Array = state_i.personal_hostile_ids
		var grudge_actor_ids_i: PackedStringArray = state_i.personal_hostile_actor_ids
		# Engagement lock: once the slot system has us committed to a target (seeking a slot or
		# trading blows), keep that target instead of re-scanning for a "cheaper" enemy. This is
		# what stops an actor abandoning a live duel mid-fight. The lock releases automatically the
		# moment the engagement ends — target dies/protected/no-longer-hostile here, or the slot
		# system drops FIGHTING (e.g. the target fled out of leash), so we free-pick again next pass.
		var lock_j := _engagement_lock_index(i, slots, index_by_actor_id, vitals, configs, factions, instance_ids, actor_ids, alive_value, hostile_relation_pairs, fac_i, grudges_i, grudge_actor_ids_i)
		if lock_j >= 0:
			state_i.system_target_id = instance_ids[lock_j]
			state_i.system_target_actor_id = actor_ids[lock_j]
			_write_node_target(node_actor, state_i.system_target_id, process_frame)
			continue
		var vtol: float = cfg_i.move_target_vertical_tolerance
		var attack_range: float = cfg_i.attack_range
		var radius: float = _target_scan_radius(cfg_i, fac_i, attack_range)
		var radius_sq := radius * radius
		var center_cell := _target_cell(pos_i)
		var cell_radius := int(ceil(radius / TARGET_CELL_SIZE))
		var best_j := -1
		var best_score := INF
		var occupant_checks := 0
		var candidate_checks := 0
		for cell_x in range(center_cell.x - cell_radius, center_cell.x + cell_radius + 1):
			for cell_z in range(center_cell.y - cell_radius, center_cell.y + cell_radius + 1):
				var bucket: Array = spatial_buckets.get(Vector2i(cell_x, cell_z), [])
				for j_value in bucket:
					occupant_checks += 1
					if occupant_checks > MAX_TARGET_OCCUPANT_CHECKS:
						break
					var j := int(j_value)
					if j == i:
						continue
					var vit_j = vitals[j]
					var cfg_j = configs[j]
					if vit_j == null or cfg_j == null or vit_j.life_state != alive_value or cfg_j.protected_from_combat:
						continue
					var pos_j: Vector3 = spatials[j].world_position
					if absf(pos_j.y - pos_i.y) > vtol:
						continue
					if not _is_hostile(fac_i, factions[j], grudges_i, instance_ids[j], grudge_actor_ids_i, actor_ids[j], hostile_relation_pairs):
						continue
					candidate_checks += 1
					if candidate_checks > MAX_TARGET_CANDIDATE_CHECKS:
						break
					var dx := pos_j.x - pos_i.x
					var dz := pos_j.z - pos_i.z
					var d2 := dx * dx + dz * dz
					if d2 > radius_sq:
						continue
					var distance := sqrt(d2)
					var score := _target_score(i, j, distance, attack_range, actor_id_i, current_target_actor_id, actor_ids, states, pressure_by_target_actor_id)
					if score >= best_score:
						continue
					best_score = score
					best_j = j
				if occupant_checks > MAX_TARGET_OCCUPANT_CHECKS or candidate_checks > MAX_TARGET_CANDIDATE_CHECKS:
					break
			if occupant_checks > MAX_TARGET_OCCUPANT_CHECKS or candidate_checks > MAX_TARGET_CANDIDATE_CHECKS:
				break

		var final_j := best_j
		var final_actor_id := ""
		if final_j >= 0:
			state_i.system_target_id = instance_ids[final_j]
			final_actor_id = str(identities[final_j].actor_id) if identities[final_j] != null else ""
			state_i.system_target_actor_id = final_actor_id
			_apply_projected_pressure_change(pressure_by_target_actor_id, current_target_actor_id, final_actor_id)
		_write_node_target(node_actor, state_i.system_target_id, process_frame)

	if shadow_enabled:
		_record_shadow(states, count)


func _is_hostile(fac_a, fac_b, grudges_a: PackedInt64Array, instance_id_b: int, grudge_actor_ids_a: PackedStringArray, actor_id_b: String, hostile_relation_pairs: Dictionary) -> bool:
	if fac_a == null or fac_b == null:
		return false
	# Approximation of WorldActor.has_hostility_with using component data only:
	# explicit hostile-faction lists, faction-controller relation snapshot, or a personal grudge.
	if instance_id_b != 0 and grudges_a.size() > 0 and grudges_a.has(instance_id_b):
		return true
	if not actor_id_b.is_empty() and grudge_actor_ids_a.size() > 0 and grudge_actor_ids_a.has(actor_id_b):
		return true
	var fa: String = fac_a.faction_id
	var fb: String = fac_b.faction_id
	if fa == fb:
		return false
	if fac_a.hostile_faction_ids.has(fb):
		return true
	if fac_b.hostile_faction_ids.has(fa):
		return true
	if hostile_relation_pairs.has(_relation_key(fa, fb)):
		return true
	return false


func _engagement_lock_index(i: int, slots: Array, index_by_actor_id: Dictionary, vitals: Array, configs: Array, factions: Array, instance_ids: PackedInt64Array, actor_ids: PackedStringArray, alive_value: int, hostile_relation_pairs: Dictionary, fac_i, grudges_i: PackedInt64Array, grudge_actor_ids_i: PackedStringArray) -> int:
	if i >= slots.size():
		return -1
	var slot = slots[i]
	if slot == null:
		return -1
	var fight_state := int(slot.slot_state)
	if fight_state != FIGHT_STATE_FIGHTING and fight_state != FIGHT_STATE_SEEKING_SLOT:
		return -1
	var target_id := str(slot.slot_target_actor_id)
	if target_id.is_empty() or not index_by_actor_id.has(target_id):
		return -1
	var j := int(index_by_actor_id[target_id])
	if j == i:
		return -1
	var vit_j = vitals[j]
	var cfg_j = configs[j]
	if vit_j == null or cfg_j == null or vit_j.life_state != alive_value or cfg_j.protected_from_combat:
		return -1
	if not _is_hostile(fac_i, factions[j], grudges_i, instance_ids[j], grudge_actor_ids_i, actor_ids[j], hostile_relation_pairs):
		return -1
	return j


func _target_scan_radius(cfg, faction, attack_range: float) -> float:
	var radius: float = maxf(float(cfg.aggro_scan_radius), attack_range)
	if int(cfg.combat_stance) == NpcRules.CombatStance.AGGRESSIVE and _has_meaningful_squad(faction):
		radius = maxf(radius, minf(float(cfg.squad_assist_radius), FORMATION_ENGAGEMENT_SCAN_RADIUS_CAP))
	return radius


func _has_meaningful_squad(faction) -> bool:
	if faction == null:
		return false
	var squad := str(faction.squad_name).strip_edges()
	if squad.is_empty():
		return false
	var lower := squad.to_lower()
	return lower != "default" and lower != "none"


func _target_score(_attacker_index: int, target_index: int, distance: float, attack_range: float, attacker_actor_id: String, current_target_actor_id: String, actor_ids: PackedStringArray, states: Array, pressure_by_target_actor_id: Dictionary) -> float:
	var target_actor_id := actor_ids[target_index]
	var pressure := int(pressure_by_target_actor_id.get(target_actor_id, 0))
	var score := distance + float(pressure) * maxf(attack_range, 0.1) * TARGET_PRESSURE_SCORE_MULTIPLIER
	if not current_target_actor_id.is_empty() and target_actor_id == current_target_actor_id:
		score -= maxf(attack_range, 0.1) * CURRENT_TARGET_STICKINESS
	var target_state = states[target_index]
	if target_state != null and (str(target_state.current_target_actor_id) == attacker_actor_id or str(target_state.system_target_actor_id) == attacker_actor_id):
		score -= maxf(attack_range, 0.1) * MUTUAL_TARGET_BONUS
	return score


func _build_current_target_pressure(states: Array, count: int) -> Dictionary:
	var pressure := {}
	for i in range(count):
		var state = states[i]
		if state == null:
			continue
		var target_actor_id := str(state.system_target_actor_id)
		if target_actor_id.is_empty():
			target_actor_id = str(state.current_target_actor_id)
		if target_actor_id.is_empty():
			continue
		pressure[target_actor_id] = int(pressure.get(target_actor_id, 0)) + 1
	return pressure


func _next_retarget_seconds(cfg) -> float:
	var interval := maxf(float(cfg.retarget_interval_seconds), 0.0)
	if interval <= 0.0:
		interval = maxf(default_targeting_interval_seconds, 0.01)
	return interval + randf_range(0.0, maxf(float(cfg.retarget_jitter_seconds), 0.0))


func _apply_projected_pressure_change(pressure_by_target_actor_id: Dictionary, old_target_actor_id: String, new_target_actor_id: String) -> void:
	if old_target_actor_id == new_target_actor_id:
		return
	if not old_target_actor_id.is_empty():
		var old_pressure := maxi(0, int(pressure_by_target_actor_id.get(old_target_actor_id, 0)) - 1)
		if old_pressure <= 0:
			pressure_by_target_actor_id.erase(old_target_actor_id)
		else:
			pressure_by_target_actor_id[old_target_actor_id] = old_pressure
	if not new_target_actor_id.is_empty():
		pressure_by_target_actor_id[new_target_actor_id] = int(pressure_by_target_actor_id.get(new_target_actor_id, 0)) + 1


func _build_hostile_relation_pairs(factions: Array, count: int) -> Dictionary:
	var faction_ids := PackedStringArray()
	for i in range(count):
		var faction = factions[i]
		if faction == null:
			continue
		var faction_id := str(faction.faction_id)
		if not faction_id.is_empty() and not faction_ids.has(faction_id):
			faction_ids.append(faction_id)
	if faction_ids.size() < 2:
		return {}
	var faction_controller := get_tree().get_first_node_in_group("faction_controller") if get_tree() != null else null
	if faction_controller == null or not faction_controller.has_method("are_hostile"):
		return {}
	var pairs := {}
	for a_index in range(faction_ids.size()):
		for b_index in range(a_index + 1, faction_ids.size()):
			var faction_a := str(faction_ids[a_index])
			var faction_b := str(faction_ids[b_index])
			if bool(faction_controller.call("are_hostile", faction_a, faction_b)):
				pairs[_relation_key(faction_a, faction_b)] = true
	return pairs


func _relation_key(faction_a: String, faction_b: String) -> String:
	var values := [faction_a, faction_b]
	values.sort()
	return "%s|%s" % [str(values[0]), str(values[1])]


func _target_cell(position: Vector3) -> Vector2i:
	var cell_size := maxf(TARGET_CELL_SIZE, 1.0)
	return Vector2i(floori(position.x / cell_size), floori(position.z / cell_size))


func _add_spatial_bucket(spatial_buckets: Dictionary, position: Vector3, index: int) -> void:
	var cell := _target_cell(position)
	var bucket: Array = spatial_buckets.get(cell, [])
	bucket.append(index)
	spatial_buckets[cell] = bucket


func _write_node_target(actor, target_id: int, process_frame: int) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var world_actor := actor as WorldActor
	if world_actor != null:
		world_actor.set_system_target_bridge(target_id, process_frame)
	elif actor.has_method("set"):
		actor.set("_system_target_id", target_id)


func _write_cached_node_targets(nodes: Array, states: Array, process_frame: int, count: int) -> void:
	for i in range(count):
		var state = states[i]
		var node_actor = nodes[i].actor if nodes[i] != null else null
		_write_node_target(node_actor, int(state.system_target_id) if state != null else 0, process_frame)


func _record_shadow(states: Array, count: int) -> void:
	# Compare the system's pick vs the node's actual current target, only where the node HAS a target.
	for i in range(count):
		var s = states[i]
		if s == null or s.current_target_id == 0:
			continue
		_cmp_total += 1
		if s.system_target_id == s.current_target_id:
			_cmp_match += 1
	_report_calls += 1
	if _report_calls >= SHADOW_REPORT_INTERVAL:
		var pct := (100.0 * float(_cmp_match) / float(_cmp_total)) if _cmp_total > 0 else 0.0
		print("COMBAT_TARGETING_SHADOW match=%d/%d (%.1f%%) over %d frames" % [_cmp_match, _cmp_total, pct, _report_calls])
		_report_calls = 0
		_cmp_total = 0
		_cmp_match = 0
