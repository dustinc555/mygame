extends StaticBody3D

class_name SittableSeat

@export var interaction_local_offset := Vector3(0.0, 0.0, 0.9)
@export var seat_local_offset := Vector3(0.0, 0.72, 0.0)
@export var stand_local_offset := Vector3(0.0, 0.0, 1.15)
@export var sit_arrival_distance := 3.0

var _sitter: HumanoidCharacter
var _bar_venue: BarVenue
var _seated_since_seconds := 0.0
var _service_requested := false
var _service_completed := false


func _ready() -> void:
	add_to_group("sittable_seat")


func get_interaction_position(_member: HumanoidCharacter) -> Vector3:
	return global_transform * interaction_local_offset


func get_seat_position() -> Vector3:
	return global_transform * seat_local_offset


func get_seat_rotation() -> Vector3:
	return Vector3(0.0, global_rotation.y, 0.0)


func get_stand_position() -> Vector3:
	return global_transform * stand_local_offset


func get_arrival_distance() -> float:
	return sit_arrival_distance


func can_sit_from_position(world_position: Vector3) -> bool:
	return get_sit_distance_to(world_position) <= sit_arrival_distance


func get_sit_distance_to(world_position: Vector3) -> float:
	var seat_position := get_seat_position()
	var flat_delta := Vector3(world_position.x - seat_position.x, 0.0, world_position.z - seat_position.z)
	return flat_delta.length()


func set_bar_venue(venue: BarVenue) -> void:
	_bar_venue = venue


func claim_sitter(member: HumanoidCharacter) -> bool:
	if member == null:
		return false
	if _sitter != null and is_instance_valid(_sitter) and _sitter != member:
		return false
	if _sitter != member:
		_seated_since_seconds = Time.get_ticks_msec() / 1000.0
		_service_requested = false
		_service_completed = false
	_sitter = member
	return true


func release_sitter(member: HumanoidCharacter) -> void:
	if _sitter == member:
		_sitter = null
		_seated_since_seconds = 0.0
		_service_requested = false
		_service_completed = false


func is_occupied() -> bool:
	return _sitter != null and is_instance_valid(_sitter)


func get_sitter() -> HumanoidCharacter:
	return _sitter if is_occupied() else null


func get_seated_seconds() -> float:
	if not is_occupied():
		return 0.0
	return Time.get_ticks_msec() / 1000.0 - _seated_since_seconds


func is_waiting_for_service(required_seconds: float) -> bool:
	if not is_occupied() or _service_requested or _service_completed:
		return false
	if _sitter == null or not _sitter.is_player_party_member():
		return false
	return get_seated_seconds() >= required_seconds


func mark_service_requested() -> void:
	_service_requested = true


func mark_service_completed() -> void:
	_service_requested = false
	_service_completed = true
