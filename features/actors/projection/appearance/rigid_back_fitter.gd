@tool
extends RefCounted
## Fits an unskinned Y-up, +Z-outward pack once at equip/rebuild time.
## Anatomy and body surfaces live on the wearer; no race names or per-frame work.
## A single upper-spine skin follows animation without deforming the pack.
const LANDMARKS := [&"pelvis", &"neck_01", &"spine_03", &"upperarm_l", &"upperarm_r"]
const MAX_CACHED_MESHES := 16
static var _meshes: Dictionary = {}

static func fit(source: Node3D, visual: EquipmentVisualDefinition, skeleton: Skeleton3D, body_root: Node3D) -> Dictionary:
	if source == null or visual == null or skeleton == null or body_root == null:
		return _failure("Rigid back fit requires a source, body and live skeleton")
	var points: Array[Vector3] = []
	for landmark in LANDMARKS:
		var index := skeleton.find_bone(landmark)
		if index < 0:
			return _failure("Rigid back fit: missing body landmark %s" % landmark)
		points.append(skeleton.get_bone_global_pose(index).origin)
	var pelvis := points[0]
	var torso_height := points[0].distance_to(points[1])
	var shoulder_width := points[3].distance_to(points[4])
	if torso_height < 0.001 or shoulder_width < 0.001:
		return _failure("Rigid back fit: degenerate torso landmarks")
	var up := (points[1] - pelvis).normalized()
	var right := (points[3] - points[4]).normalized()
	var forward := right.cross(up).normalized()
	if forward.length_squared() < 0.5:
		return _failure("Rigid back fit: degenerate torso axes")
	right = up.cross(forward).normalized()
	var sources: Array[MeshInstance3D] = []
	_collect_meshes(source, sources)
	var bounds := AABB()
	var have_bounds := false
	for mesh in sources:
		if mesh.mesh == null: continue
		var box := _relative(source, mesh) * mesh.mesh.get_aabb()
		bounds = bounds.merge(box) if have_bounds else box
		have_bounds = true
	if not have_bounds or bounds.size.y < 0.001 or bounds.size.x < 0.001:
		return _failure("Rigid back fit: source has no usable mesh")
	var scale_factor := minf(torso_height * visual.back_height_ratio / bounds.size.y,
		shoulder_width * visual.back_width_ratio / bounds.size.x)
	if scale_factor <= 0.0:
		return _failure("Rigid back fit: size ratios must be positive")
	var envelope := _back_surface(body_root, skeleton, pelvis, right, up, forward, torso_height, shoulder_width)
	if not envelope.found:
		return _failure("Rigid back fit: no torso surface on the live body")
	var basis := Basis(-right, up, -forward).scaled(Vector3.ONE * scale_factor)
	var source_anchor := Vector3(bounds.get_center().x, bounds.position.y, bounds.position.z)
	var target_anchor := pelvis + up * torso_height * visual.back_raise_ratio
	target_anchor += forward * (float(envelope.depth) - torso_height * visual.back_clearance_ratio)
	var placement := Transform3D(basis, target_anchor - basis * source_anchor)
	var bone := skeleton.find_bone(&"spine_03")
	# Capture the wearer's current anatomy, including live proportion modifiers.
	# Bind relative to this pose so the next animated pose moves the rigid bag.
	var inverse_pose := skeleton.get_bone_global_pose(bone).affine_inverse()
	var result := Node3D.new()
	result.name = source.name
	for mesh in sources:
		if mesh.mesh == null: continue
		var prepared := _rigid_mesh(mesh.mesh)
		if prepared == null:
			result.free()
			return _failure("Rigid back fit: unsupported source mesh surface")
		var copy := MeshInstance3D.new()
		copy.name = mesh.name
		copy.mesh = prepared
		copy.material_override = mesh.material_override
		copy.cast_shadow = mesh.cast_shadow
		for surface in mesh.mesh.get_surface_count():
			copy.set_surface_override_material(surface, mesh.get_surface_override_material(surface))
		var mesh_placement := placement * _relative(source, mesh)
		copy.skin = Skin.new()
		copy.skin.add_named_bind(&"spine_03", inverse_pose * mesh_placement)
		# GPU skinning moves source vertices outside their original bounds.
		copy.custom_aabb = (mesh_placement * mesh.mesh.get_aabb()).grow(torso_height * 0.5)
		result.add_child(copy)
	return {"error": "", "visual": result}

static func _back_surface(root: Node3D, skeleton: Skeleton3D, pelvis: Vector3, right: Vector3, up: Vector3, forward: Vector3, height: float, width: float) -> Dictionary:
	var candidates: Array[MeshInstance3D] = []
	_collect_meshes(root, candidates, true)
	var found := false
	var depth := INF
	for mesh in candidates:
		if mesh.mesh == null or mesh.skin == null or mesh.get_node_or_null(mesh.skeleton) != skeleton:
			continue
		var to_skeleton := skeleton.global_transform.affine_inverse() * mesh.global_transform
		var skin_poses: Array[Transform3D] = []
		for bind in mesh.skin.get_bind_count():
			var bone := skeleton.find_bone(mesh.skin.get_bind_name(bind)) if mesh.skin.get_bind_name(bind) != &"" else mesh.skin.get_bind_bone(bind)
			if bone < 0 or bone >= skeleton.get_bone_count():
				return {"found": false, "depth": 0.0}
			skin_poses.append(skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind))
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
			var influences := bones.size() / maxi(vertices.size(), 1)
			for index in vertices.size():
				var vertex := vertices[index]
				var point := to_skeleton * vertex
				if influences > 0:
					point = Vector3.ZERO
					for influence in influences:
						var offset := index * influences + influence
						if weights[offset] > 0.0:
							point += (skin_poses[bones[offset]] * vertex) * weights[offset]
				point -= pelvis
				var y := point.dot(up)
				if y < height * 0.1 or y > height * 1.05 or absf(point.dot(right)) > width * 0.65:
					continue
				depth = minf(depth, point.dot(forward))
				found = true
	return {"found": found, "depth": depth}

static func _rigid_mesh(source: Mesh) -> ArrayMesh:
	if _meshes.has(source): return _meshes[source]
	var result := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface).duplicate(true)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if vertices.is_empty(): return null
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		bones.resize(vertices.size() * 4)
		weights.resize(vertices.size() * 4)
		for vertex in vertices.size(): weights[vertex * 4] = 1.0
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		var lods: Dictionary = {}
		# ArrayMesh's LOD getter is not exposed to GDScript; the server's
		# documented surface dictionary retains the imported index buffers.
		var surface_data := RenderingServer.mesh_get_surface(source.get_rid(), surface)
		for lod: Dictionary in surface_data.get("lods", []):
			var bytes: PackedByteArray = lod.index_data
			var indices := PackedInt32Array()
			if vertices.size() < 65536:
				indices.resize(bytes.size() / 2)
				for i in indices.size(): indices[i] = bytes.decode_u16(i * 2)
			else:
				indices = bytes.to_int32_array()
			lods[float(lod.edge_length)] = indices
		var primitive: int = (source as ArrayMesh).surface_get_primitive_type(surface) if source is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES
		result.add_surface_from_arrays(primitive, arrays, [], lods)
		result.surface_set_material(surface, source.surface_get_material(surface))
	if _meshes.size() >= MAX_CACHED_MESHES: _meshes.erase(_meshes.keys()[0])
	_meshes[source] = result
	return result

static func _collect_meshes(node: Node, out: Array[MeshInstance3D], body_only := false) -> void:
	if body_only and (str(node.name).begins_with("Equipped") or (node is Node3D and not node.visible)):
		return
	if node is MeshInstance3D: out.append(node)
	for child in node.get_children(): _collect_meshes(child, out, body_only)

static func _relative(root: Node3D, node: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D: result = current.transform * result
		current = current.get_parent()
	return result

static func _failure(message: String) -> Dictionary:
	return {"error": message, "visual": null}
