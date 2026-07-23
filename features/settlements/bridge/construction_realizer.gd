extends Node

class_name ConstructionRealizer

## Realizes constructed BuildingRegistry records into the live world: instantiates
## each building's catalog scene at its exact committed transform under the
## played scene root (so navigation tiles patch automatically), and draws a
## dashed circular town border per constructed settlement that redraws as the
## record's radius grows. Because it only consumes records, a future
## save/load replays through this same path unchanged.

const SERVICE_ID := &"construction_realizer"

const BORDER_Y_OFFSET := 0.5
const BORDER_SEGMENTS := 96
const BORDER_DASH_RATIO := 0.6

var root_scene: Node

var _construction: ConstructionController
var _registry: BuildingRegistry
var _projection_bridge: BuildingProjectionBridge
var _building_instances := {}
var _border_instances := {}
var _zoning_borders_visible := false


func initialize(context: BootstrapContext) -> void:
	root_scene = context.root_scene
	_construction = context.require(ConstructionController.SERVICE_ID) as ConstructionController
	_registry = context.require(BuildingRegistry.SERVICE_ID) as BuildingRegistry
	_projection_bridge = context.require(BuildingProjectionBridge.SERVICE_ID) as BuildingProjectionBridge
	_registry.building_created.connect(_on_building_created)
	_registry.registry_rebuilt.connect(_reconcile_realized_records)
	_construction.settlement_added.connect(_on_settlement_changed)
	_construction.settlement_updated.connect(_on_settlement_changed)
	_realize_all.call_deferred()


func _ready() -> void:
	add_to_group("construction_realizer")


## Debug toggle (Towns window): zoning borders are hidden by default.
func set_zoning_borders_visible(visible_flag: bool) -> void:
	_zoning_borders_visible = visible_flag
	for settlement_id in _border_instances:
		var border: Node = _border_instances[settlement_id]
		if border != null and is_instance_valid(border):
			(border as Node3D).visible = visible_flag


func are_zoning_borders_visible() -> bool:
	return _zoning_borders_visible


## Idempotent: realizes any record without a live instance (initial load,
## future save restore).
func _realize_all() -> void:
	if _construction == null:
		return
	_reconcile_realized_records()


func _reconcile_realized_records() -> void:
	if _construction == null or _registry == null:
		return
	var live_record_ids := {}
	for building in _registry.get_all_buildings():
		if str(building.get("source", "")) == "constructed":
			live_record_ids[str(building.get("building_id", ""))] = true
			_realize_building(building)
	for building_id_value in _building_instances.keys():
		var building_id := str(building_id_value)
		if live_record_ids.has(building_id):
			continue
		var stale: Node = _building_instances.get(building_id)
		if stale != null and is_instance_valid(stale):
			stale.queue_free()
		_building_instances.erase(building_id)
	var live_settlement_ids := {}
	for settlement in _construction.get_settlements().values():
		live_settlement_ids[str(settlement.get("settlement_id", ""))] = true
		_redraw_border(settlement)
	for settlement_id_value in _border_instances.keys():
		var settlement_id := str(settlement_id_value)
		if live_settlement_ids.has(settlement_id):
			continue
		var stale_border: Node = _border_instances.get(settlement_id)
		if stale_border != null and is_instance_valid(stale_border):
			stale_border.queue_free()
		_border_instances.erase(settlement_id)


func _on_building_created(building_id: String) -> void:
	var building := _registry.get_building(building_id)
	if str(building.get("source", "")) == "constructed":
		_realize_building(building)


func _on_settlement_changed(settlement: Dictionary) -> void:
	_redraw_border(settlement)


func _realize_building(building: Dictionary) -> void:
	var building_id: String = building["building_id"]
	if _building_instances.has(building_id) and is_instance_valid(_building_instances[building_id]):
		var existing := _building_instances[building_id] as Node3D
		if not (existing is WorldBuilding) or (existing as WorldBuilding).catalog_id == str(building.get("catalog_id", "")):
			if existing is WorldBuilding:
				(existing as WorldBuilding).apply_registry_state(building)
			else:
				existing.global_transform = building["world_transform"] as Transform3D
			return
		existing.queue_free()
		_building_instances.erase(building_id)
	var definition: Resource = _construction.catalog.get_building(building["catalog_id"])
	var scene: PackedScene = definition.get("scene") as PackedScene if definition != null else null
	if scene == null:
		push_error("ConstructionRealizer: cannot realize unknown catalog id '%s' for building '%s'" % [building["catalog_id"], building_id])
		return
	var instance: Node3D = scene.instantiate()
	instance.name = building_id
	if instance is WorldBuilding:
		(instance as WorldBuilding).building_id = building_id
		(instance as WorldBuilding).apply_registry_state(building)
	_world_parent().add_child(instance)
	instance.global_transform = building["world_transform"] as Transform3D
	_building_instances[building_id] = instance
	if instance is WorldBuilding:
		_projection_bridge.bind_projection(instance as WorldBuilding, false)


func _redraw_border(settlement: Dictionary) -> void:
	var settlement_id: String = settlement["settlement_id"]
	var old: Node = _border_instances.get(settlement_id)
	if old != null and is_instance_valid(old):
		old.queue_free()
	var center: Vector3 = settlement["world_position"]
	var radius: float = settlement["radius"]
	var instance := MeshInstance3D.new()
	instance.name = "TownBorder_%s" % settlement_id
	instance.mesh = _dashed_circle_mesh(radius)
	instance.material_override = _border_material()
	instance.visible = _zoning_borders_visible
	_world_parent().add_child(instance)
	instance.global_position = center + Vector3.UP * BORDER_Y_OFFSET
	_border_instances[settlement_id] = instance


## Buildings and borders parent under the PLAYED scene root: the same scope
## the navigation system watches, so tiles re-bake on placement.
func _world_parent() -> Node:
	var current := get_tree().current_scene
	if current != null and (current == root_scene or current.is_ancestor_of(root_scene)):
		return current
	return root_scene


func _dashed_circle_mesh(radius: float) -> ArrayMesh:
	var lines := PackedVector3Array()
	var step := TAU / float(BORDER_SEGMENTS)
	for i in range(BORDER_SEGMENTS):
		var a := step * i
		var b := a + step * BORDER_DASH_RATIO
		lines.append(Vector3(cos(a) * radius, 0.0, sin(a) * radius))
		lines.append(Vector3(cos(b) * radius, 0.0, sin(b) * radius))
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = lines
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


func _border_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.95, 0.82, 0.4, 0.85)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
