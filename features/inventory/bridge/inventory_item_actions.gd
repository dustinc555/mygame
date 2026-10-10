extends RefCounted

## Item actions resolve the acting character separately from the exact storage.
## A looted body's view is deliberately not a personal-use inventory.
const ITEM_STORAGE_VIEW = preload("res://features/inventory/bridge/item_storage_view.gd")
const FOOD_AUDIO = preload("res://features/inventory/projection/food_eating_audio.gd")

static func character_for(source_owner) -> WorldActor:
	if not is_instance_valid(source_owner) or source_owner.is_queued_for_deletion():
		return null
	if source_owner is ITEM_STORAGE_VIEW:
		return character_for(source_owner.get_source_owner()) if source_owner.is_access_valid() else null
	return source_owner as WorldActor


static func inventory_for(source_owner) -> InventoryData:
	if not is_instance_valid(source_owner) or source_owner.is_queued_for_deletion():
		return null
	return source_owner.get_inventory_for_display() if source_owner.has_method("get_inventory_for_display") else null


static func can_eat(source_owner, entry) -> bool:
	var actor := character_for(source_owner)
	var inventory := inventory_for(source_owner)
	return actor != null and actor.life_state == NpcRules.LifeState.ALIVE \
		and inventory != null and inventory.is_accessible() and inventory.entries.has(entry) \
		and entry.count > 0 and actor.can_eat_item(entry.definition) \
		and actor.get_inventory().can_transfer_display_inventory_to(actor)


static func eat(source_owner, entry) -> bool:
	if not can_eat(source_owner, entry):
		return false
	var actor := character_for(source_owner)
	var inventory := inventory_for(source_owner)
	return _consume(actor, inventory, entry)


static func eat_shared(donor: WorldActor, inventory: InventoryData, entry, recipient: WorldActor, distance: float) -> bool:
	if not is_instance_valid(donor) or not is_instance_valid(recipient) or donor == recipient:
		return false
	if donor.is_queued_for_deletion() or recipient.is_queued_for_deletion() \
		or not donor.is_inside_tree() or not recipient.is_inside_tree() \
		or not donor.share_food_enabled or not donor.is_player_party_member() or not recipient.is_player_party_member() \
		or donor.life_state != NpcRules.LifeState.ALIVE or recipient.life_state != NpcRules.LifeState.ALIVE \
		or donor.global_position.distance_to(recipient.global_position) > distance:
		return false
	if inventory == null or not inventory.is_accessible() or not inventory.entries.has(entry) or entry.count <= 0 \
		or inventory.storage_stack_id.is_empty() or inventory.storage_stack_id != donor.get_equipment().get_equipped_stack_id("backpack") \
		or inventory.get_carrying_inventory() != donor.inventory \
		or not donor.get_inventory().can_transfer_display_inventory_to(recipient) \
		or not recipient.can_eat_item(entry.definition) or not recipient.get_needs().wants_food():
		return false
	return _consume(recipient, inventory, entry)


static func _consume(actor: WorldActor, inventory: InventoryData, entry) -> bool:
	if actor.is_food_effect_active():
		return false
	# Debit silently before digestion announces its change. Restore the exact
	# entry and position if the effect refuses; never refund a generic item.
	var index := inventory.entries.find(entry)
	entry.count -= 1
	if entry.count == 0:
		inventory.entries.erase(entry)
	if not actor.get_needs().start_food_effect(entry.definition.nutrition_value, NpcRules.FOOD_EFFECT_DURATION_SECONDS):
		entry.count += 1
		if not inventory.entries.has(entry):
			inventory.entries.insert(index, entry)
		return false
	inventory.changed.emit()
	FOOD_AUDIO.play_for(actor)
	return true


static func can_take_silver(source_owner, entry) -> bool:
	var actor := character_for(source_owner)
	var inventory := inventory_for(source_owner)
	return actor != null and actor.is_player_party_member() and inventory != null \
		and inventory.is_accessible() and inventory.entries.has(entry) \
		and actor.get_inventory().can_transfer_display_inventory_to(actor) \
		and inventory.is_entry_currency_container(entry, InventoryData.SILVER_ITEM) \
		and inventory.get_entry_contained_item_count(entry, InventoryData.SILVER_ITEM) > 0
