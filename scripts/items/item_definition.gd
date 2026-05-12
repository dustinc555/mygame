extends Resource

class_name ItemDefinition

const EQUIP_SLOT_NONE := ""
const EQUIP_SLOT_UNDERSHIRT := "undershirt"
const EQUIP_SLOT_HANDS := "hands"
const EQUIP_SLOT_HEAD := "head"
const EQUIP_SLOT_CHEST := "chest"
const EQUIP_SLOT_BACKPACK := "backpack"
const EQUIP_SLOT_LEGS := "legs"
const EQUIP_SLOT_FEET := "feet"
const EQUIP_SLOT_WEAPON := "weapon"
const EQUIP_SLOT_OFFHAND := "offhand"

@export var display_name := "Item"
@export var icon: Texture2D
@export var grid_size := Vector2i(1, 1)
@export var unit_weight := 1.0
@export var max_stack := 1
@export var nutrition_value := 0.0
@export var bandage_power := 0.0
@export var equip_slot := EQUIP_SLOT_NONE
@export var alternate_equip_slots: PackedStringArray = PackedStringArray()
@export var world_scene: PackedScene
@export var equipped_scene: PackedScene
@export var equipped_visuals: Array[Resource] = []
@export var grip_profile: Resource
@export var equipped_transform := Transform3D.IDENTITY
@export var stat_modifiers: Array[ItemStatModifier] = []


func is_equippable() -> bool:
	return not equip_slot.is_empty()


func can_equip_to_slot(slot_name: String) -> bool:
	if slot_name.is_empty():
		return false
	if equip_slot == slot_name:
		return true
	return alternate_equip_slots.has(slot_name)


func get_equipment_visual_for_body_archetype(body_archetype: Resource) -> Resource:
	if body_archetype == null:
		return null
	for visual in equipped_visuals:
		if visual != null and visual.has_method("matches_body_archetype") and visual.matches_body_archetype(body_archetype):
			return visual
	return null


func get_equipped_scene_for_body_archetype(body_archetype: Resource) -> PackedScene:
	var visual := get_equipment_visual_for_body_archetype(body_archetype)
	if visual != null:
		var visual_scene := visual.get("visual_scene") as PackedScene
		if visual_scene != null:
			return visual_scene
	return equipped_scene
