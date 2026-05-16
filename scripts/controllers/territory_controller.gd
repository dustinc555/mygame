extends Node

class_name TerritoryController

var root_scene: Node
var faction_territories: Dictionary = {}
var town_borders: Dictionary = {}
var faction_territories_visible := false
var town_borders_visible := false
var _initialized := false


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	_try_initialize()


func _ready() -> void:
	add_to_group("territory_controller")
	_try_initialize()


func refresh() -> void:
	faction_territories.clear()
	town_borders.clear()
	_collect_territories()
	_apply_debug_visibility()


func toggle_faction_territories_visible() -> String:
	set_faction_territories_visible(not faction_territories_visible)
	return "Faction territories visible" if faction_territories_visible else "Faction territories hidden"


func toggle_town_borders_visible() -> String:
	set_town_borders_visible(not town_borders_visible)
	return "Town borders visible" if town_borders_visible else "Town borders hidden"


func set_faction_territories_visible(value: bool) -> void:
	faction_territories_visible = value
	for node in get_tree().get_nodes_in_group("faction_territory"):
		if node.has_method("set_debug_visible"):
			node.call("set_debug_visible", value)


func set_town_borders_visible(value: bool) -> void:
	town_borders_visible = value
	for node in get_tree().get_nodes_in_group("settlement_town"):
		if node.has_method("set_town_border_debug_visible"):
			node.call("set_town_border_debug_visible", value)


func get_build_permission(world_position: Vector3, builder_faction_id := "") -> Dictionary:
	for node in get_tree().get_nodes_in_group("settlement_town"):
		if node.has_method("contains_town_border_position") and bool(node.call("contains_town_border_position", world_position)):
			return {
				"can_build": false,
				"reason": "too_close_to_town",
				"settlement_id": str(node.call("get_settlement_id")) if node.has_method("get_settlement_id") else node.name,
			}
	for node in get_tree().get_nodes_in_group("faction_territory"):
		if not node.has_method("contains_world_position") or not bool(node.call("contains_world_position", world_position)):
			continue
		var faction_id := str(node.get("faction_id"))
		if not faction_id.is_empty() and faction_id != builder_faction_id:
			return {
				"can_build": true,
				"reason": "foreign_faction_territory",
				"faction_id": faction_id,
				"territory_id": str(node.call("get_territory_id")) if node.has_method("get_territory_id") else node.name,
			}
	return {"can_build": true, "reason": "unclaimed"}


func serialize_state() -> Dictionary:
	return {
		"faction_territories": faction_territories.duplicate(true),
		"town_borders": town_borders.duplicate(true),
		"faction_territories_visible": faction_territories_visible,
		"town_borders_visible": town_borders_visible,
	}


func _try_initialize() -> void:
	if _initialized or root_scene == null or not is_inside_tree():
		return
	_collect_territories()
	_apply_debug_visibility()
	_initialized = true


func _collect_territories() -> void:
	for node in get_tree().get_nodes_in_group("faction_territory"):
		if node.has_method("get_territory_record"):
			var record: Dictionary = node.call("get_territory_record")
			var territory_id := str(record.get("territory_id", node.name))
			faction_territories[territory_id] = record
	for node in get_tree().get_nodes_in_group("settlement_town"):
		if node.has_method("get_town_border_record"):
			var record: Dictionary = node.call("get_town_border_record")
			var settlement_id := str(record.get("settlement_id", node.name))
			town_borders[settlement_id] = record


func _apply_debug_visibility() -> void:
	set_faction_territories_visible(faction_territories_visible)
	set_town_borders_visible(town_borders_visible)
