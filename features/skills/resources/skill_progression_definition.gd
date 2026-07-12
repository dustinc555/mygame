@tool
extends Resource

class_name SkillProgressionDefinition

@export_range(1, 1000, 1) var maximum_level := 100
@export_range(1, 10000, 1) var base_xp_to_next := 50.0
@export_range(1, 1000, 1) var level_xp_decay_cap := 101.0
@export_range(0.0001, 1.0, 0.0001) var minimum_level_xp_multiplier := 0.002

@export_range(0.0, 1.0, 0.01) var chance_very_low_max := 0.2
@export_range(0.0, 1.0, 0.01) var chance_low_max := 0.4
@export_range(0.0, 1.0, 0.01) var chance_even_max := 0.65
@export_range(0.0, 1.0, 0.01) var chance_high_max := 0.9

@export_range(0.0, 100.0, 0.01) var very_low_success_xp := 20.0
@export_range(0.0, 100.0, 0.01) var very_low_failure_xp := 10.0
@export_range(0.0, 100.0, 0.01) var low_success_xp := 12.0
@export_range(0.0, 100.0, 0.01) var low_failure_xp := 4.5
@export_range(0.0, 100.0, 0.01) var even_success_xp := 5.0
@export_range(0.0, 100.0, 0.01) var even_failure_xp := 2.0
@export_range(0.0, 100.0, 0.01) var high_success_xp := 3.0
@export_range(0.0, 100.0, 0.01) var high_failure_xp := 1.5
@export_range(0.0, 100.0, 0.01) var trivial_success_xp := 0.5
@export_range(0.0, 100.0, 0.01) var trivial_failure_xp := 0.25
