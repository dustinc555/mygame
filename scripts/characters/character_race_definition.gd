@tool
extends Resource

class_name CharacterRaceDefinition

@export var race_id := ""
@export var display_name := "Race"
@export var equipment_slots: PackedStringArray = PackedStringArray()
@export var equipment_slot_labels: Dictionary = {}
@export var default_male_archetype: Resource
@export var default_female_archetype: Resource


func get_equipment_slots() -> Array[String]:
	var slots: Array[String] = []
	for slot_name in equipment_slots:
		slots.append(str(slot_name))
	return slots


func get_slot_label(slot_name: String) -> String:
	return str(equipment_slot_labels.get(slot_name, slot_name.capitalize()))
