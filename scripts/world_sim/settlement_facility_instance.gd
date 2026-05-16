@tool
extends "res://scripts/world_sim/settlement_facility.gd"

class_name SettlementFacilityInstance

@export var facility_function: Resource:
	set(value):
		facility_function = value
		_apply_function_defaults()
@export var building_root_path: NodePath = NodePath("BuildingSlot")
@export var staff_root_path: NodePath = NodePath("Staff")
@export var service_points_root_path: NodePath = NodePath("ServicePoints")
@export var storage_root_path: NodePath = NodePath("Storage")
@export var job_providers_root_path: NodePath = NodePath("JobProviders")
@export var auto_create_standard_roots := true:
	set(value):
		auto_create_standard_roots = value
		_repair_authoring_tree()


func _enter_tree() -> void:
	call_deferred("_repair_authoring_tree")


func _ready() -> void:
	_repair_authoring_tree()
	super._ready()


func get_facility_record(settlement_id := "") -> Dictionary:
	var record := super.get_facility_record(settlement_id)
	record["function_id"] = _function_id()
	record["building_count"] = _get_child_count_at(building_root_path)
	record["staff_count"] = _get_child_count_at(staff_root_path)
	record["service_point_count"] = _get_child_count_at(service_points_root_path)
	record["storage_link_count"] = _get_child_count_at(storage_root_path)
	return record


func get_building_root() -> Node3D:
	return get_node_or_null(building_root_path) as Node3D


func get_staff_root() -> Node3D:
	return get_node_or_null(staff_root_path) as Node3D


func get_service_points_root() -> Node3D:
	return get_node_or_null(service_points_root_path) as Node3D


func get_storage_root() -> Node3D:
	return get_node_or_null(storage_root_path) as Node3D


func get_job_providers_root() -> Node3D:
	return get_node_or_null(job_providers_root_path) as Node3D


func validate_authoring() -> Array[String]:
	var warnings: Array[String] = []
	if get_facility_id().is_empty():
		warnings.append("Missing facility_id")
	if facility_function == null:
		warnings.append("Missing facility_function")
	for root_path in [building_root_path, staff_root_path, service_points_root_path, storage_root_path, job_providers_root_path, activity_points_root_path]:
		if get_node_or_null(root_path) == null:
			warnings.append("Missing root: %s" % root_path)
	return warnings


func _repair_authoring_tree() -> void:
	if not is_inside_tree() or not auto_create_standard_roots:
		return
	_apply_function_defaults()
	_ensure_root(building_root_path)
	_ensure_root(staff_root_path)
	_ensure_root(service_points_root_path)
	_ensure_root(storage_root_path)
	_ensure_root(job_providers_root_path)
	if activity_points_root_path.is_empty():
		activity_points_root_path = NodePath("ActivityPoints")
	_ensure_root(activity_points_root_path)


func _apply_function_defaults() -> void:
	if facility_function == null:
		return
	var function_display := _resource_string(facility_function, "display_name", "")
	var function_type := _resource_string(facility_function, "facility_type", facility_type)
	if not function_type.is_empty():
		facility_type = function_type
	if display_name.is_empty() or display_name == "Facility":
		display_name = function_display if not function_display.is_empty() else display_name
	if absf(food_production_per_day) <= 0.0001:
		food_production_per_day = _resource_float(facility_function, "default_food_production_per_day", food_production_per_day)
	if absf(food_consumption_per_day) <= 0.0001:
		food_consumption_per_day = _resource_float(facility_function, "default_food_consumption_per_day", food_consumption_per_day)
	if absf(storage_capacity_bonus) <= 0.0001:
		storage_capacity_bonus = _resource_float(facility_function, "default_storage_capacity_bonus", storage_capacity_bonus)


func _function_id() -> String:
	if facility_function != null and facility_function.has_method("get_id"):
		return str(facility_function.call("get_id"))
	return ""


func _ensure_root(root_path: NodePath) -> Node:
	if root_path.is_empty():
		return null
	var existing := get_node_or_null(root_path)
	if existing != null:
		return existing
	var root_name := str(root_path)
	if root_name.contains("/"):
		return null
	var root := Node3D.new()
	root.name = root_name
	add_child(root)
	_set_editor_owner(root)
	return root


func _get_child_count_at(root_path: NodePath) -> int:
	var root := get_node_or_null(root_path)
	return root.get_child_count() if root != null else 0


func _resource_string(resource: Resource, property_name: String, fallback: String) -> String:
	if resource == null:
		return fallback
	var value = resource.get(property_name)
	return fallback if value == null else str(value)


func _resource_float(resource: Resource, property_name: String, fallback: float) -> float:
	if resource == null:
		return fallback
	var value = resource.get(property_name)
	return fallback if value == null else float(value)


func _set_editor_owner(node: Node) -> void:
	if not Engine.is_editor_hint():
		return
	var tree := get_tree()
	if tree == null:
		return
	var edited_root := tree.edited_scene_root
	if edited_root != null:
		node.owner = edited_root
