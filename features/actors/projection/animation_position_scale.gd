class_name AnimationPositionScale
extends RefCounted

## Compensates transplanted animation position tracks for rig proportion
## differences. Vendor clips (UAL packs) author absolute pelvis/root heights
## for the vendor mannequin; playing them verbatim on a rig with different leg
## proportions plants the pelvis at the wrong height and the feet sink into or
## float off the floor. This is the same math Godot's Skeleton3D.motion_scale
## implements, applied at copy time because our imports all carry
## motion_scale = 1.0. Baseline: UAL1 "Idle" native lowest bone Y = 0.0000;
## uncompensated transplant measured -0.0318 (feet 3.2 cm underground).


## Global rest-pose height of the hips bone: composed rest transforms from the
## hips up the parent chain, in skeleton-local space (matches the space
## animation position tracks are applied in, so node scaling is irrelevant).
static func hips_height(skeleton: Skeleton3D) -> float:
	if skeleton == null:
		return 0.0
	var bone_index := skeleton.find_bone("pelvis")
	if bone_index == -1:
		bone_index = skeleton.find_bone("Hips")
	if bone_index == -1:
		return 0.0
	var rest_transform := skeleton.get_bone_rest(bone_index)
	var parent_index := skeleton.get_bone_parent(bone_index)
	while parent_index != -1:
		rest_transform = skeleton.get_bone_rest(parent_index) * rest_transform
		parent_index = skeleton.get_bone_parent(parent_index)
	return rest_transform.origin.y


static func ratio_between(source_skeleton: Skeleton3D, target_skeleton: Skeleton3D) -> float:
	var source_height := hips_height(source_skeleton)
	var target_height := hips_height(target_skeleton)
	if source_height <= 0.001 or target_height <= 0.001:
		return 1.0
	return target_height / source_height


## Scales every position-track key in place. The animation must be a copy the
## caller owns (never the vendor source resource).
static func scale_position_tracks(animation: Animation, ratio: float) -> void:
	if animation == null or absf(ratio - 1.0) < 0.0005:
		return
	for track_index in range(animation.get_track_count()):
		if animation.track_get_type(track_index) != Animation.TYPE_POSITION_3D:
			continue
		for key_index in range(animation.track_get_key_count(track_index)):
			var value := animation.track_get_key_value(track_index, key_index) as Vector3
			animation.track_set_key_value(track_index, key_index, value * ratio)


static func scale_animation_names(animation_library: AnimationLibrary, animation_names: Array, ratio: float) -> void:
	if animation_library == null or absf(ratio - 1.0) < 0.0005:
		return
	for animation_name in animation_names:
		scale_position_tracks(animation_library.get_animation(animation_name), ratio)
