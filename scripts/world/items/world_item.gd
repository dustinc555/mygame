extends StaticBody3D

class_name WorldItem

const PICKUP_NOTICE := "I don't have enough room"

@export var item_definition: ItemDefinition:
	set(value):
		item_definition = value
		_rebuild_visual()
@export var quantity := 1:
	set(value):
		quantity = maxi(1, value)
@export var pickup_distance := 1.4

@onready var collision_shape_node: CollisionShape3D = $CollisionShape3D
@onready var model_root: Node3D = $ModelRoot
@onready var label: Label3D = $Label3D


func _ready() -> void:
	add_to_group("world_item")
	_rebuild_visual()
	_refresh_label()


func setup(definition: ItemDefinition, amount: int = 1) -> void:
	item_definition = definition
	quantity = amount
	_rebuild_visual()
	_refresh_label()


func get_pickup_position(_actor) -> Vector3:
	return global_position


func try_pickup(actor) -> bool:
	if actor == null or item_definition == null:
		return false
	var actor_inventory = actor.inventory if actor.get("inventory") != null else null
	if actor_inventory == null or not actor_inventory.can_add_item_count(item_definition, quantity):
		_show_pickup_failure(actor)
		return false
	if not actor_inventory.add_item_count(item_definition, quantity):
		_show_pickup_failure(actor)
		return false
	queue_free()
	return true


func get_inventory_world_position() -> Vector3:
	return global_position


func _show_pickup_failure(actor) -> void:
	if actor.has_method("show_world_speech"):
		actor.show_world_speech(PICKUP_NOTICE, 4.0)
	elif actor.has_method("show_world_notice"):
		actor.show_world_notice(PICKUP_NOTICE)


func _refresh_label() -> void:
	if label == null:
		return
	if item_definition == null:
		label.text = "Item"
		return
	label.text = item_definition.display_name if quantity <= 1 else "%s x%d" % [item_definition.display_name, quantity]


func _rebuild_visual() -> void:
	if model_root == null:
		return
	for child in model_root.get_children():
		model_root.remove_child(child)
		child.queue_free()
	if item_definition == null:
		_add_fallback_visual()
		return
	var visual_scene := item_definition.world_scene
	if visual_scene == null:
		visual_scene = item_definition.equipped_scene
	if visual_scene == null:
		_add_fallback_visual()
		return
	var visual_instance := visual_scene.instantiate()
	model_root.add_child(visual_instance)
	if visual_instance is Node3D:
		_normalize_visual(visual_instance as Node3D)


func _add_fallback_visual() -> void:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.18, 0.5)
	mesh_instance.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.72, 0.54, 0.28, 1.0)
	material.roughness = 0.9
	mesh_instance.material_override = material
	mesh_instance.position.y = 0.09
	model_root.add_child(mesh_instance)


func _normalize_visual(visual_root: Node3D) -> void:
	var bounds := _calculate_local_mesh_bounds(visual_root)
	if bounds.size.length() <= 0.001:
		return
	var max_dimension := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	if max_dimension <= 0.001:
		return
	var scale_factor := 0.72 / max_dimension
	visual_root.scale = Vector3.ONE * scale_factor
	visual_root.position = Vector3(-bounds.get_center().x * scale_factor, -bounds.position.y * scale_factor + 0.05, -bounds.get_center().z * scale_factor)


func _calculate_local_mesh_bounds(root: Node) -> AABB:
	var result := {
		"has_bounds": false,
		"bounds": AABB(),
	}
	_accumulate_local_mesh_bounds(root, Transform3D.IDENTITY, result)
	return result["bounds"]


func _accumulate_local_mesh_bounds(node: Node, parent_transform: Transform3D, result: Dictionary) -> void:
	var local_transform := parent_transform
	if node is Node3D:
		local_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_bounds := _transform_aabb((node as MeshInstance3D).mesh.get_aabb(), local_transform)
		if result["has_bounds"]:
			result["bounds"] = (result["bounds"] as AABB).merge(mesh_bounds)
		else:
			result["bounds"] = mesh_bounds
			result["has_bounds"] = true
	for child in node.get_children():
		_accumulate_local_mesh_bounds(child, local_transform, result)


func _transform_aabb(bounds: AABB, transform: Transform3D) -> AABB:
	var first := true
	var transformed_bounds := AABB()
	for x in [bounds.position.x, bounds.position.x + bounds.size.x]:
		for y in [bounds.position.y, bounds.position.y + bounds.size.y]:
			for z in [bounds.position.z, bounds.position.z + bounds.size.z]:
				var point := transform * Vector3(x, y, z)
				if first:
					transformed_bounds = AABB(point, Vector3.ZERO)
					first = false
				else:
					transformed_bounds = transformed_bounds.expand(point)
	return transformed_bounds
