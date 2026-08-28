@tool
extends StaticBody3D

class_name WorldContainer

signal inventory_changed
signal interaction_resolved(container, actor)

@export var display_name := "Container"
@export var container_id := ""
@export var settlement_id := ""
@export var facility_id := ""
@export var container_kind := "storage"
## Player/developer-facing storage purpose. The physical furniture remains a
## generic sack, barrel, chest, or crate; this value controls routing and item
## admission. The Facility dock presents these as General/Seeds/Tools/Food/
## Materials and keeps container_kind as the lower-level GECS routing value.
@export_enum("general", "seeds", "tools", "food", "materials") var container_type := "general":
	set(value):
		container_type = value.strip_edges().to_lower()
		if container_type not in CONTAINER_TYPES:
			container_type = "general"
		if container_type != "general":
			container_kind = str(TYPE_CONTAINER_KINDS.get(container_type, container_kind))
		elif container_kind in TYPE_CONTAINER_KINDS.values():
			container_kind = "storage"
		if inventory != null:
			_configure_inventory_admission()
		if is_inside_tree() and not Engine.is_editor_hint() and not _inventory_sync_suspended:
			_sync_inventory_to_gecs()
## On by default: a container standing in a settlement is part of that town's
## stock unless someone deliberately says otherwise. Contribution still requires
## a settlement_id (inventory_stock_controller.gd:108), so a crate out in the
## world counts toward nothing regardless of this flag.
@export var contributes_to_town_stock := true
@export var next_stack_sequence := 1
@export var furniture_type := FurnitureRules.Type.CONTAINER
@export var inventory_columns := 7
@export var inventory_rows := 5
@export var is_locked := false
@export var supports_locking := true
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
## Optional exact filter inside the broad container type. Empty means every
## item belonging to that type; authored starting_items remain independent.
@export var allowed_item_ids := PackedStringArray()
const CONTAINER_TYPES := ["general", "seeds", "tools", "food", "materials"]
const TYPE_CONTAINER_KINDS := {
	"seeds": "farm_seed",
	"tools": "tool_store",
	"food": "granary",
	"materials": "storage",
}
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
var _item_reservations: Dictionary = {}
var _inventory_sync_suspended := false
var _bind_attempts := 0
var _should_seed_starting_inventory := false

@onready var collision_shape_node: CollisionShape3D = $CollisionShape3D
@onready var model_root: Node3D = $ModelRoot


func _ready() -> void:
	if container_id.strip_edges().is_empty():
		push_warning("WorldContainer '%s' needs an authored container_id; it will not sync or contribute to town stock" % name)
	# Only warn about a container that is IN a town but cannot be counted. Having
	# no settlement_id is not a misconfiguration now that the flag defaults on —
	# it just means this container is not part of any town.
	if contributes_to_town_stock and not settlement_id.strip_edges().is_empty() and container_kind.strip_edges().is_empty():
		push_warning("WorldContainer '%s' is in settlement '%s' but has no container_kind, so it cannot contribute to town stock" % [name, settlement_id])
	if inventory == null:
		_should_seed_starting_inventory = true
		var inventory_data_script = load("res://features/inventory/sim/inventory_data.gd")
		inventory = inventory_data_script.new(inventory_columns, inventory_rows, 0.0, false)
	_configure_inventory_admission()
	if not inventory.changed.is_connected(_on_inventory_changed):
		inventory.changed.connect(_on_inventory_changed)
	if not container_id.strip_edges().is_empty():
		inventory.configure_stack_allocator(container_id, next_stack_sequence)
	add_to_group("world_container")
	add_to_group(FurnitureRules.FURNITURE_GROUP)
	_apply_collision_settings()
	_rebuild_visual()
	if container_id.strip_edges().is_empty():
		if _should_seed_starting_inventory:
			_seed_starting_inventory()
	else:
		call_deferred("_bind_inventory_state")


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		call_deferred("_refresh_editor_preview")


func _exit_tree() -> void:
	if Engine.is_editor_hint() or container_id.strip_edges().is_empty():
		return
	var stock_controller := BootstrapContext.service(InventoryStockController.SERVICE_ID)
	if stock_controller != null:
		stock_controller.call("detach_world_container", container_id, self)


func register_interactor(member: HumanoidCharacter) -> void:
	_get_slot_index(member)
	_pending_actor_ids[member.get_instance_id()] = true


func release_interactor(member: HumanoidCharacter) -> void:
	_pending_actor_ids.erase(member.get_instance_id())
	_assigned_slots.erase(member.get_instance_id())


func resolve_interaction(member: HumanoidCharacter) -> bool:
	if member == null:
		return false
	if supports_locking and is_locked:
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
	if container_type == "general" or display_name not in ["Container", "Sack", "Barrel", "Dark Barrel", "Wooden Chest", "Wooden Crate", "Crate"]:
		return display_name
	var prefix: String = str({
		"seeds": "Seed",
		"tools": "Tool",
		"food": "Food",
		"materials": "Material",
	}.get(container_type, ""))
	var furniture_name: String = str({
		"Wooden Chest": "Chest",
		"Wooden Crate": "Crate",
		"Dark Barrel": "Barrel",
	}.get(display_name, display_name))
	return "%s %s" % [prefix, furniture_name] if not prefix.is_empty() else display_name


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


func can_actor_access(actor: Node) -> bool:
	if actor == null or not is_instance_valid(actor) or (supports_locking and is_locked):
		return false
	var owner_faction := get_owner_faction_name()
	if owner_faction.is_empty():
		return true
	var actor_faction := str(actor.get("faction_name")) if "faction_name" in actor else str(actor.get_meta("faction_id", ""))
	return actor_faction == owner_faction


func find_reservable_tool(required_tag: String, actor: Node):
	_prune_item_reservations()
	if required_tag.is_empty() or inventory == null or not can_actor_access(actor):
		return null
	var reserved_stack_ids := _reserved_stack_ids()
	for entry in inventory.entries:
		if entry == null or entry.definition == null or not entry.definition.has_tool_tag(required_tag) \
				or reserved_stack_ids.has(str(entry.stack_id)):
			continue
		return entry.definition
	return null


func reserve_item_for_actor(definition: ItemDefinition, actor: Node, amount := 1) -> bool:
	_prune_item_reservations()
	if definition == null or actor == null or amount <= 0 or inventory == null or not can_actor_access(actor):
		return false
	var actor_key := actor.get_instance_id()
	var existing: Dictionary = _item_reservations.get(actor_key, {})
	if not existing.is_empty():
		return existing.get("definition") == definition and int(existing.get("amount", 0)) == amount
	var reserved_stack_ids := _reserved_stack_ids()
	for entry in inventory.entries:
		if entry == null or entry.definition != definition or int(entry.count) != amount or reserved_stack_ids.has(str(entry.stack_id)):
			continue
		_item_reservations[actor_key] = {
			"actor_ref": weakref(actor),
			"definition": definition,
			"amount": amount,
			"stack_id": str(entry.stack_id),
			"contained_item_counts": entry.contained_item_counts.duplicate(true),
			"metadata": entry.metadata.duplicate(true),
			"checked_out": false,
		}
		return true
	return false


func get_item_reservation_snapshot(actor: Node) -> Dictionary:
	return (_item_reservations.get(actor.get_instance_id(), {}) as Dictionary).duplicate(true) if actor != null else {}


func release_item_reservation(actor_or_key) -> void:
	var actor_key := int(actor_or_key) if actor_or_key is int else (actor_or_key as Node).get_instance_id() if actor_or_key is Node else 0
	if actor_key != 0:
		_item_reservations.erase(actor_key)


func withdraw_reserved_item_to(definition: ItemDefinition, actor: Node, target_inventory) -> bool:
	if actor == null or definition == null or inventory == null or target_inventory == null or not can_actor_access(actor):
		return false
	var actor_key := actor.get_instance_id()
	var reservation: Dictionary = _item_reservations.get(actor_key, {})
	if reservation.get("definition") != definition or bool(reservation.get("checked_out", false)):
		return false
	var entry = _inventory_entry_by_stack_id(inventory, str(reservation.get("stack_id", "")))
	if entry == null or entry.definition != definition or int(entry.count) != int(reservation.get("amount", 0)):
		return false
	var target_position: Vector2i = target_inventory.find_first_space(definition)
	if target_position == Vector2i(-1, -1) or not inventory.move_entry_to_inventory(entry, target_inventory, target_position):
		return false
	reservation["checked_out"] = true
	_item_reservations[actor_key] = reservation
	return true


func return_borrowed_item_from(definition: ItemDefinition, actor: Node, source_inventory, stack_id: String) -> bool:
	if actor == null or definition == null or source_inventory == null or inventory == null:
		return false
	var actor_key := actor.get_instance_id()
	var reservation: Dictionary = _item_reservations.get(actor_key, {})
	if reservation.get("definition") != definition or not bool(reservation.get("checked_out", false)) \
			or str(reservation.get("stack_id", "")) != stack_id:
		return false
	var entry = _inventory_entry_by_stack_id(source_inventory, stack_id)
	if entry == null or entry.definition != definition:
		return false
	var target_position: Vector2i = inventory.find_first_space(definition)
	if target_position == Vector2i(-1, -1) or not source_inventory.move_entry_to_inventory(entry, inventory, target_position):
		return false
	_item_reservations.erase(actor_key)
	return true


func return_borrowed_equipped_item(definition: ItemDefinition, actor: Node, equipment, stack_id: String, current_snapshot: Dictionary = {}) -> bool:
	if actor == null or definition == null or equipment == null or inventory == null:
		return false
	if actor.has_method("get_equipment") and actor.call("get_equipment") != equipment:
		return false
	var actor_key := actor.get_instance_id()
	var reservation: Dictionary = _item_reservations.get(actor_key, {})
	if reservation.get("definition") != definition or not bool(reservation.get("checked_out", false)) \
			or str(reservation.get("stack_id", "")) != stack_id \
			or equipment.get_equipped_item("weapon") != definition \
			or str(equipment.get_equipped_stack_id("weapon")) != stack_id:
		return false
	var count := int(current_snapshot.get("count", reservation.get("amount", 1)))
	var contents: Dictionary = (current_snapshot.get("contained_item_counts", reservation.get("contained_item_counts", {})) as Dictionary).duplicate(true)
	var metadata: Dictionary = (current_snapshot.get("metadata", reservation.get("metadata", {})) as Dictionary).duplicate(true)
	if not inventory.can_add_entry_with_contents(definition, count, contents, metadata):
		return false
	if equipment.has_method("begin_equipment_update_batch"):
		equipment.begin_equipment_update_batch()
	equipment.unequip_item_from_slot("weapon")
	if not inventory.add_entry_with_contents(definition, count, contents, metadata, stack_id):
		equipment.equip_item_to_slot(definition, "weapon", stack_id)
		if equipment.has_method("end_equipment_update_batch"):
			equipment.end_equipment_update_batch()
		return false
	if equipment.has_method("end_equipment_update_batch"):
		equipment.end_equipment_update_batch()
	_item_reservations.erase(actor_key)
	return true


func _inventory_entry_by_stack_id(source_inventory, stack_id: String):
	if source_inventory == null or stack_id.is_empty():
		return null
	for entry in source_inventory.entries:
		if entry != null and str(entry.stack_id) == stack_id:
			return entry
	return null


func _reserved_stack_ids() -> Dictionary:
	var result := {}
	for reservation_value in _item_reservations.values():
		var stack_id := str((reservation_value as Dictionary).get("stack_id", ""))
		if not stack_id.is_empty():
			result[stack_id] = true
	return result


func _prune_item_reservations() -> void:
	for actor_key_value in _item_reservations.keys().duplicate():
		var actor_ref := (_item_reservations[actor_key_value] as Dictionary).get("actor_ref") as WeakRef
		if actor_ref == null or actor_ref.get_ref() == null:
			_item_reservations.erase(actor_key_value)


func _configure_inventory_admission() -> void:
	if inventory != null and inventory.has_method("set_admission_validator"):
		inventory.call("set_admission_validator", Callable(self, "can_accept_item_count"))


func can_accept_item_count(definition: ItemDefinition, amount: int) -> bool:
	if definition == null or amount <= 0:
		return false
	var item_id := definition.item_id.strip_edges()
	if item_id.is_empty():
		item_id = definition.resource_path
	if not allowed_item_ids.is_empty() and not allowed_item_ids.has(item_id):
		return false
	match container_type:
		"seeds":
			return item_id.begins_with("seed.")
		"tools":
			return item_id.begins_with("tool.") or definition.has_any_tool_tag()
		"food":
			return item_id.begins_with("food.") or not definition.food_type_id.is_empty()
		"materials":
			return item_id.begins_with("material.") or item_id.begins_with("ore.")
		_:
			return true


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
	if not _inventory_sync_suspended:
		_sync_inventory_to_gecs()


func _bind_inventory_state() -> void:
	if Engine.is_editor_hint() or container_id.strip_edges().is_empty():
		return
	var stock_controller := BootstrapContext.service(InventoryStockController.SERVICE_ID)
	if stock_controller == null and _bind_attempts < 8:
		_bind_attempts += 1
		call_deferred("_bind_inventory_state")
		return
	if stock_controller != null and bool(stock_controller.call("bind_world_container", self)):
		return
	_inventory_sync_suspended = true
	if _should_seed_starting_inventory:
		_seed_starting_inventory()
	_inventory_sync_suspended = false
	_sync_inventory_to_gecs()


func hydrate_inventory_from_gecs(stack_snapshots: Array, sequence: int) -> void:
	_inventory_sync_suspended = true
	inventory.entries.clear()
	inventory.configure_stack_allocator(container_id, sequence)
	for snapshot_value in stack_snapshots:
		var snapshot := snapshot_value as Dictionary
		var item_path := str(snapshot.get("item_definition_path", ""))
		var definition := snapshot.get("definition") as ItemDefinition
		if definition == null and not item_path.is_empty() and ResourceLoader.exists(item_path):
			definition = load(item_path) as ItemDefinition
		if definition == null:
			continue
		var stack_count := int(snapshot.get("count", 1))
		if not inventory.hydrate_entry_with_contents(
			definition,
			snapshot.get("grid_position", Vector2i.ZERO),
			stack_count,
			(snapshot.get("contained_item_counts", {}) as Dictionary).duplicate(true),
			(snapshot.get("metadata", {}) as Dictionary).duplicate(true),
			str(snapshot.get("stack_id", "")),
			false
		):
			push_warning("WorldContainer '%s' could not hydrate stock '%s' within inventory limits" % [name, definition.display_name])
	next_stack_sequence = inventory.next_stack_sequence
	inventory.changed.emit()
	_inventory_sync_suspended = false


func hydrate_container_policy_from_gecs(type_id: String, item_ids: PackedStringArray) -> void:
	_inventory_sync_suspended = true
	container_type = type_id
	allowed_item_ids = item_ids.duplicate()
	_configure_inventory_admission()
	_inventory_sync_suspended = false


func _sync_inventory_to_gecs() -> void:
	if not is_inside_tree():
		return
	next_stack_sequence = inventory.next_stack_sequence
	var bridge := BootstrapContext.service(GecsWorldController.SERVICE_ID)
	if bridge != null and bridge.has_method("sync_world_container"):
		bridge.call("sync_world_container", self)
	var stock_controller := BootstrapContext.service(InventoryStockController.SERVICE_ID)
	if stock_controller != null:
		stock_controller.call("sync_world_container", self)


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
