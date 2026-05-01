extends Node

class_name JobSystemController

const JOB_PROVIDER_SCRIPT = preload("res://scripts/jobs/job_provider.gd")

var root_scene: Node
var _sim_time := 0.0
var _initialized := false


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	if is_inside_tree():
		_initialized = true


func _ready() -> void:
	if root_scene != null:
		_initialized = true


func _process(delta: float) -> void:
	if not _initialized:
		return
	_sim_time += delta
	for node in get_tree().get_nodes_in_group("job_provider"):
		if node is JOB_PROVIDER_SCRIPT:
			node.process_jobs(delta, _sim_time)


func get_sim_time() -> float:
	return _sim_time
