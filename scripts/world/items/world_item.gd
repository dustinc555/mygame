extends RigidBody3D

class_name WorldItem

const PICKUP_NOTICE := "I don't have enough room"
const GROUND_CLEARANCE := 0.015
const MIN_COLLIDER_SIZE := Vector3(0.08, 0.03, 0.08)

@export var item_definition: ItemDefinition:
	set(value):
		item_definition = value
		_rebuild_visual()
@export var quantity := 1:
	set(value):
		quantity = maxi(1, value)
@export var pickup_distance := 1.4
@export var owner_faction_name := "":
	set(value):
		owner_faction_name = value
		_refresh_label()
@export var theft_value := 10
@export var theft_noise_radius := 0.0
@export_range(0, 100, 1) var theft_difficulty := 25

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


func get_owner_faction_name() -> String:
	return owner_faction_name


func get_theft_value() -> int:
	return theft_value


func get_theft_noise_radius() -> float:
	return theft_noise_radius


func get_theft_difficulty() -> int:
	return theft_difficulty


func try_pickup(actor) -> bool:
	if actor == null or item_definition == null:
		return false
	var ownership_controller := _find_ownership_controller()
	if ownership_controller != null and ownership_controller.has_method("request_take_item") and not bool(ownership_controller.call("request_take_item", actor, self)):
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


func _find_ownership_controller() -> Node:
	for node in get_tree().get_nodes_in_group("ownership_controller"):
		return node
	var bootstrap := get_tree().current_scene.get_node_or_null("GameBootstrap") if get_tree().current_scene != null else null
	return bootstrap.get_node_or_null("OwnershipController") if bootstrap != null else null


func get_inventory_world_position() -> Vector3:
	return global_position


func place_on_ground_at(world_position: Vector3, stack_offset_meters: float = 0.0) -> float:
	return place_bottom_at(world_position, world_position.y + stack_offset_meters + GROUND_CLEARANCE)


func place_bottom_at(world_position: Vector3, bottom_y: float) -> float:
	var bounds := _calculate_local_mesh_bounds(model_root)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = false
	if bounds.size.length() <= 0.001:
		global_position = Vector3(world_position.x, bottom_y, world_position.z)
		return 0.0
	global_position = Vector3(
		world_position.x,
		bottom_y - bounds.position.y,
		world_position.z
	)
	return bounds.size.y


func get_visual_world_bounds() -> AABB:
	var bounds := _calculate_local_mesh_bounds(model_root)
	if bounds.size.length() <= 0.001:
		return AABB(global_position, Vector3.ZERO)
	return _transform_aabb(bounds, global_transform)


func get_visual_top_y() -> float:
	var bounds := get_visual_world_bounds()
	return bounds.position.y + bounds.size.y


func _show_pickup_failure(actor) -> void:
	if actor.has_method("show_world_speech"):
		actor.show_world_speech(PICKUP_NOTICE, 4.0)
	elif actor.has_method("show_world_notice"):
		actor.show_world_notice(PICKUP_NOTICE)


func _refresh_label() -> void:
	if label == null:
		return
	if item_definition == null:
		label.text = "Owned Item" if not owner_faction_name.is_empty() else "Item"
		return
	var item_label := item_definition.display_name if quantity <= 1 else "%s x%d" % [item_definition.display_name, quantity]
	label.text = "%s (Owned)" % item_label if not owner_faction_name.is_empty() else item_label


func _rebuild_visual() -> void:
	if model_root == null:
		return
	for child in model_root.get_children():
		model_root.remove_child(child)
		child.queue_free()
	if item_definition == null:
		_add_fallback_visual()
		_refresh_collision_from_visual()
		return
	var visual_scene := item_definition.world_scene
	if visual_scene == null:
		visual_scene = item_definition.equipped_scene
	if visual_scene == null:
		_add_fallback_visual()
		_refresh_collision_from_visual()
		return
	var visual_instance := visual_scene.instantiate()
	model_root.add_child(visual_instance)
	if visual_instance is Node3D:
		_normalize_visual(visual_instance as Node3D, item_definition.world_visual_height_meters)
	_refresh_collision_from_visual()


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


func _normalize_visual(visual_root: Node3D, target_height_meters: float = 0.0) -> void:
	var bounds := _calculate_local_mesh_bounds(visual_root)
	if bounds.size.length() <= 0.001:
		return
	var scale_dimension := bounds.size.y if target_height_meters > 0.0 else maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	if scale_dimension <= 0.001:
		return
	var target_dimension := target_height_meters if target_height_meters > 0.0 else 0.72
	var scale_factor := target_dimension / scale_dimension
	visual_root.scale = Vector3.ONE * scale_factor
	visual_root.position = Vector3(-bounds.get_center().x * scale_factor, -bounds.position.y * scale_factor + 0.05, -bounds.get_center().z * scale_factor)


func _refresh_collision_from_visual() -> void:
	if collision_shape_node == null or model_root == null:
		return
	var bounds := _calculate_local_mesh_bounds(model_root)
	if bounds.size.length() <= 0.001:
		collision_shape_node.disabled = true
		return
	var collision_size := Vector3(
		maxf(bounds.size.x, MIN_COLLIDER_SIZE.x),
		maxf(bounds.size.y, MIN_COLLIDER_SIZE.y),
		maxf(bounds.size.z, MIN_COLLIDER_SIZE.z)
	)
	var box := BoxShape3D.new()
	box.size = collision_size
	collision_shape_node.shape = box
	collision_shape_node.position = Vector3(
		bounds.get_center().x,
		bounds.position.y + collision_size.y * 0.5,
		bounds.get_center().z
	)
	collision_shape_node.rotation = Vector3.ZERO
	collision_shape_node.scale = Vector3.ONE
	collision_shape_node.disabled = false


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
