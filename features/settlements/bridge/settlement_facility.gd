@icon("res://addons/world_authoring/icons/facility.svg")
extends Node3D

class_name SettlementFacility

const FACILITY_DUTY_CONTRACT = preload("res://features/settlements/sim/facility_duty_contract.gd")
const ACTIVE_FACILITY_DUTY_META := &"active_facility_duty"


static func begin_actor_facility_duty(actor: Node, facility_id: String) -> void:
	FACILITY_DUTY_CONTRACT.begin(actor, facility_id)


static func end_actor_facility_duty(actor: Node, facility_id: String) -> void:
	FACILITY_DUTY_CONTRACT.end(actor, facility_id)


static func actor_has_active_facility_duty(actor: Node) -> bool:
	return FACILITY_DUTY_CONTRACT.is_active(actor)

@export var facility_id := ""
@export var building_id := ""
@export var display_name := "Facility"
@export_enum("generic", "housing", "farm", "mine", "bar", "jail", "shop", "storage", "guard", "social", "police", "weapon_shop", "armor_shop", "travel_shop", "potion_shop", "tavern", "keep") var facility_type := "generic"
@export var owner_faction_id := ""
@export_group("Assignments")
@export var role_slots: Array[FacilityRoleSlotDefinition] = []
@export_group("")
@export_group("Door Policy")
@export_enum("private", "public") var door_access_policy := "private":
	set(value):
		door_access_policy = value
		_refresh_door_authoring()
@export_enum("door_default", "closed", "open", "locked") var door_initial_state := "door_default"
@export var door_schedule_enabled := false:
	set(value):
		door_schedule_enabled = value
		_refresh_door_authoring()
@export_range(0, 23, 1) var door_open_hour := 8:
	set(value):
		door_open_hour = clampi(value, 0, 23)
		_refresh_door_authoring()
@export_range(0, 23, 1) var door_close_hour := 21:
	set(value):
		door_close_hour = clampi(value, 0, 23)
		_refresh_door_authoring()
@export var doors_keep_open_during_hours := false
@export_group("")
@export_group("Character Realization")
@export var population_appearance_profile: Resource
@export var population_name_profile: Resource
@export var character_type_set: Resource
@export_group("")
@export var enabled := true
## Optional abstract capacity floor. Physical SleepableBed children always
## contribute and the assigned neutral shell receives the effective total.
@export_range(0, 1000, 1) var housing_capacity := 0
@export var food_outputs_per_day: Array[Resource] = []
@export var storage_capacity_bonus := 0.0
@export var activity_points_root_path: NodePath
@export var linked_node_paths: Array[NodePath] = []


func _enter_tree() -> void:
	stamp_building_identity()


func _ready() -> void:
	add_to_group("settlement_facility")
	if not role_slots.is_empty():
		add_to_group("settlement_staff_role_owner")
	stamp_building_identity()


func stamp_building_identity() -> void:
	_stamp_building_identity(self)


func stamp_building_node_identity(node: Node) -> void:
	_stamp_building_identity(node)


func _stamp_building_identity(node: Node) -> void:
	if "building_id" in node and "settlement_id" in node and "facility_id" in node and "building_type" in node:
		var effective_facility_id := get_facility_id()
		node.set("building_id", building_id if not building_id.strip_edges().is_empty() else "%s.building" % effective_facility_id)
		node.set("facility_id", effective_facility_id)
		node.set("settlement_id", _effective_settlement_id())
		node.set("building_type", facility_type)
		if "owner_faction_id" in node:
			node.set("owner_faction_id", get_property_owner_faction())
		if "access_state" in node:
			node.set("access_state", door_access_policy)
		if "public_schedule_enabled" in node:
			node.set("public_schedule_enabled", door_schedule_enabled)
		if "public_open_hour" in node:
			node.set("public_open_hour", door_open_hour)
		if "public_close_hour" in node:
			node.set("public_close_hour", door_close_hour)
		var physical_beds := get_physical_bed_count()
		if "bed_count" in node:
			node.set("bed_count", physical_beds)
		if "housing_capacity" in node:
			node.set("housing_capacity", maxi(housing_capacity, physical_beds))
		return
	for child in node.get_children():
		_stamp_building_identity(child)


## Everything inside a facility is the facility owner's property: spawned
## prop items resolve ownership by walking up to these instead of per-node
## stamping, so ownership follows staff turnover automatically.
func get_property_owner_faction() -> String:
	if not Engine.is_editor_hint():
		var registry := BootstrapContext.service(&"building_registry")
		if registry != null and not building_id.strip_edges().is_empty():
			var record: Dictionary = registry.call("get_building", building_id)
			var canonical_owner := str(record.get("owner_faction_id", "")).strip_edges()
			if not canonical_owner.is_empty():
				return canonical_owner
	if not owner_faction_id.strip_edges().is_empty():
		return owner_faction_id
	var settlement := _find_settlement_ancestor()
	if settlement == null:
		return ""
	if settlement.has_method("get_faction_id"):
		return str(settlement.call("get_faction_id"))
	var definition = settlement.get("settlement_definition")
	return str(definition.call("get_faction_id")) if definition != null and definition.has_method("get_faction_id") else ""


func get_effective_character_realizer() -> Resource:
	if population_appearance_profile != null:
		return population_appearance_profile
	var settlement := _find_settlement_ancestor()
	var definition = settlement.get("settlement_definition") if settlement != null else null
	return definition.call("get_character_realizer") as Resource if definition != null and definition.has_method("get_character_realizer") else null


func get_effective_character_realizer_source() -> String:
	if population_appearance_profile != null:
		return "facility"
	var settlement := _find_settlement_ancestor()
	var definition = settlement.get("settlement_definition") if settlement != null else null
	return "town" if definition != null and definition.get("population_appearance_profile") != null else "faction"


func get_effective_character_type_set() -> Resource:
	if character_type_set != null:
		return character_type_set
	var settlement := _find_settlement_ancestor()
	var definition = settlement.get("settlement_definition") if settlement != null else null
	return definition.call("get_character_type_set") as Resource if definition != null and definition.has_method("get_character_type_set") else null


func get_effective_character_type_set_source() -> String:
	if character_type_set != null:
		return "facility"
	var settlement := _find_settlement_ancestor()
	var definition = settlement.get("settlement_definition") if settlement != null else null
	return "town" if definition != null and definition.get("character_type_set") != null else "faction"


func get_assignment_slot_specs() -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	var role_indexes: Dictionary = {}
	for slot in role_slots:
		if slot == null:
			continue
		var spec := slot.to_slot_spec(get_facility_id())
		if spec.is_empty():
			continue
		var role_id := str(spec.get("role_id", ""))
		spec["role_index"] = int(role_indexes.get(role_id, 0))
		role_indexes[role_id] = int(spec["role_index"]) + 1
		specs.append(spec)
	return specs


func count_role_slots(role_id: String, assignment_domain := "") -> int:
	var count := 0
	var normalized_role := role_id.strip_edges().to_lower()
	for slot in role_slots:
		if slot == null or slot.role == null or slot.role.get_id() != normalized_role:
			continue
		if not assignment_domain.is_empty() and slot.role.assignment_domain != assignment_domain:
			continue
		count += 1
	return count


func get_role_slot(role_id: String, role_index := 0) -> FacilityRoleSlotDefinition:
	var current_index := 0
	var normalized_role := role_id.strip_edges().to_lower()
	for slot in role_slots:
		if slot == null or slot.role == null or slot.role.get_id() != normalized_role:
			continue
		if current_index == role_index:
			return slot
		current_index += 1
	return null


func get_role_slot_id(role_id: String, role_index := 0) -> String:
	var slot := get_role_slot(role_id, role_index)
	return "%s.%s" % [get_facility_id(), slot.slot_id.strip_edges().to_lower()] if slot != null else ""


func _effective_settlement_id() -> String:
	var settlement := _find_settlement_ancestor()
	return str(settlement.call("get_settlement_id")) if settlement != null and settlement.has_method("get_settlement_id") else ""


func _find_settlement_ancestor() -> Node:
	var current := get_parent()
	while current != null:
		if current is SettlementAnchor:
			return current
		current = current.get_parent()
	return null


## The person who personally owns the facility's goods (a bar's barkeeper);
## facilities without a personal owner stay faction-owned only.
func get_property_owner_character() -> HumanoidCharacter:
	return null


func get_property_owner_role_id() -> String:
	return ""


func _refresh_door_authoring() -> void:
	if is_inside_tree():
		stamp_building_identity()


func get_facility_id() -> String:
	return facility_id if not facility_id.is_empty() else str(name)


func get_facility_record(settlement_id := "") -> Dictionary:
	var physical_beds := get_physical_bed_count()
	return {
		"facility_id": get_facility_id(),
		"settlement_id": settlement_id,
		"display_name": display_name if not display_name.is_empty() else get_facility_id().capitalize(),
		"facility_type": facility_type,
		"owner_faction_id": get_property_owner_faction(),
		"owner_role_id": get_property_owner_role_id(),
		"door_access_policy": door_access_policy,
		"door_initial_state": door_initial_state,
		"door_schedule_enabled": door_schedule_enabled,
		"door_open_hour": door_open_hour,
		"door_close_hour": door_close_hour,
		"doors_keep_open_during_hours": doors_keep_open_during_hours,
		"enabled": enabled,
		"bed_count": physical_beds,
		"housing_capacity": maxi(housing_capacity, physical_beds),
		"world_position": global_position,
		"food_outputs_per_day": _food_output_records() if enabled else [],
		"storage_capacity_bonus": storage_capacity_bonus if enabled else 0.0,
		"activity_point_count": get_activity_points().size(),
		"job_provider_count": get_job_providers().size(),
		"bar_service_area_count": get_bar_service_areas().size(),
	}


func get_physical_bed_count() -> int:
	var count := 0
	var pending: Array[Node] = [self]
	while not pending.is_empty():
		var parent: Node = pending.pop_back()
		for child in parent.get_children():
			if child is SettlementFacility:
				continue
			if child.is_in_group("sleepable_bed"):
				count += 1
			pending.append(child)
	return count


func _food_outputs_per_day() -> Array:
	return food_outputs_per_day.duplicate()


func _food_output_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for output in _food_outputs_per_day():
		if output == null:
			continue
		var item := output.get("item") as ItemDefinition
		var count := int(output.get("count"))
		if item == null or item.resource_path.is_empty() or count <= 0:
			continue
		records.append({
			"item_definition_path": item.resource_path,
			"count": count,
			"food_units_per_item": item.settlement_food_units,
		})
	return records


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
