@tool
extends Resource

class_name CharacterAppearanceData

const VISUAL_BODY_TYPE_AUTO := 0
const VISUAL_BODY_TYPE_NONE := 1
const VISUAL_BODY_TYPE_MALE := 2
const VISUAL_BODY_TYPE_FEMALE := 3

@export var character_race: Resource
@export var body_archetype: Resource
@export_enum("Auto:0", "None:1", "Male:2", "Female:3") var visual_body_type := VISUAL_BODY_TYPE_AUTO
@export var hair_style: Resource
@export var beard_style: Resource
@export var eyebrow_style: Resource
@export var hair_color := Color(0.16, 0.11, 0.07, 1.0)
@export var beard_color := Color(0.16, 0.11, 0.07, 1.0)
@export var eyebrow_color := Color(0.13, 0.09, 0.06, 1.0)
@export_range(-1.0, 1.0, 0.01) var height_slider := 0.0
@export_range(-1.0, 1.0, 0.01) var shoulder_width_slider := 0.0
@export_range(-1.0, 1.0, 0.01) var head_height_slider := 0.0


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
	target.height_slider = height_slider
	target.shoulder_width_slider = shoulder_width_slider
	target.head_height_slider = head_height_slider


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
		height_slider = source.height_slider
		shoulder_width_slider = source.shoulder_width_slider
		head_height_slider = source.head_height_slider


func get_body_type_id() -> String:
	match visual_body_type:
		VISUAL_BODY_TYPE_MALE:
			return "male"
		VISUAL_BODY_TYPE_FEMALE:
			return "female"
	return ""


func get_body_pose_offsets(base_offsets: Dictionary = {}) -> Dictionary:
	var offsets := base_offsets.duplicate()
	var height := clampf(height_slider, -1.0, 1.0)
	var shoulders := clampf(shoulder_width_slider, -1.0, 1.0)
	var head := clampf(head_height_slider, -1.0, 1.0)
	_add_offset(offsets, "spine_01", Vector3(0.0, height * 0.018, 0.0))
	_add_offset(offsets, "spine_02", Vector3(0.0, height * 0.026, 0.0))
	_add_offset(offsets, "spine_03", Vector3(0.0, height * 0.032, 0.0))
	_add_offset(offsets, "neck_01", Vector3(0.0, height * 0.02, 0.0))
	_add_offset(offsets, "Head", Vector3(0.0, height * 0.022 + head * 0.018, 0.0))
	_add_offset(offsets, "clavicle_l", Vector3(absf(shoulders) * -0.018 if shoulders < 0.0 else shoulders * -0.024, 0.0, 0.0))
	_add_offset(offsets, "clavicle_r", Vector3(absf(shoulders) * 0.018 if shoulders < 0.0 else shoulders * 0.024, 0.0, 0.0))
	return offsets


func _add_offset(offsets: Dictionary, bone_name: String, offset: Vector3) -> void:
	if offset.length_squared() <= 0.0000001:
		return
	var existing: Vector3 = offsets.get(bone_name, Vector3.ZERO)
	offsets[bone_name] = existing + offset
