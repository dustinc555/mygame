@tool
extends Resource

class_name CharacterAppearanceData

const VISUAL_BODY_TYPE_AUTO := 0
const VISUAL_BODY_TYPE_NONE := 1
const VISUAL_BODY_TYPE_MALE := 2
const VISUAL_BODY_TYPE_FEMALE := 3
const DEFAULT_SKIN_COLOR := Color(0.58, 0.38, 0.27, 1.0)

@export var character_race: Resource
@export var body_archetype: Resource
@export_enum("Auto:0", "None:1", "Male:2", "Female:3") var visual_body_type := VISUAL_BODY_TYPE_AUTO
@export var hair_style: Resource
@export var beard_style: Resource
@export var eyebrow_style: Resource
@export var hair_color := Color(0.16, 0.11, 0.07, 1.0)
@export var beard_color := Color(0.16, 0.11, 0.07, 1.0)
@export var eyebrow_color := Color(0.13, 0.09, 0.06, 1.0)
@export var skin_color_customized := false
@export var skin_color := DEFAULT_SKIN_COLOR
@export_range(-1.0, 1.0, 0.01) var height_slider := 0.0
@export_range(-1.0, 1.0, 0.01) var shoulder_width_slider := 0.0
@export_range(-1.0, 1.0, 0.01) var arm_length_slider := 0.0
@export_range(-1.0, 1.0, 0.01) var neck_length_slider := 0.0

# Transient presentation context. Durable age and Toughness remain owned by the
# population record and skill state, respectively.
var visual_age_years := CharacterVisualRules.DEFAULT_ADULT_AGE
var visual_toughness_level := 1


func make_copy():
	var result = get_script().new()
	copy_to(result)
	return result


func copy_to(target) -> void:
	if target == null:
		return
	target.character_race = character_race
	target.body_archetype = body_archetype
	target.visual_body_type = visual_body_type
	target.hair_style = hair_style
	target.beard_style = beard_style
	target.eyebrow_style = eyebrow_style
	target.hair_color = hair_color
	target.beard_color = beard_color
	target.eyebrow_color = eyebrow_color
	target.skin_color_customized = skin_color_customized
	target.skin_color = skin_color
	target.height_slider = height_slider
	target.shoulder_width_slider = shoulder_width_slider
	target.arm_length_slider = arm_length_slider
	target.neck_length_slider = neck_length_slider
	target.visual_age_years = visual_age_years
	target.visual_toughness_level = visual_toughness_level


func set_from_character(character) -> void:
	if character == null:
		return
	character_race = character.character_race
	body_archetype = character.body_archetype
	visual_body_type = character.visual_body_type
	var source = character.get("appearance_data")
	if source != null:
		hair_style = source.hair_style
		beard_style = source.beard_style
		eyebrow_style = source.eyebrow_style
		hair_color = source.hair_color
		beard_color = source.beard_color
		eyebrow_color = source.eyebrow_color
		skin_color_customized = source.skin_color_customized
		skin_color = source.skin_color
		height_slider = source.height_slider
		shoulder_width_slider = source.shoulder_width_slider
		arm_length_slider = source.arm_length_slider
		neck_length_slider = source.neck_length_slider
		visual_age_years = source.visual_age_years
		visual_toughness_level = source.visual_toughness_level


func get_body_type_id() -> String:
	match visual_body_type:
		VISUAL_BODY_TYPE_MALE:
			return "male"
		VISUAL_BODY_TYPE_FEMALE:
			return "female"
	return ""


func has_custom_skin_color() -> bool:
	return skin_color_customized


func get_body_pose_offsets(base_offsets: Dictionary = {}) -> Dictionary:
	var offsets := base_offsets.duplicate()
	var height := clampf(height_slider, -1.0, 1.0)
	var shoulders := clampf(shoulder_width_slider, -1.0, 1.0)
	var arms := clampf(arm_length_slider, -1.0, 1.0)
	var neck := clampf(neck_length_slider, -1.0, 1.0)
	# Height is spread mostly into the legs, with smaller torso changes to avoid long-neck proportions.
	var thigh_length := height * 0.024
	var calf_length := height * 0.024
	var lower_torso_length := height * 0.010
	var middle_torso_length := height * 0.013
	var upper_torso_length := height * 0.016
	_add_symmetric_y_offset(offsets, "calf", thigh_length)
	_add_symmetric_y_offset(offsets, "foot", calf_length)
	_add_offset(offsets, "spine_01", Vector3(0.0, lower_torso_length, 0.0))
	_add_offset(offsets, "spine_02", Vector3(0.0, middle_torso_length, 0.0))
	_add_offset(offsets, "spine_03", Vector3(0.0, upper_torso_length, 0.0))
	_add_offset(offsets, "clavicle_l", Vector3(shoulders * 0.020, 0.0, 0.0))
	_add_offset(offsets, "clavicle_r", Vector3(shoulders * -0.020, 0.0, 0.0))
	_add_symmetric_y_offset(offsets, "lowerarm", arms * 0.018)
	_add_symmetric_y_offset(offsets, "hand", arms * 0.018)
	_add_offset(offsets, "Head", Vector3(0.0, neck * 0.018, 0.0))
	return offsets


func get_foot_anchor_correction_y() -> float:
	return clampf(height_slider, -1.0, 1.0) * (0.024 + 0.024)


func _add_offset(offsets: Dictionary, bone_name: String, offset: Vector3) -> void:
	if offset.length_squared() <= 0.0000001:
		return
	var existing: Vector3 = offsets.get(bone_name, Vector3.ZERO)
	offsets[bone_name] = existing + offset


func _add_symmetric_y_offset(offsets: Dictionary, bone_prefix: String, amount: float) -> void:
	_add_offset(offsets, "%s_l" % bone_prefix, Vector3(0.0, amount, 0.0))
	_add_offset(offsets, "%s_r" % bone_prefix, Vector3(0.0, amount, 0.0))
