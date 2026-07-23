extends RigidBody3D

class_name WorldItem

const PICKUP_NOTICE := "I don't have enough room"
const GROUND_CLEARANCE := 0.015
const MIN_COLLIDER_SIZE := Vector3(0.08, 0.03, 0.08)

static var _left_alt_item_labels_visible := false

@export var stack_id := ""
@export var stock_projection := false
@export var stock_source_settlement_id := ""
@export var item_definition: ItemDefinition:
	set(value):
		item_definition = value
		_rebuild_visual()
@export var quantity := 1:
	set(value):
		quantity = maxi(1, value)
@export var contained_item_counts: Dictionary = {}:
	set(value):
		contained_item_counts = value.duplicate(true)
		_refresh_label()
@export var item_metadata: Dictionary = {}:
	set(value):
		item_metadata = value.duplicate(true)
		_refresh_label()
@export var pickup_distance := 1.4
@export var owner_faction_name := "":
	set(value):
		owner_faction_name = value
		_refresh_label()
@export var theft_value := 10
## Pocketing an owned item makes some noise: witnesses inside this radius
## contest the thief's stealing skill even when they cannot see the grab.
@export var theft_noise_radius := 4.0
@export_range(0, 100, 1) var theft_difficulty := 25
@export_enum("world_loose", "world_placed", "tabletop_slot") var location_kind := "world_loose"
@export var placement_host_id := ""
@export var placement_slot_id := ""
@export var location_settlement_id := ""

## Matches OwnershipController.STEAL_ACTION_COLOR — owned items read red so
## the player knows grabbing them is theft before committing.
const OWNED_LABEL_COLOR := Color(0.92, 0.34, 0.30, 1.0)

@onready var collision_shape_node: CollisionShape3D = $CollisionShape3D
@onready var model_root: Node3D = $ModelRoot
@onready var label: Label3D = $Label3D


func _ready() -> void:
	if stack_id.is_empty():
		stack_id = InventoryData.create_stack_id()
	add_to_group("world_item")
	if not sleeping_state_changed.is_connected(_on_sleeping_state_changed):
		sleeping_state_changed.connect(_on_sleeping_state_changed)
	var projection_bridge := BootstrapContext.service(&"world_item_projection")
	if projection_bridge != null and projection_bridge.has_method("register_projection"):
		projection_bridge.call("register_projection", self)
	_rebuild_visual()
	_refresh_label()


func _exit_tree() -> void:
	var projection_bridge := BootstrapContext.service(&"world_item_projection")
	if projection_bridge != null and projection_bridge.has_method("unregister_projection"):
		projection_bridge.call("unregister_projection", self)


func setup(definition: ItemDefinition, amount: int = 1, item_contained_item_counts: Dictionary = {}, item_stack_id := "") -> void:
	if not item_stack_id.is_empty():
		stack_id = item_stack_id
	elif stack_id.is_empty():
		stack_id = InventoryData.create_stack_id()
	item_definition = definition
	quantity = amount
	contained_item_counts = item_contained_item_counts.duplicate(true)
	_rebuild_visual()
	_refresh_label()


func apply_lifecycle_record(record: Dictionary) -> void:
	stack_id = str(record.get("stack_id", ""))
	item_definition = load(str(record.get("item_definition_path", ""))) as ItemDefinition
	quantity = maxi(1, int(record.get("count", 1)))
	contained_item_counts = (record.get("contained_item_counts", {}) as Dictionary).duplicate(true)
	item_metadata = (record.get("metadata", {}) as Dictionary).duplicate(true)
	location_kind = str(record.get("location_kind", "world_loose"))
	placement_host_id = str(record.get("placement_host_id", ""))
	placement_slot_id = str(record.get("placement_slot_id", ""))
	location_settlement_id = str(record.get("location_settlement_id", ""))
	if is_inside_tree():
		global_transform = record.get("world_transform", global_transform)
	if location_kind == "world_placed":
		freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		freeze = true
		gravity_scale = 0.0
	else:
		freeze = false
		gravity_scale = 1.0


func _process(_delta: float) -> void:
	if _left_alt_item_labels_visible and not Input.is_key_pressed(KEY_ALT):
		_left_alt_item_labels_visible = false
	_refresh_label_visibility()


func _on_sleeping_state_changed() -> void:
	if sleeping and location_kind == "world_loose":
		var lifecycle := BootstrapContext.service(ItemLifecycleController.SERVICE_ID) as ItemLifecycleController
		if lifecycle != null:
			lifecycle.submit_world_loose(stack_id, global_transform, location_settlement_id)


func _input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or key_event.keycode != KEY_ALT or key_event.echo:
		return
	if key_event.pressed:
		if key_event.location == KEY_LOCATION_LEFT:
			_left_alt_item_labels_visible = true
	elif key_event.location == KEY_LOCATION_LEFT or not Input.is_key_pressed(KEY_ALT):
		_left_alt_item_labels_visible = false
	_refresh_label_visibility()


func get_pickup_position(actor) -> Vector3:
	var tabletop_provider := _find_tabletop_pickup_provider()
	if tabletop_provider != null and tabletop_provider.has_method("get_tabletop_pickup_position"):
		var pickup_position = tabletop_provider.call("get_tabletop_pickup_position", self, actor)
		if pickup_position is Vector3:
			return pickup_position
	return global_position


func is_pickup_reachable_from(actor, actor_position: Vector3, reach_distance: float) -> bool:
	var tabletop_provider := _find_tabletop_pickup_provider()
	if tabletop_provider != null and tabletop_provider.has_method("is_tabletop_item_reachable_from"):
		return bool(tabletop_provider.call("is_tabletop_item_reachable_from", self, actor, actor_position, reach_distance))
	return actor_position.distance_to(global_position) <= maxf(reach_distance, pickup_distance)


func _find_tabletop_pickup_provider() -> Node:
	if not has_meta("tabletop_slot"):
		return null
	var current := get_parent()
	while current != null:
		if current.has_method("get_tabletop_pickup_position"):
			return current
		current = current.get_parent()
	return null


## Explicit stamp wins; otherwise anything sitting inside a facility (shelf
## stock, tabletop props) belongs to the facility owner automatically.
func get_owner_faction_name() -> String:
	if not owner_faction_name.is_empty():
		return owner_faction_name
	var facility := _find_owning_facility()
	return str(facility.call("get_property_owner_faction")) if facility != null else ""


func get_explicit_owner_character() -> HumanoidCharacter:
	var facility := _find_owning_facility()
	return facility.call("get_property_owner_character") as HumanoidCharacter if facility != null else null


func _find_owning_facility() -> Node:
	var current := get_parent()
	while current != null:
		if current.has_method("get_property_owner_faction"):
			return current
		current = current.get_parent()
	return null


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
	var pickup_metadata := item_metadata.duplicate(true)
	if ownership_controller != null and ownership_controller.has_method("get_take_item_metadata"):
		pickup_metadata = ownership_controller.call("get_take_item_metadata", actor, self, pickup_metadata) as Dictionary
	var actor_inventory = actor.inventory if actor.get("inventory") != null else null
	if actor_inventory == null:
		_show_pickup_failure(actor)
		return false
	if not actor_inventory.can_add_entry_with_contents(item_definition, quantity, contained_item_counts, pickup_metadata):
		_show_pickup_failure(actor)
		return false
	var stock: InventoryStockController
	if stock_projection:
		stock = BootstrapContext.service(InventoryStockController.SERVICE_ID) as InventoryStockController
		if stock == null or not stock.transact_item_count(stock_source_settlement_id, item_definition, -quantity):
			_show_pickup_failure(actor)
			return false
	var inventory_stack_id := "" if stock_projection else stack_id
	var picked_up: bool = actor_inventory.add_entry_with_contents(item_definition, quantity, contained_item_counts, pickup_metadata, inventory_stack_id)
	if not picked_up:
		if stock_projection and stock != null:
			stock.transact_item_count(stock_source_settlement_id, item_definition, quantity)
		_show_pickup_failure(actor)
		return false
	var lifecycle := BootstrapContext.service(&"item_lifecycle")
	if not stock_projection and lifecycle != null:
		lifecycle.call("submit_inventory", stack_id, str(actor.get("stable_id")), "%s.inventory" % str(actor.get("stable_id")))
	queue_free()
	return true


func _find_ownership_controller() -> Node:
	return BootstrapContext.service(OwnershipController.SERVICE_ID)


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
	var effective_owner_faction := get_owner_faction_name() if is_inside_tree() else owner_faction_name
	if item_definition == null:
		label.text = "Owned Item" if not effective_owner_faction.is_empty() else "Item"
		label.modulate = OWNED_LABEL_COLOR if not effective_owner_faction.is_empty() else Color.WHITE
		_refresh_label_visibility()
		return
	var item_label := _item_display_label()
	if bool(item_metadata.get(InventoryData.META_STOLEN, false)):
		label.text = "%s (Stolen)" % item_label
		label.modulate = OWNED_LABEL_COLOR
	elif not effective_owner_faction.is_empty():
		label.text = "%s (Owned)" % item_label
		label.modulate = OWNED_LABEL_COLOR
	else:
		label.text = item_label
		label.modulate = Color.WHITE
	_refresh_label_visibility()


func _refresh_label_visibility() -> void:
	if label != null:
		label.visible = _left_alt_item_labels_visible


func _item_display_label() -> String:
	if item_definition == null:
		return "Item"
	if int(item_definition.currency_container_capacity) > 0:
		var silver_count := int(contained_item_counts.get(str(InventoryData.SILVER_ITEM.resource_path), 0))
		return "%s %d/%d" % [item_definition.display_name, silver_count, int(item_definition.currency_container_capacity)]
	return item_definition.display_name if quantity <= 1 else "%s x%d" % [item_definition.display_name, quantity]


func _item_has_contained_counts() -> bool:
	return item_definition != null and (int(item_definition.currency_container_capacity) > 0 or not contained_item_counts.is_empty())


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
	_remove_imported_collision_nodes(visual_instance)
	model_root.add_child(visual_instance)
	if visual_instance is Node3D:
		_normalize_visual(visual_instance as Node3D, item_definition.world_visual_height_meters, item_definition.world_visual_long_axis_meters)
	_refresh_collision_from_visual()


func _remove_imported_collision_nodes(root: Node) -> void:
	for child in root.get_children():
		if child is CollisionObject3D or child is CollisionShape3D:
			root.remove_child(child)
			child.queue_free()
		else:
			_remove_imported_collision_nodes(child)


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


func _normalize_visual(visual_root: Node3D, target_height_meters: float = 0.0, target_long_axis_meters: float = 0.0) -> void:
	var bounds := _calculate_local_mesh_bounds(visual_root)
	if bounds.size.length() <= 0.001:
		return
	var longest_axis := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var scale_dimension := longest_axis
	if target_height_meters > 0.0 and target_long_axis_meters <= 0.0:
		scale_dimension = bounds.size.y
	if scale_dimension <= 0.001:
		return
	var target_dimension := 0.72
	if target_long_axis_meters > 0.0:
		target_dimension = target_long_axis_meters
	elif target_height_meters > 0.0:
		target_dimension = target_height_meters
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


func _transform_aabb(bounds: AABB, bounds_transform: Transform3D) -> AABB:
	var first := true
	var transformed_bounds := AABB()
	for x in [bounds.position.x, bounds.position.x + bounds.size.x]:
		for y in [bounds.position.y, bounds.position.y + bounds.size.y]:
			for z in [bounds.position.z, bounds.position.z + bounds.size.z]:
				var point := bounds_transform * Vector3(x, y, z)
				if first:
					transformed_bounds = AABB(point, Vector3.ZERO)
					first = false
				else:
					transformed_bounds = transformed_bounds.expand(point)
	return transformed_bounds
