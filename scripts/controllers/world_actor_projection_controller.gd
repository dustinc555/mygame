extends Node

class_name WorldActorProjectionController

const WORLD_ACTOR_PROJECTION_SCRIPT := preload("res://scripts/projection/world_actor_projection.gd")
const HUMANOID_BODY_PROJECTION_SCRIPT := preload("res://scripts/projection/humanoid_body_projection.gd")
const PLACEHOLDER_BODY_PROJECTION_SCRIPT := preload("res://scripts/projection/placeholder_body_projection.gd")

@export var auto_project := true
@export_range(0.05, 5.0, 0.05) var projection_update_interval_seconds := 0.25
@export var projection_root_name := "WorldActorProjections"

var root_scene: Node
var _projection_root: Node3D
var _projection_by_actor_id: Dictionary = {}
var _initialized := false
var _update_elapsed := 0.0
var _unsupported_projection_kinds: Dictionary = {}


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
	if not _try_initialize():
		return
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_population_records"):
		return
	var records: Dictionary = bridge.call("get_population_records")
	var equipment_by_actor := _equipment_slots_by_actor(bridge, records)
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


func _equipment_slots_by_actor(bridge: Node, records: Dictionary) -> Dictionary:
	var result := {}
	if bridge != null and bridge.has_method("get_equipment_slots"):
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
	for actor_id_value in records.keys():
		var record = records[actor_id_value]
		if not (record is Dictionary):
			continue
		var actor_id := str((record as Dictionary).get("actor_id", actor_id_value)).strip_edges()
		var record_slots = (record as Dictionary).get("equipment_slots", {})
		if actor_id.is_empty() or not (record_slots is Dictionary):
			continue
		var actor_slots: Dictionary = result.get(actor_id, {})
		for slot_name in (record_slots as Dictionary).keys():
			if not actor_slots.has(str(slot_name)):
				actor_slots[str(slot_name)] = str((record_slots as Dictionary)[slot_name])
		result[actor_id] = actor_slots
	return result


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
