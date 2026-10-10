extends SceneTree
## Non-runtime authoring bridge. Invoke only through author.py (serialized lock).
## Reads the imported meshes; it never imports, edits or repacks source scenes.

const BODY_SCRIPT = preload("res://features/actors/resources/wardrobe/wardrobe_body_profile.gd")
const BINDING_SCRIPT = preload("res://features/inventory/resources/items/clothing_binding.gd")
const SURFACE_SCRIPT = preload("res://features/inventory/resources/items/clothing_surface_binding.gd")
var failed := false

func _initialize() -> void:
	call_deferred("_run")

func _fail(message: String) -> void:
	failed = true
	push_error("WARDROBE: " + message)

func _vectors(values: PackedVector3Array) -> Array:
	var result: Array = []
	for value in values:
		result.append([value.x, value.y, value.z])
	return result

func _points(values: Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	for value: Array in values:
		if value.size() != 3:
			_fail("invalid point arity")
			return result
		var point := Vector3(value[0], value[1], value[2])
		if not point.is_finite():
			_fail("nonfinite point")
			return result
		result.append(point)
	return result

func _matrix(value: Transform3D) -> Array:
	return [
		[value.basis.x.x, value.basis.y.x, value.basis.z.x, value.origin.x],
		[value.basis.x.y, value.basis.y.y, value.basis.z.y, value.origin.y],
		[value.basis.x.z, value.basis.y.z, value.basis.z.z, value.origin.z],
		[0, 0, 0, 1]]

func _transform(rows: Array) -> Transform3D:
	return Transform3D(Basis(
		Vector3(rows[0][0], rows[1][0], rows[2][0]),
		Vector3(rows[0][1], rows[1][1], rows[2][1]),
		Vector3(rows[0][2], rows[1][2], rows[2][2])),
		Vector3(rows[0][3], rows[1][3], rows[2][3]))

func _export_scene(path: String) -> Dictionary:
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		_fail("cannot load source scene " + path)
		return {}
	var scene := packed.instantiate()
	root.add_child(scene)
	var skeletons: Array = []
	var nodes: Array[Node] = [scene]
	nodes.append_array(scene.find_children("*", "", true, false))
	for node in nodes:
		if node is Skeleton3D:
			var rests: Dictionary = {}
			for i in node.get_bone_count():
				rests[str(node.get_bone_name(i))] = _matrix(node.get_bone_global_rest(i))
			skeletons.append({"path": str(scene.get_path_to(node)), "rests": rests})
	var meshes: Array = []
	for node in nodes:
		if not node is MeshInstance3D or node.mesh == null:
			continue
		var skel := node.get_node_or_null(node.skeleton) as Skeleton3D
		var binds: Array = []
		if node.skin != null:
			for i in node.skin.get_bind_count():
				var bone_name := str(node.skin.get_bind_name(i))
				if bone_name.is_empty():
					var bone_index: int = node.skin.get_bind_bone(i)
					if skel == null or bone_index < 0 or bone_index >= skel.get_bone_count():
						_fail("unresolved skin bind in " + path)
						continue
					bone_name = str(skel.get_bone_name(bone_index))
				binds.append({"name": bone_name, "pose": _matrix(node.skin.get_bind_pose(i))})
		var surfaces: Array = []
		for i in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(i)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals := PackedVector3Array()
			if arrays[Mesh.ARRAY_NORMAL] != null:
				normals = arrays[Mesh.ARRAY_NORMAL]
			var digest := HashingContext.new()
			digest.start(HashingContext.HASH_SHA256)
			digest.update(var_to_bytes(arrays))
			surfaces.append({"surface_index": i, "vertices": _vectors(vertices),
				"normals": _vectors(normals), "primitive": node.mesh.surface_get_primitive_type(i),
				"format": node.mesh.surface_get_format(i), "arrays_sha256": digest.finish().hex_encode(),
				"indices": Array(arrays[Mesh.ARRAY_INDEX]) if arrays[Mesh.ARRAY_INDEX] != null else [],
				"bones": Array(arrays[Mesh.ARRAY_BONES]) if arrays[Mesh.ARRAY_BONES] != null else [],
				"weights": Array(arrays[Mesh.ARRAY_WEIGHTS]) if arrays[Mesh.ARRAY_WEIGHTS] != null else []})
		meshes.append({"mesh_path": str(scene.get_path_to(node)), "skin": binds,
			"skeleton_path": str(scene.get_path_to(skel)) if skel != null else "",
			"visible": node.is_visible_in_tree(), "surfaces": surfaces})
	scene.free()
	return {"scene_path": path, "skeletons": skeletons, "meshes": meshes}

func _make_resource(job: Dictionary) -> Resource:
	var data: Dictionary = job.data
	if job.kind == "body":
		var body: Resource = BODY_SCRIPT.new()
		body.cage_id = data.cage_id
		body.body_scene_path = data.body_scene_path
		body.source_digest = data.source_digest
		body.points = _points(data.points)
		if body.points.is_empty():
			_fail("empty body cage")
		for key: String in data.get("bone_aliases", {}):
			body.bone_aliases[key] = str(data.bone_aliases[key])
		return body
	if job.kind != "binding":
		_fail("unknown artifact kind")
		return null
	var binding: Resource = BINDING_SCRIPT.new()
	binding.reference_profile = ResourceLoader.load(data.reference_profile, "", ResourceLoader.CACHE_MODE_IGNORE)
	if binding.reference_profile == null:
		_fail("missing reference profile " + str(data.reference_profile))
		return null
	binding.source_scene_path = data.source_scene_path
	binding.source_digest = data.source_digest
	binding.clearance_meters = float(data.clearance_meters)
	if not is_finite(binding.clearance_meters) or binding.clearance_meters < 0:
		_fail("invalid clearance")
	for values: Dictionary in data.surfaces:
		var surface: Resource = SURFACE_SCRIPT.new()
		surface.mesh_path = NodePath(values.mesh_path)
		surface.surface_index = int(values.surface_index)
		surface.vertex_count = int(values.vertex_count)
		surface.mesh_to_reference = _transform(values.mesh_to_reference)
		surface.influences = int(values.influences)
		surface.cage_indices = PackedInt32Array(values.cage_indices)
		surface.cage_weights = PackedFloat32Array(values.cage_weights)
		var length: int = surface.vertex_count * surface.influences
		if surface.vertex_count <= 0 or surface.influences < 1 or surface.influences > 32 or surface.cage_indices.size() != length or surface.cage_weights.size() != length:
			_fail("invalid surface lengths")
			return null
		for vertex in surface.vertex_count:
			var total := 0.0
			for k in surface.influences:
				var index: int = vertex * surface.influences + k
				var weight: float = surface.cage_weights[index]
				if not is_finite(weight) or weight < 0 or surface.cage_indices[index] < 0 or surface.cage_indices[index] >= binding.reference_profile.points.size():
					_fail("invalid cage influence")
					return null
				total += weight
			if absf(total - 1.0) > 0.00001:
				_fail("cage weights do not sum to one")
				return null
		binding.surfaces.append(surface)
	if binding.surfaces.is_empty():
		_fail("binding has no surfaces")
	return binding

func _check_resource(actual: Resource, expected: Resource, kind: String) -> bool:
	if actual == null or actual.get_script() != expected.get_script() or actual.source_digest != expected.source_digest:
		return false
	if kind == "body":
		return actual.cage_id == expected.cage_id and actual.body_scene_path == expected.body_scene_path and actual.points == expected.points and actual.bone_aliases == expected.bone_aliases
	if actual.reference_profile.resource_path != expected.reference_profile.resource_path or actual.source_scene_path != expected.source_scene_path or actual.clearance_meters != expected.clearance_meters or actual.surfaces.size() != expected.surfaces.size():
		return false
	for i in actual.surfaces.size():
		for key in ["mesh_path", "surface_index", "vertex_count", "mesh_to_reference", "influences", "cage_indices", "cage_weights"]:
			if actual.surfaces[i].get(key) != expected.surfaces[i].get(key):
				return false
	return true

func _save_or_verify(job: Dictionary, save: bool) -> Dictionary:
	var expected := _make_resource(job)
	if failed or expected == null:
		return {}
	var path: String = job.path
	var exists := FileAccess.file_exists(path)
	var uid := ResourceLoader.get_resource_uid(path) if exists else ResourceUID.INVALID_ID
	# Runtime ResourceLoader may not have this file in its editor-built UID cache.
	# The verified artifact index retains its ID across separate headless runs.
	var recorded_uid := ResourceUID.text_to_id(str(job.get("preserve_uid", "")))
	if exists and recorded_uid != ResourceUID.INVALID_ID:
		uid = recorded_uid
	if save and exists and uid == ResourceUID.INVALID_ID:
		_fail("existing resource UID unavailable; restore its index record or scan it in the editor before rebuilding: " + path)
		return {}
	if save:
		if not path.begins_with("res://assets/characters/wardrobe/") and not path.begins_with("res://assets/items/equipment/wardrobe_bindings/"):
			_fail("refusing output outside wardrobe directories")
			return {}
		if path.contains("..") or path.get_extension() != "res":
			_fail("invalid native artifact path")
			return {}
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		var temporary := path.get_basename() + ".building.res"
		var error := ResourceSaver.save(expected, temporary, ResourceSaver.FLAG_COMPRESS)
		if error != OK:
			_fail("ResourceSaver failed: %s (%d)" % [path, error])
			return {}
		if uid == ResourceUID.INVALID_ID:
			uid = ResourceUID.create_id_for_path(path) if ResourceUID.has_method("create_id_for_path") else ResourceUID.create_id()
		if ResourceSaver.set_uid(temporary, uid) != OK:
			_fail("cannot preserve UID " + path)
			return {}
		var staged := ResourceLoader.load(temporary, "", ResourceLoader.CACHE_MODE_IGNORE)
		if not _check_resource(staged, expected, job.kind):
			_fail("staged resource roundtrip mismatch " + path)
			return {}
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path)) != OK:
			_fail("atomic artifact rename failed " + path)
			return {}
		if ResourceUID.has_id(uid):
			ResourceUID.set_id(uid, path)
		else:
			ResourceUID.add_id(uid, path)
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not _check_resource(loaded, expected, job.kind) or ResourceLoader.get_resource_uid(path) != uid:
		_fail("saved resource readback mismatch " + path)
		return {}
	return {"path": path, "uid": ResourceUID.id_to_text(uid), "verified": true}

func _resource_data(path: String) -> Dictionary:
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if resource == null:
		_fail("cannot read generated resource " + path)
		return {}
	var data := {"source_digest": resource.source_digest}
	if resource.get_script() == BODY_SCRIPT:
		data.merge({"cage_id": resource.cage_id, "body_scene_path": resource.body_scene_path,
			"points": _vectors(resource.points), "bone_aliases": resource.bone_aliases})
	elif resource.get_script() == BINDING_SCRIPT:
		var surfaces: Array = []
		for surface: Resource in resource.surfaces:
			surfaces.append({"mesh_path": str(surface.mesh_path), "surface_index": surface.surface_index,
				"vertex_count": surface.vertex_count, "mesh_to_reference": _matrix(surface.mesh_to_reference),
				"influences": surface.influences, "cage_indices": Array(surface.cage_indices),
				"cage_weights": Array(surface.cage_weights)})
		data.merge({"reference_profile": resource.reference_profile.resource_path,
			"source_scene_path": resource.source_scene_path, "clearance_meters": resource.clearance_meters,
			"surfaces": surfaces})
	else:
		_fail("not a wardrobe resource " + path)
	return {"path": path, "data": data}

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		_fail("expected one request JSON path")
		quit(1)
		return
	var request = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not request is Dictionary:
		_fail("invalid request JSON")
		quit(1)
		return
	var result := {"engine": Engine.get_version_info().string, "results": []}
	match str(request.get("operation", "")):
		"export":
			for path: String in request.scenes:
				result.results.append(_export_scene(path))
		"read":
			for path: String in request.paths:
				result.results.append(_resource_data(path))
		"save", "verify":
			for job: Dictionary in request.jobs:
				result.results.append(_save_or_verify(job, request.operation == "save"))
				if failed: break
		_:
			_fail("unknown operation")
	if not failed:
		var file := FileAccess.open(request.output, FileAccess.WRITE)
		if file == null:
			_fail("cannot write bridge response")
		else:
			file.store_string(JSON.stringify(result, "", true, true))
			file.close()
	if not failed:
		print("WARDROBE_NATIVE_OK ", result.results.size())
	quit(1 if failed else 0)
