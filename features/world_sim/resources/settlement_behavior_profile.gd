extends Resource

class_name SettlementBehaviorProfile

@export var profile_id := ""
@export var display_name := "Settlement Behavior"
@export var food_units_per_person_per_day := 1.0
@export var food_outputs_per_day: Array[Resource] = []
@export_range(0.0, 1.0, 0.01) var base_aggression := 0.0
@export var can_initiate_food_raids := false
@export_range(0.0, 1.0, 0.01) var food_raid_pressure_threshold := 0.28
@export var can_attack_when_starving := false
@export_range(0.0, 1.0, 0.01) var desperate_attack_pressure_threshold := 0.08
@export_enum("default_target", "closest_peer", "best_raid_target") var raid_target_selection_mode := "default_target"
@export_enum("any_non_self", "not_allied", "hostile_only") var raid_target_relation_policy := "any_non_self"
@export var raid_target_exclude_same_faction := true
@export var raid_target_requires_food := true
@export var raid_target_max_distance := 0.0
@export var raid_target_distance_weight := 0.25
@export var raid_target_food_weight := 0.15
@export var raid_target_population_weight := 2.0
@export var raid_target_weakness_weight := 1.0
@export var raid_target_defense_weight := 0.55
@export var raid_target_stronger_penalty_weight := 3.0
@export var raid_target_population_defense_weight := 1.0
@export var raid_target_armed_defense_weight := 4.0
@export var raid_target_supply_defense_weight := 18.0
@export_range(0, 23, 1) var daily_upkeep_hour := 6
@export var action_cooldown_hours := 6.0
@export var require_action_time_window := false
@export_range(0, 23, 1) var action_window_start_hour := 0
@export_range(0, 23, 1) var action_window_end_hour := 23


func get_id() -> String:
	return profile_id if not profile_id.is_empty() else display_name


func is_hour_in_action_window(hour: int) -> bool:
	if not require_action_time_window:
		return true
	if action_window_start_hour <= action_window_end_hour:
		return hour >= action_window_start_hour and hour <= action_window_end_hour
	return hour >= action_window_start_hour or hour <= action_window_end_hour
