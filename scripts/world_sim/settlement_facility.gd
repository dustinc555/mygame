extends Node3D

class_name SettlementFacility

@export var facility_id := ""
@export var display_name := "Facility"
@export_enum("generic", "housing", "farm", "mine", "bar", "shop", "storage", "guard", "social", "police", "weapon_shop", "armor_shop", "travel_shop", "potion_shop", "tavern") var facility_type := "generic"
@export var owner_faction_id := ""
@export var enabled := true
@export var food_production_per_day := 0.0
@export var food_consumption_per_day := 0.0
@export var storage_capacity_bonus := 0.0
@export var activity_points_root_path: NodePath
@export var linked_node_paths: Array[NodePath] = []


func _ready() -> void:
	add_to_group("settlement_facility")


func get_facility_id() -> String:
	return facility_id if not facility_id.is_empty() else name


func get_facility_record(settlement_id := "") -> Dictionary:
	return {
		"facility_id": get_facility_id(),
		"settlement_id": settlement_id,
		"display_name": display_name if not display_name.is_empty() else get_facility_id().capitalize(),
		"facility_type": facility_type,
		"owner_faction_id": owner_faction_id,
		"enabled": enabled,
		"world_position": global_position,
		"food_production_per_day": food_production_per_day if enabled else 0.0,
		"food_consumption_per_day": food_consumption_per_day if enabled else 0.0,
		"storage_capacity_bonus": storage_capacity_bonus if enabled else 0.0,
		"activity_point_count": get_activity_points().size(),
		"job_provider_count": get_job_providers().size(),
		"bar_service_area_count": get_bar_service_areas().size(),
	}


func get_activity_points() -> Array:
	var points: Array = []
	var root := get_node_or_null(activity_points_root_path)
	if root == null:
		root = self
	_collect_activity_points(root, points)
	return points


func get_linked_nodes() -> Array:
	var nodes: Array = []
	for node_path in linked_node_paths:
		var node := get_node_or_null(node_path)
		if node != null:
			nodes.append(node)
	return nodes


func get_job_providers() -> Array:
	var providers: Array = []
	_collect_nodes_with_group(self, "job_provider", providers)
	for node in get_linked_nodes():
		_collect_nodes_with_group(node, "job_provider", providers)
	return providers


func get_bar_service_areas() -> Array:
	var service_areas: Array = []
	_collect_nodes_with_group(self, "bar_service_area", service_areas)
	for node in get_linked_nodes():
		_collect_nodes_with_group(node, "bar_service_area", service_areas)
	return service_areas


func _collect_activity_points(root: Node, points: Array) -> void:
	for child in root.get_children():
		if child != self and child.has_method("get_activity_record"):
			points.append(child)
		_collect_activity_points(child, points)


func _collect_nodes_with_group(root: Node, group_name: String, nodes: Array) -> void:
	if root == null:
		return
	if root.is_in_group(group_name) and not nodes.has(root):
		nodes.append(root)
	for child in root.get_children():
		_collect_nodes_with_group(child, group_name, nodes)
