extends Resource

class_name HumanoidRagdollProfile

## Shared humanoid physics tuning. Edit humanoid_ragdoll_profile.tres in the
## Inspector; settings are read when a body's physical skeleton is first built.

const JOINT_TYPE_NONE := 0
const JOINT_TYPE_PIN := 1
const JOINT_TYPE_CONE := 2
const JOINT_TYPE_HINGE := 3
const JOINT_TYPE_6DOF := 5

@export_group("Skeleton")
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
@export_group("Collision and Weight")
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
@export_group("Settling")
@export var linear_damp := 0.24
@export var angular_damp := 1.0
@export var friction := 0.6
@export var bounce := 0.0
@export var gravity_scale := 1.0
@export var impulse_scale := 2.4
@export var get_up_fallback_seconds := 1.15
@export var disable_internal_collisions := true
@export_group("Joint Limits")
@export var cone_swing_span_degrees := 70.0
@export var cone_twist_span_degrees := 50.0
@export var spine_flexion_degrees := 10.0
@export var spine_extension_degrees := 8.0
@export var spine_side_bend_degrees := 12.0
@export var spine_twist_span_degrees := 10.0
@export var shoulder_swing_span_degrees := 110.0
@export var shoulder_twist_span_degrees := 70.0
## Passive collapse travel, not a person's maximum voluntary range: allowing
## both hips and knees to fully fold makes gravity produce a compact W-sit.
@export var hip_flexion_degrees := 20.0
@export var hip_extension_degrees := 20.0
@export var hip_side_bend_degrees := 15.0
@export var hip_twist_span_degrees := 10.0
@export var head_swing_span_degrees := 30.0
@export var head_twist_span_degrees := 30.0
@export var hand_swing_span_degrees := 35.0
@export var hand_twist_span_degrees := 15.0
@export var foot_swing_span_degrees := 25.0
@export var foot_twist_span_degrees := 10.0
## Maximum flexion from the authored rest pose. Godot's hinge sign is opposite
## the rig's bone-local X flexion, so native limits are negated below.
@export_range(30.0, 150.0, 1.0, "suffix:°") var knee_flexion_degrees := 60.0
@export_range(90.0, 150.0, 1.0, "suffix:°") var elbow_flexion_degrees := 140.0
@export_range(0.0, 5.0, 0.5, "suffix:°") var hinge_extension_degrees := 2.0
@export_group("Solver")
## Fraction of spine/hip joint error corrected per physics step. Larger values
## make correction more abrupt when an animation starts outside a joint limit.
@export_range(0.01, 0.8, 0.01) var angular_limit_error_reduction := 0.4
## Spine and hip limits must support the falling body's weight, not just return
## to their allowed angles after the torso has already folded through them.
@export_range(0.1, 1.0, 0.05) var angular_limit_softness := 0.9
@export var cone_bias := 0.08
@export var cone_softness := 0.88
@export var cone_relaxation := 0.65
## Knees/elbows need firmer correction than cone joints to resist hyperextension.
@export var hinge_bias := 0.5
@export var hinge_softness := 0.9
@export var hinge_relaxation := 1.0


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
	if bone_name.begins_with("spine") or bone_name.begins_with("thigh"):
		return JOINT_TYPE_6DOF
	return JOINT_TYPE_CONE


func get_bone_angular_lower_degrees(bone_name: String) -> Vector3:
	if bone_name.begins_with("thigh"):
		return Vector3(-hip_extension_degrees, -hip_twist_span_degrees, -hip_side_bend_degrees)
	return Vector3(-spine_flexion_degrees, -spine_twist_span_degrees, -spine_side_bend_degrees)


func get_bone_angular_upper_degrees(bone_name: String) -> Vector3:
	if bone_name.begins_with("thigh"):
		return Vector3(hip_flexion_degrees, hip_twist_span_degrees, hip_side_bend_degrees)
	return Vector3(spine_extension_degrees, spine_twist_span_degrees, spine_side_bend_degrees)


func get_bone_hinge_limits_degrees(bone_name: String) -> Vector2:
	var flexion := knee_flexion_degrees if bone_name.begins_with("calf") else elbow_flexion_degrees
	return Vector2(-flexion, hinge_extension_degrees)


func get_bone_cone_swing_span_degrees(bone_name: String) -> float:
	if bone_name == "Head":
		return head_swing_span_degrees
	if bone_name.begins_with("upperarm"):
		return shoulder_swing_span_degrees
	if bone_name.begins_with("hand"):
		return hand_swing_span_degrees
	if bone_name.begins_with("foot"):
		return foot_swing_span_degrees
	return cone_swing_span_degrees


func get_bone_cone_twist_span_degrees(bone_name: String) -> float:
	if bone_name == "Head":
		return head_twist_span_degrees
	if bone_name.begins_with("upperarm"):
		return shoulder_twist_span_degrees

	if bone_name.begins_with("hand"):
		return hand_twist_span_degrees
	if bone_name.begins_with("foot"):
		return foot_twist_span_degrees
	return cone_twist_span_degrees


func should_use_box_shape(bone_name: String) -> bool:
	return bone_name == root_bone_name or bone_name.begins_with("spine") or bone_name == "Head"


func should_create_collision_shape(bone_name: String) -> bool:
	return not bone_name.is_empty()
