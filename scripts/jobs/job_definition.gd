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


func get_display_name() -> String:
	if not display_name.is_empty():
		return display_name
	if not job_id.is_empty():
		return job_id.capitalize()
	return "Job"
