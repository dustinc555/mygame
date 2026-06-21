extends Node

class_name SettlementController

signal settlement_state_changed(settlement_id: String, state: Dictionary)
signal settlement_event_recorded(event_record: Dictionary)

const PRESSURE_SUPPLIED := "supplied"
const PRESSURE_HUNGRY := "hungry"
const PRESSURE_STARVING := "starving"
const OCCUPANCY_DEPOPULATED := "depopulated"
const OCCUPANCY_SPARSE := "sparse"
const OCCUPANCY_POPULATED := "populated"
const OCCUPANCY_OVERCROWDED := "overcrowded"
const RAID_TARGET_DEFAULT := "default_target"
const RAID_TARGET_CLOSEST_PEER := "closest_peer"
const RAID_TARGET_BEST_RAID_TARGET := "best_raid_target"
const RAID_RELATION_ANY_NON_SELF := "any_non_self"
const RAID_RELATION_NOT_ALLIED := "not_allied"
const RAID_RELATION_HOSTILE_ONLY := "hostile_only"
const BLOCKED_NOT_ALLIED_STATES := ["alliance", "protectorate", "trade", "truce", "vassal", "tributary"]
const STAFF_ROLE_OWNER_GROUP := "settlement_staff_role_owner"
const DEFAULT_STAFF_REPLACEMENT_DELAY_DAYS := 7.0
const POPULATION_RECOVERY_PER_DAY := 1
const BOOTSTRAP_UNASSIGNED_POPULATION := 2
const MINUTES_PER_DAY := 24 * 60

var root_scene: Node
var world_time: Node
var faction_controller: Node
var settlement_definitions: Dictionary = {}
var settlement_states: Dictionary = {}
var settlement_anchors: Dictionary = {}
var event_log: Array[Dictionary] = []
var _initialized := false


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	_try_initialize()


func _ready() -> void:
	add_to_group("settlement_controller")
	_try_initialize()


func get_settlement_definition(settlement_id: String) -> Resource:
	return settlement_definitions.get(settlement_id, null) as Resource


func get_settlement_anchor(settlement_id: String) -> Node3D:
	return settlement_anchors.get(settlement_id, null) as Node3D


func get_raid_squad_template(settlement_id: String) -> Resource:
	var definition: Resource = get_settlement_definition(settlement_id)
	return definition.get("raid_squad_template") as Resource if definition != null else null


func get_settlement_state(settlement_id: String) -> Dictionary:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("get_settlement_state"):
		var ecs_state: Dictionary = bridge.call("get_settlement_state", settlement_id)
		if not ecs_state.is_empty():
			settlement_states[settlement_id] = ecs_state.duplicate(true)
			return ecs_state.duplicate(true)
	var state: Dictionary = settlement_states.get(settlement_id, {})
	return state.duplicate(true)


func get_available_population(settlement_id: String) -> int:
	if not settlement_states.has(settlement_id):
		return 0
	_refresh_population_availability(settlement_id)
	var state: Dictionary = settlement_states[settlement_id]
	return int(state.get("population_available", 0))


func can_assign_population(settlement_id: String, count := 1) -> bool:
	return get_available_population(settlement_id) >= max(0, count)


func bootstrap_staff_vacancies(settlement_id: String) -> void:
	_process_staff_vacancies(settlement_id, true)


func set_population_total(settlement_id: String, value: int, reason := "manual") -> Dictionary:
	if not settlement_states.has(settlement_id):
		return {}
	_set_population_total(settlement_id, value)
	var state: Dictionary = settlement_states[settlement_id]
	state["last_action"] = "Population set: %d" % int(state.get("population", 0))
	_record_event({
		"type": "population_set",
		"settlement_id": settlement_id,
		"population": int(state.get("population", 0)),
		"reason": reason,
	})
	_notify_state_changed(settlement_id)
	return get_settlement_state(settlement_id)


func get_staff_vacancy_realization_count(settlement_id: String) -> int:
	if not settlement_states.has(settlement_id):
		return 0
	_refresh_population_availability(settlement_id)
	var state: Dictionary = settlement_states[settlement_id]
	var vacancies: Dictionary = state.get("staff_vacancies", {})
	if vacancies.is_empty():
		return 0
	return mini(vacancies.size(), int(state.get("population_available", 0)))


func record_population_death(settlement_id: String, actor: Node, reason := "death") -> bool:
	if settlement_id.is_empty() or not settlement_states.has(settlement_id) or actor == null:
		return false
	return _record_population_death_if_needed(settlement_id, _actor_death_key(actor), actor, reason)


func get_all_settlement_states() -> Array[Dictionary]:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("get_settlement_states"):
		var ecs_states: Dictionary = bridge.call("get_settlement_states")
		if not ecs_states.is_empty():
			settlement_states = ecs_states.duplicate(true)
	var states: Array[Dictionary] = []
	for settlement_id in settlement_states.keys():
		states.append(get_settlement_state(str(settlement_id)))
	return states


func set_settlement_owner(settlement_id: String, faction_id: String, reason := "manual") -> Dictionary:
	if settlement_id.is_empty() or not settlement_states.has(settlement_id):
		return {}
	var state: Dictionary = settlement_states[settlement_id]
	var previous_owner := str(state.get("faction_id", ""))
	var next_owner := faction_id.strip_edges()
	if previous_owner == next_owner:
		return get_settlement_state(settlement_id)
	state["faction_id"] = next_owner
	state["last_action"] = "Owner changed: %s" % (next_owner if not next_owner.is_empty() else "None")
	_record_event({
		"type": "settlement_owner_changed",
		"settlement_id": settlement_id,
		"previous_faction_id": previous_owner,
		"faction_id": next_owner,
		"reason": reason,
	})
	_notify_state_changed(settlement_id)
	return get_settlement_state(settlement_id)


func adjust_food(settlement_id: String, amount: float, reason := "manual") -> float:
	if not settlement_states.has(settlement_id):
		return 0.0
	var state: Dictionary = settlement_states[settlement_id]
	var previous_food := float(state.get("food", 0.0))
	var max_food := maxf(float(state.get("max_food", 1.0)), 1.0)
	state["food"] = clampf(previous_food + amount, 0.0, max_food)
	_update_pressure_state(settlement_id)
	state["last_action"] = "Food %+.0f" % (float(state["food"]) - previous_food)
	_record_event({
		"type": "food_changed",
		"settlement_id": settlement_id,
		"amount": float(state["food"]) - previous_food,
		"reason": reason,
	})
	_notify_state_changed(settlement_id)
	return float(state["food"])


func set_food(settlement_id: String, amount: float, reason := "manual") -> float:
	if not settlement_states.has(settlement_id):
		return 0.0
	var state: Dictionary = settlement_states[settlement_id]
	return adjust_food(settlement_id, amount - float(state.get("food", 0.0)), reason)


func set_occupancy_state(settlement_id: String, occupancy_key: String, reason := "manual") -> Dictionary:
	if not settlement_states.has(settlement_id):
		return {}
	var state: Dictionary = settlement_states[settlement_id]
	var normalized_key := _normalize_occupancy_key(occupancy_key)
	state["occupancy_state"] = normalized_key
	state["occupancy_label"] = _occupancy_label(normalized_key)
	state["occupancy_multiplier"] = _occupancy_multiplier(normalized_key)
	_apply_population_from_occupancy(settlement_id, true)
	state["last_action"] = "Occupancy set: %s" % state["occupancy_label"]
	_record_event({
		"type": "occupancy_changed",
		"settlement_id": settlement_id,
		"occupancy_state": normalized_key,
		"population": state["population"],
		"reason": reason,
	})
	_notify_state_changed(settlement_id)
	return get_settlement_state(settlement_id)


func resolve_food_transfer(source_settlement_id: String, target_settlement_id: String, requested_amount: float, reason := "food_raid") -> float:
	if not settlement_states.has(source_settlement_id) or not settlement_states.has(target_settlement_id):
		return 0.0
	var target_state: Dictionary = settlement_states[target_settlement_id]
	var source_state: Dictionary = settlement_states[source_settlement_id]
	var stolen := minf(maxf(requested_amount, 0.0), float(target_state.get("food", 0.0)))
	var source_space := maxf(float(source_state.get("max_food", 0.0)) - float(source_state.get("food", 0.0)), 0.0)
	stolen = minf(stolen, source_space)
	if stolen <= 0.0:
		return 0.0
	adjust_food(target_settlement_id, -stolen, reason)
	adjust_food(source_settlement_id, stolen, reason)
	_record_event({
		"type": "food_transferred",
		"source_settlement_id": source_settlement_id,
		"target_settlement_id": target_settlement_id,
		"amount": stolen,
		"reason": reason,
	})
	return stolen


func get_summary_text() -> String:
	var parts: Array[String] = []
	for settlement_id in settlement_states.keys():
		var state: Dictionary = settlement_states[settlement_id]
		parts.append("%s: %s food, %s" % [state.get("display_name", settlement_id), int(round(float(state.get("food", 0.0)))), str(state.get("pressure_state", PRESSURE_SUPPLIED)).capitalize()])
	if parts.is_empty():
		return "World: Stable"
	return " | ".join(parts)


func serialize_state() -> Dictionary:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("get_settlement_states"):
		var ecs_states: Dictionary = bridge.call("get_settlement_states")
		if not ecs_states.is_empty():
			settlement_states = ecs_states.duplicate(true)
	return {
		"settlements": settlement_states.duplicate(true),
		"events": event_log.duplicate(true),
	}


func refresh_from_gecs_state() -> void:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_settlement_states"):
		return
	var ecs_states: Dictionary = bridge.call("get_settlement_states")
	if not ecs_states.is_empty():
		settlement_states = ecs_states.duplicate(true)


func _try_initialize() -> void:
	if _initialized or root_scene == null or not is_inside_tree():
		return
	world_time = get_parent().get_node_or_null("WorldTimeController")
	if world_time == null:
		return
	faction_controller = get_parent().get_node_or_null("FactionController")
	_collect_world_definitions()
	var hour_changed_callable := Callable(self, "_on_hour_changed")
	if world_time.has_signal("hour_changed") and not world_time.is_connected("hour_changed", hour_changed_callable):
		world_time.connect("hour_changed", hour_changed_callable)
	_initialized = true


func _collect_world_definitions() -> void:
	for node in get_tree().get_nodes_in_group("world_sim_registry"):
		var definitions = node.get("settlement_definitions")
		if definitions is Array:
			for definition in definitions:
				if definition is Resource:
					_register_settlement_definition(definition, null)
	for node in get_tree().get_nodes_in_group("settlement_anchor"):
		_register_settlement_definition(node.get("settlement_definition") as Resource, node as Node3D)


func _register_settlement_definition(definition: Resource, anchor: Node3D) -> void:
	if definition == null:
		return
	var settlement_id: String = _resource_id(definition)
	if settlement_id.is_empty():
		return
	settlement_definitions[settlement_id] = definition
	if anchor != null:
		settlement_anchors[settlement_id] = anchor
	if not settlement_states.has(settlement_id):
		_create_settlement_state(definition, anchor)
	elif anchor != null:
		var state: Dictionary = settlement_states[settlement_id]
		state["world_position"] = anchor.global_position
		_register_anchor_population_capacity(settlement_id, anchor, false)
		_register_anchor_facilities(settlement_id, anchor)
		_sync_settlement_staff_slots(settlement_id)
		_apply_population_from_occupancy(settlement_id)
		_notify_state_changed(settlement_id)
	if faction_controller != null and faction_controller.has_method("register_faction"):
		faction_controller.call("register_faction", definition.get("faction_definition") as Resource)


func _create_settlement_state(definition: Resource, anchor: Node3D) -> void:
	var settlement_id: String = _resource_id(definition)
	var position: Vector3 = _resource_vector3(definition, "world_position", Vector3.ZERO)
	if anchor != null:
		position = anchor.global_position
	settlement_states[settlement_id] = {
		"settlement_id": settlement_id,
		"display_name": _resource_string(definition, "display_name", settlement_id),
		"faction_id": _definition_faction_id(definition),
		"population": 0,
		"population_target": 0,
		"population_assigned": 0,
		"population_available": 0,
		"population_required_staff": 0,
		"population_bootstrap_unassigned": BOOTSTRAP_UNASSIGNED_POPULATION,
		"population_shortfall": 0,
		"population_initialized": false,
		"max_occupancy": 0,
		"population_capacity_sources": [],
		"occupancy_state": _definition_occupancy_key(definition),
		"occupancy_label": _definition_occupancy_label(definition),
		"occupancy_multiplier": _definition_occupancy_multiplier(definition),
		"occupancy_ratio": 1.0,
		"food": clampf(_resource_float(definition, "starting_food", 0.0), 0.0, maxf(_resource_float(definition, "max_food", 1.0), 1.0)),
		"max_food": maxf(_resource_float(definition, "max_food", 1.0), 1.0),
		"morale": 1.0,
		"food_ratio": 1.0,
		"pressure_state": PRESSURE_SUPPLIED,
		"last_upkeep_day": -1,
		"last_action_absolute_hour": -999999,
		"last_action": "Idle",
		"world_position": position,
		"facilities": {},
		"facility_totals": {},
		"staff_slots": {},
		"staff_vacancies": {},
		"population_death_records": {},
		"last_population_recovery_day": -1,
	}
	_register_anchor_population_capacity(settlement_id, anchor, false)
	_register_anchor_facilities(settlement_id, anchor)
	_sync_settlement_staff_slots(settlement_id)
	_apply_population_from_occupancy(settlement_id)
	_process_staff_vacancies(settlement_id, true)
	call_deferred("_bootstrap_staff_vacancies", settlement_id)
	_update_pressure_state(settlement_id)
	_notify_state_changed(settlement_id)


func _on_hour_changed(absolute_hour: int, day_index: int, hour: int) -> void:
	for settlement_id in settlement_definitions.keys():
		var sid := str(settlement_id)
		# Staff-slot sync (a full subtree walk + GECS re-save), vacancy filling and resident
		# death reconciliation only matter where the player can see live bodies. Off-screen
		# towns have no realized staff to sync and reconcile lazily on approach (the population
		# spawner re-bootstraps their vacancies — that's the promote-from-pool moment). Gating
		# here keeps the hourly cost O(near towns) instead of O(all towns) — the old ~20s spike.
		if not _settlement_is_near_player(sid):
			continue
		_sync_settlement_staff_slots(sid)
		_process_staff_vacancies(sid)
		_sync_settlement_resident_deaths(sid)
	# Daily upkeep is pure arithmetic on the settlement ledger (food in/out, pressure) and is
	# the believable background economy — it runs O(1) for every town, near or far.
	for settlement_id in settlement_definitions.keys():
		_process_daily_upkeep(str(settlement_id), day_index, hour)


func _process_daily_upkeep(settlement_id: String, day_index: int, hour: int) -> void:
	var definition: Resource = get_settlement_definition(settlement_id)
	var profile := _definition_behavior_profile(definition)
	if profile == null:
		return
	if hour != _resource_int(profile, "daily_upkeep_hour", 6):
		return
	var state: Dictionary = settlement_states[settlement_id]
	if int(state.get("last_upkeep_day", -1)) == day_index:
		return
	state["last_upkeep_day"] = day_index
	var facility_totals: Dictionary = state.get("facility_totals", {})
	var produced := maxf(_resource_float(profile, "food_production_per_day", 0.0) + float(facility_totals.get("food_production_per_day", 0.0)), 0.0)
	var consumed := maxf(float(state.get("population", 1)) * _resource_float(profile, "food_consumption_per_person_per_day", 1.0) + float(facility_totals.get("food_consumption_per_day", 0.0)), 0.0)
	var previous_food := float(state.get("food", 0.0))
	state["food"] = clampf(previous_food + produced - consumed, 0.0, float(state.get("max_food", 1.0)))
	_update_pressure_state(settlement_id)
	_process_population_recovery(settlement_id, day_index)
	state["last_action"] = "Daily upkeep %+.0f food" % (float(state["food"]) - previous_food)
	_record_event({
		"type": "daily_upkeep",
		"settlement_id": settlement_id,
		"day": day_index,
		"hour": hour,
		"produced_food": produced,
		"consumed_food": consumed,
		"food_delta": float(state["food"]) - previous_food,
	})
	_notify_state_changed(settlement_id)


func _update_pressure_state(settlement_id: String) -> void:
	var state: Dictionary = settlement_states[settlement_id]
	var max_food := maxf(float(state.get("max_food", 1.0)), 1.0)
	var ratio := clampf(float(state.get("food", 0.0)) / max_food, 0.0, 1.0)
	state["food_ratio"] = ratio
	if ratio <= 0.08:
		state["pressure_state"] = PRESSURE_STARVING
	elif ratio <= 0.28:
		state["pressure_state"] = PRESSURE_HUNGRY
	else:
		state["pressure_state"] = PRESSURE_SUPPLIED


func _settlement_distance(source_settlement_id: String, target_settlement_id: String) -> float:
	return _flat_distance(_settlement_position(source_settlement_id), _settlement_position(target_settlement_id))


func _settlement_position(settlement_id: String) -> Vector3:
	var anchor := get_settlement_anchor(settlement_id)
	if anchor != null:
		return anchor.global_position
	var state: Dictionary = settlement_states.get(settlement_id, {})
	var position = state.get("world_position", Vector3.ZERO)
	return position if position is Vector3 else Vector3.ZERO


func _flat_distance(left: Vector3, right: Vector3) -> float:
	return Vector2(left.x, left.z).distance_to(Vector2(right.x, right.z))


## True when the player/party is within the population LOD radius of the settlement — i.e.
## its residents are realized (or about to be) as live bodies. Used to gate heavy per-hour
## reconciliation to towns the player can actually see; far towns reconcile on approach.
func _settlement_is_near_player(settlement_id: String) -> bool:
	var settlement_position := _settlement_position(settlement_id)
	var radius := _population_lod_radius()
	var tree := get_tree()
	if tree != null:
		var members := tree.get_nodes_in_group("party_member")
		for member in members:
			if member is Node3D and _flat_distance((member as Node3D).global_position, settlement_position) <= radius:
				return true
		if not members.is_empty():
			return false
	var reference := _fallback_player_reference_position()
	if reference == Vector3.INF:
		return true
	return _flat_distance(reference, settlement_position) <= radius


func _fallback_player_reference_position() -> Vector3:
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d() if viewport != null else null
	return camera.global_position if camera != null else Vector3.INF


## Shared population LOD radius (plus a small margin so a town that's realizing its bodies is
## definitely also staff-synced). Falls back if the realization controller isn't up yet.
func _population_lod_radius() -> float:
	var controller := get_tree().get_first_node_in_group("population_realization_controller") if get_tree() != null else null
	if controller != null:
		var radius_value = controller.get("near_player_radius")
		if radius_value != null:
			return float(radius_value) + 50.0
	return 490.0


func _notify_state_changed(settlement_id: String) -> void:
	var state: Dictionary = settlement_states.get(settlement_id, {}).duplicate(true)
	_save_settlement_state_to_gecs(settlement_id, state)
	var anchor := get_settlement_anchor(settlement_id)
	if anchor != null and anchor.has_method("apply_settlement_state"):
		anchor.call("apply_settlement_state", state)
	settlement_state_changed.emit(settlement_id, state)


func _sync_settlement_staff_slots(settlement_id: String) -> void:
	if not settlement_states.has(settlement_id):
		return
	var anchor := get_settlement_anchor(settlement_id)
	if anchor == null:
		_refresh_population_availability(settlement_id)
		return
	var state: Dictionary = settlement_states[settlement_id]
	var slots: Dictionary = {}
	var assigned_count := 0
	var required_count := 0
	var vacancies: Dictionary = state.get("staff_vacancies", {})
	_clear_staff_slots_for_settlement_in_gecs(settlement_id)
	for role_owner in _collect_staff_role_owners(anchor):
		if role_owner == null or not role_owner.has_method("get_settlement_staff_slots"):
			continue
		var owner_slots = role_owner.call("get_settlement_staff_slots")
		if not (owner_slots is Array):
			continue
		for slot_value in owner_slots:
			if not (slot_value is Dictionary):
				continue
			var slot: Dictionary = (slot_value as Dictionary).duplicate(true)
			var slot_id := str(slot.get("slot_id", "")).strip_edges()
			if slot_id.is_empty():
				continue
			slot["slot_id"] = slot_id
			slot["settlement_id"] = settlement_id
			if not slot.has("owner_path"):
				slot["owner_path"] = anchor.get_path_to(role_owner)
			var population_cost: int = max(0, int(slot.get("population_cost", 1)))
			slot["population_cost"] = population_cost
			required_count += population_cost
			var filled := bool(slot.get("filled", false))
			slot["filled"] = filled
			slots[slot_id] = slot
			if filled:
				assigned_count += population_cost
				if vacancies.has(slot_id):
					vacancies.erase(slot_id)
				_save_staff_slot_to_gecs(settlement_id, slot_id, slot)
				continue
			var dead_actor_key := str(slot.get("dead_actor_key", "")).strip_edges()
			if not dead_actor_key.is_empty():
				_record_population_death_if_needed(settlement_id, dead_actor_key, null, "staff_death")
			_ensure_staff_vacancy(settlement_id, slot_id, slot)
			_save_staff_slot_to_gecs(settlement_id, slot_id, slot)
			state = settlement_states[settlement_id]
			vacancies = state.get("staff_vacancies", {})
	state["staff_slots"] = slots
	for vacancy_id in vacancies.keys():
		if not slots.has(str(vacancy_id)):
			vacancies.erase(vacancy_id)
	state["staff_vacancies"] = vacancies
	state["population_required_staff"] = required_count
	state["population_assigned"] = assigned_count
	settlement_states[settlement_id] = state
	_refresh_population_availability(settlement_id)
	_save_settlement_state_to_gecs(settlement_id, state)


func _process_staff_vacancies(settlement_id: String, ignore_delay := false) -> void:
	if not settlement_states.has(settlement_id):
		return
	var state: Dictionary = settlement_states[settlement_id]
	var vacancies: Dictionary = state.get("staff_vacancies", {})
	if vacancies.is_empty():
		return
	var now_minute := _get_absolute_minute()
	var available_population := get_available_population(settlement_id)
	for slot_id_value in vacancies.keys():
		var slot_id := str(slot_id_value)
		var vacancy: Dictionary = vacancies.get(slot_id, {})
		if not ignore_delay and now_minute < int(vacancy.get("replacement_due_minute", 0)):
			continue
		var cost: int = max(0, int(vacancy.get("population_cost", 1)))
		if cost > available_population:
			continue
		if _fill_staff_vacancy(settlement_id, slot_id, vacancy):
			available_population -= cost
			vacancies.erase(slot_id)
	state["staff_vacancies"] = vacancies
	_sync_settlement_staff_slots(settlement_id)
	_notify_state_changed(settlement_id)


func _bootstrap_staff_vacancies(settlement_id: String) -> void:
	bootstrap_staff_vacancies(settlement_id)


func _fill_staff_vacancy(settlement_id: String, slot_id: String, vacancy: Dictionary) -> bool:
	var anchor := get_settlement_anchor(settlement_id)
	if anchor == null:
		return false
	var owner_path = vacancy.get("owner_path", NodePath(""))
	var role_owner := anchor.get_node_or_null(owner_path as NodePath) if owner_path is NodePath else anchor.get_node_or_null(NodePath(str(owner_path)))
	if role_owner == null or not role_owner.has_method("fill_settlement_staff_slot"):
		return false
	var actor = role_owner.call("fill_settlement_staff_slot", slot_id, vacancy.duplicate(true))
	if actor == null:
		return false
	_record_event({
		"type": "staff_replaced",
		"settlement_id": settlement_id,
		"slot_id": slot_id,
		"role_id": str(vacancy.get("role_id", "")),
		"actor_name": str(actor.get("member_name")) if _has_property(actor, "member_name") else str(actor.name),
	})
	return true


func _ensure_staff_vacancy(settlement_id: String, slot_id: String, slot: Dictionary) -> void:
	if not settlement_states.has(settlement_id):
		return
	var state: Dictionary = settlement_states[settlement_id]
	var vacancies: Dictionary = state.get("staff_vacancies", {})
	if vacancies.has(slot_id):
		state["staff_vacancies"] = vacancies
		return
	var now_minute := _get_absolute_minute()
	var is_replacement := not str(slot.get("dead_actor_key", "")).strip_edges().is_empty()
	var delay_days := maxf(float(slot.get("replacement_delay_days", DEFAULT_STAFF_REPLACEMENT_DELAY_DAYS)), 0.0) if is_replacement else 0.0
	var vacancy := {
		"slot_id": slot_id,
		"settlement_id": settlement_id,
		"role_id": str(slot.get("role_id", "")),
		"role_index": int(slot.get("role_index", 0)),
		"display_name": str(slot.get("display_name", slot_id)),
		"owner_path": slot.get("owner_path", NodePath("")),
		"population_cost": max(0, int(slot.get("population_cost", 1))),
		"replacement_delay_days": delay_days,
		"vacant_since_minute": now_minute,
		"replacement_due_minute": now_minute + int(round(delay_days * float(MINUTES_PER_DAY))),
	}
	vacancies[slot_id] = vacancy
	state["staff_vacancies"] = vacancies
	_record_event({
		"type": "staff_vacancy_created",
		"settlement_id": settlement_id,
		"slot_id": slot_id,
		"role_id": str(vacancy.get("role_id", "")),
		"replacement_due_minute": int(vacancy.get("replacement_due_minute", now_minute)),
	})


func _sync_settlement_resident_deaths(settlement_id: String) -> void:
	var anchor := get_settlement_anchor(settlement_id)
	if anchor == null or not anchor.has_method("get_resident_characters"):
		return
	for resident in anchor.call("get_resident_characters"):
		if resident == null or not is_instance_valid(resident):
			continue
		if _actor_life_state(resident) == NpcRules.LifeState.DEAD:
			_record_population_death_if_needed(settlement_id, _actor_death_key(resident), resident, "resident_death")


func _collect_staff_role_owners(root: Node) -> Array[Node]:
	var owners: Array[Node] = []
	_collect_staff_role_owners_recursive(root, owners)
	return owners


func _collect_staff_role_owners_recursive(node: Node, owners: Array[Node]) -> void:
	if node == null:
		return
	if node.is_in_group(STAFF_ROLE_OWNER_GROUP) or node.has_method("get_settlement_staff_slots"):
		owners.append(node)
	for child in node.get_children():
		_collect_staff_role_owners_recursive(child, owners)


func _process_population_recovery(settlement_id: String, day_index: int) -> void:
	if not settlement_states.has(settlement_id):
		return
	var state: Dictionary = settlement_states[settlement_id]
	if int(state.get("last_population_recovery_day", -1)) == day_index:
		return
	state["last_population_recovery_day"] = day_index
	if str(state.get("pressure_state", PRESSURE_SUPPLIED)) == PRESSURE_STARVING:
		_refresh_population_availability(settlement_id)
		return
	var target: int = max(0, int(state.get("population_target", 0)))
	var current: int = max(0, int(state.get("population", 0)))
	if current >= target:
		_refresh_population_availability(settlement_id)
		return
	var recovered := mini(POPULATION_RECOVERY_PER_DAY, target - current)
	_set_population_total(settlement_id, current + recovered)
	_record_event({
		"type": "population_recovered",
		"settlement_id": settlement_id,
		"amount": recovered,
		"population": int(state.get("population", 0)),
	})


func _record_population_death_if_needed(settlement_id: String, actor_key: String, actor: Node, reason: String) -> bool:
	if actor_key.strip_edges().is_empty() or not settlement_states.has(settlement_id):
		return false
	var state: Dictionary = settlement_states[settlement_id]
	var death_records: Dictionary = state.get("population_death_records", {})
	if death_records.has(actor_key):
		return false
	death_records[actor_key] = {
		"actor_key": actor_key,
		"actor_name": str(actor.get("member_name")) if actor != null and _has_property(actor, "member_name") else actor_key,
		"reason": reason,
		"absolute_minute": _get_absolute_minute(),
	}
	state["population_death_records"] = death_records
	_set_population_total(settlement_id, max(0, int(state.get("population", 0)) - 1))
	_record_event({
		"type": "population_death",
		"settlement_id": settlement_id,
		"actor_key": actor_key,
		"actor_name": str(death_records[actor_key].get("actor_name", actor_key)),
		"reason": reason,
		"population": int(state.get("population", 0)),
	})
	return true


func _set_population_total(settlement_id: String, value: int) -> void:
	if not settlement_states.has(settlement_id):
		return
	var state: Dictionary = settlement_states[settlement_id]
	var previous_population: int = max(0, int(state.get("population", 0)))
	state["population"] = max(0, value)
	var max_occupancy := maxf(float(state.get("max_occupancy", 0)), 0.0)
	state["occupancy_ratio"] = float(state.get("population", 0)) / max_occupancy if max_occupancy > 0.0 else 0.0
	_refresh_population_availability(settlement_id)
	_save_settlement_state_to_gecs(settlement_id, state)
	if int(state.get("population", 0)) != previous_population:
		_resync_population_spawners_for_settlement(settlement_id)


func _refresh_population_availability(settlement_id: String) -> void:
	if not settlement_states.has(settlement_id):
		return
	var state: Dictionary = settlement_states[settlement_id]
	var population: int = max(0, int(state.get("population", 0)))
	var assigned: int = clampi(int(state.get("population_assigned", 0)), 0, population)
	var target: int = max(0, int(state.get("population_target", population)))
	state["population_assigned"] = assigned
	state["population_available"] = max(0, population - assigned)
	state["population_shortfall"] = max(0, target - population)


func _register_anchor_facilities(settlement_id: String, anchor: Node3D) -> void:
	if anchor == null or not settlement_states.has(settlement_id):
		return
	if not anchor.has_method("get_facility_records"):
		return
	var state: Dictionary = settlement_states[settlement_id]
	var facilities: Dictionary = state.get("facilities", {})
	for record in anchor.call("get_facility_records"):
		if not (record is Dictionary):
			continue
		var facility_id := str(record.get("facility_id", ""))
		if facility_id.is_empty():
			continue
		facilities[facility_id] = record.duplicate(true)
	state["facilities"] = facilities
	_recalculate_facility_totals(settlement_id)


func _register_anchor_population_capacity(settlement_id: String, anchor: Node3D, apply_population := true) -> void:
	if anchor == null or not settlement_states.has(settlement_id):
		return
	var state: Dictionary = settlement_states[settlement_id]
	var records: Array[Dictionary] = []
	var total := 0
	if anchor.has_method("get_population_capacity_records"):
		for record in anchor.call("get_population_capacity_records"):
			if not (record is Dictionary):
				continue
			var capacity: int = max(0, int(record.get("population_capacity", 0)))
			if capacity <= 0:
				continue
			records.append(record.duplicate(true))
			total += capacity
	state["population_capacity_sources"] = records
	state["max_occupancy"] = total
	if apply_population:
		_apply_population_from_occupancy(settlement_id)
	else:
		state["population_target"] = total
	_refresh_population_availability(settlement_id)


func _recalculate_facility_totals(settlement_id: String) -> void:
	var state: Dictionary = settlement_states[settlement_id]
	var facilities: Dictionary = state.get("facilities", {})
	var totals := {
		"food_production_per_day": 0.0,
		"food_consumption_per_day": 0.0,
		"storage_capacity_bonus": 0.0,
		"activity_point_count": 0,
		"job_provider_count": 0,
		"bar_service_area_count": 0,
	}
	for record in facilities.values():
		if not (record is Dictionary):
			continue
		totals["food_production_per_day"] = float(totals["food_production_per_day"]) + float(record.get("food_production_per_day", 0.0))
		totals["food_consumption_per_day"] = float(totals["food_consumption_per_day"]) + float(record.get("food_consumption_per_day", 0.0))
		totals["storage_capacity_bonus"] = float(totals["storage_capacity_bonus"]) + float(record.get("storage_capacity_bonus", 0.0))
		totals["activity_point_count"] = int(totals["activity_point_count"]) + int(record.get("activity_point_count", 0))
		totals["job_provider_count"] = int(totals["job_provider_count"]) + int(record.get("job_provider_count", 0))
		totals["bar_service_area_count"] = int(totals["bar_service_area_count"]) + int(record.get("bar_service_area_count", 0))
	state["facility_totals"] = totals


func _apply_population_from_occupancy(settlement_id: String, fill_to_target := false) -> void:
	var state: Dictionary = settlement_states[settlement_id]
	var previous_population: int = max(0, int(state.get("population", 0)))
	var previous_target: int = max(0, int(state.get("population_target", 0)))
	var max_occupancy := maxf(float(state.get("max_occupancy", 0)), 0.0)
	if max_occupancy <= 0.0:
		state["population_target"] = 0
		if fill_to_target:
			state["population"] = 0
			state["population_initialized"] = true
		elif not bool(state.get("population_initialized", false)):
			state["population"] = 0
		else:
			state["population"] = max(0, int(state.get("population", 0)))
		state["occupancy_ratio"] = 0.0
		_refresh_population_availability(settlement_id)
		_save_settlement_state_to_gecs(settlement_id, state)
		if previous_population > 0 or previous_target > 0:
			_resync_population_spawners_for_settlement(settlement_id)
		return
	var required_staff: int = max(0, int(state.get("population_required_staff", 0)))
	var target_population: int = maxi(required_staff, max(0, int(round(max_occupancy))))
	state["population_target"] = target_population
	var should_bootstrap_population := not bool(state.get("population_initialized", false)) or (previous_target <= 0 and previous_population <= 0 and target_population > 0)
	if fill_to_target:
		state["population"] = target_population
		state["population_initialized"] = true
	elif should_bootstrap_population:
		state["population"] = _get_bootstrap_population(state)
		state["population_initialized"] = true
	else:
		state["population"] = max(0, int(state.get("population", 0)))
	state["occupancy_ratio"] = float(state["population"]) / max_occupancy
	_refresh_population_availability(settlement_id)
	_save_settlement_state_to_gecs(settlement_id, state)
	if int(state.get("population", 0)) != previous_population or int(state.get("population_target", 0)) != previous_target:
		_resync_population_spawners_for_settlement(settlement_id)


func _get_bootstrap_population(state: Dictionary) -> int:
	var target: int = max(0, int(state.get("population_target", 0)))
	var required_staff: int = max(0, int(state.get("population_required_staff", 0)))
	var unassigned: int = max(0, int(state.get("population_bootstrap_unassigned", BOOTSTRAP_UNASSIGNED_POPULATION)))
	return mini(target, required_staff + unassigned)


func _resync_population_spawners_for_settlement(settlement_id: String) -> void:
	if settlement_id.strip_edges().is_empty() or not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	for spawner in tree.get_nodes_in_group("population_spawner"):
		if spawner == null or not spawner.has_method("get_settlement_id"):
			continue
		if str(spawner.call("get_settlement_id")) != settlement_id:
			continue
		if spawner.has_method("mark_population_realization_dirty"):
			spawner.call("mark_population_realization_dirty")


func _get_effective_food_pressure(state: Dictionary) -> float:
	var food_ratio := float(state.get("food_ratio", 1.0))
	var occupancy_ratio := maxf(float(state.get("occupancy_ratio", 1.0)), 0.25)
	return clampf(food_ratio / occupancy_ratio, 0.0, 1.0)


func _get_absolute_minute() -> int:
	if world_time != null and world_time.has_method("get_absolute_minute"):
		return int(world_time.call("get_absolute_minute"))
	return 0


func _actor_life_state(actor: Node) -> int:
	if actor == null or not _has_property(actor, "life_state"):
		return NpcRules.LifeState.ALIVE
	return int(actor.get("life_state"))


func _actor_death_key(actor: Node) -> String:
	if actor == null:
		return ""
	if _has_property(actor, "stable_id"):
		var stable_id := str(actor.get("stable_id")).strip_edges()
		if not stable_id.is_empty():
			return stable_id
	if actor.is_inside_tree():
		return str(actor.get_path())
	return str(actor.get_instance_id())


func _has_property(object: Object, property_name: String) -> bool:
	if object == null:
		return false
	for property in object.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _save_settlement_state_to_gecs(settlement_id: String, state: Dictionary) -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("upsert_settlement_state"):
		bridge.call("upsert_settlement_state", settlement_id, state)


func _save_staff_slot_to_gecs(settlement_id: String, slot_id: String, slot: Dictionary) -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("upsert_staff_slot"):
		bridge.call("upsert_staff_slot", settlement_id, slot_id, slot)


func _clear_staff_slots_for_settlement_in_gecs(settlement_id: String) -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("clear_staff_slots_for_settlement"):
		bridge.call("clear_staff_slots_for_settlement", settlement_id)


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
	return null


func _record_event(event_record: Dictionary) -> void:
	if world_time != null:
		if world_time.has_method("get_absolute_minute"):
			event_record["absolute_minute"] = int(world_time.call("get_absolute_minute"))
		if world_time.has_method("get_day_index"):
			event_record["day"] = int(world_time.call("get_day_index"))
		if world_time.has_method("get_hour"):
			event_record["hour"] = int(world_time.call("get_hour"))
		if world_time.has_method("get_minute"):
			event_record["minute"] = int(world_time.call("get_minute"))
	event_log.append(event_record)
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("record_settlement_event"):
		bridge.call("record_settlement_event", event_record)
	settlement_event_recorded.emit(event_record.duplicate(true))


func _resource_id(resource: Resource) -> String:
	if resource != null and resource.has_method("get_id"):
		return str(resource.call("get_id"))
	return ""


func _definition_faction_id(definition: Resource) -> String:
	if definition != null and definition.has_method("get_faction_id"):
		return str(definition.call("get_faction_id"))
	return _resource_id(definition.get("faction_definition") as Resource) if definition != null else ""


func _definition_behavior_profile(definition: Resource) -> Resource:
	if definition == null:
		return null
	if definition.has_method("get_behavior_profile"):
		return definition.call("get_behavior_profile") as Resource
	return definition.get("behavior_profile") as Resource


func _definition_occupancy_key(definition: Resource) -> String:
	return _occupancy_key_from_index(_resource_int(definition, "occupancy_state", 2))


func _definition_occupancy_label(definition: Resource) -> String:
	if definition != null and definition.has_method("get_occupancy_label"):
		return str(definition.call("get_occupancy_label"))
	return _occupancy_label(_definition_occupancy_key(definition))


func _definition_occupancy_multiplier(definition: Resource) -> float:
	if definition != null and definition.has_method("get_occupancy_multiplier"):
		return float(definition.call("get_occupancy_multiplier"))
	return _occupancy_multiplier(_definition_occupancy_key(definition))


func _occupancy_key_from_index(index: int) -> String:
	match index:
		0:
			return OCCUPANCY_DEPOPULATED
		1:
			return OCCUPANCY_SPARSE
		3:
			return OCCUPANCY_OVERCROWDED
		_:
			return OCCUPANCY_POPULATED


func _normalize_occupancy_key(occupancy_key: String) -> String:
	match occupancy_key.to_lower():
		OCCUPANCY_DEPOPULATED, "depop", "low":
			return OCCUPANCY_DEPOPULATED
		OCCUPANCY_SPARSE, "half":
			return OCCUPANCY_SPARSE
		OCCUPANCY_OVERCROWDED, "crowded", "over":
			return OCCUPANCY_OVERCROWDED
		_:
			return OCCUPANCY_POPULATED


func _occupancy_label(occupancy_key: String) -> String:
	match occupancy_key:
		OCCUPANCY_DEPOPULATED:
			return "Depopulated"
		OCCUPANCY_SPARSE:
			return "Sparse"
		OCCUPANCY_OVERCROWDED:
			return "Overcrowded"
		_:
			return "Populated"


func _occupancy_multiplier(occupancy_key: String) -> float:
	match occupancy_key:
		OCCUPANCY_DEPOPULATED:
			return 0.25
		OCCUPANCY_SPARSE:
			return 0.5
		OCCUPANCY_OVERCROWDED:
			return 1.25
		_:
			return 1.0


func _resource_string(resource: Resource, property_name: String, fallback: String) -> String:
	if resource == null:
		return fallback
	var value = resource.get(property_name)
	return fallback if value == null else str(value)


func _resource_int(resource: Resource, property_name: String, fallback: int) -> int:
	if resource == null:
		return fallback
	var value = resource.get(property_name)
	return fallback if value == null else int(value)


func _resource_float(resource: Resource, property_name: String, fallback: float) -> float:
	if resource == null:
		return fallback
	var value = resource.get(property_name)
	return fallback if value == null else float(value)


func _resource_value(resource: Resource, property_name: String, fallback: Variant) -> Variant:
	if resource == null:
		return fallback
	var value = resource.get(property_name)
	return fallback if value == null else value


func _resource_vector3(resource: Resource, property_name: String, fallback: Vector3) -> Vector3:
	if resource == null:
		return fallback
	var value = resource.get(property_name)
	return value if value is Vector3 else fallback
