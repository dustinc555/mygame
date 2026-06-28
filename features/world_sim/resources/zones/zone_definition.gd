extends Resource

class_name ZoneDefinition

@export var zone_id := ""
@export var display_name := "Zone"
@export var random_seed := 1
@export var minimum_initial_active_nests := 0
@export var generated := false
@export var faction_definitions: Array[Resource] = []
@export var settlement_placements: Array[Resource] = []
@export var starting_relations: Array[Resource] = []
@export var squad_templates: Array[Resource] = []


func get_id() -> String:
	return zone_id if not zone_id.is_empty() else display_name


func get_settlement_definitions() -> Array[Resource]:
	var definitions: Array[Resource] = []
	var seen_ids := {}
	for placement in settlement_placements:
		if placement == null:
			continue
		var definition := placement.get("settlement_definition") as Resource
		if definition == null:
			continue
		var definition_id := _resource_id(definition)
		if definition_id.is_empty() or seen_ids.has(definition_id):
			continue
		seen_ids[definition_id] = true
		definitions.append(definition)
	return definitions


func get_all_faction_definitions() -> Array[Resource]:
	var definitions: Array[Resource] = []
	var seen_ids := {}
	for definition in faction_definitions:
		_add_faction_definition(definitions, seen_ids, definition)
	for settlement_definition in get_settlement_definitions():
		_add_faction_definition(definitions, seen_ids, settlement_definition.get("faction_definition") as Resource)
	for template in squad_templates:
		if template != null:
			_add_faction_definition(definitions, seen_ids, template.get("faction_definition") as Resource)
	return definitions


func _add_faction_definition(definitions: Array[Resource], seen_ids: Dictionary, definition: Resource) -> void:
	if definition == null:
		return
	var definition_id := _resource_id(definition)
	if definition_id.is_empty() or seen_ids.has(definition_id):
		return
	seen_ids[definition_id] = true
	definitions.append(definition)


func _resource_id(definition: Resource) -> String:
	if definition != null and definition.has_method("get_id"):
		return str(definition.call("get_id")).strip_edges()
	return ""
