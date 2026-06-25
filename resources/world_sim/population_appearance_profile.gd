extends Resource

class_name PopulationAppearanceProfile

const CHARACTER_APPEARANCE_DATA_SCRIPT := preload("res://resources/character_appearance/character_appearance_data.gd")
const SKIN_TEXTURE_BUILDER := preload("res://src/actors/projection/appearance/skin_texture_builder.gd")
const HUMAN_RACE := preload("res://resources/character_races/human.tres")
const CHARACTER_RACE_DIR := "res://resources/character_races"
const VISUAL_BODY_TYPE_MALE := 2
const VISUAL_BODY_TYPE_FEMALE := 3
const BODY_TYPE_MALE_FLAG := 1
const BODY_TYPE_FEMALE_FLAG := 2

const DEFAULT_HAIR_COLORS := [
	Color(0.07, 0.045, 0.028, 1.0),
	Color(0.13, 0.085, 0.045, 1.0),
	Color(0.24, 0.14, 0.07, 1.0),
	Color(0.36, 0.23, 0.12, 1.0),
	Color(0.55, 0.39, 0.20, 1.0),
	Color(0.68, 0.58, 0.42, 1.0),
	Color(0.48, 0.48, 0.45, 1.0),
	Color(0.70, 0.68, 0.62, 1.0),
	Color(0.50, 0.20, 0.08, 1.0),
]

static var _available_races_cache: Array[Resource] = []

@export var profile_id := ""
@export var display_name := "Population Appearance"
@export var allowed_races: Array[Resource] = []
@export_flags("Male", "Female") var allowed_body_type_flags := BODY_TYPE_MALE_FLAG | BODY_TYPE_FEMALE_FLAG
@export var hair_styles: Array[Resource] = []
@export var beard_styles: Array[Resource] = []
@export var hair_color_palette: Array[Color] = []
@export_range(0.0, 1.0, 0.01) var male_beard_chance := 0.45
@export var chest_items: Array[Resource] = []
@export var leg_items: Array[Resource] = []
@export var feet_items: Array[Resource] = []
@export var head_items: Array[Resource] = []
@export_range(0.0, 1.0, 0.01) var head_item_chance := 0.0
@export var height_range := Vector2(-0.30, 0.35)
@export var shoulder_range := Vector2(-0.25, 0.30)
@export var arm_length_range := Vector2(-0.15, 0.18)
@export var neck_length_range := Vector2(-0.10, 0.10)


func create_appearance(rng: RandomNumberGenerator) -> Resource:
	var appearance = CHARACTER_APPEARANCE_DATA_SCRIPT.new()
	var body_type := _pick_body_type(rng)
	var race := _pick_race(rng)
	appearance.character_race = race
	appearance.visual_body_type = body_type
	appearance.body_archetype = _get_body_archetype(race, body_type)
	var hair_color := _pick_color(_get_hair_palette(), rng)
	appearance.hair_style = _pick_style_for_body(hair_styles, body_type, rng)
	appearance.hair_color = hair_color
	appearance.beard_style = null
	appearance.beard_color = hair_color
	if body_type == VISUAL_BODY_TYPE_MALE and rng.randf() < male_beard_chance:
		appearance.beard_style = _pick_style_for_body(beard_styles, body_type, rng)
	appearance.eyebrow_color = hair_color
	appearance.skin_color_customized = true
	appearance.skin_color = _pick_color(SKIN_TEXTURE_BUILDER.NATURAL_SKIN_TONES, rng)
	appearance.height_slider = _center_biased_range(height_range, rng)
	appearance.shoulder_width_slider = _center_biased_range(shoulder_range, rng)
	appearance.arm_length_slider = _center_biased_range(arm_length_range, rng)
	appearance.neck_length_slider = _center_biased_range(neck_length_range, rng)
	return appearance


func apply_to_actor(actor: Node, rng: RandomNumberGenerator, apply_equipment := true) -> void:
	if actor == null:
		return
	var appearance := create_appearance(rng)
	actor.set("character_race", appearance.character_race)
	actor.set("body_archetype", appearance.body_archetype)
	actor.set("visual_body_type", appearance.visual_body_type)
	actor.set("appearance_data", appearance)
	var batch_equipment := apply_equipment and actor.is_inside_tree() and actor.has_method("begin_equipment_update_batch") and actor.has_method("end_equipment_update_batch")
	if batch_equipment:
		actor.call("begin_equipment_update_batch")
	if apply_equipment:
		_apply_equipment(actor, rng)
	if batch_equipment:
		actor.call("end_equipment_update_batch")
	if actor.is_inside_tree() and actor.has_method("apply_appearance_data"):
		actor.call("apply_appearance_data", appearance)


func get_natural_hair_colors() -> Array:
	return _get_hair_palette().duplicate()


func _pick_race(rng: RandomNumberGenerator) -> Resource:
	var races := allowed_races.duplicate()
	if races.is_empty():
		races.append(HUMAN_RACE)
	return races[rng.randi_range(0, races.size() - 1)] if not races.is_empty() else HUMAN_RACE


static func _get_available_races() -> Array[Resource]:
	if not _available_races_cache.is_empty():
		return _available_races_cache.duplicate()
	var files := Array(DirAccess.get_files_at(CHARACTER_RACE_DIR))
	files.sort()
	for file_name in files:
		var path := "%s/%s" % [CHARACTER_RACE_DIR, str(file_name)]
		if not path.ends_with(".tres"):
			continue
		var race := load(path) as Resource
		if race != null:
			_available_races_cache.append(race)
	if _available_races_cache.is_empty():
		_available_races_cache.append(HUMAN_RACE)
	return _available_races_cache.duplicate()


func _pick_body_type(rng: RandomNumberGenerator) -> int:
	var body_types: Array[int] = []
	if (allowed_body_type_flags & BODY_TYPE_MALE_FLAG) != 0:
		body_types.append(VISUAL_BODY_TYPE_MALE)
	if (allowed_body_type_flags & BODY_TYPE_FEMALE_FLAG) != 0:
		body_types.append(VISUAL_BODY_TYPE_FEMALE)
	if body_types.is_empty():
		body_types.append(VISUAL_BODY_TYPE_MALE)
	return body_types[rng.randi_range(0, body_types.size() - 1)]


func _get_body_archetype(race: Resource, body_type: int) -> Resource:
	if race != null:
		if body_type == VISUAL_BODY_TYPE_FEMALE and race.get("default_female_archetype") != null:
			return race.get("default_female_archetype") as Resource
		if body_type == VISUAL_BODY_TYPE_MALE and race.get("default_male_archetype") != null:
			return race.get("default_male_archetype") as Resource
	return HUMAN_RACE.get("default_female_archetype") if body_type == VISUAL_BODY_TYPE_FEMALE else HUMAN_RACE.get("default_male_archetype")


func _pick_style_for_body(styles: Array[Resource], body_type: int, rng: RandomNumberGenerator) -> Resource:
	var body_type_id := "female" if body_type == VISUAL_BODY_TYPE_FEMALE else "male"
	var supported: Array[Resource] = []
	for style in styles:
		if style == null:
			continue
		if style.has_method("supports_body_type") and not bool(style.call("supports_body_type", body_type_id)):
			continue
		supported.append(style)
	if supported.is_empty():
		return null
	return supported[rng.randi_range(0, supported.size() - 1)]


func _pick_color(colors: Array, rng: RandomNumberGenerator) -> Color:
	if colors.is_empty():
		return Color.WHITE
	return colors[rng.randi_range(0, colors.size() - 1)] as Color


func _get_hair_palette() -> Array:
	return hair_color_palette if not hair_color_palette.is_empty() else DEFAULT_HAIR_COLORS


func _center_biased_range(range_value: Vector2, rng: RandomNumberGenerator) -> float:
	var low := minf(range_value.x, range_value.y)
	var high := maxf(range_value.x, range_value.y)
	var t := (rng.randf() + rng.randf()) * 0.5
	return lerpf(low, high, t)


func _apply_equipment(actor: Node, rng: RandomNumberGenerator) -> void:
	_apply_item_from_pool(actor, chest_items, rng)
	_apply_item_from_pool(actor, leg_items, rng)
	_apply_item_from_pool(actor, feet_items, rng)
	if rng.randf() < head_item_chance:
		_apply_item_from_pool(actor, head_items, rng)


func _apply_item_from_pool(actor: Node, pool: Array[Resource], rng: RandomNumberGenerator) -> void:
	if actor == null or pool.is_empty():
		return
	var item := pool[rng.randi_range(0, pool.size() - 1)]
	if item == null or not item.has_method("is_equippable") or not bool(item.call("is_equippable")):
		return
	var slot_name := str(item.get("equip_slot"))
	if slot_name.is_empty():
		return
	if actor.is_inside_tree() and actor.has_method("get_equipped_item") and actor.has_method("equip_item_to_slot"):
		if actor.call("get_equipped_item", slot_name) == null:
			actor.call("equip_item_to_slot", item, slot_name)
		return
	var starting_equipment: Array = actor.get("starting_equipment")
	if _equipment_list_has_slot(starting_equipment, slot_name):
		return
	starting_equipment.append(item)
	actor.set("starting_equipment", starting_equipment)


func _equipment_list_has_slot(items: Array, slot_name: String) -> bool:
	for item in items:
		if item != null and str(item.get("equip_slot")) == slot_name:
			return true
	return false
