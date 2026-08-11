extends Node

class_name TerritoryController

const SERVICE_ID := &"territory"

var root_scene: Node
var faction_territories: Dictionary = {}
var town_borders: Dictionary = {}
var faction_territories_visible := false
var town_borders_visible := false
var _gecs: Node
var _initialized := false
@export var town_build_exclusion_margin := 18.0


func initialize(context: BootstrapContext) -> void:
	root_scene = context.root_scene
	_gecs = context.get_optional(&"gecs_world")
	_try_initialize()


func _ready() -> void:
	add_to_group("territory_controller")
	_try_initialize()


func refresh() -> void:
	faction_territories.clear()
	town_borders.clear()
	_collect_territories()
	_apply_debug_visibility()


func toggle_faction_territories_visible() -> String:
	set_faction_territories_visible(not faction_territories_visible)
	return "Faction territories visible" if faction_territories_visible else "Faction territories hidden"


func toggle_town_borders_visible() -> String:
	set_town_borders_visible(not town_borders_visible)
	return "Town borders visible" if town_borders_visible else "Town borders hidden"


func set_faction_territories_visible(value: bool) -> void:
	faction_territories_visible = value
	for node in get_tree().get_nodes_in_group("faction_territory"):
		if node.has_method("set_debug_visible"):
			node.call("set_debug_visible", value)


func set_town_borders_visible(value: bool) -> void:
	town_borders_visible = value
	for node in get_tree().get_nodes_in_group("settlement_town"):
		if node.has_method("set_town_border_debug_visible"):
			node.call("set_town_border_debug_visible", value)


func get_build_permission(world_position: Vector3, builder_faction_id := "") -> Dictionary:
	var town_nodes := get_tree().get_nodes_in_group("settlement_town")
	return _get_build_permission_from_nodes(
		world_position,
		builder_faction_id,
		town_nodes,
		get_tree().get_nodes_in_group("faction_territory"),
		_get_unprojected_settlement_states(town_nodes)
	)


func get_build_permissions(world_positions: Array, builder_faction_id := "") -> Array[Dictionary]:
	var town_nodes := get_tree().get_nodes_in_group("settlement_town")
	var territory_nodes := get_tree().get_nodes_in_group("faction_territory")
	var settlement_states := _get_unprojected_settlement_states(town_nodes)
	var permissions: Array[Dictionary] = []
	permissions.resize(world_positions.size())
	for index in world_positions.size():
		permissions[index] = _get_build_permission_from_nodes(world_positions[index] as Vector3, builder_faction_id, town_nodes, territory_nodes, settlement_states)
	return permissions


func get_build_permission_for_footprint(placement_transform: Transform3D, footprint_size: Vector2, builder_faction_id := "") -> Dictionary:
	var town_nodes := get_tree().get_nodes_in_group("settlement_town")
	var territory_nodes := get_tree().get_nodes_in_group("faction_territory")
	var settlement_states := _get_unprojected_settlement_states(town_nodes)
	var origin_permission := _get_build_permission_from_nodes(placement_transform.origin, builder_faction_id, town_nodes, territory_nodes, settlement_states)
	if not bool(origin_permission.get("can_build", false)):
		return origin_permission
	var half := footprint_size.abs() * 0.5
	if half.x <= 0.0 or half.y <= 0.0:
		return origin_permission
	var world_corners := PackedVector2Array()
	var local_corners: Array[Vector3] = [
		Vector3(-half.x, 0.0, -half.y),
		Vector3(half.x, 0.0, -half.y),
		Vector3(half.x, 0.0, half.y),
		Vector3(-half.x, 0.0, half.y),
	]
	for local_corner in local_corners:
		var world_corner: Vector3 = placement_transform * local_corner
		world_corners.append(Vector2(world_corner.x, world_corner.z))
	for node in town_nodes:
		var town_faction_id := str(node.call("get_faction_id")) if node.has_method("get_faction_id") else ""
		if not builder_faction_id.is_empty() and not town_faction_id.is_empty() and town_faction_id == builder_faction_id:
			continue
		if not node.has_method("overlaps_town_border_footprint"):
			return {"can_build": false, "reason": "town_authority_incompatible", "settlement_id": str(node.name)}
		if bool(node.call("overlaps_town_border_footprint", world_corners, town_build_exclusion_margin)):
			return {
				"can_build": false,
				"reason": "too_close_to_town",
				"settlement_id": str(node.call("get_settlement_id")) if node.has_method("get_settlement_id") else str(node.name),
				"faction_id": town_faction_id,
			}
	for state in settlement_states:
		var town_faction_id := str(state.get("faction_id", ""))
		if not builder_faction_id.is_empty() and not town_faction_id.is_empty() and town_faction_id == builder_faction_id:
			continue
		var center: Vector3 = state.get("world_position", Vector3.ZERO)
		var radius := maxf(0.0, float(state.get("radius", 0.0))) + town_build_exclusion_margin
		if _circle_overlaps_polygon(Vector2(center.x, center.z), radius, world_corners):
			return {
				"can_build": false,
				"reason": "too_close_to_town",
				"settlement_id": str(state.get("settlement_id", "")),
				"faction_id": town_faction_id,
			}
	return origin_permission


func _get_build_permission_from_nodes(world_position: Vector3, builder_faction_id: String, town_nodes: Array[Node], territory_nodes: Array[Node], settlement_states: Array[Dictionary]) -> Dictionary:
	for node in town_nodes:
		var town_faction_id := str(node.call("get_faction_id")) if node.has_method("get_faction_id") else ""
		if not builder_faction_id.is_empty() and not town_faction_id.is_empty() and town_faction_id == builder_faction_id:
			continue
		if node.has_method("contains_town_border_position") and bool(node.call("contains_town_border_position", world_position, town_build_exclusion_margin)):
			return {
				"can_build": false,
				"reason": "too_close_to_town",
				"settlement_id": str(node.call("get_settlement_id")) if node.has_method("get_settlement_id") else str(node.name),
				"faction_id": town_faction_id,
			}
	for state in settlement_states:
		var town_faction_id := str(state.get("faction_id", ""))
		if not builder_faction_id.is_empty() and not town_faction_id.is_empty() and town_faction_id == builder_faction_id:
			continue
		var center: Vector3 = state.get("world_position", Vector3.ZERO)
		var radius := maxf(0.0, float(state.get("radius", 0.0))) + town_build_exclusion_margin
		if Vector2(world_position.x, world_position.z).distance_to(Vector2(center.x, center.z)) <= radius:
			return {
				"can_build": false,
				"reason": "too_close_to_town",
				"settlement_id": str(state.get("settlement_id", "")),
				"faction_id": town_faction_id,
			}
	for node in territory_nodes:
		if not node.has_method("contains_world_position") or not bool(node.call("contains_world_position", world_position)):
			continue
		var faction_id := _get_territory_owner_faction_id(node)
		if not faction_id.is_empty() and faction_id != builder_faction_id:
			return {
				"can_build": true,
				"reason": "foreign_faction_territory",
				"faction_id": faction_id,
				"territory_id": str(node.call("get_territory_id")) if node.has_method("get_territory_id") else str(node.name),
			}
	return {"can_build": true, "reason": "unclaimed"}


func _get_unprojected_settlement_states(town_nodes: Array[Node]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _gecs == null or not _gecs.has_method("get_settlement_states"):
		return result
	var live_ids: Dictionary = {}
	for node in town_nodes:
		if node.has_method("get_settlement_id"):
			live_ids[str(node.call("get_settlement_id"))] = true
	var states: Dictionary = _gecs.call("get_settlement_states")
	for state_value in states.values():
		var state := state_value as Dictionary
		var settlement_id := str(state.get("settlement_id", ""))
		if not settlement_id.is_empty() and not live_ids.has(settlement_id):
			result.append(state)
	return result


func _circle_overlaps_polygon(center: Vector2, radius: float, polygon: PackedVector2Array) -> bool:
	if polygon.size() < 3:
		return false
	if Geometry2D.is_point_in_polygon(center, polygon):
		return true
	var radius_squared := radius * radius
	for index in polygon.size():
		var closest := Geometry2D.get_closest_point_to_segment(center, polygon[index], polygon[(index + 1) % polygon.size()])
		if center.distance_squared_to(closest) <= radius_squared:
			return true
	return false


func _get_territory_owner_faction_id(territory: Node) -> String:
	if territory == null:
		return ""
	if territory.has_method("get_resolved_faction_id"):
		return str(territory.call("get_resolved_faction_id"))
	return str(territory.get("faction_id")) if _has_property(territory, "faction_id") else ""


func serialize_state() -> Dictionary:
	return {
		"faction_territories": faction_territories.duplicate(true),
		"town_borders": town_borders.duplicate(true),
		"faction_territories_visible": faction_territories_visible,
		"town_borders_visible": town_borders_visible,
	}


func _try_initialize() -> void:
	if _initialized or root_scene == null or not is_inside_tree():
		return
	_collect_territories()
	_apply_debug_visibility()
	_initialized = true


func _collect_territories() -> void:
	for node in get_tree().get_nodes_in_group("faction_territory"):
		if node.has_method("get_territory_record"):
			var record: Dictionary = node.call("get_territory_record")
			var territory_id := str(record.get("territory_id", node.name))
			faction_territories[territory_id] = record
	for node in get_tree().get_nodes_in_group("settlement_town"):
		if node.has_method("get_town_border_record"):
			var record: Dictionary = node.call("get_town_border_record")
			var settlement_id := str(record.get("settlement_id", node.name))
			town_borders[settlement_id] = record


func _apply_debug_visibility() -> void:
	set_faction_territories_visible(faction_territories_visible)
	set_town_borders_visible(town_borders_visible)


func _has_property(target: Object, property_name: String) -> bool:
	if target == null:
		return false
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false
