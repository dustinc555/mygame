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
@export var grip_socket_profile: Resource
@export_enum("None:1", "Male:2", "Female:3") var visual_body_type := VISUAL_BODY_TYPE_NONE
@export var bone_pose_position_offsets: Dictionary = {}


func get_race_id() -> String:
	if race != null:
		var resource_id := str(race.get("race_id"))
		if not resource_id.is_empty():
			return resource_id
	return race_id
