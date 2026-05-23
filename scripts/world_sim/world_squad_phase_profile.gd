extends Resource

class_name WorldSquadPhaseProfile

@export var phase_id := ""
@export var display_name := "Phase"
@export_enum("travel", "planning", "battle", "resolved") var phase_type := "travel"
@export var target_role := ""
@export var duration_seconds := 0.0
@export var next_phase_id := ""
@export var leader_conversation: Resource
@export var leader_shout_lines: PackedStringArray = PackedStringArray()
@export var leader_shout_interval_seconds := 20.0
@export var create_conflict_event_on_enter := false
