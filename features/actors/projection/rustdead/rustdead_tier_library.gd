extends RefCounted

class_name RustdeadTierLibrary

const SKIN_TEXTURE_BUILDER := preload("res://features/actors/projection/appearance/skin_texture_builder.gd")
const FRESH := preload("res://features/actors/resources/character_races/rustdead_tiers/fresh.tres")
const FESTERED := preload("res://features/actors/resources/character_races/rustdead_tiers/festered.tres")
const WROUGHT := preload("res://features/actors/resources/character_races/rustdead_tiers/wrought.tres")
const ANCIENT := preload("res://features/actors/resources/character_races/rustdead_tiers/ancient.tres")

const VISUAL_BODY_TYPE_MALE := 2
const VISUAL_BODY_TYPE_FEMALE := 3
const NON_TIER_SKILL_RANGE := Vector2i(0, 20)

const TIERS: Array[Resource] = [FRESH, FESTERED, WROUGHT, ANCIENT]


static func get_tiers() -> Array[Resource]:
	return TIERS.duplicate()


static func get_default_tier() -> Resource:
	return FRESH


static func get_tier_by_id(tier_id: String) -> Resource:
	var clean_id := tier_id.strip_edges().to_lower()
	for tier in TIERS:
		if tier != null and str(tier.call("get_id")) == clean_id:
			return tier
	return FRESH


static func get_tier_for_demo_index(index: int) -> Resource:
	return TIERS[wrapi(index, 0, TIERS.size())]


static func pick_tier_for_nest_size(size_id: String, rng: RandomNumberGenerator) -> Resource:
	var total_weight := 0.0
	for tier in TIERS:
		if tier != null:
			total_weight += float(tier.call("get_weight_for_nest_size", size_id))
	if total_weight <= 0.0:
		return FRESH
	var roll := rng.randf_range(0.0, total_weight)
	var cursor := 0.0
	for tier in TIERS:
		if tier == null:
			continue
		cursor += float(tier.call("get_weight_for_nest_size", size_id))
		if roll <= cursor:
			return tier
	return FRESH


static func roll_skill_levels(tier: Resource, rng: RandomNumberGenerator) -> Dictionary:
	var result := {}
	var stat_range := _get_stat_range(tier)
	for definition in SkillRules.get_all_definitions():
		var skill_id := str(definition.skill_id)
		var roll_range := stat_range if is_tier_scaled_skill_id(skill_id) else NON_TIER_SKILL_RANGE
		result[skill_id] = rng.randi_range(roll_range.x, roll_range.y)
	return result


static func is_tier_scaled_skill_id(skill_id: String) -> bool:
	match skill_id:
		SkillRules.ATTRIBUTE_STRENGTH, SkillRules.ATTRIBUTE_PERCEPTION, SkillRules.ATTRIBUTE_DEXTERITY, SkillRules.ATTRIBUTE_TOUGHNESS, SkillRules.ATTRIBUTE_ENDURANCE, SkillRules.COMBAT_UNARMED, SkillRules.MOVEMENT_RUNNING:
			return true
	return false


static func get_non_tier_skill_range() -> Vector2i:
	return NON_TIER_SKILL_RANGE


static func roll_max_hp(tier: Resource, rng: RandomNumberGenerator) -> float:
	var hp_range := _get_max_hp_range(tier)
	return rng.randf_range(hp_range.x, hp_range.y)


static func pick_skin_color(tier: Resource, rng: RandomNumberGenerator) -> Color:
	var tones: Array = SKIN_TEXTURE_BUILDER.get_skin_tones_for_race(SKIN_TEXTURE_BUILDER.RUSTDEAD_RACE_ID)
	if tones.is_empty():
		return Color(0.64, 0.19, 0.16, 1.0)
	var indices := PackedInt32Array()
	if tier != null and tier.get("skin_tone_indices") is PackedInt32Array:
		indices = tier.get("skin_tone_indices")
	if indices.is_empty():
		return tones[0] as Color
	var tone_index := clampi(indices[rng.randi_range(0, indices.size() - 1)], 0, tones.size() - 1)
	return tones[tone_index] as Color


static func apply_hair_for_tier(appearance: Resource, tier: Resource, rng: RandomNumberGenerator, body_type: int) -> void:
	if appearance == null or tier == null:
		return
	var hair_pool: Array = tier.get("female_hair_styles") if body_type == VISUAL_BODY_TYPE_FEMALE else tier.get("male_hair_styles")
	if hair_pool.is_empty():
		return
	var hair_color := _pick_hair_color(tier, rng)
	appearance.hair_color = hair_color
	appearance.hair_style = hair_pool[rng.randi_range(0, hair_pool.size() - 1)] as Resource
	if body_type == VISUAL_BODY_TYPE_MALE:
		var beard_pool: Array = tier.get("male_beard_styles")
		if not beard_pool.is_empty():
			appearance.beard_style = beard_pool[rng.randi_range(0, beard_pool.size() - 1)] as Resource
			appearance.beard_color = hair_color


static func _pick_hair_color(tier: Resource, rng: RandomNumberGenerator) -> Color:
	var palette: Array = tier.get("hair_color_palette") if tier != null else []
	if palette.is_empty():
		return Color(0.08, 0.055, 0.04, 1.0)
	return palette[rng.randi_range(0, palette.size() - 1)] as Color


static func _get_stat_range(tier: Resource) -> Vector2i:
	if tier != null and tier.has_method("get_stat_range"):
		return tier.call("get_stat_range")
	return Vector2i(10, 25)


static func _get_max_hp_range(tier: Resource) -> Vector2:
	if tier != null and tier.has_method("get_max_hp_range"):
		return tier.call("get_max_hp_range")
	return Vector2(85.0, 105.0)
