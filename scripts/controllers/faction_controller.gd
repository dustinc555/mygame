extends Node

class_name FactionController

var root_scene: Node
var faction_definitions: Dictionary = {}
var reputations: Dictionary = {}


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	_collect_definitions()


func _ready() -> void:
	add_to_group("faction_controller")
	_collect_definitions()


func register_faction(definition: Resource) -> void:
	if definition == null:
		return
	var faction_id: String = _resource_id(definition)
	if faction_id.is_empty():
		return
	faction_definitions[faction_id] = definition


func get_faction_definition(faction_id: String) -> Resource:
	return faction_definitions.get(faction_id, null) as Resource


func get_faction_ids() -> Array:
	return faction_definitions.keys()


func are_hostile(faction_a: String, faction_b: String) -> bool:
	if faction_a.is_empty() or faction_b.is_empty() or faction_a == faction_b:
		return false
	var definition_a: Resource = get_faction_definition(faction_a)
	if definition_a != null and (bool(definition_a.get("permanently_hostile")) or _resource_is_hostile_to(definition_a, faction_b)):
		return true
	var definition_b: Resource = get_faction_definition(faction_b)
	return definition_b != null and (bool(definition_b.get("permanently_hostile")) or _resource_is_hostile_to(definition_b, faction_a))


func get_reputation(faction_a: String, faction_b: String) -> int:
	return int(reputations.get(_relation_key(faction_a, faction_b), 0))


func set_reputation(faction_a: String, faction_b: String, value: int) -> void:
	reputations[_relation_key(faction_a, faction_b)] = clampi(value, -100, 100)


func serialize_state() -> Dictionary:
	return {
		"faction_ids": faction_definitions.keys(),
		"reputations": reputations.duplicate(true),
	}


func _collect_definitions() -> void:
	if root_scene == null or not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group("world_sim_registry"):
		var definitions = node.get("faction_definitions")
		if definitions is Array:
			for definition in definitions:
				if definition is Resource:
					register_faction(definition)
	for node in get_tree().get_nodes_in_group("settlement_anchor"):
		var settlement_definition: Resource = node.get("settlement_definition") as Resource
		if settlement_definition != null:
			register_faction(settlement_definition.get("faction_definition") as Resource)


func _relation_key(faction_a: String, faction_b: String) -> String:
	var ids := [faction_a, faction_b]
	ids.sort()
	return "%s:%s" % [ids[0], ids[1]]


func _resource_id(definition: Resource) -> String:
	if definition != null and definition.has_method("get_id"):
		return str(definition.call("get_id"))
	return ""


func _resource_is_hostile_to(definition: Resource, other_faction_id: String) -> bool:
	if definition == null or other_faction_id.is_empty():
		return false
	if definition.has_method("is_hostile_to"):
		return bool(definition.call("is_hostile_to", other_faction_id))
	var hostile_ids = definition.get("default_hostile_faction_ids")
	return hostile_ids != null and hostile_ids.has(other_faction_id)
