extends Node

## Disposable view of a body's personal inventory, never its shop or job stock.
## The original actor capabilities still own every item and equipment mutation.
signal inventory_changed

var _actor_ref: WeakRef
var _target_ref: WeakRef
var _ownership_ref: WeakRef
var action := ""

func bind(actor: HumanoidCharacter, target: HumanoidCharacter, ownership: Node, requested_action: String) -> void:
	_actor_ref = weakref(actor)
	_target_ref = weakref(target)
	_ownership_ref = weakref(ownership)
	action = requested_action
	target.inventory_changed.connect(_on_inventory_changed)

func _exit_tree() -> void:
	var target := get_owner_character()
	if target != null and target.inventory_changed.is_connected(_on_inventory_changed):
		target.inventory_changed.disconnect(_on_inventory_changed)

func _on_inventory_changed() -> void:
	inventory_changed.emit()

func get_actor() -> HumanoidCharacter:
	return _live_actor(_actor_ref)

func get_owner_character() -> HumanoidCharacter:
	return _live_actor(_target_ref)

func _live_actor(reference: WeakRef) -> HumanoidCharacter:
	var value = reference.get_ref() if reference != null else null
	return value if is_instance_valid(value) and not value.is_queued_for_deletion() else null

func is_access_valid() -> bool:
	if is_queued_for_deletion():
		return false
	var actor := get_actor()
	var target := get_owner_character()
	return actor != null and target != null and OwnershipController.get_character_inventory_action(actor, target) == action \
		and actor.get_interaction() != null and actor.global_position.distance_to(target.global_position) <= actor.get_interaction().get_trade_interaction_distance()

func authorize_inventory_take() -> bool:
	if not is_access_valid():
		return false
	var ownership = _ownership_ref.get_ref() if _ownership_ref != null else null
	return is_instance_valid(ownership) and ownership.request_take_item(get_actor(), get_owner_character())

func get_inventory_take_metadata(metadata: Dictionary) -> Dictionary:
	var ownership = _ownership_ref.get_ref() if _ownership_ref != null else null
	return ownership.get_take_item_metadata(get_actor(), get_owner_character(), metadata) if is_instance_valid(ownership) else metadata

func get_inventory_for_display() -> InventoryData:
	var target := get_owner_character()
	return target.inventory if target != null else null

func get_inventory_display_title() -> String:
	var target := get_owner_character()
	return "%s — %s" % [action.capitalize(), target.member_name] if target != null else "Unavailable"

func get_inventory_world_position() -> Vector3:
	var target := get_owner_character()
	return target.global_position if target != null else Vector3.INF

func shows_inventory_equipment() -> bool: return true
func shows_inventory_weight() -> bool: return true

func get_equipment() -> EquipmentCapability:
	var target := get_owner_character()
	return target.get_equipment() if target != null else null

func get_equipped_item(slot: String) -> ItemDefinition:
	var gear := get_equipment()
	return gear.get_equipped_item(slot) if gear != null else null

func get_equipment_slot_names() -> Array[String]:
	var target := get_owner_character()
	return target.get_equipment_slot_names() if target != null else []

func get_equipment_slot_label(slot: String) -> String:
	var target := get_owner_character()
	return target.get_equipment_slot_label(slot) if target != null else slot.capitalize()

func get_equipment_slot_grid_size(slot: String) -> Vector2i:
	var target := get_owner_character()
	return target.get_equipment_slot_grid_size(slot) if target != null else Vector2i.ONE

func can_equip_item_to_slot(_item: ItemDefinition, _slot: String) -> bool:
	return false # A body view is a source, not an equipment destination.

func can_transfer_display_inventory_to(_target_owner) -> bool: return is_access_valid()
func can_receive_inventory_transfer_from(_source_owner) -> bool: return false
