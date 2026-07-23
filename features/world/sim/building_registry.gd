extends Node

class_name BuildingRegistry

const SERVICE_ID := &"building_registry"

signal building_created(building_id: String)
signal building_updated(building_id: String)
signal registry_rebuilt

var _gecs: GecsWorldController
var _records_by_id: Dictionary = {}
var _building_ids_by_settlement: Dictionary = {}
var _building_ids_by_facility: Dictionary = {}
var _capacity_by_settlement: Dictionary = {}


func initialize(context: BootstrapContext) -> void:
	_gecs = context.require(GecsWorldController.SERVICE_ID) as GecsWorldController
	if not _gecs.world_reindexed.is_connected(_rebuild_from_gecs):
		_gecs.world_reindexed.connect(_rebuild_from_gecs)
	_rebuild_from_gecs()


func create_building(record: Dictionary) -> Dictionary:
	var normalized := _normalize_record(record)
	var building_id := str(normalized.get("building_id", ""))
	if building_id.is_empty():
		push_error("BuildingRegistry: building_id is required")
		return {}
	if _records_by_id.has(building_id):
		push_error("BuildingRegistry: duplicate building_id '%s'" % building_id)
		return {}
	var persisted: Dictionary = _gecs.upsert_building_record(normalized)
	if persisted.is_empty():
		return {}
	_index_record(persisted)
	building_created.emit(building_id)
	return persisted.duplicate(true)


func update_building(building_id: String, changes: Dictionary) -> Dictionary:
	var clean_id := building_id.strip_edges()
	if not _records_by_id.has(clean_id):
		return {}
	if changes.has("building_id") and str(changes["building_id"]).strip_edges() != clean_id:
		push_error("BuildingRegistry: building_id is immutable")
		return {}
	var updated: Dictionary = (_records_by_id[clean_id] as Dictionary).duplicate(true)
	updated.merge(changes, true)
	updated["building_id"] = clean_id
	_remove_from_indexes(_records_by_id[clean_id])
	var persisted: Dictionary = _gecs.upsert_building_record(_normalize_record(updated))
	_index_record(persisted)
	building_updated.emit(clean_id)
	return persisted.duplicate(true)


func get_building(building_id: String) -> Dictionary:
	var record: Dictionary = _records_by_id.get(building_id.strip_edges(), {})
	return record.duplicate(true)


func get_buildings_for_settlement(settlement_id: String) -> Array[Dictionary]:
	return _records_for_index(_building_ids_by_settlement.get(settlement_id.strip_edges(), {}))


func get_buildings_for_facility(facility_id: String) -> Array[Dictionary]:
	return _records_for_index(_building_ids_by_facility.get(facility_id.strip_edges(), {}))


func get_all_buildings() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record in _records_by_id.values():
		result.append((record as Dictionary).duplicate(true))
	return result


func get_settlement_housing_capacity(settlement_id: String) -> int:
	return int(_capacity_by_settlement.get(settlement_id.strip_edges(), 0))


func get_settlement_building_snapshot(settlement_id: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for record in get_buildings_for_settlement(settlement_id):
		rows.append({
			"building_id": record["building_id"],
			"display_name": record["display_name"],
			"type_id": record["type_id"],
			"owner_faction_id": record["owner_faction_id"],
			"access_state": record["access_state"],
			"abandoned": record["abandoned"],
			"operational_state": record["operational_state"],
			"bed_count": record["bed_count"],
			"housing_capacity": record["housing_capacity"],
			"source": record["source"],
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["building_id"]) < str(b["building_id"]))
	return rows


func _rebuild_from_gecs() -> void:
	_records_by_id.clear()
	_building_ids_by_settlement.clear()
	_building_ids_by_facility.clear()
	_capacity_by_settlement.clear()
	if _gecs == null:
		return
	for record in _gecs.get_building_records():
		_index_record(record)
	registry_rebuilt.emit()


func _index_record(record: Dictionary) -> void:
	var building_id := str(record.get("building_id", ""))
	if building_id.is_empty():
		return
	_records_by_id[building_id] = record.duplicate(true)
	var settlement_id := str(record.get("settlement_id", ""))
	var facility_id := str(record.get("facility_id", ""))
	_add_index(_building_ids_by_settlement, settlement_id, building_id)
	_add_index(_building_ids_by_facility, facility_id, building_id)
	if _contributes_capacity(record):
		_capacity_by_settlement[settlement_id] = int(_capacity_by_settlement.get(settlement_id, 0)) + int(record["housing_capacity"])


func _remove_from_indexes(record: Dictionary) -> void:
	var building_id := str(record.get("building_id", ""))
	var settlement_id := str(record.get("settlement_id", ""))
	_remove_index(_building_ids_by_settlement, settlement_id, building_id)
	_remove_index(_building_ids_by_facility, str(record.get("facility_id", "")), building_id)
	if _contributes_capacity(record):
		_capacity_by_settlement[settlement_id] = maxi(0, int(_capacity_by_settlement.get(settlement_id, 0)) - int(record["housing_capacity"]))
	_records_by_id.erase(building_id)


func _records_for_index(ids: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for building_id in ids:
		if _records_by_id.has(building_id):
			result.append((_records_by_id[building_id] as Dictionary).duplicate(true))
	return result


func _add_index(index: Dictionary, key: String, building_id: String) -> void:
	if key.is_empty():
		return
	if not index.has(key):
		index[key] = {}
	(index[key] as Dictionary)[building_id] = true


func _remove_index(index: Dictionary, key: String, building_id: String) -> void:
	if not index.has(key):
		return
	(index[key] as Dictionary).erase(building_id)
	if (index[key] as Dictionary).is_empty():
		index.erase(key)


func _contributes_capacity(record: Dictionary) -> bool:
	return not bool(record.get("abandoned", false)) \
		and str(record.get("operational_state", "")) == "operational" \
		and int(record.get("housing_capacity", 0)) > 0


func _normalize_record(record: Dictionary) -> Dictionary:
	return {
		"building_id": str(record.get("building_id", "")).strip_edges(),
		"settlement_id": str(record.get("settlement_id", "")).strip_edges(),
		"facility_id": str(record.get("facility_id", "")).strip_edges(),
		"type_id": str(record.get("type_id", "generic")).strip_edges(),
		"display_name": str(record.get("display_name", "Building")),
		"owner_faction_id": str(record.get("owner_faction_id", "")).strip_edges(),
		"access_state": str(record.get("access_state", "public")).strip_edges(),
		"abandoned": bool(record.get("abandoned", false)),
		"operational_state": str(record.get("operational_state", "operational")).strip_edges(),
		"bed_count": maxi(0, int(record.get("bed_count", 0))),
		"housing_capacity": maxi(0, int(record.get("housing_capacity", 0))),
		"world_transform": record.get("world_transform", Transform3D.IDENTITY) as Transform3D,
		"source": str(record.get("source", "authored")).strip_edges(),
		"catalog_id": str(record.get("catalog_id", "")).strip_edges(),
		"foundation_height": float(record.get("foundation_height", 0.0)),
	}
