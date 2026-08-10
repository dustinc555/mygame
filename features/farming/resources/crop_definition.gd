extends Resource

class_name CropDefinition

## Data-only crop profile. Sim rules consume to_sim_profile(); projections use
## source_node_prefix/procedural_visual to select a nine-stage visual family.

@export var crop_id := ""
@export var display_name := "Crop"
@export var source_node_prefix := ""
@export var procedural_visual := ""
@export var produce_item: ItemDefinition
@export var seed_item: ItemDefinition
@export_range(1, 20, 1) var seed_cost_per_cell := 1
@export_range(1.0, 10080.0, 1.0) var growth_minutes := 1440.0
@export_range(1.0, 2880.0, 1.0) var dry_grace_minutes := 240.0
@export_range(1.0, 2880.0, 1.0) var ripe_window_minutes := 720.0
@export_range(0.1, 100.0, 0.1) var water_capacity := 20.0
@export_range(0.0, 10.0, 0.01) var water_per_growth_minute := 0.02
@export_range(1, 100, 1) var base_yield := 3
@export_range(0.0, 1.0, 0.001) var yield_per_farming_level := 0.01
@export_range(0.1, 120.0, 0.1) var till_seconds := 4.0
@export_range(0.1, 120.0, 0.1) var plant_seconds := 2.0
@export_range(0.1, 120.0, 0.1) var water_seconds := 2.5
@export_range(0.1, 120.0, 0.1) var harvest_seconds := 3.0
@export_range(0.1, 120.0, 0.1) var clear_seconds := 2.0
@export var required_harvest_tool_tag := ""
@export var required_harvest_tool_label := ""


func get_visual_stage_count() -> int:
	return FarmSimulation.VISUAL_STAGE_COUNT


func get_stage_node_name(stage_index: int) -> String:
	if source_node_prefix.is_empty():
		return ""
	return "%s_Stage%02d" % [source_node_prefix, clampi(stage_index, 0, get_visual_stage_count() - 1) + 1]


func to_sim_profile() -> Dictionary:
	return {
		"crop_id": crop_id,
		"growth_minutes": growth_minutes,
		"dry_grace_minutes": dry_grace_minutes,
		"ripe_window_minutes": ripe_window_minutes,
		"water_capacity": water_capacity,
		"water_per_growth_minute": water_per_growth_minute,
		"base_yield": base_yield,
		"yield_per_farming_level": yield_per_farming_level,
	}
