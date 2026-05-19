extends PhysicalBone3D

class_name StablePhysicalBone

@export var max_linear_speed := 18.0
@export var max_angular_speed := 28.0


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var linear_velocity := state.linear_velocity
	if linear_velocity.length() > max_linear_speed:
		state.linear_velocity = linear_velocity.normalized() * max_linear_speed
	var angular_velocity := state.angular_velocity
	if angular_velocity.length() > max_angular_speed:
		state.angular_velocity = angular_velocity.normalized() * max_angular_speed
