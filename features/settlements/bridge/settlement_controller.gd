extends Node

class_name SettlementController

const SERVICE_ID := &"settlement"

signal settlement_state_changed(settlement_id: String, state: Dictionary)
signal settlement_event_recorded(event_record: Dictionary)
signal settlement_registered(settlement_id: String, definition: Resource)

const PRESSURE_SUPPLIED := "supplied"
const PRESSURE_HUNGRY := "hungry"
const PRESSURE_STARVING := "starving"
const META_SETTLEMENT_SLOT_ID := "settlement_staff_slot_id"
const META_ASSIGNMENT_SLOT_ID := "settlement_assignment_slot_id"
const META_ASSIGNMENT_DOMAIN := "settlement_assignment_domain"
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
const BOOTSTRAP_UNASSIGNED_POPULATION := 2
const MINUTES_PER_DAY := 24 * 60
const FEAR_PER_DEATH := 0.08

var root_scene: Node
var _context: BootstrapContext
var world_time: Node
var faction_controller: Node
var census: Node
var building_registry: BuildingRegistry
var settlement_definitions: Dictionary = {}
var settlement_states: Dictionary = {}
var settlement_anchors: Dictionary = {}
var event_log: Array[Dictionary] = []
var _staff_role_owners_by_settlement: Dictionary = {}
var _initialized := false


func initialize(context: BootstrapContext) -> void:
	root_scene = context.root_scene
	_context = context
	_try_initialize()


func _ready() -> void:
	add_to_group("settlement_controller")
	_try_initialize()


func get_settlement_definition(settlement_id: String) -> Resource:
	return settlement_definitions.get(settlement_id, null) as Resource


func get_settlement_anchor(settlement_id: String) -> Node3D:
	var anchor = settlement_anchors.get(settlement_id)
	if anchor == null or not is_instance_valid(anchor):
		settlement_anchors.erase(settlement_id)
		return null
	return anchor as Node3D


func register_settlement_anchor(anchor: Node3D) -> void:
	if anchor == null or not is_instance_valid(anchor):
		return
	_register_settlement_definition(anchor.get("settlement_definition") as Resource, anchor)


func unregister_settlement_anchor(anchor: Node3D) -> void:
	if anchor == null:
		return
	var settlement_id := str(anchor.call("get_settlement_id")) if anchor.has_method("get_settlement_id") else ""
	if settlement_id.is_empty():
		return
	if settlement_anchors.get(settlement_id) != anchor:
		return
	derealize_all_settlement_assignments(settlement_id)
	settlement_anchors.erase(settlement_id)
	_staff_role_owners_by_settlement.erase(settlement_id)


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


func get_settlement_buildings(settlement_id: String) -> Array[Dictionary]:
	return building_registry.get_buildings_for_settlement(settlement_id) if building_registry != null else []


func get_settlement_building_snapshot(settlement_id: String) -> Array[Dictionary]:
	return building_registry.get_settlement_building_snapshot(settlement_id) if building_registry != null else []


func get_available_population(settlement_id: String) -> int:
	if not settlement_states.has(settlement_id):
		return 0
	_refresh_population_availability(settlement_id)
	var state: Dictionary = settlement_states[settlement_id]
	return int(state.get("population_available", 0))


func can_assign_population(settlement_id: String, count := 1) -> bool:
	return get_available_population(settlement_id) >= max(0, count)


func bootstrap_assignments(settlement_id: String) -> void:
	_process_assignment_vacancies(settlement_id, true)


func assign_actor_to_assignment_slot(settlement_id: String, assignment_domain: String, slot_id: String, actor_id: String) -> Dictionary:
	var state: Dictionary = settlement_states.get(settlement_id, {})
	var slots: Dictionary = state.get("assignment_slots", {})
	var key := _assignment_key(assignment_domain, slot_id)
	var slot: Dictionary = (slots.get(key, {}) as Dictionary).duplicate(true)
	var population := _get_population_controller()
	if slot.is_empty() or population == null or not population.has_method("assign_record_to_slot"):
		return {}
	var record: Dictionary = population.call("assign_record_to_slot", actor_id, slot)
	if record.is_empty():
		return {}
	slot["occupant_actor_id"] = actor_id
	slot["filled"] = true
	slots[key] = slot
	var vacancies: Dictionary = state.get("assignment_vacancies", {})
	vacancies.erase(key)
	state["assignment_slots"] = slots
	state["assignment_vacancies"] = vacancies
	settlement_states[settlement_id] = state
	_apply_assignment_record_authorship(settlement_id, slot)
	_save_assignment_slot_to_gecs(settlement_id, slot)
	_save_settlement_state_to_gecs(settlement_id, state)
	return record


func release_actor_facility_assignments(actor_id: String, is_replacement := false) -> void:
	for settlement_id_value in settlement_states.keys():
		var settlement_id := str(settlement_id_value)
		var state: Dictionary = settlement_states[settlement_id]
		var slots: Dictionary = state.get("assignment_slots", {})
		var changed := false
		for key_value in slots.keys():
			var key := str(key_value)
			var slot: Dictionary = (slots[key] as Dictionary).duplicate(true)
			if str(slot.get("occupant_actor_id", "")) != actor_id:
				continue
			slot["occupant_actor_id"] = ""
			slot["filled"] = false
			if is_replacement:
				slot["dead_actor_key"] = actor_id
			slots[key] = slot
			_ensure_assignment_vacancy(settlement_id, slot, key)
			_save_assignment_slot_to_gecs(settlement_id, slot)
			_sync_assignment_owner_access(settlement_id, slot)
			changed = true
		if changed:
			state = settlement_states[settlement_id]
			state["assignment_slots"] = slots
			settlement_states[settlement_id] = state
			_notify_state_changed(settlement_id)


func _on_population_record_changed(_settlement_id: String, actor_id: String) -> void:
	var population := _get_population_controller()
	var record: Dictionary = population.call("get_actor_record", actor_id) if population != null and population.has_method("get_actor_record") else {}
	# The death signal releases assignments with replacement timing intact.
	if int(record.get("life_state", NpcRules.LifeState.ALIVE)) == NpcRules.LifeState.DEAD:
		return
	var assignments: Dictionary = record.get("assignments", {})
	for state_value in settlement_states.values():
		for slot_value in ((state_value as Dictionary).get("assignment_slots", {}) as Dictionary).values():
			var slot: Dictionary = slot_value
			if str(slot.get("occupant_actor_id", "")) != actor_id:
				continue
			var domain := str(slot.get("assignment_domain", "employment"))
			if str(assignments.get(domain, "")) != str(slot.get("slot_id", "")):
				release_actor_facility_assignments(actor_id)
				return


func _on_person_died(actor_id: String) -> void:
	release_actor_facility_assignments(actor_id, true)
	var population := _get_population_controller()
	if population == null or not population.has_method("get_actor_record") or not population.has_method("count_alive_records_for_settlement"):
		return
	var record: Dictionary = population.call("get_actor_record", actor_id)
	var settlement_id := str(record.get("settlement_id", ""))
	if settlement_id.is_empty() or not settlement_states.has(settlement_id):
		return
	_set_population_total(settlement_id, int(population.call("count_alive_records_for_settlement", settlement_id)))


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


func get_assignment_vacancy_count(settlement_id: String) -> int:
	if not settlement_states.has(settlement_id):
		return 0
	_refresh_population_availability(settlement_id)
	var state: Dictionary = settlement_states[settlement_id]
	var vacancies: Dictionary = state.get("assignment_vacancies", {})
	if vacancies.is_empty():
		return 0
	return mini(vacancies.size(), int(state.get("population_available", 0)))


func adjust_fear(settlement_id: String, delta: float, reason := "manual") -> float:
	if not settlement_states.has(settlement_id):
		return 0.0
	var state: Dictionary = settlement_states[settlement_id]
	var previous := float(state.get("fear", 0.0))
	state["fear"] = clampf(previous + delta, 0.0, 1.0)
	if not is_equal_approx(previous, float(state["fear"])):
		_save_settlement_state_to_gecs(settlement_id, state)
		_record_event({
			"type": "fear_changed",
			"settlement_id": settlement_id,
			"fear": float(state["fear"]),
			"reason": reason,
		})
	return float(state["fear"])


func adjust_wealth(settlement_id: String, delta: float, reason := "manual") -> float:
	if not settlement_states.has(settlement_id):
		return 0.0
	var state: Dictionary = settlement_states[settlement_id]
	state["wealth"] = maxf(float(state.get("wealth", 0.0)) + delta, 0.0)
	_save_settlement_state_to_gecs(settlement_id, state)
	_record_event({
		"type": "wealth_changed",
		"settlement_id": settlement_id,
		"wealth": float(state["wealth"]),
		"delta": delta,
		"reason": reason,
	})
	return float(state["wealth"])


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
	if building_registry != null:
		for building in building_registry.get_buildings_for_settlement(settlement_id):
			building_registry.update_building(str(building.get("building_id", "")), {"owner_faction_id": next_owner})
	_refresh_live_settlement_ownership(settlement_id)
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


func _refresh_live_settlement_ownership(settlement_id: String) -> void:
	var anchor := get_settlement_anchor(settlement_id)
	if anchor == null:
		return
	for facility in get_tree().get_nodes_in_group("settlement_facility"):
		if facility == null or not anchor.is_ancestor_of(facility):
			continue
		if facility.has_method("stamp_building_identity"):
			facility.call("stamp_building_identity")
		if facility.has_method("sync_property_ownership"):
			facility.call("sync_property_ownership")
		if facility.has_method("sync_door_policy"):
			facility.call("sync_door_policy")


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


func get_summary_text() -> String:
	var parts: Array[String] = []
	var food_controller: Node = _context.get_optional(&"settlement_food") if _context != null else null
	for settlement_id in settlement_states.keys():
		var state: Dictionary = settlement_states[settlement_id]
		var food_status: Dictionary = food_controller.get_status(str(settlement_id)) if food_controller != null else {}
		parts.append("%s: %s food units, %s" % [state.get("display_name", settlement_id), int(round(float(food_status.get("food_units", 0.0)))), str(food_status.get("pressure_state", PRESSURE_SUPPLIED)).capitalize()])
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
	world_time = _context.get_optional(WorldTimeController.SERVICE_ID) if _context != null else null
	if world_time == null:
		return
	faction_controller = _context.get_optional(FactionController.SERVICE_ID)
	census = _context.get_optional(&"settlement_census")
	var population := _context.get_optional(PopulationController.SERVICE_ID)
	if population != null and population.has_signal("person_died") and not population.person_died.is_connected(_on_person_died):
		population.person_died.connect(_on_person_died)
	if population != null and population.has_signal("population_record_changed") and not population.population_record_changed.is_connected(_on_population_record_changed):
		population.population_record_changed.connect(_on_population_record_changed)
	building_registry = _context.require(BuildingRegistry.SERVICE_ID) as BuildingRegistry
	if not building_registry.building_created.is_connected(_on_building_registry_changed):
		building_registry.building_created.connect(_on_building_registry_changed)
	if not building_registry.building_updated.is_connected(_on_building_registry_changed):
		building_registry.building_updated.connect(_on_building_registry_changed)
	if not building_registry.registry_rebuilt.is_connected(_on_building_registry_rebuilt):
		building_registry.registry_rebuilt.connect(_on_building_registry_rebuilt)
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
		_refresh_settlement_housing_capacity(settlement_id, false)
		_register_anchor_facilities(settlement_id, anchor)
		_sync_settlement_assignment_slots(settlement_id)
		_apply_population_from_occupancy(settlement_id)
		# A registry-known settlement gained its live anchor (zone loaded):
		# real housing/staff demand exists only now, so seed here too —
		# seed_settlement no-ops if records already exist.
		if census != null and census.has_method("seed_settlement"):
			census.call_deferred("seed_settlement", settlement_id)
		_notify_state_changed(settlement_id)
	if faction_controller != null and faction_controller.has_method("register_faction"):
		faction_controller.call("register_faction", definition.get("faction_definition") as Resource)
	settlement_registered.emit(settlement_id, definition)


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
		"occupancy_state": _definition_occupancy_key(definition),
		"occupancy_label": _definition_occupancy_label(definition),
		"occupancy_multiplier": _definition_occupancy_multiplier(definition),
		"occupancy_ratio": 1.0,
		"wealth": maxf(_resource_float(definition, "starting_wealth", 0.0), 0.0),
		"supplies": maxf(_resource_float(definition, "starting_supplies", 0.0), 0.0),
		"fear": 0.0,
		"morale": 1.0,
		"last_action_absolute_hour": -999999,
		"last_action": "Idle",
		"world_position": position,
		"facilities": {},
		"facility_totals": {},
		"assignment_slots": {},
		"assignment_vacancies": {},
		"population_death_records": {},
	}
	_refresh_settlement_housing_capacity(settlement_id, false)
	_register_anchor_facilities(settlement_id, anchor)
	_sync_settlement_assignment_slots(settlement_id)
	_apply_population_from_occupancy(settlement_id)
	# Born settled: the census mints a resident record for every staff slot
	# plus surplus before vacancies process, so day zero starts staffed.
	if census != null and census.has_method("seed_settlement"):
		census.call_deferred("seed_settlement", settlement_id)
	call_deferred("_bootstrap_assignments", settlement_id)
	_notify_state_changed(settlement_id)


func _on_hour_changed(_absolute_hour: int, _day_index: int, _hour: int) -> void:
	for settlement_id in settlement_definitions.keys():
		var sid := str(settlement_id)
		# Assignment is world-sim knowledge and runs O(1) for EVERY town, near or far — a faraway
		# bar knows who tends it without the player ever visiting. It's a cheap ledger bind: no
		# subtree walk, no live bodies.
		_assign_from_ledger(sid)
		# The expensive work — the full subtree walk + GECS re-save to reconcile slot definitions
		# and dead bodies, plus putting live staff bodies in place — only matters where the player
		# can see them. Gating keeps the hourly cost O(near towns), not O(all towns).
		if not _settlement_is_within_lod_exit(sid):
			continue
		_sync_settlement_assignment_slots(sid)
		_assign_from_ledger(sid)
		_sync_settlement_resident_deaths(sid)


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


func _settlement_is_within_lod_exit(settlement_id: String) -> bool:
	var controller := get_tree().get_first_node_in_group("population_realization_controller") if get_tree() != null else null
	return bool(controller.call("is_position_within_realization_range", _settlement_position(settlement_id), true)) if controller != null and controller.has_method("is_position_within_realization_range") else DisplayServer.get_name() == "headless"


func _notify_state_changed(settlement_id: String) -> void:
	var state: Dictionary = settlement_states.get(settlement_id, {}).duplicate(true)
	_save_settlement_state_to_gecs(settlement_id, state)
	var anchor := get_settlement_anchor(settlement_id)
	if anchor != null and anchor.has_method("apply_settlement_state"):
		anchor.call("apply_settlement_state", state)
	settlement_state_changed.emit(settlement_id, state)


func _sync_settlement_assignment_slots(settlement_id: String) -> void:
	if not settlement_states.has(settlement_id):
		return
	var anchor := get_settlement_anchor(settlement_id)
	if anchor == null:
		_refresh_population_availability(settlement_id)
		return
	var state: Dictionary = settlement_states[settlement_id]
	var prior_slots: Dictionary = state.get("assignment_slots", {})
	var slots: Dictionary = {}
	var assigned_count := 0
	var required_count := 0
	var vacancies: Dictionary = state.get("assignment_vacancies", {})
	var owners_by_id := {}
	for role_owner in _collect_staff_role_owners(anchor):
		if role_owner == null or not role_owner.has_method("get_assignment_slot_specs"):
			continue
		var owner_id := _staff_role_owner_id(role_owner, settlement_id)
		owners_by_id[owner_id] = role_owner
		var owner_slots = role_owner.call("get_assignment_slot_specs")
		if not (owner_slots is Array):
			continue
		for slot_value in owner_slots:
			if not (slot_value is Dictionary):
				continue
			var slot: Dictionary = (slot_value as Dictionary).duplicate(true)
			var slot_id := str(slot.get("slot_id", "")).strip_edges()
			if slot_id.is_empty():
				continue
			var domain := str(slot.get("assignment_domain", "employment")).strip_edges().to_lower()
			if domain.is_empty():
				continue
			var assignment_key := _assignment_key(domain, slot_id)
			slot["slot_id"] = slot_id
			slot["assignment_domain"] = domain
			slot["settlement_id"] = settlement_id
			slot["owner_id"] = owner_id
			slot["facility_id"] = str(role_owner.call("get_facility_id")) if role_owner.has_method("get_facility_id") else ""
			slot["building_id"] = str(role_owner.get("building_id")) if _has_property(role_owner, "building_id") else ""
			slot["world_position"] = (role_owner as Node3D).global_position if role_owner is Node3D else anchor.global_position
			var population_cost: int = max(0, int(slot.get("population_cost", 1)))
			slot["population_cost"] = population_cost
			if domain == "employment":
				required_count += population_cost
			# Ledger binding is the only source of truth for "filled". A scene body
			# without a permanent record must never bypass Character Realization.
			var occupant_actor_id := str((prior_slots.get(assignment_key, {}) as Dictionary).get("occupant_actor_id", ""))
			var dead_actor_key := str(slot.get("dead_actor_key", "")).strip_edges()
			# The bound worker is gone if the facility found its corpse (dead_actor_key) or its
			# record is dead/missing. Mark the record dead and drop the binding so the slot reopens.
			if not occupant_actor_id.is_empty() and (not dead_actor_key.is_empty() or not _is_assigned_record_alive(occupant_actor_id)):
				var pop := _get_population_controller()
				if pop != null:
					if pop.has_method("mark_record_dead"):
						pop.call("mark_record_dead", occupant_actor_id)
					# Detach the corpse from the slot so the next sync doesn't re-detect it as this
					# slot's worker (which would churn a fresh death every tick and drain population).
					# Both the slot-id meta AND the role node name resolve a slot's actor, so clear
					# the meta and rename the body off the role name — otherwise the name fallback
					# keeps finding the corpse and re-killing each freshly-assigned replacement.
					var corpse = pop.call("get_live_actor", occupant_actor_id) if pop.has_method("get_live_actor") else null
					if corpse != null and is_instance_valid(corpse):
						corpse.set_meta("settlement_staff_slot_id", "")
						corpse.name = "Corpse"
				occupant_actor_id = ""
			slot["occupant_actor_id"] = occupant_actor_id
			var filled := not occupant_actor_id.is_empty()
			slot["filled"] = filled
			slots[assignment_key] = slot
			if filled:
				if domain == "employment":
					assigned_count += population_cost
				vacancies.erase(assignment_key)
				_save_assignment_slot_to_gecs(settlement_id, slot)
				continue
			if not dead_actor_key.is_empty():
				_record_population_death_if_needed(settlement_id, dead_actor_key, null, "staff_death")
			_ensure_assignment_vacancy(settlement_id, slot, assignment_key)
			_save_assignment_slot_to_gecs(settlement_id, slot)
			state = settlement_states[settlement_id]
			vacancies = state.get("assignment_vacancies", {})
	var population := _get_population_controller()
	for prior_key_value in prior_slots.keys():
		var prior_key := str(prior_key_value)
		if slots.has(prior_key):
			continue
		var removed: Dictionary = prior_slots[prior_key]
		if population != null and population.has_method("release_assignment"):
			population.call("release_assignment", settlement_id, str(removed.get("assignment_domain", "employment")), str(removed.get("slot_id", "")))
		_remove_assignment_slot_from_gecs(settlement_id, removed)
	state["assignment_slots"] = slots
	for vacancy_id in vacancies.keys():
		if not slots.has(str(vacancy_id)):
			vacancies.erase(vacancy_id)
	state["assignment_vacancies"] = vacancies
	state["population_required_staff"] = required_count
	state["population_assigned"] = assigned_count
	settlement_states[settlement_id] = state
	_staff_role_owners_by_settlement[settlement_id] = owners_by_id
	for slot_value in slots.values():
		var filled_slot: Dictionary = slot_value
		if bool(filled_slot.get("filled", false)):
			_apply_assignment_record_authorship(settlement_id, filled_slot)
		_sync_assignment_owner_access(settlement_id, filled_slot)
	_refresh_population_availability(settlement_id)
	_save_settlement_state_to_gecs(settlement_id, state)
	_remove_unbound_assignment_bodies_for_settlement(settlement_id)


## Staffing has two layers. (1) Assignment is world-sim knowledge — a record is bound to a slot
## at the ledger level for every town, near or far, in O(records). (2) Realization (putting a live
## body in place) is LOD-gated and only happens when the player is near. This entry runs both:
## the cheap ledger bind always, the expensive body realization only when near.
func _process_assignment_vacancies(settlement_id: String, ignore_delay := false) -> void:
	if not settlement_states.has(settlement_id):
		return
	_assign_from_ledger(settlement_id, ignore_delay)
	_notify_state_changed(settlement_id)


## Cheap, player-independent: bind an available resident record to each open staff slot. Promoting
## the record's role_id removes it from the resident pool (so the population accounting balances)
## and is the durable "who staffs this" knowledge that survives LOD. No subtree walk, no live actors.
func _assign_from_ledger(settlement_id: String, ignore_delay := false) -> void:
	if not settlement_states.has(settlement_id):
		return
	var pop := _get_population_controller()
	if pop == null or not pop.has_method("claim_record_for_assignment"):
		return
	var state: Dictionary = settlement_states[settlement_id]
	var vacancies: Dictionary = state.get("assignment_vacancies", {})
	if vacancies.is_empty():
		return
	var slots: Dictionary = state.get("assignment_slots", {})
	var available := get_available_population(settlement_id)
	var now_minute := _get_absolute_minute()
	var changed := false
	var vacancy_keys := vacancies.keys()
	vacancy_keys.sort()
	for assignment_key_value in vacancy_keys:
		var assignment_key := str(assignment_key_value)
		var vacancy: Dictionary = vacancies.get(assignment_key, {})
		if not ignore_delay and now_minute < int(vacancy.get("replacement_due_minute", 0)):
			continue
		var cost: int = max(0, int(vacancy.get("population_cost", 1)))
		var domain := str(vacancy.get("assignment_domain", "employment"))
		if domain == "employment" and cost > available:
			continue
		var role_id := str(vacancy.get("role_id", "")).strip_edges()
		if role_id.is_empty():
			continue
		var slot: Dictionary = (slots.get(assignment_key, vacancy) as Dictionary).duplicate(true)
		var record: Dictionary = pop.call("claim_record_for_assignment", settlement_id, slot)
		if record.is_empty():
			continue
		slot["occupant_actor_id"] = str(record.get("actor_id", ""))
		slot["filled"] = true
		slots[assignment_key] = slot
		_apply_assignment_record_authorship(settlement_id, slot)
		_save_assignment_slot_to_gecs(settlement_id, slot)
		vacancies.erase(assignment_key)
		if domain == "employment":
			available -= cost
		changed = true
		_record_event({
			"type": "staff_assigned",
			"settlement_id": settlement_id,
			"slot_id": str(slot.get("slot_id", "")),
			"assignment_domain": str(slot.get("assignment_domain", "employment")),
			"role_id": role_id,
			"actor_id": str(record.get("actor_id", "")),
			"actor_name": str(record.get("member_name", record.get("actor_id", ""))),
		})
	if not changed:
		return
	state["assignment_slots"] = slots
	state["assignment_vacancies"] = vacancies
	var assigned := 0
	for sid_key in slots.keys():
		if str((slots[sid_key] as Dictionary).get("assignment_domain", "")) == "employment" and bool((slots[sid_key] as Dictionary).get("filled", false)):
			assigned += max(0, int((slots[sid_key] as Dictionary).get("population_cost", 1)))
	state["population_assigned"] = assigned
	settlement_states[settlement_id] = state
	_refresh_population_availability(settlement_id)
	_save_settlement_state_to_gecs(settlement_id, state)
func get_assignment_slots_for_realization(settlement_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var state: Dictionary = settlement_states.get(settlement_id, {})
	for slot_value in (state.get("assignment_slots", {}) as Dictionary).values():
		if slot_value is Dictionary:
			result.append((slot_value as Dictionary).duplicate(true))
	return result


func get_facility_assignment_slots(stable_owner_id: String, assignment_domain := "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for state_value in settlement_states.values():
		for slot_value in ((state_value as Dictionary).get("assignment_slots", {}) as Dictionary).values():
			var slot: Dictionary = slot_value
			if stable_owner_id != str(slot.get("owner_id", "")) and stable_owner_id != str(slot.get("facility_id", "")) and stable_owner_id != str(slot.get("building_id", "")):
				continue
			if not assignment_domain.is_empty() and str(slot.get("assignment_domain", "")) != assignment_domain:
				continue
			result.append(slot.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _assignment_key(str(a.get("assignment_domain", "")), str(a.get("slot_id", ""))) < _assignment_key(str(b.get("assignment_domain", "")), str(b.get("slot_id", ""))))
	return result


func get_facility_assignment_counts(stable_owner_id: String, assignment_domain := "") -> Dictionary:
	var slots := get_facility_assignment_slots(stable_owner_id, assignment_domain)
	var filled := 0
	for slot in slots:
		if not str(slot.get("occupant_actor_id", "")).is_empty():
			filled += 1
	return {"filled": filled, "expected": slots.size()}


func get_assignment_actor_display_name(actor_id: String) -> String:
	var population := _get_population_controller()
	var record: Dictionary = population.call("get_actor_record", actor_id) if population != null and population.has_method("get_actor_record") else {}
	return str(record.get("member_name", actor_id))


func get_facility_assignments_grouped_by_role(stable_owner_id: String, assignment_domain := "") -> Dictionary:
	var grouped := {}
	for slot in get_facility_assignment_slots(stable_owner_id, assignment_domain):
		var role_id := str(slot.get("role_id", ""))
		if not grouped.has(role_id):
			grouped[role_id] = []
		var entry := slot.duplicate(true)
		entry["actor_display_name"] = get_assignment_actor_display_name(str(slot.get("occupant_actor_id", ""))) if not str(slot.get("occupant_actor_id", "")).is_empty() else ""
		(grouped[role_id] as Array).append(entry)
	return grouped


func get_facility_people_snapshot(building_id: String, facility_id: String, settlement_id: String) -> Dictionary:
	var owner_id := facility_id.strip_edges()
	var slots := get_facility_assignment_slots(owner_id)
	if slots.is_empty() and not building_id.strip_edges().is_empty():
		owner_id = building_id.strip_edges()
		slots = get_facility_assignment_slots(owner_id)
	var rows: Array[Dictionary] = []
	var population := _get_population_controller()
	for slot in slots:
		var actor_id := str(slot.get("occupant_actor_id", "")).strip_edges()
		var record: Dictionary = population.call("get_actor_record", actor_id) if population != null and not actor_id.is_empty() else {}
		var preferred_actor_id := str(slot.get("preferred_actor_id", "")).strip_edges()
		var source := ""
		if not actor_id.is_empty():
			source = "named" if actor_id == preferred_actor_id and not preferred_actor_id.is_empty() else ("auto" if str(record.get("generation_source", "")).begins_with("assignment_auto") else "assigned")
		rows.append({
			"slot_id": str(slot.get("slot_id", "")),
			"group": str(slot.get("assignment_domain", "employment")),
			"role_id": str(slot.get("role_id", "role")),
			"actor_id": actor_id,
			"character_name": str(record.get("member_name", actor_id)),
			"source": source,
		})
	return {
		"display_name": _facility_display_name(settlement_id, facility_id),
		"rows": rows,
		"role_count": rows.size(),
	}


func _facility_display_name(settlement_id: String, facility_id: String) -> String:
	var state: Dictionary = settlement_states.get(settlement_id, {})
	var facility: Dictionary = (state.get("facilities", {}) as Dictionary).get(facility_id, {})
	var display_name := str(facility.get("display_name", "")).strip_edges()
	return display_name if not display_name.is_empty() else "Facility"


func is_assignment_slot_realized(settlement_id: String, assignment_domain: String, slot_id: String) -> bool:
	var state: Dictionary = settlement_states.get(settlement_id, {})
	var slot: Dictionary = (state.get("assignment_slots", {}) as Dictionary).get(_assignment_key(assignment_domain, slot_id), {})
	var actor_id := str(slot.get("occupant_actor_id", ""))
	var population := _get_population_controller()
	var actor = population.call("get_live_actor", actor_id) if population != null and population.has_method("get_live_actor") and not actor_id.is_empty() else null
	return actor != null and is_instance_valid(actor) and str(actor.get_meta(META_ASSIGNMENT_DOMAIN, "")) == assignment_domain and str(actor.get_meta(META_ASSIGNMENT_SLOT_ID, "")) == slot_id


## Realize one ledger-bound assignment. The facility configures only this body's projection.
func realize_assignment_slot(settlement_id: String, assignment_domain: String, slot_id: String) -> bool:
	if not settlement_states.has(settlement_id):
		return false
	var slots: Dictionary = (settlement_states[settlement_id] as Dictionary).get("assignment_slots", {})
	var slot: Dictionary = slots.get(_assignment_key(assignment_domain, slot_id), {})
	if not bool(slot.get("filled", false)):
		return false
	var actor_id := str(slot.get("occupant_actor_id", ""))
	if actor_id.is_empty():
		return false
	var role_owner := _staff_role_owner(settlement_id, slot)
	if role_owner == null or not role_owner.has_method("configure_settlement_assignment_actor") or not role_owner.has_method("get_assignment_realization_parent"):
		return false
	var population := _get_population_controller()
	var realizer := _context.get_optional(PopulationCharacterRealizer.SERVICE_ID) as PopulationCharacterRealizer if _context != null else null
	if realizer == null:
		push_error("Settlement assignment cannot realize %s/%s: PopulationCharacterRealizer is unavailable" % [assignment_domain, slot_id])
		return false
	var parent := role_owner.call("get_assignment_realization_parent") as Node
	var actor = population.call("get_live_actor", actor_id) if population != null and population.has_method("get_live_actor") else null
	if actor != null and is_instance_valid(actor) and actor.get_parent() == parent and str(actor.get_meta(META_ASSIGNMENT_DOMAIN, "")) == assignment_domain and str(actor.get_meta(META_ASSIGNMENT_SLOT_ID, "")) == slot_id:
		return true
	var durable_record: Dictionary = population.call("get_actor_record", actor_id) if population != null and population.has_method("get_actor_record") else {}
	var returning_assignment := bool((durable_record.get("assignment_realized_once", {}) as Dictionary).get(assignment_domain, false))
	actor = realizer.realize_actor(actor_id, role_owner, parent, "", str(slot.get("character_type_id", "")))
	if actor == null:
		return false
	var configuration_record := slot.duplicate(true)
	configuration_record["preserve_durable_transform"] = returning_assignment
	role_owner.call("configure_settlement_assignment_actor", actor, slot_id, configuration_record)
	actor.set_meta(META_ASSIGNMENT_DOMAIN, assignment_domain)
	actor.set_meta(META_ASSIGNMENT_SLOT_ID, slot_id)
	if returning_assignment and not durable_record.is_empty():
		var durable_movement: Dictionary = durable_record.get("movement_state", {})
		# Facility defaults win for a new assignment; returning workers resume their exact order.
		if actor.has_method("apply_population_runtime_state"):
			actor.call("apply_population_runtime_state", {}, durable_movement)
		# Role setup must never teleport a persistent person away from their durable position.
		realizer.restore_record_transform(actor as Node3D, durable_record)
	if population != null and population.has_method("update_actor_record"):
		var realized: Dictionary = (durable_record.get("assignment_realized_once", {}) as Dictionary).duplicate(true)
		realized[assignment_domain] = true
		population.call("update_actor_record", actor_id, {"assignment_realized_once": realized})
	if role_owner.has_method("sync_property_ownership"):
		role_owner.call("sync_property_ownership")
	if role_owner.has_method("sync_door_policy"):
		role_owner.call("sync_door_policy")
	refresh_actor_assignment_projections(settlement_id, actor_id)
	return is_assignment_slot_realized(settlement_id, assignment_domain, slot_id)


func _staff_role_owner(settlement_id: String, slot: Dictionary) -> Node:
	var owners: Dictionary = _staff_role_owners_by_settlement.get(settlement_id, {})
	var owner: Node = owners.get(str(slot.get("owner_id", "")))
	if owner != null and is_instance_valid(owner):
		return owner
	var anchor := get_settlement_anchor(settlement_id)
	if anchor == null:
		return null
	owners = {}
	for candidate in _collect_staff_role_owners(anchor):
		owners[_staff_role_owner_id(candidate, settlement_id)] = candidate
	_staff_role_owners_by_settlement[settlement_id] = owners
	return owners.get(str(slot.get("owner_id", ""))) as Node


func _apply_assignment_record_authorship(settlement_id: String, slot: Dictionary) -> void:
	var actor_id := str(slot.get("occupant_actor_id", ""))
	if actor_id.is_empty():
		return
	var role_owner := _staff_role_owner(settlement_id, slot)
	var realizer := _context.get_optional(PopulationCharacterRealizer.SERVICE_ID) as PopulationCharacterRealizer if _context != null else null
	if role_owner != null and realizer != null:
		realizer.apply_record_authorship(actor_id, role_owner, str(slot.get("character_type_id", "")))
	_sync_assignment_owner_access(settlement_id, slot)


func _sync_assignment_owner_access(settlement_id: String, slot: Dictionary) -> void:
	var role_owner := _staff_role_owner(settlement_id, slot)
	if role_owner != null and role_owner.has_method("sync_door_policy"):
		role_owner.call("sync_door_policy")


func refresh_assignment_slot_projection(settlement_id: String, assignment_domain: String, slot_id: String, routine_activity_override := "") -> void:
	var state: Dictionary = settlement_states.get(settlement_id, {})
	var slot: Dictionary = (state.get("assignment_slots", {}) as Dictionary).get(_assignment_key(assignment_domain, slot_id), {})
	var actor_id := str(slot.get("occupant_actor_id", ""))
	var population := _get_population_controller()
	var actor = population.call("get_live_actor", actor_id) if population != null and population.has_method("get_live_actor") else null
	if actor == null or not is_instance_valid(actor):
		return
	var is_primary_assignment := str(actor.get_meta(META_ASSIGNMENT_DOMAIN, "")) == assignment_domain \
			and str(actor.get_meta(META_ASSIGNMENT_SLOT_ID, "")) == slot_id
	# Residence remains available as a secondary relationship when employment
	# owns the actor's primary realization; facility duty arbitrates precedence.
	if not is_primary_assignment and assignment_domain != "residence":
		return
	var role_owner := _staff_role_owner(settlement_id, slot)
	if role_owner != null and role_owner.has_method("refresh_settlement_assignment_actor"):
		var projection_record := slot.duplicate(true)
		if not routine_activity_override.is_empty():
			projection_record["routine_activity_state"] = routine_activity_override
		elif population.has_method("get_actor_routine_activity"):
			projection_record["routine_activity_state"] = population.call("get_actor_routine_activity", actor_id, _get_absolute_minute())
		role_owner.call("refresh_settlement_assignment_actor", actor, projection_record)


func refresh_actor_assignment_projections(settlement_id: String, actor_id: String) -> void:
	var state: Dictionary = settlement_states.get(settlement_id, {})
	for slot_value in (state.get("assignment_slots", {}) as Dictionary).values():
		var slot: Dictionary = slot_value
		if str(slot.get("occupant_actor_id", "")) != actor_id:
			continue
		refresh_assignment_slot_projection(settlement_id, str(slot.get("assignment_domain", "")), str(slot.get("slot_id", "")))


func refresh_actor_residence_projection(settlement_id: String, actor_id: String, routine_activity := "home_day") -> void:
	var state: Dictionary = settlement_states.get(settlement_id, {})
	for slot_value in (state.get("assignment_slots", {}) as Dictionary).values():
		var slot: Dictionary = slot_value
		if str(slot.get("occupant_actor_id", "")) != actor_id or str(slot.get("assignment_domain", "")) != "residence":
			continue
		refresh_assignment_slot_projection(settlement_id, "residence", str(slot.get("slot_id", "")), routine_activity)


func _remove_unbound_assignment_bodies_for_settlement(settlement_id: String) -> void:
	var state: Dictionary = settlement_states.get(settlement_id, {})
	var expected_actor_ids := {}
	for slot_value in (state.get("assignment_slots", {}) as Dictionary).values():
		var actor_id := str((slot_value as Dictionary).get("occupant_actor_id", ""))
		if not actor_id.is_empty():
			expected_actor_ids[actor_id] = true
	var cleaned_parents := {}
	var population := _get_population_controller()
	for owner in (_staff_role_owners_by_settlement.get(settlement_id, {}) as Dictionary).values():
		if owner == null or not is_instance_valid(owner) or not owner.has_method("get_assignment_realization_parent"):
			continue
		var parent := owner.call("get_assignment_realization_parent") as Node
		if parent == null or cleaned_parents.has(parent):
			continue
		cleaned_parents[parent] = true
		for child in parent.get_children():
			if not (child is WorldActor) or int(child.get("life_state")) == NpcRules.LifeState.DEAD:
				continue
			var actor_id := str(child.get_meta("actor_record_id", ""))
			if not actor_id.is_empty() and expected_actor_ids.has(actor_id):
				continue
			if not actor_id.is_empty() and population != null and population.has_method("unregister_actor"):
				population.call("unregister_actor", child)
			child.queue_free()


func derealize_assignment_slot(settlement_id: String, assignment_domain: String, slot_id: String) -> void:
	if not settlement_states.has(settlement_id):
		return
	var pop := _get_population_controller()
	if pop == null or not pop.has_method("get_live_actor"):
		return
	var slots: Dictionary = (settlement_states[settlement_id] as Dictionary).get("assignment_slots", {})
	var worker := str((slots.get(_assignment_key(assignment_domain, slot_id), {}) as Dictionary).get("occupant_actor_id", ""))
	if worker.is_empty():
		return
	var actor = pop.call("get_live_actor", worker)
	if actor == null or not is_instance_valid(actor):
		return
	if str(actor.get_meta(META_ASSIGNMENT_DOMAIN, "")) != assignment_domain or str(actor.get_meta(META_ASSIGNMENT_SLOT_ID, "")) != slot_id:
		return
	if actor.has_method("is_player_party_member") and bool(actor.call("is_player_party_member")):
		return
	if pop.has_method("unregister_actor"):
		pop.call("unregister_actor", actor)
	actor.queue_free()


func derealize_all_settlement_assignments(settlement_id: String) -> void:
	var state: Dictionary = settlement_states.get(settlement_id, {})
	for slot_value in (state.get("assignment_slots", {}) as Dictionary).values():
		var slot: Dictionary = slot_value
		derealize_assignment_slot(settlement_id, str(slot.get("assignment_domain", "")), str(slot.get("slot_id", "")))


func _get_population_controller() -> Node:
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group("population_controller")


func _is_assigned_record_alive(actor_id: String) -> bool:
	var pop := _get_population_controller()
	if pop == null or not pop.has_method("is_record_alive"):
		return true  # Can't verify yet — assume alive so we don't churn a valid binding.
	return bool(pop.call("is_record_alive", actor_id))


func _bootstrap_assignments(settlement_id: String) -> void:
	bootstrap_assignments(settlement_id)


func _ensure_assignment_vacancy(settlement_id: String, slot: Dictionary, assignment_key: String) -> void:
	if not settlement_states.has(settlement_id):
		return
	var state: Dictionary = settlement_states[settlement_id]
	var vacancies: Dictionary = state.get("assignment_vacancies", {})
	if vacancies.has(assignment_key):
		state["assignment_vacancies"] = vacancies
		return
	var now_minute := _get_absolute_minute()
	var is_replacement := not str(slot.get("dead_actor_key", "")).strip_edges().is_empty()
	var delay_days := maxf(float(slot.get("replacement_delay_days", DEFAULT_STAFF_REPLACEMENT_DELAY_DAYS)), 0.0) if is_replacement else 0.0
	var vacancy := {
		"slot_id": str(slot.get("slot_id", "")),
		"assignment_domain": str(slot.get("assignment_domain", "employment")),
		"authority_scope": str(slot.get("authority_scope", "")),
		"assignment_exclusivity_group": str(slot.get("assignment_exclusivity_group", "")),
		"settlement_id": settlement_id,
		"role_id": str(slot.get("role_id", "")),
		"role_index": int(slot.get("role_index", 0)),
		"display_name": str(slot.get("display_name", slot.get("slot_id", ""))),
		"owner_id": str(slot.get("owner_id", "")),
		"population_cost": max(0, int(slot.get("population_cost", 1))),
		"replacement_delay_days": delay_days,
		"vacant_since_minute": now_minute,
		"replacement_due_minute": now_minute + int(round(delay_days * float(MINUTES_PER_DAY))),
	}
	vacancies[assignment_key] = vacancy
	state["assignment_vacancies"] = vacancies
	_record_event({
		"type": "staff_vacancy_created",
		"settlement_id": settlement_id,
		"slot_id": str(slot.get("slot_id", "")),
		"assignment_domain": str(slot.get("assignment_domain", "employment")),
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


func _staff_role_owner_id(owner: Node, settlement_id: String) -> String:
	if owner != null and owner.has_method("get_facility_id"):
		var facility_id := str(owner.call("get_facility_id")).strip_edges()
		if not facility_id.is_empty():
			return facility_id
	return settlement_id


func _collect_staff_role_owners_recursive(node: Node, owners: Array[Node]) -> void:
	if node == null:
		return
	if node.is_in_group(STAFF_ROLE_OWNER_GROUP) or node.has_method("get_assignment_slot_specs"):
		owners.append(node)
	for child in node.get_children():
		_collect_staff_role_owners_recursive(child, owners)


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
	# Violence scares the town: fear gates population growth and decays daily
	# (the census owns the decay).
	state["fear"] = clampf(float(state.get("fear", 0.0)) + FEAR_PER_DEATH, 0.0, 1.0)
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
	var facilities: Dictionary = {}
	for record in anchor.call("get_facility_records"):
		if not (record is Dictionary):
			continue
		var facility_id := str(record.get("facility_id", ""))
		if facility_id.is_empty():
			continue
		facilities[facility_id] = record.duplicate(true)
	state["facilities"] = facilities
	_recalculate_facility_totals(settlement_id)


func _refresh_settlement_housing_capacity(settlement_id: String, apply_population := true) -> void:
	if building_registry == null or not settlement_states.has(settlement_id):
		return
	var state: Dictionary = settlement_states[settlement_id]
	var total := building_registry.get_settlement_housing_capacity(settlement_id)
	state["max_occupancy"] = total
	if apply_population:
		_apply_population_from_occupancy(settlement_id)
	else:
		state["population_target"] = total
	_refresh_population_availability(settlement_id)


func _on_building_registry_changed(building_id: String) -> void:
	call_deferred("_apply_building_registry_change", building_id)


func _apply_building_registry_change(building_id: String) -> void:
	refresh_from_gecs_state()
	var record := building_registry.get_building(building_id)
	var settlement_id := str(record.get("settlement_id", ""))
	if settlement_id.is_empty() or not settlement_states.has(settlement_id):
		return
	_refresh_settlement_housing_capacity(settlement_id)
	_notify_state_changed(settlement_id)


func _on_building_registry_rebuilt() -> void:
	call_deferred("_refresh_housing_after_registry_rebuild")


func _refresh_housing_after_registry_rebuild() -> void:
	# registry_rebuilt fires synchronously inside GECS load, before the world
	# simulation facade refreshes this controller's cached settlement states.
	refresh_from_gecs_state()
	for settlement_id in settlement_states.keys():
		_refresh_settlement_housing_capacity(str(settlement_id))
		_notify_state_changed(str(settlement_id))


func _recalculate_facility_totals(settlement_id: String) -> void:
	var state: Dictionary = settlement_states[settlement_id]
	var facilities: Dictionary = state.get("facilities", {})
	var totals := {
		"storage_capacity_bonus": 0.0,
		"activity_point_count": 0,
		"job_provider_count": 0,
		"bar_service_area_count": 0,
	}
	for record in facilities.values():
		if not (record is Dictionary):
			continue
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
	elif should_bootstrap_population and census != null:
		# Census-backed worlds: population is the count of living records; the
		# census reconciles it after seeding. Occupancy only shapes the target.
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


func _save_assignment_slot_to_gecs(settlement_id: String, slot: Dictionary) -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("upsert_assignment_slot"):
		bridge.call("upsert_assignment_slot", settlement_id, slot)


func _remove_assignment_slot_from_gecs(settlement_id: String, slot: Dictionary) -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("remove_assignment_slot"):
		bridge.call("remove_assignment_slot", settlement_id, str(slot.get("assignment_domain", "employment")), str(slot.get("slot_id", "")))


func _assignment_key(assignment_domain: String, slot_id: String) -> String:
	return "%s:%s" % [assignment_domain, slot_id]


func _get_gecs_world() -> Node:
	if not is_inside_tree():
		return null
	return _context.get_optional(GecsWorldController.SERVICE_ID) if _context != null else null


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
