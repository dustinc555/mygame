extends Node

class_name MerchantRole

@export var prices: Array[Resource] = []
@export var initial_stock: Array[Resource] = []


func _ready() -> void:
	call_deferred("_seed_inventory")


func _seed_inventory() -> void:
	var owner_character = get_parent()
	if owner_character == null:
		return
	for stock in initial_stock:
		if stock.item_definition != null and stock.quantity > 0:
			owner_character.inventory.add_item_count(stock.item_definition, stock.quantity)


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
