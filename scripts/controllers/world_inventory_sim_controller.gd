extends Node

class_name WorldInventorySimController

const MAX_COMMAND_LOG_ENTRIES := 40

var root_scene: Node
var _last_state: Dictionary = {"applied_count": 0, "failed_count": 0, "command_log": []}


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root


func _ready() -> void:
	add_to_group("world_inventory_sim_controller")


func apply_sim_commands(commands: Array[Dictionary]) -> void:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("apply_inventory_command"):
		return
	var command_log: Array = _last_state.get("command_log", []) if _last_state.get("command_log", []) is Array else []
	var applied_count := 0
	var failed_count := 0
	for command in commands:
		if command.is_empty():
			continue
		var result = bridge.call("apply_inventory_command", command)
		var result_dict: Dictionary = result if result is Dictionary else {"ok": false, "message": "Invalid result"}
		if bool(result_dict.get("ok", false)):
			applied_count += 1
		else:
			failed_count += 1
		command_log.append({
			"action": str(command.get("action", "")),
			"ok": bool(result_dict.get("ok", false)),
			"message": str(result_dict.get("message", "")),
		})
	while command_log.size() > MAX_COMMAND_LOG_ENTRIES:
		command_log.pop_front()
	_last_state = {"applied_count": applied_count, "failed_count": failed_count, "command_log": command_log}


func update_sim(_fixed_delta: float) -> void:
	pass


func get_sim_state() -> Dictionary:
	return _last_state.duplicate(true)


func _get_gecs_world() -> Node:
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("GecsWorldController")
		if local != null:
			return local
	return get_tree().get_first_node_in_group("gecs_world_controller") if is_inside_tree() else null
