extends RefCounted

## Manual Cinder Flask transaction, owned by InteractionCapability.
## No automatic target selection, reservations or scheduler.
const FLASK_TAG := "tool.cinder_flask"


func burn(interaction, body, show_notices := true) -> bool:
	var actor = interaction.actor
	if not _live(actor) or not _live(body) or actor.life_state != NpcRules.LifeState.ALIVE:
		return false
	if not body.has_method("begin_cinder_burn") or not body.can_be_destroyed_by_cinder():
		return false
	if not actor._is_close_enough_to_downed_interaction_target(body):
		return false
	var inventory = actor.inventory
	var flask = _find_flask(inventory)
	if flask == null:
		if show_notices:
			actor.show_world_speech("Need a Cinder Flask", 4.0)
		return false
	# Use InventoryData's transaction snapshot/restore, including live entry
	# identity and allocator state. Publish only AFTER fire accepts the debit;
	# synchronous inventory observers cannot invalidate the unpaid target.
	var snapshot: Dictionary = inventory._snapshot_standard_transaction()
	if not inventory._remove_standard_item_count(flask, 1, false):
		return false
	if not _live(body) or not body.begin_cinder_burn(actor):
		inventory._restore_standard_transaction(snapshot)
		return false
	inventory.changed.emit()
	return true


func _find_flask(inventory):
	if inventory != null:
		for entry in inventory.entries:
			if entry != null and entry.count > 0 and entry.definition != null and FLASK_TAG in entry.definition.tool_tags:
				return entry.definition
	return null


static func _live(node) -> bool:
	return is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion()
