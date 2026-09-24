@tool
extends Node3D

class_name FacilityGuardPost

@export var collision_shape: Shape3D
@export var stand_radius := 0.85
## Rotate the node to aim the arrow (+Z). No wall scans or inferred facing.
@export_enum("Town Guard", "Private Security") var guard_scope := "Town Guard"
## Private spots default to the containing facility's proprietor. Set a stable
## character ID to share an employer's posts across buildings or a caravan.
@export var employer_actor_id := ""
## Optional persistent identity; otherwise the town-relative authored path is used.
@export var post_id := ""
@export_range(1.0, 240.0, 1.0) var hold_minutes := 30.0
@export var editor_show_debug_marker := true:
	set(value):
		editor_show_debug_marker = value
		_sync_debug_marker_visibility()
@export var debug_color := Color(0.46, 1.0, 0.38, 0.76):
	set(value):
		debug_color = value
		_refresh_debug_marker()

var _assigned_worker: WorldActor
var _debug_marker: MeshInstance3D
var _debug_arrow: MeshInstance3D


func _enter_tree() -> void:
	call_deferred("_refresh_debug_marker")


func _ready() -> void:
	add_to_group("facility_guard_post")
	_refresh_debug_marker()


func get_work_position() -> Vector3:
	return global_position


func get_facing_direction() -> Vector3:
	var forward := global_basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD


func get_post_id() -> String:
	if not post_id.strip_edges().is_empty():
		return post_id.strip_edges()
	var town := _town()
	return "%s:%s" % [town.call("get_settlement_id"), town.get_path_to(self)] if town != null else str(get_path())


func get_pool_key(facility_employers: Dictionary) -> String:
	if guard_scope == "Private Security":
		var employer := employer_actor_id.strip_edges()
		var ancestor := get_parent()
		while employer.is_empty() and ancestor != null:
			if ancestor.has_method("get_facility_id"):
				employer = str(facility_employers.get(str(ancestor.call("get_facility_id")), ""))
				break
			ancestor = ancestor.get_parent()
		return "character:" + employer if not employer.is_empty() else ""
	var town := _town()
	return "town:" + str(town.call("get_settlement_id")) if town != null else ""


func _town() -> Node:
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor.has_method("get_settlement_id"):
			return ancestor
		ancestor = ancestor.get_parent()
	return null


func claim_worker(worker: WorldActor) -> bool:
	if worker == null:
		return false
	if _assigned_worker != null and is_instance_valid(_assigned_worker) and _assigned_worker != worker:
		return false
	_assigned_worker = worker
	return true


func release_worker(worker: WorldActor) -> void:
	if _assigned_worker == worker:
		_assigned_worker = null


func is_available_for(worker: WorldActor) -> bool:
	return _assigned_worker == null or not is_instance_valid(_assigned_worker) or _assigned_worker == worker


func get_assigned_worker() -> WorldActor:
	return _assigned_worker if _assigned_worker != null and is_instance_valid(_assigned_worker) else null


func is_worker_at_post(worker: WorldActor) -> bool:
	return worker != null and worker.global_position.distance_to(global_position) <= stand_radius


func _refresh_debug_marker() -> void:
	if not is_inside_tree():
		return
	if not Engine.is_editor_hint():
		_hide_debug_marker()
		return
	_create_debug_marker()
	if _debug_marker == null:
		return
	var disc := CylinderMesh.new()
	disc.top_radius = 0.35
	disc.bottom_radius = 0.35
	disc.height = 0.025
	_debug_marker.mesh = disc
	_debug_marker.position.y = 0.025
	_debug_marker.material_override = _make_debug_material(debug_color)
	_debug_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not is_instance_valid(_debug_arrow):
		_debug_arrow = MeshInstance3D.new()
		_debug_arrow.name = "FacingArrow"
		add_child(_debug_arrow, false, Node.INTERNAL_MODE_BACK)
	_debug_arrow.mesh = _build_arrow_mesh()
	_debug_arrow.material_override = _make_debug_material(Color(1.0, 0.85, 0.25, 0.95))
	_debug_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sync_debug_marker_visibility()


func _create_debug_marker() -> void:
	_debug_marker = get_node_or_null("DebugMarker") as MeshInstance3D
	if _debug_marker != null:
		return
	_debug_marker = MeshInstance3D.new()
	_debug_marker.name = "DebugMarker"
	add_child(_debug_marker, false, Node.INTERNAL_MODE_BACK)


func _sync_debug_marker_visibility() -> void:
	if _debug_marker != null and is_instance_valid(_debug_marker):
		_debug_marker.visible = Engine.is_editor_hint() and editor_show_debug_marker
	if is_instance_valid(_debug_arrow):
		_debug_arrow.visible = Engine.is_editor_hint() and editor_show_debug_marker


func _hide_debug_marker() -> void:
	_debug_marker = get_node_or_null("DebugMarker") as MeshInstance3D
	if _debug_marker != null:
		_debug_marker.visible = false


func _build_arrow_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array([
		Vector3(-0.065, 0.06, 0.0), Vector3(0.065, 0.06, 0.0),
		Vector3(0.065, 0.06, 0.65), Vector3(-0.065, 0.06, 0.65),
		Vector3(-0.23, 0.06, 0.65), Vector3(0.23, 0.06, 0.65),
		Vector3(0, 0.06, 1.0),
	])
	var indices := PackedInt32Array([
		0, 1, 2, 0, 2, 3,
		4, 5, 6,
	])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_debug_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	return material
