extends Node

class_name BuildingProjectionBridge

const SERVICE_ID := &"building_projection_bridge"

var _registry: BuildingRegistry
var _projections_by_id: Dictionary = {}
var _imports_seed_by_id: Dictionary = {}


func initialize(context: BootstrapContext) -> void:
	_registry = context.require(BuildingRegistry.SERVICE_ID) as BuildingRegistry
	_registry.building_updated.connect(_apply_record_to_projection)
	_registry.registry_rebuilt.connect(_reconcile_all_projections)
	call_deferred("_bind_authored_buildings_once")


func bind_projection(building: WorldBuilding, import_seed := true) -> bool:
	if building == null or not is_instance_valid(building):
		return false
	var building_id := building.building_id.strip_edges()
	if building_id.is_empty():
		push_error("BuildingProjectionBridge: authored WorldBuilding '%s' is missing explicit building_id" % building.name)
		return false
	var record: Dictionary = _registry.get_building(building_id)
	if record.is_empty() and import_seed:
		record = _registry.create_building(building.get_building_seed())
	elif import_seed and str(record.get("source", "authored")) == "authored":
		var seed := building.get_building_seed()
		var composition_changes: Dictionary = {}
		for field in ["facility_id", "type_id", "bed_count", "housing_capacity"]:
			if record.get(field) != seed.get(field):
				composition_changes[field] = seed.get(field)
		if not composition_changes.is_empty():
			record = _registry.update_building(building_id, composition_changes)
	if record.is_empty():
		return false
	_projections_by_id[building_id] = building
	_imports_seed_by_id[building_id] = import_seed
	var exiting := _on_projection_exiting.bind(building_id, building)
	if not building.tree_exiting.is_connected(exiting):
		building.tree_exiting.connect(exiting, CONNECT_ONE_SHOT)
	building.apply_registry_state(record)
	return true


func _bind_authored_buildings_once() -> void:
	for node in get_tree().get_nodes_in_group("world_building"):
		if node is WorldBuilding:
			bind_projection(node as WorldBuilding, true)


func _apply_record_to_projection(building_id: String) -> void:
	var building: WorldBuilding = _projections_by_id.get(building_id)
	if building != null and is_instance_valid(building):
		building.apply_registry_state(_registry.get_building(building_id))


func _reconcile_all_projections() -> void:
	for building_id in _projections_by_id.keys():
		var clean_id := str(building_id)
		var building: WorldBuilding = _projections_by_id.get(clean_id)
		if building == null or not is_instance_valid(building):
			continue
		# Constructed projections are reconciled by ConstructionRealizer, which
		# can replace the scene when a migrated catalog ID changes.
		if not bool(_imports_seed_by_id.get(clean_id, false)):
			continue
		var record := _registry.get_building(clean_id)
		if record.is_empty() and bool(_imports_seed_by_id.get(clean_id, false)):
			record = _registry.create_building(building.get_building_seed())
		if not record.is_empty():
			building.apply_registry_state(record)


func _on_projection_exiting(building_id: String, building: WorldBuilding) -> void:
	if _projections_by_id.get(building_id) == building:
		_projections_by_id.erase(building_id)
		_imports_seed_by_id.erase(building_id)
