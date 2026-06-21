extends Resource

class_name SettlementPlacement

@export var placement_id := ""
@export var settlement_definition: Resource
@export var town_scene: PackedScene
@export var world_transform: Transform3D = Transform3D.IDENTITY
@export_enum("full_town", "important_plus_near", "near_player") var realization_policy := "near_player"
@export var road_connection_ids: PackedStringArray = PackedStringArray()


func get_id() -> String:
	if not placement_id.is_empty():
		return placement_id
	return get_settlement_id()


func get_settlement_id() -> String:
	return str(settlement_definition.call("get_id")).strip_edges() if settlement_definition != null and settlement_definition.has_method("get_id") else ""


func get_faction_id() -> String:
	return str(settlement_definition.call("get_faction_id")).strip_edges() if settlement_definition != null and settlement_definition.has_method("get_faction_id") else ""
