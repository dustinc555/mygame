extends Node

const SERVICE_ID := &"world_item_projection"
const WORLD_ITEM_SCENE_PATH := "res://features/world/projection/items/world_item.tscn"

var _root_scene: Node
var _lifecycle: Node
var _gecs: Node
var _projections_by_stack_id: Dictionary = {}
var _authored_bootstrap_pending := true


func initialize(context: BootstrapContext) -> void:
	_root_scene = context.root_scene
	_lifecycle = context.require(&"item_lifecycle")
	_gecs = context.require(&"gecs_world")
	_lifecycle.item_location_changed.connect(_on_item_location_changed)
	_lifecycle.item_metadata_changed.connect(_on_item_metadata_changed)
	_gecs.world_reindexed.connect(_on_world_reindexed)
	_finish_authored_bootstrap.call_deferred()


func _finish_authored_bootstrap() -> void:
	# Scene-authored loose/placed items are initial world inputs, not perpetual
	# seeds. Deferred startup also lets parent _ready finish configuring them.
	if _authored_bootstrap_pending:
		_authored_bootstrap_pending = false
		_index_live_projections()
		for stack_id in _projections_by_stack_id.keys():
			var item := _projection(str(stack_id))
			if item == null or item.is_queued_for_deletion() or not _root_scene.is_ancestor_of(item):
				continue
			if item.has_meta("item_projection_bridge_realized") or str(item.get("location_kind")) not in ["world_loose", "world_placed"]:
				continue
			if not _gecs.get_item_stack(str(stack_id)).is_empty() or _lifecycle.has_pending_world_stack(str(stack_id)):
				continue
			var definition := item.get("item_definition") as ItemDefinition
			if definition == null or not item is Node3D:
				continue
			_lifecycle.submit_world_stack({
				"stack_id": str(stack_id), "container_id": "world", "owner_actor_id": "",
				"owner_faction_name": str(item.get("owner_faction_name")),
				"item_definition_path": definition.resource_path, "count": int(item.get("quantity")),
				"grid_position": Vector2i.ZERO,
				"contained_item_counts": (item.get("contained_item_counts") as Dictionary).duplicate(true),
				"metadata": (item.get("item_metadata") as Dictionary).duplicate(true),
				"location_kind": str(item.get("location_kind")),
				"world_transform": (item as Node3D).global_transform,
				"placement_host_id": str(item.get("placement_host_id")),
				"placement_slot_id": str(item.get("placement_slot_id")),
				"location_settlement_id": str(item.get("location_settlement_id")),
			})
	_reconcile()


func register_projection(item: Node) -> void:
	if item == null or bool(item.get("stock_projection")) or str(item.get("stack_id")).strip_edges().is_empty():
		return
	_projections_by_stack_id[str(item.get("stack_id"))] = weakref(item)


func unregister_projection(item: Node) -> void:
	if item == null or str(item.get("stack_id")).strip_edges().is_empty():
		return
	var stack_id := str(item.get("stack_id"))
	var projection_ref := _projections_by_stack_id.get(stack_id) as WeakRef
	if projection_ref != null and projection_ref.get_ref() == item:
		_projections_by_stack_id.erase(stack_id)


func _on_world_reindexed() -> void:
	# Loading before the deferred bootstrap must not reintroduce absent items.
	_authored_bootstrap_pending = false
	_reconcile.call_deferred()


func _on_item_location_changed(stack_id: String, record: Dictionary) -> void:
	var kind := str(record.get("location_kind", ""))
	if kind == "world_loose" or kind == "world_placed":
		_realize_or_update(record)
	elif kind == "inventory" or kind == "equipment":
		_remove_projection(stack_id)


func _on_item_metadata_changed(stack_id: String, metadata: Dictionary) -> void:
	var item := _projection(stack_id)
	if item != null:
		item.set("item_metadata", metadata.duplicate(true))


func _reconcile() -> void:
	if _lifecycle == null:
		return
	_index_live_projections()
	var records_by_id: Dictionary = {}
	for record in _gecs.get_inventory_stacks():
		var stack_id := str(record.get("stack_id", ""))
		if stack_id.is_empty():
			continue
		records_by_id[stack_id] = record
		var kind := str(record.get("location_kind", ""))
		if kind == "world_loose" or kind == "world_placed":
			_realize_or_update(record)
	for stack_id_value in _projections_by_stack_id.keys():
		var stack_id := str(stack_id_value)
		var item := _projection(stack_id)
		if item == null:
			_projections_by_stack_id.erase(stack_id)
			continue
		var record := records_by_id.get(stack_id, {}) as Dictionary
		if record.is_empty() and _lifecycle.has_pending_world_stack(stack_id):
			continue
		if record.is_empty() or str(record.get("location_kind", "")) in ["inventory", "equipment"]:
			item.queue_free()


func _index_live_projections() -> void:
	_projections_by_stack_id.clear()
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group("world_item"):
		register_projection(node)


func _realize_or_update(record: Dictionary) -> void:
	var stack_id := str(record.get("stack_id", ""))
	if stack_id.is_empty():
		return
	var item: Node = _projection(stack_id)
	if item != null:
		_apply_record(item, record)
		return
	var definition := load(str(record.get("item_definition_path", ""))) as ItemDefinition
	if definition == null:
		push_error("WorldItemProjectionBridge: missing item definition for stack '%s'" % stack_id)
		return
	var world_item_scene := load(WORLD_ITEM_SCENE_PATH) as PackedScene
	item = world_item_scene.instantiate() if world_item_scene != null else null
	if not (item is Node3D):
		if item != null:
			item.free()
		return
	item.call("apply_lifecycle_record", record)
	var parent := _world_parent()
	if parent == null:
		item.free()
		return
	var world_transform: Transform3D = record.get("world_transform", Transform3D.IDENTITY)
	(item as Node3D).transform = (parent as Node3D).global_transform.affine_inverse() * world_transform if parent is Node3D else world_transform
	item.set_meta("item_projection_bridge_realized", true)
	parent.add_child(item)
	register_projection(item)


func _apply_record(item: Node, record: Dictionary) -> void:
	item.call("apply_lifecycle_record", record)


func _remove_projection(stack_id: String) -> void:
	var item := _projection(stack_id)
	if item != null:
		item.queue_free()


func _projection(stack_id: String) -> Node:
	var projection_ref := _projections_by_stack_id.get(stack_id) as WeakRef
	if projection_ref == null:
		return null
	var item := projection_ref.get_ref() as Node
	if item == null or not is_instance_valid(item):
		_projections_by_stack_id.erase(stack_id)
		return null
	return item


func _world_parent() -> Node:
	var current_scene := get_tree().current_scene if get_tree() != null else null
	return current_scene if current_scene != null else _root_scene
