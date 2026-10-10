extends Node

## Disposable projection of an exact item's storage, never a second owner.
## The item's serialized GECS metadata travels through the existing item lifecycle.
signal inventory_changed

var stack_id := ""
var inventory: InventoryData
var _owner_ref: WeakRef
var _gecs_ref: WeakRef
var _parent_inventory: InventoryData
var _parent_entry
var _slot := ""
var _definition: ItemDefinition
var _last_contents: Dictionary
var _publishing := false
var _invalidated := false

func bind(owner: Node, id: String, gecs: Node) -> bool:
	_owner_ref = weakref(owner)
	_gecs_ref = weakref(gecs) if gecs != null else null
	stack_id = id
	_parent_inventory = owner.get_inventory_for_display() if owner.has_method("get_inventory_for_display") else owner.get("inventory")
	if _parent_inventory == null:
		return false
	var metadata: Dictionary = {}
	for entry in _parent_inventory.entries:
		if entry.stack_id == id:
			_parent_entry = entry
			_definition = entry.definition
			metadata = entry.metadata
			break
	if _parent_entry == null and owner.has_method("get_equipment"):
		var equipment: EquipmentCapability = owner.get_equipment()
		if equipment != null:
			for slot in equipment.get_equipped_items():
				if equipment.get_equipped_stack_id(slot) == id:
					_slot = slot
					_definition = equipment.get_equipped_item(slot)
					metadata = _record().get("metadata", {})
	if _definition == null or not _definition.has_storage() or (_parent_entry == null and _record().is_empty()):
		return false
	inventory = InventoryData.create_item_storage(_definition, metadata, id)
	if inventory == null:
		return false
	inventory.access_validator = is_access_valid
	_parent_inventory.bind_item_storage(id, inventory)
	_last_contents = metadata.get(InventoryData.ITEM_STORAGE_KEY, {}).duplicate(true)
	inventory.changed.connect(_publish)
	if owner.has_signal("inventory_changed"):
		owner.inventory_changed.connect(_on_owner_changed)
	if gecs != null:
		gecs.world_reindexed.connect(_invalidate)
	return true

func get_source_owner():
	var value = _owner_ref.get_ref() if _owner_ref != null else null
	return value if is_instance_valid(value) and not value.is_queued_for_deletion() else null

func get_owner_character():
	var owner = get_source_owner()
	return owner.get_owner_character() if owner != null and owner.has_method("get_owner_character") else owner

func _record() -> Dictionary:
	var gecs = _gecs_ref.get_ref() if _gecs_ref != null else null
	return gecs.get_item_stack(stack_id) if is_instance_valid(gecs) else {}

func is_access_valid() -> bool:
	var owner = get_source_owner()
	if _invalidated or is_queued_for_deletion() or owner == null:
		return false
	if owner.has_method("is_access_valid") and not owner.is_access_valid():
		return false
	if _parent_entry != null:
		var current = owner.get_inventory_for_display() if owner.has_method("get_inventory_for_display") else owner.get("inventory")
		return current == _parent_inventory and _parent_inventory.entries.has(_parent_entry)
	var equipment: EquipmentCapability = owner.get_equipment() if owner.has_method("get_equipment") else null
	return equipment != null and equipment.get_equipped_stack_id(_slot) == stack_id and not _record().is_empty()

func _publish() -> void:
	if not is_access_valid():
		return
	_publishing = true
	_last_contents = inventory.serialize_contents()
	if _parent_entry != null:
		_parent_entry.metadata[InventoryData.ITEM_STORAGE_KEY] = _last_contents.duplicate(true)
		_parent_inventory.changed.emit()
	else:
		var record := _record()
		record.metadata[InventoryData.ITEM_STORAGE_KEY] = _last_contents.duplicate(true)
		var gecs = _gecs_ref.get_ref()
		gecs.upsert_item_stack_record(record)
		_parent_inventory.changed.emit()
	_publishing = false
	inventory_changed.emit()

func _on_owner_changed() -> void:
	if _publishing:
		return
	if not is_access_valid():
		_invalidated = true
		return
	var metadata: Dictionary = _parent_entry.metadata if _parent_entry != null else _record().get("metadata", {})
	# A load or external replacement invalidates the old view, never writes it back.
	if metadata.get(InventoryData.ITEM_STORAGE_KEY, {}) != _last_contents:
		_invalidated = true
	inventory_changed.emit()

func _invalidate() -> void:
	_invalidated = true
	inventory_changed.emit()

func _exit_tree() -> void:
	var gecs = _gecs_ref.get_ref() if _gecs_ref != null else null
	if is_instance_valid(gecs) and gecs.world_reindexed.is_connected(_invalidate):
		gecs.world_reindexed.disconnect(_invalidate)
	if _parent_inventory != null:
		_parent_inventory.unbind_item_storage(stack_id, inventory)
	var owner = get_source_owner()
	if owner != null and owner.has_signal("inventory_changed") and owner.inventory_changed.is_connected(_on_owner_changed):
		owner.inventory_changed.disconnect(_on_owner_changed)
	if inventory != null and inventory.changed.is_connected(_publish):
		inventory.changed.disconnect(_publish)
	_invalidated = true

func get_inventory_for_display() -> InventoryData: return inventory
func get_inventory_display_title() -> String: return _definition.display_name
func shows_inventory_equipment() -> bool: return false
func shows_inventory_weight() -> bool: return true
func get_inventory_world_position() -> Vector3:
	var owner = get_source_owner()
	if owner == null:
		return Vector3.INF
	return owner.get_inventory_world_position() if owner.has_method("get_inventory_world_position") else owner.global_position
func can_transfer_display_inventory_to(target) -> bool:
	var owner = get_source_owner()
	var access = owner.get_inventory() if owner is WorldActor else owner
	return is_access_valid() and access != null and (not access.has_method("can_transfer_display_inventory_to") or access.can_transfer_display_inventory_to(target))
func can_receive_inventory_transfer_from(source) -> bool:
	var owner = get_source_owner()
	var access = owner.get_inventory() if owner is WorldActor else owner
	return is_access_valid() and access != null and (not access.has_method("can_receive_inventory_transfer_from") or access.can_receive_inventory_transfer_from(source))
