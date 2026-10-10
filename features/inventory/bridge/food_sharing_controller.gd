extends Node

## Shared food is party policy, not per-actor AI or inventory-window behavior.
## Signals maintain hungry members and dirty suppliers. The existing world-minute
## event retries proximity only while both sets are nonempty; no frame polling.
const SERVICE_ID := &"food_sharing"
const ITEM_ACTIONS = preload("res://features/inventory/bridge/inventory_item_actions.gd")
const STORAGE_VIEW = preload("res://features/inventory/bridge/item_storage_view.gd")
@export var settings: Resource = preload("res://features/inventory/resources/food_sharing_settings.tres")

var _party: PartyManager
var _gecs: GecsWorldController
var _world_time: WorldTimeController
var _members: Dictionary = {}
var _hungry: Dictionary = {}
var _suppliers: Dictionary = {}
var _dirty_suppliers: Dictionary = {}
var _nutrition_by_path: Dictionary = {}
var _check_queued := false
var _checking := false

func initialize(context: BootstrapContext) -> void:
	_gecs = context.get_optional(GecsWorldController.SERVICE_ID)
	_world_time = context.get_optional(WorldTimeController.SERVICE_ID)
	_party = context.root_scene.get_node_or_null("PartyManager")
	if _party == null or _gecs == null:
		return
	_party.party_member_added.connect(_track)
	_party.party_member_removed.connect(_untrack)
	_party.party_membership_changed.connect(_membership_changed)
	_gecs.world_reindexed.connect(_on_world_reindexed)
	if _world_time != null:
		_world_time.minute_changed.connect(_on_minute)
	for member in _party.party_members:
		_track(member)


func _track(member: WorldActor) -> void:
	if not is_instance_valid(member) or member.is_queued_for_deletion() \
		or _party == null or not _party.party_members.has(member) or _members.has(member.get_instance_id()):
		return
	# Saved records announce membership before the actor enters the scene.
	# Capabilities and hydrated needs exist only after its ready lifecycle.
	if not member.is_inside_tree() or not member.is_node_ready():
		var on_ready := _track.bind(member)
		if not member.ready.is_connected(on_ready):
			member.ready.connect(on_ready, CONNECT_ONE_SHOT)
		return
	var needs := member.get_needs()
	if needs == null:
		return
	var id := member.get_instance_id()
	_members[id] = member
	member.state_changed.connect(_member_changed.bind(id))
	member.inventory_changed.connect(_inventory_changed.bind(id))
	member.tree_exiting.connect(_untrack.bind(member))
	needs.food_need_changed.connect(_need_changed.bind(id))
	_member_changed(id)


func _untrack(member) -> void:
	if not is_instance_valid(member):
		return
	var on_ready := _track.bind(member)
	if member.ready.is_connected(on_ready):
		member.ready.disconnect(on_ready)
	var id: int = member.get_instance_id()
	if not _members.has(id):
		return
	_members.erase(id)
	_hungry.erase(id)
	_suppliers.erase(id)
	_dirty_suppliers.erase(id)
	member.state_changed.disconnect(_member_changed.bind(id))
	member.inventory_changed.disconnect(_inventory_changed.bind(id))
	member.tree_exiting.disconnect(_untrack.bind(member))
	# Actor teardown clears capabilities before its tree_exiting notification.
	var needs = member.get_needs()
	if needs != null and needs.food_need_changed.is_connected(_need_changed.bind(id)):
		needs.food_need_changed.disconnect(_need_changed.bind(id))


func _membership_changed(member: WorldActor, _party_id: String) -> void:
	# Membership is announced before the actor's party flag is updated.
	_refresh_membership.call_deferred(weakref(member))


func _refresh_membership(reference: WeakRef) -> void:
	var member = reference.get_ref()
	if not is_instance_valid(member) or _party == null:
		return
	if _party.party_members.has(member):
		_track(member)
		_member_changed(member.get_instance_id())
	else:
		_untrack(member)


func _member_changed(id: int) -> void:
	if not _members.has(id):
		return
	_inventory_changed(id)
	_need_changed(id)


func _inventory_changed(id: int) -> void:
	_dirty_suppliers[id] = true
	_queue_check()


func _need_changed(id: int) -> void:
	var member = _members.get(id)
	if is_instance_valid(member) and member.is_player_party_member() and member.life_state == NpcRules.LifeState.ALIVE and member.get_needs().wants_food():
		_hungry[id] = member
	else:
		_hungry.erase(id)
	_queue_check()


func _queue_check() -> void:
	if not _check_queued:
		_check_queued = true
		check_pending_meals.call_deferred()


func _on_minute(_minute: int, _day: int, _hour: int, _minute_of_hour: int) -> void:
	if not _hungry.is_empty() and not _suppliers.is_empty():
		check_pending_meals()


func _on_world_reindexed() -> void:
	# Population hydration is deferred too; its needs/state signals wake us after
	# load. Never consume against old projections during the load boundary.
	_hungry.clear()
	_suppliers.clear()
	_dirty_suppliers.clear()
	_rebuild_after_load.call_deferred()


func _rebuild_after_load() -> void:
	for id in _members.keys():
		_member_changed(id)


func check_pending_meals() -> void:
	_check_queued = false
	if _checking or _gecs == null:
		return
	_checking = true
	var dirty := _dirty_suppliers.keys()
	_dirty_suppliers.clear()
	for id in dirty:
		var donor = _members.get(id)
		if is_instance_valid(donor) and _has_food(donor):
			_suppliers[id] = donor
		else:
			_suppliers.erase(id)
	if not _suppliers.is_empty():
		for id in _hungry.keys():
			var recipient = _hungry.get(id)
			if not is_instance_valid(recipient) or recipient.is_queued_for_deletion() or not recipient.is_inside_tree():
				continue
			for nearby in _gecs.get_nearby_actors(recipient.global_position, settings.distance, true):
				if _suppliers.has(nearby.get_instance_id()) and _feed(nearby, recipient):
					break
	_checking = false


func _has_food(donor: WorldActor) -> bool:
	if not is_instance_valid(donor) or donor.is_queued_for_deletion() or not donor.share_food_enabled \
		or not donor.is_player_party_member() or donor.life_state != NpcRules.LifeState.ALIVE \
		or not donor.get_inventory().can_transfer_display_inventory_to(donor):
		return false
	var bag := donor.get_equipped_item("backpack")
	if bag == null or not bag.has_storage():
		return false
	var id := donor.get_equipment().get_equipped_stack_id("backpack")
	var storage := donor.inventory.get_bound_item_storage(id)
	if storage != null:
		for entry in storage.entries:
			if entry.count > 0 and entry.definition.nutrition_value > 0:
				return true
		return false
	var metadata: Dictionary = _gecs.get_item_stack(id).get("metadata", {})
	for entry in metadata.get(InventoryData.ITEM_STORAGE_KEY, {}).get("entries", []):
		var path := str(entry.get("item_definition_path", ""))
		if path.is_empty() or int(entry.get("count", 0)) <= 0:
			continue
		if not _nutrition_by_path.has(path):
			var definition = load(path) as ItemDefinition
			_nutrition_by_path[path] = definition.nutrition_value if definition != null else 0.0
		if float(_nutrition_by_path[path]) > 0:
			return true
	return false


func _feed(donor: WorldActor, recipient: WorldActor) -> bool:
	if donor == recipient:
		return false
	var id := donor.get_equipment().get_equipped_stack_id("backpack")
	var storage := donor.inventory.get_bound_item_storage(id)
	var temporary_view: Node
	if storage == null:
		temporary_view = STORAGE_VIEW.new()
		if not temporary_view.bind(donor, id, _gecs):
			temporary_view.free()
			return false
		add_child(temporary_view)
		storage = temporary_view.inventory
	var eaten := false
	for entry in storage.entries:
		if ITEM_ACTIONS.eat_shared(donor, storage, entry, recipient, settings.distance):
			eaten = true
			break
	if temporary_view != null:
		temporary_view.free()
	return eaten


func _exit_tree() -> void:
	for member in _members.values():
		_untrack(member)
	# Pending actors are deliberately absent from _members until ready.
	if is_instance_valid(_party):
		for member in _party.party_members:
			_untrack(member)
