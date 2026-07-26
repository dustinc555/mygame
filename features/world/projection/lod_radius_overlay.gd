extends Node3D

class_name LodRadiusOverlay

## Draws the actual population realization boundaries: camera plus every living
## party member. The green bands sample collision so slopes do not turn into walls.

const SEGMENTS := 72
const RING_WIDTH := 0.5
const GROUND_OFFSET := 0.08
const REFRESH_INTERVAL := 1.0
const RING_COLOR := Color(0.18, 1.0, 0.32, 0.82)
const EDGE_COLOR := Color(0.42, 1.0, 0.5, 1.0)

var _immediate: ImmediateMesh
var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D
var _realization_controller: Node
var _radius := 120.0
var _refresh_remaining := 0.0


func _ready() -> void:
	add_to_group("lod_radius_overlay")
	top_level = true
	visible = false
	_immediate = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _immediate
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.vertex_color_use_as_albedo = true
	_material.no_depth_test = false
	_mesh_instance.material_override = _material
	add_child(_mesh_instance)


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_remaining -= delta
	if _refresh_remaining > 0.0:
		return
	_refresh_remaining = REFRESH_INTERVAL
	_update_ring()


func _update_ring() -> void:
	if _realization_controller == null or not is_instance_valid(_realization_controller):
		_realization_controller = get_tree().get_first_node_in_group("population_realization_controller") if get_tree() != null else null
	if _realization_controller != null:
		var radius_value = _realization_controller.get("near_player_radius")
		if radius_value != null:
			_radius = float(radius_value)
	_immediate.clear_surfaces()
	var anchors := _anchor_positions()
	if anchors.is_empty():
		return
	for anchor in anchors:
		_draw_ground_ring(anchor)


func _draw_ground_ring(anchor: Vector3) -> void:
	var points: Array[Vector3] = []
	for i in range(SEGMENTS + 1):
		var angle := TAU * float(i) / float(SEGMENTS)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		points.append(_ground_point(anchor + direction * _radius, anchor.y))
	_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(SEGMENTS):
		var direction0 := Vector3(points[i].x - anchor.x, 0.0, points[i].z - anchor.z).normalized()
		var direction1 := Vector3(points[i + 1].x - anchor.x, 0.0, points[i + 1].z - anchor.z).normalized()
		var inner0 := points[i] - direction0 * (RING_WIDTH * 0.5)
		var outer0 := points[i] + direction0 * (RING_WIDTH * 0.5)
		var inner1 := points[i + 1] - direction1 * (RING_WIDTH * 0.5)
		var outer1 := points[i + 1] + direction1 * (RING_WIDTH * 0.5)
		_add_vertex(inner0, RING_COLOR)
		_add_vertex(outer0, RING_COLOR)
		_add_vertex(outer1, RING_COLOR)
		_add_vertex(inner0, RING_COLOR)
		_add_vertex(outer1, RING_COLOR)
		_add_vertex(inner1, RING_COLOR)
	_immediate.surface_end()
	_draw_edge_ring(points)


func _draw_edge_ring(points: Array[Vector3]) -> void:
	_immediate.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in points:
		_add_vertex(point, EDGE_COLOR)
	_immediate.surface_end()


func _add_vertex(vertex_position: Vector3, color: Color) -> void:
	_immediate.surface_set_color(color)
	_immediate.surface_add_vertex(vertex_position)


func _anchor_positions() -> Array[Vector3]:
	var result: Array[Vector3] = []
	if _realization_controller == null or not _realization_controller.has_method("get_realization_anchor_positions"):
		return result
	for value in _realization_controller.call("get_realization_anchor_positions"):
		if value is Vector3:
			result.append(value)
	return result


func _ground_point(world_position: Vector3, fallback_y: float) -> Vector3:
	var world := get_world_3d()
	if world == null:
		return Vector3(world_position.x, fallback_y + GROUND_OFFSET, world_position.z)
	var from := Vector3(world_position.x, fallback_y + 200.0, world_position.z)
	var to := Vector3(world_position.x, fallback_y - 500.0, world_position.z)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	var hit := world.direct_space_state.intersect_ray(query)
	var y := fallback_y
	if not hit.is_empty():
		var hit_position = hit.get("position", Vector3(world_position.x, fallback_y, world_position.z))
		if hit_position is Vector3:
			y = hit_position.y
	return Vector3(world_position.x, y + GROUND_OFFSET, world_position.z)
