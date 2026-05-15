extends Resource

class_name SettlementDefinition

@export var settlement_id := ""
@export var display_name := "Settlement"
@export var faction_definition: Resource
@export var behavior_profile: Resource
@export var world_position := Vector3.ZERO
@export_range(1, 10000, 1) var max_occupancy := 12
@export_enum("Depopulated", "Sparse", "Populated", "Overcrowded") var occupancy_state := 2
@export_range(1, 10000, 1) var population := 12
@export var starting_food := 60.0
@export var max_food := 160.0
@export var known_settlement_ids: PackedStringArray = PackedStringArray()
@export var default_target_settlement_id := ""
@export var raid_squad_template: Resource
@export var defense_squad_template: Resource


func get_id() -> String:
	return settlement_id if not settlement_id.is_empty() else display_name


func get_faction_id() -> String:
	return str(faction_definition.call("get_id")) if faction_definition != null and faction_definition.has_method("get_id") else ""


func get_occupancy_multiplier() -> float:
	match occupancy_state:
		0:
			return 0.25
		1:
			return 0.5
		3:
			return 1.25
		_:
			return 1.0


func get_occupancy_label() -> String:
	match occupancy_state:
		0:
			return "Depopulated"
		1:
			return "Sparse"
		3:
			return "Overcrowded"
		_:
			return "Populated"


func get_effective_population() -> int:
	return max(1, int(round(float(max_occupancy) * get_occupancy_multiplier())))
