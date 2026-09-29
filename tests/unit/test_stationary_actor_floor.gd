extends GutTest

class GroundedActor extends WorldActor:
	var floor_motion_calls := 0
	var avoidance_submissions := 0
	func _apply_floor_motion(delta: float) -> void:
		floor_motion_calls += 1
		super._apply_floor_motion(delta)
	func _submit_navigation_avoidance_velocity(desired_velocity: Vector3) -> void:
		avoidance_submissions += 1
		super._submit_navigation_avoidance_velocity(desired_velocity)
	func _enter_tree() -> void:
		pass
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)

var _viewport: SubViewport
var _root: Node3D
var _actor: GroundedActor
var _floor: StaticBody3D

func before_each() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	add_child(_viewport)
	_root = Node3D.new()
	_viewport.add_child(_root)
	_floor = _box(Vector3(0, -0.1, 0), Vector3(10, 0.2, 10))
	_actor = GroundedActor.new()
	_actor.collision_layer = 2
	_actor.collision_mask = 1
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	collision.shape = capsule
	_actor.add_child(collision)
	_root.add_child(_actor)
	_actor.position.y = 0.9
	await get_tree().physics_frame
	await get_tree().physics_frame
	_actor.velocity = Vector3.DOWN
	_actor.move_and_slide()
	_actor.velocity = Vector3.ZERO
	assert_true(_actor.is_on_floor())

func after_each() -> void:
	_viewport.queue_free()
	await get_tree().process_frame

func _can_rest() -> bool:
	if not _actor.has_method("_can_keep_stationary_floor"):
		assert_true(false, "Stationary actors validate support without sweeping their body")
		return false
	return _actor.call("_can_keep_stationary_floor")

func test_stationary_flat_supported_body_can_rest() -> void:
	assert_true(_can_rest())

func test_resting_body_stops_repeating_navigation_work() -> void:
	for tick in range(6):
		_actor._process_navigation_motion(1.0 / 60.0, false)
	assert_eq(_actor.floor_motion_calls, 0, "Validated support does not need repeated floor snapping")
	assert_eq(_actor.avoidance_submissions, 1, "Publish a stop once, not every stationary tick")
	assert_true(_actor.is_on_floor())

func test_new_destination_leaves_stationary_navigation_immediately() -> void:
	_actor._process_navigation_motion(1.0 / 60.0, false)
	var before := _actor.floor_motion_calls
	_actor._navigation_agent.set_move_target(Vector3(3, 0.9, 0))
	_actor._process_navigation_motion(1.0 / 60.0, false)
	assert_eq(_actor.floor_motion_calls, before + 1, "A command must not wait for an idle timer")

func test_resting_body_falls_after_support_is_removed() -> void:
	_actor._process_navigation_motion(1.0 / 60.0, false)
	var before := _actor.global_position.y
	_floor.queue_free()
	for tick in range(8):
		await get_tree().physics_frame
		_actor._process_navigation_motion(1.0 / 60.0, false)
	assert_lt(_actor.global_position.y, before - 0.01, "Support loss resumes real gravity and collision movement")

func test_combat_keeps_movement_and_facing_work_active() -> void:
	_actor._process_navigation_motion(1.0 / 60.0, false)
	var before := _actor.floor_motion_calls
	_actor._process_navigation_motion(1.0 / 60.0, true)
	assert_eq(_actor.floor_motion_calls, before + 1)

func test_movement_always_runs_native_slide() -> void:
	_actor.velocity = Vector3(0.01, 0, 0)
	assert_false(_can_rest())

func test_removed_support_wakes_body_immediately() -> void:
	assert_true(_can_rest())
	_floor.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_false(_can_rest())

func test_new_obstruction_wakes_body() -> void:
	assert_true(_can_rest())
	_box(Vector3(0.2, 0.9, 0), Vector3(0.4, 1.8, 1))
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_false(_can_rest())

func test_lowered_support_does_not_leave_body_floating() -> void:
	assert_true(_can_rest())
	_floor.position.y -= 0.01
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_false(_can_rest())

func test_moving_support_keeps_native_platform_handling() -> void:
	_floor.constant_linear_velocity = Vector3.RIGHT
	await get_tree().physics_frame
	assert_false(_can_rest())

func test_stationary_slope_uses_capsule_contact_not_center_bottom() -> void:
	_floor.rotation.z = 0.2
	_actor.position.y = 1.0
	for tick in range(40):
		await get_tree().physics_frame
		_actor.velocity = Vector3.DOWN * 2.0
		_actor.move_and_slide()
		if _actor.is_on_floor():
			break
	_actor.velocity = Vector3.ZERO
	assert_true(_actor.is_on_floor())
	assert_true(_can_rest(), "A supported capsule may retain its stationary slope contact")
	_actor.floor_stop_on_slope = false
	assert_false(_can_rest(), "Native sliding remains active when slope stopping is disabled")

func _box(position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	_root.add_child(body)
	body.position = position
	return body
