extends StaticBody3D

class_name SittableSeat

@export var interaction_local_offset := Vector3(0.0, 0.0, 0.9)
@export var service_local_offset := Vector3(0.0, 0.0, -1.15)
@export var seated_floor_local_offset := Vector3.ZERO
@export var seated_yaw_offset_degrees := 180.0
@export var stand_local_offset := Vector3(0.0, 0.0, 1.15)
@export var sit_arrival_distance := 3.0

var _sitter: HumanoidCharacter
var _bar_service_area: BarServiceArea
var _seated_since_seconds := 0.0
var _service_requested := false
var _service_completed := false


func _ready() -> void:
	add_to_group("sittable_seat")


func get_interaction_position(_member: HumanoidCharacter) -> Vector3:
	return global_transform * interaction_local_offset


func get_service_position(_member: HumanoidCharacter) -> Vector3:
	return global_transform * service_local_offset


func get_seat_position(member: HumanoidCharacter = null) -> Vector3:
	var seated_floor_position := global_transform * seated_floor_local_offset
	if member != null:
		return member.get_floor_aligned_origin_position(seated_floor_position)
	return seated_floor_position


func get_seat_rotation(_member: HumanoidCharacter = null) -> Vector3:
	return Vector3(0.0, global_rotation.y + deg_to_rad(seated_yaw_offset_degrees), 0.0)


func get_stand_position() -> Vector3:
	return global_transform * stand_local_offset


func get_arrival_distance() -> float:
	return sit_arrival_distance


func can_sit_from_position(world_position: Vector3) -> bool:
	return get_sit_distance_to(world_position) <= sit_arrival_distance


func get_sit_distance_to(world_position: Vector3) -> float:
	var seat_position := global_transform * seated_floor_local_offset
	var flat_delta := Vector3(world_position.x - seat_position.x, 0.0, world_position.z - seat_position.z)
	return flat_delta.length()


func set_bar_service_area(service_area: BarServiceArea) -> void:
	_bar_service_area = service_area


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


func should_use_sitting_talking_idle(member: HumanoidCharacter) -> bool:
	return _bar_service_area != null and member != null and not member.is_player_party_member()
