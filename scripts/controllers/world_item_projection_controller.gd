extends Node

class_name WorldItemProjectionController

const WORLD_ITEM_SCENE := preload("res://scenes/world/items/world_item.tscn")

@export var auto_project := true
@export_range(0.05, 5.0, 0.05) var projection_update_interval_seconds := 0.25
@export var projection_root_name := "WorldItemProjections"

var root_scene: Node
var _projection_root: Node3D
var _projection_by_stack_id: Dictionary = {}
var _signature_by_stack_id: Dictionary = {}
var _item_definition_by_path: Dictionary = {}
var _initialized := false
var _update_elapsed := 0.0


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	_initialized = false
	_try_initialize()


func _ready() -> void:
	add_to_group("world_item_projection_controller")


func _process(delta: float) -> void:
	if not auto_project or not _initialized:
		return
	_update_elapsed += delta
	if _update_elapsed < projection_update_interval_seconds:
		return
	_update_elapsed = 0.0
	sync_world_items()


func sync_world_items() -> void:
	if not _try_initialize():
		return
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("get_inventory_stacks"):
		return
	var expected_stack_ids := {}
	for stack in bridge.call("get_inventory_stacks", "world"):
		if not (stack is Dictionary):
			continue
		var stack_id := str((stack as Dictionary).get("stack_id", "")).strip_edges()
		var item_path := str((stack as Dictionary).get("item_definition_path", "")).strip_edges()
		if stack_id.is_empty() or item_path.is_empty():
			continue
		expected_stack_ids[stack_id] = true
		var projection := _get_or_create_projection(stack_id)
		var signature := _stack_signature(stack as Dictionary)
		if projection != null and str(_signature_by_stack_id.get(stack_id, "")) == signature:
			continue
		if projection != null and projection.has_method("apply_stack_snapshot"):
			var projected_stack: Dictionary = (stack as Dictionary).duplicate(true)
			projected_stack["item_definition_resource"] = _item_definition_for_path(item_path)
			projection.call("apply_stack_snapshot", projected_stack)
			_signature_by_stack_id[stack_id] = signature
	_remove_stale_projections(expected_stack_ids)


func get_projection_for_stack(stack_id: String) -> Node:
	var projection = _projection_by_stack_id.get(stack_id)
	return projection as Node if projection != null and is_instance_valid(projection) else null


func get_projection_count() -> int:
	return _projection_by_stack_id.size()


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


func _get_or_create_projection(stack_id: String) -> Node:
	var existing := get_projection_for_stack(stack_id)
	if existing != null:
		return existing
	var projection := WORLD_ITEM_SCENE.instantiate()
	_projection_root.add_child(projection)
	projection.set("item_stack_id", stack_id)
	projection.set("gecs_import_enabled", false)
	_projection_by_stack_id[stack_id] = projection
	return projection


func _remove_stale_projections(expected_stack_ids: Dictionary) -> void:
	var existing_ids := _projection_by_stack_id.keys()
	for stack_id_value in existing_ids:
		var stack_id := str(stack_id_value)
		if expected_stack_ids.has(stack_id):
			continue
		var projection = _projection_by_stack_id.get(stack_id)
		if projection != null and is_instance_valid(projection):
			(projection as Node).queue_free()
		_projection_by_stack_id.erase(stack_id)
		_signature_by_stack_id.erase(stack_id)


func _stack_signature(stack: Dictionary) -> String:
	return "%s|%s|%d|%s|%s|%s|%s" % [
		str(stack.get("stack_id", "")),
		str(stack.get("item_definition_path", "")),
		int(stack.get("count", 1)),
		str(stack.get("contained_item_counts", {})),
		str(stack.get("metadata", {})),
		str(stack.get("world_position", Vector3.ZERO)),
		str(stack.get("world_position_initialized", false)),
	]


func _item_definition_for_path(item_path: String) -> ItemDefinition:
	if item_path.is_empty():
		return null
	var cached = _item_definition_by_path.get(item_path)
	if cached is ItemDefinition:
		return cached
	var definition := load(item_path) as ItemDefinition
	if definition != null:
		_item_definition_by_path[item_path] = definition
	return definition


func _get_gecs_world() -> Node:
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("GecsWorldController")
		if local != null:
			return local
	return get_tree().get_first_node_in_group("gecs_world_controller") if is_inside_tree() else null
