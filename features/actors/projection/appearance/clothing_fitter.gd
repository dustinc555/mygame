extends RefCounted
class_name ClothingFitter

## One source garment + body-owned cage. Generated meshes are disposable views.
## No per-frame fitting: live proportions/animation use the actor's own skeleton.
const CACHE_LIMIT := 64
const CACHE_BYTE_LIMIT := 128 * 1024 * 1024
static var _cache: Dictionary = {}
static var _recent: Array[String] = []
static var _bytes := 0
static var _hits := 0
static var _builds := 0


static func clear_cache() -> void:
	_cache.clear()
	_recent.clear()
	_bytes = 0
	_hits = 0
	_builds = 0


static func cache_stats() -> Dictionary:
	return {"entries": _cache.size(), "bytes": _bytes, "hits": _hits, "builds": _builds}


static func fit(source: Node3D, binding: Resource, target: Resource, skeleton: Skeleton3D) -> Dictionary:
	if source == null or binding == null or target == null or skeleton == null:
		return {"error": "Clothing requires a source, binding, body profile and live skeleton"}
	var clearance: float = binding.get("clearance_meters")
	if not is_finite(clearance) or clearance < 0.0 or clearance > 0.08:
		return {"error": "Clothing clearance must be finite and between 0 and 0.08 meters"}
	var reference: Resource = binding.get("reference_profile")
	if reference == null or str(reference.get("cage_id")).is_empty() or reference.get("cage_id") != target.get("cage_id"):
		return {"error": "Clothing/body cage families do not match"}
	var source_points: PackedVector3Array = reference.get("points")
	var target_points: PackedVector3Array = target.get("points")
	if source_points.is_empty() or source_points.size() != target_points.size():
		return {"error": "Clothing/body cage point counts do not match"}
	var surfaces: Array = binding.get("surfaces")
	if surfaces.is_empty(): return {"error": "Clothing binding has no surfaces; rebuild its binding"}
	var source_path: String = binding.get("source_scene_path")
	if not source_path.is_empty() and not source.scene_file_path.is_empty() and source.scene_file_path != source_path:
		return {"error": "Clothing binding belongs to a different source scene"}
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(source, meshes)
	var fingerprint: Array = [binding.get_instance_id(), hash(source_points), hash(target_points), target.get("bone_aliases"), binding.get("clearance_meters")]
	for bone in skeleton.get_bone_count():
		fingerprint.append([skeleton.get_bone_name(bone), skeleton.get_bone_global_rest(bone)])
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh == null or mesh.skin == null:
			return {"error": "Clothing fit requires skinned source meshes: " + str(mesh.name)}
		# Native resources can be edited/reimported in place without changing ID.
		# Static callbacks retain no character nodes and die with the source resource.
		for resource: Resource in [mesh.mesh, mesh.skin]:
			if not resource.changed.is_connected(clear_cache):
				resource.changed.connect(clear_cache)
		fingerprint.append([str(source.get_path_to(mesh)), mesh.mesh.get_instance_id(), mesh.skin.get_instance_id()])
	for surface: Resource in surfaces:
		fingerprint.append([surface.get("mesh_path"), surface.get("surface_index"), surface.get("vertex_count"), surface.get("influences"), surface.get("mesh_to_reference"), hash(surface.get("cage_indices")), hash(surface.get("cage_weights"))])
	var key := str(hash(fingerprint))
	var use_cache := not Engine.is_editor_hint()
	if use_cache and _cache.has(key) and _cache[key].fingerprint == fingerprint:
		_hits += 1
		_recent.erase(key)
		_recent.append(key)
		return {"error": "", "visual": _instantiate(source.name, _cache[key].meshes, meshes), "cache_hit": true}
	var started := Time.get_ticks_usec()
	var deltas := PackedVector3Array()
	deltas.resize(source_points.size())
	var unchanged := true
	for point in source_points.size():
		if not source_points[point].is_finite() or not target_points[point].is_finite():
			return {"error": "Clothing cage contains nonfinite points"}
		deltas[point] = target_points[point] - source_points[point]
		if deltas[point].length_squared() > 0.000000000001: unchanged = false
	var generated: Array[Dictionary] = []
	var byte_count := 0
	var matched_surfaces := 0
	for mesh: MeshInstance3D in meshes:
		var path := source.get_path_to(mesh)
		var adapted := ArrayMesh.new()
		if mesh.mesh.get_blend_shape_count() > 0:
			return {"error": "Garment-authored morph targets require explicit binding support: " + str(path)}
		var skin_result := _make_skin(mesh, target, skeleton)
		if not skin_result.error.is_empty(): return skin_result
		for index in mesh.mesh.get_surface_count():
			var bound: Resource
			for candidate: Resource in surfaces:
				if candidate.get("mesh_path") == path and int(candidate.get("surface_index")) == index:
					if bound != null: return {"error": "Duplicate clothing surface binding: " + str(path)}
					bound = candidate
			if bound == null: return {"error": "Clothing binding omits source surface: %s/%d" % [path, index]}
			var arrays := mesh.mesh.surface_get_arrays(index)
			var error := _validate_surface(arrays, bound, source_points.size())
			if not error.is_empty(): return {"error": "%s: %s/%d" % [error, path, index]}
			var changed := _fit_surface(arrays, bound, deltas, float(binding.get("clearance_meters")), unchanged)
			adapted.add_surface_from_arrays(mesh.mesh.surface_get_primitive_type(index), changed, [], {}, mesh.mesh.surface_get_format(index))
			adapted.surface_set_material(index, mesh.mesh.surface_get_material(index))
			for array: Variant in changed:
				if array != null: byte_count += var_to_bytes(array).size()
			matched_surfaces += 1
		generated.append({"mesh": adapted, "skin": skin_result.skin})
	if matched_surfaces != surfaces.size(): return {"error": "Clothing binding contains stale mesh paths; rebuild it"}
	_builds += 1
	if use_cache and byte_count <= CACHE_BYTE_LIMIT:
		while not _recent.is_empty() and (_cache.size() >= CACHE_LIMIT or _bytes + byte_count > CACHE_BYTE_LIMIT):
			var oldest := _recent.pop_front() as String
			_bytes -= int(_cache[oldest].bytes)
			_cache.erase(oldest)
		_cache[key] = {"meshes": generated, "bytes": byte_count, "fingerprint": fingerprint}
		_recent.append(key)
		_bytes += byte_count
	return {"error": "", "visual": _instantiate(source.name, generated, meshes), "cache_hit": false, "build_usec": Time.get_ticks_usec() - started}


static func _collect_meshes(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D: output.append(node as MeshInstance3D)
	for child in node.get_children(): _collect_meshes(child, output)


static func _make_skin(mesh: MeshInstance3D, profile: Resource, target: Skeleton3D) -> Dictionary:
	var used: Dictionary = {}
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		if arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_WEIGHTS] == null:
			return {"error": "Clothing source is missing skin weights"}
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if bones.size() != weights.size(): return {"error": "Clothing bone/weight count mismatch"}
		for index in bones.size():
			if not is_finite(weights[index]) or weights[index] < 0: return {"error": "Invalid source skin weight"}
			if weights[index] <= 0.0: continue
			if bones[index] < 0 or bones[index] >= mesh.skin.get_bind_count(): return {"error": "Invalid source skin bind index"}
			used[bones[index]] = true
	var source_skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
	var result := Skin.new()
	var aliases: Dictionary = profile.get("bone_aliases")
	for bind in mesh.skin.get_bind_count():
		var name := String(mesh.skin.get_bind_name(bind))
		if name.is_empty() and source_skeleton != null:
			var bone := mesh.skin.get_bind_bone(bind)
			if bone >= 0 and bone < source_skeleton.get_bone_count(): name = source_skeleton.get_bone_name(bone)
		var target_name: String = aliases.get(name, name)
		var target_bone := target.find_bone(target_name)
		if target_bone < 0:
			if used.has(bind): return {"error": "Clothing requires weighted joint '%s', absent on this body" % name}
			if target.get_bone_count() == 0: return {"error": "Target skeleton has no bones"}
			target_bone = 0
			target_name = target.get_bone_name(0)
		result.add_named_bind(target_name, target.get_bone_global_rest(target_bone).affine_inverse())
	return {"error": "", "skin": result}


static func _validate_surface(arrays: Array, binding: Resource, cage_count: int) -> String:
	var transform: Transform3D = binding.get("mesh_to_reference")
	if not transform.is_finite() or absf(transform.basis.determinant()) < 0.00000001:
		return "Invalid clothing source transform"
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var count: int = binding.get("vertex_count")
	if count <= 0 or vertices.size() != count: return "Stale clothing binding vertex count"
	var influences: int = binding.get("influences")
	var indices: PackedInt32Array = binding.get("cage_indices")
	var weights: PackedFloat32Array = binding.get("cage_weights")
	if influences < 1 or influences > 32 or indices.size() != count * influences or weights.size() != indices.size():
		return "Invalid clothing binding array lengths"
	var skin_weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if skin_weights.size() != count * 4 and skin_weights.size() != count * 8: return "Invalid garment skin influence count"
	var skin_stride: int = skin_weights.size() / count
	# Native reductions replace per-influence bounds checks on valid bindings.
	# Keep the ordered checks below for invalid input so the first error is unchanged.
	var in_range := _nonnegative_below(indices, cage_count) and _nonnegative_below(weights, INF)
	for vertex in count:
		if not vertices[vertex].is_finite(): return "Invalid source garment vertex"
		var sum := 0.0
		if in_range:
			var first := vertex * influences
			for influence in influences: sum += weights[first + influence]
			# min/max can ignore an interior NaN; summing every weight cannot.
			if not is_finite(sum): return "Invalid clothing cage weight"
		else:
			for influence in influences:
				var index := vertex * influences + influence
				if indices[index] < 0 or indices[index] >= cage_count: return "Invalid clothing cage index"
				if not is_finite(weights[index]) or weights[index] < 0: return "Invalid clothing cage weight"
				sum += weights[index]
		if absf(sum - 1.0) > 0.0001: return "Clothing cage weights must sum to one"
		var skin_sum := 0.0
		for influence in skin_stride: skin_sum += skin_weights[vertex * skin_stride + influence]
		if absf(skin_sum - 1.0) > 0.001: return "Garment skin weights must sum to one"
	return ""


static func _nonnegative_below(packed: Variant, maximum: float) -> bool:
	# Scope the temporary Variant array to one reduction, not the entire surface.
	var values := Array(packed)
	return values.min() >= 0.0 and values.max() < maximum


static func _fit_surface(input: Array, binding: Resource, deltas: PackedVector3Array, clearance: float, unchanged: bool) -> Array:
	var arrays := input.duplicate(true)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = binding.get("cage_indices")
	var weights: PackedFloat32Array = binding.get("cage_weights")
	var influences: int = binding.get("influences")
	var transform: Transform3D = binding.get("mesh_to_reference")
	var normal_basis := transform.basis.inverse().transposed()
	for vertex in vertices.size():
		var point := vertices[vertex]
		if not normals.is_empty(): point += normals[vertex] * clearance
		point = transform * point
		if not unchanged:
			for influence in influences:
				var index := vertex * influences + influence
				point += deltas[indices[index]] * weights[index]
		vertices[vertex] = point
		if not normals.is_empty(): normals[vertex] = (normal_basis * normals[vertex]).normalized()
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	if transform.basis != Basis.IDENTITY and arrays[Mesh.ARRAY_TANGENT] != null:
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		for vertex in vertices.size():
			var index := vertex * 4
			var tangent := transform.basis * Vector3(tangents[index], tangents[index + 1], tangents[index + 2])
			if not normals.is_empty():
				tangent -= normals[vertex] * normals[vertex].dot(tangent)
			tangent = tangent.normalized()
			tangents[index] = tangent.x
			tangents[index + 1] = tangent.y
			tangents[index + 2] = tangent.z
			tangents[index + 3] *= signf(transform.basis.determinant())
		arrays[Mesh.ARRAY_TANGENT] = tangents
	if not unchanged: _rebuild_frames(arrays)
	return arrays


static func _rebuild_frames(arrays: Array) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var old_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	if old_normals.is_empty(): return
	var triangles: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vertices.size()))
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for face in range(0, triangles.size() - 2, 3):
		var a := triangles[face]
		var b := triangles[face + 1]
		var c := triangles[face + 2]
		var normal := (vertices[c] - vertices[a]).cross(vertices[b] - vertices[a])
		if normal.dot(old_normals[a]) < 0: normal = -normal
		normals[a] += normal
		normals[b] += normal
		normals[c] += normal
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	for vertex in vertices.size():
		normals[vertex] = normals[vertex].normalized() if normals[vertex].length_squared() > 0.0 else old_normals[vertex]
		if not tangents.is_empty():
			var index := vertex * 4
			var tangent := Vector3(tangents[index], tangents[index + 1], tangents[index + 2])
			tangent = (tangent - normals[vertex] * normals[vertex].dot(tangent)).normalized()
			tangents[index] = tangent.x
			tangents[index + 1] = tangent.y
			tangents[index + 2] = tangent.z
	arrays[Mesh.ARRAY_NORMAL] = normals
	if not tangents.is_empty(): arrays[Mesh.ARRAY_TANGENT] = tangents


static func _instantiate(name: StringName, records: Array, sources: Array[MeshInstance3D]) -> Node3D:
	var root := Node3D.new()
	root.name = name
	for record_index in records.size():
		var record: Dictionary = records[record_index]
		var source := sources[record_index]
		var mesh := MeshInstance3D.new()
		mesh.name = source.name
		mesh.mesh = record.mesh
		mesh.skin = record.skin
		mesh.material_override = source.material_override
		mesh.material_overlay = source.material_overlay
		mesh.layers = source.layers
		mesh.cast_shadow = source.cast_shadow
		mesh.visible = source.visible
		for index in source.get_surface_override_material_count():
			mesh.set_surface_override_material(index, source.get_surface_override_material(index))
		root.add_child(mesh)
	return root
