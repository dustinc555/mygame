@tool
extends Resource
class_name MerchantProfile

## Shared defaults only. Individual facilities overlay stock without editing
## this resource. Once initialized, GECS owns the character's trading policy.
@export var display_name := "General Trader"
@export var buys_any_sellable_item := true
@export_range(0, 100000, 1) var default_buy_price := 1
@export_range(0, 100000, 1) var default_sell_price := 2
## Item resource path -> {quantity, replenishes, optional buy_price/sell_price}.
@export var stock: Dictionary = {}
