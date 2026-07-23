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
## Global staffing priority (2026-07-06 design; per-faction orders deferred).
## A vacancy may poach a worker from any role listed AFTER its own — the
## poached slot opens a vacancy in turn, so a massacre drains the labor
## market bottom-up instead of leaving the walls unmanned.
const ROLE_POACH_PRIORITY := ["ruler", "warden", "guard", "barkeeper", "merchant", "worker"]

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
		_sync_settlement_staff_slots(settlement_id)
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
		"staff_slots": {},
		"staff_vacancies": {},
		"population_death_records": {},
	}
	_refresh_settlement_housing_capacity(settlement_id, false)
	_register_anchor_facilities(settlement_id, anchor)
	_sync_settlement_staff_slots(settlement_id)
	_apply_population_from_occupancy(settlement_id)
	# Born settled: the census mints a resident record for every staff slot
	# plus surplus before vacancies process, so day zero starts staffed.
	if census != null and census.has_method("seed_settlement"):
		census.call_deferred("seed_settlement", settlement_id)
	_assign_staff_from_ledger(settlement_id, true)
	call_deferred("_bootstrap_staff_vacancies", settlement_id)
	_notify_state_changed(settlement_id)


func _on_hour_changed(_absolute_hour: int, _day_index: int, _hour: int) -> void:
	for settlement_id in settlement_definitions.keys():
		var sid := str(settlement_id)
		# Assignment is world-sim knowledge and runs O(1) for EVERY town, near or far — a faraway
		# bar knows who tends it without the player ever visiting. It's a cheap ledger bind: no
		# subtree walk, no live bodies.
		_assign_staff_from_ledger(sid)
		# The expensive work — the full subtree walk + GECS re-save to reconcile slot definitions
		# and dead bodies, plus putting live staff bodies in place — only matters where the player
		# can see them. Gating keeps the hourly cost O(near towns), not O(all towns).
		if not _settlement_is_near_player(sid):
			continue
		_sync_settlement_staff_slots(sid)
		_assign_staff_from_ledger(sid)
		_realize_staff_bodies(sid)
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
	var prior_slots: Dictionary = state.get("staff_slots", {})
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
			slot["owner_id"] = _staff_role_owner_id(role_owner, settlement_id)
			var population_cost: int = max(0, int(slot.get("population_cost", 1)))
			slot["population_cost"] = population_cost
			required_count += population_cost
			# Ledger binding is the only source of truth for "filled". A scene body
			# without a permanent record must never bypass Character Realization.
			var worker_actor_id := str((prior_slots.get(slot_id, {}) as Dictionary).get("worker_actor_id", ""))
			var dead_actor_key := str(slot.get("dead_actor_key", "")).strip_edges()
			# The bound worker is gone if the facility found its corpse (dead_actor_key) or its
			# record is dead/missing. Mark the record dead and drop the binding so the slot reopens.
			if not worker_actor_id.is_empty() and (not dead_actor_key.is_empty() or not _is_assigned_record_alive(worker_actor_id)):
				var pop := _get_population_controller()
				if pop != null:
					if pop.has_method("mark_record_dead"):
						pop.call("mark_record_dead", worker_actor_id)
					# Detach the corpse from the slot so the next sync doesn't re-detect it as this
					# slot's worker (which would churn a fresh death every tick and drain population).
					# Both the slot-id meta AND the role node name resolve a slot's actor, so clear
					# the meta and rename the body off the role name — otherwise the name fallback
					# keeps finding the corpse and re-killing each freshly-assigned replacement.
					var corpse = pop.call("get_live_actor", worker_actor_id) if pop.has_method("get_live_actor") else null
					if corpse != null and is_instance_valid(corpse):
						corpse.set_meta("settlement_staff_slot_id", "")
						corpse.name = "Corpse"
				worker_actor_id = ""
			slot["worker_actor_id"] = worker_actor_id
			var filled := not worker_actor_id.is_empty()
			slot["filled"] = filled
			slots[slot_id] = slot
			if filled:
				assigned_count += population_cost
				if vacancies.has(slot_id):
					vacancies.erase(slot_id)
				_save_staff_slot_to_gecs(settlement_id, slot_id, slot)
				continue
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


## Staffing has two layers. (1) Assignment is world-sim knowledge — a record is bound to a slot
## at the ledger level for every town, near or far, in O(records). (2) Realization (putting a live
## body in place) is LOD-gated and only happens when the player is near. This entry runs both:
## the cheap ledger bind always, the expensive body realization only when near.
func _process_staff_vacancies(settlement_id: String, ignore_delay := false) -> void:
	if not settlement_states.has(settlement_id):
		return
	_assign_staff_from_ledger(settlement_id, ignore_delay)
	if _settlement_is_near_player(settlement_id):
		_realize_staff_bodies(settlement_id)
	_notify_state_changed(settlement_id)


## Cheap, player-independent: bind an available resident record to each open staff slot. Promoting
## the record's role_id removes it from the resident pool (so the population accounting balances)
## and is the durable "who staffs this" knowledge that survives LOD. No subtree walk, no live actors.
func _assign_staff_from_ledger(settlement_id: String, ignore_delay := false) -> void:
	if not settlement_states.has(settlement_id):
		return
	var pop := _get_population_controller()
	if pop == null or not pop.has_method("claim_unassigned_record_for_slot"):
		return
	var state: Dictionary = settlement_states[settlement_id]
	var vacancies: Dictionary = state.get("staff_vacancies", {})
	if vacancies.is_empty():
		return
	var slots: Dictionary = state.get("staff_slots", {})
	var available := get_available_population(settlement_id)
	var now_minute := _get_absolute_minute()
	var changed := false
	for slot_id_value in vacancies.keys():
		var slot_id := str(slot_id_value)
		var vacancy: Dictionary = vacancies.get(slot_id, {})
		if not ignore_delay and now_minute < int(vacancy.get("replacement_due_minute", 0)):
			continue
		var cost: int = max(0, int(vacancy.get("population_cost", 1)))
		if cost > available:
			continue
		var role_id := str(vacancy.get("role_id", "")).strip_edges()
		if role_id.is_empty():
			continue
		var record: Dictionary = pop.call("claim_unassigned_record_for_slot", settlement_id, slot_id, role_id)
		if record.is_empty():
			# No surplus left — poach the lowest-priority filled role. The
			# poached slot opens its own vacancy, cascading the labor shortage
			# to the least critical job instead of leaving this one open.
			record = _poach_assigned_record_for_slot(settlement_id, slot_id, role_id, slots, vacancies, pop)
		if record.is_empty():
			continue
		var slot: Dictionary = (slots.get(slot_id, vacancy) as Dictionary).duplicate(true)
		slot["worker_actor_id"] = str(record.get("actor_id", ""))
		slot["filled"] = true
		slots[slot_id] = slot
		_save_staff_slot_to_gecs(settlement_id, slot_id, slot)
		vacancies.erase(slot_id)
		available -= cost
		changed = true
		_record_event({
			"type": "staff_assigned",
			"settlement_id": settlement_id,
			"slot_id": slot_id,
			"role_id": role_id,
			"actor_id": str(record.get("actor_id", "")),
			"actor_name": str(record.get("member_name", record.get("actor_id", ""))),
		})
	if not changed:
		return
	state["staff_slots"] = slots
	state["staff_vacancies"] = vacancies
	var assigned := 0
	for sid_key in slots.keys():
		if bool((slots[sid_key] as Dictionary).get("filled", false)):
			assigned += max(0, int((slots[sid_key] as Dictionary).get("population_cost", 1)))
	state["population_assigned"] = assigned
	settlement_states[settlement_id] = state
	_refresh_population_availability(settlement_id)
	_save_settlement_state_to_gecs(settlement_id, state)


## Surplus is exhausted: take the worker from the filled slot whose role sits
## LOWEST in ROLE_POACH_PRIORITY (strictly below the vacancy's role), rebind
## the record to the vacancy, and open a vacancy for the poached slot.
func _poach_assigned_record_for_slot(settlement_id: String, slot_id: String, role_id: String, slots: Dictionary, vacancies: Dictionary, pop: Node) -> Dictionary:
	var vacancy_priority := ROLE_POACH_PRIORITY.find(role_id)
	if vacancy_priority < 0:
		return {}
	var best_slot_id := ""
	var best_priority := vacancy_priority
	for candidate_id_value in slots.keys():
		var candidate_id := str(candidate_id_value)
		if candidate_id == slot_id or vacancies.has(candidate_id):
			continue
		var candidate: Dictionary = slots[candidate_id]
		if not bool(candidate.get("filled", false)) or str(candidate.get("worker_actor_id", "")).strip_edges().is_empty():
			continue
		var candidate_priority := ROLE_POACH_PRIORITY.find(str(candidate.get("role_id", "")))
		if candidate_priority > best_priority:
			best_priority = candidate_priority
			best_slot_id = candidate_id
	if best_slot_id.is_empty():
		return {}
	var poached: Dictionary = (slots[best_slot_id] as Dictionary).duplicate(true)
	var worker_actor_id := str(poached.get("worker_actor_id", ""))
	poached["filled"] = false
	poached["worker_actor_id"] = ""
	slots[best_slot_id] = poached
	_save_staff_slot_to_gecs(settlement_id, best_slot_id, poached)
	_ensure_staff_vacancy(settlement_id, best_slot_id, poached)
	_record_event({
		"type": "staff_poached",
		"settlement_id": settlement_id,
		"from_slot_id": best_slot_id,
		"to_slot_id": slot_id,
		"actor_id": worker_actor_id,
	})
	if pop == null or not pop.has_method("update_actor_record"):
		return {}
	return pop.call("update_actor_record", worker_actor_id, {"role_id": role_id, "assigned_slot_id": slot_id})


## LOD-gated: one shared realizer turns the bound population record into a body,
## then the owning facility only attaches role behavior and placement.
func _realize_staff_bodies(settlement_id: String) -> void:
	if not settlement_states.has(settlement_id):
		return
	var anchor := get_settlement_anchor(settlement_id)
	if anchor == null:
		return
	var population := _get_population_controller()
	var slots: Dictionary = (settlement_states[settlement_id] as Dictionary).get("staff_slots", {})
	var realizer := _context.get_optional(PopulationCharacterRealizer.SERVICE_ID) as PopulationCharacterRealizer if _context != null else null
	if realizer == null:
		push_error("Settlement staffing cannot realize %s: PopulationCharacterRealizer is unavailable" % settlement_id)
		return
	var owners_by_id := {}
	for owner in _collect_staff_role_owners(anchor):
		owners_by_id[_staff_role_owner_id(owner, settlement_id)] = owner
	var expected_actor_ids := {}
	for expected_slot_value in slots.values():
		var expected_actor_id := str((expected_slot_value as Dictionary).get("worker_actor_id", "")).strip_edges()
		if not expected_actor_id.is_empty():
			expected_actor_ids[expected_actor_id] = true
	var cleaned_parents := {}
	for slot_id_value in slots.keys():
		var slot: Dictionary = slots[slot_id_value]
		if not bool(slot.get("filled", false)):
			continue
		if str(slot.get("worker_actor_id", "")).is_empty():
			continue
		var role_owner: Node = owners_by_id.get(str(slot.get("owner_id", "")))
		if role_owner == null:
			role_owner = _infer_staff_role_owner(str(slot_id_value), owners_by_id)
		if role_owner == null or not role_owner.has_method("configure_settlement_staff_actor") or not role_owner.has_method("get_staff_realization_parent"):
			continue
		var parent := role_owner.call("get_staff_realization_parent") as Node
		if parent != null and not cleaned_parents.has(parent):
			_remove_unbound_staff_bodies(parent, expected_actor_ids)
			cleaned_parents[parent] = true
		var actor_id := str(slot.get("worker_actor_id", ""))
		var actor = population.call("get_live_actor", actor_id) if population != null and population.has_method("get_live_actor") else null
		if actor != null \
				and actor.get_parent() == parent \
				and str(actor.get_meta(META_SETTLEMENT_SLOT_ID, "")) == str(slot_id_value):
			continue
		actor = realizer.realize_actor(actor_id, role_owner, parent, "", str(slot.get("character_type_id", "")))
		if actor != null:
			role_owner.call("configure_settlement_staff_actor", actor, str(slot_id_value), slot.duplicate(true))
			if role_owner.has_method("sync_property_ownership"):
				role_owner.call("sync_property_ownership")
			if role_owner.has_method("sync_door_policy"):
				role_owner.call("sync_door_policy")


func _remove_unbound_staff_bodies(parent: Node, expected_actor_ids: Dictionary) -> void:
	var population := _get_population_controller()
	for child in parent.get_children():
		if not (child is WorldActor):
			continue
		var actor_id := str(child.get_meta("actor_record_id", "")).strip_edges()
		if not actor_id.is_empty() and expected_actor_ids.has(actor_id):
			continue
		if not actor_id.is_empty() and population != null and population.has_method("unregister_actor"):
			population.call("unregister_actor", child)
		parent.remove_child(child)
		child.queue_free()


## A town left LOD range: free its live staff bodies back to ledger records (on/off, nothing lingers
## off-screen). The slot bindings stay, so the same staff re-realize when the player returns.
func derealize_settlement_staff(settlement_id: String) -> void:
	if not settlement_states.has(settlement_id):
		return
	var pop := _get_population_controller()
	if pop == null or not pop.has_method("get_live_actor"):
		return
	var slots: Dictionary = (settlement_states[settlement_id] as Dictionary).get("staff_slots", {})
	for slot_id_value in slots.keys():
		var worker := str((slots[slot_id_value] as Dictionary).get("worker_actor_id", "")).strip_edges()
		if worker.is_empty():
			continue
		var actor = pop.call("get_live_actor", worker)
		if actor == null or not is_instance_valid(actor):
			continue
		if actor.has_method("is_player_party_member") and bool(actor.call("is_player_party_member")):
			continue
		if pop.has_method("unregister_actor"):
			pop.call("unregister_actor", actor)  # record -> "ledger"; binding (worker_actor_id) kept
		actor.queue_free()


func _get_population_controller() -> Node:
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group("population_controller")


func _is_assigned_record_alive(actor_id: String) -> bool:
	var pop := _get_population_controller()
	if pop == null or not pop.has_method("is_record_alive"):
		return true  # Can't verify yet — assume alive so we don't churn a valid binding.
	return bool(pop.call("is_record_alive", actor_id))


func _bootstrap_staff_vacancies(settlement_id: String) -> void:
	bootstrap_staff_vacancies(settlement_id)


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
		"owner_id": str(slot.get("owner_id", "")),
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


func _staff_role_owner_id(owner: Node, settlement_id: String) -> String:
	if owner != null and owner.has_method("get_facility_id"):
		var facility_id := str(owner.call("get_facility_id")).strip_edges()
		if not facility_id.is_empty():
			return facility_id
	return settlement_id


func _infer_staff_role_owner(slot_id: String, owners_by_id: Dictionary) -> Node:
	var best_id := ""
	for owner_id_value in owners_by_id.keys():
		var owner_id := str(owner_id_value)
		if slot_id.begins_with("%s." % owner_id) and owner_id.length() > best_id.length():
			best_id = owner_id
	return owners_by_id.get(best_id) as Node if not best_id.is_empty() else null


func _collect_staff_role_owners_recursive(node: Node, owners: Array[Node]) -> void:
	if node == null:
		return
	if node.is_in_group(STAFF_ROLE_OWNER_GROUP) or node.has_method("get_settlement_staff_slots"):
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
