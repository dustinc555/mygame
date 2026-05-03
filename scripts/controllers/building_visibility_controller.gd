extends Node

class_name BuildingVisibilityController

const WORLD_BUILDING_SCRIPT = preload("res://scripts/world/buildings/world_building.gd")

var root_scene: Node
var _party_manager: PartyManager
var _camera: Camera3D
var _initialized := false
var _active_building: Node


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	if is_inside_tree():
		_do_initialize()


func _ready() -> void:
	if root_scene != null:
		_do_initialize()


func _do_initialize() -> void:
	if _initialized or root_scene == null:
		return
	_party_manager = root_scene.get_node_or_null("PartyManager") as PartyManager
	_camera = root_scene.get_node_or_null("CameraRig/CameraPivot/Camera3D") as Camera3D
	_initialized = _party_manager != null and _camera != null


func _process(_delta: float) -> void:
	if not _initialized:
		return
	var meaningful_actor := _get_meaningful_actor()
	var next_building: Node = _find_building_for_actor(meaningful_actor)
	if _active_building == next_building:
		if _active_building != null and is_instance_valid(_active_building):
			_active_building.set_visibility_for_camera(next_building != null, _camera.global_position)
		return
	if _active_building != null and is_instance_valid(_active_building):
		_active_building.set_visibility_for_camera(false, _camera.global_position)
	_active_building = next_building
	if _active_building != null:
		_active_building.set_visibility_for_camera(true, _camera.global_position)


func _get_meaningful_actor() -> HumanoidCharacter:
	if _party_manager == null:
		return null
	if _party_manager.followed_member != null:
		return _party_manager.followed_member
	if _party_manager.selected_members.size() == 1:
		return _party_manager.selected_members[0]
	return null


func _find_building_for_actor(actor: HumanoidCharacter) -> Node:
	if actor == null:
		return null
	for node in get_tree().get_nodes_in_group("world_building"):
		if node != null and node.get_script() == WORLD_BUILDING_SCRIPT and node.is_actor_inside(actor):
			return node
	return null
