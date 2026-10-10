extends GutTest

class PresentationProbe extends HumanoidCharacter:
	var locomotion_updates := 0
	var marker_updates := 0
	var carry_updates := 0
	var settled := false
	func _enter_tree() -> void:
		pass
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
	func process_world_actor_movement(_delta: float) -> void:
		pass
	func _update_locomotion_animation(_delta: float) -> void:
		locomotion_updates += 1
	func _update_carried_pose() -> void:
		carry_updates += 1
	func _update_ground_markers() -> void:
		marker_updates += 1
	func _begin_stand_up_settle() -> void:
		settled = true
		_stand_up_exit_remaining = 0.0

func _actor() -> PresentationProbe:
	var actor := PresentationProbe.new()
	add_child_autofree(actor)
	actor._body = HumanoidBodyProjection.new()
	actor.add_child(actor._body)
	return actor

func test_physics_catchup_does_not_repeat_frame_presentation() -> void:
	var actor := _actor()
	for tick in range(8):
		actor._physics_process(1.0 / 60.0)
	assert_eq(actor.locomotion_updates, 0)
	assert_eq(actor.marker_updates, 0)
	assert_eq(actor.carry_updates, 0)
	actor._process(8.0 / 60.0)
	assert_eq(actor.locomotion_updates, 1)
	assert_eq(actor.marker_updates, 1)
	assert_eq(actor.carry_updates, 1)

func test_seat_exit_keeps_physics_time_without_a_rendered_frame() -> void:
	var actor := _actor()
	actor._stand_up_exit_remaining = 0.2
	actor._physics_process(0.1)
	assert_almost_eq(actor._stand_up_exit_remaining, 0.1, 0.001)
	assert_false(actor.settled)
	actor._physics_process(0.11)
	assert_true(actor.settled)

func test_combat_interruption_holds_seat_exit_clock() -> void:
	var actor := _actor()
	actor._stand_up_exit_remaining = 0.2
	actor._system_combat_action_active = true
	actor._physics_process(0.3)
	assert_eq(actor._stand_up_exit_remaining, 0.2)
	assert_false(actor.settled)
	actor._system_combat_action_active = false
	actor._physics_process(0.3)
	assert_true(actor.settled)
