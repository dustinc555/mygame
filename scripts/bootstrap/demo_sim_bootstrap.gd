extends "res://scripts/controllers/world_map_combat_sim_controller.gd"

class_name DemoSimBootstrap


func _ready() -> void:
	use_isolated_ecs_world = true
	process_ecs_world_on_fixed_tick = true
	squad_id_prefix = "demo_squad"
	member_id_prefix = "demo_member"
	population_generation_source = "demo_world_squad"
	add_to_group("demo_sim_bootstrap")
	super._ready()
