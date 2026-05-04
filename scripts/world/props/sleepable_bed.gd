extends StaticBody3D

class_name SleepableBed

@export var interaction_local_offset := Vector3(0.0, 0.0, 1.55)
@export var sleep_local_offset := Vector3(0.0, 0.55, 0.7)
@export var sleep_roll_degrees := 90.0
@export var sleep_yaw_offset_degrees := -90.0

var _sleeper: HumanoidCharacter
var _bar_venue: BarVenue


func _ready() -> void:
	add_to_group("sleepable_bed")


func get_interaction_position(_member: HumanoidCharacter) -> Vector3:
	return global_transform * interaction_local_offset


func get_sleep_position() -> Vector3:
	return global_transform * sleep_local_offset


func get_sleep_rotation() -> Vector3:
	return Vector3(0.0, global_rotation.y + deg_to_rad(sleep_yaw_offset_degrees), deg_to_rad(sleep_roll_degrees))


func set_bar_venue(venue: BarVenue) -> void:
	_bar_venue = venue


func request_sleep(member: HumanoidCharacter) -> Dictionary:
	if is_occupied() and _sleeper != member:
		return {"allowed": false, "message": "Bed occupied"}
	var venue := _resolve_bar_venue()
	if venue == null:
		return {"allowed": true, "message": ""}
	return venue.request_bed_sleep(member, self)


func claim_sleeper(member: HumanoidCharacter) -> bool:
	if member == null:
		return false
	if _sleeper != null and is_instance_valid(_sleeper) and _sleeper != member:
		return false
	_sleeper = member
	return true


func release_sleeper(member: HumanoidCharacter) -> void:
	if _sleeper == member:
		_sleeper = null


func is_occupied() -> bool:
	return _sleeper != null and is_instance_valid(_sleeper)


func _resolve_bar_venue() -> BarVenue:
	if _bar_venue != null and is_instance_valid(_bar_venue):
		return _bar_venue
	var node: Node = get_parent()
	while node != null:
		if node is BarVenue:
			_bar_venue = node
			return _bar_venue
		node = node.get_parent()
	return null
