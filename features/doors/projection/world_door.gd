@tool
extends ModularBuildingPiece

class_name WorldDoor

const DOOR_SERVICE_ID := &"doors"
## Physics layer 4 (value 8) is reserved for runtime door blockers. Layers
## already taken: 1 = world, 2 = actors (ACTOR_COLLISION_LAYER), 3 = furniture.
const BLOCKER_COLLISION_LAYER := 8

@export_category("Door")
## Stable gameplay ID. Empty is valid for catalog previews, but not for a live door.
@export var door_id := ""
@export var building_id := ""
@export var door_definition: Resource
@export var authorized_actor_ids := PackedStringArray()
@export var authorized_faction_ids := PackedStringArray()
@export var authorized_key_ids := PackedStringArray()
@export var scheduled_actor_id := ""
@export_range(-1, 23, 1) var scheduled_open_hour := -1
@export_range(-1, 23, 1) var scheduled_close_hour := -1
## Business-hours doors that should stand open, not merely unlocked (bar and
## shop front doors); the keeper is sent when it drifts shut mid-business.
@export var keep_open_during_hours := false
## Per-placement override of the definition's exit policy (a shop-shell door
## reused as a jail cell needs "symmetric" without a new definition resource).
@export_enum("definition_default", "free_exit", "symmetric", "authorized_exit") var exit_policy_override := "definition_default"

var _door_controller: Node
var _door_interactions: Node
var _closed_blocker: StaticBody3D
var _hinge_pivot: Node3D
var _closed_hinge_rotation := Vector3.ZERO
var _is_open := false
var _motion_tween: Tween


func _ready() -> void:
	super._ready()
	if not Engine.is_editor_hint():
		add_to_group("world_door")
	_closed_blocker = get_node_or_null("ClosedBlocker") as StaticBody3D
	_hinge_pivot = get_node_or_null("HingePivot") as Node3D
	if _hinge_pivot != null:
		_closed_hinge_rotation = _hinge_pivot.rotation
	var auto_open_area := get_node_or_null("AutoOpenArea") as Area3D
	if auto_open_area != null and not auto_open_area.body_entered.is_connected(_on_auto_open_area_body_entered):
		auto_open_area.body_entered.connect(_on_auto_open_area_body_entered)
	if Engine.is_editor_hint():
		_apply_door_state({"is_open": _definition_bool("default_open", false)}, false)
		return
	if door_id.is_empty():
		# Catalog previews and unconfigured placements must not leave a permanent
		# nav blocker with no durable record capable of opening it.
		_set_closed_blocker_enabled(false)
		return
	call_deferred("_register_with_door_system")


func _exit_tree() -> void:
	if _door_controller != null and is_instance_valid(_door_controller):
		_door_controller.mark_door_unrealized(door_id)
		if _door_controller.door_state_changed.is_connected(_on_door_state_changed):
			_door_controller.door_state_changed.disconnect(_on_door_state_changed)
	if _door_interactions != null and is_instance_valid(_door_interactions) and _door_interactions.has_method("unregister_door_projection"):
		_door_interactions.call("unregister_door_projection", door_id, self)


## Bodies currently inside the auto-open volume of a closed, registered door.
## The bridge polls this because body_entered alone misses actors already in
## the volume when the door closes or when their move target changes.
func get_auto_open_candidates() -> Array:
	if _is_open or door_id.is_empty():
		return []
	var auto_open_area := get_node_or_null("AutoOpenArea") as Area3D
	return auto_open_area.get_overlapping_bodies() if auto_open_area != null else []


func get_interaction_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for marker_name in ["InteractionSideA", "InteractionSideB"]:
		var marker := get_node_or_null(marker_name) as Marker3D
		if marker != null:
			positions.append(marker.global_position)
	return positions


## Matches OwnershipController.STEAL_ACTION_COLOR — red marks actions on
## someone else's property: legal to attempt, incriminating if witnessed.
const PRIVATE_ACTION_COLOR := Color(0.92, 0.34, 0.30, 1.0)


func get_world_context_actions(actor: Node = null) -> Array:
	if _door_controller == null or door_id.is_empty():
		return []
	var state: Dictionary = _door_controller.get_door_state(door_id)
	if state.is_empty():
		return []
	var restricted := _actor_lacks_access(actor)
	if bool(state.get("is_locked", false)):
		var unlock_action := {"key": "unlock", "label": "Unlock"}
		var lockpick_action := {"key": "lockpick", "label": "Pick Lock"}
		if restricted:
			unlock_action["color"] = PRIVATE_ACTION_COLOR
			lockpick_action["color"] = PRIVATE_ACTION_COLOR
		return [unlock_action, lockpick_action]
	var door_open := bool(state.get("is_open", false))
	var open_action := {"key": "close" if door_open else "open", "label": "Close" if door_open else "Open"}
	if restricted and not door_open:
		open_action["color"] = PRIVATE_ACTION_COLOR
	var actions := [open_action]
	if not door_open:
		actions.append({"key": "lock", "label": "Lock"})
	return actions


## Red-label test: the door is someone's (any authorization list) and this
## actor is not on any of them — same rule the sim enforces on commands.
func _actor_lacks_access(actor: Node) -> bool:
	if actor == null or _door_interactions == null:
		return false
	if not _door_interactions.has_method("is_door_private") or not _door_interactions.has_method("is_actor_authorized"):
		return false
	return bool(_door_interactions.call("is_door_private", self)) and not bool(_door_interactions.call("is_actor_authorized", actor, self))


func perform_world_context_action(action_key: String, actors: Array = []) -> String:
	if _door_interactions == null or not _door_interactions.has_method("request_world_action"):
		return "Door controls unavailable."
	return str(_door_interactions.call("request_world_action", self, action_key, actors))


func apply_door_state(state: Dictionary, animate := true) -> void:
	_apply_door_state(state, animate)


## Reusable shells cannot author globally unique door IDs, so the owning
## WorldBuilding mints one per placement at ready time and hands it over here.
func assign_runtime_identity(new_door_id: String, new_building_id: String) -> void:
	if not door_id.is_empty() or new_door_id.is_empty() or Engine.is_editor_hint():
		return
	door_id = new_door_id
	building_id = new_building_id
	call_deferred("ensure_registered")


## Registration must survive init-order races: doors ready before the
## bootstrap's deferred controller pass, so the bridge sweeps the world_door
## group once services exist, and late-spawned doors register themselves.
func ensure_registered() -> void:
	if _door_controller == null and not door_id.is_empty() and not Engine.is_editor_hint():
		_register_with_door_system()


func _register_with_door_system() -> void:
	_door_controller = BootstrapContext.service(DOOR_SERVICE_ID)
	if _door_controller == null:
		return
	if not _door_controller.door_state_changed.is_connected(_on_door_state_changed):
		_door_controller.door_state_changed.connect(_on_door_state_changed)
	_door_interactions = BootstrapContext.service(&"door_interactions")
	if _door_interactions != null and _door_interactions.has_method("register_door_projection"):
		_door_interactions.call("register_door_projection", self)
	var state: Dictionary = _door_controller.register_door(_door_record())
	if not state.is_empty():
		_apply_door_state(state, false)


func _door_record() -> Dictionary:
	var sides := get_interaction_positions()
	return {
		"door_id": door_id,
		"building_id": building_id,
		"default_open": _definition_bool("default_open", false),
		"default_locked": _definition_bool("default_locked", false),
		"lock_tier_id": _definition_string("lock_tier_id", "easy"),
		"exit_policy": exit_policy_override if exit_policy_override != "definition_default" else _definition_string("exit_policy", "free_exit"),
		"close_behavior": _definition_string("close_behavior", "stay_open"),
		"auto_close_delay_seconds": _definition_float("auto_close_delay_seconds", 0.0),
		"interaction_radius": _definition_float("interaction_radius", 1.5),
		"interaction_side_a": sides[0] if sides.size() > 0 else global_position,
		"interaction_side_b": sides[1] if sides.size() > 1 else global_position,
		"authorized_actor_ids": authorized_actor_ids,
		"authorized_faction_ids": authorized_faction_ids,
		"authorized_key_ids": authorized_key_ids,
		"scheduled_actor_id": scheduled_actor_id,
		"scheduled_open_hour": scheduled_open_hour,
		"scheduled_close_hour": scheduled_close_hour,
		"kept_open": keep_open_during_hours,
	}


func _on_door_state_changed(changed_door_id: String, state: Dictionary) -> void:
	if changed_door_id == door_id:
		_apply_door_state(state, true)


func _on_auto_open_area_body_entered(body: Node3D) -> void:
	if Engine.is_editor_hint() or _door_interactions == null or not _door_interactions.has_method("request_npc_auto_open"):
		return
	_door_interactions.call("request_npc_auto_open", body, self)


func _apply_door_state(state: Dictionary, animate: bool) -> void:
	_is_open = bool(state.get("is_open", false))
	_set_closed_blocker_enabled(not _is_open)
	_apply_hinge_rotation(_is_open, animate)


func _set_closed_blocker_enabled(enabled: bool) -> void:
	if _closed_blocker == null:
		return
	_closed_blocker.collision_layer = BLOCKER_COLLISION_LAYER if enabled else 0
	_closed_blocker.collision_mask = 1 if enabled else 0
	for child in _closed_blocker.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = not enabled


func _apply_hinge_rotation(open: bool, animate: bool) -> void:
	if _hinge_pivot == null:
		return
	var target := _closed_hinge_rotation
	if open:
		target.y += deg_to_rad(_definition_float("open_angle_degrees", -90.0))
	if _motion_tween != null and _motion_tween.is_valid():
		_motion_tween.kill()
	if not animate or _definition_float("animation_duration_seconds", 0.35) <= 0.0:
		_hinge_pivot.rotation = target
		return
	_motion_tween = create_tween()
	_motion_tween.set_trans(Tween.TRANS_QUAD)
	_motion_tween.set_ease(Tween.EASE_OUT)
	_motion_tween.tween_property(_hinge_pivot, "rotation", target, _definition_float("animation_duration_seconds", 0.35))


func _definition_bool(property_name: String, fallback: bool) -> bool:
	return bool(door_definition.get(property_name)) if door_definition != null else fallback


func _definition_float(property_name: String, fallback: float) -> float:
	return float(door_definition.get(property_name)) if door_definition != null else fallback


func _definition_string(property_name: String, fallback: String) -> String:
	return str(door_definition.get(property_name)) if door_definition != null else fallback
