@tool
extends RefCounted

class_name CharacterVisualRules

const DEFAULT_ADULT_AGE := 23
const TEEN_MIN_AGE := 13
const TEEN_MAX_AGE := 16
const HEROIC_TOUGHNESS_LEVEL := 60


static func is_teen_age(age_years: int) -> bool:
	return age_years <= TEEN_MAX_AGE


static func is_heroic(age_years: int, toughness_level: int) -> bool:
	return not is_teen_age(age_years) and toughness_level >= HEROIC_TOUGHNESS_LEVEL


static func get_body_visual_scene(body_archetype: Resource, age_years: int, toughness_level: int) -> PackedScene:
	if body_archetype == null:
		return null
	if body_archetype.has_method("get_visual_scene_for_context"):
		return body_archetype.call("get_visual_scene_for_context", age_years, toughness_level) as PackedScene
	return body_archetype.get("visual_scene") as PackedScene


static func get_head_attachment_scene(style: Resource, age_years: int) -> PackedScene:
	if style == null:
		return null
	if style.has_method("get_visual_scene_for_age"):
		return style.call("get_visual_scene_for_age", age_years) as PackedScene
	return style.get("visual_scene") as PackedScene
