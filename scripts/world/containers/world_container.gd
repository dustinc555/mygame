extends StaticBody3D

class_name WorldContainer

const INVENTORY_DATA_SCRIPT = preload("res://scripts/items/inventory_data.gd")

@export var display_name := "Container"
@export var container_id := ""
@export_range(1, 64, 1) var inventory_columns := 10
@export_range(1, 64, 1) var inventory_rows := 6
@export_range(0.0, 10000.0, 1.0) var inventory_max_weight := 60.0
@export var is_locked := false
@export_range(0, 100, 1) var lock_difficulty := 0
@export_range(0.0, 20.0, 0.1) var interaction_distance := 2.0
@export_range(0.0, 20.0, 0.1) var slot_distance := 1.6
@export var cell_size := Vector2(24.0, 24.0)
@export var owner_faction_name := ""
@export var visual_scene: PackedScene
@export var visual_transform := Transform3D.IDENTITY
@export var collision_shape: Shape3D
@export var collision_transform := Transform3D.IDENTITY

var inventory


func _ready() -> void:
	add_to_group("world_container")
	_ensure_inventory()
	_apply_collision_shape()
	_apply_visual_scene()
	call_deferred("_sync_world_container_to_gecs")


func get_inventory_world_position() -> Vector3:
	return global_position


func get_container_id() -> String:
	if not container_id.strip_edges().is_empty():
		return container_id.strip_edges()
	return str(get_path()) if is_inside_tree() else str(get_instance_id())


func get_interaction_position(actor = null) -> Vector3:
	var actor_position := global_position + Vector3.FORWARD
	if actor is Node3D:
		actor_position = (actor as Node3D).global_position
	return get_interaction_position_for_actor("", actor_position)


func get_interaction_position_for_actor(_actor_id: String, actor_position: Vector3) -> Vector3:
	var direction := actor_position - global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		direction = Vector3.FORWARD
	return global_position + direction.normalized() * maxf(slot_distance, interaction_distance)


func get_interaction_distance() -> float:
	return maxf(interaction_distance, 0.05)


func _ensure_inventory() -> void:
	if inventory != null:
		return
	inventory = INVENTORY_DATA_SCRIPT.new(inventory_columns, inventory_rows, inventory_max_weight)


func _apply_collision_shape() -> void:
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		return
	if collision_shape != null:
		shape_node.shape = collision_shape
	shape_node.transform = collision_transform


func _apply_visual_scene() -> void:
	if visual_scene == null:
		return
	var model_root := get_node_or_null("ModelRoot") as Node3D
	if model_root == null or model_root.get_child_count() > 0:
		return
	var visual := visual_scene.instantiate()
	model_root.add_child(visual)
	if visual is Node3D:
		(visual as Node3D).transform = visual_transform


func _sync_world_container_to_gecs() -> void:
	if not is_inside_tree():
		return
	var bridge := get_tree().get_first_node_in_group("gecs_world_controller")
	if bridge != null and bridge.has_method("sync_world_container"):
		bridge.call("sync_world_container", self)
