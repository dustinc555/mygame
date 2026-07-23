extends Marker3D

class_name TabletopItemSlot

@export var slot_id := ""
@export var required_item: ItemDefinition
## Stock projections are visual offers backed by opted-in town containers.
## They become real inventory items only when an interaction removes stock.
@export var stock_projection := false
@export_range(0.0, 1.0, 0.01) var spawn_chance := 1.0
@export var optional_items: Array[ItemDefinition] = []
@export var optional_weights: PackedFloat32Array = PackedFloat32Array()


func choose_definition(rng: RandomNumberGenerator) -> ItemDefinition:
	if required_item != null:
		return required_item
	if optional_items.is_empty() or rng.randf() > spawn_chance:
		return null
	var total := 0.0
	for index in range(optional_items.size()):
		total += maxf(optional_weights[index] if index < optional_weights.size() else 1.0, 0.0)
	if total <= 0.0:
		return null
	var roll := rng.randf() * total
	for index in range(optional_items.size()):
		roll -= maxf(optional_weights[index] if index < optional_weights.size() else 1.0, 0.0)
		if roll <= 0.0:
			return optional_items[index]
	return optional_items.back()


func choose_available_definition(rng: RandomNumberGenerator, available_items: Dictionary, chance_scale: float) -> ItemDefinition:
	if rng.randf() > spawn_chance * clampf(chance_scale, 0.0, 1.0):
		return null
	var available: Array[ItemDefinition] = []
	var weights := PackedFloat32Array()
	for index in range(optional_items.size()):
		var definition := optional_items[index]
		if definition == null or int(available_items.get(definition.item_id, 0)) <= 0:
			continue
		available.append(definition)
		weights.append(maxf(optional_weights[index] if index < optional_weights.size() else 1.0, 0.0))
	if available.is_empty():
		return null
	var total := 0.0
	for weight in weights:
		total += weight
	var roll := rng.randf() * total
	for index in range(available.size()):
		roll -= weights[index]
		if roll <= 0.0:
			return available[index]
	return available.back()
