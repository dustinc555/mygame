@tool
extends Node3D

class_name NestPlacementMarker

const NEST_TYPE_RUSTDEAD := 1
const NEST_TYPE_WOLVES := 2
const NEST_TYPE_ELEPHANTS := 4
const NEST_TYPE_TRIBALS := 8
const NEST_TYPE_CANNIBALS := 16

const SIZE_SMALL := 0
const SIZE_MEDIUM := 1
const SIZE_LARGE := 2

@export var marker_id := ""
@export var display_name := "Ancient Vent"
@export var region_id := "demo_world"
@export_flags("Rustdead", "Wolves", "Elephants", "Tribals", "Cannibals") var allowed_nest_types := NEST_TYPE_RUSTDEAD
@export_enum("Small", "Medium", "Large") var size := SIZE_SMALL
@export var activation_chance_override := -1.0
@export var respawn_cooldown_days_override := -1
@export var editor_debug_radius := 4.0


func _ready() -> void:
	add_to_group("nest_placement_marker")


func get_marker_id() -> String:
	var clean_id := marker_id.strip_edges()
	if not clean_id.is_empty():
		return clean_id
	return str(name).strip_edges().to_snake_case()


func get_region_id() -> String:
	return region_id.strip_edges() if not region_id.strip_edges().is_empty() else "world"


func get_size_id() -> String:
	match size:
		SIZE_MEDIUM:
			return "medium"
		SIZE_LARGE:
			return "large"
		_:
			return "small"


func get_allowed_nest_type_ids() -> Array[String]:
	var result: Array[String] = []
	if allowed_nest_types & NEST_TYPE_RUSTDEAD:
		result.append("rustdead")
	if allowed_nest_types & NEST_TYPE_WOLVES:
		result.append("wolves")
	if allowed_nest_types & NEST_TYPE_ELEPHANTS:
		result.append("elephants")
	if allowed_nest_types & NEST_TYPE_TRIBALS:
		result.append("tribals")
	if allowed_nest_types & NEST_TYPE_CANNIBALS:
		result.append("cannibals")
	return result


func get_activation_chance(default_value: float) -> float:
	if activation_chance_override >= 0.0:
		return clampf(activation_chance_override, 0.0, 1.0)
	return clampf(default_value, 0.0, 1.0)


func get_respawn_cooldown_days(default_value: int) -> int:
	if respawn_cooldown_days_override >= 0:
		return max(0, respawn_cooldown_days_override)
	return max(0, default_value)
