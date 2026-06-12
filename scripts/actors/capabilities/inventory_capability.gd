extends "res://scripts/actors/capabilities/actor_capability.gd"

class_name InventoryCapability

var inventory: InventoryData
var work_inventory_override: InventoryData

var _initialized := false
var _gecs_world_controller: Node
var _actor_property_cache: Dictionary = {}


func _init() -> void:
	super._init(&"inventory")


func setup(target_actor: Node) -> void:
	super.setup(target_actor)
	_actor_property_cache.clear()


func ready() -> void:
	initialize_from_actor()


func teardown() -> void:
	_disconnect_inventory(inventory)
	_disconnect_inventory(work_inventory_override)
	inventory = null
	work_inventory_override = null
	_gecs_world_controller = null
	_actor_property_cache.clear()
	_initialized = false
	super.teardown()


func initialize_from_actor() -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	var existing = actor.get("inventory") if _actor_has_property("inventory") else null
	inventory = existing as InventoryData
	if inventory == null:
		inventory = InventoryData.new(
			_get_actor_int("inventory_columns", 10),
			_get_actor_int("inventory_rows", 4),
			_get_actor_float("max_carry_weight", 60.0),
			true
		)
		actor.set("inventory", inventory)
	_connect_inventory(inventory)
	if _actor_has_property("_work_inventory_override"):
		work_inventory_override = actor.get("_work_inventory_override") as InventoryData
		_connect_inventory(work_inventory_override)
	if _initialized:
		return true
	_initialized = true
	seed_starting_inventory_from_actor()
	apply_population_inventory_entries_if_present()
	return true


func seed_starting_inventory_from_actor() -> void:
	if not _ensure_inventory_ready():
		return
	var starting_items = actor.get("starting_items") if _actor_has_property("starting_items") else []
	if not (starting_items is Array):
		return
	for stock in starting_items:
		if stock == null:
			continue
		var item_definition = stock.get("item_definition")
		var quantity := int(stock.get("quantity"))
		if item_definition != null and quantity > 0:
			inventory.add_item_count(item_definition, quantity)


func apply_population_inventory_entries_if_present() -> void:
	if not _ensure_inventory_ready() or not actor.has_meta("population_inventory_entries"):
		return
	var snapshots: Array = actor.get_meta("population_inventory_entries")
	if snapshots.is_empty():
		return
	inventory.entries.clear()
	for snapshot_value in snapshots:
		if not (snapshot_value is Dictionary):
			continue
		var snapshot: Dictionary = snapshot_value
		var item_path := str(snapshot.get("item_id", ""))
		if item_path.strip_edges().is_empty() or not ResourceLoader.exists(item_path):
			continue
		var definition := load(item_path) as ItemDefinition
		if definition == null:
			continue
		var grid_position: Vector2i = snapshot.get("grid_position", Vector2i.ZERO)
		inventory.entries.append(InventoryData.InventoryEntry.new(
			definition,
			grid_position,
			maxi(1, int(snapshot.get("count", 1))),
			(snapshot.get("contained_item_counts", {}) as Dictionary).duplicate(true),
			(snapshot.get("metadata", {}) as Dictionary).duplicate(true)
		))
	inventory.changed.emit()


func set_work_inventory(next_work_inventory: InventoryData) -> void:
	if work_inventory_override == next_work_inventory:
		if _actor_has_property("_work_inventory_override"):
			actor.set("_work_inventory_override", work_inventory_override)
		return
	_disconnect_inventory(work_inventory_override)
	work_inventory_override = next_work_inventory
	if _actor_has_property("_work_inventory_override"):
		actor.set("_work_inventory_override", work_inventory_override)
	_connect_inventory(work_inventory_override)


func get_inventory_for_display() -> InventoryData:
	if work_inventory_override != null:
		return work_inventory_override
	if inventory == null:
		initialize_from_actor()
	return inventory


func is_displaying_work_inventory() -> bool:
	return work_inventory_override != null


func can_transfer_display_inventory_to(_target_owner) -> bool:
	return not is_displaying_work_inventory()


func can_receive_inventory_transfer_from(_source_owner) -> bool:
	return not is_displaying_work_inventory()


func notify_inventory_changed(reset_auto_burn_scan := true) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	if reset_auto_burn_scan and _actor_has_property("_auto_burn_next_scan_msec"):
		actor.set("_auto_burn_next_scan_msec", 0)
	if actor.has_signal("inventory_changed"):
		actor.emit_signal("inventory_changed")
	sync_to_gecs()


func sync_to_gecs() -> void:
	if actor == null or not is_instance_valid(actor) or not actor.is_inside_tree():
		return
	var bridge := _get_gecs_world_controller()
	if bridge != null and bridge.has_method("sync_actor_inventory"):
		bridge.call("sync_actor_inventory", actor)


func _ensure_inventory_ready() -> bool:
	if inventory == null:
		initialize_from_actor()
	return inventory != null


func _connect_inventory(target_inventory: InventoryData) -> void:
	if target_inventory == null:
		return
	var callback := Callable(self, "_on_inventory_data_changed")
	if not target_inventory.changed.is_connected(callback):
		target_inventory.changed.connect(callback)


func _disconnect_inventory(target_inventory: InventoryData) -> void:
	if target_inventory == null:
		return
	var callback := Callable(self, "_on_inventory_data_changed")
	if target_inventory.changed.is_connected(callback):
		target_inventory.changed.disconnect(callback)


func _on_inventory_data_changed() -> void:
	notify_inventory_changed(true)


func _get_gecs_world_controller() -> Node:
	if actor == null or not is_instance_valid(actor) or not actor.is_inside_tree():
		return null
	if _gecs_world_controller != null and is_instance_valid(_gecs_world_controller):
		return _gecs_world_controller
	_gecs_world_controller = actor.get_tree().get_first_node_in_group("gecs_world_controller")
	return _gecs_world_controller


func _actor_has_property(property_name: String) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	if _actor_property_cache.has(property_name):
		return bool(_actor_property_cache[property_name])
	for property in actor.get_property_list():
		if str(property.get("name", "")) == property_name:
			_actor_property_cache[property_name] = true
			return true
	_actor_property_cache[property_name] = false
	return false


func _get_actor_int(property_name: String, fallback: int) -> int:
	return int(actor.get(property_name)) if _actor_has_property(property_name) else fallback


func _get_actor_float(property_name: String, fallback: float) -> float:
	return float(actor.get(property_name)) if _actor_has_property(property_name) else fallback
