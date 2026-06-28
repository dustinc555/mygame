@tool
extends StaticBody3D

class_name WorldProp

@export var display_name := "Prop"
@export var visual_scene: PackedScene:
	set(value):
		visual_scene = value
		_refresh_editor_preview()
@export var visual_transform := Transform3D.IDENTITY:
	set(value):
		visual_transform = value
		_refresh_editor_preview()
@export var collision_shapes: Array[Shape3D] = []:
	set(value):
		collision_shapes = value
		_refresh_editor_preview()
@export var collision_transforms: Array[Transform3D] = []:
	set(value):
		collision_transforms = value
		_refresh_editor_preview()

@onready var model_root: Node3D = $ModelRoot


func _ready() -> void:
	add_to_group("world_prop")
	_rebuild_collision_shapes()
	_rebuild_visual()


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		call_deferred("_refresh_editor_preview")


func _rebuild_collision_shapes() -> void:
	for child in get_children():
		if child is CollisionShape3D and child.name.begins_with("GeneratedCollisionShape3D"):
			remove_child(child)
			child.queue_free()
	for index in collision_shapes.size():
		var shape := collision_shapes[index]
		if shape == null:
			continue
		var collision_node := CollisionShape3D.new()
		collision_node.name = "GeneratedCollisionShape3D%d" % index
		collision_node.shape = shape
		if index < collision_transforms.size():
			collision_node.transform = collision_transforms[index]
		add_child(collision_node)
		if Engine.is_editor_hint():
			if owner != null:
				collision_node.owner = owner


func _rebuild_visual() -> void:
	if model_root == null:
		return
	for child in model_root.get_children():
		model_root.remove_child(child)
		child.queue_free()
	if visual_scene == null:
		return
	var visual_instance := visual_scene.instantiate()
	model_root.add_child(visual_instance)
	if Engine.is_editor_hint():
		if model_root.owner != null:
			visual_instance.owner = model_root.owner
	if visual_instance is Node3D:
		visual_instance.transform = visual_transform


func _refresh_editor_preview() -> void:
	if not is_inside_tree():
		return
	_rebuild_collision_shapes()
	_rebuild_visual()
