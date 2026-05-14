extends Resource

class_name HumanoidRagdollProfile

const JOINT_TYPE_NONE := 0
const JOINT_TYPE_PIN := 1
const JOINT_TYPE_CONE := 2
const JOINT_TYPE_HINGE := 3

@export var root_bone_name := "pelvis"
@export var physical_bone_names: PackedStringArray = PackedStringArray([
	"pelvis",
	"spine_01",
	"spine_02",
	"spine_03",
	"Head",
	"upperarm_l",
	"lowerarm_l",
	"hand_l",
	"upperarm_r",
	"lowerarm_r",
	"hand_r",
	"thigh_l",
	"calf_l",
	"foot_l",
	"thigh_r",
	"calf_r",
	"foot_r",
])
@export var get_up_animation_names: PackedStringArray = PackedStringArray(["LayToIdle", "Crawl_Exit"])
@export var collision_layer := 1
@export var collision_mask := 1
@export var default_mass := 1.0
@export var pelvis_mass := 5.0
@export var torso_mass := 4.0
@export var head_mass := 1.2
@export var arm_mass := 0.9
@export var leg_mass := 1.8
@export var default_radius := 0.08
@export var torso_radius := 0.17
@export var pelvis_radius := 0.18
@export var head_radius := 0.14
@export var hand_radius := 0.07
@export var foot_radius := 0.08
@export var linear_damp := 0.12
@export var angular_damp := 0.18
@export var friction := 0.82
@export var bounce := 0.0
@export var gravity_scale := 1.0
@export var impulse_scale := 2.4
@export var get_up_fallback_seconds := 1.15


func get_all_animation_names() -> Array[String]:
	var result: Array[String] = []
	for animation_name in get_up_animation_names:
		var resolved_name := String(animation_name)
		if not resolved_name.is_empty() and not result.has(resolved_name):
			result.append(resolved_name)
	return result


func choose_get_up_animation(animation_player: AnimationPlayer, rng: RandomNumberGenerator) -> String:
	if animation_player == null:
		return ""
	var available: Array[String] = []
	for animation_name in get_up_animation_names:
		var resolved_name := String(animation_name)
		if animation_player.has_animation(resolved_name):
			available.append(resolved_name)
	if available.is_empty():
		return ""
	return available[rng.randi_range(0, available.size() - 1)]


func has_physical_bone(bone_name: String) -> bool:
	return physical_bone_names.has(bone_name)


func get_bone_mass(bone_name: String) -> float:
	if bone_name == root_bone_name:
		return pelvis_mass
	if bone_name.begins_with("spine"):
		return torso_mass
	if bone_name == "Head":
		return head_mass
	if bone_name.begins_with("thigh") or bone_name.begins_with("calf") or bone_name.begins_with("foot"):
		return leg_mass
	if bone_name.begins_with("upperarm") or bone_name.begins_with("lowerarm") or bone_name.begins_with("hand"):
		return arm_mass
	return default_mass


func get_bone_radius(bone_name: String) -> float:
	if bone_name == root_bone_name:
		return pelvis_radius
	if bone_name.begins_with("spine"):
		return torso_radius
	if bone_name == "Head":
		return head_radius
	if bone_name.begins_with("hand"):
		return hand_radius
	if bone_name.begins_with("foot"):
		return foot_radius
	return default_radius


func get_bone_joint_type(bone_name: String) -> int:
	if bone_name == root_bone_name:
		return JOINT_TYPE_NONE
	if bone_name.begins_with("lowerarm") or bone_name.begins_with("calf"):
		return JOINT_TYPE_HINGE
	return JOINT_TYPE_CONE


func should_use_box_shape(bone_name: String) -> bool:
	return bone_name == root_bone_name or bone_name.begins_with("spine") or bone_name == "Head"
