extends Node

class_name MerchantRole

@export var prices: Array[Resource] = []
@export var initial_stock: Array[Resource] = []
@export var shop_inventory_columns := 15
@export var shop_inventory_rows := 12
@export var shop_inventory_max_weight := 0.0
@export var shop_inventory_uses_weight := false

var shop_inventory: InventoryData
var _stock_seeded := false

signal shop_inventory_changed


func _ready() -> void:
	_ensure_shop_inventory()
	call_deferred("_seed_shop_inventory")


func get_shop_inventory() -> InventoryData:
	_ensure_shop_inventory()
	return shop_inventory


func _ensure_shop_inventory() -> void:
	if shop_inventory != null:
		return
	shop_inventory = InventoryData.new(shop_inventory_columns, shop_inventory_rows, shop_inventory_max_weight, shop_inventory_uses_weight)
	shop_inventory.changed.connect(_on_shop_inventory_changed)


func _seed_shop_inventory() -> void:
	if _stock_seeded:
		return
	_stock_seeded = true
	_ensure_shop_inventory()
	for stock in initial_stock:
		if stock.item_definition != null and stock.quantity > 0:
			shop_inventory.add_item_count(stock.item_definition, stock.quantity)


func _on_shop_inventory_changed() -> void:
	shop_inventory_changed.emit()
	var owner_character = get_parent()
	if owner_character != null and owner_character.has_signal("inventory_changed"):
		owner_character.inventory_changed.emit()


func get_buy_price(definition: ItemDefinition) -> int:
	for price in prices:
		if price.item_definition == definition:
			return price.buy_price
	return -1


func get_sell_price(definition: ItemDefinition) -> int:
	for price in prices:
		if price.item_definition == definition:
			return price.sell_price
	return -1


func get_job_provider() -> JobProvider:
	var owner_character = get_parent()
	if owner_character == null:
		return null
	return owner_character.get_node_or_null("JobProvider") as JobProvider
