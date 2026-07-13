@tool
@icon("res://addons/world_authoring/icons/faction.svg")
extends Node

class_name Faction

## Authoring node for one faction: a child of the Factions root wrapping a
## FactionDefinition resource (the on-disk truth under
## features/factions/resources/factions). The node is pure editor
## affordance — the Factions dock edits and saves the definition; runtime
## systems only ever see the resource, registered through the Factions root.

@export var definition: FactionDefinition:
	set(value):
		definition = value
		if Engine.is_editor_hint():
			update_configuration_warnings()
			_sync_name_to_definition()


func _ready() -> void:
	if Engine.is_editor_hint():
		_sync_name_to_definition()


func get_faction_id() -> String:
	return definition.get_id() if definition != null else ""


func _sync_name_to_definition() -> void:
	if definition == null:
		return
	var display := definition.display_name.strip_edges()
	if not display.is_empty() and str(name) != display.to_pascal_case():
		name = display.to_pascal_case()


func _get_configuration_warnings() -> PackedStringArray:
	if definition == null:
		return PackedStringArray(["Assign a FactionDefinition (or create one from the Factions dock)."])
	return PackedStringArray()
