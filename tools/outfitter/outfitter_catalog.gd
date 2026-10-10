extends RefCounted
## Discovery only: saved definitions remain the sole body/item/grip authority.
const RACES := preload("res://features/world_sim/resources/population_appearance_profile.gd")
const PROFILES := "res://features/world_sim/resources/population_appearance_profiles"
const ITEMS := "res://features/inventory/resources/items"
# Representative inspection contexts; production rules resolve the actual scene.
const BUILD_CONTEXTS := {
	"regular": {"age_years": CharacterVisualRules.DEFAULT_ADULT_AGE, "toughness_level": SkillRules.DEFAULT_LEVEL},
	"heroic": {"age_years": CharacterVisualRules.DEFAULT_ADULT_AGE, "toughness_level": CharacterVisualRules.HEROIC_TOUGHNESS_LEVEL},
	"teen": {"age_years": 15, "toughness_level": SkillRules.DEFAULT_LEVEL},
}
var races: Array[Resource] = []
var items: Array[ItemDefinition] = []
var profiles: Array[Resource] = []

func _init() -> void:
	races = RACES._get_available_races()
	for path in resource_paths(PROFILES):
		var profile := load(path) as PopulationAppearanceProfile
		if profile != null: profiles.append(profile)
	for path in resource_paths(ITEMS):
		var item := load(path) as ItemDefinition
		if item != null and item.is_equippable(): items.append(item)
	items.sort_custom(func(a, b): return a.display_name.naturalnocasecmp_to(b.display_name) < 0)

static func resource_paths(directory: String) -> Array[String]:
	var result: Array[String] = []
	for file in DirAccess.get_files_at(directory):
		if file.ends_with(".tres"): result.append(directory.path_join(file))
	for child in DirAccess.get_directories_at(directory):
		result.append_array(resource_paths(directory.path_join(child)))
	result.sort()
	return result

func bodies(race: Resource) -> Array[Resource]:
	var result: Array[Resource] = []
	for body in [race.default_male_archetype, race.default_female_archetype]:
		if body != null and not result.has(body): result.append(body)
	return result

func actor_script_for(race: Resource, body: Resource) -> Script:
	# Specialized production realizers (e.g. robots, undead) take precedence.
	for profile in profiles:
		if profile.allowed_races.has(race): return profile.actor_script
	# A registered humanoid body without a specialized population profile uses
	# the same general humanoid actuator as ordinary population realizers.
	if body.visual_body_type in [CharacterAppearanceData.VISUAL_BODY_TYPE_MALE, CharacterAppearanceData.VISUAL_BODY_TYPE_FEMALE]:
		return load("res://features/actors/projection/humanoid/humanoid_character.gd")
	return null

func builds(body: Resource) -> Array[String]:
	var result: Array[String] = []
	for build in BUILD_CONTEXTS:
		if build == "regular" or (body != null and body.get(build + "_visual_scene") != null): result.append(build)
	return result

func create_actor(race: Resource, body: Resource, build: String = "regular") -> WorldActor:
	var script := actor_script_for(race, body)
	if script == null: return null
	var actor := script.new() as WorldActor
	var appearance := CharacterAppearanceData.new()
	appearance.character_race = race
	appearance.body_archetype = body
	appearance.visual_body_type = body.visual_body_type
	var context: Dictionary = BUILD_CONTEXTS[build if builds(body).has(build) else "regular"]
	appearance.visual_age_years = context.age_years
	appearance.visual_toughness_level = context.toughness_level
	actor.set("character_race", race)
	actor.set("body_archetype", body)
	actor.set("visual_body_type", body.visual_body_type)
	actor.set("appearance_data", appearance)
	actor.set("show_nameplate", false)
	actor.starting_equipment.clear()
	# Reuse the production script-created-actor scaffold, not copied dimensions.
	var realizer := PopulationCharacterRealizer.new()
	realizer._ensure_projection_bootstrap(actor)
	realizer.free()
	return actor
