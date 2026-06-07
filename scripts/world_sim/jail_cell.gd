extends StaticBody3D

class_name JailCell

@export var display_name := "Jail Cell"
@export_range(0, 100, 1) var lock_difficulty := 0
@export var visual_scene: PackedScene
@export var visual_transform := Transform3D.IDENTITY
@export var collision_shape: Shape3D
@export var collision_transform := Transform3D.IDENTITY
@export var interaction_point_path := NodePath("InteractionPoint")
@export var prisoner_point_path := NodePath("PrisonerPoint")
@export var release_point_path := NodePath("ReleasePoint")


func _ready() -> void:
	add_to_group("jail_cell")
	_apply_collision_shape()
	_apply_visual_scene()


func get_interaction_position() -> Vector3:
	return _node_position_or_self(interaction_point_path)


func get_prisoner_position() -> Vector3:
	return _node_position_or_self(prisoner_point_path)


func get_release_position() -> Vector3:
	return _node_position_or_self(release_point_path)


func _node_position_or_self(path: NodePath) -> Vector3:
	var node := get_node_or_null(path) as Node3D
	return node.global_position if node != null else global_position


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
