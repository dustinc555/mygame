extends SceneTree
## Runtime equipment must survive population LOD snapshots.

class RuntimeEquipment:
	extends RefCounted
	var equipped_items: Dictionary = {}
	func get_equipped_items() -> Dictionary:
		return equipped_items

class RuntimeEquipmentActor:
	extends Node
	var equipped_items = null
	var starting_equipment: Array[Resource] = []
	var equipment := RuntimeEquipment.new()
	func get_equipment():
		return equipment


func _initialize() -> void:
	var population = (load("res://features/world_sim/sim/population/population_controller.gd") as Script).new()
	var actor := RuntimeEquipmentActor.new()
	actor.equipment.equipped_items["weapon"] = load("res://features/inventory/resources/items/hoe.tres")
	var slots: Dictionary = population.call("_equipment_slots_from_actor", actor)
	actor.free()
	population.free()
	if str(slots.get("weapon", "")) != "res://features/inventory/resources/items/hoe.tres":
		push_error("Population LOD snapshot dropped EquipmentCapability weapon")
		quit(1)
		return
	print("POPULATION_EQUIPMENT_LOD_OK")
	quit(0)
