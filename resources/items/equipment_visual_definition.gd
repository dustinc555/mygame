@tool
extends Resource

class_name EquipmentVisualDefinition

@export var body_archetype: Resource
@export var body_archetype_id := ""
@export var visual_scene: PackedScene
@export var equipped_transform := Transform3D.IDENTITY
@export_range(0.0, 0.08, 0.001) var surface_offset_ratio := 0.0
@export var visual_layer := ""
@export var visual_coverage := ""
@export var replaces_body_slots: PackedStringArray = PackedStringArray()
@export_multiline var visual_notes := ""


func get_body_archetype_id() -> String:
	if body_archetype != null:
		var resource_id := str(body_archetype.get("archetype_id"))
		if not resource_id.is_empty():
			return resource_id
	return body_archetype_id


func matches_body_archetype(archetype: Resource) -> bool:
	if archetype == null:
		return false
	var archetype_id := str(archetype.get("archetype_id"))
	return not archetype_id.is_empty() and get_body_archetype_id() == archetype_id
