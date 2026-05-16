extends Node

class_name WorldSimulationController

var root_scene: Node
var world_time: Node
var settlement_controller: Node
var territory_controller: Node
var world_squad_controller: Node
var _initialized := false


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	_try_initialize()


func _ready() -> void:
	add_to_group("world_simulation_controller")
	_try_initialize()


func get_summary_text() -> String:
	if settlement_controller == null:
		return "World: Stable"
	return settlement_controller.get_summary_text()


func perform_world_sim_debug_action(action_key: String) -> String:
	if action_key.is_empty():
		return "No action configured"
	var parts := action_key.split(":")
	match parts[0]:
		"advance_hours":
			var hours := float(parts[1]) if parts.size() > 1 else 1.0
			if world_time != null and world_time.has_method("advance_hours"):
				world_time.call("advance_hours", hours)
			return "Advanced %.0f hour(s)" % hours
		"advance_days":
			var days := float(parts[1]) if parts.size() > 1 else 1.0
			if world_time != null and world_time.has_method("advance_days"):
				world_time.call("advance_days", days)
			return "Advanced %.0f day(s)" % days
		"adjust_food":
			if parts.size() < 3 or settlement_controller == null:
				return "Food action is misconfigured"
			var settlement_id := parts[1]
			var amount := float(parts[2])
			var food: float = float(settlement_controller.call("adjust_food", settlement_id, amount, "debug_action"))
			return "%s food is now %.0f" % [settlement_id, food]
		"set_food":
			if parts.size() < 3 or settlement_controller == null:
				return "Food action is misconfigured"
			var settlement_id := parts[1]
			var amount := float(parts[2])
			var food: float = float(settlement_controller.call("set_food", settlement_id, amount, "debug_action"))
			return "%s food is now %.0f" % [settlement_id, food]
		"set_occupancy":
			if parts.size() < 3 or settlement_controller == null or not settlement_controller.has_method("set_occupancy_state"):
				return "Occupancy action is misconfigured"
			var settlement_id := parts[1]
			var state: Dictionary = settlement_controller.call("set_occupancy_state", settlement_id, parts[2], "debug_action")
			if state.is_empty():
				return "Occupancy could not be changed"
			return "%s is %s (%d/%d)" % [settlement_id, state.get("occupancy_label", "Populated"), int(state.get("population", 0)), int(state.get("max_occupancy", 0))]
		"force_raid":
			if parts.size() < 3 or settlement_controller == null:
				return "Raid action is misconfigured"
			var started: bool = bool(settlement_controller.call("force_food_raid", parts[1], parts[2]))
			return "Raid started" if started else "Raid could not start"
		"toggle_faction_territories":
			if territory_controller != null and territory_controller.has_method("toggle_faction_territories_visible"):
				return str(territory_controller.call("toggle_faction_territories_visible"))
			return "Territory controller is not available"
		"toggle_town_borders":
			if territory_controller != null and territory_controller.has_method("toggle_town_borders_visible"):
				return str(territory_controller.call("toggle_town_borders_visible"))
			return "Territory controller is not available"
		_:
			return "Unknown world sim action"


func serialize_state() -> Dictionary:
	return {
		"settlements": settlement_controller.call("serialize_state") if settlement_controller != null and settlement_controller.has_method("serialize_state") else {},
		"squads": world_squad_controller.call("serialize_state") if world_squad_controller != null and world_squad_controller.has_method("serialize_state") else {},
		"territories": territory_controller.call("serialize_state") if territory_controller != null and territory_controller.has_method("serialize_state") else {},
	}


func _try_initialize() -> void:
	if _initialized or root_scene == null or not is_inside_tree():
		return
	world_time = get_parent().get_node_or_null("WorldTimeController")
	settlement_controller = get_parent().get_node_or_null("SettlementController")
	territory_controller = get_parent().get_node_or_null("TerritoryController")
	world_squad_controller = get_parent().get_node_or_null("WorldSquadController")
	if world_time == null or settlement_controller == null or world_squad_controller == null:
		return
	var action_requested_callable := Callable(self, "_on_settlement_action_requested")
	if settlement_controller.has_signal("settlement_action_requested") and not settlement_controller.is_connected("settlement_action_requested", action_requested_callable):
		settlement_controller.connect("settlement_action_requested", action_requested_callable)
	_initialized = true


func _on_settlement_action_requested(action_record: Dictionary) -> void:
	if world_squad_controller != null and world_squad_controller.has_method("start_action"):
		world_squad_controller.call("start_action", action_record)
