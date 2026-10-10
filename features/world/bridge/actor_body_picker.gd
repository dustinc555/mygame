extends RefCounted

## Click-only geometry for posed humanoids. Movement capsules are deliberately
## not selection shapes: seated/carried visuals can move away from their roots.
## Reuse the authored anatomical bone names/radii, without creating physical
## bones, reading mesh vertices back from the GPU, or updating anything per frame.

static func pick(actors: Array[Node], camera: Camera3D, ray_from: Vector3, ray_to: Vector3) -> Dictionary:
	var excluded: Array[RID] = []
	var nearest: Dictionary = {}
	var nearest_distance := ray_from.distance_squared_to(ray_to)
	for node in actors:
		var actor := node as WorldActor
		if actor == null or not actor.is_inside_tree() or actor.get_world_3d() != camera.get_world_3d():
			continue
		var body := actor.get_body_projection() as HumanoidBodyProjection
		if body == null:
			continue
		var skeleton := body.get_skeleton()
		if skeleton == null:
			continue
		excluded.append(actor.get_rid())
		if not body.is_visible_in_tree() or not skeleton.is_visible_in_tree():
			continue
		# Conservative world-space broad phase. The authored body envelope covers
		# limb motion; the narrow phase below, never this envelope, grants a hit.
		var body_mesh := actor.get_node_or_null("BodyMesh") as MeshInstance3D
		if body_mesh == null or body_mesh.mesh == null:
			continue
		var reach := body_mesh.get_aabb().size.length() * body_mesh.global_basis.get_scale().abs().length()
		var anchor := body.global_position
		if body.is_ragdoll_active():
			var ragdoll_anchor: Variant = body.get_ragdoll_anchor_position()
			if ragdoll_anchor is Vector3:
				anchor = ragdoll_anchor
		if Geometry3D.get_closest_point_to_segment(anchor, ray_from, ray_to).distance_squared_to(anchor) > reach * reach:
			continue
		var profile = body.get_ragdoll_profile()
		for bone_name in profile.physical_bone_names:
			var index := skeleton.find_bone(bone_name)
			if index < 0:
				continue
			var pose := skeleton.global_transform * skeleton.get_bone_global_pose(index)
			var start := pose.origin
			var radius: float = profile.get_bone_radius(bone_name)
			# Follow the longest immediate child (neck, elbow, knee, toe, etc.).
			# Terminal bones use a short cap along their authored length axis.
			var end := start + pose.basis.y.normalized() * radius
			var longest := 0.0
			for child in skeleton.get_bone_children(index):
				var child_position := skeleton.global_transform * skeleton.get_bone_global_pose(child).origin
				var length_squared := start.distance_squared_to(child_position)
				if length_squared > longest:
					longest = length_squared
					end = child_position
			var hit := intersect_capsule(ray_from, ray_to, start, end, radius)
			if hit.is_empty():
				continue
			var point := hit[0]
			var distance := ray_from.distance_squared_to(point)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest = {"collider": actor, "position": point}
	return {"hit": nearest, "exclude": excluded}


static func intersect_capsule(ray_from: Vector3, ray_to: Vector3, start: Vector3, end: Vector3, radius: float) -> PackedVector3Array:
	var nearest := PackedVector3Array()
	var distance := INF
	for center in [start, end]:
		var cap := Geometry3D.segment_intersects_sphere(ray_from, ray_to, center, radius)
		if not cap.is_empty() and ray_from.distance_squared_to(cap[0]) < distance:
			distance = ray_from.distance_squared_to(cap[0])
			nearest = cap
	var axis := end - start
	if axis.length_squared() < 0.000001:
		return nearest
	var up := Vector3.RIGHT if absf(axis.normalized().dot(Vector3.UP)) > 0.99 else Vector3.UP
	# Geometry3D's cylinder is centered at the origin along local Z.
	var transform := Transform3D(Basis.looking_at(axis, up), (start + end) * 0.5)
	var inverse := transform.affine_inverse()
	var side := Geometry3D.segment_intersects_cylinder(inverse * ray_from, inverse * ray_to, axis.length(), radius)
	if not side.is_empty():
		var point := transform * side[0]
		if ray_from.distance_squared_to(point) < distance:
			nearest = PackedVector3Array([point, transform.basis * side[1]])
	return nearest
