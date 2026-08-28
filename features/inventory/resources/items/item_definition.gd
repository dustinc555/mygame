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

enum ReadBehavior {
	NONE,
	DUD,
	TOWN_LEDGER,
}

@export var display_name := "Item"
@export var item_id := ""
@export var food_type_id := ""
@export var settlement_food_units := 0.0
@export var icon: Texture2D
@export var grid_size := Vector2i(1, 1)
@export var unit_weight := 1.0
@export var max_stack := 1
## Total hunger points this food restores, dripped in over the food effect
## duration (NpcRules.FOOD_EFFECT_DURATION_SECONDS). 100 points = one full bar.
@export var nutrition_value := 0.0
@export var bandage_power := 0.0
@export_range(0, 100, 1) var bandage_max_uses := 0
@export var equip_slot := EQUIP_SLOT_NONE
@export var alternate_equip_slots: PackedStringArray = PackedStringArray()
@export var world_scene: PackedScene
@export var world_visual_height_meters := 0.0
@export var world_visual_long_axis_meters := 0.0
@export var equipped_scene: PackedScene
@export var equipped_visuals: Array[Resource] = []
@export var grip_profile: Resource
@export var equipped_transform := Transform3D.IDENTITY
@export var stat_modifiers: Array[ItemStatModifier] = []
@export var tool_tags: PackedStringArray = PackedStringArray()
@export var access_key_ids: PackedStringArray = PackedStringArray()
@export var currency_id := ""
@export_range(0, 1000000, 1) var currency_container_capacity := 0
@export var sellable := true
## Typed interaction handled by ItemReadBridge. Empty items have no Read action.
@export var read_behavior := ReadBehavior.NONE
@export var read_title := ""


func is_equippable() -> bool:
	return not equip_slot.is_empty()


func has_tool_tag(tag: String) -> bool:
	var value: Variant = get("tool_tags")
	return not tag.is_empty() and value is PackedStringArray and (value as PackedStringArray).has(tag)


func has_any_tool_tag() -> bool:
	var value: Variant = get("tool_tags")
	return value is PackedStringArray and (value as PackedStringArray).size() > 0


func is_currency_item() -> bool:
	return not currency_id.is_empty() and currency_container_capacity <= 0


func is_currency_container() -> bool:
	return not currency_id.is_empty() and currency_container_capacity > 0


func can_store_currency(definition: ItemDefinition) -> bool:
	return is_currency_container() and definition != null and definition.currency_id == currency_id


func can_equip_to_slot(slot_name: String) -> bool:
	if slot_name.is_empty():
		return false
	if equip_slot == slot_name:
		return true
	return alternate_equip_slots != null and alternate_equip_slots.has(slot_name)


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
