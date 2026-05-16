extends Node

class_name SettlementController

signal settlement_state_changed(settlement_id: String, state: Dictionary)
signal settlement_event_recorded(event_record: Dictionary)
signal settlement_action_requested(action_record: Dictionary)

const PRESSURE_SUPPLIED := "supplied"
const PRESSURE_HUNGRY := "hungry"
const PRESSURE_STARVING := "starving"
const OCCUPANCY_DEPOPULATED := "depopulated"
const OCCUPANCY_SPARSE := "sparse"
const OCCUPANCY_POPULATED := "populated"
const OCCUPANCY_OVERCROWDED := "overcrowded"

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
	var state: Dictionary = settlement_states.get(settlement_id, {})
	return state.duplicate(true)


func get_all_settlement_states() -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	for settlement_id in settlement_states.keys():
		states.append(get_settlement_state(str(settlement_id)))
	return states


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
	_apply_population_from_occupancy(settlement_id)
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


func force_food_raid(source_settlement_id: String, target_settlement_id: String) -> bool:
	return _request_food_raid(source_settlement_id, target_settlement_id, "forced_food_raid")


func get_summary_text() -> String:
	var parts: Array[String] = []
	for settlement_id in settlement_states.keys():
		var state: Dictionary = settlement_states[settlement_id]
		parts.append("%s: %s food, %s" % [state.get("display_name", settlement_id), int(round(float(state.get("food", 0.0)))), str(state.get("pressure_state", PRESSURE_SUPPLIED)).capitalize()])
	if parts.is_empty():
		return "World: Stable"
	return " | ".join(parts)


func serialize_state() -> Dictionary:
	return {
		"settlements": settlement_states.duplicate(true),
		"events": event_log.duplicate(true),
	}


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
		_register_anchor_population_capacity(settlement_id, anchor)
		_register_anchor_facilities(settlement_id, anchor)
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
	}
	_register_anchor_population_capacity(settlement_id, anchor)
	_register_anchor_facilities(settlement_id, anchor)
	_update_pressure_state(settlement_id)
	_notify_state_changed(settlement_id)


func _on_hour_changed(absolute_hour: int, day_index: int, hour: int) -> void:
	for settlement_id in settlement_definitions.keys():
		_process_daily_upkeep(str(settlement_id), day_index, hour)
	for settlement_id in settlement_definitions.keys():
		_evaluate_settlement_strategy(str(settlement_id), absolute_hour, day_index, hour)


func _process_daily_upkeep(settlement_id: String, day_index: int, hour: int) -> void:
	var definition: Resource = get_settlement_definition(settlement_id)
	var profile: Resource = definition.get("behavior_profile") as Resource if definition != null else null
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


func _evaluate_settlement_strategy(settlement_id: String, absolute_hour: int, day_index: int, hour: int) -> void:
	var definition: Resource = get_settlement_definition(settlement_id)
	var profile: Resource = definition.get("behavior_profile") as Resource if definition != null else null
	if profile == null:
		return
	if profile.has_method("is_hour_in_action_window") and not bool(profile.call("is_hour_in_action_window", hour)):
		return
	var state: Dictionary = settlement_states[settlement_id]
	var hours_since_action := float(absolute_hour - int(state.get("last_action_absolute_hour", -999999)))
	if hours_since_action < _resource_float(profile, "action_cooldown_hours", 6.0):
		return
	var food_pressure := _get_effective_food_pressure(state)
	if bool(profile.get("can_initiate_food_raids")) and food_pressure <= _resource_float(profile, "food_raid_pressure_threshold", 0.28):
		_request_food_raid(settlement_id, _resource_string(definition, "default_target_settlement_id", ""), "food_pressure", absolute_hour, day_index, hour)
		return
	if bool(profile.get("can_attack_when_starving")) and food_pressure <= _resource_float(profile, "desperate_attack_pressure_threshold", 0.08):
		_request_food_raid(settlement_id, _resource_string(definition, "default_target_settlement_id", ""), "desperation", absolute_hour, day_index, hour)


func _request_food_raid(source_settlement_id: String, target_settlement_id: String, reason := "food_raid", absolute_hour := -1, day_index := -1, hour := -1) -> bool:
	if source_settlement_id.is_empty() or target_settlement_id.is_empty():
		return false
	if not settlement_states.has(source_settlement_id) or not settlement_states.has(target_settlement_id):
		return false
	var definition: Resource = get_settlement_definition(source_settlement_id)
	if definition == null:
		return false
	var state: Dictionary = settlement_states[source_settlement_id]
	if absolute_hour < 0 and world_time != null and world_time.has_method("get_absolute_hour"):
		absolute_hour = int(world_time.call("get_absolute_hour"))
	if day_index < 0 and world_time != null and world_time.has_method("get_day_index"):
		day_index = int(world_time.call("get_day_index"))
	if hour < 0 and world_time != null and world_time.has_method("get_hour"):
		hour = int(world_time.call("get_hour"))
	state["last_action_absolute_hour"] = absolute_hour
	var template: Resource = definition.get("raid_squad_template") as Resource
	var action_record := {
		"action_id": "%s:%s:%d" % [source_settlement_id, target_settlement_id, absolute_hour],
		"type": "raid_food",
		"reason": reason,
		"source_settlement_id": source_settlement_id,
		"target_settlement_id": target_settlement_id,
		"faction_id": _definition_faction_id(definition),
		"squad_template_id": _resource_id(template) if template != null else "",
		"absolute_hour": absolute_hour,
		"day": day_index,
		"hour": hour,
	}
	state["last_action"] = "Raid requested: %s" % target_settlement_id
	_record_event(action_record.duplicate(true))
	settlement_action_requested.emit(action_record)
	_notify_state_changed(source_settlement_id)
	return true


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


func _notify_state_changed(settlement_id: String) -> void:
	var state := get_settlement_state(settlement_id)
	var anchor := get_settlement_anchor(settlement_id)
	if anchor != null and anchor.has_method("apply_settlement_state"):
		anchor.call("apply_settlement_state", state)
	settlement_state_changed.emit(settlement_id, state)


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


func _register_anchor_population_capacity(settlement_id: String, anchor: Node3D) -> void:
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
	_apply_population_from_occupancy(settlement_id)


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


func _apply_population_from_occupancy(settlement_id: String) -> void:
	var state: Dictionary = settlement_states[settlement_id]
	var max_occupancy := maxf(float(state.get("max_occupancy", 0)), 0.0)
	if max_occupancy <= 0.0:
		state["population"] = 0
		state["occupancy_ratio"] = 0.0
		return
	state["population"] = max(0, int(round(max_occupancy * float(state.get("occupancy_multiplier", 1.0)))))
	state["occupancy_ratio"] = float(state["population"]) / max_occupancy


func _get_effective_food_pressure(state: Dictionary) -> float:
	var food_ratio := float(state.get("food_ratio", 1.0))
	var occupancy_ratio := maxf(float(state.get("occupancy_ratio", 1.0)), 0.25)
	return clampf(food_ratio / occupancy_ratio, 0.0, 1.0)


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
	settlement_event_recorded.emit(event_record.duplicate(true))


func _resource_id(resource: Resource) -> String:
	if resource != null and resource.has_method("get_id"):
		return str(resource.call("get_id"))
	return ""


func _definition_faction_id(definition: Resource) -> String:
	if definition != null and definition.has_method("get_faction_id"):
		return str(definition.call("get_faction_id"))
	return _resource_id(definition.get("faction_definition") as Resource) if definition != null else ""


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


func _resource_vector3(resource: Resource, property_name: String, fallback: Vector3) -> Vector3:
	if resource == null:
		return fallback
	var value = resource.get(property_name)
	return value if value is Vector3 else fallback
