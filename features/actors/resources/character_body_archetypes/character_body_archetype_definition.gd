@tool
extends Resource

class_name CharacterBodyArchetypeDefinition

const VISUAL_BODY_TYPE_NONE := 1
const VISUAL_BODY_TYPE_MALE := 2
const VISUAL_BODY_TYPE_FEMALE := 3

@export var archetype_id := ""
@export var display_name := "Body Archetype"
@export var race: Resource
@export var race_id := ""
@export var visual_scene: PackedScene
@export var regular_visual_scene: PackedScene
@export var heroic_visual_scene: PackedScene
@export var teen_visual_scene: PackedScene
@export var grip_socket_profile: Resource
## Transfer UAL motion through this body's rest axes instead of copying human poses.
@export var rest_aware_animation := false
@export_enum("None:1", "Male:2", "Female:3") var visual_body_type := VISUAL_BODY_TYPE_NONE
@export var bone_pose_position_offsets: Dictionary = {}
## One registration per body surface, shared by every source garment.
@export var wardrobe_profiles: Dictionary[String, Resource] = {}


func get_wardrobe_profile(body_scene_path: String = "") -> Resource:
	if body_scene_path.is_empty():
		var scene := regular_visual_scene if regular_visual_scene != null else visual_scene
		if scene == null:
			return null
		body_scene_path = scene.resource_path
	return wardrobe_profiles.get(body_scene_path)


func get_race_id() -> String:
	if race != null:
		var resource_id := str(race.get("race_id"))
		if not resource_id.is_empty():
			return resource_id
	return race_id


func get_visual_scene_for_context(age_years: int, toughness_level: int) -> PackedScene:
	if CharacterVisualRules.is_teen_age(age_years) and teen_visual_scene != null:
		return teen_visual_scene
	if CharacterVisualRules.is_heroic(age_years, toughness_level) and heroic_visual_scene != null:
		return heroic_visual_scene
	if regular_visual_scene != null:
		return regular_visual_scene
	return visual_scene
