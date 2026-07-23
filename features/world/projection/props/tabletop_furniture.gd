extends StaticBody3D

class_name TabletopFurniture

@export var furniture_type := FurnitureRules.Type.TABLE
@export var surface_id := ""


func _enter_tree() -> void:
	var surface := get_node_or_null("TabletopSurface") as TabletopItemSpawner
	if surface != null and surface.surface_id.strip_edges().is_empty():
		surface.surface_id = surface_id.strip_edges()


func _ready() -> void:
	add_to_group(FurnitureRules.FURNITURE_GROUP)
	FurnitureRules.strip_imported_collision(self)
