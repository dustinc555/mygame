extends Node3D

class_name SettlementPopulationSpawner

@export var settlement_definition: Resource
@export var member_name_prefix := "Resident"
@export var stable_id_prefix := "resident"
@export var faction_id := ""
@export var squad_name := ""
@export var base_color := Color(0.62, 0.62, 0.62, 1.0)
@export var color_variation := 0.0
@export var hostile_faction_ids: PackedStringArray = PackedStringArray()
@export_range(0, 8, 1) var combat_stance := NpcRules.CombatStance.DEFENSIVE
@export var population_appearance_profile: Resource
@export var desired_population_override := -1
@export_range(0, 8, 1) var spawn_layout := 0
@export_range(0.0, 1000.0, 0.1) var spawn_radius := 8.0
@export_range(0.0, 1000.0, 0.1) var spawn_inner_radius := 0.0
@export var random_seed := 1
@export var starting_equipment: Array[Resource] = []
@export_range(1, 100, 1) var resident_perception_min := SkillRules.DEFAULT_LEVEL
@export_range(1, 100, 1) var resident_perception_max := SkillRules.DEFAULT_LEVEL

var _needs_resync := true


func _ready() -> void:
	add_to_group("population_spawner")
	call_deferred("resync_population_realization")


func get_settlement_id() -> String:
	var definition_id := _resource_id(settlement_definition)
	if not definition_id.is_empty():
		return definition_id
	var current := get_parent()
	while current != null:
		if current.has_method("get_settlement_id"):
			return str(current.call("get_settlement_id"))
		current = current.get_parent()
	return ""


func needs_population_realization_resync() -> bool:
	return _needs_resync


func resync_population_realization() -> void:
	var population_controller := _get_population_controller()
	if population_controller == null or not population_controller.has_method("ensure_generated_population"):
		_needs_resync = true
		return
	var settlement_id := get_settlement_id()
	if settlement_id.is_empty():
		_needs_resync = true
		return
	var desired_count := _desired_population_count(settlement_id)
	population_controller.call("ensure_generated_population", settlement_id, _spawner_id(), desired_count, _population_context())
	_needs_resync = false


func mark_population_dirty() -> void:
	_needs_resync = true


func _desired_population_count(settlement_id: String) -> int:
	if desired_population_override >= 0:
		return desired_population_override
	var settlement_controller := _get_settlement_controller()
	if settlement_controller != null and settlement_controller.has_method("get_settlement_state"):
		var state: Dictionary = settlement_controller.call("get_settlement_state", settlement_id)
		if not state.is_empty():
			return max(0, int(state.get("population_available", state.get("population", 0))))
	return 0


func _population_context() -> Dictionary:
	return {
		"role_id": "resident",
		"member_name_prefix": member_name_prefix,
		"stable_id_prefix": stable_id_prefix,
		"faction_id": faction_id,
		"squad_name": squad_name,
		"hostile_faction_ids": Array(hostile_faction_ids),
		"combat_stance": combat_stance,
		"base_color": base_color,
		"color_variation": color_variation,
		"population_appearance_profile": population_appearance_profile,
		"starting_equipment": starting_equipment,
		"spawn_position": global_position,
		"resident_perception_min": resident_perception_min,
		"resident_perception_max": resident_perception_max,
	}


func _spawner_id() -> String:
	var clean_prefix := stable_id_prefix.strip_edges()
	if not clean_prefix.is_empty():
		return clean_prefix
	return str(name).strip_edges().to_snake_case()


func _resource_id(resource: Resource) -> String:
	if resource != null and resource.has_method("get_id"):
		return str(resource.call("get_id")).strip_edges()
	return ""


func _get_population_controller() -> Node:
	return _first_group_node("population_controller")


func _get_settlement_controller() -> Node:
	return _first_group_node("settlement_controller")


func _first_group_node(group_name: String) -> Node:
	if not is_inside_tree():
		return null
	var tree := get_tree()
	return tree.get_first_node_in_group(group_name) if tree != null else null
