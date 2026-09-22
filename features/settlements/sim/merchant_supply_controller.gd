extends Node
class_name MerchantSupplyController

const SERVICE_ID := &"merchant_supply"
const POLICY = preload("res://features/settlements/resources/merchant_stock_policy.gd")
var _gecs: GecsWorldController
var _time: WorldTimeController
var _due: Dictionary = {}
var _live: Dictionary = {}


func initialize(context: BootstrapContext) -> void:
	_gecs = context.require(GecsWorldController.SERVICE_ID)
	_time = context.require(WorldTimeController.SERVICE_ID)
	_gecs.world_reindexed.connect(_rebuild)
	_time.hour_changed.connect(_on_hour_changed)
	_rebuild()


func register_merchant(role: MerchantRole, container_id: String) -> void:
	var container = _container(container_id)
	if container == null: return
	if container.merchant_policy.is_empty():
		container.merchant_policy = role.trading_policy.duplicate(true)
		container.merchant_next_restock_minute = POLICY.first_due_minute(_time.get_absolute_minute(), int(role.trading_policy.get("days", 3)), int(role.trading_policy.get("hour", 8)))
	role.trading_policy = container.merchant_policy.duplicate(true)
	_live[container_id] = weakref(role)
	_due[container_id] = int(container.merchant_next_restock_minute)
	process_due(_time.get_absolute_minute())


func _container(id: String):
	var entity = _gecs.get_inventory_container_entity(id)
	return entity.get_component(_gecs.C_INVENTORY_CONTAINER) if entity != null else null


func _rebuild() -> void:
	_due.clear()
	for id in _gecs.get_merchant_container_ids():
		_due[id] = int(_container(id).merchant_next_restock_minute)
	# Reindexing is not a delivery. In particular, the clock may still hold
	# pre-load time until WorldSimulationController restores it. The next
	# world-time boundary handles due supply after all state is restored.


func _on_hour_changed(_absolute_hour: int, _day: int, _hour: int) -> void:
	process_due(_time.get_absolute_minute())


## No scene walks and no per-frame work. The index contains only businesses;
## hydrate a container only when a supply delivery is actually due.
func process_due(now: int) -> void:
	for id in _due.keys():
		if int(_due[id]) < 0 or now < int(_due[id]): continue
		var container = _container(str(id))
		if container == null:
			_due.erase(id)
			continue
		var policy: Dictionary = container.merchant_policy
		var record := _gecs.get_population_record(str(container.owner_actor_id))
		if not record.is_empty() and int(record.get("life_state", 0)) == NpcRules.LifeState.DEAD:
			_due.erase(id)
			continue
		var role: MerchantRole = _live[id].get_ref() if _live.has(id) else null
		var inventory := role.get_shop_inventory() if is_instance_valid(role) else _hydrate(str(id), container)
		if inventory == null: continue
		var changed := POLICY.replenish(inventory, policy.get("stock", {}))
		if changed and not is_instance_valid(role):
			_gecs.sync_merchant_inventory(str(container.owner_actor_id), inventory)
		# Long time skips top up once, not once for each missed period.
		var next := POLICY.advance_due_minute(int(container.merchant_next_restock_minute), now, int(policy.get("days", 3)))
		container.merchant_next_restock_minute = next
		_due[id] = next


func _hydrate(id: String, container) -> InventoryData:
	var inventory := InventoryData.new(int(container.columns), int(container.rows), float(container.max_weight), false)
	inventory.configure_stack_allocator(id, int(container.next_stack_sequence))
	for stack in _gecs.get_inventory_stacks(id):
		var item := load(str(stack.item_definition_path)) as ItemDefinition
		if not inventory.hydrate_entry_with_contents(item, stack.grid_position, int(stack.count), stack.contained_item_counts, stack.metadata, str(stack.stack_id), false):
			push_error("Merchant supply could not hydrate %s" % id)
			return null
	return inventory
