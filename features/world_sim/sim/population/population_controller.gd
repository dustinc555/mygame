extends Node

class_name PopulationController

const RESIDENCE_SPAWN_REVISION := 1

signal population_record_changed(settlement_id: String, actor_id: String)
signal person_died(actor_id: String)
signal dead_projection_registered(actor_id: String)
signal assignment_error(code: String, actor_id: String, settlement_ids: PackedStringArray)

const SERVICE_ID := &"population"

const CHARACTER_APPEARANCE_DATA_SCRIPT := preload("res://features/actors/resources/character_appearance/character_appearance_data.gd")
const HUMAN_RACE := preload("res://features/actors/resources/character_races/human.tres")
const RUSTDEAD_FACTION_ID := "Rustdead"
const RUSTDEAD_RACE_ID := "rustdead"
const VISUAL_BODY_TYPE_FEMALE := 3

var root_scene: Node
var _context: BootstrapContext
var actor_records: Dictionary = {}
var _actor_id_by_assignment_key: Dictionary = {}
var _live_actor_by_id: Dictionary = {}
var _skill_change_callable_by_actor_id: Dictionary = {}
var _life_change_callable_by_actor_id: Dictionary = {}
var _initialized := false


func initialize(context: BootstrapContext) -> void:
	_context = context
	root_scene = context.root_scene
	var gecs := context.get_optional(GecsWorldController.SERVICE_ID) as GecsWorldController
	if gecs != null and not gecs.world_reindexed.is_connected(_on_world_reindexed):
		gecs.world_reindexed.connect(_on_world_reindexed)
	if gecs != null and not gecs.population_life_state_changed.is_connected(_on_population_life_state_changed):
		gecs.population_life_state_changed.connect(_on_population_life_state_changed)
	var party_manager := root_scene.get_node_or_null("PartyManager") as PartyManager if root_scene != null else null
	if party_manager != null and not party_manager.party_membership_changed.is_connected(_on_party_membership_changed):
		party_manager.party_membership_changed.connect(_on_party_membership_changed)
	var world_time := context.get_optional(WorldTimeController.SERVICE_ID) as WorldTimeController
	if world_time != null and not world_time.day_changed.is_connected(_on_world_day_changed):
		world_time.day_changed.connect(_on_world_day_changed)
	_try_initialize()


func _ready() -> void:
	add_to_group("population_controller")
	_try_initialize()


func register_actor(actor: Node, settlement_id := "", context: Dictionary = {}) -> Dictionary:
	if actor == null or not is_instance_valid(actor):
		return {}
	if settlement_id.is_empty():
		settlement_id = _find_actor_settlement_id(actor)
	var actor_id := _actor_id_for_actor(actor, settlement_id)
	if actor_id.is_empty():
		return {}
	actor.set("stable_id", actor_id)
	actor.set_meta("actor_record_id", actor_id)
	var record: Dictionary = _get_actor_record_mutable(actor_id)
	if record.is_empty():
		record = _new_record_from_actor(actor, actor_id, settlement_id, context)
	else:
		record = _merge_actor_state_into_record(record, actor, settlement_id, context)
	record["realization_state"] = "realized"
	record["live_node_path"] = actor.get_path()
	record = _save_actor_record(actor_id, record)
	_live_actor_by_id[actor_id] = actor
	_connect_actor_skill_changes(actor, actor_id)
	_connect_actor_life_changes(actor, actor_id)
	actor.set_meta("settlement_id", str(record.get("settlement_id", settlement_id)))
	actor.set_meta("actor_role_id", str(record.get("role_id", "resident")))
	_refresh_actor_visual_context(actor, record)
	_register_actor_with_query_controller(actor)
	return record.duplicate(true)


func unregister_actor(actor: Node) -> void:
	if actor == null:
		return
	var actor_id := _actor_record_id(actor)
	if actor_id.is_empty():
		return
	var stats = actor.call("get_stats") if is_instance_valid(actor) and actor.has_method("get_stats") else null
	if stats != null and stats.has_method("flush_pending_xp"):
		stats.call("flush_pending_xp")
	_unregister_actor_from_query_controller(actor)
	_disconnect_actor_skill_changes(actor, actor_id)
	_disconnect_actor_life_changes(actor, actor_id)
	var bridge := _get_gecs_world()
	var record: Dictionary = bridge.call("get_population_record", actor_id) if bridge != null and bridge.has_method("get_population_record") else _get_actor_record_mutable(actor_id)
	if not record.is_empty():
		record = _merge_actor_state_into_record(record, actor, str(record.get("settlement_id", "")), {})
		record["realization_state"] = "ledger"
		record.erase("live_node_path")
		if actor is Node3D:
			record["last_world_transform"] = (actor as Node3D).global_transform
			record["last_world_transform_initialized"] = true
			record["last_world_position"] = (actor as Node3D).global_transform.origin
			record["last_world_position_initialized"] = true
		if bridge != null and bridge.has_method("update_population_realization"):
			bridge.call("update_population_realization", actor_id, "ledger", record.get("last_world_transform", Transform3D.IDENTITY), bool(record.get("last_world_transform_initialized", false)))
		_save_actor_record(actor_id, record)
	_live_actor_by_id.erase(actor_id)


func get_actor_record(actor_id: String) -> Dictionary:
	return _get_actor_record_mutable(actor_id).duplicate(true)


func update_actor_appearance(actor_id: String, appearance) -> Dictionary:
	if actor_id.strip_edges().is_empty() or appearance == null:
		return {}
	var record := _get_actor_record_mutable(actor_id)
	if record.is_empty():
		return {}
	var canonical_appearance = appearance.make_copy() if appearance.has_method("make_copy") else appearance
	_repair_non_rustdead_appearance(canonical_appearance, str(record.get("faction_id", "")))
	var serialized := _appearance_to_record(canonical_appearance)
	if serialized.is_empty():
		return {}
	record["appearance"] = serialized
	return _save_actor_record(actor_id, record)


func get_records_for_settlement(settlement_id: String) -> Array[Dictionary]:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("get_population_records_for_settlement"):
		var result: Array[Dictionary] = []
		result.assign(bridge.call("get_population_records_for_settlement", settlement_id))
		return result
	return []


func get_records_for_squad(squad_id: String) -> Array[Dictionary]:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("get_population_records_for_squad"):
		var result: Array[Dictionary] = []
		result.assign(bridge.call("get_population_records_for_squad", squad_id))
		return result
	return []


func get_live_actor(actor_id: String) -> Node:
	var actor = _live_actor_by_id.get(actor_id)
	if actor == null or not is_instance_valid(actor):
		_live_actor_by_id.erase(actor_id)
		return null
	return actor as Node


func update_actor_record(actor_id: String, updates: Dictionary) -> Dictionary:
	if actor_id.is_empty() or not _has_actor_record(actor_id):
		return {}
	var record: Dictionary = _get_actor_record_mutable(actor_id)
	for key in updates.keys():
		record[key] = updates[key]
	_save_actor_record(actor_id, record)
	return record.duplicate(true)


## Assignment claims only inspect the GECS settlement index. They never create population.
func claim_record_for_assignment(settlement_id: String, slot: Dictionary) -> Dictionary:
	var domain := str(slot.get("assignment_domain", "employment")).strip_edges().to_lower()
	var slot_id := str(slot.get("slot_id", "")).strip_edges()
	if settlement_id.is_empty() or domain.is_empty() or slot_id.is_empty():
		return {}
	var preferred_actor_id := str(slot.get("preferred_actor_id", "")).strip_edges()
	if not preferred_actor_id.is_empty():
		var preferred := get_actor_record(preferred_actor_id)
		if _eligible_for_assignment(preferred, settlement_id, domain, str(slot.get("assignment_exclusivity_group", "")), true):
			return assign_record_to_slot(preferred_actor_id, slot, true)
	var candidates := get_records_for_settlement(settlement_id)
	var best: Dictionary = {}
	var best_score := -INF
	for candidate in candidates:
		if not _eligible_for_assignment(candidate, settlement_id, domain, str(slot.get("assignment_exclusivity_group", ""))):
			continue
		var score := score_record_for_assignment(candidate, slot)
		var actor_id := str(candidate.get("actor_id", ""))
		if score > best_score or (score == best_score and actor_id < str(best.get("actor_id", "~"))):
			best = candidate
			best_score = score
	return assign_record_to_slot(str(best.get("actor_id", "")), slot) if not best.is_empty() else {}


## One dirty-town transaction: fetch the settlement's residents once, then
## bind every vacancy deterministically. A resident may hold different
## exclusivity groups (residence + one employment) but never two jobs.
func claim_records_for_assignments(settlement_id: String, slots: Array[Dictionary]) -> Dictionary:
	var claimed_by_slot_id := {}
	if settlement_id.is_empty() or slots.is_empty():
		return claimed_by_slot_id
	var candidates := get_records_for_settlement(settlement_id)
	var ordered_slots := slots.duplicate(true)
	ordered_slots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var priority_a := int(a.get("assignment_priority", 0))
		var priority_b := int(b.get("assignment_priority", 0))
		return priority_a > priority_b if priority_a != priority_b else str(a.get("slot_id", "")) < str(b.get("slot_id", "")))
	for slot in ordered_slots:
		var domain := str(slot.get("assignment_domain", "employment")).strip_edges().to_lower()
		var exclusivity_group := str(slot.get("assignment_exclusivity_group", ""))
		var preferred_actor_id := str(slot.get("preferred_actor_id", "")).strip_edges()
		var best_index := -1
		var best_score := -INF
		for index in candidates.size():
			var candidate: Dictionary = candidates[index]
			var actor_id := str(candidate.get("actor_id", ""))
			var is_preferred := actor_id == preferred_actor_id and not preferred_actor_id.is_empty()
			if not _eligible_for_assignment(candidate, settlement_id, domain, exclusivity_group, is_preferred):
				continue
			var score := score_record_for_assignment(candidate, slot)
			if actor_id == preferred_actor_id and not preferred_actor_id.is_empty():
				score += 1000000.0
			var wins_tie := best_index < 0 or actor_id < str((candidates[best_index] as Dictionary).get("actor_id", "~"))
			if score > best_score or (is_equal_approx(score, best_score) and wins_tie):
				best_index = index
				best_score = score
		if best_index < 0:
			continue
		var selected_actor_id := str((candidates[best_index] as Dictionary).get("actor_id", ""))
		var assigned := assign_record_to_slot(selected_actor_id, slot, selected_actor_id == preferred_actor_id and not preferred_actor_id.is_empty())
		if assigned.is_empty():
			continue
		candidates[best_index] = assigned
		claimed_by_slot_id[str(slot.get("slot_id", ""))] = assigned
	return claimed_by_slot_id


func score_record_for_assignment(record: Dictionary, slot: Dictionary) -> float:
	var score := 0.0
	var skill_id := str(slot.get("preferred_skill_id", "")).strip_edges()
	if not skill_id.is_empty():
		score += float((record.get("skill_levels", {}) as Dictionary).get(skill_id, SkillRules.DEFAULT_LEVEL)) * 100.0
	var preferred_type := str(slot.get("character_type_id", "")).strip_edges()
	if not preferred_type.is_empty() and str(record.get("character_type_id", "")) == preferred_type:
		score += 25.0
	if str(record.get("generation_source", "")).begins_with("assignment_auto"):
		score += 1.0
	return score


func assign_record_to_slot(actor_id: String, slot: Dictionary, allow_unavailable := false) -> Dictionary:
	var record := get_actor_record(actor_id)
	var settlement_id := str(slot.get("settlement_id", ""))
	var domain := str(slot.get("assignment_domain", "employment")).strip_edges().to_lower()
	var scope := str(slot.get("authority_scope", "")).strip_edges()
	var exclusivity_group := str(slot.get("assignment_exclusivity_group", "")).strip_edges()
	var assigned_actor_id := str(_actor_id_by_assignment_key.get(_assignment_index_key(settlement_id, domain, str(slot.get("slot_id", ""))), ""))
	if not assigned_actor_id.is_empty() and assigned_actor_id != actor_id:
		return {}
	if not _eligible_for_assignment(record, settlement_id, domain, exclusivity_group, allow_unavailable):
		return {}
	var assignments: Dictionary = (record.get("assignments", {}) as Dictionary).duplicate(true)
	var scopes: Dictionary = (record.get("assignment_authority_scopes", {}) as Dictionary).duplicate(true)
	var exclusivity_groups: Dictionary = (record.get("assignment_exclusivity_groups", {}) as Dictionary).duplicate(true)
	var realized: Dictionary = (record.get("assignment_realized_once", {}) as Dictionary).duplicate(true)
	assignments[domain] = str(slot.get("slot_id", ""))
	scopes[domain] = scope
	exclusivity_groups[domain] = exclusivity_group
	realized[domain] = false
	var updates := {
		"assignments": assignments,
		"assignment_authority_scopes": scopes,
		"assignment_exclusivity_groups": exclusivity_groups,
		"assignment_realized_once": realized,
	}
	if domain == "residence" and (not bool(record.get("last_world_position_initialized", false)) \
			or (str(record.get("generation_source", "")).begins_with("assignment_auto.residence") \
			and int(record.get("residence_spawn_revision", 0)) < RESIDENCE_SPAWN_REVISION)):
		var slot_position = slot.get("world_position", Vector3.INF)
		if slot_position is Vector3 and slot_position != Vector3.INF:
			var home_position: Vector3 = slot_position
			updates["last_world_position"] = home_position
			updates["last_world_position_initialized"] = true
			updates["last_world_transform"] = Transform3D(Basis.IDENTITY, home_position)
			updates["last_world_transform_initialized"] = true
			updates["residence_spawn_revision"] = RESIDENCE_SPAWN_REVISION
	if domain == "employment":
		updates["role_id"] = str(slot.get("role_id", "resident"))
		updates["movement_state"] = {}
	return update_actor_record(actor_id, updates)


func repair_residence_spawn_position(actor_id: String, slot: Dictionary) -> Dictionary:
	var record := get_actor_record(actor_id)
	if record.is_empty() or not str(record.get("generation_source", "")).begins_with("assignment_auto.residence") \
			or int(record.get("residence_spawn_revision", 0)) >= RESIDENCE_SPAWN_REVISION:
		return record
	var spawn_position = slot.get("world_position", Vector3.INF)
	if not (spawn_position is Vector3) or spawn_position == Vector3.INF:
		return record
	var spawn_transform := Transform3D(Basis.IDENTITY, spawn_position)
	var updated := update_actor_record(actor_id, {
		"last_world_position": spawn_position,
		"last_world_position_initialized": true,
		"last_world_transform": spawn_transform,
		"last_world_transform_initialized": true,
		"residence_spawn_revision": RESIDENCE_SPAWN_REVISION,
	})
	var actor := get_live_actor(actor_id)
	if actor != null and is_instance_valid(actor):
		actor.global_position = spawn_position
		if actor.has_method("stop_movement"):
			actor.call("stop_movement")
		update_realized_actor_transform(actor_id, actor.global_transform)
	return updated


func get_record_assigned_to_slot(settlement_id: String, assignment_domain: String, slot_id: String) -> Dictionary:
	var actor_id := str(_actor_id_by_assignment_key.get(_assignment_index_key(settlement_id, assignment_domain, slot_id), ""))
	return get_actor_record(actor_id) if not actor_id.is_empty() else {}


func release_assignment(settlement_id: String, assignment_domain: String, slot_id: String) -> Dictionary:
	var record := get_record_assigned_to_slot(settlement_id, assignment_domain, slot_id)
	if record.is_empty():
		return {}
	return release_actor_assignment(str(record.get("actor_id", "")), assignment_domain)


func release_actor_assignment(actor_id: String, assignment_domain: String) -> Dictionary:
	var record := get_actor_record(actor_id)
	if record.is_empty():
		return {}
	var assignments: Dictionary = (record.get("assignments", {}) as Dictionary).duplicate(true)
	var scopes: Dictionary = (record.get("assignment_authority_scopes", {}) as Dictionary).duplicate(true)
	var exclusivity_groups: Dictionary = (record.get("assignment_exclusivity_groups", {}) as Dictionary).duplicate(true)
	var realized: Dictionary = (record.get("assignment_realized_once", {}) as Dictionary).duplicate(true)
	assignments.erase(assignment_domain)
	scopes.erase(assignment_domain)
	exclusivity_groups.erase(assignment_domain)
	realized.erase(assignment_domain)
	var updates := {"assignments": assignments, "assignment_authority_scopes": scopes, "assignment_exclusivity_groups": exclusivity_groups, "assignment_realized_once": realized}
	if assignment_domain == "employment":
		updates["role_id"] = "resident"
		updates["movement_state"] = {}
	return update_actor_record(actor_id, updates)


func release_all_actor_assignments(actor_id: String) -> Dictionary:
	var record := get_actor_record(actor_id)
	if record.is_empty():
		return {}
	return update_actor_record(actor_id, {
		"assignments": {},
		"assignment_authority_scopes": {},
		"assignment_exclusivity_groups": {},
		"assignment_realized_once": {},
		"role_id": "resident" if int(record.get("life_state", NpcRules.LifeState.ALIVE)) != NpcRules.LifeState.DEAD else str(record.get("role_id", "resident")),
		"movement_state": {},
	})


func _eligible_for_assignment(record: Dictionary, settlement_id: String, domain: String, exclusivity_group: String, allow_unavailable := false) -> bool:
	if record.is_empty() or str(record.get("settlement_id", "")) != settlement_id:
		return false
	if int(record.get("life_state", NpcRules.LifeState.ALIVE)) == NpcRules.LifeState.DEAD:
		return false
	if domain == "employment" and not allow_unavailable and not _available_for_automatic_work(record):
		return false
	if not str((record.get("assignments", {}) as Dictionary).get(domain, "")).is_empty():
		return false
	if domain == "employment" and not ["resident", "civilian"].has(str(record.get("role_id", "resident"))):
		return false
	if not exclusivity_group.is_empty() and (record.get("assignment_exclusivity_groups", {}) as Dictionary).values().has(exclusivity_group):
		return false
	if not str(record.get("party_id", "")).strip_edges().is_empty():
		return false
	var live_actor := get_live_actor(str(record.get("actor_id", "")))
	return live_actor == null or not live_actor.has_method("is_player_party_member") or not bool(live_actor.call("is_player_party_member"))


func _available_for_automatic_work(record: Dictionary) -> bool:
	if record.has("available_for_work"):
		return bool(record.get("available_for_work", false))
	var source := str(record.get("generation_source", ""))
	return source == "census" or source.begins_with("assignment_auto")


## A bound staff body died — mark its record dead and free the slot binding so the world sim
## opens a vacancy and assigns a replacement. The dead record keeps its staff role (it is not
## reclaimable: claims require a living "resident") so it won't be re-promoted.
func mark_record_dead(actor_id: String, actor: Node = null, corpse_transform_override: Variant = null) -> void:
	if actor_id.strip_edges().is_empty() or not _has_actor_record(actor_id):
		return
	if actor == null:
		actor = _live_actor_by_id.get(actor_id)
	var record := (actor_records.get(actor_id, {}) as Dictionary).duplicate(true)
	var was_dead := int(record.get("life_state", NpcRules.LifeState.ALIVE)) == NpcRules.LifeState.DEAD and str(record.get("body_state", "")) == "corpse"
	var corpse_transform: Transform3D = record.get("last_world_transform", Transform3D.IDENTITY)
	if corpse_transform_override is Transform3D:
		corpse_transform = corpse_transform_override
	elif actor is Node3D and is_instance_valid(actor):
		corpse_transform = (actor as Node3D).global_transform
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("update_population_death"):
		bridge.call("update_population_death", actor_id, actor, corpse_transform)
		if bridge.has_method("get_population_record"):
			var durable_record: Dictionary = bridge.call("get_population_record", actor_id)
			if not durable_record.is_empty():
				record = durable_record
	record["life_state"] = NpcRules.LifeState.DEAD
	record["body_state"] = "corpse"
	record["body_container_id"] = ""
	record["assignments"] = {}
	record["assignment_authority_scopes"] = {}
	record["assignment_exclusivity_groups"] = {}
	record["assignment_realized_once"] = {}
	record["last_world_position"] = corpse_transform.origin
	record["last_world_position_initialized"] = true
	record["last_world_transform"] = corpse_transform
	record["last_world_transform_initialized"] = true
	_save_actor_record(actor_id, record)
	if actor != null and is_instance_valid(actor) and int(actor.get("life_state")) != NpcRules.LifeState.DEAD:
		actor.set("life_state", NpcRules.LifeState.DEAD)
	if not was_dead:
		dead_projection_registered.emit(actor_id)
		person_died.emit(actor_id)


func apply_offscreen_squad_casualties(squad_id: String, survivor_count: int, world_position: Vector3) -> void:
	var living_records: Array[Dictionary] = []
	for record in get_records_for_squad(squad_id):
		if str(record.get("squad_name", "")) == squad_id and int(record.get("life_state", NpcRules.LifeState.ALIVE)) != NpcRules.LifeState.DEAD:
			living_records.append(record)
	living_records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("actor_id", "")) < str(b.get("actor_id", "")))
	var survivors := clampi(survivor_count, 0, living_records.size())
	for index in range(survivors, living_records.size()):
		var actor_id := str(living_records[index].get("actor_id", ""))
		var hash_value := absi(hash(actor_id))
		var angle := TAU * float(hash_value % 360) / 360.0
		var radius := 0.75 + float((hash_value / 360) % 100) / 100.0
		var corpse_position := world_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		mark_record_dead(actor_id, null, Transform3D(Basis(), corpse_position))


func apply_offscreen_squad_captures(squad_id: String, captured_count: int, settlement_id: String, world_position: Vector3) -> Array[String]:
	var captured_actor_ids: Array[String] = []
	var living_records: Array[Dictionary] = []
	for record in get_records_for_squad(squad_id):
		if int(record.get("life_state", NpcRules.LifeState.ALIVE)) != NpcRules.LifeState.DEAD:
			living_records.append(record)
	living_records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("actor_id", "")) < str(b.get("actor_id", "")))
	var count := mini(maxi(captured_count, 0), living_records.size())
	for index in range(living_records.size() - count, living_records.size()):
		var actor_id := str(living_records[index].get("actor_id", ""))
		captured_actor_ids.append(actor_id)
		update_actor_record(actor_id, {
			"settlement_id": settlement_id,
			"role_id": "prisoner",
			"squad_name": "",
			"assignments": {},
			"assignment_authority_scopes": {},
			"assignment_exclusivity_groups": {},
			"assignment_realized_once": {},
			"last_world_position": world_position,
			"last_world_position_initialized": true,
			"last_world_transform": Transform3D(Basis(), world_position),
			"last_world_transform_initialized": true,
		})
	return captured_actor_ids


func is_record_alive(actor_id: String) -> bool:
	if actor_id.strip_edges().is_empty():
		return false
	var record := _get_actor_record_mutable(actor_id)
	if record.is_empty():
		return false
	return int(record.get("life_state", 0)) != NpcRules.LifeState.DEAD


func get_population_summary() -> Dictionary:
	_refresh_actor_records_cache()
	var summary := {
		"total_records": actor_records.size(),
		"realized_records": 0,
		"ledger_records": 0,
		"by_settlement": {},
		"by_role": {},
	}
	for actor_id in actor_records.keys():
		var record: Dictionary = actor_records[actor_id]
		var state := str(record.get("realization_state", "ledger"))
		if state == "realized":
			summary["realized_records"] = int(summary["realized_records"]) + 1
		else:
			summary["ledger_records"] = int(summary["ledger_records"]) + 1
		_increment_count(summary["by_settlement"], str(record.get("settlement_id", "world")))
		_increment_count(summary["by_role"], str(record.get("role_id", "resident")))
	return summary


func ensure_generated_population(settlement_id: String, spawner_id: String, desired_count: int, context: Dictionary = {}) -> Array[Dictionary]:
	if settlement_id.is_empty() or spawner_id.is_empty():
		return []
	desired_count = max(0, desired_count)
	var role_id := str(context.get("role_id", "resident"))
	var all_records: Array[Dictionary] = _get_generated_records(settlement_id, spawner_id, role_id)
	var records: Array[Dictionary] = []
	for record in all_records:
		if int(record.get("life_state", NpcRules.LifeState.ALIVE)) != NpcRules.LifeState.DEAD:
			records.append(record)
	var start_index: int = max(0, int(context.get("start_index", 0)))
	var next_generation_index: int = _next_generation_index(settlement_id, spawner_id, start_index)
	var used_names := _collect_used_names(settlement_id)
	var current_actor_ids := {}
	for record in records:
		current_actor_ids[str(record.get("actor_id", ""))] = true
	var known_ages: Array[int] = []
	var missing_external_records: Array[Dictionary] = []
	var external_population_count := 0
	for external_record in get_records_for_settlement(settlement_id):
		if current_actor_ids.has(str(external_record.get("actor_id", ""))) or int(external_record.get("life_state", NpcRules.LifeState.ALIVE)) == NpcRules.LifeState.DEAD:
			continue
		external_population_count += 1
		var external_birth_day := int(external_record.get("birth_day_index", CharacterAgeRules.UNKNOWN_BIRTH_DAY))
		if external_birth_day == CharacterAgeRules.UNKNOWN_BIRTH_DAY:
			missing_external_records.append(external_record)
		else:
			known_ages.append(CharacterAgeRules.age_years(external_birth_day, _current_world_day()))
	var missing_existing_indices: Array[int] = []
	for index in range(mini(records.size(), desired_count)):
		var birth_day := int(records[index].get("birth_day_index", CharacterAgeRules.UNKNOWN_BIRTH_DAY))
		if birth_day == CharacterAgeRules.UNKNOWN_BIRTH_DAY:
			missing_existing_indices.append(index)
		else:
			known_ages.append(CharacterAgeRules.age_years(birth_day, _current_world_day()))
	var age_rng := _make_rng("%s:%s" % [settlement_id, spawner_id], "age_cohort", int(context.get("generation_seed", 0)))
	var missing_ages := CharacterAgeRules.generate_missing_ages(external_population_count + desired_count, known_ages, age_rng)
	for missing_external_record in missing_external_records:
		if missing_ages.is_empty():
			break
		missing_external_record["birth_day_index"] = CharacterAgeRules.birth_day_for_age(missing_ages.pop_back(), _current_world_day(), age_rng)
		_save_actor_record(str(missing_external_record.get("actor_id", "")), missing_external_record)
	for record_index in missing_existing_indices:
		if missing_ages.is_empty():
			break
		var migrated_record := records[record_index]
		migrated_record["birth_day_index"] = CharacterAgeRules.birth_day_for_age(missing_ages.pop_back(), _current_world_day(), age_rng)
		records[record_index] = _save_actor_record(str(migrated_record.get("actor_id", "")), migrated_record)
	while records.size() < desired_count:
		var generation_index: int = next_generation_index
		next_generation_index += 1
		var generation_context := context.duplicate(true)
		generation_context["generated_age_years"] = missing_ages.pop_back() if not missing_ages.is_empty() else CharacterAgeRules.DEFAULT_ADULT_AGE
		var record: Dictionary = _create_generated_actor_record(settlement_id, spawner_id, generation_index, generation_context, used_names)
		if record.is_empty():
			break
		_save_actor_record(str(record["actor_id"]), record)
		records.append(record.duplicate(true))
		var display_name := str(record.get("member_name", "")).strip_edges()
		if not display_name.is_empty():
			used_names[display_name.to_lower()] = true
	return records.slice(0, desired_count)


## Mints one record with authored overrides (member_name, role_id, skills…)
## on top of the generated baseline — the seeding path for a settlement's
## hand-authored residents. Idempotent per (settlement, spawner, index).
func ensure_authored_record(settlement_id: String, spawner_id: String, generation_index: int, context: Dictionary, overrides: Dictionary) -> Dictionary:
	if settlement_id.is_empty() or spawner_id.is_empty():
		return {}
	var existing := _get_generated_records(settlement_id, spawner_id)
	for record in existing:
		if int(record.get("generation_index", 0)) == generation_index:
			return record
	var created := _create_generated_actor_record(settlement_id, spawner_id, generation_index, context, _collect_used_names(settlement_id))
	created["available_for_work"] = false
	for key in overrides:
		var value = overrides[key]
		if value == null:
			continue
		if value is String and (value as String).strip_edges().is_empty():
			continue
		if (value is Dictionary and (value as Dictionary).is_empty()) or (value is Array and (value as Array).is_empty()):
			continue
		created[key] = value
	return _save_actor_record(str(created["actor_id"]), created)


func ensure_preferred_assignment_record(settlement_id: String, slot: Dictionary, context: Dictionary) -> Dictionary:
	var actor_id := str(slot.get("preferred_actor_id", "")).strip_edges()
	var character_path := str(slot.get("preferred_character_path", "")).strip_edges()
	var definition := load(character_path) if not character_path.is_empty() else null
	var authored: Dictionary = definition.call("to_record") if definition != null and definition.has_method("to_record") else {}
	actor_id = str(authored.get("actor_id", actor_id)).strip_edges()
	if actor_id.is_empty():
		return {}
	var existing := get_actor_record(actor_id)
	if not existing.is_empty():
		if str(existing.get("settlement_id", "")) != settlement_id:
			assignment_error.emit("duplicate_named_actor", actor_id, PackedStringArray([str(existing.get("settlement_id", "")), settlement_id]))
			return {}
		return existing
	var created := _create_generated_actor_record(settlement_id, "assignment_preferred.%s" % _sanitize_id(str(slot.get("slot_id", ""))), 1, context, _collect_used_names(settlement_id))
	if created.is_empty():
		return {}
	for key in authored.keys():
		created[key] = authored[key]
	created["actor_id"] = actor_id
	created["stable_id"] = actor_id
	created["settlement_id"] = settlement_id
	created["generation_source"] = "assignment_preferred"
	created["role_id"] = "resident"
	created["available_for_work"] = bool(authored.get("available_for_work", false))
	return _save_actor_record(actor_id, created)


func ensure_assignment_filler_record(settlement_id: String, slot: Dictionary, context: Dictionary) -> Dictionary:
	var domain := _sanitize_id(str(slot.get("assignment_domain", "employment")))
	var slot_id := _sanitize_id(str(slot.get("slot_id", "")))
	var actor_id := "%s.assignment_auto.%s.%s" % [_sanitize_id(settlement_id), domain, slot_id]
	var existing := get_actor_record(actor_id)
	if not existing.is_empty():
		return existing
	var created := _create_generated_actor_record(settlement_id, "assignment_auto.%s.%s" % [domain, slot_id], 1, context, _collect_used_names(settlement_id))
	if created.is_empty():
		return {}
	created["actor_id"] = actor_id
	created["stable_id"] = actor_id
	created["generation_source"] = "assignment_auto"
	created["role_id"] = "resident"
	created["available_for_work"] = true
	return _save_actor_record(actor_id, created)


## Census-seeded surplus residents (alive, still role "resident"). Population
## spawners realize these instead of minting a parallel record namespace, so
## the ambient crowd IS the census.
func get_seeded_resident_records(settlement_id: String) -> Array[Dictionary]:
	_refresh_actor_records_cache()
	var records: Array[Dictionary] = []
	for actor_id in actor_records.keys():
		var record: Dictionary = actor_records[actor_id]
		if str(record.get("settlement_id", "")) != settlement_id:
			continue
		var source := str(record.get("generation_source", ""))
		if source != "census" and source != "census_authored":
			continue
		if str(record.get("role_id", "resident")) != "resident":
			continue
		if int(record.get("life_state", 0)) == NpcRules.LifeState.DEAD:
			continue
		records.append(record.duplicate(true))
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("generation_index", 0)) < int(b.get("generation_index", 0)))
	return records


func count_alive_records_for_settlement(settlement_id: String) -> int:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("count_alive_population_records_for_settlement"):
		return int(bridge.call("count_alive_population_records_for_settlement", settlement_id))
	return 0


func set_person_body_state(actor_id: String, body_state: String, body_container_id := "", destroy_items := false) -> Dictionary:
	if actor_id.is_empty() or body_state.is_empty():
		return {}
	var updates := {
		"body_state": body_state,
		"body_container_id": body_container_id,
		"realization_state": "ledger",
	}
	if destroy_items:
		updates["inventory_entries"] = []
		updates["equipment_slots"] = {}
	var saved := update_actor_record(actor_id, updates)
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("update_population_body_state"):
		bridge.call("update_population_body_state", actor_id, body_state, body_container_id)
	return saved


func apply_record_to_actor(actor: Node, record: Dictionary) -> void:
	if actor == null or record.is_empty():
		return
	var actor_id := str(record.get("actor_id", ""))
	if not actor_id.is_empty():
		actor.set("stable_id", actor_id)
		actor.set_meta("actor_record_id", actor_id)
	actor.set("member_name", str(record.get("member_name", actor.get("member_name"))))
	var faction_id := str(record.get("faction_id", actor.get("faction_name")))
	actor.set("faction_name", faction_id)
	var party_id := str(record.get("party_id", "")).strip_edges()
	var is_player_party := party_id == PartyManager.PLAYER_PARTY_ID
	var party_manager := root_scene.get_node_or_null("PartyManager") as PartyManager if root_scene != null else null
	if not is_player_party and actor is WorldActor and party_manager != null and party_manager.party_members.has(actor as WorldActor):
		party_manager.unregister_party_member(actor as WorldActor)
	if party_id.is_empty():
		actor.remove_meta("party_id")
	else:
		actor.set_meta("party_id", party_id)
	if actor.has_method("set_player_party_member"):
		actor.call("set_player_party_member", is_player_party)
	if is_player_party and actor is WorldActor:
		if party_manager != null:
			party_manager.register_party_member(actor as WorldActor)
	elif not party_id.is_empty():
		update_actor_record(actor_id, {"party_id": party_id})
	actor.set("squad_name", str(record.get("squad_name", actor.get("squad_name"))))
	actor.set("hostile_factions", PackedStringArray(record.get("hostile_faction_ids", [])))
	actor.set("combat_stance", int(record.get("combat_stance", actor.get("combat_stance"))))
	actor.set("auto_heal_enabled", bool(record.get("auto_heal_enabled", actor.get("auto_heal_enabled"))))
	actor.set("auto_burn_rustdead_enabled", bool(record.get("auto_burn_rustdead_enabled", actor.get("auto_burn_rustdead_enabled"))))
	actor.set("life_state", int(record.get("life_state", actor.get("life_state"))))
	if record.has("conversation_definition_path") and actor.has_method("get_conversation_definition"):
		actor.set("conversation_definition", _load_resource(str(record.get("conversation_definition_path", ""))))
	actor.set("starting_skill_levels", record.get("skill_levels", {}))
	var age_years := CharacterAgeRules.age_years(int(record.get("birth_day_index", CharacterAgeRules.UNKNOWN_BIRTH_DAY)), _current_world_day())
	actor.set_meta("population_birth_day_index", int(record.get("birth_day_index", CharacterAgeRules.UNKNOWN_BIRTH_DAY)))
	actor.set_meta("population_age_years", age_years)
	actor.set_meta("settlement_id", str(record.get("settlement_id", "")))
	actor.set_meta("actor_role_id", str(record.get("role_id", "resident")))
	actor.set_meta("population_inventory_entries", Array(record.get("inventory_entries", [])).duplicate(true))
	if record.has("base_color"):
		actor.set("base_color", record.get("base_color"))
	actor.set_meta("population_needs_state", (record.get("needs_state", {}) as Dictionary).duplicate(true))
	actor.set_meta("population_movement_state", (record.get("movement_state", {}) as Dictionary).duplicate(true))
	if actor.is_inside_tree() and actor.has_method("apply_population_runtime_state"):
		actor.call("apply_population_runtime_state", record.get("needs_state", {}), record.get("movement_state", {}))
	var appearance = appearance_from_record(record.get("appearance", {}) as Dictionary)
	if appearance != null:
		appearance.visual_age_years = age_years
		appearance.visual_toughness_level = int((record.get("skill_levels", {}) as Dictionary).get(SkillRules.ATTRIBUTE_TOUGHNESS, SkillRules.DEFAULT_LEVEL))
		_repair_non_rustdead_appearance(appearance, faction_id)
		actor.set("character_race", appearance.character_race)
		actor.set("body_archetype", appearance.body_archetype)
		actor.set("visual_body_type", appearance.visual_body_type)
		if actor.is_inside_tree() and actor.has_method("apply_appearance_data"):
			actor.call("apply_appearance_data", appearance)
		else:
			actor.set("appearance_data", appearance)
	var starting_equipment: Array[Resource] = []
	var equipment_slots: Dictionary = record.get("equipment_slots", {})
	for slot in equipment_slots.keys():
		var item := _load_resource(str(equipment_slots[slot]))
		if item != null:
			starting_equipment.append(item)
	actor.set("starting_equipment", starting_equipment)
	actor.set_meta("population_character_realizer_id", str(record.get("character_realizer_id", "")))
	actor.set_meta("population_character_type_id", str(record.get("character_type_id", "")))
	if actor.is_inside_tree():
		var stats = actor.call("get_stats") if actor.has_method("get_stats") else null
		if stats != null and stats.has_method("hydrate_skill_progress"):
			stats.call("hydrate_skill_progress", record.get("skill_levels", {}), record.get("skill_xp", {}))
		var inventory = actor.call("get_inventory") if actor.has_method("get_inventory") else null
		if inventory != null and inventory.has_method("hydrate_population_entries"):
			inventory.call("hydrate_population_entries", record.get("inventory_entries", []), false)
		var equipment = actor.call("get_equipment") if actor.has_method("get_equipment") else null
		var gecs := _get_gecs_world()
		if equipment != null and equipment.has_method("hydrate_gecs_slots") and gecs != null:
			equipment.call("hydrate_gecs_slots", gecs.call("get_equipment_slots", actor_id), true)
		elif inventory != null:
			inventory.inventory_changed.emit()


func ensure_record_character_realizer(actor_id: String, realizer: Resource, name_profile: Resource = null) -> Dictionary:
	if actor_id.strip_edges().is_empty() or realizer == null:
		return {}
	var realizer_id := str(realizer.get("profile_id")).strip_edges()
	var actor_script := realizer.get("actor_script") as Script
	if realizer_id.is_empty() or actor_script == null or not realizer.has_method("create_appearance"):
		push_error("Population record realizer rejected: actor=%s profile=%s" % [actor_id, realizer.resource_path])
		return {}
	var record := _get_actor_record_mutable(actor_id)
	if record.is_empty():
		return {}
	var appearance_record: Dictionary = record.get("appearance", {})
	var realizer_signature := _realization_signature(realizer)
	if str(record.get("character_realizer_signature", "")) == realizer_signature and not appearance_record.is_empty():
		return record.duplicate(true)
	var realizer_changed := str(record.get("character_realizer_id", "")) != realizer_id
	var initialize_appearance := appearance_record.is_empty() or realizer_changed
	var appearance = realizer.call("create_appearance", _make_rng(actor_id, "appearance", 0)) if initialize_appearance else appearance_from_record(appearance_record)
	if initialize_appearance:
		appearance_record = _appearance_to_record(appearance)
		if appearance == null or appearance_record.is_empty():
			push_error("Population record realizer produced no appearance: actor=%s realizer=%s" % [actor_id, realizer_id])
			return {}
		record["appearance"] = appearance_record
		var equipment_slots: Dictionary = (record.get("equipment_slots", {}) as Dictionary).duplicate(true)
		if realizer_changed:
			for clothing_slot in ["chest", "legs", "feet", "head"]:
				equipment_slots.erase(clothing_slot)
		var generated_equipment := _generate_equipment_slots(realizer, {}, actor_id)
		for slot in generated_equipment:
			if not equipment_slots.has(slot):
				equipment_slots[slot] = generated_equipment[slot]
		record["equipment_slots"] = equipment_slots
	record["character_realizer_id"] = realizer_id
	record["character_realizer_path"] = realizer.resource_path
	record["character_realizer_signature"] = realizer_signature
	var member_name := str(record.get("member_name", "")).strip_edges()
	if (member_name.is_empty() or member_name == "Character") and name_profile != null and name_profile.has_method("generate_name"):
		var body_type := int(appearance.visual_body_type)
		record["member_name"] = str(name_profile.call("generate_name", body_type, _make_rng(actor_id, "name", 0), _collect_used_names(str(record.get("settlement_id", ""))))).strip_edges()
	_save_actor_record(actor_id, record)
	return record.duplicate(true)


func ensure_record_character_type(actor_id: String, character_type: Resource) -> Dictionary:
	if actor_id.strip_edges().is_empty() or character_type == null:
		return {}
	var type_id := str(character_type.get("type_id")).strip_edges().to_lower()
	if type_id.is_empty():
		return {}
	var record := _get_actor_record_mutable(actor_id)
	if record.is_empty():
		return {}
	var signature := _realization_signature(character_type)
	if str(record.get("character_type_signature", "")) == signature:
		return record.duplicate(true)
	var equipment_slots: Dictionary = (record.get("equipment_slots", {}) as Dictionary).duplicate(true)
	var inventory_entries: Array = Array(record.get("inventory_entries", [])).duplicate(true)
	for item in character_type.get("starting_equipment") as Array:
		if item == null:
			continue
		var equip_slot := str(item.get("equip_slot")).strip_edges()
		if not equip_slot.is_empty():
			if not equipment_slots.has(equip_slot):
				equipment_slots[equip_slot] = item.resource_path
			continue
		_add_character_type_inventory_item(inventory_entries, item, actor_id, type_id)
	record["equipment_slots"] = equipment_slots
	record["inventory_entries"] = inventory_entries
	record["character_type_id"] = type_id
	record["character_type_path"] = character_type.resource_path
	record["character_type_signature"] = signature
	_save_actor_record(actor_id, record)
	return record.duplicate(true)


func mark_actor_realized(actor: Node, actor_id := "") -> void:
	if actor == null:
		return
	if actor_id.is_empty():
		actor_id = _actor_record_id(actor)
	if actor_id.is_empty():
		return
	actor.set("stable_id", actor_id)
	actor.set_meta("actor_record_id", actor_id)
	_live_actor_by_id[actor_id] = actor
	_connect_actor_skill_changes(actor, actor_id)
	var record: Dictionary = _get_actor_record_mutable(actor_id)
	if not record.is_empty():
		record["realization_state"] = "realized"
		if actor is Node3D and actor.is_inside_tree():
			record["last_world_transform"] = (actor as Node3D).global_transform
			record["last_world_transform_initialized"] = true
			record["last_world_position"] = (actor as Node3D).global_transform.origin
			record["last_world_position_initialized"] = true
		actor_records[actor_id] = record
		var realization_bridge := _get_gecs_world()
		if realization_bridge != null and realization_bridge.has_method("update_population_realization"):
			realization_bridge.call("update_population_realization", actor_id, "realized", record.get("last_world_transform", Transform3D.IDENTITY), bool(record.get("last_world_transform_initialized", false)))
	actor.set_meta("settlement_id", str(record.get("settlement_id", "")))
	actor.set_meta("actor_role_id", str(record.get("role_id", "resident")))
	_register_actor_with_query_controller(actor)
	var equipment = actor.call("get_equipment") if actor.has_method("get_equipment") else null
	var gecs := _get_gecs_world()
	if equipment != null and equipment.has_method("hydrate_gecs_slots") and gecs != null:
		equipment.call("hydrate_gecs_slots", gecs.call("get_equipment_slots", actor_id))


func update_realized_actor_transform(actor_id: String, world_transform: Transform3D) -> void:
	var record := _get_actor_record_mutable(actor_id)
	if record.is_empty():
		return
	record["last_world_transform"] = world_transform
	record["last_world_transform_initialized"] = true
	record["last_world_position"] = world_transform.origin
	record["last_world_position_initialized"] = true
	actor_records[actor_id] = record
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("update_population_realization"):
		bridge.call("update_population_realization", actor_id, str(record.get("realization_state", "realized")), world_transform, true)


func advance_ledger_minutes(minutes: int, absolute_minute := -1) -> Dictionary:
	_refresh_actor_records_cache()
	var summary := {"elapsed_minutes": max(0, minutes), "updated_actor_count": 0, "batches": {}}
	if minutes <= 0:
		return summary
	for actor_id in actor_records.keys():
		var record: Dictionary = actor_records[actor_id]
		var activity := _ledger_activity_for_record(record, absolute_minute)
		if str(record.get("realization_state", "ledger")) == "realized":
			if str(record.get("ledger_activity_state", "")) != activity:
				record["ledger_activity_state"] = activity
				record["last_ledger_absolute_minute"] = absolute_minute
				actor_records[actor_id] = record
				var realized_bridge := _get_gecs_world()
				if realized_bridge != null and realized_bridge.has_method("update_population_ledger_state"):
					realized_bridge.call("update_population_ledger_state", str(actor_id), record)
			continue
		record["ledger_minutes_elapsed"] = int(record.get("ledger_minutes_elapsed", 0)) + minutes
		record["ledger_activity_state"] = activity
		record["last_ledger_absolute_minute"] = absolute_minute
		var activity_minutes: Dictionary = record.get("ledger_activity_minutes", {})
		activity_minutes[activity] = int(activity_minutes.get(activity, 0)) + minutes
		record["ledger_activity_minutes"] = activity_minutes
		if activity == "working":
			record["ledger_work_minutes"] = int(record.get("ledger_work_minutes", 0)) + minutes
		elif activity == "resting":
			record["ledger_rest_minutes"] = int(record.get("ledger_rest_minutes", 0)) + minutes
		actor_records[actor_id] = record
		var bridge := _get_gecs_world()
		if bridge != null and bridge.has_method("update_population_ledger_state"):
			bridge.call("update_population_ledger_state", str(actor_id), record)
		summary["updated_actor_count"] = int(summary["updated_actor_count"]) + 1
		var batch_key := "%s:%s:%s" % [str(record.get("settlement_id", "world")), str(record.get("role_id", "resident")), activity]
		var batches: Dictionary = summary["batches"]
		var batch: Dictionary = batches.get(batch_key, {"settlement_id": str(record.get("settlement_id", "world")), "role_id": str(record.get("role_id", "resident")), "activity": activity, "actor_count": 0, "actor_minutes": 0})
		batch["actor_count"] = int(batch.get("actor_count", 0)) + 1
		batch["actor_minutes"] = int(batch.get("actor_minutes", 0)) + minutes
		batches[batch_key] = batch
		summary["batches"] = batches
	return summary


func serialize_state() -> Dictionary:
	_sync_live_corpse_transforms()
	_refresh_actor_records_cache()
	var records := {}
	for actor_id in actor_records.keys():
		var record: Dictionary = (actor_records[actor_id] as Dictionary).duplicate(true)
		record.erase("live_node_path")
		records[actor_id] = record
	return {"actor_records": records}


func apply_serialized_state(state: Dictionary) -> void:
	if state.is_empty() or not state.has("actor_records"):
		refresh_from_gecs_state()
		return
	_clear_population_records_for_load()
	actor_records.clear()
	_actor_id_by_assignment_key.clear()
	_disconnect_all_actor_skill_changes()
	_live_actor_by_id.clear()
	var records: Dictionary = state.get("actor_records", {})
	var migrated_records := {}
	for actor_id in records.keys():
		if records[actor_id] is Dictionary:
			var record: Dictionary = (records[actor_id] as Dictionary).duplicate(true)
			_migrate_legacy_assignment_record(record)
			record.erase("live_node_path")
			if str(record.get("realization_state", "ledger")) == "realized":
				record["realization_state"] = "ledger"
			migrated_records[str(actor_id)] = record
	_migrate_serialized_birth_days(migrated_records)
	var migrated_actor_ids: Array = migrated_records.keys()
	migrated_actor_ids.sort()
	for actor_id_value in migrated_actor_ids:
		_save_actor_record(str(actor_id_value), migrated_records[actor_id_value] as Dictionary)


func _migrate_serialized_birth_days(records: Dictionary) -> void:
	var actor_ids_by_settlement := {}
	for actor_id_value in records.keys():
		var actor_id := str(actor_id_value)
		var record: Dictionary = records[actor_id]
		if CharacterAgeRules.has_birth_day(record):
			continue
		var settlement_id := str(record.get("settlement_id", "world")).strip_edges()
		if settlement_id.is_empty():
			settlement_id = "world"
		var actor_ids: Array = actor_ids_by_settlement.get(settlement_id, [])
		actor_ids.append(actor_id)
		actor_ids_by_settlement[settlement_id] = actor_ids
	var settlement_ids: Array = actor_ids_by_settlement.keys()
	settlement_ids.sort()
	for settlement_id_value in settlement_ids:
		var settlement_id := str(settlement_id_value)
		var all_settlement_records: Array[Dictionary] = []
		var known_ages: Array[int] = []
		for record_value in records.values():
			var record := record_value as Dictionary
			if str(record.get("settlement_id", "world")) != settlement_id:
				continue
			all_settlement_records.append(record)
			if CharacterAgeRules.has_birth_day(record):
				known_ages.append(CharacterAgeRules.age_years(int(record.get("birth_day_index")), _current_world_day()))
		var rng := _make_rng(settlement_id, "birth_day_migration", all_settlement_records.size())
		var missing_ages := CharacterAgeRules.generate_missing_ages(all_settlement_records.size(), known_ages, rng)
		var missing_actor_ids: Array = actor_ids_by_settlement[settlement_id]
		missing_actor_ids.sort()
		for actor_id_value in missing_actor_ids:
			var actor_id := str(actor_id_value)
			var age_years: int = int(missing_ages.pop_back()) if not missing_ages.is_empty() else CharacterAgeRules.DEFAULT_ADULT_AGE
			var record: Dictionary = records[actor_id]
			record["birth_day_index"] = CharacterAgeRules.birth_day_for_age(age_years, _current_world_day(), rng)


func _migrate_legacy_assignment_record(record: Dictionary) -> void:
	var legacy_slot := str(record.get("assigned_slot_id", "")).strip_edges()
	if not legacy_slot.is_empty():
		var assignments: Dictionary = (record.get("assignments", {}) as Dictionary).duplicate(true)
		assignments["employment"] = legacy_slot
		record["assignments"] = assignments
		var realized: Dictionary = (record.get("assignment_realized_once", {}) as Dictionary).duplicate(true)
		realized["employment"] = bool(record.get("staff_assignment_realized_once", false))
		record["assignment_realized_once"] = realized
	record.erase("assigned_slot_id")
	record.erase("staff_assignment_realized_once")


func refresh_from_gecs_state() -> void:
	_refresh_actor_records_cache()


func sync_population_state() -> void:
	_sync_live_corpse_transforms()
	for actor_id_value in _live_actor_by_id.keys():
		var actor = _live_actor_by_id.get(actor_id_value)
		if actor == null or not is_instance_valid(actor):
			_live_actor_by_id.erase(actor_id_value)
	_refresh_actor_records_cache()


func _on_world_reindexed() -> void:
	_refresh_actor_records_cache()
	_hydrate_live_actors_from_gecs.call_deferred()


func _on_population_life_state_changed(actor_id: String, _previous_state: int, next_state: int) -> void:
	var record := get_actor_record(actor_id)
	if not record.is_empty():
		actor_records[actor_id] = record
		population_record_changed.emit(str(record.get("settlement_id", "")), actor_id)
	if next_state == NpcRules.LifeState.DEAD:
		person_died.emit(actor_id)


func _on_party_membership_changed(member: WorldActor, party_id: String) -> void:
	if member == null:
		return
	var actor_id := _actor_record_id(member)
	if actor_id.is_empty() or get_actor_record(actor_id).is_empty():
		return
	update_actor_record(actor_id, {"party_id": party_id.strip_edges()})


func _hydrate_live_actors_from_gecs() -> void:
	for actor_id_value in _live_actor_by_id.keys():
		var actor = _live_actor_by_id.get(actor_id_value)
		if actor == null or not is_instance_valid(actor):
			_live_actor_by_id.erase(actor_id_value)
			continue
		var record := get_actor_record(str(actor_id_value))
		if not record.is_empty():
			apply_record_to_actor(actor, record)
			if int(record.get("life_state", NpcRules.LifeState.ALIVE)) == NpcRules.LifeState.DEAD:
				dead_projection_registered.emit(str(actor_id_value))


func _try_initialize() -> void:
	if _initialized or root_scene == null or not is_inside_tree():
		return
	_collect_existing_actors()
	var tree := get_tree()
	if tree != null and not tree.node_added.is_connected(_on_tree_node_added):
		tree.node_added.connect(_on_tree_node_added)
	_initialized = true


func _collect_existing_actors() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for actor in tree.get_nodes_in_group("humanoid_character"):
		register_actor(actor)


func _on_tree_node_added(node: Node) -> void:
	if node == null or not node.has_signal("life_state_changed"):
		return
	if node.is_node_ready():
		_register_late_humanoid(node)
	else:
		node.ready.connect(_register_late_humanoid.bind(node), CONNECT_ONE_SHOT)


func _register_late_humanoid(node: Node) -> void:
	if node != null and is_instance_valid(node) and node.is_in_group("humanoid_character") and not bool(node.get_meta("defer_population_registration", false)):
		register_actor(node)


func _refresh_actor_records_cache() -> void:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_population_records"):
		return
	actor_records = bridge.call("get_population_records")
	_rebuild_assignment_index()


func _has_actor_record(actor_id: String) -> bool:
	if actor_id.is_empty():
		return false
	if actor_records.has(actor_id):
		return true
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("get_population_record"):
		var record: Dictionary = bridge.call("get_population_record", actor_id)
		if not record.is_empty():
			actor_records[actor_id] = record
			return true
	return false


func _get_actor_record_mutable(actor_id: String) -> Dictionary:
	if actor_id.is_empty():
		return {}
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("get_population_record"):
		var record: Dictionary = bridge.call("get_population_record", actor_id)
		if not record.is_empty():
			actor_records[actor_id] = record
			return record.duplicate(true)
	if actor_records.has(actor_id):
		return (actor_records[actor_id] as Dictionary).duplicate(true)
	return {}


func _save_actor_record(actor_id: String, record: Dictionary) -> Dictionary:
	if actor_id.strip_edges().is_empty() or record.is_empty():
		return {}
	record["actor_id"] = actor_id
	record["stable_id"] = str(record.get("stable_id", actor_id))
	if int(record.get("birth_day_index", CharacterAgeRules.UNKNOWN_BIRTH_DAY)) == CharacterAgeRules.UNKNOWN_BIRTH_DAY:
		_assign_birth_day_for_new_record(actor_id, record)
	var previous: Dictionary = actor_records.get(actor_id, {})
	var saved := record.duplicate(true)
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("upsert_population_record"):
		saved = bridge.call("upsert_population_record", saved)
	actor_records[actor_id] = saved.duplicate(true)
	_index_record_assignments(saved, previous)
	population_record_changed.emit(str(saved.get("settlement_id", "")), actor_id)
	return saved.duplicate(true)


func _assign_birth_day_for_new_record(actor_id: String, record: Dictionary) -> void:
	var settlement_id := str(record.get("settlement_id", "world")).strip_edges()
	if settlement_id.is_empty():
		settlement_id = "world"
	var existing_ages: Array[int] = []
	for existing_actor_id_value in actor_records.keys():
		var existing_actor_id := str(existing_actor_id_value)
		if existing_actor_id == actor_id:
			continue
		var existing_record: Dictionary = actor_records[existing_actor_id]
		if str(existing_record.get("settlement_id", "world")) != settlement_id:
			continue
		if int(existing_record.get("life_state", NpcRules.LifeState.ALIVE)) == NpcRules.LifeState.DEAD:
			continue
		if CharacterAgeRules.has_birth_day(existing_record):
			existing_ages.append(CharacterAgeRules.age_years(int(existing_record.get("birth_day_index")), _current_world_day()))
	var age_rng := _make_rng(actor_id, "birth_day_migration", existing_ages.size())
	var generated_ages := CharacterAgeRules.generate_missing_ages(existing_ages.size() + 1, existing_ages, age_rng)
	var age_years: int = int(generated_ages.pop_back()) if not generated_ages.is_empty() else CharacterAgeRules.DEFAULT_ADULT_AGE
	record["birth_day_index"] = CharacterAgeRules.birth_day_for_age(age_years, _current_world_day(), age_rng)


func _clear_population_records_for_load() -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("_clear_population_records_for_load"):
		bridge.call("_clear_population_records_for_load")


func _get_gecs_world() -> Node:
	return _context.get_optional(GecsWorldController.SERVICE_ID) if _context != null else null


func _get_generated_records(settlement_id: String, spawner_id: String, role_id := "") -> Array[Dictionary]:
	_refresh_actor_records_cache()
	var records: Array[Dictionary] = []
	for actor_id in actor_records.keys():
		var record: Dictionary = actor_records[actor_id]
		if str(record.get("settlement_id", "")) == settlement_id and str(record.get("generation_source", "")) == spawner_id and (role_id.is_empty() or str(record.get("role_id", "")) == role_id):
			records.append(record.duplicate(true))
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("generation_index", 0)) < int(b.get("generation_index", 0)))
	return records


func _next_generation_index(settlement_id: String, spawner_id: String, start_index: int) -> int:
	_refresh_actor_records_cache()
	var next_index: int = maxi(1, start_index + 1)
	for actor_id in actor_records.keys():
		var record: Dictionary = actor_records[actor_id]
		if str(record.get("settlement_id", "")) != settlement_id or str(record.get("generation_source", "")) != spawner_id:
			continue
		next_index = maxi(next_index, int(record.get("generation_index", 0)) + 1)
	return next_index


func _create_generated_actor_record(settlement_id: String, spawner_id: String, generation_index: int, context: Dictionary, used_names: Dictionary) -> Dictionary:
	var actor_id := "%s.%s.%03d" % [_sanitize_id(settlement_id), _sanitize_id(spawner_id), generation_index]
	var generation_seed := int(context.get("generation_seed", 0))
	var appearance_profile: Resource = context.get("population_appearance_profile") as Resource
	var realizer_id := str(appearance_profile.get("profile_id")).strip_edges() if appearance_profile != null else ""
	var actor_script := appearance_profile.get("actor_script") as Script if appearance_profile != null else null
	if appearance_profile == null or realizer_id.is_empty() or actor_script == null or not appearance_profile.has_method("create_appearance"):
		push_error("Population generation rejected: settlement=%s source=%s has no valid character realizer" % [settlement_id, spawner_id])
		return {}
	var appearance_rng := _make_rng(actor_id, "appearance", generation_seed)
	var appearance = appearance_profile.call("create_appearance", appearance_rng)
	if appearance == null:
		push_error("Population generation rejected: character realizer %s produced no appearance" % realizer_id)
		return {}
	_repair_non_rustdead_appearance(appearance, str(context.get("faction_id", "")))
	var body_type := int(appearance.visual_body_type) if appearance != null else 0
	var name_profile: Resource = context.get("population_name_profile") as Resource
	if name_profile == null or not name_profile.has_method("generate_name"):
		push_error("Population generation rejected: settlement=%s source=%s has no valid name profile" % [settlement_id, spawner_id])
		return {}
	var name_rng := _make_rng(actor_id, "name", generation_seed)
	var display_name := str(name_profile.call("generate_name", body_type, name_rng, used_names)).strip_edges()
	if display_name.is_empty():
		push_error("Population generation rejected: name profile produced an empty name for %s" % actor_id)
		return {}
	var equipment_slots := _generate_equipment_slots(appearance_profile, context, actor_id)
	var character_type: Resource = context.get("character_type") as Resource
	if character_type != null:
		for item in character_type.get("starting_equipment") as Array:
			_add_equipment_path(equipment_slots, item)
	var skill_levels := _generate_skill_levels(context, actor_id)
	var inventory_entries: Array = []
	var character_type_id := str(character_type.get("type_id")).strip_edges().to_lower() if character_type != null else ""
	if character_type != null:
		for item in character_type.get("starting_equipment") as Array:
			if item != null and str(item.get("equip_slot")).strip_edges().is_empty():
				_add_character_type_inventory_item(inventory_entries, item, actor_id, character_type_id)
	return {
		"actor_id": actor_id,
		"stable_id": actor_id,
		"settlement_id": settlement_id,
		"generation_source": spawner_id,
		"generation_index": generation_index,
		"member_name": display_name,
		"birth_day_index": CharacterAgeRules.birth_day_for_age(int(context.get("generated_age_years", CharacterAgeRules.DEFAULT_ADULT_AGE)), _current_world_day(), _make_rng(actor_id, "birth_day", generation_seed)),
		"actor_script_path": actor_script.resource_path,
		"character_realizer_id": realizer_id,
		"character_realizer_path": appearance_profile.resource_path,
		"character_realizer_signature": _realization_signature(appearance_profile),
		"character_type_id": character_type_id,
		"character_type_path": character_type.resource_path if character_type != null else "",
		"character_type_signature": _realization_signature(character_type),
		"faction_id": str(context.get("faction_id", "")),
		"party_id": str(context.get("party_id", "")),
		"squad_name": str(context.get("squad_name", "")),
		"role_id": str(context.get("role_id", "resident")),
		"available_for_work": bool(context.get("available_for_work", true)),
		"hostile_faction_ids": Array(context.get("hostile_faction_ids", [])),
		"combat_stance": int(context.get("combat_stance", NpcRules.combat_stance_for_role(str(context.get("role_id", "resident"))))),
		"auto_heal_enabled": bool(context.get("auto_heal_enabled", false)),
		"auto_burn_rustdead_enabled": bool(context.get("auto_burn_rustdead_enabled", false)),
		"base_color": context.get("base_color", Color(0.62, 0.62, 0.62, 1.0)),
		"appearance": _appearance_to_record(appearance),
		"equipment_slots": equipment_slots,
		"inventory_entries": inventory_entries,
		"skill_levels": skill_levels,
		"traits": {},
		"personality": {},
		"life_state": NpcRules.LifeState.ALIVE,
		"body_state": "living",
		"realization_state": "ledger",
		"ledger_minutes_elapsed": 0,
		"last_world_position": context.get("spawn_position", Vector3.ZERO),
		"last_world_position_initialized": context.has("spawn_position"),
	}


func _new_record_from_actor(actor: Node, actor_id: String, settlement_id: String, context: Dictionary) -> Dictionary:
	var record := {
		"actor_id": actor_id,
		"stable_id": actor_id,
		"settlement_id": settlement_id,
		"generation_source": str(context.get("generation_source", "authored")),
		"generation_index": int(context.get("generation_index", 0)),
		"role_id": str(context.get("role_id", _actor_role(actor))),
		"available_for_work": bool(context.get("available_for_work", false)),
		"traits": {},
		"personality": {},
		"ledger_minutes_elapsed": 0,
	}
	return _merge_actor_state_into_record(record, actor, settlement_id, context)


func _merge_actor_state_into_record(record: Dictionary, actor: Node, settlement_id: String, context: Dictionary) -> Dictionary:
	if actor == null:
		return record
	if settlement_id.is_empty():
		settlement_id = _find_actor_settlement_id(actor)
	if not settlement_id.is_empty() or str(record.get("settlement_id", "")).is_empty():
		record["settlement_id"] = settlement_id
	if context.has("role_id"):
		record["role_id"] = str(context.get("role_id"))
	elif actor.has_meta("settlement_staff_role") and not str(actor.get_meta("settlement_staff_role", "")).is_empty():
		record["role_id"] = str(actor.get_meta("settlement_staff_role"))
	elif actor.has_meta("actor_role_id") and not str(actor.get_meta("actor_role_id", "")).is_empty():
		record["role_id"] = str(actor.get_meta("actor_role_id"))
	if actor.has_meta("population_birth_day_index"):
		record["birth_day_index"] = int(actor.get_meta("population_birth_day_index"))
	record["member_name"] = str(actor.get("member_name"))
	var actor_script := actor.get_script() as Script
	if actor_script != null and not actor_script.resource_path.is_empty():
		record["actor_script_path"] = actor_script.resource_path
	var faction_id := str(actor.get("faction_name"))
	record["faction_id"] = faction_id
	record["party_id"] = str(actor.get_meta("party_id", ""))
	record["squad_name"] = str(actor.get("squad_name"))
	record["hostile_faction_ids"] = Array(actor.get("hostile_factions"))
	record["combat_stance"] = int(actor.get("combat_stance"))
	record["auto_heal_enabled"] = bool(actor.get("auto_heal_enabled"))
	record["auto_burn_rustdead_enabled"] = bool(actor.get("auto_burn_rustdead_enabled"))
	record["life_state"] = int(actor.get("life_state")) if actor.get("life_state") != null else NpcRules.LifeState.ALIVE
	if int(record["life_state"]) == NpcRules.LifeState.DEAD:
		record["body_state"] = str(record.get("body_state", "corpse"))
		if str(record["body_state"]) == "living":
			record["body_state"] = "corpse"
	else:
		record["body_state"] = "living"
	var appearance = actor.get("appearance_data")
	_repair_non_rustdead_appearance(appearance, faction_id)
	record["appearance"] = _appearance_to_record(appearance)
	record["equipment_slots"] = _equipment_slots_from_actor(actor)
	record["inventory_entries"] = _inventory_entries_from_actor(actor)
	var actor_skill_levels := _skill_levels_from_actor(actor)
	for skill_id in (record.get("skill_levels", {}) as Dictionary):
		if not actor_skill_levels.has(skill_id) and actor.has_method("get_skill_level"):
			actor_skill_levels[skill_id] = int(actor.call("get_skill_level", str(skill_id)))
	record["skill_levels"] = actor_skill_levels
	var needs = actor.call("get_needs") if actor.has_method("get_needs") else null
	if needs != null and needs.has_method("durable_state"):
		record["needs_state"] = needs.call("durable_state")
	record["movement_state"] = {
		"has_move_target": bool(actor.call("has_move_target")) if actor.has_method("has_move_target") else false,
		"move_target": actor.call("get_move_target") if actor.has_method("get_move_target") else Vector3.ZERO,
		"running": bool(actor.call("is_running_requested")) if actor.has_method("is_running_requested") else false,
		"sneaking": bool(actor.call("is_sneaking")) if actor.has_method("is_sneaking") else false,
		"issued_by_player": bool(actor.call("has_active_player_order")) if actor.has_method("has_active_player_order") else false,
	}
	if actor is Node3D:
		record["last_world_position"] = (actor as Node3D).global_position
		record["last_world_position_initialized"] = true
		record["last_world_transform"] = (actor as Node3D).global_transform
		record["last_world_transform_initialized"] = true
	return record


func _register_actor_with_query_controller(actor: Node) -> void:
	if actor == null or not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	for query_controller in tree.get_nodes_in_group("actor_query_controller"):
		if query_controller != null and query_controller.has_method("register_actor"):
			query_controller.call("register_actor", actor)


func _connect_actor_skill_changes(actor: Node, actor_id: String) -> void:
	var stats = actor.call("get_stats") if actor != null and actor.has_method("get_stats") else null
	if stats == null:
		return
	_disconnect_actor_skill_changes(actor, actor_id)
	var callback := _on_actor_skill_level_changed.bind(actor_id)
	stats.skill_progress_changed.connect(callback)
	_skill_change_callable_by_actor_id[actor_id] = callback


func _disconnect_actor_skill_changes(actor: Node, actor_id: String) -> void:
	var callback: Callable = _skill_change_callable_by_actor_id.get(actor_id, Callable())
	if callback.is_null():
		return
	var stats = actor.call("get_stats") if actor != null and actor.has_method("get_stats") else null
	if stats != null and stats.skill_progress_changed.is_connected(callback):
		stats.skill_progress_changed.disconnect(callback)
	_skill_change_callable_by_actor_id.erase(actor_id)


func _disconnect_all_actor_skill_changes() -> void:
	for actor_id_value in _skill_change_callable_by_actor_id.keys():
		var actor_id := str(actor_id_value)
		_disconnect_actor_skill_changes(_live_actor_by_id.get(actor_id), actor_id)
	for actor_id_value in _life_change_callable_by_actor_id.keys():
		var actor_id := str(actor_id_value)
		_disconnect_actor_life_changes(_live_actor_by_id.get(actor_id), actor_id)


func _connect_actor_life_changes(actor: Node, actor_id: String) -> void:
	if actor == null or not actor.has_signal("life_state_changed"):
		return
	_disconnect_actor_life_changes(actor, actor_id)
	var callback := _on_actor_life_state_changed.bind(actor_id, actor)
	actor.life_state_changed.connect(callback)
	_life_change_callable_by_actor_id[actor_id] = callback
	if int(actor.get("life_state")) == NpcRules.LifeState.DEAD:
		mark_record_dead(actor_id, actor)
		dead_projection_registered.emit(actor_id)


func _disconnect_actor_life_changes(actor: Node, actor_id: String) -> void:
	var callback: Callable = _life_change_callable_by_actor_id.get(actor_id, Callable())
	if callback.is_null():
		return
	if actor != null and is_instance_valid(actor) and actor.has_signal("life_state_changed") and actor.life_state_changed.is_connected(callback):
		actor.life_state_changed.disconnect(callback)
	_life_change_callable_by_actor_id.erase(actor_id)


func _on_actor_life_state_changed(_previous_state: int, next_state: int, actor_id: String, actor: Node) -> void:
	if next_state == NpcRules.LifeState.DEAD:
		mark_record_dead(actor_id, actor)


func _sync_live_corpse_transforms() -> void:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("update_population_corpse_transform"):
		return
	for actor_id_value in _live_actor_by_id.keys():
		var actor = _live_actor_by_id.get(actor_id_value)
		if not (actor is Node3D) or not is_instance_valid(actor):
			continue
		if int(actor.get("life_state")) != NpcRules.LifeState.DEAD:
			continue
		bridge.call("update_population_corpse_transform", str(actor_id_value), (actor as Node3D).global_transform)


func _on_actor_skill_level_changed(skill_id: String, actor_id: String) -> void:
	var actor = _live_actor_by_id.get(actor_id)
	var stats = actor.call("get_stats") if actor != null and is_instance_valid(actor) and actor.has_method("get_stats") else null
	if stats == null:
		return
	var level := int(stats.call("get_skill_level", skill_id))
	var xp := float(stats.call("get_skill_xp", skill_id))
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("update_population_skill_progress"):
		bridge.call("update_population_skill_progress", actor_id, skill_id, level, xp)
	if not actor_records.has(actor_id):
		return
	var record := actor_records[actor_id] as Dictionary
	var skill_levels := record.get("skill_levels", {}) as Dictionary
	var skill_xp := record.get("skill_xp", {}) as Dictionary
	if level > SkillRules.DEFAULT_LEVEL:
		skill_levels[skill_id] = level
	else:
		skill_levels.erase(skill_id)
	if xp > 0.0:
		skill_xp[skill_id] = xp
	else:
		skill_xp.erase(skill_id)
	if skill_id == SkillRules.ATTRIBUTE_TOUGHNESS:
		_refresh_actor_visual_context(actor, record, level)


func _unregister_actor_from_query_controller(actor: Node) -> void:
	if actor == null or not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	for query_controller in tree.get_nodes_in_group("actor_query_controller"):
		if query_controller != null and query_controller.has_method("unregister_actor"):
			query_controller.call("unregister_actor", actor)


func _rebuild_assignment_index() -> void:
	_actor_id_by_assignment_key.clear()
	for record_value in actor_records.values():
		_index_record_assignments(record_value)


func _index_record_assignments(record: Dictionary, previous: Dictionary = {}) -> void:
	var previous_actor_id := str(previous.get("actor_id", ""))
	var previous_settlement_id := str(previous.get("settlement_id", ""))
	for domain_value in (previous.get("assignments", {}) as Dictionary).keys():
		var key := _assignment_index_key(previous_settlement_id, str(domain_value), str((previous.get("assignments", {}) as Dictionary)[domain_value]))
		if str(_actor_id_by_assignment_key.get(key, "")) == previous_actor_id:
			_actor_id_by_assignment_key.erase(key)
	var actor_id := str(record.get("actor_id", ""))
	var settlement_id := str(record.get("settlement_id", ""))
	for domain_value in (record.get("assignments", {}) as Dictionary).keys():
		_actor_id_by_assignment_key[_assignment_index_key(settlement_id, str(domain_value), str((record.get("assignments", {}) as Dictionary)[domain_value]))] = actor_id


func _assignment_index_key(settlement_id: String, assignment_domain: String, slot_id: String) -> String:
	return "%s:%s:%s" % [settlement_id, assignment_domain, slot_id]


func _generate_equipment_slots(appearance_profile: Resource, context: Dictionary, actor_id: String) -> Dictionary:
	var slots := {}
	var starting_equipment: Array = context.get("starting_equipment", [])
	for item in starting_equipment:
		_add_equipment_path(slots, item)
	if appearance_profile == null:
		return slots
	var rng := _make_rng(actor_id, "equipment", int(context.get("generation_seed", 0)))
	for property_name in ["chest_items", "leg_items", "feet_items"]:
		_pick_equipment_from_pool(slots, appearance_profile.get(property_name), rng)
	var head_chance = appearance_profile.get("head_item_chance")
	if head_chance != null and rng.randf() < float(head_chance):
		_pick_equipment_from_pool(slots, appearance_profile.get("head_items"), rng)
	return slots


func _pick_equipment_from_pool(slots: Dictionary, pool_value, rng: RandomNumberGenerator) -> void:
	if not (pool_value is Array) or (pool_value as Array).is_empty():
		return
	var pool: Array = pool_value
	var item: Resource = pool[rng.randi_range(0, pool.size() - 1)] as Resource
	_add_equipment_path(slots, item)


func _add_equipment_path(slots: Dictionary, item) -> void:
	if item == null:
		return
	var slot := str(item.get("equip_slot")) if item is Resource else ""
	var path := _resource_path(item)
	if slot.is_empty() or path.is_empty() or slots.has(slot):
		return
	slots[slot] = path


func _generate_skill_levels(context: Dictionary, actor_id: String) -> Dictionary:
	var minimum := int(context.get("resident_perception_min", SkillRules.DEFAULT_LEVEL))
	var maximum := int(context.get("resident_perception_max", SkillRules.DEFAULT_LEVEL))
	var rng := _make_rng(actor_id, "skills", int(context.get("generation_seed", 0)))
	var low := mini(minimum, maximum)
	var high := maxi(minimum, maximum)
	var t := (rng.randf() + rng.randf()) * 0.5
	var result := {SkillRules.ATTRIBUTE_PERCEPTION: clampi(int(round(lerpf(float(low), float(high), t))), low, high)}
	var character_type: Resource = context.get("character_type") as Resource
	var ranges: Dictionary = character_type.get("starting_skill_ranges") if character_type != null else {}
	var skill_ids := ranges.keys()
	skill_ids.sort()
	for skill_id_value in skill_ids:
		var range_value = ranges[skill_id_value]
		if not (range_value is Vector2i):
			continue
		var skill_range := range_value as Vector2i
		var skill_low := mini(skill_range.x, skill_range.y)
		var skill_high := maxi(skill_range.x, skill_range.y)
		var skill_t := (rng.randf() + rng.randf()) * 0.5
		result[str(skill_id_value)] = clampi(int(round(lerpf(float(skill_low), float(skill_high), skill_t))), skill_low, skill_high)
	return result


func _add_character_type_inventory_item(entries: Array, item: Resource, actor_id: String, type_id: String) -> void:
	if item == null or item.resource_path.is_empty():
		return
	for entry_value in entries:
		if entry_value is Dictionary and str((entry_value as Dictionary).get("item_id", "")) == item.resource_path:
			return
	entries.append({
		"stack_id": "%s.type.%s.%03d" % [actor_id, type_id, entries.size() + 1],
		"item_id": item.resource_path,
		"count": 1,
		"grid_position": Vector2i(0, entries.size() * 2),
		"contained_item_counts": {},
		"metadata": {"character_type_id": type_id},
	})


func _realization_signature(resource: Resource) -> String:
	if resource == null:
		return ""
	if resource.has_method("get_realization_signature"):
		return str(resource.call("get_realization_signature"))
	return resource.resource_path


func _appearance_to_record(appearance) -> Dictionary:
	if appearance == null:
		return {}
	return {
		"character_race": _resource_path(appearance.character_race),
		"body_archetype": _resource_path(appearance.body_archetype),
		"visual_body_type": int(appearance.visual_body_type),
		"hair_style": _resource_path(appearance.hair_style),
		"beard_style": _resource_path(appearance.beard_style),
		"eyebrow_style": _resource_path(appearance.eyebrow_style),
		"hair_color": _canonical_color(appearance.hair_color),
		"beard_color": _canonical_color(appearance.beard_color),
		"eyebrow_color": _canonical_color(appearance.eyebrow_color),
		"skin_color_customized": bool(appearance.skin_color_customized),
		"skin_color": _canonical_color(appearance.skin_color),
		"height_slider": snappedf(float(appearance.height_slider), 0.000001),
		"shoulder_width_slider": snappedf(float(appearance.shoulder_width_slider), 0.000001),
		"arm_length_slider": snappedf(float(appearance.arm_length_slider), 0.000001),
		"neck_length_slider": snappedf(float(appearance.neck_length_slider), 0.000001),
	}


static func _canonical_color(color: Color) -> Color:
	return Color(
		snappedf(color.r, 0.000001),
		snappedf(color.g, 0.000001),
		snappedf(color.b, 0.000001),
		snappedf(color.a, 0.000001)
	)


func _repair_non_rustdead_appearance(appearance, faction_id: String) -> void:
	if appearance == null or faction_id == RUSTDEAD_FACTION_ID:
		return
	if _appearance_race_id(appearance) != RUSTDEAD_RACE_ID:
		return
	appearance.character_race = HUMAN_RACE
	appearance.body_archetype = _human_body_archetype(int(appearance.visual_body_type))


func _appearance_race_id(appearance) -> String:
	if appearance == null:
		return ""
	return _resource_race_id(appearance.character_race as Resource)


func _resource_race_id(race: Resource) -> String:
	return str(race.get("race_id")).strip_edges().to_lower() if race != null else ""


func _human_body_archetype(body_type: int) -> Resource:
	var property_name := "default_female_archetype" if body_type == VISUAL_BODY_TYPE_FEMALE else "default_male_archetype"
	return HUMAN_RACE.get(property_name) as Resource


## Public: builds CharacterAppearanceData from a serialized appearance dict
## (population records, authored CharacterRecordDefinition resources). Static so
## authored scenes can convert records without the controller being live yet.
static func appearance_from_record(record: Dictionary):
	if record.is_empty():
		return null
	var appearance = CHARACTER_APPEARANCE_DATA_SCRIPT.new()
	appearance.character_race = _load_resource(str(record.get("character_race", "")))
	appearance.body_archetype = _load_resource(str(record.get("body_archetype", "")))
	appearance.visual_body_type = int(record.get("visual_body_type", 0))
	appearance.hair_style = _load_resource(str(record.get("hair_style", "")))
	appearance.beard_style = _load_resource(str(record.get("beard_style", "")))
	appearance.eyebrow_style = _load_resource(str(record.get("eyebrow_style", "")))
	appearance.hair_color = record.get("hair_color", appearance.hair_color)
	appearance.beard_color = record.get("beard_color", appearance.beard_color)
	appearance.eyebrow_color = record.get("eyebrow_color", appearance.eyebrow_color)
	appearance.skin_color_customized = bool(record.get("skin_color_customized", false))
	appearance.skin_color = record.get("skin_color", appearance.skin_color)
	appearance.height_slider = float(record.get("height_slider", 0.0))
	appearance.shoulder_width_slider = float(record.get("shoulder_width_slider", 0.0))
	appearance.arm_length_slider = float(record.get("arm_length_slider", 0.0))
	appearance.neck_length_slider = float(record.get("neck_length_slider", 0.0))
	return appearance


func _equipment_slots_from_actor(actor: Node) -> Dictionary:
	var slots := {}
	var equipment = actor.call("get_equipment") if actor.has_method("get_equipment") else null
	var equipped = equipment.call("get_equipped_items") \
			if equipment != null and equipment.has_method("get_equipped_items") \
			else actor.get("equipped_items")
	if equipped is Dictionary:
		for slot in equipped.keys():
			var path := _resource_path(equipped[slot])
			if not path.is_empty():
				slots[str(slot)] = path
	var starting_equipment = actor.get("starting_equipment")
	if starting_equipment is Array:
		for item in starting_equipment:
			_add_equipment_path(slots, item)
	return slots


func _inventory_entries_from_actor(actor: Node) -> Array:
	var inventory = actor.get("inventory")
	if inventory == null or not (inventory.get("entries") is Array):
		return []
	var result: Array = []
	for entry in inventory.get("entries"):
		if entry == null:
			continue
		result.append({
			"stack_id": str(entry.stack_id),
			"item_id": _resource_path(entry.definition),
			"count": int(entry.count),
			"grid_position": entry.grid_position,
			"contained_item_counts": entry.contained_item_counts.duplicate(true),
			"metadata": entry.metadata.duplicate(true),
		})
	return result


func _skill_levels_from_actor(actor: Node) -> Dictionary:
	var result := {}
	var stats = actor.call("get_stats") if actor != null and actor.has_method("get_stats") else null
	var skill_set = stats.get("skill_set") if stats != null else null
	if skill_set != null and skill_set.has_method("get_all_entry_snapshots"):
		for snapshot in skill_set.call("get_all_entry_snapshots"):
			if snapshot is Dictionary:
				var level := int(snapshot.get("level", SkillRules.DEFAULT_LEVEL))
				if level > SkillRules.DEFAULT_LEVEL:
					result[str(snapshot.get("skill_id", ""))] = level
	return result


func _actor_id_for_actor(actor: Node, settlement_id: String) -> String:
	var existing := _actor_record_id(actor)
	if not existing.is_empty():
		return existing
	var stable_id = actor.get("stable_id")
	if stable_id != null and not str(stable_id).strip_edges().is_empty():
		return str(stable_id).strip_edges()
	var prefix := _sanitize_id(settlement_id if not settlement_id.is_empty() else "world")
	var path_part := _sanitize_id(_relative_actor_path(actor))
	if path_part.is_empty():
		path_part = _sanitize_id(str(actor.name))
	return "%s.%s" % [prefix, path_part]


func _actor_record_id(actor: Node) -> String:
	if actor == null:
		return ""
	if actor.has_meta("actor_record_id"):
		return str(actor.get_meta("actor_record_id")).strip_edges()
	var stable_id = actor.get("stable_id")
	return str(stable_id).strip_edges() if stable_id != null else ""


func _relative_actor_path(actor: Node) -> String:
	var settlement := _find_actor_settlement(actor)
	if settlement != null:
		return str(settlement.get_path_to(actor))
	if actor != null and actor.is_inside_tree():
		return str(actor.get_path())
	return str(actor.name) if actor != null else ""


func _find_actor_settlement_id(actor: Node) -> String:
	var settlement := _find_actor_settlement(actor)
	if settlement != null and settlement.has_method("get_settlement_id"):
		return str(settlement.call("get_settlement_id"))
	return ""


func _find_actor_settlement(actor: Node) -> Node:
	var current := actor
	while current != null:
		if current is SettlementAnchor or current.is_in_group("settlement_anchor"):
			return current
		current = current.get_parent()
	return null


func _actor_role(actor: Node) -> String:
	if actor == null:
		return "resident"
	if actor.has_meta("settlement_staff_role"):
		return str(actor.get_meta("settlement_staff_role"))
	if actor.is_in_group("settlement_authority"):
		return "guard"
	if actor.has_method("has_merchant_role") and bool(actor.call("has_merchant_role")):
		return "merchant"
	return "resident"


func _collect_used_names(settlement_id: String) -> Dictionary:
	_refresh_actor_records_cache()
	var used := {}
	for actor_id in actor_records.keys():
		var record: Dictionary = actor_records[actor_id]
		if str(record.get("settlement_id", "")) != settlement_id:
			continue
		var display_name := str(record.get("member_name", "")).strip_edges()
		if not display_name.is_empty():
			used[display_name.to_lower()] = true
	return used


func _ledger_activity_for_record(record: Dictionary, absolute_minute: int) -> String:
	var life_state := int(record.get("life_state", NpcRules.LifeState.ALIVE))
	if life_state != NpcRules.LifeState.ALIVE and life_state != NpcRules.LifeState.ASLEEP:
		return "recovering"
	var hour := int(floor(float(max(absolute_minute, 0) % 1440) / 60.0)) if absolute_minute >= 0 else 12
	var assignments: Dictionary = record.get("assignments", {})
	var has_home := not str(assignments.get("residence", "")).is_empty()
	if hour >= 22 or hour < 6:
		return "home_sleep" if has_home else "resting"
	if not str(assignments.get("employment", "")).is_empty():
		return "working"
	if has_home:
		return "home_day"
	var role_id := str(record.get("role_id", "resident")).to_lower()
	if ["worker", "waiter", "barkeeper", "merchant", "guard", "barber", "warden", "ruler", "mayor"].has(role_id):
		return "working"
	return "routine"


func get_actor_routine_activity(actor_id: String, absolute_minute: int) -> String:
	var record := get_actor_record(actor_id)
	return _ledger_activity_for_record(record, absolute_minute) if not record.is_empty() else ""


func _increment_count(counts: Dictionary, key: String) -> void:
	var safe_key := key if not key.strip_edges().is_empty() else "unknown"
	counts[safe_key] = int(counts.get(safe_key, 0)) + 1


## extra_seed perturbs the actor_id-derived stream: a settlement's authored
## generation_seed makes its whole population reproducible, while a per-run
## rolled seed makes each new game generate different people.
func _make_rng(actor_id: String, purpose: String, extra_seed := 0) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = max(1, absi(("%s:%s:%d" % [actor_id, purpose, extra_seed]).hash()))
	return rng


func _current_world_day() -> int:
	var world_time := _context.get_optional(WorldTimeController.SERVICE_ID) as WorldTimeController if _context != null else null
	return world_time.get_day_index() if world_time != null else 0


func _on_world_day_changed(_day_index: int) -> void:
	for actor_id_value in _live_actor_by_id.keys():
		var actor = _live_actor_by_id.get(actor_id_value)
		if actor == null or not is_instance_valid(actor):
			continue
		var record := get_actor_record(str(actor_id_value))
		if not record.is_empty():
			_refresh_actor_visual_context(actor, record)


func _refresh_actor_visual_context(actor: Node, record: Dictionary, toughness_override := -1) -> void:
	if actor == null or not actor.has_method("apply_appearance_data"):
		return
	var appearance = actor.get("appearance_data")
	if appearance == null:
		return
	var next_age := CharacterAgeRules.age_years(int(record.get("birth_day_index", CharacterAgeRules.UNKNOWN_BIRTH_DAY)), _current_world_day())
	var next_toughness := toughness_override
	if next_toughness < 0:
		next_toughness = int((record.get("skill_levels", {}) as Dictionary).get(SkillRules.ATTRIBUTE_TOUGHNESS, SkillRules.DEFAULT_LEVEL))
	var body_variant_changed := CharacterVisualRules.is_teen_age(int(appearance.visual_age_years)) != CharacterVisualRules.is_teen_age(next_age) \
		or CharacterVisualRules.is_heroic(int(appearance.visual_age_years), int(appearance.visual_toughness_level)) != CharacterVisualRules.is_heroic(next_age, next_toughness)
	appearance.visual_age_years = next_age
	appearance.visual_toughness_level = next_toughness
	actor.set_meta("population_age_years", next_age)
	if body_variant_changed:
		actor.call("apply_appearance_data", appearance)


func _resource_path(resource) -> String:
	if resource == null:
		return ""
	if resource is Resource:
		return str((resource as Resource).resource_path)
	return ""


static func _load_resource(path: String) -> Resource:
	if path.strip_edges().is_empty():
		return null
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Resource


func _sanitize_id(value: String) -> String:
	var text := value.strip_edges().to_lower()
	var result := ""
	for index in range(text.length()):
		var ch := text.substr(index, 1)
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			result += ch
		else:
			result += "_"
	while result.contains("__"):
		result = result.replace("__", "_")
	while result.begins_with("_"):
		result = result.substr(1)
	while result.ends_with("_") and result.length() > 0:
		result = result.substr(0, result.length() - 1)
	return result
