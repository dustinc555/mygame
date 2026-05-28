extends AiTaskStep

class_name AiReleaseActivityStep


func _init() -> void:
	step_id = "release_activity"
	debug_label = "Release Activity"


func start(owner, job) -> void:
	super.start(owner, job)
	var target = job.target if job != null else null
	if target != null and is_instance_valid(target):
		if target.has_method("end_ai_activity"):
			target.call("end_ai_activity", owner, job)
		elif target.has_method("release_actor"):
			target.call("release_actor", owner)
	var tree: SceneTree = owner.get_tree() if owner is Node and owner.is_inside_tree() else null
	var bridge: Node = tree.get_first_node_in_group("gecs_world_controller") if tree != null else null
	if bridge != null and bridge.has_method("clear_activity_assignment"):
		bridge.call("clear_activity_assignment", owner)
	status = StepStatus.SUCCEEDED
