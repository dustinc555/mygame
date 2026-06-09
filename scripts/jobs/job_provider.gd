extends Node

class_name JobProvider

const REPORT_GRACE_SECONDS := 45.0

@export var jobs: Array[JobDefinition] = []
@export var wage_item_definition: Resource

var _sim_time := 0.0


func _ready() -> void:
	add_to_group("job_provider")
	call_deferred("sync_gecs_state")


func set_sim_time(value: float) -> void:
	_sim_time = value
	sync_gecs_state()


func get_provider_character() -> Node:
	return get_parent()


func get_provider_name() -> String:
	var owner := get_provider_character()
	if owner != null:
		var member_name = owner.get("member_name")
		if member_name != null and not str(member_name).strip_edges().is_empty():
			return str(member_name).strip_edges()
	return str(name)


func get_provider_id() -> String:
	return str(get_path()) if is_inside_tree() else str(get_instance_id())


func get_job_count() -> int:
	return jobs.size()


func get_job_definition(job_index: int) -> JobDefinition:
	if job_index < 0 or job_index >= jobs.size():
		return null
	return jobs[job_index]


func get_job_label(job_index: int) -> String:
	var job := get_job_definition(job_index)
	return job.get_display_name() if job != null else "Job"


func create_job_contract(actor_id: String, job_index: int) -> Dictionary:
	var normalized_actor_id := actor_id.strip_edges()
	var job := get_job_definition(job_index)
	var bridge := _get_gecs_world()
	if normalized_actor_id.is_empty() or job == null or bridge == null or not bridge.has_method("upsert_job_contract"):
		return {}
	var job_id := str(job.job_id).strip_edges()
	if job_id.is_empty():
		job_id = "%s.%d" % [str(job.algorithm_id).strip_edges(), job_index]
	var provider_owner := get_provider_character()
	var owner_actor_id := _actor_id_for_node(provider_owner)
	var contract: Dictionary = bridge.call("upsert_job_contract", {
		"actor_id": normalized_actor_id,
		"provider_id": get_provider_id(),
		"provider_name": get_provider_name(),
		"provider_path": get_path() if is_inside_tree() else NodePath(),
		"provider_owner_actor_id": owner_actor_id,
		"job_id": job_id,
		"job_index": job_index,
		"algorithm_id": str(job.algorithm_id),
		"display_name": job.get_display_name(),
		"status": "active",
		"hired_at": _sim_time,
		"next_shift_time": _sim_time,
		"report_deadline": _sim_time + REPORT_GRACE_SECONDS,
		"last_started_at": -1.0,
	})
	sync_gecs_state()
	return contract


func sync_gecs_state() -> void:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("sync_job_provider"):
		return
	bridge.call("sync_job_provider", self, _active_slot_snapshot(), {}, _sim_time)


func _active_slot_snapshot() -> Dictionary:
	var snapshot := {}
	for job_index in range(jobs.size()):
		var job := jobs[job_index]
		if job == null:
			continue
		var slots: Array = []
		for slot_index in range(maxi(int(job.slot_count), 1)):
			slots.append({"slot_index": slot_index, "worker": null})
		snapshot[job_index] = slots
	return snapshot


func _get_gecs_world() -> Node:
	if not is_inside_tree():
		return null
	var current := get_parent()
	while current != null:
		var local := current.get_node_or_null("GecsWorldController")
		if local != null:
			return local
		var bootstrap := current.get_node_or_null("GameBootstrap")
		if bootstrap != null:
			var bridge := bootstrap.get_node_or_null("GecsWorldController")
			if bridge != null:
				return bridge
		current = current.get_parent()
	return get_tree().get_first_node_in_group("gecs_world_controller")


func _actor_id_for_node(node: Node) -> String:
	if node == null:
		return ""
	if node.has_meta("actor_record_id"):
		return str(node.get_meta("actor_record_id")).strip_edges()
	var stable_id = node.get("stable_id")
	return str(stable_id).strip_edges() if stable_id != null else ""
