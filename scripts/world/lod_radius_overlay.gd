extends Node3D

class_name LodRadiusOverlay

## Draws a ground ring at the population realization cutoff radius
## (PopulationRealizationController.near_player_radius) centered on the party.
## This is the "LOD line" — the boundary where actors would realize into live
## nodes vs stay in the cheap world-sim ledger. Toggled from the debug menu.

const SEGMENTS := 72
const WALL_HEIGHT := 3.0
const WALL_COLOR := Color(1.0, 0.78, 0.18, 0.13)
const EDGE_COLOR := Color(1.0, 0.86, 0.22, 0.95)

var _immediate: ImmediateMesh
var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D
var _realization_controller: Node
var _radius := 120.0


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
	# Drawn over geometry so you can always see the boundary, even through terrain/buildings.
	_material.no_depth_test = true
	_mesh_instance.material_override = _material
	add_child(_mesh_instance)


func _process(_delta: float) -> void:
	if not visible:
		return
	_update_ring()


func _update_ring() -> void:
	if _realization_controller == null or not is_instance_valid(_realization_controller):
		_realization_controller = get_tree().get_first_node_in_group("population_realization_controller") if get_tree() != null else null
	if _realization_controller != null:
		var radius_value = _realization_controller.get("near_player_radius")
		if radius_value != null:
			_radius = float(radius_value)
	var center := _reference_position()
	_immediate.clear_surfaces()
	if center == Vector3.INF:
		return
	# Translucent vertical wall — the boundary reads as a "fence" you can see the size of.
	_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(SEGMENTS):
		var a0 := TAU * float(i) / float(SEGMENTS)
		var a1 := TAU * float(i + 1) / float(SEGMENTS)
		var b0 := center + Vector3(cos(a0) * _radius, 0.1, sin(a0) * _radius)
		var b1 := center + Vector3(cos(a1) * _radius, 0.1, sin(a1) * _radius)
		var t0 := b0 + Vector3(0.0, WALL_HEIGHT, 0.0)
		var t1 := b1 + Vector3(0.0, WALL_HEIGHT, 0.0)
		_add_vertex(b0, WALL_COLOR)
		_add_vertex(t0, WALL_COLOR)
		_add_vertex(t1, WALL_COLOR)
		_add_vertex(b0, WALL_COLOR)
		_add_vertex(t1, WALL_COLOR)
		_add_vertex(b1, WALL_COLOR)
	_immediate.surface_end()
	# Bright top + bottom edge rings to crisp the boundary.
	_draw_edge_ring(center, 0.15)
	_draw_edge_ring(center, WALL_HEIGHT)


func _draw_edge_ring(center: Vector3, height: float) -> void:
	_immediate.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in range(SEGMENTS + 1):
		var angle := TAU * float(i) / float(SEGMENTS)
		_add_vertex(center + Vector3(cos(angle) * _radius, height, sin(angle) * _radius), EDGE_COLOR)
	_immediate.surface_end()


func _add_vertex(position: Vector3, color: Color) -> void:
	_immediate.surface_set_color(color)
	_immediate.surface_add_vertex(position)


func _reference_position() -> Vector3:
	var tree := get_tree()
	if tree == null:
		return Vector3.INF
	var members := tree.get_nodes_in_group("party_member")
	if not members.is_empty():
		var sum := Vector3.ZERO
		var count := 0
		for member in members:
			if member is Node3D:
				sum += (member as Node3D).global_position
				count += 1
		if count > 0:
			return sum / float(count)
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d() if viewport != null else null
	if camera != null:
		return Vector3(camera.global_position.x, 0.0, camera.global_position.z)
	return Vector3.INF
