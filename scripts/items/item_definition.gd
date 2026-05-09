extends Resource

class_name ItemDefinition

const EQUIP_SLOT_NONE := ""
const EQUIP_SLOT_HEAD := "head"
const EQUIP_SLOT_CHEST := "chest"
const EQUIP_SLOT_BACKPACK := "backpack"
const EQUIP_SLOT_LEGS := "legs"
const EQUIP_SLOT_GLOVES := "gloves"
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
@export var male_equipped_scene: PackedScene
@export var female_equipped_scene: PackedScene
@export var grip_profile: Resource
@export var equipped_transform := Transform3D.IDENTITY
@export_range(0.0, 0.08, 0.001) var equipped_surface_offset_ratio := 0.0
@export var stat_modifiers: Array[ItemStatModifier] = []


func is_equippable() -> bool:
	return not equip_slot.is_empty()


func can_equip_to_slot(slot_name: String) -> bool:
	if slot_name.is_empty():
		return false
	if equip_slot == slot_name:
		return true
	return alternate_equip_slots.has(slot_name)


func get_equipped_scene_for_body_type(body_type: int) -> PackedScene:
	if body_type == 3 and female_equipped_scene != null:
		return female_equipped_scene
	if body_type == 2 and male_equipped_scene != null:
		return male_equipped_scene
	if equipped_scene != null:
		return equipped_scene
	if male_equipped_scene != null:
		return male_equipped_scene
	return female_equipped_scene
