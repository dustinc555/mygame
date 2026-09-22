extends Node

class_name MerchantRole

@export var prices: Array[Resource] = []
@export var initial_stock: Array[Resource] = []
@export var shop_inventory_columns := 15
@export var shop_inventory_rows := 12
@export var shop_inventory_max_weight := 0.0
@export var shop_inventory_uses_weight := false
## Empty preserves existing inn/standalone merchant pricing and seeding.
var trading_policy: Dictionary = {}
## Optional projection-side service gate. Prices recheck this at transaction
## time, so an open trade window cannot extend a scheduled shop's hours.
var trade_availability: Callable

var shop_inventory: InventoryData
var _stock_seeded := false
var _gecs_world: Node
var _container_id := ""
var _inventory_sync_suspended := false
var _pending_trader_ids: Dictionary = {}

signal shop_inventory_changed


func _ready() -> void:
	_ensure_shop_inventory()
	call_deferred("_initialize_shop_inventory")


func get_shop_inventory() -> InventoryData:
	_ensure_shop_inventory()
	return shop_inventory


func register_trader(member: Node) -> void:
	if member != null:
		_pending_trader_ids[member.get_instance_id()] = true


func release_trader(member: Node) -> void:
	if member != null:
		_pending_trader_ids.erase(member.get_instance_id())


func resolve_trade(member: Node) -> bool:
	if member == null or not _pending_trader_ids.has(member.get_instance_id()):
		return false
	_pending_trader_ids.erase(member.get_instance_id())
	return is_available_for_trade()


func is_available_for_trade() -> bool:
	return trade_availability.is_null() or (trade_availability.is_valid() and bool(trade_availability.call()))


func _ensure_shop_inventory() -> void:
	if shop_inventory != null:
		return
	shop_inventory = InventoryData.new(shop_inventory_columns, shop_inventory_rows, shop_inventory_max_weight, shop_inventory_uses_weight)
	shop_inventory.changed.connect(_on_shop_inventory_changed)


func _initialize_shop_inventory() -> void:
	# Roles may be attached after actor registration. Reuse the same shared
	# inventory binding rather than persisting individual trade gestures.
	var bridge := BootstrapContext.service(GecsWorldController.SERVICE_ID)
	if bridge != null:
		bridge.call("sync_actor_inventory", get_parent())
		var supply := BootstrapContext.service(&"merchant_supply")
		if supply != null and not trading_policy.is_empty():
			supply.call("register_merchant", self, _container_id)
	else:
		_seed_shop_inventory()


func bind_inventory_state(bridge: Node, actor_id: String) -> void:
	var container_id := "%s.shop_inventory" % actor_id
	if _gecs_world == bridge and _container_id == container_id:
		return
	if is_instance_valid(_gecs_world) and _gecs_world.world_reindexed.is_connected(_restore_shop_inventory):
		_gecs_world.world_reindexed.disconnect(_restore_shop_inventory)
	_gecs_world = bridge
	_container_id = container_id
	_gecs_world.world_reindexed.connect(_restore_shop_inventory)
	_ensure_shop_inventory()
	if not _restore_shop_inventory():
		shop_inventory.configure_stack_allocator(_container_id, shop_inventory.next_stack_sequence)
		_seed_shop_inventory()


func is_inventory_sync_suspended() -> bool:
	return _inventory_sync_suspended


func _restore_shop_inventory() -> bool:
	var entity = _gecs_world.call("get_inventory_container_entity", _container_id)
	if entity == null:
		return false
	var container = entity.get_component(_gecs_world.C_INVENTORY_CONTAINER)
	if container == null:
		return false
	# Container existence, not a nonempty stack list, distinguishes initialized
	# stock. Hydration must never grant the authored starting goods again.
	_inventory_sync_suspended = true
	_stock_seeded = true
	if not container.merchant_policy.is_empty():
		trading_policy = container.merchant_policy.duplicate(true)
	shop_inventory.entries.clear()
	shop_inventory.columns = int(container.columns)
	shop_inventory.rows = int(container.rows)
	shop_inventory.max_weight = float(container.max_weight)
	shop_inventory.configure_stack_allocator(_container_id, int(container.next_stack_sequence))
	for snapshot in _gecs_world.call("get_inventory_stacks", _container_id):
		var definition := load(str(snapshot.item_definition_path)) as ItemDefinition
		if not shop_inventory.hydrate_entry_with_contents(definition, snapshot.grid_position, int(snapshot.count), snapshot.contained_item_counts, snapshot.metadata, str(snapshot.stack_id), false):
			push_error("MerchantRole could not restore stock '%s'" % str(snapshot.stack_id))
	shop_inventory.changed.emit()
	_inventory_sync_suspended = false
	return true


func _seed_shop_inventory() -> void:
	if _stock_seeded:
		return
	_stock_seeded = true
	_ensure_shop_inventory()
	_inventory_sync_suspended = true
	for stock in initial_stock:
		if stock != null and stock.item_definition != null and stock.quantity > 0:
			if not shop_inventory.add_item_count(stock.item_definition, stock.quantity):
				push_error("Merchant starting stock does not fit: %s" % stock.item_definition.display_name)
	_inventory_sync_suspended = false


func _on_shop_inventory_changed() -> void:
	shop_inventory_changed.emit()
	var owner_character = get_parent()
	if owner_character != null and owner_character.has_signal("inventory_changed"):
		owner_character.inventory_changed.emit()


func get_buy_price(definition: ItemDefinition) -> int:
	if not is_available_for_trade(): return -1
	for price in prices:
		if price.item_definition == definition:
			return price.buy_price
	return _policy_price(definition, "buy_price")


func get_sell_price(definition: ItemDefinition) -> int:
	if not is_available_for_trade(): return -1
	for price in prices:
		if price.item_definition == definition:
			return price.sell_price
	return _policy_price(definition, "sell_price")


func _policy_price(definition: ItemDefinition, key: String) -> int:
	if definition == null or not definition.sellable or definition.is_currency_item() or trading_policy.is_empty():
		return -1
	var rules: Dictionary = trading_policy.get("stock", {})
	if key == "buy_price" and not bool(trading_policy.get("buys_any", false)) and not rules.has(definition.resource_path):
		return -1
	return int((rules.get(definition.resource_path, {}) as Dictionary).get(key, trading_policy.get(key, -1)))
