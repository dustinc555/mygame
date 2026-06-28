extends Node

class_name ZoneLoader

@export var zone_definition: Resource
@export var town_root_path: NodePath = NodePath("../Towns")
@export var clear_town_root_on_load := true

var faction_definitions: Array[Resource] = []
var settlement_definitions: Array[Resource] = []
var squad_templates: Array[Resource] = []
var relation_definitions: Array[Resource] = []
var loaded_towns: Array[Node] = []


func _ready() -> void:
	add_to_group("zone_loader")
	add_to_group("world_sim_registry")
	_sync_registry_arrays()
	_load_zone_towns()


func get_zone_id() -> String:
	return str(zone_definition.call("get_id")) if zone_definition != null and zone_definition.has_method("get_id") else ""


func get_settlement_placements() -> Array[Resource]:
	var placements: Array[Resource] = []
	if zone_definition == null:
		return placements
	var raw_placements = zone_definition.get("settlement_placements")
	if not (raw_placements is Array):
		return placements
	for placement in raw_placements:
		if placement is Resource:
			placements.append(placement)
	return placements


func _sync_registry_arrays() -> void:
	faction_definitions.clear()
	settlement_definitions.clear()
	squad_templates.clear()
	relation_definitions.clear()
	if zone_definition == null:
		return
	if zone_definition.has_method("get_all_faction_definitions"):
		faction_definitions = zone_definition.call("get_all_faction_definitions")
	else:
		faction_definitions = _resource_array(zone_definition.get("faction_definitions"))
	if zone_definition.has_method("get_settlement_definitions"):
		settlement_definitions = zone_definition.call("get_settlement_definitions")
	else:
		settlement_definitions = _settlement_definitions_from_placements()
	squad_templates = _resource_array(zone_definition.get("squad_templates"))
	relation_definitions = _resource_array(zone_definition.get("starting_relations"))


func _resource_array(value) -> Array[Resource]:
	var result: Array[Resource] = []
	if not (value is Array):
		return result
	for item in value:
		if item is Resource:
			result.append(item)
	return result


func _settlement_definitions_from_placements() -> Array[Resource]:
	var definitions: Array[Resource] = []
	var seen_ids := {}
	for placement in get_settlement_placements():
		if placement == null:
			continue
		var definition := placement.get("settlement_definition") as Resource
		if definition == null:
			continue
		var definition_id := str(definition.call("get_id")) if definition.has_method("get_id") else ""
		if definition_id.is_empty() or seen_ids.has(definition_id):
			continue
		seen_ids[definition_id] = true
		definitions.append(definition)
	return definitions


func _load_zone_towns() -> void:
	var placements := get_settlement_placements()
	if placements.is_empty():
		return
	var town_root := _get_or_create_town_root()
	if town_root == null:
		return
	if clear_town_root_on_load:
		for child in town_root.get_children():
			child.queue_free()
		loaded_towns.clear()
	for placement in placements:
		_load_town_placement(town_root, placement)


func _get_or_create_town_root() -> Node:
	var root := get_node_or_null(town_root_path)
	if root != null:
		return root
	var parent_node := get_parent()
	if parent_node == null:
		return null
	root = Node3D.new()
	root.name = "Towns"
	parent_node.add_child(root)
	return root


func _load_town_placement(town_root: Node, placement: Resource) -> void:
	if placement == null:
		return
	var scene := placement.get("town_scene") as PackedScene
	if scene == null:
		return
	var town := scene.instantiate()
	if town == null:
		return
	var placement_id := str(placement.call("get_id")) if placement.has_method("get_id") else str(placement.get("placement_id"))
	if not placement_id.is_empty():
		town.name = _node_name_from_id(placement_id)
		town.set_meta("settlement_placement_id", placement_id)
	var settlement_definition := placement.get("settlement_definition") as Resource
	if settlement_definition != null and _has_property(town, "settlement_definition"):
		town.set("settlement_definition", settlement_definition)
	if _has_property(town, "actor_realization_policy"):
		town.set("actor_realization_policy", str(placement.get("realization_policy")))
	if town is Node3D:
		var world_transform: Transform3D = placement.get("world_transform")
		(town as Node3D).transform = world_transform
	town_root.add_child(town)
	loaded_towns.append(town)


func _has_property(target: Object, property_name: String) -> bool:
	if target == null:
		return false
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _node_name_from_id(value: String) -> String:
	var result := ""
	for part in value.split("_", false):
		if part.is_empty():
			continue
		result += part.substr(0, 1).to_upper() + part.substr(1).to_lower()
	return result if not result.is_empty() else value
