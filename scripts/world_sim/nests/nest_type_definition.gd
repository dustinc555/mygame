extends Resource

class_name NestTypeDefinition

@export var nest_type_id := ""
@export var display_name := "Nest"
@export var faction_definition: Resource
@export var actor_script: Script
@export var visual_scenes: Array[PackedScene] = []
@export var selection_weight := 1.0
@export var default_initial_activation_chance := 0.5
@export var respawn_cooldown_days := 7
@export var wander_radius := 500.0
@export var attack_radius := 1000.0
@export var daily_attack_chance := 0.05
@export_range(1, 64, 1) var small_population_min := 8
@export_range(1, 64, 1) var small_population_max := 12
@export_range(0, 12, 1) var small_patrol_squad_count := 2
@export_range(1, 24, 1) var small_patrol_squad_min := 3
@export_range(1, 24, 1) var small_patrol_squad_max := 5
@export_range(1, 24, 1) var small_attack_squad_min := 3
@export_range(1, 24, 1) var small_attack_squad_max := 7
@export_range(1, 128, 1) var medium_population_min := 18
@export_range(1, 128, 1) var medium_population_max := 28
@export_range(0, 16, 1) var medium_patrol_squad_count := 3
@export_range(1, 32, 1) var medium_patrol_squad_min := 4
@export_range(1, 32, 1) var medium_patrol_squad_max := 8
@export_range(1, 32, 1) var medium_attack_squad_min := 6
@export_range(1, 32, 1) var medium_attack_squad_max := 12
@export_range(1, 256, 1) var large_population_min := 42
@export_range(1, 256, 1) var large_population_max := 64
@export_range(0, 24, 1) var large_patrol_squad_count := 5
@export_range(1, 48, 1) var large_patrol_squad_min := 6
@export_range(1, 48, 1) var large_patrol_squad_max := 12
@export_range(1, 48, 1) var large_attack_squad_min := 10
@export_range(1, 48, 1) var large_attack_squad_max := 20


func get_id() -> String:
	return nest_type_id.strip_edges() if not nest_type_id.strip_edges().is_empty() else display_name.strip_edges().to_snake_case()


func get_faction_id() -> String:
	if faction_definition != null and faction_definition.has_method("get_id"):
		return str(faction_definition.call("get_id"))
	return ""


func get_visual_scene_count() -> int:
	return visual_scenes.size()


func get_visual_scene(index: int) -> PackedScene:
	if visual_scenes.is_empty():
		return null
	return visual_scenes[clampi(index, 0, visual_scenes.size() - 1)]


func get_population_range(size_id: String) -> Vector2i:
	match size_id:
		"medium":
			return _normalized_range(medium_population_min, medium_population_max)
		"large":
			return _normalized_range(large_population_min, large_population_max)
		_:
			return _normalized_range(small_population_min, small_population_max)


func get_patrol_squad_count(size_id: String) -> int:
	match size_id:
		"medium":
			return max(0, medium_patrol_squad_count)
		"large":
			return max(0, large_patrol_squad_count)
		_:
			return max(0, small_patrol_squad_count)


func get_patrol_squad_size_range(size_id: String) -> Vector2i:
	match size_id:
		"medium":
			return _normalized_range(medium_patrol_squad_min, medium_patrol_squad_max)
		"large":
			return _normalized_range(large_patrol_squad_min, large_patrol_squad_max)
		_:
			return _normalized_range(small_patrol_squad_min, small_patrol_squad_max)


func get_attack_squad_size_range(size_id: String) -> Vector2i:
	match size_id:
		"medium":
			return _normalized_range(medium_attack_squad_min, medium_attack_squad_max)
		"large":
			return _normalized_range(large_attack_squad_min, large_attack_squad_max)
		_:
			return _normalized_range(small_attack_squad_min, small_attack_squad_max)


func _normalized_range(minimum: int, maximum: int) -> Vector2i:
	var low := mini(maxi(1, minimum), maxi(1, maximum))
	var high := maxi(maxi(1, minimum), maxi(1, maximum))
	return Vector2i(low, high)
