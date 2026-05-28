extends Node

class_name PopulationController

const CHARACTER_APPEARANCE_DATA_SCRIPT := preload("res://scripts/character_appearance/character_appearance_data.gd")
const GECS_WORLD_CONTROLLER_SCRIPT := preload("res://scripts/controllers/gecs_world_controller.gd")

var root_scene: Node
var actor_records: Dictionary = {}
var _live_actor_by_id: Dictionary = {}
var _initialized := false


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
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
	_save_actor_record(actor_id, record)
	_live_actor_by_id[actor_id] = actor
	actor.set_meta("settlement_id", str(record.get("settlement_id", settlement_id)))
	actor.set_meta("actor_role_id", str(record.get("role_id", "resident")))
	_register_actor_with_query_controller(actor)
	return record.duplicate(true)


func unregister_actor(actor: Node) -> void:
	if actor == null:
		return
	var actor_id := _actor_record_id(actor)
	if actor_id.is_empty():
		return
	_unregister_actor_from_query_controller(actor)
	var record: Dictionary = _get_actor_record_mutable(actor_id)
	if not record.is_empty():
		record = _merge_actor_state_into_record(record, actor, str(record.get("settlement_id", "")), {})
		record["realization_state"] = "ledger"
		record.erase("live_node_path")
		_save_actor_record(actor_id, record)
	_live_actor_by_id.erase(actor_id)


func get_actor_record(actor_id: String) -> Dictionary:
	return _get_actor_record_mutable(actor_id).duplicate(true)


func get_records_for_settlement(settlement_id: String) -> Array[Dictionary]:
	_refresh_actor_records_cache()
	var records: Array[Dictionary] = []
	for actor_id in actor_records.keys():
		var record: Dictionary = actor_records[actor_id]
		if str(record.get("settlement_id", "")) == settlement_id:
			records.append(record.duplicate(true))
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("actor_id", "")) < str(b.get("actor_id", "")))
	return records


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
	var records: Array[Dictionary] = _get_generated_records(settlement_id, spawner_id, role_id)
	while records.size() > desired_count:
		var removed_record: Dictionary = records.pop_back()
		_remove_actor_record(str(removed_record.get("actor_id", "")), true)
	var start_index: int = max(0, int(context.get("start_index", 0)))
	var next_generation_index: int = _next_generation_index(settlement_id, spawner_id, start_index)
	var used_names := _collect_used_names(settlement_id)
	while records.size() < desired_count:
		var generation_index: int = next_generation_index
		next_generation_index += 1
		var record: Dictionary = _create_generated_actor_record(settlement_id, spawner_id, generation_index, context, used_names)
		_save_actor_record(str(record["actor_id"]), record)
		records.append(record.duplicate(true))
		var display_name := str(record.get("member_name", "")).strip_edges()
		if not display_name.is_empty():
			used_names[display_name.to_lower()] = true
	return records


func remove_actor_record(actor_id: String, remove_live_actor := true) -> void:
	_remove_actor_record(actor_id, remove_live_actor)


func apply_record_to_actor(actor: Node, record: Dictionary) -> void:
	if actor == null or record.is_empty():
		return
	var actor_id := str(record.get("actor_id", ""))
	if not actor_id.is_empty():
		actor.set("stable_id", actor_id)
		actor.set_meta("actor_record_id", actor_id)
	actor.set("member_name", str(record.get("member_name", actor.get("member_name"))))
	actor.set("faction_name", str(record.get("faction_id", actor.get("faction_name"))))
	actor.set("squad_name", str(record.get("squad_name", actor.get("squad_name"))))
	actor.set("hostile_factions", PackedStringArray(record.get("hostile_faction_ids", [])))
	actor.set("combat_stance", int(record.get("combat_stance", actor.get("combat_stance"))))
	actor.set("starting_skill_levels", record.get("skill_levels", {}))
	actor.set_meta("settlement_id", str(record.get("settlement_id", "")))
	actor.set_meta("actor_role_id", str(record.get("role_id", "resident")))
	actor.set_meta("population_inventory_entries", Array(record.get("inventory_entries", [])).duplicate(true))
	if record.has("base_color"):
		actor.set("base_color", record.get("base_color"))
	var appearance = _appearance_from_record(record.get("appearance", {}) as Dictionary)
	if appearance != null:
		actor.set("character_race", appearance.character_race)
		actor.set("body_archetype", appearance.body_archetype)
		actor.set("visual_body_type", appearance.visual_body_type)
		actor.set("appearance_data", appearance)
	var starting_equipment: Array[Resource] = []
	var equipment_slots: Dictionary = record.get("equipment_slots", {})
	for slot in equipment_slots.keys():
		var item := _load_resource(str(equipment_slots[slot]))
		if item != null:
			starting_equipment.append(item)
	actor.set("starting_equipment", starting_equipment)


func mark_actor_realized(actor: Node, actor_id := "") -> void:
	if actor == null:
		return
	if actor_id.is_empty():
		actor_id = _actor_record_id(actor)
	if actor_id.is_empty():
		return
	_live_actor_by_id[actor_id] = actor
	var record: Dictionary = _get_actor_record_mutable(actor_id)
	if not record.is_empty():
		record["realization_state"] = "realized"
		record["live_node_path"] = actor.get_path()
		_save_actor_record(actor_id, record)


func advance_ledger_minutes(minutes: int, absolute_minute := -1) -> Dictionary:
	_refresh_actor_records_cache()
	var summary := {"elapsed_minutes": max(0, minutes), "updated_actor_count": 0, "batches": {}}
	if minutes <= 0:
		return summary
	for actor_id in actor_records.keys():
		var record: Dictionary = actor_records[actor_id]
		if str(record.get("realization_state", "ledger")) == "realized":
			continue
		var activity := _ledger_activity_for_record(record, absolute_minute)
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
		_save_actor_record(str(actor_id), record)
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
	sync_population_state()
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
	_clear_population_records_in_gecs()
	actor_records.clear()
	_live_actor_by_id.clear()
	var records: Dictionary = state.get("actor_records", {})
	for actor_id in records.keys():
		if records[actor_id] is Dictionary:
			var record: Dictionary = (records[actor_id] as Dictionary).duplicate(true)
			record.erase("live_node_path")
			if str(record.get("realization_state", "ledger")) == "realized":
				record["realization_state"] = "ledger"
			_save_actor_record(str(actor_id), record)


func refresh_from_gecs_state() -> void:
	_refresh_actor_records_cache()


func sync_population_state() -> void:
	_collect_existing_actors()
	for actor_id_value in _live_actor_by_id.keys():
		var actor_id := str(actor_id_value)
		var actor = _live_actor_by_id.get(actor_id_value)
		if actor == null or not is_instance_valid(actor):
			_live_actor_by_id.erase(actor_id_value)
			continue
		var record: Dictionary = _get_actor_record_mutable(actor_id)
		if record.is_empty():
			record = _new_record_from_actor(actor, actor_id, _find_actor_settlement_id(actor), {})
		else:
			record = _merge_actor_state_into_record(record, actor, str(record.get("settlement_id", "")), {})
		record["realization_state"] = "realized"
		record["live_node_path"] = actor.get_path()
		_save_actor_record(actor_id, record)


func _try_initialize() -> void:
	if _initialized or root_scene == null or not is_inside_tree():
		return
	_collect_existing_actors()
	_initialized = true


func _collect_existing_actors() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for actor in tree.get_nodes_in_group("humanoid_character"):
		register_actor(actor)


func _refresh_actor_records_cache() -> void:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_population_records"):
		return
	actor_records = bridge.call("get_population_records")


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
	if actor_records.has(actor_id):
		return (actor_records[actor_id] as Dictionary).duplicate(true)
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("get_population_record"):
		var record: Dictionary = bridge.call("get_population_record", actor_id)
		if not record.is_empty():
			actor_records[actor_id] = record
			return record.duplicate(true)
	return {}


func _save_actor_record(actor_id: String, record: Dictionary) -> Dictionary:
	if actor_id.strip_edges().is_empty() or record.is_empty():
		return {}
	record["actor_id"] = actor_id
	record["stable_id"] = str(record.get("stable_id", actor_id))
	var saved := record.duplicate(true)
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("upsert_population_record"):
		saved = bridge.call("upsert_population_record", saved)
	actor_records[actor_id] = saved.duplicate(true)
	return saved.duplicate(true)


func _remove_actor_record_from_gecs(actor_id: String) -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("remove_population_record"):
		bridge.call("remove_population_record", actor_id)


func _clear_population_records_in_gecs() -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("clear_population_records"):
		bridge.call("clear_population_records")


func _get_gecs_world() -> Node:
	if not is_inside_tree():
		return null
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("GecsWorldController")
		if local != null:
			return local
	var existing := get_tree().get_first_node_in_group("gecs_world_controller")
	if existing != null and (parent_node == null or existing.get_parent() == parent_node):
		return existing
	if parent_node == null:
		return null
	var bridge = GECS_WORLD_CONTROLLER_SCRIPT.new()
	bridge.name = "GecsWorldController"
	parent_node.add_child(bridge)
	bridge.call("initialize", root_scene if root_scene != null else parent_node)
	return bridge


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
	var appearance_profile: Resource = context.get("population_appearance_profile") as Resource
	var appearance_rng := _make_rng(actor_id, "appearance")
	var appearance = appearance_profile.call("create_appearance", appearance_rng) if appearance_profile != null and appearance_profile.has_method("create_appearance") else CHARACTER_APPEARANCE_DATA_SCRIPT.new()
	var body_type := int(appearance.visual_body_type) if appearance != null else 0
	var name_profile: Resource = context.get("population_name_profile") as Resource
	var name_rng := _make_rng(actor_id, "name")
	var display_name := "%s %02d" % [str(context.get("member_name_prefix", "Resident")), generation_index]
	if name_profile != null and name_profile.has_method("generate_name"):
		display_name = str(name_profile.call("generate_name", body_type, name_rng, used_names)).strip_edges()
	var equipment_slots := _generate_equipment_slots(appearance_profile, context, actor_id)
	var skill_levels := _generate_skill_levels(context, actor_id)
	return {
		"actor_id": actor_id,
		"stable_id": actor_id,
		"settlement_id": settlement_id,
		"generation_source": spawner_id,
		"generation_index": generation_index,
		"member_name": display_name,
		"faction_id": str(context.get("faction_id", "")),
		"squad_name": str(context.get("squad_name", "")),
		"role_id": str(context.get("role_id", "resident")),
		"hostile_faction_ids": Array(context.get("hostile_faction_ids", [])),
		"combat_stance": int(context.get("combat_stance", NpcRules.CombatStance.DEFENSIVE)),
		"base_color": context.get("base_color", Color(0.62, 0.62, 0.62, 1.0)),
		"appearance": _appearance_to_record(appearance),
		"equipment_slots": equipment_slots,
		"inventory_entries": [],
		"skill_levels": skill_levels,
		"traits": {},
		"personality": {},
		"life_state": NpcRules.LifeState.ALIVE,
		"realization_state": "ledger",
		"ledger_minutes_elapsed": 0,
		"last_world_position": context.get("spawn_position", Vector3.ZERO),
	}


func _new_record_from_actor(actor: Node, actor_id: String, settlement_id: String, context: Dictionary) -> Dictionary:
	var record := {
		"actor_id": actor_id,
		"stable_id": actor_id,
		"settlement_id": settlement_id,
		"generation_source": str(context.get("generation_source", "authored")),
		"generation_index": int(context.get("generation_index", 0)),
		"role_id": str(context.get("role_id", _actor_role(actor))),
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
	record["settlement_id"] = settlement_id
	record["role_id"] = str(context.get("role_id", _actor_role(actor)))
	record["member_name"] = str(actor.get("member_name"))
	record["faction_id"] = str(actor.get("faction_name"))
	record["squad_name"] = str(actor.get("squad_name"))
	record["hostile_faction_ids"] = Array(actor.get("hostile_factions"))
	record["combat_stance"] = int(actor.get("combat_stance"))
	record["life_state"] = int(actor.get("life_state")) if actor.get("life_state") != null else NpcRules.LifeState.ALIVE
	record["appearance"] = _appearance_to_record(actor.get("appearance_data"))
	record["equipment_slots"] = _equipment_slots_from_actor(actor)
	record["inventory_entries"] = _inventory_entries_from_actor(actor)
	record["skill_levels"] = _skill_levels_from_actor(actor)
	if actor is Node3D:
		record["last_world_position"] = (actor as Node3D).global_position
		record["last_world_position_initialized"] = true
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


func _unregister_actor_from_query_controller(actor: Node) -> void:
	if actor == null or not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	for query_controller in tree.get_nodes_in_group("actor_query_controller"):
		if query_controller != null and query_controller.has_method("unregister_actor"):
			query_controller.call("unregister_actor", actor)


func _remove_actor_record(actor_id: String, remove_live_actor := true) -> void:
	if actor_id.strip_edges().is_empty() or not _has_actor_record(actor_id):
		return
	var live_actor = _live_actor_by_id.get(actor_id)
	if remove_live_actor and live_actor != null and is_instance_valid(live_actor):
		if live_actor.has_method("is_player_party_member") and bool(live_actor.call("is_player_party_member")):
			remove_live_actor = false
		else:
			unregister_actor(live_actor)
			live_actor.queue_free()
	_live_actor_by_id.erase(actor_id)
	actor_records.erase(actor_id)
	_remove_actor_record_from_gecs(actor_id)


func _generate_equipment_slots(appearance_profile: Resource, context: Dictionary, actor_id: String) -> Dictionary:
	var slots := {}
	var starting_equipment: Array = context.get("starting_equipment", [])
	for item in starting_equipment:
		_add_equipment_path(slots, item)
	if appearance_profile == null:
		return slots
	var rng := _make_rng(actor_id, "equipment")
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
	var rng := _make_rng(actor_id, "skills")
	var low := mini(minimum, maximum)
	var high := maxi(minimum, maximum)
	var t := (rng.randf() + rng.randf()) * 0.5
	return {SkillRules.ATTRIBUTE_PERCEPTION: clampi(int(round(lerpf(float(low), float(high), t))), low, high)}


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
		"hair_color": appearance.hair_color,
		"beard_color": appearance.beard_color,
		"eyebrow_color": appearance.eyebrow_color,
		"skin_color_customized": bool(appearance.skin_color_customized),
		"skin_color": appearance.skin_color,
		"height_slider": float(appearance.height_slider),
		"shoulder_width_slider": float(appearance.shoulder_width_slider),
		"arm_length_slider": float(appearance.arm_length_slider),
		"neck_length_slider": float(appearance.neck_length_slider),
	}


func _appearance_from_record(record: Dictionary):
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
	var equipped = actor.get("equipped_items")
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
			"item_id": _resource_path(entry.definition),
			"count": int(entry.count),
			"grid_position": entry.grid_position,
			"contained_item_counts": entry.contained_item_counts.duplicate(true),
			"metadata": entry.metadata.duplicate(true),
		})
	return result


func _skill_levels_from_actor(actor: Node) -> Dictionary:
	var result := {}
	var skill_set = actor.get("skill_set")
	if skill_set != null and skill_set.has_method("get_all_entry_snapshots"):
		for snapshot in skill_set.call("get_all_entry_snapshots"):
			if snapshot is Dictionary:
				result[str(snapshot.get("skill_id", ""))] = int(snapshot.get("level", SkillRules.DEFAULT_LEVEL))
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
	return str(actor.get_path()) if actor != null and actor.is_inside_tree() else str(actor.name if actor != null else "")


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
	if int(record.get("life_state", NpcRules.LifeState.ALIVE)) != NpcRules.LifeState.ALIVE:
		return "recovering"
	var hour := int(floor(float(max(absolute_minute, 0) % 1440) / 60.0)) if absolute_minute >= 0 else 12
	if hour >= 22 or hour < 6:
		return "resting"
	var role_id := str(record.get("role_id", "resident")).to_lower()
	if ["worker", "waiter", "barkeeper", "merchant", "guard", "warden", "ruler", "mayor"].has(role_id):
		return "working"
	return "routine"


func _increment_count(counts: Dictionary, key: String) -> void:
	var safe_key := key if not key.strip_edges().is_empty() else "unknown"
	counts[safe_key] = int(counts.get(safe_key, 0)) + 1


func _make_rng(actor_id: String, purpose: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = max(1, absi(("%s:%s" % [actor_id, purpose]).hash()))
	return rng


func _resource_path(resource) -> String:
	if resource == null:
		return ""
	if resource is Resource:
		return str((resource as Resource).resource_path)
	return ""


func _load_resource(path: String) -> Resource:
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
