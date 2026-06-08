extends Node

class_name WorldActorProjectionController

const WORLD_ACTOR_PROJECTION_SCRIPT := preload("res://scripts/projection/world_actor_projection.gd")
const HUMANOID_BODY_PROJECTION_SCRIPT := preload("res://scripts/projection/humanoid_body_projection.gd")
const PLACEHOLDER_BODY_PROJECTION_SCRIPT := preload("res://scripts/projection/placeholder_body_projection.gd")

@export var auto_project := true
@export_range(0.05, 5.0, 0.05) var projection_update_interval_seconds := 0.25
@export var projection_root_name := "WorldActorProjections"
@export var performance_logging_enabled := false
@export_range(0.1, 10.0, 0.1) var performance_log_interval_seconds := 1.0
@export_range(0.0, 50000.0, 100.0) var performance_log_threshold_usec := 1000.0

var root_scene: Node
var _projection_root: Node3D
var _projection_by_actor_id: Dictionary = {}
var _initialized := false
var _update_elapsed := 0.0
var _unsupported_projection_kinds: Dictionary = {}
var _equipment_slots_cache_by_actor_id: Dictionary = {}
var _equipment_slots_cache_dirty := true
var _equipment_signal_bridge: Node
var _perf_log_next_msec_by_label: Dictionary = {}


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	_initialized = false
	_try_initialize()


func _ready() -> void:
	add_to_group("world_actor_projection_controller")


func _process(delta: float) -> void:
	if not auto_project or not _initialized:
		return
	_update_elapsed += delta
	if _update_elapsed < projection_update_interval_seconds:
		return
	_update_elapsed = 0.0
	sync_projections()


func sync_projections() -> void:
	var started_at_usec := Time.get_ticks_usec() if performance_logging_enabled else 0
	if not _try_initialize():
		return
	var bridge := _get_gecs_world()
	if bridge == null:
		return
	var records := _get_population_records_core(bridge)
	var equipment_by_actor := _equipment_slots_by_actor(bridge)
	var expected_actor_ids := {}
	for actor_id_value in records.keys():
		var record_value = records[actor_id_value]
		if not (record_value is Dictionary):
			continue
		var record: Dictionary = record_value
		var actor_id := str(record.get("actor_id", actor_id_value)).strip_edges()
		if actor_id.is_empty():
			continue
		var projection_kind := _projection_kind_for_record(record)
		if not can_project_kind(projection_kind):
			_note_unsupported_kind(projection_kind)
			_remove_projection(actor_id)
			continue
		expected_actor_ids[actor_id] = true
		project_record_snapshot(record, equipment_by_actor.get(actor_id, {}))
	_remove_stale_projections(expected_actor_ids)
	_log_perf_duration("projection.sync_projections", started_at_usec, {"records": records.size(), "projections": _projection_by_actor_id.size()})


func project_record_snapshot(record: Dictionary, equipment_slots: Dictionary = {}, combat_state: Dictionary = {}) -> Node:
	if not _try_initialize() or record.is_empty():
		return null
	var actor_id := str(record.get("actor_id", record.get("stable_id", ""))).strip_edges()
	if actor_id.is_empty():
		return null
	var projection_kind := _projection_kind_for_record(record)
	if not can_project_kind(projection_kind):
		_note_unsupported_kind(projection_kind)
		return null
	var projection := _get_or_create_projection(actor_id, projection_kind)
	if projection == null:
		return null
	projection.apply_projection_snapshot(record, equipment_slots, combat_state)
	return projection


func can_project_kind(projection_kind: String) -> bool:
	return _body_script_for_kind(projection_kind) != null


func get_projection_for_actor(actor_id: String) -> Node:
	var projection = _projection_by_actor_id.get(actor_id)
	return projection as Node if projection != null and is_instance_valid(projection) else null


func get_projection_count() -> int:
	return _projection_by_actor_id.size()


func get_projection_counts_by_kind() -> Dictionary:
	var counts := {}
	for projection in _projection_by_actor_id.values():
		if projection == null or not is_instance_valid(projection):
			continue
		var kind := str((projection as Node).get("projection_kind"))
		counts[kind] = int(counts.get(kind, 0)) + 1
	return counts


func get_unsupported_projection_kinds() -> Dictionary:
	return _unsupported_projection_kinds.duplicate()


func _try_initialize() -> bool:
	if _initialized:
		return true
	if root_scene == null:
		root_scene = get_parent()
	if root_scene == null or not is_inside_tree():
		return false
	_projection_root = root_scene.get_node_or_null(projection_root_name) as Node3D
	if _projection_root == null:
		_projection_root = Node3D.new()
		_projection_root.name = projection_root_name
		root_scene.add_child(_projection_root)
	_initialized = true
	return true


func _get_or_create_projection(actor_id: String, projection_kind: String) -> Node:
	var existing := get_projection_for_actor(actor_id)
	if existing != null and str(existing.get("projection_kind")) == projection_kind:
		return existing
	_remove_projection(actor_id)
	var body_script := _body_script_for_kind(projection_kind)
	if body_script == null:
		return null
	var projection := WORLD_ACTOR_PROJECTION_SCRIPT.new() as Node
	_projection_root.add_child(projection)
	projection.setup(actor_id, projection_kind, body_script)
	_projection_by_actor_id[actor_id] = projection
	return projection


func _remove_stale_projections(expected_actor_ids: Dictionary) -> void:
	var existing_ids := _projection_by_actor_id.keys()
	for actor_id_value in existing_ids:
		var actor_id := str(actor_id_value)
		if not expected_actor_ids.has(actor_id):
			_remove_projection(actor_id)


func _remove_projection(actor_id: String) -> void:
	var projection = _projection_by_actor_id.get(actor_id)
	if projection != null and is_instance_valid(projection):
		(projection as Node).queue_free()
	_projection_by_actor_id.erase(actor_id)


func _equipment_slots_by_actor(bridge: Node) -> Dictionary:
	_bind_equipment_cache_signal(bridge)
	if _equipment_slots_cache_dirty:
		_equipment_slots_cache_by_actor_id = _load_equipment_slots_by_actor(bridge)
		_equipment_slots_cache_dirty = false
	return _equipment_slots_cache_by_actor_id


func _load_equipment_slots_by_actor(bridge: Node) -> Dictionary:
	var result := {}
	if bridge == null or not bridge.has_method("get_equipment_slots"):
		return result
	for slot in bridge.call("get_equipment_slots"):
		if not (slot is Dictionary):
			continue
		var actor_id := str((slot as Dictionary).get("actor_id", "")).strip_edges()
		var slot_name := str((slot as Dictionary).get("slot_name", "")).strip_edges()
		var item_path := str((slot as Dictionary).get("item_definition_path", "")).strip_edges()
		if actor_id.is_empty() or slot_name.is_empty() or item_path.is_empty():
			continue
		var actor_slots: Dictionary = result.get(actor_id, {})
		actor_slots[slot_name] = item_path
		result[actor_id] = actor_slots
	return result


func _bind_equipment_cache_signal(bridge: Node) -> void:
	if bridge == null or bridge == _equipment_signal_bridge or not bridge.has_signal("inventory_state_changed"):
		return
	var callable := Callable(self, "_on_equipment_cache_changed")
	if bridge.is_connected("inventory_state_changed", callable):
		_equipment_signal_bridge = bridge
		return
	bridge.connect("inventory_state_changed", callable)
	_equipment_signal_bridge = bridge


func _on_equipment_cache_changed(_result: Dictionary = {}) -> void:
	_equipment_slots_cache_dirty = true


func _projection_kind_for_record(record: Dictionary) -> String:
	var explicit_kind := str(record.get("projection_kind", "")).strip_edges()
	if not explicit_kind.is_empty():
		return explicit_kind
	var appearance = record.get("appearance", {})
	if appearance is Dictionary and (not str((appearance as Dictionary).get("body_archetype", "")).is_empty() or int((appearance as Dictionary).get("visual_body_type", 0)) > 0):
		return "humanoid"
	return ""


func _body_script_for_kind(projection_kind: String) -> Script:
	match projection_kind:
		"humanoid":
			return HUMANOID_BODY_PROJECTION_SCRIPT
		"animal_placeholder", "robot_placeholder":
			return PLACEHOLDER_BODY_PROJECTION_SCRIPT
	return null


func _note_unsupported_kind(projection_kind: String) -> void:
	var key := projection_kind if not projection_kind.is_empty() else "<empty>"
	_unsupported_projection_kinds[key] = int(_unsupported_projection_kinds.get(key, 0)) + 1


func _get_gecs_world() -> Node:
	if not is_inside_tree():
		return null
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("GecsWorldController")
		if local != null:
			return local
	var existing := get_tree().get_first_node_in_group("gecs_world_controller")
	if existing != null and (parent_node == null or existing.get_parent() == parent_node):
		return existing
	return null


func _get_population_records_core(bridge: Node) -> Dictionary:
	if bridge.has_method("get_population_records_core"):
		var core_records = bridge.call("get_population_records_core")
		return core_records if core_records is Dictionary else {}
	if bridge.has_method("get_population_records"):
		var records = bridge.call("get_population_records")
		return records if records is Dictionary else {}
	return {}


func _log_perf_duration(label: String, started_at_usec: int, metadata: Dictionary = {}) -> void:
	if not performance_logging_enabled or started_at_usec <= 0:
		return
	var elapsed_usec := int(Time.get_ticks_usec() - started_at_usec)
	if float(elapsed_usec) < performance_log_threshold_usec:
		return
	var now_msec := Time.get_ticks_msec()
	var next_msec := int(_perf_log_next_msec_by_label.get(label, 0))
	if now_msec < next_msec:
		return
	_perf_log_next_msec_by_label[label] = now_msec + int(performance_log_interval_seconds * 1000.0)
	var suffix := ""
	for key in metadata.keys():
		suffix += " %s=%s" % [str(key), str(metadata[key])]
	print("PERF %s %.3fms%s" % [label, float(elapsed_usec) / 1000.0, suffix])
