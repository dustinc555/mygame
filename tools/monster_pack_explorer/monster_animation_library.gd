extends RefCounted
## Rest-aware UAL transfer for differently proportioned Bestiary humanoid rigs.
## Keeps target bone offsets; transfers motion in the shared skeleton space.
const PACKS := [
	{"label": "UAL1 Pro", "path": "res://assets/vendor/quaternius/universal_animation_library_1_pro/UAL1_Pro.glb"},
	{"label": "UAL2", "path": "res://assets/vendor/quaternius/universal_animation_library_2/UAL2.glb"},
]
var sources: Array[Dictionary] = []

func _init() -> void:
	for pack in PACKS:
		var root: Node = load(pack.path).instantiate()
		var skeleton := AnimationRetargetLib.find_skeleton(root)
		var player := AnimationRetargetLib.find_animation_player(root)
		if skeleton == null or player == null:
			root.free()
			continue
		var rests := {}
		for index in skeleton.get_bone_count():
			var parent := skeleton.get_bone_parent(index)
			rests[skeleton.get_bone_name(index)] = {
				"local": skeleton.get_bone_rest(index),
				"global": skeleton.get_bone_global_rest(index),
				"parent": skeleton.get_bone_global_rest(parent) if parent >= 0 else Transform3D.IDENTITY,
			}
		var pelvis := skeleton.find_bone("pelvis")
		var height := skeleton.get_bone_global_rest(pelvis).origin.y if pelvis >= 0 else 1.0
		for name in player.get_animation_list():
			if name in ["RESET", "A_TPose"]: continue
			sources.append({"name": str(name), "pack": pack.label, "animation": player.get_animation(name), "rests": rests, "height": height})
		root.free()

func attach(target: Node3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var skeleton := AnimationRetargetLib.find_skeleton(target)
	if skeleton == null: return result
	var player := AnimationPlayer.new()
	player.name = "UniversalAnimationPlayer"
	target.add_child(player)
	player.root_node = NodePath("..")
	var library := AnimationLibrary.new()
	player.add_animation_library("", library)
	for source in sources:
		var animation := retarget(source, target, skeleton)
		if animation.get_track_count() == 0: continue
		var name := "%s · %s" % [source.pack, source.name]
		library.add_animation(name, animation)
		result.append({"name": name, "player": player})
	return result

func retarget(source: Dictionary, target: Node3D, skeleton: Skeleton3D) -> Animation:
	var original: Animation = source.animation
	var animation := Animation.new()
	animation.length = original.length
	animation.loop_mode = Animation.LOOP_LINEAR
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
