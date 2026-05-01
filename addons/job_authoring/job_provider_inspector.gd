@tool
extends EditorInspectorPlugin

const JOB_DEFINITION_SCRIPT = preload("res://scripts/jobs/job_definition.gd")
const JOB_PROVIDER_SCRIPT = preload("res://scripts/jobs/job_provider.gd")
const MINING_RESOURCE_NODE_SCRIPT = preload("res://scripts/resources/mining_resource_node.gd")
const WORLD_CONTAINER_SCRIPT = preload("res://scripts/world/containers/world_container.gd")

var _plugin: EditorPlugin


func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin


func _can_handle(object: Object) -> bool:
	return object is Node and object.get_script() == JOB_PROVIDER_SCRIPT


func _parse_begin(object: Object) -> void:
	var provider = object as Node
	if provider == null:
		return
	add_custom_control(_build_panel(provider))


func _build_panel(provider: Node) -> Control:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title := Label.new()
	title.text = "Job Authoring"
	root.add_child(title)

	var add_mine_button := Button.new()
	add_mine_button.text = "Add Mine Job"
	add_mine_button.pressed.connect(_on_add_mine_job.bind(provider))
	root.add_child(add_mine_button)

	for job_index in range(provider.jobs.size()):
		var job = provider.jobs[job_index]
		if job == null:
			continue
		root.add_child(_build_job_box(provider, job, job_index))

	return root


func _build_job_box(provider: Node, job, job_index: int) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var heading := Label.new()
	heading.text = "%d. %s" % [job_index + 1, job.get_display_name()]
	box.add_child(heading)

	if str(job.algorithm_id) == "mine_and_haul":
		var button_row := HBoxContainer.new()
		var add_resource_button := Button.new()
		add_resource_button.text = "Add Resource Node"
		add_resource_button.pressed.connect(_show_picker.bind(provider, job_index, "resource_paths", MINING_RESOURCE_NODE_SCRIPT, add_resource_button))
		button_row.add_child(add_resource_button)

		var add_container_button := Button.new()
		add_container_button.text = "Add Container"
		add_container_button.pressed.connect(_show_picker.bind(provider, job_index, "container_paths", WORLD_CONTAINER_SCRIPT, add_container_button))
		button_row.add_child(add_container_button)
		box.add_child(button_row)

	return box


func _on_add_mine_job(provider: Node) -> void:
	var old_jobs: Array = provider.jobs.duplicate()
	var new_jobs: Array = provider.jobs.duplicate()
	var job = JOB_DEFINITION_SCRIPT.new()
	job.display_name = "Mining work"
	job.job_id = "mine_job"
	job.algorithm_id = "mine_and_haul"
	job.slot_count = 1
	job.pay_interval_seconds = 30.0
	job.pay_per_interval = 1
	job.carry_item_threshold = 4
	job.output_mode = "abstract_sink"
	new_jobs.append(job)
	_apply_jobs_change(provider, old_jobs, new_jobs, "Add Mine Job")


func _show_picker(provider: Node, job_index: int, field_name: String, target_script, source_button: Control) -> void:
	var edited_root := _plugin.get_editor_interface().get_edited_scene_root()
	if edited_root == null:
		return
	var matches := _collect_matches(provider, edited_root, target_script)
	var popup := PopupMenu.new()
	popup.name = "JobAuthoringPopup"
	popup.hide_on_checkable_item_selection = true
	popup.hide_on_item_selection = true
	for index in range(matches.size()):
		var match: Dictionary = matches[index]
		popup.add_item(str(match.get("label", "")), index)
		popup.set_item_metadata(index, match)
	if matches.is_empty():
		popup.add_item("No matching nodes in scene", -1)
		popup.set_item_disabled(0, true)
	popup.id_pressed.connect(_on_picker_selected.bind(provider, job_index, field_name, popup))
	_plugin.get_editor_interface().get_base_control().add_child(popup)
	popup.popup()
	var popup_position: Vector2 = source_button.get_screen_position() + Vector2(0.0, source_button.size.y)
	popup.position = Vector2i(popup_position)


func _on_picker_selected(item_id: int, provider: Node, job_index: int, field_name: String, popup: PopupMenu) -> void:
	if item_id < 0:
		if is_instance_valid(popup):
			popup.queue_free()
		return
	var metadata: Dictionary = popup.get_item_metadata(item_id)
	if is_instance_valid(popup):
		popup.queue_free()
	var path: NodePath = metadata.get("path", NodePath())
	if path.is_empty():
		return
	var old_jobs: Array = provider.jobs.duplicate()
	var new_jobs: Array = provider.jobs.duplicate()
	var old_job = provider.jobs[job_index]
	if old_job == null:
		return
	var new_job = _duplicate_job(old_job)
	var values: Array = new_job.get(field_name).duplicate()
	if not values.has(path):
		values.append(path)
		new_job.set(field_name, values)
	new_jobs[job_index] = new_job
	var action_name := "Add %s" % ("Resource Node" if field_name == "resource_paths" else "Container")
	_apply_jobs_change(provider, old_jobs, new_jobs, action_name)


func _collect_matches(provider: Node, root: Node, target_script) -> Array:
	var matches: Array = []
	var provider_owner = provider.get_parent() as Node3D
	var provider_position: Vector3 = provider_owner.global_position if provider_owner != null else Vector3.ZERO
	for child in _collect_nodes_recursive(root):
		if not _matches_script(child, target_script):
			continue
		var node3d := child as Node3D
		if node3d == null:
			continue
		var distance: float = provider_position.distance_to(node3d.global_position)
		matches.append({
			"node": child,
			"path": provider.get_path_to(child),
			"distance": distance,
			"label": "%s - %.1fm - %s" % [_get_display_name(child), distance, provider.get_path_to(child)],
		})
	matches.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.get("distance", 0.0)) < float(b.get("distance", 0.0)))
	return matches


func _matches_script(node: Node, target_script) -> bool:
	return node != null and node.get_script() == target_script


func _collect_nodes_recursive(root: Node) -> Array:
	var nodes: Array = [root]
	for child in root.get_children():
		nodes.append_array(_collect_nodes_recursive(child))
	return nodes


func _get_display_name(node: Node) -> String:
	if node.has_method("get"):
		var label = node.get("display_name")
		if label != null and str(label) != "":
			return str(label)
	return node.name


func _duplicate_job(job):
	var duplicate = JOB_DEFINITION_SCRIPT.new()
	duplicate.display_name = job.display_name
	duplicate.job_id = job.job_id
	duplicate.algorithm_id = job.algorithm_id
	duplicate.slot_count = job.slot_count
	duplicate.pay_interval_seconds = job.pay_interval_seconds
	duplicate.pay_per_interval = job.pay_per_interval
	duplicate.carry_item_threshold = job.carry_item_threshold
	duplicate.output_mode = job.output_mode
	duplicate.resource_paths = job.resource_paths.duplicate()
	duplicate.container_paths = job.container_paths.duplicate()
	duplicate.requirements = job.requirements.duplicate()
	return duplicate


func _apply_jobs_change(provider: Node, old_jobs: Array, new_jobs: Array, action_name: String) -> void:
	var undo_redo := _plugin.get_undo_redo()
	undo_redo.create_action(action_name)
	undo_redo.add_do_property(provider, "jobs", new_jobs)
	undo_redo.add_undo_property(provider, "jobs", old_jobs)
	undo_redo.add_do_method(provider, "notify_property_list_changed")
	undo_redo.add_undo_method(provider, "notify_property_list_changed")
	undo_redo.commit_action()
