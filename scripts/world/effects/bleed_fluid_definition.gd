@tool
extends Resource

class_name BleedFluidDefinition

@export var fluid_id := "blood"
@export var display_name := "Blood"
@export var fresh_color := Color(0.46, 0.015, 0.01, 0.92)
@export var dried_color := Color(0.13, 0.025, 0.018, 0.82)
@export var uses_custom_ui_color := false
@export var ui_bar_color := Color(0.46, 0.015, 0.01, 0.92)
@export var ui_glow_color := Color(1.0, 0.04, 0.02, 1.0)
