@tool
extends RefCounted

class_name CharacterAppearanceCatalog

const STYLE_DIRECTORY := "res://features/actors/resources/character_appearance"
const SLOT_HAIR := 0
const SLOT_BEARD := 1
const SLOT_EYEBROWS := 2

static var _styles_by_slot: Dictionary = {}


static func get_hair_styles() -> Array[Resource]:
	return _get_styles_for_slot(SLOT_HAIR)


static func get_beard_styles() -> Array[Resource]:
	return _get_styles_for_slot(SLOT_BEARD)


static func get_eyebrow_styles() -> Array[Resource]:
	return _get_styles_for_slot(SLOT_EYEBROWS)


static func clear_cache() -> void:
	_styles_by_slot.clear()


static func _get_styles_for_slot(slot: int) -> Array[Resource]:
	_ensure_loaded()
	return (_styles_by_slot.get(slot, []) as Array[Resource]).duplicate()


static func _ensure_loaded() -> void:
	if not _styles_by_slot.is_empty():
		return
	_styles_by_slot = {
		SLOT_HAIR: [] as Array[Resource],
		SLOT_BEARD: [] as Array[Resource],
		SLOT_EYEBROWS: [] as Array[Resource],
	}
	var file_names := Array(DirAccess.get_files_at(STYLE_DIRECTORY))
	file_names.sort()
	for file_name_value in file_names:
		var file_name := str(file_name_value)
		if not file_name.ends_with(".tres"):
			continue
		var style := load("%s/%s" % [STYLE_DIRECTORY, file_name]) as Resource
		if style == null or not style.has_method("get_slot_id"):
			continue
		var slot := int(style.get("slot"))
		var styles := _styles_by_slot.get(slot, []) as Array[Resource]
		styles.append(style)
		_styles_by_slot[slot] = styles
	for slot_value in _styles_by_slot.keys():
		var styles := _styles_by_slot[slot_value] as Array[Resource]
		styles.sort_custom(func(left: Resource, right: Resource) -> bool:
			return str(left.get("style_id")) < str(right.get("style_id"))
		)
