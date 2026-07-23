extends "res://features/actors/bridge/capabilities/actor_capability.gd"

class_name InventoryCapability

## Owns one concern: this actor's carried inventory (and optional work-inventory
## override). The capability is the sole owner of the InventoryData — the actor
## exposes it as a computed `inventory` property. Inventory changes go out as the
## `inventory_changed` signal (the actor re-emits its own for external systems). The
## world controller OBSERVES that signal and mirrors it into GECS — this capability holds
## no reference to the controller (dependency inverted, so no actor<->capability cycle).
## No actor reflection.

signal inventory_changed()

var inventory: InventoryData
var work_inventory_override: InventoryData

var _initialized := false


func _init() -> void:
	super._init(&"inventory")


func ready() -> void:
	initialize_from_actor()


func teardown() -> void:
	_disconnect_inventory(inventory)
	_disconnect_inventory(work_inventory_override)
	inventory = null
	work_inventory_override = null
	_initialized = false
	super.teardown()


func initialize_from_actor() -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	if inventory == null:
		inventory = InventoryData.new(
			actor.inventory_columns,
			actor.inventory_rows,
			actor.max_carry_weight,
			true
		)
		if not actor.stable_id.strip_edges().is_empty():
			inventory.configure_stack_allocator("%s.inventory" % actor.stable_id)
	_connect_inventory(inventory)
	if _initialized:
		return true
	_initialized = true
	seed_starting_inventory_from_actor()
	apply_population_inventory_entries_if_present()
	return true


func seed_starting_inventory_from_actor() -> void:
	if not _ensure_inventory_ready():
		return
	var starting_items: Array = actor.starting_items
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
	hydrate_population_entries(snapshots)


func hydrate_population_entries(snapshots: Array, emit_changed := true) -> void:
	if not _ensure_inventory_ready():
		return
	inventory.entries.clear()
	if snapshots.is_empty():
		if emit_changed:
			inventory.changed.emit()
		return
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
		inventory.entries.append(inventory.create_entry(
			definition,
			grid_position,
			maxi(1, int(snapshot.get("count", 1))),
			(snapshot.get("contained_item_counts", {}) as Dictionary).duplicate(true),
			(snapshot.get("metadata", {}) as Dictionary).duplicate(true),
			str(snapshot.get("stack_id", ""))
		))
	if emit_changed:
		inventory.changed.emit()


func set_work_inventory(next_work_inventory: InventoryData) -> void:
	if work_inventory_override == next_work_inventory:
		return
	_disconnect_inventory(work_inventory_override)
	work_inventory_override = next_work_inventory
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


func notify_inventory_changed(_reset_auto_burn_scan := true) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	# GECS sync is INVERTED (dependency direction): the capability only emits. The
	# GecsWorldController observes this signal (connected in register_actor) and mirrors
	# the inventory into the component. The capability no longer references the controller.
	inventory_changed.emit()


func _ensure_inventory_ready() -> bool:
	if inventory == null:
		initialize_from_actor()
	return inventory != null


func _connect_inventory(target_inventory: InventoryData) -> void:
	if target_inventory == null:
		return
	if not target_inventory.changed.is_connected(_on_inventory_data_changed):
		target_inventory.changed.connect(_on_inventory_data_changed)


func _disconnect_inventory(target_inventory: InventoryData) -> void:
	if target_inventory == null:
		return
	if target_inventory.changed.is_connected(_on_inventory_data_changed):
		target_inventory.changed.disconnect(_on_inventory_data_changed)


func _on_inventory_data_changed() -> void:
	notify_inventory_changed(true)
