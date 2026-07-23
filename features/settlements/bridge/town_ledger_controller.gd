extends Node

class_name TownLedgerReadModel

## Event-driven read model for physical town ledgers.

signal report_updated(stack_id: String, snapshot: Dictionary)

const SERVICE_ID := &"town_ledger"
const LEDGER_ITEM_ID := "administration.town_ledger"
const LEDGER_METADATA_KEY := "town_ledger"

var _lifecycle: ItemLifecycleController
var _settlements: SettlementController
var _food: SettlementFoodController
var _population: PopulationController
var _buildings: BuildingRegistry
var _stock: InventoryStockController
var _time: WorldTimeController
var _gecs: GecsWorldController
var _active_stack_ids_by_settlement: Dictionary = {}
var _active_settlement_by_stack_id: Dictionary = {}
var _queued_refresh_settlement_ids: Dictionary = {}


func initialize(context: BootstrapContext) -> void:
	_lifecycle = context.require(ItemLifecycleController.SERVICE_ID) as ItemLifecycleController
	_settlements = context.require(SettlementController.SERVICE_ID) as SettlementController
	_food = context.require(SettlementFoodController.SERVICE_ID) as SettlementFoodController
	_population = context.require(PopulationController.SERVICE_ID) as PopulationController
	_buildings = context.require(BuildingRegistry.SERVICE_ID) as BuildingRegistry
	_stock = context.require(InventoryStockController.SERVICE_ID) as InventoryStockController
	_time = context.require(WorldTimeController.SERVICE_ID) as WorldTimeController
	_gecs = context.require(GecsWorldController.SERVICE_ID) as GecsWorldController
	_lifecycle.item_location_changed.connect(_on_item_location_changed)
	_settlements.settlement_event_recorded.connect(_on_settlement_event)
	_settlements.settlement_state_changed.connect(_on_settlement_state_changed)
	_food.food_status_changed.connect(_on_food_status_changed)
	_stock.stock_changed.connect(_on_stock_changed)
	_population.population_record_changed.connect(_on_population_record_changed)
	_buildings.building_created.connect(_on_building_changed)
	_buildings.building_updated.connect(_on_building_changed)
	_gecs.world_reindexed.connect(_reconcile_all_ledgers)
	call_deferred("_reconcile_all_ledgers")


func get_report(stack_id: String) -> Dictionary:
	var record := _lifecycle.get_stack_record(stack_id)
	if record.is_empty() or not _is_ledger(record):
		return {}
	var ledger := _ledger_state(record)
	var snapshot := (ledger.get("snapshot", {}) as Dictionary).duplicate(true)
	if snapshot.is_empty():
		_bind_and_refresh_if_valid(record)
		record = _lifecycle.get_stack_record(stack_id)
		ledger = _ledger_state(record)
		snapshot = (ledger.get("snapshot", {}) as Dictionary).duplicate(true)
	var original_id := str(ledger.get("original_settlement_id", ""))
	if original_id.is_empty() or snapshot.is_empty():
		return {}
	snapshot["record_state"] = "current" if _is_live_in_original_town(record, original_id) else "outdated"
	return snapshot


func _reconcile_all_ledgers() -> void:
	_active_stack_ids_by_settlement.clear()
	_active_settlement_by_stack_id.clear()
	for record in _gecs.get_inventory_stacks():
		if _is_ledger(record):
			_bind_and_refresh_if_valid(record)


func _on_item_location_changed(_stack_id: String, record: Dictionary) -> void:
	if _is_ledger(record):
		_bind_and_refresh_if_valid(record)


func _bind_and_refresh_if_valid(record: Dictionary) -> void:
	var kind := str(record.get("location_kind", ""))
	var settlement_id := str(record.get("location_settlement_id", ""))
	var stack_id := str(record.get("stack_id", ""))
	_remove_active_stack(stack_id)
	if settlement_id.is_empty() or (kind != "world_placed" and kind != "tabletop_slot"):
		return
	var ledger := _ledger_state(record)
	var original_id := str(ledger.get("original_settlement_id", ""))
	if original_id.is_empty():
		original_id = settlement_id
		ledger["original_settlement_id"] = original_id
		_write_ledger_state(stack_id, record, ledger)
	if settlement_id == original_id:
		_add_active_stack(stack_id, settlement_id)
		_refresh_stack(stack_id, original_id)


func _refresh_settlement(settlement_id: String) -> void:
	for stack_id in (_active_stack_ids_by_settlement.get(settlement_id, {}) as Dictionary).keys():
		_refresh_stack(str(stack_id), settlement_id)


func _queue_settlement_refresh(settlement_id: String) -> void:
	if settlement_id.is_empty() or not _active_stack_ids_by_settlement.has(settlement_id):
		return
	var was_empty := _queued_refresh_settlement_ids.is_empty()
	_queued_refresh_settlement_ids[settlement_id] = true
	if was_empty:
		_flush_queued_settlement_refreshes.call_deferred()


func _flush_queued_settlement_refreshes() -> void:
	var settlement_ids := _queued_refresh_settlement_ids.keys()
	_queued_refresh_settlement_ids.clear()
	for settlement_id in settlement_ids:
		_refresh_settlement(str(settlement_id))


func _add_active_stack(stack_id: String, settlement_id: String) -> void:
	var ids := _active_stack_ids_by_settlement.get(settlement_id, {}) as Dictionary
	ids[stack_id] = true
	_active_stack_ids_by_settlement[settlement_id] = ids
	_active_settlement_by_stack_id[stack_id] = settlement_id


func _remove_active_stack(stack_id: String) -> void:
	var settlement_id := str(_active_settlement_by_stack_id.get(stack_id, ""))
	if settlement_id.is_empty():
		return
	var ids := _active_stack_ids_by_settlement.get(settlement_id, {}) as Dictionary
	ids.erase(stack_id)
	if ids.is_empty():
		_active_stack_ids_by_settlement.erase(settlement_id)
	_active_settlement_by_stack_id.erase(stack_id)


func _refresh_stack(stack_id: String, settlement_id: String) -> void:
	var record := _lifecycle.get_stack_record(stack_id)
	if record.is_empty() or not _is_live_in_original_town(record, settlement_id):
		return
	var state := _settlements.get_settlement_state(settlement_id)
	var people := _population.get_records_for_settlement(settlement_id)
	var buildings := _buildings.get_buildings_for_settlement(settlement_id)
	var facilities: Array = []
	for facility in (state.get("facilities", {}) as Dictionary).values():
		if facility is Dictionary:
			facilities.append((facility as Dictionary).duplicate(true))
	facilities.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("facility_id", "")) < str(b.get("facility_id", "")))
	var facility_names: Dictionary = {}
	var facility_owner_roles: Dictionary = {}
	var facility_owner_names: Dictionary = {}
	for facility in facilities:
		var facility_id := str(facility.get("facility_id", ""))
		var owner_role_id := str(facility.get("owner_role_id", ""))
		facility_names[facility_id] = str(facility.get("display_name", "Town Service"))
		facility_owner_roles[facility_id] = owner_role_id
		facility_owner_names[facility_id] = "Town-owned" if owner_role_id.is_empty() else "Vacant"
	var people_by_id: Dictionary = {}
	for person in people:
		people_by_id[str(person.get("actor_id", ""))] = person
	var assignments_by_actor: Dictionary = {}
	for slot_value in (state.get("staff_slots", {}) as Dictionary).values():
		if not (slot_value is Dictionary):
			continue
		var slot := slot_value as Dictionary
		var actor_id := str(slot.get("worker_actor_id", ""))
		var person := people_by_id.get(actor_id, {}) as Dictionary
		var owner_id := str(slot.get("owner_id", ""))
		var role_id := str(slot.get("role_id", ""))
		if not actor_id.is_empty():
			assignments_by_actor[actor_id] = {
				"job": _humanize_role(str(role_id if not role_id.is_empty() else person.get("role_id", "resident"))),
				"workplace": str(facility_names.get(owner_id, "Town Service")),
			}
			if str(facility_owner_roles.get(owner_id, "")) == role_id:
				facility_owner_names[owner_id] = str(person.get("member_name", "Vacant"))
	var people_rows: Array[Dictionary] = []
	for person in people:
		var actor_id := str(person.get("actor_id", ""))
		var assignment := assignments_by_actor.get(actor_id, {}) as Dictionary
		people_rows.append({
			"name": str(person.get("member_name", "Unnamed Resident")),
			"job": str(assignment.get("job", _humanize_role(str(person.get("role_id", "resident"))))),
			"workplace": str(assignment.get("workplace", "None")),
		})
	people_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("name", "")) < str(b.get("name", "")))
	var building_rows: Array[Dictionary] = []
	var housing_capacity := 0
	for building in buildings:
		var physical_beds := maxi(0, int(building.get("bed_count", 0)))
		var beds := maxi(physical_beds, maxi(0, int(building.get("housing_capacity", 0))))
		housing_capacity += beds
		building_rows.append({
			"name": str(facility_names.get(str(building.get("facility_id", "")), building.get("display_name", "Unnamed Building"))),
			"purpose": _humanize_identifier(str(building.get("type_id", "building"))),
			"owner": str(facility_owner_names.get(str(building.get("facility_id", "")), "Town-owned")),
		})
	building_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("name", "")) < str(b.get("name", "")))
	var store_rows: Array[Dictionary] = []
	var food_rows: Array[Dictionary] = []
	var stock := _stock.get_settlement_stock_snapshot(settlement_id)
	var food := _food.get_status(settlement_id)
	var item_counts := stock.get("items", {}) as Dictionary
	var produced_counts := food.get("last_produced_item_counts", {}) as Dictionary
	var consumed_counts := food.get("last_consumed_item_counts", {}) as Dictionary
	var food_item_ids: Dictionary = {}
	for item_id in item_counts:
		var profile := _stock.get_item_profile(str(item_id))
		if bool(profile.get("is_food", false)):
			food_item_ids[item_id] = true
		else:
			store_rows.append({
				"item": str(profile.get("display_name", _stock.get_item_display_name(str(item_id)))),
				"quantity": int(item_counts[item_id]),
			})
	for item_id in produced_counts:
		food_item_ids[item_id] = true
	for item_id in consumed_counts:
		food_item_ids[item_id] = true
	var has_history := int(food.get("last_processed_day", -1)) >= 0
	for item_id in food_item_ids:
		var profile := _stock.get_item_profile(str(item_id))
		if profile.is_empty() or not bool(profile.get("is_food", false)):
			continue
		var quantity := int(item_counts.get(item_id, 0))
		var produced := float(produced_counts.get(item_id, 0))
		var consumed := float(consumed_counts.get(item_id, 0))
		var remaining := "No history yet"
		if has_history:
			if consumed <= 0.0:
				remaining = "Not currently used"
			elif produced >= consumed:
				remaining = "Sustainable"
			else:
				remaining = "%.1f days" % (float(quantity) / (consumed - produced))
		food_rows.append({
			"food": str(profile.get("display_name", _stock.get_item_display_name(str(item_id)))),
			"stored": quantity,
			"produced": "%.1f" % produced if has_history else "-",
			"consumed": "%.1f" % consumed if has_history else "-",
			"remaining": remaining,
		})
	store_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("item", "")) < str(b.get("item", "")))
	food_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("food", "")) < str(b.get("food", "")))
	var snapshot := {
		"settlement_name": str(state.get("display_name", settlement_id.capitalize())),
		"record_state": "current",
		"reported_at_text": _time.format_time(),
		"overview": {
			"population": people.size(),
			"housing_capacity": housing_capacity,
			"food_outlook": _food_outlook(food),
			"provisions": float(food.get("food_units", 0.0)),
			"reserve": _reserve_text(food),
			"daily_use": float(food.get("demand_per_day", 0.0)),
			"daily_output": float(food.get("production_per_day", 0.0)),
			"daily_balance": float(food.get("net_per_day", 0.0)),
		},
		"people": people_rows,
		"buildings": building_rows,
		"food": food_rows,
		"stores": store_rows,
	}
	var ledger := _ledger_state(record)
	ledger["original_settlement_id"] = settlement_id
	ledger["snapshot"] = snapshot.duplicate(true)
	_write_ledger_state(stack_id, record, ledger)
	report_updated.emit(stack_id, snapshot.duplicate(true))


func _humanize_role(role_id: String) -> String:
	var normalized := role_id.strip_edges().to_lower()
	if normalized.is_empty() or normalized == "resident":
		return "Unassigned"
	return _humanize_identifier(normalized)


func _humanize_identifier(value: String) -> String:
	return value.strip_edges().replace("_", " ").replace("-", " ").capitalize()


func _food_outlook(food: Dictionary) -> String:
	match str(food.get("pressure_state", "supplied")):
		"starving":
			return "Severe shortage"
		"hungry":
			return "Running low"
		_:
			return "Well supplied"


func _reserve_text(food: Dictionary) -> String:
	match str(food.get("reserve_state", "finite")):
		"sustainable":
			return "Self-sustaining"
		"zero_demand":
			return "No daily use"
		_:
			return "%.1f days" % maxf(0.0, float(food.get("reserve_days", 0.0)))


func _is_live_in_original_town(record: Dictionary, original_id: String) -> bool:
	var kind := str(record.get("location_kind", ""))
	return not original_id.is_empty() and str(record.get("location_settlement_id", "")) == original_id and (kind == "world_placed" or kind == "tabletop_slot")


func _is_ledger(record: Dictionary) -> bool:
	var definition := load(str(record.get("item_definition_path", ""))) as ItemDefinition
	return definition != null and definition.item_id == LEDGER_ITEM_ID


func _ledger_state(record: Dictionary) -> Dictionary:
	var metadata := record.get("metadata", {}) as Dictionary
	return (metadata.get(LEDGER_METADATA_KEY, {}) as Dictionary).duplicate(true)


func _write_ledger_state(stack_id: String, record: Dictionary, ledger: Dictionary) -> void:
	var metadata := (record.get("metadata", {}) as Dictionary).duplicate(true)
	metadata[LEDGER_METADATA_KEY] = ledger.duplicate(true)
	_lifecycle.submit_metadata(stack_id, metadata)


func _on_settlement_event(event: Dictionary) -> void:
	_queue_settlement_refresh(str(event.get("settlement_id", "")))


func _on_settlement_state_changed(settlement_id: String, _state: Dictionary) -> void:
	_queue_settlement_refresh(settlement_id)


func _on_food_status_changed(settlement_id: String, _status: Dictionary) -> void:
	_queue_settlement_refresh(settlement_id)


func _on_stock_changed(settlement_id: String, _facility_id: String) -> void:
	_queue_settlement_refresh(settlement_id)


func _on_population_record_changed(settlement_id: String, _actor_id: String) -> void:
	_queue_settlement_refresh(settlement_id)


func _on_building_changed(building_id: String) -> void:
	_queue_settlement_refresh(str(_buildings.get_building(building_id).get("settlement_id", "")))
