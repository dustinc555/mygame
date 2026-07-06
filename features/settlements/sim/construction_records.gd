extends Node

class_name ConstructionRecords

## Durable construction state: buildings placed at runtime and the faction
## settlements (bases/towns) they found. Placement is intent -> record here;
## the ConstructionRealizer (bridge) turns records into live scenes, so fresh
## placement and a future save/load replay share one code path.
##
## Records are plain serializable data (dictionaries, arrays, floats, stable
## ids). Transforms are stored as 12 floats. `serialize_state()` follows the
## SettlementController precedent and is the future save hook.
##
## Settlement rule (Kenshi-inspired): a placed building joins the nearest
## settlement of the SAME faction whose border it lands within reach of
## (join radius measured from the settlement's buildings, not its founding
## point — leapfrogging grows the town); otherwise it founds a new
## settlement. The border radius redraws to encompass all buildings.

const SERVICE_ID := &"construction"

const CATALOG_PATH := "res://features/settlements/resources/buildings/player_building_catalog.tres"

signal settlement_added(settlement: Dictionary)
signal settlement_updated(settlement: Dictionary)
signal building_added(settlement_id: String, building: Dictionary)

## A new building within this distance of an existing same-faction building
## joins that building's settlement.
@export var town_join_radius := 90.0
## A settlement border is never smaller than this.
@export var min_town_radius := 40.0
## Border extends this far beyond the outermost building.
@export var border_margin := 18.0
## Zoning claim around AUTHORED towns (which have no construction records):
## foreign factions may not build within this range of their world position.
@export var authored_town_zone_radius := 90.0

var catalog: Resource

var _settlements := {}
var _next_settlement_index := 1
var _next_building_index := 1


var _settlement_bridge: Node


func initialize(context: BootstrapContext) -> void:
	if catalog == null:
		catalog = load(CATALOG_PATH)
	# Authored towns (SettlementController records) also project zoning claims.
	_settlement_bridge = context.get_optional(&"settlement")


func _ready() -> void:
	add_to_group("construction_records")
	if catalog == null:
		catalog = load(CATALOG_PATH)


## Zoning rule: a faction may not build inside another faction's town zone
## (constructed settlement border or an authored town's claim). Returns
## {"allowed": bool, "reason": String, "blocking_settlement": String}.
## Taking the ground means conquering the town — not building around it.
func can_place(position: Vector3, faction_id: String) -> Dictionary:
	for settlement_id in _settlements:
		var settlement: Dictionary = _settlements[settlement_id]
		if settlement["faction_id"] == faction_id:
			continue
		var center: Array = settlement["center"]
		if Vector2(center[0] - position.x, center[2] - position.z).length() <= settlement["radius"]:
			return {"allowed": false, "reason": "Too close to another faction's town.", "blocking_settlement": settlement_id}
	if _settlement_bridge != null:
		var states: Dictionary = _settlement_bridge.get("settlement_states") if _settlement_bridge.get("settlement_states") is Dictionary else {}
		for settlement_id in states:
			var state: Dictionary = states[settlement_id]
			if str(state.get("faction_id", "")) == faction_id:
				continue
			var world_position: Vector3 = state.get("world_position", Vector3.INF)
			if world_position == Vector3.INF:
				continue
			if Vector2(world_position.x - position.x, world_position.z - position.z).length() <= authored_town_zone_radius:
				return {"allowed": false, "reason": "Too close to another faction's town.", "blocking_settlement": str(settlement_id)}
	return {"allowed": true, "reason": "", "blocking_settlement": ""}


## Places a building record. Returns the building record, or {} when the
## catalog id is unknown or zoning forbids the position. `transform` is the
## finalized world transform; `foundation_height` is the intentional raise
## above the ground so realize-time terrain snap can restore it.
func place_building(catalog_building_id: String, transform: Transform3D, faction_id: String, foundation_height := 0.0) -> Dictionary:
	if catalog == null or catalog.call("get_building", catalog_building_id) == null:
		push_warning("ConstructionRecords: unknown building id '%s'" % catalog_building_id)
		return {}
	if not bool(can_place(transform.origin, faction_id)["allowed"]):
		return {}
	var settlement := _find_joinable_settlement(transform.origin, faction_id)
	var founded := settlement.is_empty()
	if founded:
		settlement = _found_settlement(faction_id, transform.origin)
	var building := {
		"building_id": "constructed_building_%d" % _next_building_index,
		"catalog_id": catalog_building_id,
		"faction_id": faction_id,
		"settlement_id": settlement["settlement_id"],
		"transform": _serialize_transform(transform),
		"foundation": foundation_height,
	}
	_next_building_index += 1
	settlement["buildings"][building["building_id"]] = building
	_recompute_settlement_bounds(settlement)
	if founded:
		settlement_added.emit(settlement)
	else:
		settlement_updated.emit(settlement)
	building_added.emit(settlement["settlement_id"], building)
	return building


func get_settlements() -> Dictionary:
	return _settlements


func get_settlement(settlement_id: String) -> Dictionary:
	return _settlements.get(settlement_id, {})


## Future save hook, shaped like SettlementController.serialize_state().
func serialize_state() -> Dictionary:
	return {"constructed_settlements": _settlements.duplicate(true)}


static func deserialize_transform(values: Array) -> Transform3D:
	return Transform3D(
		Vector3(values[0], values[1], values[2]),
		Vector3(values[3], values[4], values[5]),
		Vector3(values[6], values[7], values[8]),
		Vector3(values[9], values[10], values[11]))


func _find_joinable_settlement(position: Vector3, faction_id: String) -> Dictionary:
	var best := {}
	var best_distance := INF
	for settlement_id in _settlements:
		var settlement: Dictionary = _settlements[settlement_id]
		if settlement["faction_id"] != faction_id:
			continue
		for building_id in settlement["buildings"]:
			var building: Dictionary = settlement["buildings"][building_id]
			var origin := Vector3(building["transform"][9], building["transform"][10], building["transform"][11])
			var distance := Vector2(origin.x - position.x, origin.z - position.z).length()
			if distance <= town_join_radius and distance < best_distance:
				best_distance = distance
				best = settlement
	return best


func _found_settlement(faction_id: String, position: Vector3) -> Dictionary:
	var settlement := {
		"settlement_id": "constructed_settlement_%d" % _next_settlement_index,
		"display_name": "%s Base %d" % [faction_id, _next_settlement_index],
		"faction_id": faction_id,
		"center": [position.x, position.y, position.z],
		"radius": min_town_radius,
		"buildings": {},
	}
	_next_settlement_index += 1
	_settlements[settlement["settlement_id"]] = settlement
	return settlement


## Border redraw: center = building centroid, radius encompasses the
## outermost building plus margin, never below min_town_radius.
func _recompute_settlement_bounds(settlement: Dictionary) -> void:
	var buildings: Dictionary = settlement["buildings"]
	if buildings.is_empty():
		return
	var centroid := Vector3.ZERO
	for building_id in buildings:
		var t: Array = buildings[building_id]["transform"]
		centroid += Vector3(t[9], t[10], t[11])
	centroid /= buildings.size()
	var radius := min_town_radius
	for building_id in buildings:
		var t: Array = buildings[building_id]["transform"]
		var distance := Vector2(t[9] - centroid.x, t[11] - centroid.z).length()
		radius = maxf(radius, distance + border_margin)
	settlement["center"] = [centroid.x, centroid.y, centroid.z]
	settlement["radius"] = radius


func _serialize_transform(transform: Transform3D) -> Array:
	var b := transform.basis
	var o := transform.origin
	return [
		b.x.x, b.x.y, b.x.z,
		b.y.x, b.y.y, b.y.z,
		b.z.x, b.z.y, b.z.z,
		o.x, o.y, o.z,
	]
