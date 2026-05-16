@tool
extends "res://scripts/world_sim/settlement_facility_instance.gd"

class_name SettlementField

const FIELD_FUNCTION = preload("res://resources/world_sim/facility_functions/field.tres")
const ACTIVITY_POINT_SCRIPT = preload("res://scripts/world_sim/settlement_activity_point.gd")

@export var field_size := Vector2(16.0, 10.0):
	set(value):
		field_size = value
		_repair_authoring_tree()


func _ready() -> void:
	_repair_authoring_tree()
	super._ready()


func _repair_authoring_tree() -> void:
	_apply_field_defaults()
	super._repair_authoring_tree()
	if not is_inside_tree() or not auto_create_standard_roots:
		return
	_ensure_visuals()
	_ensure_activity_points()


func _apply_field_defaults() -> void:
	if facility_function == null:
		facility_function = FIELD_FUNCTION
	building_root_path = NodePath("BuildingSlot")
	staff_root_path = NodePath("Staff")
	service_points_root_path = NodePath("ServicePoints")
	storage_root_path = NodePath("Storage")
	job_providers_root_path = NodePath("JobProviders")
	activity_points_root_path = NodePath("ActivityPoints")
	facility_type = "farm"
	if display_name.is_empty() or display_name == "Facility":
		display_name = "Settlement Field"


func _ensure_visuals() -> void:
	var visual := get_node_or_null("FieldVisual") as MeshInstance3D
	if visual == null:
		visual = MeshInstance3D.new()
		visual.name = "FieldVisual"
		visual.position = Vector3(0.0, 0.035, 0.0)
		add_child(visual)
		_set_editor_owner(visual)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(field_size.x, 0.04, field_size.y)
	visual.mesh = mesh
	visual.material_override = _make_material(Color(0.34, 0.48, 0.2, 0.62))
	var rows := _ensure_child_root(self, "Rows")
	for index in range(3):
		var row_name := "Row%s" % char(65 + index)
		var row := rows.get_node_or_null(row_name) as MeshInstance3D
		if row == null:
			row = MeshInstance3D.new()
			row.name = row_name
			rows.add_child(row)
			_set_editor_owner(row)
		var row_mesh := BoxMesh.new()
		row_mesh.size = Vector3(maxf(field_size.x - 1.0, 1.0), 0.05, 0.35)
		row.mesh = row_mesh
		row.material_override = _make_material(Color(0.23, 0.16, 0.08, 1.0))
		row.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(5.0)), Vector3(0.0, 0.075, -field_size.y * 0.3 + field_size.y * 0.3 * index))


func _ensure_activity_points() -> void:
	var root := _ensure_root(activity_points_root_path)
	var positions := [
		Vector3(-field_size.x * 0.34, 0.05, -field_size.y * 0.27),
		Vector3(0.0, 0.05, 0.2),
		Vector3(field_size.x * 0.34, 0.05, field_size.y * 0.28),
	]
	for index in range(positions.size()):
		var point_name := "FieldHand%s" % char(65 + index)
		var point := root.get_node_or_null(point_name)
		if point == null:
			point = Marker3D.new()
			point.name = point_name
			point.set_script(ACTIVITY_POINT_SCRIPT)
			root.add_child(point)
			_set_editor_owner(point)
		if point is Node3D:
			(point as Node3D).position = positions[index]
		point.set("activity_type", "farm")
		point.set("weight", 2.0)
		point.set("active_start_hour", 5)
		point.set("active_end_hour", 19)


func _ensure_child_root(parent: Node, root_name: String) -> Node:
	var child := parent.get_node_or_null(root_name)
	if child != null:
		return child
	child = Node3D.new()
	child.name = root_name
	parent.add_child(child)
	_set_editor_owner(child)
	return child


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	return material
