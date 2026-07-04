class_name AnimationRetargetLib
extends RefCounted

## Shared retargeting for dev tooling (animation showcase + animation browser).
## Copies bone tracks from a vendor clip onto a target skeleton by bone name.
## Single home for this logic — showcase and browser must not drift apart.


static func retarget_animation(source_animation: Animation, target_root: Node3D, target_skeleton: Skeleton3D, loop_animation: bool = true, position_scale: float = 1.0) -> Animation:
	if source_animation == null:
		return null

	var skeleton_path := String(target_root.get_path_to(target_skeleton))
	var retargeted := Animation.new()
	retargeted.length = source_animation.length
	retargeted.loop_mode = Animation.LOOP_LINEAR if loop_animation else Animation.LOOP_NONE

	for source_track_index in range(source_animation.get_track_count()):
		var track_type := source_animation.track_get_type(source_track_index)
		if not _is_supported_track_type(track_type):
			continue

		var source_bone := _get_track_bone_name(source_animation.track_get_path(source_track_index))
		if source_bone.is_empty():
			continue
		var target_bone_index := target_skeleton.find_bone(source_bone)
		if target_bone_index == -1:
			continue

		var target_track_index := retargeted.add_track(track_type)
		retargeted.track_set_path(target_track_index, NodePath("%s:%s" % [skeleton_path, source_bone]))
		retargeted.track_set_interpolation_type(target_track_index, source_animation.track_get_interpolation_type(source_track_index))

		for key_index in range(source_animation.track_get_key_count(source_track_index)):
			var key_value = source_animation.track_get_key_value(source_track_index, key_index)
			retargeted.track_insert_key(
				target_track_index,
				source_animation.track_get_key_time(source_track_index, key_index),
				key_value,
				source_animation.track_get_key_transition(source_track_index, key_index)
			)

	AnimationPositionScale.scale_position_tracks(retargeted, position_scale)
	return retargeted if retargeted.get_track_count() > 0 else null


static func find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var player := find_animation_player(child)
		if player != null:
			return player
	return null


static func find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var skeleton := find_skeleton(child)
		if skeleton != null:
			return skeleton
	return null


static func _is_supported_track_type(track_type: int) -> bool:
	return track_type == Animation.TYPE_POSITION_3D or track_type == Animation.TYPE_ROTATION_3D or track_type == Animation.TYPE_SCALE_3D


static func _get_track_bone_name(track_path: NodePath) -> String:
	var path_text := String(track_path)
	var separator_index := path_text.rfind(":")
	if separator_index == -1 or separator_index >= path_text.length() - 1:
		return ""
	return path_text.substr(separator_index + 1)
