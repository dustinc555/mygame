extends Node

class_name ConstructionController

## Placement rules only. Buildings live in BuildingRegistry; settlement bounds
## live in GECS settlement records. This service keeps its stable identity so
## existing command emitters can resolve it without owning duplicate state.
const SERVICE_ID := &"construction"
const CATALOG_PATH := "res://features/settlements/resources/buildings/player_building_catalog.tres"

signal settlement_added(settlement: Dictionary)
signal settlement_updated(settlement: Dictionary)

@export var town_join_radius := 90.0
@export var min_town_radius := 40.0
@export var border_margin := 18.0
@export var authored_town_zone_radius := 90.0

var catalog: Resource
var _gecs: GecsWorldController
var _buildings: BuildingRegistry
var _next_settlement_index := 1
var _next_building_index := 1


func initialize(context: BootstrapContext) -> void:
	catalog = load(CATALOG_PATH)
	_gecs = context.require(GecsWorldController.SERVICE_ID) as GecsWorldController
	_buildings = context.require(BuildingRegistry.SERVICE_ID) as BuildingRegistry
	_gecs.world_reindexed.connect(_rebuild_id_counters)
	_rebuild_id_counters()


func _ready() -> void:
	add_to_group("construction_controller")


func can_place(position: Vector3, faction_id: String) -> Dictionary:
	for settlement in _gecs.get_settlement_states().values():
		if str(settlement.get("faction_id", "")) == faction_id:
			continue
		var radius := float(settlement.get("radius", 0.0))
		if radius <= 0.0:
			radius = authored_town_zone_radius
		var center: Vector3 = settlement.get("world_position", Vector3.INF)
		if center != Vector3.INF and Vector2(center.x - position.x, center.z - position.z).length() <= radius:
			return {"allowed": false, "reason": "Too close to another faction's town.", "blocking_settlement": str(settlement.get("settlement_id", ""))}
	return {"allowed": true, "reason": "", "blocking_settlement": ""}


func place_building(catalog_building_id: String, transform: Transform3D, faction_id: String, foundation_height := 0.0) -> Dictionary:
	var definition: Resource = catalog.get_building(catalog_building_id) if catalog != null else null
	if definition == null:
		push_warning("ConstructionController: unknown building id '%s'" % catalog_building_id)
		return {}
	if not bool(can_place(transform.origin, faction_id)["allowed"]):
		return {}
	var settlement := _find_joinable_settlement(transform.origin, faction_id)
	var founded := settlement.is_empty()
	if founded:
		settlement = _found_settlement(faction_id, transform.origin)
	var building_id := _next_available_building_id()
	var record: Dictionary = _buildings.create_building({
		"building_id": building_id,
		"settlement_id": settlement["settlement_id"],
		"facility_id": "",
		"type_id": str(definition.get("type_id")),
		"display_name": str(definition.get("display_name")),
		"owner_faction_id": faction_id,
		"access_state": str(definition.get("access_state")),
		"abandoned": false,
		"operational_state": "operational",
		"housing_capacity": maxi(0, int(definition.get("housing_capacity"))),
		"world_transform": transform,
		"source": "constructed",
		"catalog_id": catalog_building_id,
		"foundation_height": foundation_height,
	})
	if record.is_empty():
		return {}
	settlement = _recompute_settlement_bounds(str(settlement["settlement_id"]))
	if founded:
		settlement_added.emit(settlement)
	else:
		settlement_updated.emit(settlement)
	return record


func get_settlements() -> Dictionary:
	var result := {}
	for settlement_id in _gecs.get_settlement_states():
		var settlement := _gecs.get_settlement_state(settlement_id)
		if bool(settlement.get("constructed", false)):
			result[settlement_id] = settlement
	return result


func get_settlement(settlement_id: String) -> Dictionary:
	var settlement := _gecs.get_settlement_state(settlement_id)
	return settlement if bool(settlement.get("constructed", false)) else {}


func _find_joinable_settlement(position: Vector3, faction_id: String) -> Dictionary:
	var best := {}
	var best_distance := INF
	for settlement_id in _gecs.get_settlement_states():
		var settlement := _gecs.get_settlement_state(settlement_id)
		if str(settlement.get("faction_id", "")) != faction_id:
			continue
		for building in _buildings.get_buildings_for_settlement(settlement_id):
			var origin: Vector3 = (building["world_transform"] as Transform3D).origin
			var distance := Vector2(origin.x - position.x, origin.z - position.z).length()
			if distance <= town_join_radius and distance < best_distance:
				best_distance = distance
				best = settlement
	return best


func _found_settlement(faction_id: String, position: Vector3) -> Dictionary:
	var settlement_id := _next_available_settlement_id()
	return _gecs.upsert_settlement_state(settlement_id, {
		"settlement_id": settlement_id,
		"display_name": "%s Base %d" % [faction_id, _next_settlement_index - 1],
		"faction_id": faction_id,
		"world_position": position,
		"radius": min_town_radius,
		"constructed": true,
	})


func _recompute_settlement_bounds(settlement_id: String) -> Dictionary:
	var buildings: Array[Dictionary] = _buildings.get_buildings_for_settlement(settlement_id)
	var settlement := _gecs.get_settlement_state(settlement_id)
	if buildings.is_empty() or settlement.is_empty():
		return settlement
	var centroid := Vector3.ZERO
	for building in buildings:
		centroid += (building["world_transform"] as Transform3D).origin
	centroid /= buildings.size()
	var radius := min_town_radius
	for building in buildings:
		var origin: Vector3 = (building["world_transform"] as Transform3D).origin
		radius = maxf(radius, Vector2(origin.x - centroid.x, origin.z - centroid.z).length() + border_margin)
	settlement["world_position"] = centroid
	settlement["radius"] = radius
	return _gecs.upsert_settlement_state(settlement_id, settlement)


func _rebuild_id_counters() -> void:
	_next_settlement_index = 1
	_next_building_index = 1
	for building in _buildings.get_all_buildings():
		var building_id := str(building.get("building_id", ""))
		if building_id.begins_with("constructed_building_"):
			_next_building_index = maxi(_next_building_index, int(building_id.trim_prefix("constructed_building_")) + 1)
	for settlement_id in _gecs.get_settlement_states():
		if str(settlement_id).begins_with("constructed_settlement_"):
			_next_settlement_index = maxi(_next_settlement_index, int(str(settlement_id).trim_prefix("constructed_settlement_")) + 1)


func _next_available_building_id() -> String:
	var candidate := "constructed_building_%d" % _next_building_index
	while not _buildings.get_building(candidate).is_empty():
		_next_building_index += 1
		candidate = "constructed_building_%d" % _next_building_index
	_next_building_index += 1
	return candidate


func _next_available_settlement_id() -> String:
	var candidate := "constructed_settlement_%d" % _next_settlement_index
	while not _gecs.get_settlement_state(candidate).is_empty():
		_next_settlement_index += 1
		candidate = "constructed_settlement_%d" % _next_settlement_index
	_next_settlement_index += 1
	return candidate
