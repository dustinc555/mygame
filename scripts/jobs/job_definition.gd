extends Resource

class_name JobDefinition

@export var display_name := "Job"
@export var job_id := ""
@export var algorithm_id := "mine_and_haul"
@export_range(1, 16, 1) var slot_count := 1
@export var pay_interval_seconds := 20.0
@export var pay_per_interval := 2
@export var carry_item_threshold := 4
@export_enum("abstract_sink", "real_container") var output_mode := "abstract_sink"
@export var resource_paths: Array[NodePath] = []
@export var container_paths: Array[NodePath] = []
@export var requirements: Array[Resource] = []
@export_group("Server Shift")
@export var server_tip_on_success := 1
@export var server_charisma_failure_xp := 2.0
@export var server_charisma_success_xp := 8.0
@export_range(0.0, 1.0, 0.01) var server_charisma_base_chance := 0.25
@export_range(0.0, 1.0, 0.01) var server_charisma_chance_per_level := 0.03
@export_range(0.0, 1.0, 0.01) var server_charisma_min_chance := 0.05
@export_range(0.0, 1.0, 0.01) var server_charisma_max_chance := 0.9
@export var server_charisma_xp_soft_cap_level := 30
@export_range(0.0, 1.0, 0.01) var server_charisma_post_cap_xp_multiplier := 0.35


func get_display_name() -> String:
	if not display_name.is_empty():
		return display_name
	if not job_id.is_empty():
		return job_id.capitalize()
	return "Job"
