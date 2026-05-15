extends Resource

class_name SettlementBehaviorProfile

@export var profile_id := ""
@export var display_name := "Settlement Behavior"
@export var food_production_per_day := 0.0
@export var food_consumption_per_person_per_day := 1.0
@export_range(0.0, 1.0, 0.01) var base_aggression := 0.0
@export var can_initiate_food_raids := false
@export_range(0.0, 1.0, 0.01) var food_raid_pressure_threshold := 0.28
@export var can_attack_when_starving := false
@export_range(0.0, 1.0, 0.01) var desperate_attack_pressure_threshold := 0.08
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
