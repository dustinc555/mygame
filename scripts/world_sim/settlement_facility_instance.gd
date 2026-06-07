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
@export_range(0, 128, 1) var guard_count := 0
@export_range(0, 128, 1) var guard_post_count := 0
@export var guard_name := "Guard"
@export var staff_stable_id_prefix := ""
@export var staff_squad_name := ""
@export var ruler_title := ""
@export var ruler_name := ""
@export_range(0, 100, 1) var locker_lock_difficulty := 0


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
	record["guard_count"] = max(0, guard_count)
	record["guard_post_count"] = max(0, guard_post_count)
	return record


func get_settlement_staff_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	_collect_authored_staff_slots(self, slots)
	if slots.is_empty() and guard_count > 0:
		for index in range(guard_count):
			slots.append(_staff_slot_record("%s.guard.%d" % [get_facility_id(), index], "guard", index, guard_name, false, null))
	return slots


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
		if root_path.is_empty():
			continue
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
	if facility_function != null and not Engine.is_editor_hint() and facility_function.has_method("get_id"):
		return str(facility_function.call("get_id"))
	if facility_function != null and not _resource_string(facility_function, "function_id", "").strip_edges().is_empty():
		return _resource_string(facility_function, "function_id", "")
	return _resource_string(facility_function, "display_name", "")


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


func _collect_authored_staff_slots(root: Node, slots: Array[Dictionary]) -> void:
	for child in root.get_children():
		if child.has_meta("settlement_staff_slot_id"):
			var slot_id := str(child.get_meta("settlement_staff_slot_id", "")).strip_edges()
			if not slot_id.is_empty():
				var role_id := str(child.get_meta("settlement_staff_role", "guard")).strip_edges()
				var role_index := int(child.get_meta("settlement_staff_role_index", 0))
				slots.append(_staff_slot_record(slot_id, role_id, role_index, _actor_display_name(child), true, child))
		_collect_authored_staff_slots(child, slots)


func _staff_slot_record(slot_id: String, role_id: String, role_index: int, display: String, filled: bool, actor: Node) -> Dictionary:
	var record := {
		"slot_id": slot_id,
		"role_id": role_id if not role_id.is_empty() else "guard",
		"role_index": role_index,
		"display_name": display if not display.is_empty() else slot_id.capitalize(),
		"population_cost": 1,
		"filled": filled,
	}
	if actor != null:
		record["actor_id"] = _actor_id(actor)
		record["actor_path"] = get_path_to(actor) if actor.is_inside_tree() else NodePath()
	return record


func _actor_display_name(actor: Node) -> String:
	if _has_property(actor, "member_name"):
		var value := str(actor.get("member_name")).strip_edges()
		if not value.is_empty():
			return value
	return str(actor.name)


func _actor_id(actor: Node) -> String:
	if _has_property(actor, "stable_id"):
		var value := str(actor.get("stable_id")).strip_edges()
		if not value.is_empty():
			return value
	return str(actor.get_path()) if actor.is_inside_tree() else str(actor.get_instance_id())


func _has_property(target: Object, property_name: String) -> bool:
	if target == null:
		return false
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


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
