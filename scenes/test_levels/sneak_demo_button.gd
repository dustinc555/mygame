extends StaticBody3D

class_name SneakDemoButton

@export var action_key := ""
@export var action_label := "Toggle"
@export var target_path: NodePath

var _base_y := 0.0
var _pulse_time := 0.0


func _ready() -> void:
	add_to_group("world_context_action")
	_base_y = position.y


func _process(delta: float) -> void:
	_pulse_time += delta
	position.y = _base_y + sin(_pulse_time * 2.4) * 0.035


func get_world_context_actions(_actor = null) -> Array:
	if action_key.is_empty():
		return []
	return [{"key": action_key, "label": action_label}]


func perform_world_context_action(key: String, actors: Array = []) -> String:
	var target := get_node_or_null(target_path)
	if target == null:
		target = get_tree().current_scene
	if target != null and target.has_method("perform_sneak_demo_action"):
		return str(target.perform_sneak_demo_action(key, actors))
	return "Sneak demo is not available"
