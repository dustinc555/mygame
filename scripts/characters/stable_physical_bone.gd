extends PhysicalBone3D

class_name StablePhysicalBone

@export var max_linear_speed := 18.0
@export var max_angular_speed := 28.0

var upward_velocity_suppression_frames := 0


func set_upward_velocity_suppression_frames(frame_count: int) -> void:
	upward_velocity_suppression_frames = maxi(0, frame_count)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var current_linear_velocity := state.linear_velocity
	if upward_velocity_suppression_frames > 0:
		if current_linear_velocity.y > 0.0:
			current_linear_velocity.y = 0.0
		upward_velocity_suppression_frames = maxi(0, upward_velocity_suppression_frames - 1)
	if current_linear_velocity.length() > max_linear_speed:
		current_linear_velocity = current_linear_velocity.normalized() * max_linear_speed
	state.linear_velocity = current_linear_velocity
	var current_angular_velocity := state.angular_velocity
	if current_angular_velocity.length() > max_angular_speed:
		state.angular_velocity = current_angular_velocity.normalized() * max_angular_speed
