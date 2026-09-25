@tool
extends Resource

@export var type_id := ""
@export var display_name := "Camp"
@export var warrior_type: CharacterTypeDefinition
@export var furnishings: Array[Resource] = []
@export_group("Compact Camp Sizes")
@export var small: Resource = preload("res://features/camps/resources/sizes/small.tres")
@export var medium: Resource = preload("res://features/camps/resources/sizes/medium.tres")
@export var large: Resource = preload("res://features/camps/resources/sizes/large.tres")
## Stools face the central fire. Layout reserves this circle before other props.
@export_range(2.2, 3.5, 0.1, "suffix:m") var seating_radius := 2.6
@export_group("Lifecycle and Patrols")
## One replacement per interval, only while somebody still survives.
@export_range(1.0, 365.0, 1.0) var replacement_days := 7.0
@export_range(1.0, 365.0, 1.0) var cleanup_days := 7.0
@export_range(0.0, 1.0, 0.05) var night_watch_fraction := 0.1
@export_range(1, 240, 1) var guard_rotation_minutes := 30
@export_range(0.5, 6.0, 0.1) var patrol_speed := 2.5
## Prevent repeated abstract fights while crossing one town's outskirts.
@export_range(1.0, 168.0, 1.0) var skirmish_cooldown_hours := 24.0

func get_size_preset(size: int) -> Resource:
	return [small, medium, large][clampi(size, 0, 2)]
