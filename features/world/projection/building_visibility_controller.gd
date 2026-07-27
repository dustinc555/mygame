extends Node

class_name BuildingVisibilityController

const SERVICE_ID := &"building_visibility"
const BUILDING_OCCUPANCY_CONTROLLER := preload("res://features/world/bridge/building_occupancy_controller.gd")

var root_scene: Node
var _party_manager: PartyManager
var _camera: Camera3D
var _occupancy: Node
var _projection_bridge: BuildingProjectionBridge
var _initialized := false
var _active_building: Node
var _visibility_actor: WorldActor
var _latched_focus_actor: WorldActor
var _focus_active := false
var _last_followed_id := 0


func initialize(context: BootstrapContext) -> void:
	root_scene = context.root_scene
	_occupancy = context.require(BUILDING_OCCUPANCY_CONTROLLER.SERVICE_ID)
	_projection_bridge = context.require(BuildingProjectionBridge.SERVICE_ID) as BuildingProjectionBridge
	if is_inside_tree():
		_do_initialize()


func _ready() -> void:
	add_to_group("building_visibility_controller")
	if root_scene != null:
		_do_initialize()


func _do_initialize() -> void:
	if _initialized or root_scene == null:
		return
	_party_manager = root_scene.get_node_or_null("PartyManager") as PartyManager
	_camera = root_scene.get_node_or_null("CameraRig/CameraPivot/Camera3D") as Camera3D
	_initialized = _party_manager != null and _camera != null and _occupancy != null and _projection_bridge != null


func _process(_delta: float) -> void:
	if not _initialized:
		return
	var meaningful_actor := _get_meaningful_actor()
	# Modular see-through only opens when the camera actually follows the
	# actor (double-click); selection alone keeps buildings solid. Once open it
	# is lazy: while the camera follows nobody (WASD pan, unfocus, or plain
	# single-click selection of anyone else), the last focused character keeps
	# the cut. Only a new double-click focus hands it to someone else.
	var followed := _party_manager.followed_member
	var camera_focused := meaningful_actor != null and meaningful_actor == followed
	if camera_focused:
		_latched_focus_actor = meaningful_actor
	elif followed == null and _is_valid_actor(_latched_focus_actor):
		meaningful_actor = _latched_focus_actor
		camera_focused = true
	else:
		_latched_focus_actor = null
	var visibility_actor := _get_visibility_proxy_actor(meaningful_actor)
	var next_building: Node = _get_building_for_actor(visibility_actor)
	_focus_active = camera_focused and next_building != null
	# Refocusing any character hands the floor cut back to them.
	var followed_id := followed.get_instance_id() if _is_valid_actor(followed) else 0
	if followed_id != 0 and followed_id != _last_followed_id:
		_clear_level_override(_active_building)
	_last_followed_id = followed_id
	if _active_building == next_building:
		if _active_building != null and is_instance_valid(_active_building):
			_active_building.set_visibility_for_camera(true, _camera.global_position, visibility_actor, camera_focused)
		return
	if _active_building != null and is_instance_valid(_active_building):
		_clear_level_override(_active_building)
		_active_building.set_visibility_for_camera(false, _camera.global_position, null)
	_active_building = next_building
	if _active_building != null:
		_active_building.set_visibility_for_camera(true, _camera.global_position, visibility_actor, camera_focused)


func _get_meaningful_actor() -> WorldActor:
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
	if _is_valid_actor(_visibility_actor) and _get_building_for_actor(_get_visibility_proxy_actor(_visibility_actor)) != null:
		return _visibility_actor
	return null


func _is_valid_actor(actor: WorldActor) -> bool:
	return actor != null and is_instance_valid(actor)


func _get_visibility_proxy_actor(actor: WorldActor) -> WorldActor:
	if not _is_valid_actor(actor):
		return null
	if actor.has_method("get_carrier"):
		var carrier := actor.call("get_carrier") as WorldActor
		if _is_valid_actor(carrier):
			return carrier
	return actor


func _get_shared_selected_building_level_actor() -> WorldActor:
	var selected_members := _party_manager.selected_members
	var shared_actor: WorldActor
	var shared_building: Node = null
	var shared_level_index := -1
	for member in selected_members:
		if not _is_valid_actor(member):
			return null
		var proxy_actor := _get_visibility_proxy_actor(member)
		var member_building := _get_building_for_actor(proxy_actor)
		if member_building == null:
			return null
		var member_level_index := -1
		if member_building.has_method("get_level_index_for_actor"):
			member_level_index = int(member_building.call("get_level_index_for_actor", proxy_actor))
		if shared_building == null:
			shared_actor = member
			shared_building = member_building
			shared_level_index = member_level_index
			continue
		if member_building != shared_building or member_level_index != shared_level_index:
			return null
	return shared_actor


func _get_building_for_actor(actor: WorldActor) -> WorldBuilding:
	if actor == null:
		return null
	var actor_id := actor.stable_id.strip_edges()
	if actor_id.is_empty() and actor.has_meta("actor_record_id"):
		actor_id = str(actor.get_meta("actor_record_id")).strip_edges()
	if actor_id.is_empty():
		return null
	var building_id: String = _occupancy.get_building_id_for_actor(actor_id)
	return _projection_bridge.get_projection(building_id) if not building_id.is_empty() else null


func get_active_building() -> Node:
	return _active_building


## HUD-facing: the level the camera cut is showing. 0 = outside,
## 1+ = building level (ground floor = 1). A manual override wins.
func get_focus_display_level() -> int:
	if not _focus_active or _active_building == null or not is_instance_valid(_active_building):
		return 0
	if _active_building.has_method("get_display_level_override"):
		var override_level := int(_active_building.call("get_display_level_override"))
		if override_level > 0:
			return override_level
	var actor := _get_visibility_proxy_actor(_visibility_actor)
	if actor == null or not _active_building.has_method("get_display_level_for_actor"):
		return 0
	return int(_active_building.call("get_display_level_for_actor", actor))


## World height of the floor plate the cut is showing (override or the focused
## actor's level). NAN when no cut is open.
func get_focus_level_world_y() -> float:
	var level := get_focus_display_level()
	if level <= 0 or _active_building == null or not is_instance_valid(_active_building):
		return NAN
	if not _active_building.has_method("get_display_level_world_y"):
		return NAN
	return float(_active_building.call("get_display_level_world_y", level))


## World height of a manually stepped floor; NAN unless an override is active.
func get_focus_level_override_world_y() -> float:
	if not _focus_active or _active_building == null or not is_instance_valid(_active_building):
		return NAN
	if not _active_building.has_method("get_display_level_override") or not _active_building.has_method("get_display_level_world_y"):
		return NAN
	var override_level := int(_active_building.call("get_display_level_override"))
	if override_level <= 0:
		return NAN
	return float(_active_building.call("get_display_level_world_y", override_level))


## Step the camera cut one floor up/down in the focused building (HUD stepper).
## Detaches the cut from the focused actor until the next refocus.
func step_focus_level(delta: int) -> void:
	if not _focus_active or _active_building == null or not is_instance_valid(_active_building):
		return
	if not _active_building.has_method("get_display_level_count"):
		return
	var count := int(_active_building.call("get_display_level_count"))
	if count <= 1:
		return
	var current := int(_active_building.call("get_display_level_override"))
	if current <= 0:
		current = maxi(get_focus_display_level(), 1)
	_active_building.call("set_display_level_override", clampi(current + delta, 1, count))


func _clear_level_override(building: Node) -> void:
	if building != null and is_instance_valid(building) and building.has_method("set_display_level_override"):
		building.call("set_display_level_override", 0)
