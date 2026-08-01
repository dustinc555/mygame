@tool
extends Resource

class_name HeadAttachmentStyleDefinition

enum Slot {
	HAIR,
	BEARD,
	EYEBROWS,
}

@export var style_id := ""
@export var display_name := "Style"
@export var slot: Slot = Slot.HAIR
@export var visual_scene: PackedScene
@export var teen_visual_scene: PackedScene
@export var colorize := true
@export var default_color := Color(0.16, 0.11, 0.07, 1.0)
@export var allowed_body_types: PackedStringArray = PackedStringArray()


func get_slot_id() -> String:
	match slot:
		Slot.BEARD:
			return "beard"
		Slot.EYEBROWS:
			return "eyebrows"
		_:
			return "hair"


func supports_body_type(body_type_id: String) -> bool:
	if allowed_body_types.is_empty() or body_type_id.is_empty():
		return true
	return allowed_body_types.has(body_type_id)


func get_visual_scene_for_age(age_years: int) -> PackedScene:
	if CharacterVisualRules.is_teen_age(age_years) and teen_visual_scene != null:
		return teen_visual_scene
	return visual_scene
