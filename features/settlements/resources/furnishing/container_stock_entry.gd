@tool
extends Resource

class_name ContainerStockEntry

## One line of a ContainerStockTable: an item that MAY appear in a furnished
## container, with how likely and how many.

@export var item_definition: ItemDefinition
@export_range(0.0, 1.0, 0.05) var chance := 1.0
@export var min_quantity := 1
@export var max_quantity := 1
