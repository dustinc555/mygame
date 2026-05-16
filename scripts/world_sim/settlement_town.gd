@tool
extends "res://scripts/world_sim/settlement_anchor.gd"

class_name SettlementTown

@export var facilities_root_path: NodePath = NodePath("Facilities")
@export var bars_root_path: NodePath = NodePath("Bars")
@export var fields_root_path: NodePath = NodePath("Fields")
@export var shops_root_path: NodePath = NodePath("Shops")
@export var mines_root_path: NodePath = NodePath("Mines")
@export var housing_root_path: NodePath = NodePath("Housing")
@export var activity_points_root_path: NodePath = NodePath("ActivityPoints")
@export var storage_root_path: NodePath = NodePath("Storage")
@export var territory_root_path: NodePath = NodePath("Territory")
@export var town_border_radius := 24.0:
	set(value):
		town_border_radius = value
		_refresh_town_border_debug()
@export var town_border_debug_color := Color(0.62, 1.0, 0.94, 0.34):
	set(value):
		town_border_debug_color = value
		_refresh_town_border_debug()
@export var editor_show_debug_shape := true:
	set(value):
		editor_show_debug_shape = value
		_sync_town_border_debug_visibility()

var _town_border_debug: MeshInstance3D


func _enter_tree() -> void:
	call_deferred("_refresh_town_border_debug")


func _ready() -> void:
	super._ready()
	add_to_group("settlement_town")
	_refresh_town_border_debug()


func get_facility_nodes() -> Array:
	var facilities: Array = []
	for root_path in _get_facility_root_paths():
		var root := get_node_or_null(root_path)
		if root != null:
			_collect_facilities(root, facilities)
	return facilities


func get_facility_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var settlement_id := get_settlement_id()
	for facility in get_facility_nodes():
		if facility.has_method("get_facility_record"):
			records.append(facility.call("get_facility_record", settlement_id))
	return records


func get_activity_points() -> Array:
	var points: Array = []
	var activity_root := get_node_or_null(activity_points_root_path)
	if activity_root != null:
		_collect_activity_points(activity_root, points)
	for facility in get_facility_nodes():
		if facility.has_method("get_activity_points"):
			for point in facility.call("get_activity_points"):
				if not points.has(point):
					points.append(point)
	return points


func get_job_provider_nodes() -> Array:
	var providers: Array = []
	_collect_nodes_with_group(self, "job_provider", providers)
	return providers


func get_bar_venue_nodes() -> Array:
	var venues: Array = []
	_collect_nodes_with_group(self, "bar_venue", venues)
	return venues


func get_town_border_record() -> Dictionary:
	return {
		"settlement_id": get_settlement_id(),
		"display_name": str(settlement_definition.get("display_name")) if settlement_definition != null else name,
		"center": global_position,
		"radius": town_border_radius,
	}


func contains_town_border_position(world_position: Vector3) -> bool:
	if town_border_radius <= 0.0:
		return false
	var flat_center := Vector2(global_position.x, global_position.z)
	var flat_position := Vector2(world_position.x, world_position.z)
	return flat_center.distance_to(flat_position) <= town_border_radius


func set_town_border_debug_visible(value: bool) -> void:
	if _town_border_debug == null or not is_instance_valid(_town_border_debug):
		_create_town_border_debug()
	if _town_border_debug != null:
		_town_border_debug.visible = editor_show_debug_shape if Engine.is_editor_hint() else value


func _collect_facilities(root: Node, facilities: Array) -> void:
	for child in root.get_children():
		if child.has_method("get_facility_record") and not facilities.has(child):
			facilities.append(child)
		_collect_facilities(child, facilities)


func _get_facility_root_paths() -> Array[NodePath]:
	return [
		facilities_root_path,
		bars_root_path,
		fields_root_path,
		shops_root_path,
		mines_root_path,
		housing_root_path,
	]


func _collect_activity_points(root: Node, points: Array) -> void:
	for child in root.get_children():
		if child.has_method("get_activity_record"):
			points.append(child)
		_collect_activity_points(child, points)


func _collect_nodes_with_group(root: Node, group_name: String, nodes: Array) -> void:
	if root.is_in_group(group_name) and not nodes.has(root):
		nodes.append(root)
	for child in root.get_children():
		_collect_nodes_with_group(child, group_name, nodes)


func _create_town_border_debug() -> void:
	if town_border_radius <= 0.0:
		return
	_town_border_debug = get_node_or_null("TownBorderDebug") as MeshInstance3D
	if _town_border_debug == null:
		_town_border_debug = MeshInstance3D.new()
		_town_border_debug.name = "TownBorderDebug"
		add_child(_town_border_debug)
		_set_editor_owner(_town_border_debug)
	var mesh := CylinderMesh.new()
	mesh.top_radius = town_border_radius
	mesh.bottom_radius = town_border_radius
	mesh.height = 0.04
	mesh.radial_segments = 96
	_town_border_debug.mesh = mesh
	_town_border_debug.position = Vector3(0.0, 0.16, 0.0)
	_town_border_debug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_town_border_debug.material_override = _make_debug_material(town_border_debug_color)
	_town_border_debug.visible = Engine.is_editor_hint() and editor_show_debug_shape


func _refresh_town_border_debug() -> void:
	if not is_inside_tree():
		return
	_create_town_border_debug()


func _sync_town_border_debug_visibility() -> void:
	if _town_border_debug == null or not is_instance_valid(_town_border_debug):
		return
	if Engine.is_editor_hint():
		_town_border_debug.visible = editor_show_debug_shape


func _make_debug_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	return material


func _set_editor_owner(node: Node) -> void:
	if not Engine.is_editor_hint():
		return
	var tree := get_tree()
	if tree == null:
		return
	var edited_root := tree.edited_scene_root
	if edited_root != null:
		node.owner = edited_root
