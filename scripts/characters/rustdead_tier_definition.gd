@tool
extends Resource

class_name RustdeadTierDefinition

@export var tier_id := "fresh"
@export var display_name := "Fresh Rustdead"
@export var stat_range := Vector2i(10, 25)
@export var max_hp_range := Vector2(85.0, 105.0)
@export_range(0.0, 2.0, 0.01) var passive_bonus := 0.2
@export var skin_tone_indices: PackedInt32Array = PackedInt32Array([0, 1])
@export var male_hair_styles: Array[Resource] = []
@export var female_hair_styles: Array[Resource] = []
@export var male_beard_styles: Array[Resource] = []
@export var hair_color_palette: Array[Color] = []
@export_range(0.0, 100.0, 0.1) var small_nest_weight := 1.0
@export_range(0.0, 100.0, 0.1) var medium_nest_weight := 1.0
@export_range(0.0, 100.0, 0.1) var large_nest_weight := 1.0


func get_id() -> String:
	var clean_id := tier_id.strip_edges().to_lower()
	return clean_id if not clean_id.is_empty() else display_name.strip_edges().to_snake_case()


func get_stat_range() -> Vector2i:
	var low := mini(stat_range.x, stat_range.y)
	var high := maxi(stat_range.x, stat_range.y)
	return Vector2i(low, high)


func get_max_hp_range() -> Vector2:
	var low := minf(max_hp_range.x, max_hp_range.y)
	var high := maxf(max_hp_range.x, max_hp_range.y)
	return Vector2(low, high)


func get_weight_for_nest_size(size_id: String) -> float:
	match size_id:
		"medium":
			return maxf(0.0, medium_nest_weight)
		"large":
			return maxf(0.0, large_nest_weight)
		_:
			return maxf(0.0, small_nest_weight)


func allows_hair() -> bool:
	return not male_hair_styles.is_empty() or not female_hair_styles.is_empty()


func allows_male_beards() -> bool:
	return not male_beard_styles.is_empty()
