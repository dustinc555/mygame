@tool
extends StaticBody3D

class_name WorldContainer

signal inventory_changed
signal interaction_resolved(container, actor)

@export var display_name := "Container"
@export var furniture_type := FurnitureRules.Type.CONTAINER
@export var inventory_columns := 7
@export var inventory_rows := 5
@export var is_locked := false
## Arm's length: opening a container means standing at it, not across the room.
@export var interaction_distance := 1.6
@export var slot_distance := 1.3
@export var slot_count := 6
@export var owner_character_path: NodePath
@export var owner_faction_name := ""
@export var theft_value := 10
## Rummaging through a crate or barrel is loud: witnesses inside this radius
## contest the thief's stealing skill even when they cannot see the attempt.
@export var theft_noise_radius := 8.0
@export var starting_items: Array[InventoryStock] = []
@export var visual_scene: PackedScene:
	set(value):
		visual_scene = value
		_refresh_editor_preview()
@export var visual_transform := Transform3D.IDENTITY:
	set(value):
		visual_transform = value
		_refresh_editor_preview()
@export var collision_shape: Shape3D:
	set(value):
		collision_shape = value
		_refresh_editor_preview()
@export var collision_transform := Transform3D.IDENTITY:
	set(value):
		collision_transform = value
		_refresh_editor_preview()

var inventory
var _assigned_slots: Dictionary = {}
var _pending_actor_ids: Dictionary = {}

@onready var collision_shape_node: CollisionShape3D = $CollisionShape3D
@onready var model_root: Node3D = $ModelRoot


func _ready() -> void:
	if inventory == null:
		var inventory_data_script = load("res://features/inventory/sim/inventory_data.gd")
		inventory = inventory_data_script.new(inventory_columns, inventory_rows, 0.0, false)
		inventory.changed.connect(_on_inventory_changed)
		_seed_starting_inventory()
	add_to_group("world_container")
	add_to_group(FurnitureRules.FURNITURE_GROUP)
	_apply_collision_settings()
	_rebuild_visual()
	_sync_inventory_to_gecs()


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		call_deferred("_refresh_editor_preview")


func register_interactor(member: HumanoidCharacter) -> void:
	_get_slot_index(member)
	_pending_actor_ids[member.get_instance_id()] = true


func release_interactor(member: HumanoidCharacter) -> void:
	_pending_actor_ids.erase(member.get_instance_id())
	_assigned_slots.erase(member.get_instance_id())


func resolve_interaction(member: HumanoidCharacter) -> bool:
	if member == null:
		return false
	if is_locked:
		return false
	var actor_id: int = member.get_instance_id()
	if not _pending_actor_ids.has(actor_id):
		return false
	# Only this member's pending claim resolves — clearing everyone's made the
	# second member of a multi-select arrive to a silent no-op.
	_pending_actor_ids.erase(actor_id)
	interaction_resolved.emit(self, member)
	return true


func get_interaction_position(member: HumanoidCharacter) -> Vector3:
	var slot_index := _get_slot_index(member)
	var angle := TAU * float(slot_index) / float(max(slot_count, 1))
	var slot := global_position + Vector3(cos(angle), 0.0, sin(angle)) * slot_distance
	# Wall-hugging containers put ring slots inside walls or the container's
	# own navmesh carve; an off-mesh move target strands the actor short of
	# it forever. Hand out the nearest walkable point instead.
	return _clamped_to_navmesh(slot)


func _clamped_to_navmesh(point: Vector3) -> Vector3:
	if Engine.is_editor_hint() or not is_inside_tree():
		return point
	var map := get_world_3d().navigation_map
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return point
	return NavigationServer3D.map_get_closest_point(map, point)


func get_inventory_display_name() -> String:
	return display_name


func get_inventory_world_position() -> Vector3:
	return global_position


func shows_inventory_weight() -> bool:
	return false


func get_explicit_owner_character() -> HumanoidCharacter:
	return get_node_or_null(owner_character_path) as HumanoidCharacter


func get_owner_faction_name() -> String:
	if not owner_faction_name.is_empty():
		return owner_faction_name
	var owner_character := get_explicit_owner_character()
	return owner_character.faction_name if owner_character != null else ""


func get_theft_value() -> int:
	return theft_value


func get_theft_noise_radius() -> float:
	return theft_noise_radius


func _get_slot_index(member: HumanoidCharacter) -> int:
	var key: int = member.get_instance_id()
	if _assigned_slots.has(key):
		return _assigned_slots[key]

	var used: Array[int] = []
	for value in _assigned_slots.values():
		used.append(value)

	var best_slot := 0
	var best_distance := INF
	for slot_index in range(slot_count):
		if used.has(slot_index):
			continue
		var slot_position := _slot_position_from_index(slot_index)
		var distance: float = member.global_position.distance_squared_to(slot_position)
		if distance < best_distance:
			best_distance = distance
			best_slot = slot_index

	if best_distance == INF:
		for slot_index in range(slot_count):
			var slot_position := _slot_position_from_index(slot_index)
			var distance: float = member.global_position.distance_squared_to(slot_position)
			if distance < best_distance:
				best_distance = distance
				best_slot = slot_index

	_assigned_slots[key] = best_slot
	return best_slot


func _slot_position_from_index(slot_index: int) -> Vector3:
	var angle := TAU * float(slot_index) / float(max(slot_count, 1))
	return global_position + Vector3(cos(angle), 0.0, sin(angle)) * slot_distance


func _on_inventory_changed() -> void:
	inventory_changed.emit()
	_sync_inventory_to_gecs()


func _sync_inventory_to_gecs() -> void:
	if not is_inside_tree():
		return
	var bridge := get_tree().get_first_node_in_group("gecs_world_controller")
	if bridge != null and bridge.has_method("sync_world_container"):
		bridge.call("sync_world_container", self)


func _seed_starting_inventory() -> void:
	for stock in starting_items:
		if stock == null or stock.item_definition == null or stock.quantity <= 0:
			continue
		inventory.add_item_count(stock.item_definition, stock.quantity)


func _apply_collision_settings() -> void:
	if collision_shape_node == null:
		return
	if collision_shape != null:
		collision_shape_node.shape = collision_shape
	collision_shape_node.transform = collision_transform


func _rebuild_visual() -> void:
	if model_root == null:
		return
	for child in model_root.get_children():
		model_root.remove_child(child)
		child.queue_free()
	if visual_scene == null:
		return
	var visual_instance := visual_scene.instantiate()
	_strip_visual_collision(visual_instance)
	model_root.add_child(visual_instance)
	if Engine.is_editor_hint():
		var edited_root := get_tree().edited_scene_root
		if edited_root != null:
			visual_instance.owner = edited_root
	if visual_instance is Node3D:
		visual_instance.transform = visual_transform


## The wrapper's exported collision_shape is the container's single collision
## truth. Imported models (e.g. Quaternius gltf crates/barrels) may ship their
## own static bodies; left in, they double up physics and click collision and
## read as runtime-spawned geometry that dirties navmesh tiles at startup.
func _strip_visual_collision(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionObject3D:
			node.remove_child(child)
			child.free()
		else:
			_strip_visual_collision(child)


func _refresh_editor_preview() -> void:
	if not is_inside_tree():
		return
	_apply_collision_settings()
	_rebuild_visual()
