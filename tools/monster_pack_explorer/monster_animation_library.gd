extends RefCounted
## Rest-aware UAL transfer for differently proportioned Bestiary humanoid rigs.
## Keeps target bone offsets; transfers motion in the shared skeleton space.
const RETARGET = preload("res://features/actors/projection/humanoid/humanoid_animation_retarget.gd")
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
		var snapshot := RETARGET.capture_source(skeleton)
		for name in player.get_animation_list():
			if name in ["RESET", "A_TPose"]: continue
			sources.append({"name": str(name), "pack": pack.label, "animation": player.get_animation(name), "rests": snapshot.rests, "height": snapshot.height})
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
	var animation := RETARGET.retarget(source, target, skeleton)
	animation.loop_mode = Animation.LOOP_LINEAR
	return animation
