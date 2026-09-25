@tool
extends Resource

class_name ContainerStockTable

## Seeded loot recipe for furnish-placed containers (crates/barrels). The
## furnisher rolls one stock list per placed container using the furnish RNG,
## so contents vary between containers but are deterministic per layout seed.
## One .tres per facility type's flavor (bar_container_stock.tres first).

@export var entries: Array[ContainerStockEntry] = []
## Zero preserves independent chances. Positive values pick from the pool with
## replacement, using chance as relative weight; valid pools cannot roll empty.
@export_range(0, 32, 1) var weighted_draws := 0


## Roll the table into concrete stock. Returns the InventoryStock list that
## gets baked into the placed WorldContainer's starting_items. Each entry
## rolls independently — an all-miss (empty container) is legitimate flavor.
func roll(rng: RandomNumberGenerator, capacity: InventoryData = null) -> Array[InventoryStock]:
	var stocks: Array[InventoryStock] = []
	if weighted_draws > 0:
		return _roll_pool(rng, capacity)
	for entry in entries:
		if entry == null or entry.item_definition == null:
			continue
		if rng.randf() > entry.chance:
			continue
		var stock := InventoryStock.new()
		stock.item_definition = entry.item_definition
		stock.quantity = rng.randi_range(entry.min_quantity, maxi(entry.min_quantity, entry.max_quantity))
		stock.quantity = _fit_quantity(capacity, stock.item_definition, stock.quantity)
		if stock.quantity > 0:
			stocks.append(stock)
	return stocks


func _roll_pool(rng: RandomNumberGenerator, capacity: InventoryData) -> Array[InventoryStock]:
	var stocks: Array[InventoryStock] = []
	for draw in weighted_draws:
		var candidates: Array[ContainerStockEntry] = []
		var total := 0.0
		for entry in entries:
			if entry == null or entry.item_definition == null or entry.chance <= 0.0:
				continue
			if capacity != null and not capacity.can_add_item_count(entry.item_definition, 1):
				continue
			candidates.append(entry)
			total += entry.chance
		if total <= 0.0:
			break
		var pick := rng.randf() * total
		for entry in candidates:
			pick -= entry.chance
			if pick > 0.0:
				continue
			var stock: InventoryStock = null
			for existing in stocks:
				if existing.item_definition == entry.item_definition:
					stock = existing
					break
			if stock == null:
				stock = InventoryStock.new()
				stock.item_definition = entry.item_definition
				stock.quantity = 0
				stocks.append(stock)
			var quantity := rng.randi_range(maxi(1, entry.min_quantity), maxi(1, maxi(entry.min_quantity, entry.max_quantity)))
			stock.quantity += _fit_quantity(capacity, entry.item_definition, quantity)
			break
	return stocks


## The optional scratch inventory uses the real packing/stacking rules. It is
## filled as rolls are accepted; no live container or saved loot is mutated.
func _fit_quantity(capacity: InventoryData, item: ItemDefinition, requested: int) -> int:
	if capacity == null:
		return requested
	var quantity := requested
	while quantity > 0 and not capacity.can_add_item_count(item, quantity):
		quantity -= 1
	if quantity > 0:
		capacity.add_item_count(item, quantity)
	return quantity
