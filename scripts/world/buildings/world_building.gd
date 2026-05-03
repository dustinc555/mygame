@tool
extends StaticBody3D

class_name WorldBuilding

@export var display_name := "Building"
@export var interior_area_path: NodePath
@export var roof_occluder_paths: Array[NodePath] = []
@export var front_occluder_paths: Array[NodePath] = []
@export var right_occluder_paths: Array[NodePath] = []
@export var back_occluder_paths: Array[NodePath] = []
@export var left_occluder_paths: Array[NodePath] = []

var _interior_actor_ids: Dictionary = {}
var _roof_hidden := false
var _hidden_side := ""


func _ready() -> void:
	add_to_group("world_building")
	var interior_area := _get_interior_area()
	if interior_area != null:
		if not interior_area.body_entered.is_connected(_on_interior_body_entered):
			interior_area.body_entered.connect(_on_interior_body_entered)
		if not interior_area.body_exited.is_connected(_on_interior_body_exited):
			interior_area.body_exited.connect(_on_interior_body_exited)
	_apply_occluder_visibility(roof_occluder_paths, false)
	_apply_occluder_visibility(front_occluder_paths, false)
	_apply_occluder_visibility(right_occluder_paths, false)
	_apply_occluder_visibility(back_occluder_paths, false)
	_apply_occluder_visibility(left_occluder_paths, false)


func is_actor_inside(actor: HumanoidCharacter) -> bool:
	if actor == null:
		return false
	return _interior_actor_ids.has(actor.get_instance_id())


func set_visibility_for_camera(show_interior: bool, camera_world_position: Vector3) -> void:
	var next_roof_hidden := show_interior
	var next_hidden_side := ""
	if show_interior:
		next_hidden_side = _get_camera_facing_side(camera_world_position)
	if _roof_hidden == next_roof_hidden and _hidden_side == next_hidden_side:
		return
	_roof_hidden = next_roof_hidden
	_hidden_side = next_hidden_side
	_refresh_occluders()


func _refresh_occluders() -> void:
	_apply_occluder_visibility(roof_occluder_paths, _roof_hidden)
	_apply_occluder_visibility(front_occluder_paths, _hidden_side == "front")
	_apply_occluder_visibility(right_occluder_paths, _hidden_side == "right")
	_apply_occluder_visibility(back_occluder_paths, _hidden_side == "back")
	_apply_occluder_visibility(left_occluder_paths, _hidden_side == "left")


func _apply_occluder_visibility(paths: Array[NodePath], hidden: bool) -> void:
	for node_path in paths:
		var node := get_node_or_null(node_path)
		if node is CollisionShape3D:
			node.disabled = hidden
		elif node is Node3D:
			node.visible = not hidden


func _get_interior_area() -> Area3D:
	return get_node_or_null(interior_area_path) as Area3D


func _get_camera_facing_side(camera_world_position: Vector3) -> String:
	var local_camera_position := to_local(camera_world_position)
	if absf(local_camera_position.x) > absf(local_camera_position.z):
		return "right" if local_camera_position.x > 0.0 else "left"
	return "front" if local_camera_position.z > 0.0 else "back"


func _on_interior_body_entered(body: Node) -> void:
	if body is HumanoidCharacter:
		_interior_actor_ids[body.get_instance_id()] = true


func _on_interior_body_exited(body: Node) -> void:
	if body is HumanoidCharacter:
		_interior_actor_ids.erase(body.get_instance_id())
