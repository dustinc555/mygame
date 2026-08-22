@tool
extends Resource

class_name BulkStorageDisplayProfile

@export var item_definition: ItemDefinition
@export var unit_scene: PackedScene
@export var label_texture: Texture2D
@export_category("Batched Display")
@export var body_mesh: Mesh
@export var body_material: Material
@export var body_local_transform := Transform3D.IDENTITY
@export var stem_mesh: Mesh
@export var stem_material: Material
@export var stem_local_transform := Transform3D.IDENTITY
@export var accent_mesh: Mesh
@export var accent_material: Material
@export_range(1, 8, 1) var accents_per_unit := 1
@export var accent_local_transform := Transform3D.IDENTITY
@export_category("Layout")
@export_range(1, 1000, 1) var capacity := 50
@export_range(1, 100, 1) var units_per_visual := 2
@export_range(1, 12, 1) var base_columns := 4
@export_range(1, 12, 1) var base_rows := 4
@export_range(1, 6, 1) var upper_columns := 3
@export_range(1, 6, 1) var upper_rows := 3
@export var spacing := Vector2(0.17, 0.15)
@export var layer_height := 0.105
@export_category("Stacked Container Layout")
@export_range(1, 12, 1) var layer_columns := 1
@export_range(1, 12, 1) var layer_rows := 1
@export_range(1, 12, 1) var max_layers := 1


func matches(definition: ItemDefinition) -> bool:
	if item_definition == null or definition == null:
		return false
	if not item_definition.item_id.is_empty() and item_definition.item_id == definition.item_id:
		return true
	return item_definition.resource_path == definition.resource_path


func representative_count(quantity: int) -> int:
	if quantity <= 0:
		return 0
	var capped_quantity := mini(quantity, capacity)
	return mini(
		ceili(float(capped_quantity) / float(maxi(1, units_per_visual))),
		visual_capacity()
	)


func uses_batched_display() -> bool:
	return body_mesh != null


func uses_stacked_container_layout() -> bool:
	return unit_scene != null and layer_columns > 0 and layer_rows > 0 and max_layers > 1


func visual_capacity() -> int:
	if uses_stacked_container_layout():
		return layer_columns * layer_rows * max_layers
	return base_columns * base_rows + upper_columns * upper_rows
