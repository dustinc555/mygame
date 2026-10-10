extends GutTest

const CONTROLLER_PATH := "res://features/lockpicking/sim/lockpicking_controller.gd"
var controller
var gecs: GecsWorldController
var context: BootstrapContext
var bag: InventoryData
var pick
var doors: DoorController

func before_each() -> void:
	context = BootstrapContext.new(self)
	gecs = GecsWorldController.new()
	add_child_autofree(gecs)
	context.register(&"gecs_world", gecs)
	gecs.initialize(context)
	gecs.set_process(false)
	doors = DoorController.new()
	add_child_autofree(doors)
	context.register(&"doors", doors)
	doors.initialize(context)
	if ResourceLoader.exists(CONTROLLER_PATH):
		controller = load(CONTROLLER_PATH).new()
		add_child_autofree(controller)
		context.register(&"lockpicking", controller)
		controller.initialize(context)
	bag = InventoryData.new()
	pick = bag.create_entry(load("res://features/inventory/resources/items/lockpick_fine.tres"), Vector2i.ZERO)
	bag.entries.append(pick)

func test_shared_work_authority_exists() -> void:
	assert_not_null(controller)

func register_lock(id := "cell:test") -> void:
	controller.register_lock({"lock_id": id, "is_locked": true, "difficulty": 40.0})

func test_no_pick_no_claim_and_no_remote_progress() -> void:
	if controller == null: return
	register_lock()
	assert_false(controller.claim("cell:test", "mira", InventoryData.new(), "careful").accepted)
	var result: Dictionary = controller.advance("cell:test", "mira", bag, 80.0, 60.0, 10.0)
	assert_false(result.accepted)
	assert_eq(controller.get_state("cell:test").progress, 0.0)

func test_exclusive_claim_and_removed_tool_interrupt_without_substitution() -> void:
	if controller == null: return
	register_lock()
	assert_true(controller.claim("cell:test", "mira", bag, "careful").accepted)
	assert_false(controller.claim("cell:test", "tomas", bag, "careful").accepted)
	bag.remove_entry(pick)
	bag.entries.append(bag.create_entry(pick.definition, Vector2i.ZERO))
	var result: Dictionary = controller.advance("cell:test", "mira", bag, 80.0, 60.0, 1.0)
	assert_eq(result.reason, "pick_missing")
	assert_eq(controller.get_state("cell:test").progress, 0.0)

func test_interrupt_and_reregister_preserve_progress_and_check_sequence() -> void:
	if controller == null: return
	register_lock()
	controller.claim("cell:test", "mira", bag, "careful")
	controller.advance("cell:test", "mira", bag, 100.0, 100.0, 3.0)
	var before: Dictionary = controller.get_state("cell:test")
	assert_gt(before.progress, 0.0)
	controller.release("cell:test", "mira")
	register_lock()
	var after: Dictionary = controller.get_state("cell:test")
	assert_eq(after.progress, before.progress)
	assert_eq(after.check_sequence, before.check_sequence)
	assert_eq(after.beat_elapsed, before.beat_elapsed)

func test_chunking_does_not_change_random_results_or_wear() -> void:
	if controller == null: return
	register_lock()
	controller.claim("cell:test", "mira", bag, "rushed")
	var saved := "user://lockpick_chunking.tres"
	assert_true(gecs.save_gecs_world(saved))
	controller.advance("cell:test", "mira", bag, 35.0, 20.0, 20.0)
	var whole: Dictionary = controller.get_state("cell:test")
	assert_gt(whole.check_sequence, 0, "Chunking comparison must cross actual random checks")
	var whole_metadata: Dictionary = pick.metadata.duplicate(true)
	assert_true(gecs.load_gecs_world(saved))
	pick.metadata.clear()
	controller.claim("cell:test", "mira", bag, "rushed")
	for i in range(200):
		controller.advance("cell:test", "mira", bag, 35.0, 20.0, 0.1)
	var split: Dictionary = controller.get_state("cell:test")
	assert_almost_eq(split.progress, whole.progress, 0.00001)
	assert_eq(split.check_sequence, whole.check_sequence)
	assert_eq(pick.metadata, whole_metadata)

func test_success_unlocks_persistently_and_relock_starts_fresh() -> void:
	if controller == null: return
	register_lock()
	controller.claim("cell:test", "mira", bag, "careful")
	controller.advance("cell:test", "mira", bag, 100.0, 100.0, 120.0)
	assert_false(controller.get_state("cell:test").is_locked)
	var saved := "user://lockpick_unlock.tres"
	assert_true(gecs.save_gecs_world(saved))
	assert_true(gecs.load_gecs_world(saved))
	register_lock()
	assert_false(controller.get_state("cell:test").is_locked)
	controller.relock("cell:test")
	assert_true(controller.get_state("cell:test").is_locked)
	assert_eq(controller.get_state("cell:test").progress, 0.0)

func test_door_requires_completed_work_and_unlock_survives_reload() -> void:
	doors.register_door({"door_id": "test", "default_locked": true})
	controller.register_lock({"lock_id": "door:test", "door_id": "test"})
	assert_false(doors.complete_lockpick("test", 0))
	controller.claim("door:test", "mira", bag, "careful")
	assert_true(controller.advance("door:test", "mira", bag, 100.0, 100.0, 120.0).complete)
	assert_false(doors.get_door_state("test").is_locked)
	assert_true(gecs.save_gecs_world("user://lockpick_door.tres"))
	assert_true(gecs.load_gecs_world("user://lockpick_door.tres"))
	doors.register_door({"door_id": "test", "default_locked": true})
	assert_false(doors.get_door_state("test").is_locked)

func test_door_revision_invalidates_old_lease() -> void:
	doors.register_door({"door_id": "test", "default_locked": true})
	controller.register_lock({"lock_id": "door:test", "door_id": "test"})
	controller.claim("door:test", "mira", bag, "careful")
	controller.advance("door:test", "mira", bag, 100.0, 100.0, 1.0)
	var state = doors._get_door_component("test")
	state.state_revision += 1
	assert_false(controller.advance("door:test", "mira", bag, 100.0, 100.0, 1.0).accepted)
	assert_eq(controller.get_state("door:test").progress, 0.0)
	assert_true(doors.get_door_state("test").is_locked)

func test_fabricated_tool_snapshot_cannot_unlock_a_door() -> void:
	doors.register_door({"door_id": "test", "default_locked": true})
	var request := doors.submit_command("mira", "test", "lockpick", {"has_required_lockpick": true, "lockpick_skill_level": 100.0})
	assert_false(request.accepted)
	assert_true(doors.get_door_state("test").is_locked)

func test_minimum_skill_is_enforced_at_work_boundary() -> void:
	controller.register_lock({"lock_id": "difficult", "is_locked": true, "minimum_skill": 50.0})
	controller.claim("difficult", "mira", bag, "careful")
	assert_false(controller.advance("difficult", "mira", bag, 49.0, 100.0, 120.0).accepted)
	assert_true(controller.get_state("difficult").is_locked)

func test_partial_attempt_does_not_earn_unlock_progress() -> void:
	register_lock()
	controller.claim("cell:test", "mira", bag, "careful")
	var result: Dictionary = controller.advance("cell:test", "mira", bag, 100.0, 100.0, 0.5)
	assert_eq(result.progress, 0.0, "The gray timer is not earned unlock progress")
	assert_eq(controller.get_state("cell:test").check_sequence, 0)
	assert_gt(float(result.get("attempt_progress", 0.0)), 0.0)
	assert_lt(float(result.get("attempt_progress", 1.0)), 1.0)

func test_three_successful_attempts_unlock_but_never_early() -> void:
	controller.settings = controller.settings.duplicate()
	controller.settings.careful_risk = 0.0
	register_lock()
	controller.claim("cell:test", "mira", bag, "careful")
	for expected_passes in range(1, 4):
		var result: Dictionary = {}
		for tick in range(100):
			result = controller.advance("cell:test", "mira", bag, 100.0, 100.0, 0.05)
			if controller.get_state("cell:test").check_sequence >= expected_passes:
				break
			assert_almost_eq(result.progress, float(expected_passes - 1) / 3.0, 0.00001)
		assert_almost_eq(result.progress, float(expected_passes) / 3.0, 0.00001)
		assert_eq(result.complete, expected_passes == 3)
		assert_eq(controller.get_state("cell:test").is_locked, expected_passes != 3)
	assert_true(pick.metadata.is_empty(), "Successful attempts do not wear the pick")

func test_failed_attempt_preserves_earned_progress_and_wears_used_pick() -> void:
	controller.settings = controller.settings.duplicate()
	controller.settings.careful_risk = 1.0
	controller.register_lock({"lock_id": "failure", "is_locked": true, "difficulty": 100.0})
	var work = controller._component("failure")
	work.progress = 1.0 / 3.0
	# Fix a native RNG draw below the low-skill failure threshold before execution.
	var rng := RandomNumberGenerator.new()
	for sequence in range(100):
		rng.seed = abs(("failure:%d" % sequence).hash())
		if rng.randf() < 0.5:
			work.check_sequence = sequence
			break
	var original_sequence: int = work.check_sequence
	controller.claim("failure", "mira", bag, "careful")
	controller.advance("failure", "mira", bag, 0.0, 0.0, 19.99)
	assert_eq(work.check_sequence, original_sequence)
	controller.advance("failure", "mira", bag, 0.0, 0.0, 0.01)
	assert_eq(work.check_sequence, original_sequence + 1)
	assert_almost_eq(work.progress, 1.0 / 3.0, 0.00001, "Failure neither earns nor erases successful passes")
	assert_gt(float(pick.metadata.get("lockpick_wear", 0.0)), 0.0)
	assert_true(work.object_locked)

func test_authored_success_count_changes_earned_progress() -> void:
	controller.settings = controller.settings.duplicate()
	controller.settings.careful_risk = 0.0
	controller.settings.set("successes_required", 2)
	register_lock("baseline")
	register_lock("tuned")
	controller.claim("baseline", "mira", bag, "careful")
	var before: Dictionary = controller.advance("baseline", "mira", bag, 100.0, 100.0, 3.0)
	controller.settings.set("successes_required", 4)
	controller.claim("tuned", "mira", bag, "careful")
	var after: Dictionary = controller.advance("tuned", "mira", bag, 100.0, 100.0, 3.0)
	assert_almost_eq(before.progress, 0.5, 0.00001)
	assert_almost_eq(after.progress, 0.25, 0.00001)

func test_novice_attempt_takes_twenty_seconds_even_with_expert_dexterity() -> void:
	register_lock()
	controller.claim("cell:test", "mira", bag, "careful")
	var result: Dictionary = controller.advance("cell:test", "mira", bag, 1.0, 100.0, 10.0)
	assert_eq(controller.get_state("cell:test").check_sequence, 0, "A novice must not race through rolls")
	assert_almost_eq(result.attempt_progress, 0.5, 0.00001)
	assert_eq(result.progress, 0.0)
	controller.advance("cell:test", "mira", bag, 1.0, 100.0, 10.0)
	assert_eq(controller.get_state("cell:test").check_sequence, 1)

func test_expert_attempt_takes_two_seconds() -> void:
	register_lock()
	controller.claim("cell:test", "mira", bag, "careful")
	var result: Dictionary = controller.advance("cell:test", "mira", bag, 100.0, 1.0, 1.0)
	assert_eq(controller.get_state("cell:test").check_sequence, 0)
	assert_almost_eq(result.attempt_progress, 0.5, 0.00001)
	controller.advance("cell:test", "mira", bag, 100.0, 1.0, 1.0)
	assert_eq(controller.get_state("cell:test").check_sequence, 1)

func test_intermediate_skill_has_intermediate_attempt_duration() -> void:
	register_lock()
	controller.claim("cell:test", "mira", bag, "careful")
	# Skill 45 is 4/9 of the way from level 1 to 100: a 12-second attempt.
	var result: Dictionary = controller.advance("cell:test", "mira", bag, 45.0, 50.0, 6.0)
	assert_almost_eq(result.attempt_progress, 0.5, 0.00001)
	assert_eq(controller.get_state("cell:test").check_sequence, 0)
	controller.advance("cell:test", "mira", bag, 45.0, 50.0, 6.0)
	assert_eq(controller.get_state("cell:test").check_sequence, 1)

func test_rushing_accelerates_without_making_novices_experts() -> void:
	register_lock()
	controller.claim("cell:test", "mira", bag, "rushed")
	var result: Dictionary = controller.advance("cell:test", "mira", bag, 1.0, 100.0, 10.0)
	assert_almost_eq(result.attempt_progress, 0.75, 0.00001)
	assert_eq(controller.get_state("cell:test").check_sequence, 0)

func test_saved_partial_attempt_retains_fraction_after_timing_edit() -> void:
	controller.settings = controller.settings.duplicate()
	register_lock()
	controller.claim("cell:test", "mira", bag, "careful")
	controller.advance("cell:test", "mira", bag, 1.0, 1.0, 10.0)
	assert_true(gecs.save_gecs_world("user://lockpick_timing.tres"))
	assert_true(gecs.load_gecs_world("user://lockpick_timing.tres"))
	controller.settings.set("novice_attempt_seconds", 40.0)
	controller.claim("cell:test", "mira", bag, "careful")
	var result: Dictionary = controller.advance("cell:test", "mira", bag, 1.0, 1.0, 10.0)
	assert_almost_eq(result.attempt_progress, 0.75, 0.00001)
	assert_eq(controller.get_state("cell:test").check_sequence, 0)
	controller.advance("cell:test", "mira", bag, 1.0, 1.0, 10.0)
	assert_eq(controller.get_state("cell:test").check_sequence, 1)
