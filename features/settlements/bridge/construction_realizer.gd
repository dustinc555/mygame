extends Node

class_name ConstructionRealizer

## Realizes ConstructionRecords records into the live world: instantiates
## each building record's catalog scene at its recorded transform under the
## played scene root (so navigation tiles patch automatically), and draws a
## dashed circular town border per constructed settlement that redraws as the
## record's radius grows. Because it only consumes records, a future
## save/load replays through this same path unchanged.

const SERVICE_ID := &"construction_realizer"

const CONSTRUCTION_SCRIPT := preload("res://features/settlements/sim/construction_records.gd")

const BORDER_Y_OFFSET := 0.5
const BORDER_SEGMENTS := 96
const BORDER_DASH_RATIO := 0.6

var root_scene: Node

var _construction: Node
var _building_instances := {}
var _border_instances := {}
var _zoning_borders_visible := false


func initialize(context: BootstrapContext) -> void:
	root_scene = context.root_scene
	_construction = context.get_optional(CONSTRUCTION_SCRIPT.SERVICE_ID)
	if _construction == null:
		return
	_construction.building_added.connect(_on_building_added)
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
	var settlements: Dictionary = _construction.call("get_settlements")
	for settlement_id in settlements:
		var settlement: Dictionary = settlements[settlement_id]
		for building_id in settlement["buildings"]:
			_realize_building(settlement["buildings"][building_id])
		_redraw_border(settlement)


func _on_building_added(_settlement_id: String, building: Dictionary) -> void:
	_realize_building(building)


func _on_settlement_changed(settlement: Dictionary) -> void:
	_redraw_border(settlement)


func _realize_building(building: Dictionary) -> void:
	var building_id: String = building["building_id"]
	if _building_instances.has(building_id) and is_instance_valid(_building_instances[building_id]):
		return
	var definition: Resource = _construction.get("catalog").call("get_building", building["catalog_id"])
	if definition == null or definition.get("scene") == null:
		push_warning("ConstructionRealizer: no scene for catalog id '%s'" % building["catalog_id"])
		return
	var instance: Node3D = (definition.get("scene") as PackedScene).instantiate()
	instance.name = building_id
	instance.set_meta("constructed_building_id", building_id)
	instance.set_meta("faction_id", building["faction_id"])
	_world_parent().add_child(instance)
	instance.global_transform = CONSTRUCTION_SCRIPT.deserialize_transform(building["transform"])
	_building_instances[building_id] = instance
	_snap_realized_building(instance, definition, building)


## Records hold the transform solved at placement time; terrain may have
## changed since (world edits between sessions). Re-solve ground Y and tilt
## at the recorded XZ+yaw, restoring the recorded foundation raise.
func _snap_realized_building(instance: Node3D, definition: Resource, building: Dictionary) -> void:
	var tree := instance.get_tree()
	if tree == null:
		return
	await tree.physics_frame
	await tree.physics_frame
	if not is_instance_valid(instance) or not instance.is_inside_tree():
		return
	var footprint: Vector2 = definition.get("footprint_size") if definition.get("footprint_size") != null else BuildingPlacementSolver.estimate_footprint(instance)
	var snap_result := BuildingPlacementSolver.snap_to_terrain(
		instance.get_world_3d().direct_space_state,
		instance.global_transform,
		footprint,
		float(building.get("foundation", 0.0)))
	if not snap_result.is_empty():
		instance.global_transform = snap_result["transform"]


func _redraw_border(settlement: Dictionary) -> void:
	var settlement_id: String = settlement["settlement_id"]
	var old: Node = _border_instances.get(settlement_id)
	if old != null and is_instance_valid(old):
		old.queue_free()
	var center: Array = settlement["center"]
	var radius: float = settlement["radius"]
	var instance := MeshInstance3D.new()
	instance.name = "TownBorder_%s" % settlement_id
	instance.mesh = _dashed_circle_mesh(radius)
	instance.material_override = _border_material()
	instance.visible = _zoning_borders_visible
	_world_parent().add_child(instance)
	instance.global_position = Vector3(center[0], center[1] + BORDER_Y_OFFSET, center[2])
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
