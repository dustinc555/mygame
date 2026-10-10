@tool
extends Resource

@export var scene: PackedScene
@export_enum("center", "fire", "container", "seat", "guard") var purpose := "container"
@export_range(0, 32, 1) var minimum := 1
@export_range(0, 32, 1) var maximum := 1
## Ensures enough usable positions as camp population increases.
@export_range(0.0, 1.0, 0.1) var per_resident := 0.0
@export var stock_pool: ContainerStockTable
