@tool
extends Resource

class_name CharacterRaceDefinition

const DEFAULT_SLOT_GRID_SIZES: Dictionary[String, Vector2i] = {
	"head": Vector2i(2, 2),
	"chest": Vector2i(2, 3),
	"legs": Vector2i(2, 2),
	"feet": Vector2i(2, 2),
	"hands": Vector2i(2, 2),
	"undershirt": Vector2i(2, 2),
	"backpack": Vector2i(2, 3),
	"weapon": Vector2i(2, 3),
	"offhand": Vector2i(2, 3),
}

@export var race_id := ""
@export var display_name := "Race"
@export var equipment_slots: PackedStringArray = PackedStringArray()
@export var equipment_slot_labels: Dictionary = {}
## Width/height in square UI cells for this race's equipment areas.
## These size the presentation, not bag footprints or equipment eligibility.
@export var equipment_slot_grid_sizes: Dictionary[String, Vector2i] = DEFAULT_SLOT_GRID_SIZES.duplicate()
@export var bleed_fluid: Resource
@export var default_male_archetype: Resource
@export var default_female_archetype: Resource


func get_equipment_slots() -> Array[String]:
	var slots: Array[String] = []
	for slot_name in equipment_slots:
		slots.append(str(slot_name))
	return slots


func get_slot_label(slot_name: String) -> String:
	return str(equipment_slot_labels.get(slot_name, slot_name.capitalize()))


func get_slot_grid_size(slot_name: String) -> Vector2i:
	var cells: Vector2i = equipment_slot_grid_sizes.get(slot_name, default_slot_grid_size(slot_name))
	return Vector2i(maxi(1, cells.x), maxi(1, cells.y))


static func default_slot_grid_size(slot_name: String) -> Vector2i:
	return DEFAULT_SLOT_GRID_SIZES.get(slot_name, Vector2i(2, 2))
