extends StaticBody3D

class_name BodyFurnace

const ACTION_PLACE_IN := "place_in"

@export var display_name := "Body Furnace"
@export var interaction_local_offset := Vector3(0.0, 0.0, 2.1)
@export var body_local_offset := Vector3(0.0, 0.85, 0.0)
@export var body_yaw_offset_degrees := 180.0
@export var burn_seconds := 2.0

var _reserved_by: HumanoidCharacter
var _reserved_body: HumanoidCharacter
var _burning_body: HumanoidCharacter
var _burn_remaining := 0.0
var _burn_effect: Node3D
var _burn_light: Light3D


func _ready() -> void:
	add_to_group("body_furnace")
	add_to_group("world_context_action")
	_burn_effect = get_node_or_null("BurnEffect") as Node3D
	_burn_light = get_node_or_null("BurnEffect/BurnLight") as Light3D
	_set_burn_effect_active(false)


func _process(delta: float) -> void:
	if _burn_remaining <= 0.0:
		return
	_burn_remaining = maxf(0.0, _burn_remaining - delta)
	_update_burn_effect()
	if _burn_remaining <= 0.0:
		_finish_burning_body()


func get_interaction_position(_actor = null) -> Vector3:
	var marker := get_node_or_null("InteractionMarker") as Node3D
	if marker != null:
		return marker.global_position
	return global_transform * interaction_local_offset


func get_body_position() -> Vector3:
	var marker := get_node_or_null("BodyMarker") as Node3D
	if marker != null:
		return marker.global_position
	return global_transform * body_local_offset


func get_body_rotation() -> Vector3:
	return Vector3(0.0, global_rotation.y + deg_to_rad(body_yaw_offset_degrees), 0.0)


func get_world_context_actions(actor = null) -> Array:
	if _can_actor_place_body(actor as HumanoidCharacter):
		return [{"key": ACTION_PLACE_IN, "label": "Place in"}]
	return []


func perform_world_context_action(action_key: String, actors: Array = []) -> String:
	if action_key != ACTION_PLACE_IN:
		return ""
	var carrier := _find_valid_carrier(actors)
	if carrier == null:
		return "Carry a valid body"
	carrier.assign_place_carried_in_furnace_target(self, true)
	return ""


func can_accept_body(body: HumanoidCharacter) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	if body.has_method("is_fire_destruction_in_progress") and bool(body.call("is_fire_destruction_in_progress")):
		return false
	if body.has_method("requires_fire_to_die") and bool(body.call("requires_fire_to_die")):
		return body.is_downed_state() or body.life_state == NpcRules.LifeState.DEAD
	return body.life_state == NpcRules.LifeState.DEAD


func is_available_for(actor: HumanoidCharacter = null, body: HumanoidCharacter = null) -> bool:
	_cleanup_invalid_reservation()
	if _burning_body != null and is_instance_valid(_burning_body):
		return false
	if _reserved_by != null and is_instance_valid(_reserved_by) and _reserved_by != actor:
		return false
	if body != null and _reserved_body != null and is_instance_valid(_reserved_body) and _reserved_body != body:
		return false
	if body != null and not can_accept_body(body):
		return false
	return true


func reserve_for(actor: HumanoidCharacter, body: HumanoidCharacter) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	if not is_available_for(actor, body):
		return false
	_reserved_by = actor
	_reserved_body = body
	return true


func release_reservation(actor: HumanoidCharacter = null, body: HumanoidCharacter = null) -> void:
	if actor != null and _reserved_by != actor:
		return
	if body != null and _reserved_body != body:
		return
	_reserved_by = null
	_reserved_body = null


func is_reserved_by(actor: HumanoidCharacter) -> bool:
	_cleanup_invalid_reservation()
	return actor != null and _reserved_by == actor


func place_carried_body(carrier: HumanoidCharacter, body: HumanoidCharacter) -> bool:
	if carrier == null or body == null or not is_instance_valid(body):
		return false
	if not is_available_for(carrier, body):
		return false
	release_reservation(carrier, body)
	_burning_body = body
	_burn_remaining = maxf(0.05, burn_seconds)
	body.global_position = get_body_position()
	body.rotation = get_body_rotation()
	body.velocity = Vector3.ZERO
	body.collision_layer = 0
	body.collision_mask = 0
	if body.has_method("_clear_all_active_orders"):
		body.call("_clear_all_active_orders")
	_set_burn_effect_active(true)
	return true


func _can_actor_place_body(actor: HumanoidCharacter) -> bool:
	if actor == null or not is_instance_valid(actor) or not actor.is_carrying_someone():
		return false
	var body := actor.get_carried_character()
	return is_available_for(actor, body)


func _find_valid_carrier(actors: Array) -> HumanoidCharacter:
	for actor_value in actors:
		var actor := actor_value as HumanoidCharacter
		if _can_actor_place_body(actor):
			return actor
	return null


func _cleanup_invalid_reservation() -> void:
	if _reserved_by != null and not is_instance_valid(_reserved_by):
		release_reservation()
		return
	if _reserved_body != null and not is_instance_valid(_reserved_body):
		release_reservation()


func _set_burn_effect_active(active: bool) -> void:
	if _burn_effect != null:
		_burn_effect.visible = active
	if _burn_light != null:
		_burn_light.visible = active
		_burn_light.light_energy = 1.8 if active else 0.0


func _update_burn_effect() -> void:
	if _burn_effect == null:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var pulse := 1.0 + sin(t * 18.0) * 0.12
	_burn_effect.scale = Vector3(pulse, 1.0 + sin(t * 13.0) * 0.18, pulse)
	if _burn_light != null:
		_burn_light.light_energy = 1.7 + sin(t * 16.0) * 0.35


func _finish_burning_body() -> void:
	var body := _burning_body
	_burning_body = null
	_set_burn_effect_active(false)
	if body == null or not is_instance_valid(body):
		return
	_remove_population_record_for_body(body)
	_remove_from_party_managers(body)
	body.queue_free()


func _remove_population_record_for_body(body: HumanoidCharacter) -> void:
	var actor_id := str(body.get_meta("actor_record_id", "")).strip_edges()
	if actor_id.is_empty():
		actor_id = str(body.get("stable_id")).strip_edges()
	if actor_id.is_empty() or not is_inside_tree():
		return
	for controller in get_tree().get_nodes_in_group("population_controller"):
		if controller != null and controller.has_method("remove_actor_record"):
			controller.call("remove_actor_record", actor_id, false)
			return


func _remove_from_party_managers(body: HumanoidCharacter) -> void:
	if body == null or not is_inside_tree():
		return
	for manager in get_tree().get_nodes_in_group("party_manager"):
		if manager != null and manager.has_method("unregister_party_member"):
			manager.call("unregister_party_member", body)
