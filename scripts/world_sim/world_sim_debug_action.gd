extends StaticBody3D

class_name WorldSimDebugAction

@export var display_name := "World Sim Action"
@export var action_key := ""
@export var action_label := "Run Action"
@export var boing_enabled := true
@export var boing_duration := 0.32
@export var squash_scale := Vector3(1.28, 0.62, 1.28)
@export var stretch_scale := Vector3(0.86, 1.24, 0.86)

var _boing_target: Node3D
var _boing_base_scale := Vector3.ONE
var _boing_tween: Tween


func _ready() -> void:
	add_to_group("world_context_action")
	_cache_boing_target()


func get_world_context_actions(_actor = null) -> Array:
	if action_key.is_empty():
		return []
	return [{"key": action_key, "label": action_label}]


func perform_world_context_action(key: String, _actors: Array = []) -> String:
	_play_boing()
	var controller := get_tree().get_first_node_in_group("world_simulation_controller")
	if controller == null or not controller.has_method("perform_world_sim_debug_action"):
		return "World simulation is not available"
	return str(controller.perform_world_sim_debug_action(key))


func _cache_boing_target() -> void:
	_boing_target = get_node_or_null("MeshInstance3D") as Node3D
	if _boing_target == null:
		_boing_target = find_child("*", false, false) as Node3D
	if _boing_target == null:
		_boing_target = self
	_boing_base_scale = _boing_target.scale


func _play_boing() -> void:
	if not boing_enabled:
		return
	if _boing_target == null or not is_instance_valid(_boing_target):
		_cache_boing_target()
	if _boing_target == null:
		return
	if _boing_tween != null and _boing_tween.is_valid():
		_boing_tween.kill()
	_boing_target.scale = _boing_base_scale
	_boing_tween = create_tween()
	_boing_tween.tween_property(_boing_target, "scale", _scaled_boing(squash_scale), boing_duration * 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_boing_tween.tween_property(_boing_target, "scale", _scaled_boing(stretch_scale), boing_duration * 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_boing_tween.tween_property(_boing_target, "scale", _boing_base_scale, boing_duration * 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _scaled_boing(multiplier: Vector3) -> Vector3:
	return Vector3(
		_boing_base_scale.x * multiplier.x,
		_boing_base_scale.y * multiplier.y,
		_boing_base_scale.z * multiplier.z
	)
