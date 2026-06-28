extends RefCounted
class_name CarryPoseSolver

## Stateless projection-layer solver for the "one actor carrying another" pose.
##
## Ported verbatim from CarryCapability (pre-split). This is PRESENTATION work:
## it reads the carrier's skeleton bones and visual bounds to anchor the carried
## body at the carrier's shoulder. That is projection-layer logic, not durable
## relationship state, so it does not belong in a bridge capability.
##
## Names only engine + projection + resource types (BodyProjection, Node3D,
## Skeleton3D, MeshInstance3D, AABB, HumanoidCarryPoseProfile). It never
## references WorldActor, which is what keeps CarryCapability off the actor
## dependency cycle: the pose math used to force `carry -> WorldActor`.
##
## The CARRIER drives this each physics frame (HumanoidCharacter._physics_process)
## because the carrier owns the skeleton the pose anchors to. Non-humanoid
## carriers position nothing: base WorldActor.get_body_projection() is a null
## stub, so the solver is never called for them. That is an intentional bound --
## no gameplay carrier is non-humanoid.


## Returns the global transform to assign to the carried body.
##
## Two-sided anchor: the carried body's anchor bone (profile.carried_anchor_bones,
## pelvis = the fold apex of the frozen carry pose) is pinned at the carrier's
## shoulder anchor + profile.carrier_anchor_local_offset. Solving through the
## bone each frame is REQUIRED for correctness, not style: the frozen pose's
## bone locals shift by the visual-root correction depending on the victim's
## prior state (ragdoll-downed vs standing), so any static origin offset is
## right for one pickup path and ~0.7m wrong for the other.
##
## Tuning: rotation_degrees + carried_pose_time_ratio come from the calibrator
## (tools/humanoid_carry_pose_calibrator.tscn); position fine-tuning is
## carrier_anchor_local_offset. carried_local_position is only the fallback
## when the carried body has no skeleton yet.
static func solve_carried_transform(carrier_body: BodyProjection, carrier_node: Node3D, profile: HumanoidCarryPoseProfile, carried_body: BodyProjection = null, carried_node: Node3D = null) -> Transform3D:
	var shoulder_origin := _shoulder_origin_transform(carrier_body, carrier_node, profile)
	var pose_basis := shoulder_origin.basis * _pose_local_basis(profile)
	var anchor_position := shoulder_origin.origin + shoulder_origin.basis * (profile.carrier_anchor_local_offset if profile != null else Vector3.ZERO)
	var carried_anchor_local: Variant = _carried_anchor_local_position(carried_body, carried_node, profile) if profile != null and profile.pin_carried_anchor else null
	if carried_anchor_local is Vector3:
		return Transform3D(pose_basis, anchor_position - pose_basis * (carried_anchor_local as Vector3))
	var carried_local_position := profile.carried_local_position if profile != null else Vector3.ZERO
	return shoulder_origin * Transform3D(_pose_local_basis(profile), carried_local_position)


## The carried body's anchor bone position in the carried node's LOCAL space
## under its CURRENT pose (the frozen carry clip must already be applied).
static func _carried_anchor_local_position(carried_body: BodyProjection, carried_node: Node3D, profile: HumanoidCarryPoseProfile) -> Variant:
	if carried_body == null or carried_node == null or not is_instance_valid(carried_node):
		return null
	var bone_names := profile.carried_anchor_bones if profile != null and not profile.carried_anchor_bones.is_empty() else PackedStringArray(["pelvis"])
	var bone_global: Variant = _bone_global_position(carried_body, bone_names, Vector3.ZERO, "carried")
	if bone_global is Vector3:
		return carried_node.global_transform.affine_inverse() * (bone_global as Vector3)
	return null


static func _pose_local_basis(profile: HumanoidCarryPoseProfile) -> Basis:
	var carry_rotation_degrees := profile.rotation_degrees if profile != null else Vector3.ZERO
	return Basis.from_euler(Vector3(
		deg_to_rad(carry_rotation_degrees.x),
		deg_to_rad(carry_rotation_degrees.y),
		deg_to_rad(carry_rotation_degrees.z)
	))


static func _shoulder_origin_transform(carrier_body: BodyProjection, carrier_node: Node3D, profile: HumanoidCarryPoseProfile) -> Transform3D:
	var carrier_transform := carrier_node.global_transform
	var origin_position: Variant = _bone_global_position(carrier_body, _carrier_anchor_bone_names(profile), Vector3.ZERO, "carrier")
	var origin: Vector3 = origin_position if origin_position is Vector3 else carrier_transform * _fallback_local_anchor(carrier_body, carrier_node, true)
	return Transform3D(carrier_transform.basis.orthonormalized(), origin)


static func _bone_global_position(carrier_body: BodyProjection, bone_names: PackedStringArray, bone_local_offset: Vector3, anchor_role: String) -> Variant:
	var character_skeleton := carrier_body.get_skeleton() if carrier_body != null else null
	if character_skeleton == null or not is_instance_valid(character_skeleton):
		return null
	character_skeleton.force_update_all_bone_transforms()
	var bone_index := _find_anchor_bone_index(character_skeleton, bone_names, anchor_role)
	if bone_index < 0:
		return null
	var bone_pose := character_skeleton.get_bone_global_pose(bone_index)
	return character_skeleton.global_transform * (bone_pose * bone_local_offset)


static func _find_anchor_bone_index(skeleton: Skeleton3D, bone_names: PackedStringArray, anchor_role: String) -> int:
	for bone_name in bone_names:
		var exact_index := skeleton.find_bone(str(bone_name))
		if exact_index >= 0:
			return exact_index
	var semantic_index := _find_semantic_anchor_bone_index(skeleton, anchor_role)
	if semantic_index >= 0:
		return semantic_index
	for bone_index in range(skeleton.get_bone_count()):
		return bone_index
	return -1


static func _find_semantic_anchor_bone_index(skeleton: Skeleton3D, anchor_role: String) -> int:
	if anchor_role == "carrier":
		var shoulder_index := _find_bone_index_by_keyword_groups(skeleton, [
			["upperarm", "r"],
			["right", "upperarm"],
			["clavicle", "r"],
			["right", "clavicle"],
			["shoulder", "r"],
			["right", "shoulder"],
		])
		if shoulder_index >= 0:
			return shoulder_index
		return _find_highest_spine_bone_index(skeleton)
	return _find_bone_index_by_keyword_groups(skeleton, [
		["spine02"],
		["spine2"],
		["spine", "02"],
		["spine", "2"],
		["stomach"],
		["abdomen"],
		["torso"],
		["chest"],
		["spine03"],
		["spine3"],
		["pelvis"],
		["hips"],
	])


static func _find_bone_index_by_keyword_groups(skeleton: Skeleton3D, keyword_groups: Array) -> int:
	for keyword_group in keyword_groups:
		for bone_index in range(skeleton.get_bone_count()):
			var normalized_name := _normalize_bone_name(skeleton.get_bone_name(bone_index))
			var matches := true
			for keyword in keyword_group:
				if not normalized_name.contains(_normalize_bone_name(str(keyword))):
					matches = false
					break
			if matches:
				return bone_index
	return -1


static func _find_highest_spine_bone_index(skeleton: Skeleton3D) -> int:
	var best_index := -1
	var best_score := -1
	for bone_index in range(skeleton.get_bone_count()):
		var normalized_name := _normalize_bone_name(skeleton.get_bone_name(bone_index))
		if not normalized_name.contains("spine") and not normalized_name.contains("chest"):
			continue
		var score := 0
		for character in normalized_name:
			if character.is_valid_int():
				score = score * 10 + int(character)
		if score >= best_score:
			best_score = score
			best_index = bone_index
	return best_index


static func _normalize_bone_name(bone_name: String) -> String:
	return bone_name.to_lower().replace("_", "").replace("-", "").replace(" ", "").replace(".", "").replace(":", "")


static func _fallback_local_anchor(carrier_body: BodyProjection, carrier_node: Node3D, is_carrier_anchor: bool) -> Vector3:
	if carrier_body != null and is_instance_valid(carrier_body):
		var visual_bounds := carrier_body.get_visual_local_bounds()
		if visual_bounds.size.y > 0.001:
			return _anchor_from_bounds(visual_bounds, is_carrier_anchor)
	var body_mesh := carrier_node.get_node_or_null("BodyMesh") as MeshInstance3D if carrier_node != null else null
	if body_mesh != null and body_mesh.mesh != null:
		var bounds := _calculate_local_mesh_bounds(body_mesh)
		if bounds.size.y > 0.001:
			return _anchor_from_bounds(bounds, is_carrier_anchor)
	return Vector3(0.24, 1.55, 0.08) if is_carrier_anchor else Vector3.ZERO


static func _anchor_from_bounds(bounds: AABB, is_carrier_anchor: bool) -> Vector3:
	var height_ratio := 0.78 if is_carrier_anchor else 0.56
	var side_offset := bounds.size.x * 0.25 if is_carrier_anchor else 0.0
	return Vector3(bounds.position.x + bounds.size.x * 0.5 + side_offset, bounds.position.y + bounds.size.y * height_ratio, bounds.position.z + bounds.size.z * 0.5)


static func _calculate_local_mesh_bounds(root: Node) -> AABB:
	var result := {
		"has_bounds": false,
		"bounds": AABB(),
	}
	_accumulate_local_mesh_bounds(root, Transform3D.IDENTITY, result)
	return result["bounds"]


static func _accumulate_local_mesh_bounds(node: Node, parent_transform: Transform3D, result: Dictionary) -> void:
	var local_transform := parent_transform
	if node is Node3D:
		local_transform = parent_transform * (node as Node3D).transform

	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_bounds := _transform_aabb((node as MeshInstance3D).mesh.get_aabb(), local_transform)
		if result["has_bounds"]:
			result["bounds"] = (result["bounds"] as AABB).merge(mesh_bounds)
		else:
			result["bounds"] = mesh_bounds
			result["has_bounds"] = true

	for child in node.get_children():
		_accumulate_local_mesh_bounds(child, local_transform, result)


static func _transform_aabb(bounds: AABB, bounds_transform: Transform3D) -> AABB:
	var first := true
	var transformed_bounds := AABB()
	for x in [bounds.position.x, bounds.position.x + bounds.size.x]:
		for y in [bounds.position.y, bounds.position.y + bounds.size.y]:
			for z in [bounds.position.z, bounds.position.z + bounds.size.z]:
				var point := bounds_transform * Vector3(x, y, z)
				if first:
					transformed_bounds = AABB(point, Vector3.ZERO)
					first = false
				else:
					transformed_bounds = transformed_bounds.expand(point)
	return transformed_bounds


static func _carrier_anchor_bone_names(profile: HumanoidCarryPoseProfile) -> PackedStringArray:
	return profile.carrier_anchor_bones if profile != null and not profile.carrier_anchor_bones.is_empty() else PackedStringArray(["upperarm_r", "clavicle_r", "spine_03"])
