@tool
@icon("res://addons/world_authoring/icons/facility.svg")
extends "res://features/settlements/bridge/settlement_facility.gd"

class_name SettlementFacilityInstance

@export var facility_function: Resource:
	set(value):
		facility_function = value
		_apply_function_defaults()
@export var building_root_path: NodePath = NodePath("BuildingSlot")
## Deterministic seed for the editor furnish pass; Reroll increments it.
## Same seed always regenerates the same layout.
@export var furnish_seed := 0
## Explicit furnish recipe for this one facility. Leave empty to resolve by
## convention: <faction>/<type>.tres, then <type>.tres, then default.tres
## under features/settlements/resources/furnishing.
@export var furnish_rules: FurnishRules
@export var staff_root_path: NodePath = NodePath("Staff")
## Generic facilities get staff demand directly from their catalog definition.
## Specialized facilities may override get_settlement_staff_slots only when
## they need additional role behavior, never character construction.
@export var staff_role_counts: Dictionary = {}
@export var service_points_root_path: NodePath = NodePath("ServicePoints")
@export var storage_root_path: NodePath = NodePath("Storage")
@export var job_providers_root_path: NodePath = NodePath("JobProviders")
@export var auto_create_standard_roots := true:
	set(value):
		auto_create_standard_roots = value
		_repair_authoring_tree()


func _enter_tree() -> void:
	super._enter_tree()
	call_deferred("_repair_authoring_tree")


func _ready() -> void:
	_repair_authoring_tree()
	super._ready()
	if not staff_role_counts.is_empty():
		add_to_group("settlement_staff_role_owner")
	if not Engine.is_editor_hint():
		sync_door_policy.call_deferred()


func get_facility_record(settlement_id := "") -> Dictionary:
	var record := super.get_facility_record(settlement_id)
	record["function_id"] = _function_id()
	record["building_count"] = _get_child_count_at(building_root_path)
	record["staff_count"] = _get_child_count_at(staff_root_path)
	record["service_point_count"] = _get_child_count_at(service_points_root_path)
	record["storage_link_count"] = _get_child_count_at(storage_root_path)
	return record


## Stamp every ownable node in the facility subtree (containers, world
## items, service areas — anything exposing owner_faction_name) with the
## facility's owner. Re-run after staffing changes so ownership follows
## staff turnover; actors' own subtrees are skipped (their inventory is
## theirs).
func sync_property_ownership() -> void:
	var owner_character := get_property_owner_character()
	var owner_faction := get_property_owner_faction()
	_stamp_property_ownership(self, owner_character, owner_faction)


func _stamp_property_ownership(node: Node, owner_character: HumanoidCharacter, owner_faction: String) -> void:
	if node != self and node is WorldActor:
		return
	if node != self:
		if not owner_faction.is_empty() and "owner_faction_name" in node:
			node.set("owner_faction_name", owner_faction)
		if owner_character != null and "owner_character_path" in node:
			node.set("owner_character_path", node.get_path_to(owner_character))
	for child in node.get_children():
		_stamp_property_ownership(child, owner_character, owner_faction)


func get_building_root() -> Node3D:
	return get_node_or_null(building_root_path) as Node3D


func get_current_building() -> WorldBuilding:
	var root := get_building_root()
	if root == null:
		return null
	if root is WorldBuilding:
		return root as WorldBuilding
	for child in root.get_children():
		if child is WorldBuilding:
			return child as WorldBuilding
	return null


func sync_door_policy(retries_remaining := 30) -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	var doors := BootstrapContext.service(&"doors")
	if doors == null or not doors.has_method("configure_building_doors"):
		if retries_remaining > 0:
			sync_door_policy.call_deferred(retries_remaining - 1)
		return
	var building := get_current_building()
	if building == null or building.building_id.strip_edges().is_empty():
		return
	var owner := get_property_owner_character()
	var owner_actor_id := str(owner.get("stable_id")).strip_edges() if owner != null and "stable_id" in owner else ""
	var private_access := door_access_policy == "private"
	var config := {
		"authorized_actor_ids": PackedStringArray([owner_actor_id]) if private_access and not owner_actor_id.is_empty() else PackedStringArray(),
		"authorized_faction_ids": PackedStringArray([get_property_owner_faction()]) if private_access and not get_property_owner_faction().is_empty() else PackedStringArray(),
		"public_access": not private_access,
		"initial_state": door_initial_state,
		"keeper_actor_id": owner_actor_id,
		"open_hour": door_open_hour if door_schedule_enabled else -1,
		"close_hour": door_close_hour if door_schedule_enabled else -1,
		"kept_open": door_schedule_enabled and doors_keep_open_during_hours,
	}
	doors.call("configure_building_doors", building.building_id, config)


func get_staff_root() -> Node3D:
	return get_node_or_null(staff_root_path) as Node3D


func get_staff_realization_parent() -> Node3D:
	return get_staff_root()


func get_settlement_staff_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	var role_ids := staff_role_counts.keys()
	role_ids.sort()
	for role_id_value in role_ids:
		var role_id := str(role_id_value).strip_edges().to_lower()
		for index in range(maxi(0, int(staff_role_counts[role_id_value]))):
			var suffix := role_id if index == 0 else "%s%d" % [role_id, index + 1]
			slots.append({
				"slot_id": "%s.%s" % [get_facility_id(), suffix],
				"role_id": role_id,
				"role_index": index,
				"character_type_id": get_staff_character_type_id(role_id, index),
				"display_name": role_id.capitalize() if index == 0 else "%s %d" % [role_id.capitalize(), index + 1],
				"population_cost": 1,
				"replacement_delay_days": 7.0,
				"filled": _staff_actor_for_slot("%s.%s" % [get_facility_id(), suffix]) != null,
				"authority_scope": "facility_staff",
			})
	return slots


func configure_settlement_staff_actor(actor: Node, slot_id: String, slot_record: Dictionary) -> void:
	if actor == null:
		return
	actor.name = str(slot_record.get("role_id", "staff")).to_pascal_case() + (str(int(slot_record.get("role_index", 0)) + 1) if int(slot_record.get("role_index", 0)) > 0 else "")
	actor.set_meta("settlement_staff_role", str(slot_record.get("role_id", "staff")))
	actor.set_meta("settlement_staff_role_index", int(slot_record.get("role_index", 0)))
	actor.set_meta("settlement_staff_slot_id", slot_id)
	actor.set_meta("settlement_actor_category", "staff")


func _staff_actor_for_slot(slot_id: String) -> Node:
	var root := get_staff_root()
	if root == null:
		return null
	for child in root.get_children():
		if str(child.get_meta("settlement_staff_slot_id", "")) == slot_id:
			return child
	return null


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
	if building_id.strip_edges().is_empty():
		warnings.append("Missing building_id")
	if facility_function == null and facility_type != "housing":
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
	if absf(storage_capacity_bonus) <= 0.0001:
		storage_capacity_bonus = _resource_float(facility_function, "default_storage_capacity_bonus", storage_capacity_bonus)


func _function_id() -> String:
	if facility_function != null and not Engine.is_editor_hint() and facility_function.has_method("get_id"):
		return str(facility_function.call("get_id"))
	if facility_function != null and not _resource_string(facility_function, "function_id", "").strip_edges().is_empty():
		return _resource_string(facility_function, "function_id", "")
	return _resource_string(facility_function, "display_name", "")


func _food_outputs_per_day() -> Array:
	if facility_function == null:
		return super._food_outputs_per_day()
	return Array(facility_function.get("food_outputs_per_day")).duplicate()


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
