extends GutTest

const LOCKS := preload("res://features/lockpicking/sim/lockpicking_controller.gd")
const BRIDGE := preload("res://features/lockpicking/bridge/lockpick_interaction_controller.gd")
const QUIET_ACTOR := preload("res://tests/unit/test_lockpicking_interaction.gd").QuietHumanoid

class OwnedCell extends JailCell:
	func get_owner_faction_name() -> String: return "town"

class Sight extends Node:
	var visible := false
	var checks := 0
	func evaluate_observer(_observer: WorldActor, _subject: WorldActor) -> Dictionary:
		checks += 1
		return {"clearly_seen": visible}

var previous_context: BootstrapContext
var context: BootstrapContext
var locks
var bridge
var law: LawOrderController
var sight: Sight
var actor: HumanoidCharacter
var guard: HumanoidCharacter
var cell: JailCell

func before_each() -> void:
	previous_context = BootstrapContext.active
	context = BootstrapContext.new(self)
	BootstrapContext.active = context
	var gecs := GecsWorldController.new()
	add_child_autofree(gecs)
	context.register(&"gecs_world", gecs)
	gecs.initialize(context)
	gecs.set_process(false)
	var query := ActorQueryController.new()
	add_child_autofree(query)
	context.register(&"actor_query", query)
	query.initialize(context)
	locks = LOCKS.new()
	add_child_autofree(locks)
	context.register(&"lockpicking", locks)
	locks.initialize(context)
	locks.settings = locks.settings.duplicate()
	locks.settings.careful_risk = 0.0
	bridge = BRIDGE.new()
	add_child_autofree(bridge)
	context.register(&"lockpick_interactions", bridge)
	bridge.initialize(context)
	sight = Sight.new()
	add_child_autofree(sight)
	context.register(&"perception", sight)
	var alerts := CrimeAlertController.new()
	add_child_autofree(alerts)
	alerts.initialize(context)
	law = LawOrderController.new()
	add_child_autofree(law)
	law.set_process(false)
	law._context = context
	law.root_scene = self
	law._crime_alerts = alerts
	context.register(&"law_order", law)
	actor = QUIET_ACTOR.new()
	actor.stable_id = "picker"
	actor.faction_name = "player"
	actor.player_party_member = true
	add_child_autofree(actor)
	actor.add_to_group("world_actor")
	actor.inventory = InventoryData.new()
	actor.inventory.entries.append(actor.inventory.create_entry(load("res://features/inventory/resources/items/lockpick.tres"), Vector2i.ZERO))
	guard = QUIET_ACTOR.new()
	guard.stable_id = "guard"
	guard.faction_name = "town"
	guard.player_party_member = false
	add_child_autofree(guard)
	guard.add_to_group("world_actor")
	cell = OwnedCell.new()
	cell.cell_id = "witness"
	add_child_autofree(cell)
	bridge.register_target(cell)

func after_each() -> void:
	bridge.cancel_actor("picker")
	BootstrapContext.active = previous_context

func start_work() -> void:
	assert_true(bridge.request_pick(actor, cell))
	bridge.set_physics_process(false)
	actor.position = cell.get_lockpick_position(actor)
	bridge._tick("picker", 0.01)

func test_observer_arriving_during_clean_unfinished_attempt_reports_once() -> void:
	start_work()
	assert_true(law.warrants.is_empty(), "An unseen start is not a crime report")
	sight.visible = true
	bridge._tick("picker", 0.3)
	assert_false(law.warrants.is_empty(), "New sight must catch ongoing work before any pass or slip")
	if law.warrants.is_empty(): return
	var record: Dictionary = law.warrants.picker.town
	assert_eq(record.crimes.size(), 1)
	assert_eq(record.crimes[0].crime_type, LawOrderController.CRIME_LOCKPICKING)
	assert_eq(record.crimes[0].witness_key, "guard")
	assert_eq(record.state, "wanted")
	assert_eq(locks.get_state("cell:witness").progress, 0.0)
	bridge._tick("picker", 1.0)
	assert_eq(record.crimes.size(), 1, "Repeated sight is not another charge")

func test_unseen_slip_does_not_identify_picker_by_proximity() -> void:
	locks.settings.careful_risk = 1.0
	start_work()
	var work = locks._component("cell:witness")
	work.difficulty = 100.0
	var rng := RandomNumberGenerator.new()
	for sequence in range(100):
		rng.seed = abs(("cell:witness:%d" % sequence).hash())
		if rng.randf() < 0.5:
			work.check_sequence = sequence
			break
	guard.position = actor.position + Vector3(0.5, 0, 0)
	bridge._tick("picker", 20.0)
	assert_gt(float(actor.inventory.entries[0].metadata.get("lockpick_wear", 0.0)), 0.0, "The real attempt must slip")
	assert_true(law.warrants.is_empty(), "Hearing a slip without sight cannot identify the offender")

func test_missing_perception_does_not_assume_visible() -> void:
	sight.free()
	start_work()
	assert_true(law.warrants.is_empty(), "No vision provider is not proof of a witness")

func test_own_faction_lock_is_not_a_crime() -> void:
	actor.faction_name = "town"
	sight.visible = true
	start_work()
	bridge._tick("picker", 1.0)
	assert_true(law.warrants.is_empty(), "Authorized owners may work their own lock")
	assert_true(actor.is_actively_lockpicking())

func test_sight_checks_use_authored_cadence_and_stop_after_report() -> void:
	locks.settings.witness_check_interval_seconds = 0.5
	start_work()
	assert_eq(sight.checks, 1)
	for tick in range(4): bridge._tick("picker", 0.1)
	assert_eq(sight.checks, 1, "Not a ray test every physics frame")
	bridge._tick("picker", 0.11)
	assert_eq(sight.checks, 2)
	sight.visible = true
	bridge._tick("picker", 0.5)
	assert_eq(sight.checks, 3)
	bridge._tick("picker", 1.0)
	assert_eq(sight.checks, 3, "A reported session needs no further witness search")

func test_approach_is_not_lock_tampering() -> void:
	sight.visible = true
	actor.position = Vector3(10, 0, 0)
	assert_true(bridge.request_pick(actor, cell))
	bridge.set_physics_process(false)
	bridge._tick("picker", 1.0)
	assert_true(law.warrants.is_empty())
	assert_eq(sight.checks, 0)

func test_move_cancellation_cannot_report_later() -> void:
	start_work()
	actor.set_move_target(Vector3(8, 0, 0))
	sight.visible = true
	bridge._tick("picker", 1.0)
	assert_true(law.warrants.is_empty())
	assert_true(bridge._sessions.is_empty())
	assert_true(locks._claims.is_empty())
	assert_eq(actor.get_move_target(), Vector3(8, 0, 0))

func test_law_callback_cancellation_does_not_advance_or_restore_work() -> void:
	start_work()
	var elapsed: float = locks.get_state("cell:witness").beat_elapsed
	law._crime_alerts.crime_event_emitted.connect(func(_event): actor.set_move_target(Vector3(8, 0, 0)))
	sight.visible = true
	bridge._tick("picker", 0.3)
	assert_false(law.warrants.is_empty())
	assert_true(bridge._sessions.is_empty())
	assert_true(locks._claims.is_empty())
	assert_false(actor.is_actively_lockpicking())
	assert_eq(locks.get_state("cell:witness").beat_elapsed, elapsed)
	assert_eq(actor.get_move_target(), Vector3(8, 0, 0))

func test_target_destruction_cancels_before_sight_and_replacement_can_resume() -> void:
	start_work()
	cell.free()
	sight.visible = true
	bridge._tick("picker", 0.3)
	assert_true(law.warrants.is_empty())
	assert_true(locks._claims.is_empty())
	assert_false(actor.is_actively_lockpicking())
	cell = OwnedCell.new()
	cell.cell_id = "witness"
	add_child_autofree(cell)
	start_work()
	assert_false(law.warrants.is_empty())

func test_actor_destruction_cancels_before_sight_and_replacement_can_resume() -> void:
	start_work()
	var saved_bag := actor.inventory
	actor.free()
	sight.visible = true
	bridge._tick("picker", 0.3)
	assert_true(law.warrants.is_empty())
	assert_true(locks._claims.is_empty())
	actor = QUIET_ACTOR.new()
	actor.stable_id = "picker"
	actor.faction_name = "player"
	add_child_autofree(actor)
	actor.inventory = saved_bag
	start_work()
	assert_false(law.warrants.is_empty())

func test_freed_witness_is_not_reused_from_spatial_query() -> void:
	start_work()
	guard.free()
	sight.visible = true
	bridge._tick("picker", 0.3)
	assert_true(law.warrants.is_empty())
	assert_true(actor.is_actively_lockpicking())

func test_queued_target_cancels_before_sight() -> void:
	start_work()
	cell.queue_free()
	sight.visible = true
	bridge._tick("picker", 0.3)
	assert_true(law.warrants.is_empty())
	assert_true(locks._claims.is_empty())

func test_actual_vision_requires_facing_and_unobstructed_ray() -> void:
	sight.free()
	var perception := PerceptionController.new()
	add_child_autofree(perception)
	perception.root_scene = self
	perception.set_process(false)
	context.register(&"perception", perception)
	guard.position = Vector3(0.383, 0, 5)
	guard.rotation.y = PI
	start_work()
	assert_false(bool(perception.evaluate_observer(guard, actor).clearly_seen))
	assert_true(law.warrants.is_empty(), "Guard looking away cannot see picking")
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(4, 4, 0.3)
	wall.add_child(shape)
	wall.position = Vector3(0, 1.5, 3)
	add_child_autofree(wall)
	guard.rotation.y = 0.0
	await wait_physics_frames(2)
	assert_eq(perception.evaluate_observer(guard, actor).line_of_sight_fraction, 0.0)
	bridge._tick("picker", 0.3)
	assert_true(law.warrants.is_empty(), "A nearby facing guard still cannot see through a wall")
	wall.free()
	await wait_physics_frames(2)
	assert_true(bool(perception.evaluate_observer(guard, actor).clearly_seen))
	bridge._tick("picker", 0.3)
	assert_false(law.warrants.is_empty(), "The same unfinished attempt is caught when sight opens")
