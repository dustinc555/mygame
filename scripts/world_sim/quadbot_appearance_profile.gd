extends "res://scripts/world_sim/population_appearance_profile.gd"

class_name QuadBotAppearanceProfile

const QUADBOT_RACE := preload("res://resources/character_races/quadbot.tres")
const QUADBOT_BODY_ARCHETYPE := preload("res://resources/character_body_archetypes/quadbot.tres")


func create_appearance(_rng: RandomNumberGenerator) -> Resource:
	var appearance = CHARACTER_APPEARANCE_DATA_SCRIPT.new()
	appearance.character_race = QUADBOT_RACE
	appearance.body_archetype = QUADBOT_BODY_ARCHETYPE
	appearance.visual_body_type = CHARACTER_APPEARANCE_DATA_SCRIPT.VISUAL_BODY_TYPE_NONE
	appearance.hair_style = null
	appearance.beard_style = null
	appearance.eyebrow_style = null
	appearance.skin_color_customized = false
	appearance.height_slider = 0.0
	appearance.shoulder_width_slider = 0.0
	appearance.arm_length_slider = 0.0
	appearance.neck_length_slider = 0.0
	return appearance


func apply_to_actor(actor: Node, rng: RandomNumberGenerator, _apply_equipment := true) -> void:
	if actor == null:
		return
	var appearance := create_appearance(rng)
	actor.set("character_race", appearance.character_race)
	actor.set("body_archetype", appearance.body_archetype)
	actor.set("visual_body_type", appearance.visual_body_type)
	actor.set("appearance_data", appearance)
	actor.set("starting_equipment", [])
	if actor.is_inside_tree() and actor.has_method("apply_appearance_data"):
		actor.call("apply_appearance_data", appearance)
