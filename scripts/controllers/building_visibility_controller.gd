extends Node

class_name BuildingVisibilityController

const WORLD_BUILDING_SCRIPT = preload("res://scripts/world/buildings/world_building.gd")

var root_scene: Node
var _party_manager: PartyManager
var _camera: Camera3D
var _initialized := false
var _active_building: Node
var _visibility_actor: HumanoidCharacter


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
			_active_building.set_visibility_for_camera(true, _camera.global_position, meaningful_actor)
		return
	if _active_building != null and is_instance_valid(_active_building):
		_active_building.set_visibility_for_camera(false, _camera.global_position, null)
	_active_building = next_building
	if _active_building != null:
		_active_building.set_visibility_for_camera(true, _camera.global_position, meaningful_actor)


func _get_meaningful_actor() -> HumanoidCharacter:
	if _party_manager == null:
		return null
	if _is_valid_actor(_party_manager.followed_member):
		_visibility_actor = _party_manager.followed_member
		return _visibility_actor
	if _party_manager.selected_members.size() == 1:
		_visibility_actor = _party_manager.selected_members[0]
		return _visibility_actor
	if _party_manager.selected_members.size() > 1:
		if _is_valid_actor(_visibility_actor) and _party_manager.selected_members.has(_visibility_actor):
			return _visibility_actor
		var shared_level_actor := _get_shared_selected_building_level_actor()
		if shared_level_actor != null:
			_visibility_actor = shared_level_actor
			return _visibility_actor
		return null
	if _is_valid_actor(_visibility_actor) and _find_building_for_actor(_visibility_actor) != null:
		return _visibility_actor
	return null


func _is_valid_actor(actor: HumanoidCharacter) -> bool:
	return actor != null and is_instance_valid(actor)


func _get_shared_selected_building_level_actor() -> HumanoidCharacter:
	var selected_members := _party_manager.selected_members
	var shared_actor: HumanoidCharacter
	var shared_building: Node
	var shared_level_index := -1
	for member in selected_members:
		if not _is_valid_actor(member):
			return null
		var member_building := _find_building_for_actor(member)
		if member_building == null:
			return null
		var member_level_index := -1
		if member_building.has_method("get_level_index_for_actor"):
			member_level_index = int(member_building.call("get_level_index_for_actor", member))
		if shared_building == null:
			shared_actor = member
			shared_building = member_building
			shared_level_index = member_level_index
			continue
		if member_building != shared_building or member_level_index != shared_level_index:
			return null
	return shared_actor


func _find_building_for_actor(actor: HumanoidCharacter) -> Node:
	if actor == null:
		return null
	for node in get_tree().get_nodes_in_group("world_building"):
		if node != null and node.get_script() == WORLD_BUILDING_SCRIPT and node.is_actor_inside(actor):
			return node
	return null


func get_active_building() -> Node:
	return _active_building
