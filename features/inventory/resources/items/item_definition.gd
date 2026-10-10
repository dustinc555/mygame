@tool
extends Resource

class_name ItemDefinition

const CombatAudioProfile = preload("res://features/combat/resources/combat_item_audio_profile.gd")

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
## Independent item-owned slots, not character slots. Zero disables storage.
## Changed dimensions apply when the bag is next opened; saved goods are retained.
@export var storage_grid_size := Vector2i.ZERO
## Total hunger points this food restores, dripped in over the food effect
## duration (NpcRules.FOOD_EFFECT_DURATION_SECONDS). 100 points = one full bar.
@export var nutrition_value := 0.0
@export var bandage_power := 0.0
@export_range(0, 100, 1) var bandage_max_uses := 0
@export var equip_slot := EQUIP_SLOT_NONE
## Shared audio-only contact classification; does not change damage or protection.
@export var combat_audio: CombatAudioProfile
@export var alternate_equip_slots: PackedStringArray = PackedStringArray()
## Empty means unrestricted. Fit affects equipping only, never carrying or trading.
@export var compatible_races: PackedStringArray = PackedStringArray()
## Anatomy restriction, independent of race names and inventory/trade access.
@export var humanoid_only := false
@export var world_scene: PackedScene
@export var world_visual_height_meters := 0.0
@export var world_visual_long_axis_meters := 0.0
@export var equipped_scene: PackedScene
@export var equipped_visuals: Array[Resource] = []
@export var grip_profile: Resource
@export var equipped_transform := Transform3D.IDENTITY
@export var stat_modifiers: Array[ItemStatModifier] = []
@export var tool_tags: PackedStringArray = PackedStringArray()
## Total strain a lockpick tolerates. Current wear is inventory-entry metadata.
@export_range(1.0, 500.0, 1.0) var lockpick_durability := 60.0
@export var access_key_ids: PackedStringArray = PackedStringArray()
@export var currency_id := ""
@export_range(0, 1000000, 1) var currency_container_capacity := 0
@export var sellable := true
## Typed interaction handled by ItemReadBridge. Empty items have no Read action.
@export var read_behavior := ReadBehavior.NONE
@export var read_title := ""


func is_equippable() -> bool:
	return not equip_slot.is_empty()


func has_storage() -> bool:
	return storage_grid_size.x > 0 and storage_grid_size.y > 0


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


func fits_race(race_id: String) -> bool:
	return compatible_races.is_empty() or compatible_races.has(race_id)


func get_equipment_visual_for_body_archetype(body_archetype: Resource, body_scene_path: String = "") -> Resource:
	if body_archetype == null:
		return null
	for visual in equipped_visuals:
		if visual != null and visual.has_method("matches_body_archetype") and visual.matches_body_archetype(body_archetype):
			if not body_scene_path.is_empty() and visual.has_method("for_body_scene"):
				return visual.for_body_scene(body_scene_path)
			return visual
	return null


func get_equipped_scene_for_body_archetype(body_archetype: Resource, body_scene_path: String = "") -> PackedScene:
	var visual := get_equipment_visual_for_body_archetype(body_archetype, body_scene_path)
	if visual != null:
		var visual_scene := visual.get("visual_scene") as PackedScene
		if visual_scene != null:
			return visual_scene
	if has_clothing_binding():
		return null
	return equipped_scene


func has_clothing_binding() -> bool:
	for visual: Resource in equipped_visuals:
		if visual != null and visual.get("clothing_binding") != null:
			return true
	return false
