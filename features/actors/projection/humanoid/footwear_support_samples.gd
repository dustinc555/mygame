extends RefCounted
## Cache actual skinned sole support vertices, never mesh bounds or ankle origins.
## Rebuilt only when body/footwear changes. At most 36 heel/toe supports are posed.
const DIRECTIONS := [Vector2.ZERO, Vector2(-1,-1), Vector2(-1,0), Vector2(-1,1), Vector2(0,-1), Vector2(0,1), Vector2(1,-1), Vector2(1,0), Vector2(1,1)]
var samples: Array[Dictionary] = []

func rebuild(roots: Array[Node], skeleton: Skeleton3D) -> void:
	samples.clear()
	var best: Dictionary = {}
	for root in roots:
		_scan(root, skeleton, best)
	for value: Dictionary in best.values():
		samples.append(value)

func _scan(node: Node, skeleton: Skeleton3D, best: Dictionary) -> void:
	if node is MeshInstance3D:
		_scan_mesh(node, skeleton, best)
	for child in node.get_children():
		_scan(child, skeleton, best)

func _scan_mesh(mesh: MeshInstance3D, skeleton: Skeleton3D, best: Dictionary) -> void:
	if mesh.mesh == null or mesh.skin == null or not mesh.is_visible_in_tree() or mesh.get_node_or_null(mesh.skeleton) != skeleton:
		return
	var bind_bones: Array[int] = []
	var bind_poses: Array[Transform3D] = []
	var rest: Array[Transform3D] = []
	var sides: Array[int] = []
	for index in mesh.skin.get_bind_count():
		var bone := skeleton.find_bone(mesh.skin.get_bind_name(index))
		if bone < 0: bone = mesh.skin.get_bind_bone(index)
		if bone < 0 or bone >= skeleton.get_bone_count(): return
		bind_bones.append(bone)
		bind_poses.append(mesh.skin.get_bind_pose(index))
		rest.append(skeleton.get_bone_global_rest(bone) * bind_poses[-1])
		var name := skeleton.get_bone_name(bone)
		sides.append(0 if name in ["foot_l", "ball_l"] else (1 if name in ["foot_r", "ball_r"] else -1))
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_WEIGHTS] == null: continue
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var count := weights.size() / maxi(vertices.size(), 1)
		for vertex in vertices.size():
			var support_weight := Vector2.ZERO
			var strongest_weight := Vector2.ZERO
			var support_bones := Vector2i(-1, -1)
			var point := Vector3.ZERO
			for influence in count:
				var offset: int = vertex * count + influence
				var bind := bones[offset]
				if weights[offset] <= 0.0: continue
				if bind < 0 or bind >= bind_bones.size(): return
				point += (rest[bind] * vertices[vertex]) * weights[offset]
				var bind_side := sides[bind]
				if bind_side >= 0:
					support_weight[bind_side] += weights[offset]
					if weights[offset] > strongest_weight[bind_side]:
						strongest_weight[bind_side] = weights[offset]
						support_bones[bind_side] = bind_bones[bind]
			var side := 0 if support_weight.x >= support_weight.y else 1
			if support_weight[side] < 0.5: continue
			for direction in DIRECTIONS.size():
				var axis: Vector2 = DIRECTIONS[direction]
				var score: float = point.y - 0.5 * (point.x * axis.x + point.z * axis.y)
				# A lower rest heel must not discard toes that move independently.
				var key := support_bones[side] * DIRECTIONS.size() + direction
				if best.has(key) and best[key].score <= score: continue
				var sample := {"score":score, "side":side, "bones":PackedInt32Array(), "points":PackedVector3Array(), "weights":PackedFloat32Array()}
				for influence in count:
					var offset: int = vertex * count + influence
					if weights[offset] <= 0.0: continue
					var bind := bones[offset]
					sample.bones.append(bind_bones[bind])
					sample.points.append(bind_poses[bind] * vertices[vertex])
					sample.weights.append(weights[offset])
				best[key] = sample

func posed_points(skeleton: Skeleton3D) -> Array[Vector3]:
	var poses: Dictionary = {}
	var result: Array[Vector3] = []
	for sample in samples:
		var point := Vector3.ZERO
		for influence in sample.bones.size():
			var bone: int = sample.bones[influence]
			if not poses.has(bone): poses[bone] = skeleton.global_transform * skeleton.get_bone_global_pose(bone)
			point += (poses[bone] * sample.points[influence]) * sample.weights[influence]
		result.append(point)
	return result
