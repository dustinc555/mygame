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
@export var downed_preroll_animation_names: PackedStringArray = PackedStringArray(["Death01", "Death02"])
@export var downed_preroll_min_ratio := 0.5
@export var downed_preroll_max_ratio := 1.0
@export var collision_layer := 1
@export var collision_mask := 1
@export var default_mass := 1.0
@export var pelvis_mass := 3.2
@export var torso_mass := 2.6
@export var head_mass := 1.0
@export var arm_mass := 0.8
@export var leg_mass := 1.5
@export var default_radius := 0.065
@export var torso_radius := 0.14
@export var pelvis_radius := 0.15
@export var head_radius := 0.13
@export var hand_radius := 0.055
@export var foot_radius := 0.065
@export var linear_damp := 0.24
@export var angular_damp := 1.55
@export var friction := 0.32
@export var bounce := 0.0
@export var gravity_scale := 1.0
@export var impulse_scale := 2.4
@export var get_up_fallback_seconds := 1.15
@export var disable_internal_collisions := true
@export var cone_swing_span_degrees := 70.0
@export var cone_twist_span_degrees := 50.0
@export var spine_swing_span_degrees := 35.0
@export var spine_twist_span_degrees := 25.0
@export var shoulder_swing_span_degrees := 110.0
@export var shoulder_twist_span_degrees := 70.0
@export var hip_swing_span_degrees := 85.0
@export var hip_twist_span_degrees := 55.0
@export var head_swing_span_degrees := 45.0
@export var head_twist_span_degrees := 35.0
@export var hand_swing_span_degrees := 60.0
@export var hand_twist_span_degrees := 40.0
@export var foot_swing_span_degrees := 50.0
@export var foot_twist_span_degrees := 35.0
@export var cone_bias := 0.08
@export var cone_softness := 0.88
@export var cone_relaxation := 0.65
@export var hinge_limit_lower_degrees := -20.0
@export var hinge_limit_upper_degrees := 145.0
@export var hinge_bias := 0.08
@export var hinge_softness := 0.9
@export var hinge_relaxation := 0.65


func get_all_animation_names() -> Array[String]:
	var result: Array[String] = []
	for animation_name in get_up_animation_names:
		var resolved_name := String(animation_name)
		if not resolved_name.is_empty() and not result.has(resolved_name):
			result.append(resolved_name)
	for animation_name in downed_preroll_animation_names:
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


func choose_downed_preroll_animation(animation_player: AnimationPlayer, rng: RandomNumberGenerator) -> String:
	if animation_player == null:
		return ""
	var available: Array[String] = []
	for animation_name in downed_preroll_animation_names:
		var resolved_name := String(animation_name)
		if animation_player.has_animation(resolved_name):
			available.append(resolved_name)
	if available.is_empty():
		return ""
	return available[rng.randi_range(0, available.size() - 1)]


func choose_downed_preroll_duration(animation_length: float, rng: RandomNumberGenerator) -> float:
	if animation_length <= 0.0:
		return 0.0
	var minimum_ratio := clampf(downed_preroll_min_ratio, 0.0, 1.0)
	var maximum_ratio := clampf(downed_preroll_max_ratio, minimum_ratio, 1.0)
	return animation_length * rng.randf_range(minimum_ratio, maximum_ratio)


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


func get_bone_cone_swing_span_degrees(bone_name: String) -> float:
	if bone_name.begins_with("spine"):
		return spine_swing_span_degrees
	if bone_name == "Head":
		return head_swing_span_degrees
	if bone_name.begins_with("upperarm"):
		return shoulder_swing_span_degrees
	if bone_name.begins_with("thigh"):
		return hip_swing_span_degrees
	if bone_name.begins_with("hand"):
		return hand_swing_span_degrees
	if bone_name.begins_with("foot"):
		return foot_swing_span_degrees
	return cone_swing_span_degrees


func get_bone_cone_twist_span_degrees(bone_name: String) -> float:
	if bone_name.begins_with("spine"):
		return spine_twist_span_degrees
	if bone_name == "Head":
		return head_twist_span_degrees
	if bone_name.begins_with("upperarm"):
		return shoulder_twist_span_degrees
	if bone_name.begins_with("thigh"):
		return hip_twist_span_degrees
	if bone_name.begins_with("hand"):
		return hand_twist_span_degrees
	if bone_name.begins_with("foot"):
		return foot_twist_span_degrees
	return cone_twist_span_degrees


func should_use_box_shape(bone_name: String) -> bool:
	return bone_name == root_bone_name or bone_name.begins_with("spine") or bone_name == "Head"


func should_create_collision_shape(bone_name: String) -> bool:
	return not bone_name.is_empty()
