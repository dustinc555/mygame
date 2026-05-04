@tool
extends StaticBody3D

class_name WorldBuilding

@export var display_name := "Building"
@export var levels: Array[BuildingLevelDefinition] = []
@export var interior_area_path: NodePath
@export var roof_occluder_paths: Array[NodePath] = []
@export var front_occluder_paths: Array[NodePath] = []
@export var right_occluder_paths: Array[NodePath] = []
@export var back_occluder_paths: Array[NodePath] = []
@export var left_occluder_paths: Array[NodePath] = []

var _interior_actor_ids: Dictionary = {}
var _roof_hidden := false
var _hidden_side := ""
var _level_actor_ids: Array[Dictionary] = []
var _active_level_index := -1
const SIDE_SWITCH_HYSTERESIS := 0.45


func _ready() -> void:
	add_to_group("world_building")
	_level_actor_ids.clear()
	for level_index in range(levels.size()):
		_level_actor_ids.append({})
		var occupancy_area := _get_level_area(level_index)
		if occupancy_area != null:
			if not occupancy_area.body_entered.is_connected(_on_level_body_entered.bind(level_index)):
				occupancy_area.body_entered.connect(_on_level_body_entered.bind(level_index))
			if not occupancy_area.body_exited.is_connected(_on_level_body_exited.bind(level_index)):
				occupancy_area.body_exited.connect(_on_level_body_exited.bind(level_index))
	var interior_area := _get_interior_area()
	if interior_area != null:
		if not interior_area.body_entered.is_connected(_on_interior_body_entered):
			interior_area.body_entered.connect(_on_interior_body_entered)
		if not interior_area.body_exited.is_connected(_on_interior_body_exited):
			interior_area.body_exited.connect(_on_interior_body_exited)
	if levels.is_empty():
		_apply_occluder_visibility(roof_occluder_paths, false)
		_apply_occluder_visibility(front_occluder_paths, false)
		_apply_occluder_visibility(right_occluder_paths, false)
		_apply_occluder_visibility(back_occluder_paths, false)
		_apply_occluder_visibility(left_occluder_paths, false)
	else:
		_refresh_level_visibility(false, Vector3.ZERO, null)


func is_actor_inside(actor: HumanoidCharacter) -> bool:
	if actor == null:
		return false
	if not levels.is_empty():
		return get_level_index_for_actor(actor) >= 0
	return _interior_actor_ids.has(actor.get_instance_id())


func set_visibility_for_camera(show_interior: bool, camera_world_position: Vector3, actor: HumanoidCharacter = null) -> void:
	if not levels.is_empty():
		_refresh_level_visibility(show_interior, camera_world_position, actor)
		return
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
		if node is Node3D:
			node.visible = not hidden


func is_hidden_occluder_shape(shape_index: int) -> bool:
	if shape_index < 0:
		return false
	var owner_id := shape_find_owner(shape_index)
	if owner_id < 0:
		return false
	var owner_node := shape_owner_get_owner(owner_id)
	if not (owner_node is CollisionShape3D):
		return false
	var node_path := get_path_to(owner_node)
	if not levels.is_empty():
		if _active_level_index < 0 or _active_level_index >= levels.size():
			return false
		var level: BuildingLevelDefinition = levels[_active_level_index]
		if level == null:
			return false
		return (
			(_hidden_side == "front" and level.front_occluder_paths.has(node_path))
			or (_hidden_side == "right" and level.right_occluder_paths.has(node_path))
			or (_hidden_side == "back" and level.back_occluder_paths.has(node_path))
			or (_hidden_side == "left" and level.left_occluder_paths.has(node_path))
		)
	return (
		(_roof_hidden and roof_occluder_paths.has(node_path))
		or (_hidden_side == "front" and front_occluder_paths.has(node_path))
		or (_hidden_side == "right" and right_occluder_paths.has(node_path))
		or (_hidden_side == "back" and back_occluder_paths.has(node_path))
		or (_hidden_side == "left" and left_occluder_paths.has(node_path))
	)


func should_project_click_shape(shape_index: int) -> bool:
	if shape_index < 0:
		return false
	if is_hidden_occluder_shape(shape_index):
		return true
	if _active_level_index < 0:
		return false
	var owner_id := shape_find_owner(shape_index)
	if owner_id < 0:
		return false
	var owner_node := shape_owner_get_owner(owner_id)
	if not (owner_node is CollisionShape3D):
		return false
	var node_path := get_path_to(owner_node)
	for level_index in range(levels.size()):
		if level_index == _active_level_index:
			continue
		var level: BuildingLevelDefinition = levels[level_index]
		if level == null:
			continue
		if level.content_paths.has(node_path):
			return true
		if level.front_occluder_paths.has(node_path) or level.right_occluder_paths.has(node_path) or level.back_occluder_paths.has(node_path) or level.left_occluder_paths.has(node_path):
			return true
	return false


func _get_interior_area() -> Area3D:
	return get_node_or_null(interior_area_path) as Area3D


func get_level_index_for_actor(actor: HumanoidCharacter) -> int:
	if actor == null:
		return -1
	var actor_id := actor.get_instance_id()
	var local_y := to_local(actor.global_position).y
	for level_index in range(_level_actor_ids.size() - 1, -1, -1):
		if not _level_actor_ids[level_index].has(actor_id):
			continue
		var level: BuildingLevelDefinition = levels[level_index]
		if level == null:
			continue
		if local_y >= level.min_local_y and local_y < level.max_local_y:
			return level_index
	for level_index in range(_level_actor_ids.size() - 1, -1, -1):
		if _level_actor_ids[level_index].has(actor_id):
			return level_index
	return -1


func is_roof_level(level_index: int) -> bool:
	if level_index < 0 or level_index >= levels.size():
		return false
	var level: BuildingLevelDefinition = levels[level_index]
	return level != null and level.is_roof


func _get_camera_facing_side(camera_world_position: Vector3) -> String:
	var local_camera_position := to_local(camera_world_position)
	var abs_x := absf(local_camera_position.x)
	var abs_z := absf(local_camera_position.z)
	if _hidden_side == "right" or _hidden_side == "left":
		if abs_z + SIDE_SWITCH_HYSTERESIS < abs_x:
			return "right" if local_camera_position.x > 0.0 else "left"
	elif _hidden_side == "front" or _hidden_side == "back":
		if abs_x + SIDE_SWITCH_HYSTERESIS < abs_z:
			return "front" if local_camera_position.z > 0.0 else "back"
	if abs_x > abs_z:
		return "right" if local_camera_position.x > 0.0 else "left"
	return "front" if local_camera_position.z > 0.0 else "back"


func _refresh_level_visibility(show_interior: bool, camera_world_position: Vector3, actor: HumanoidCharacter) -> void:
	var next_level_index := -1
	var next_hidden_side := ""
	if show_interior:
		next_level_index = get_level_index_for_actor(actor)
		if next_level_index >= 0 and not is_roof_level(next_level_index):
			next_hidden_side = _get_camera_facing_side(camera_world_position)
	if _active_level_index == next_level_index and _hidden_side == next_hidden_side:
		return
	_active_level_index = next_level_index
	_hidden_side = next_hidden_side
	if _active_level_index < 0:
		for level_index in range(levels.size()):
			_apply_level_visibility(level_index, true, false)
		return
	for level_index in range(levels.size()):
		_apply_level_visibility(level_index, level_index <= _active_level_index, level_index == _active_level_index)


func _apply_level_visibility(level_index: int, visible: bool, active: bool = true) -> void:
	if level_index < 0 or level_index >= levels.size():
		return
	var level: BuildingLevelDefinition = levels[level_index]
	if level == null:
		return
	for node_path in level.content_paths:
		_apply_node_visibility(get_node_or_null(node_path), visible)
	_apply_occluder_visibility(level.front_occluder_paths, not visible or (active and _hidden_side == "front"))
	_apply_occluder_visibility(level.right_occluder_paths, not visible or (active and _hidden_side == "right"))
	_apply_occluder_visibility(level.back_occluder_paths, not visible or (active and _hidden_side == "back"))
	_apply_occluder_visibility(level.left_occluder_paths, not visible or (active and _hidden_side == "left"))


func _apply_node_visibility(node: Node, visible: bool) -> void:
	if node == null:
		return
	if node is Node3D:
		node.visible = visible
	for child in node.get_children():
		_apply_node_visibility(child, visible)


func _get_level_area(level_index: int) -> Area3D:
	if level_index < 0 or level_index >= levels.size():
		return null
	var level: BuildingLevelDefinition = levels[level_index]
	if level == null:
		return null
	return get_node_or_null(level.occupancy_area_path) as Area3D


func project_click_to_active_level(ray_origin: Vector3, ray_direction: Vector3) -> Variant:
	if _active_level_index < 0 or _active_level_index >= levels.size():
		return null
	var level: BuildingLevelDefinition = levels[_active_level_index]
	if level == null:
		return null
	var plane_point := to_global(Vector3(0.0, level.click_local_y, 0.0))
	var plane := Plane(global_transform.basis.y.normalized(), plane_point)
	var hit: Variant = plane.intersects_ray(ray_origin, ray_direction)
	return hit


func _on_interior_body_entered(body: Node) -> void:
	if body is HumanoidCharacter:
		_interior_actor_ids[body.get_instance_id()] = true


func _on_interior_body_exited(body: Node) -> void:
	if body is HumanoidCharacter:
		_interior_actor_ids.erase(body.get_instance_id())


func _on_level_body_entered(body: Node, level_index: int) -> void:
	if body is HumanoidCharacter and level_index >= 0 and level_index < _level_actor_ids.size():
		_level_actor_ids[level_index][body.get_instance_id()] = true


func _on_level_body_exited(body: Node, level_index: int) -> void:
	if body is HumanoidCharacter and level_index >= 0 and level_index < _level_actor_ids.size():
		_level_actor_ids[level_index].erase(body.get_instance_id())
