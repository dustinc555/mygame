extends RefCounted
## Shared rest-space transfer for production humanoids and asset previews.
## Bone offsets remain target-authored; animation deltas follow source motion.

static func capture_source(skeleton: Skeleton3D) -> Dictionary:
	var rests := {}
	for index in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(index)
		rests[skeleton.get_bone_name(index)] = {
			"local": skeleton.get_bone_rest(index),
			"global": skeleton.get_bone_global_rest(index),
			"parent": skeleton.get_bone_global_rest(parent) if parent >= 0 else Transform3D.IDENTITY,
		}
	var pelvis := skeleton.find_bone("pelvis")
	return {"rests": rests, "height": skeleton.get_bone_global_rest(pelvis).origin.y if pelvis >= 0 else 1.0}

static func requires_rest_transfer(source: Skeleton3D, target: Skeleton3D) -> bool:
	if source == null or target == null:
		return false
	for index in target.get_bone_count():
		var source_index := source.find_bone(target.get_bone_name(index))
		if source_index < 0:
			continue
		var a := source.get_bone_rest(source_index).basis.get_rotation_quaternion()
		var b := target.get_bone_rest(index).basis.get_rotation_quaternion()
		if absf(a.dot(b)) < 0.99999:
			return true
	return false

static func retarget(source: Dictionary, target: Node3D, skeleton: Skeleton3D) -> Animation:
	var original: Animation = source.animation
	var animation := Animation.new()
	animation.length = original.length
	animation.loop_mode = original.loop_mode
	animation.step = original.step
	var pelvis := skeleton.find_bone("pelvis")
	var height := skeleton.get_bone_global_rest(pelvis).origin.y if pelvis >= 0 else 1.0
	var motion_scale := height / maxf(absf(source.height), 0.001)
	var path := str(target.get_path_to(skeleton))
	for track in original.get_track_count():
		var type := original.track_get_type(track)
		if type not in [Animation.TYPE_ROTATION_3D, Animation.TYPE_POSITION_3D]: continue
		var bone := str(original.track_get_path(track)).get_slice(":", 1)
		var index := skeleton.find_bone(bone)
		if index < 0 or not source.rests.has(bone): continue
		var rest: Dictionary = source.rests[bone]
		var parent := skeleton.get_bone_parent(index)
		var target_parent := skeleton.get_bone_global_rest(parent) if parent >= 0 else Transform3D.IDENTITY
		var target_rest := skeleton.get_bone_rest(index)
		var target_global := skeleton.get_bone_global_rest(index)
		var parent_correction: Basis = target_parent.basis.inverse() * rest.parent.basis
		var bone_correction: Basis = rest.global.basis.inverse() * target_global.basis
		var output := animation.add_track(type)
		animation.track_set_path(output, NodePath(path + ":" + bone))
		animation.track_set_interpolation_type(output, original.track_get_interpolation_type(track))
		for key in original.track_get_key_count(track):
			var value = original.track_get_key_value(track, key)
			if type == Animation.TYPE_ROTATION_3D:
				value = (parent_correction * Basis(value) * bone_correction).get_rotation_quaternion().normalized()
			else:
				value = target_rest.origin + parent_correction * (value - rest.local.origin) * motion_scale
			animation.track_insert_key(output, original.track_get_key_time(track, key), value, original.track_get_key_transition(track, key))
	return animation
