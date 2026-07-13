@tool
extends Resource

class_name ContainerStockTable

## Seeded loot recipe for furnish-placed containers (crates/barrels). The
## furnisher rolls one stock list per placed container using the furnish RNG,
## so contents vary between containers but are deterministic per layout seed.
## One .tres per facility type's flavor (bar_container_stock.tres first).

@export var entries: Array[ContainerStockEntry] = []


## Roll the table into concrete stock. Returns the InventoryStock list that
## gets baked into the placed WorldContainer's starting_items. Each entry
## rolls independently — an all-miss (empty container) is legitimate flavor.
func roll(rng: RandomNumberGenerator) -> Array[InventoryStock]:
	var stocks: Array[InventoryStock] = []
	for entry in entries:
		if entry == null or entry.item_definition == null:
			continue
		if rng.randf() > entry.chance:
			continue
		var stock := InventoryStock.new()
		stock.item_definition = entry.item_definition
		stock.quantity = rng.randi_range(entry.min_quantity, maxi(entry.min_quantity, entry.max_quantity))
		stocks.append(stock)
	return stocks
