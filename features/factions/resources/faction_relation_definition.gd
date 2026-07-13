extends Resource

class_name FactionRelationDefinition

@export var relation_id := ""
@export var faction_a_id := ""
@export var faction_b_id := ""
@export_enum("neutral", "hostile", "war", "truce", "trade", "alliance", "vassal", "tributary", "protectorate") var diplomatic_state := "neutral"
@export_range(-100, 100, 1) var faction_a_outlook_to_b := 0
@export_range(-100, 100, 1) var faction_b_outlook_to_a := 0


func get_id() -> String:
	if not relation_id.is_empty():
		return relation_id
	return "%s:%s" % [faction_a_id, faction_b_id]


func is_valid() -> bool:
	return not faction_a_id.strip_edges().is_empty() and not faction_b_id.strip_edges().is_empty() and faction_a_id != faction_b_id
