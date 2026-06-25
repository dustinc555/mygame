extends Node3D

@export var auto_start_unconscious := true
@export var pyramid_half_size := 14.0
@export var pyramid_height := 10.0


func _ready() -> void:
	_ensure_pyramid()
	if auto_start_unconscious:
		call_deferred("_start_ragdoll_demo")


func _ensure_pyramid() -> void:
	if get_node_or_null("Pyramid") != null:
		return
	var pyramid := StaticBody3D.new()
	pyramid.name = "Pyramid"
	add_child(pyramid)

	var points := PackedVector3Array([
		Vector3(0.0, pyramid_height, 0.0),
		Vector3(-pyramid_half_size, 0.0, -pyramid_half_size),
		Vector3(pyramid_half_size, 0.0, -pyramid_half_size),
		Vector3(pyramid_half_size, 0.0, pyramid_half_size),
		Vector3(-pyramid_half_size, 0.0, pyramid_half_size),
	])
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	var convex_shape := ConvexPolygonShape3D.new()
	convex_shape.points = points
	collision_shape.shape = convex_shape
	pyramid.add_child(collision_shape)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "MeshInstance3D"
	mesh_instance.mesh = _build_pyramid_mesh(points)
	pyramid.add_child(mesh_instance)


func _build_pyramid_mesh(points: PackedVector3Array) -> Mesh:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.93, 0.71, 0.34, 1.0)
	material.roughness = 0.92
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(material)
	_add_triangle(st, points[0], points[2], points[1])
	_add_triangle(st, points[0], points[3], points[2])
	_add_triangle(st, points[0], points[4], points[3])
	_add_triangle(st, points[0], points[1], points[4])
	_add_triangle(st, points[1], points[2], points[3])
	_add_triangle(st, points[3], points[4], points[1])
	st.generate_normals()
	return st.commit()


func _add_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _start_ragdoll_demo() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	var character := get_node_or_null("PartyMembers/Mira") as HumanoidCharacter
	if character == null:
		return
	var face_z := -pyramid_half_size * 0.45
	var face_y := _get_north_face_height(face_z) + 0.7
	character.global_position = Vector3(0.0, face_y, face_z)
	character.rotation = Vector3(0.0, PI, 0.0)
	character.velocity = Vector3.ZERO
	character.force_unconscious()
	character._downed_recover_delay_remaining = 999.0


func _get_north_face_height(z_position: float) -> float:
	return pyramid_height + z_position * pyramid_height / pyramid_half_size
