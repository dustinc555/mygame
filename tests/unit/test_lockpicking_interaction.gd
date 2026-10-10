extends GutTest

const LOCKS := preload("res://features/lockpicking/sim/lockpicking_controller.gd")
const BRIDGE := preload("res://features/lockpicking/bridge/lockpick_interaction_controller.gd")

class QuietHumanoid extends HumanoidCharacter:
	func _ready() -> void:
		for cap in _capabilities.values():
			(cap as ActorCapability).ready()
		set_process(false)
		set_physics_process(false)
	func show_world_speech(_message: String, _duration := 3.0) -> void: pass

var context: BootstrapContext
var previous_context: BootstrapContext
var gecs: GecsWorldController
var locks
var bridge
var actor: QuietHumanoid
var cell: JailCell

func before_each() -> void:
	previous_context = BootstrapContext.active
	context = BootstrapContext.new(self)
	BootstrapContext.active = context
	gecs = GecsWorldController.new()
	add_child_autofree(gecs)
	context.register(&"gecs_world", gecs)
	gecs.initialize(context)
	gecs.set_process(false)
	locks = LOCKS.new()
	add_child_autofree(locks)
	context.register(&"lockpicking", locks)
	locks.initialize(context)
	bridge = BRIDGE.new()
	add_child_autofree(bridge)
	context.register(&"lockpick_interactions", bridge)
	bridge.initialize(context)
	actor = QuietHumanoid.new()
	actor.stable_id = "picker"
	add_child_autofree(actor)
	actor.inventory = InventoryData.new()
	cell = JailCell.new()
	cell.cell_id = "integration"
	add_child_autofree(cell)
	bridge.register_target(cell)

func after_each() -> void:
	bridge.cancel_actor(actor.stable_id)
	BootstrapContext.active = previous_context

func give_pick() -> void:
	actor.inventory.entries.append(actor.inventory.create_entry(load("res://features/inventory/resources/items/lockpick.tres"), Vector2i.ZERO))

func test_actions_require_pick_and_requests_cannot_bypass_inventory() -> void:
	assert_eq(cell.get_world_context_actions(actor).size(), 0)
	assert_false(bridge.request_pick(actor, cell))
	give_pick()
	assert_eq(cell.get_world_context_actions(actor).size(), 2)
	assert_true(bridge.request_pick(actor, cell))
	actor.inventory.entries.clear()
	bridge._tick(actor.stable_id, 0.1)
	assert_true(bridge._sessions.is_empty())
	assert_false(actor.is_actively_lockpicking())

func test_approach_has_no_progress_then_work_and_move_cancel_synchronously() -> void:
	give_pick()
	actor.position = Vector3(10, 0, 0)
	assert_true(bridge.request_pick(actor, cell))
	bridge._tick(actor.stable_id, 1.0)
	assert_eq(locks.get_state("cell:integration").progress, 0.0)
	assert_false(actor.is_actively_lockpicking())
	# Unit-test only the arrival boundary; physical navigation is validated separately.
	actor.position = cell.get_lockpick_position(actor)
	bridge._tick(actor.stable_id, 0.5)
	assert_true(actor.is_actively_lockpicking())
	assert_gt(actor.get_lockpick_attempt_progress_ratio(), 0.0)
	assert_eq(actor.get_lockpick_progress_ratio(), 0.0)
	var progress: float = actor.get_lockpick_progress_ratio()
	actor.set_move_target(Vector3(8, 0, 0))
	assert_false(actor.is_actively_lockpicking())
	assert_true(bridge._sessions.is_empty())
	assert_eq(actor.get_move_target(), Vector3(8, 0, 0), "Cancellation must not erase the new move order")
	assert_eq(locks.get_state("cell:integration").progress, progress)

func test_work_bar_tracks_attempt_not_earned_progress() -> void:
	var ui := WorldInteractionController.new()
	autofree(ui)
	actor.set_lockpick_work_visual(true, Vector3(0, 1, 0), 0.66, null, 0.42)
	assert_almost_eq(ui._get_member_work_progress_ratio(actor), 0.42, 0.0001)
	actor.set_lockpick_work_visual(false, Vector3.ZERO, 0.0, null)
	assert_eq(ui._get_member_work_progress_ratio(actor), 0.0)

func test_lock_symbol_keeps_shared_timer_and_lights_only_earned_pins() -> void:
	var ui := WorldInteractionController.new()
	add_child_autofree(ui)
	ui._context = context
	ui.progress_layer = Control.new()
	ui.add_child(ui.progress_layer)
	ui.camera = Camera3D.new()
	ui.camera.position = Vector3(0, 2, 6)
	ui.add_child(ui.camera)
	ui.party_members.append(actor)
	ui._ensure_work_progress_bar(actor)
	var timer: ProgressBar = ui.work_progress_bars[actor]
	var original_fill: StyleBox = timer.get_theme_stylebox("fill")
	actor.set_lockpick_work_visual(true, Vector3.ZERO, 0.0, null, 0.428715)
	ui._update_progress_bars()
	assert_same(timer.get_theme_stylebox("fill"), original_fill, "Picking must not restyle the shared gray timer")
	assert_eq(timer.value, snappedf(42.8715, timer.step), "Native shared-bar rounding, not green progress")
	assert_null(timer.get_node_or_null("EarnedProgress"), "No second loading bar")
	var earned := timer.get_node_or_null("LockProgress") as Control
	assert_not_null(earned, "Earned progress is a lock with lit pins")
	if earned == null: return
	assert_false(earned is ProgressBar)
	assert_eq(earned.get("completed_pins"), 0)
	actor.set_lockpick_work_visual(true, Vector3.ZERO, 1.0 / 3.0, null, 0.0)
	ui._update_progress_bars()
	assert_eq(earned.get("completed_pins"), 1)
	var tween: Tween = earned.get("_pulse_tween")
	tween.custom_step(0.1)
	assert_gt(float(earned.get("pulse")), 0.0, "A passed pin briefly glints")
	tween.custom_step(0.2)
	assert_eq(float(earned.get("pulse")), 0.0)
	# Another failed attempt resets gray, but does not light or flash another pin.
	actor.set_lockpick_work_visual(true, Vector3.ZERO, 1.0 / 3.0, null, 0.1)
	ui._update_progress_bars()
	assert_eq(timer.value, 10.0)
	assert_eq(earned.get("completed_pins"), 1)
	assert_eq(float(earned.get("pulse")), 0.0)
	actor.set_lockpick_work_visual(false, Vector3.ZERO, 0.0, null)
	ui._update_progress_bars()
	assert_false(timer.visible)
	assert_false(earned.visible)
	assert_same(timer.get_theme_stylebox("fill"), original_fill)
	actor.set_farming_work_visual(true, "plant", Vector3.ZERO, 0.5)
	ui._update_progress_bars()
	assert_true(timer.visible)
	assert_eq(timer.value, 50.0)
	assert_false(earned.visible, "Changing to ordinary work must not retain a lock symbol")
	assert_same(timer.get_theme_stylebox("fill"), original_fill)

func test_cage_escape_releases_custody_but_not_warrant_or_confiscated_items() -> void:
	var law := LawOrderController.new()
	add_child_autofree(law)
	law._context = context
	law.root_scene = self
	context.register(&"law_order", law)
	actor.add_to_group("world_actor")
	assert_true(cell.assign_prisoner(actor))
	actor.enter_cell_custody(cell, cell.get_prisoner_position(actor), cell.get_prisoner_rotation(actor))
	law.prisoner_records[actor.stable_id] = {"faction_id": "guards", "state": "jailed"}
	law.warrants[actor.stable_id] = {"guards": {"faction_id": "guards", "state": "jailed", "bounty": 30}}
	assert_true(actor.is_in_cell_custody())
	law.release_picked_cell(cell)
	assert_true(actor.is_in_cell_custody(), "A locked cell cannot invoke escape")
	cell.apply_lockpick_state({"is_locked": false})
	cell.on_lockpick_completed(actor)
	assert_false(actor.is_in_cell_custody())
	assert_false(law.prisoner_records.has(actor.stable_id))
	assert_eq(law.warrants[actor.stable_id].guards.state, "wanted")
	assert_eq(law.warrants[actor.stable_id].guards.bounty, 30)
	assert_true(actor.inventory.entries.is_empty(), "Picking never conjures confiscated gear")
	assert_true(cell.occupant_ids.is_empty())

func test_symbol_resume_and_tuning_do_not_fake_a_success() -> void:
	var symbol = load("res://features/lockpicking/projection/lock_progress_symbol.gd").new()
	add_child_autofree(symbol)
	symbol.update_progress(true, 1.0 / 3.0, 3)
	assert_eq(symbol.completed_pins, 1)
	assert_eq(symbol.pulse, 0.0)
	symbol.update_progress(false, 1.0 / 3.0, 3)
	symbol.update_progress(true, 1.0 / 3.0, 3)
	assert_eq(symbol.completed_pins, 1)
	assert_eq(symbol.pulse, 0.0)
	symbol.update_progress(true, 0.5, 8)
	assert_eq(symbol.pin_count, 8)
	assert_eq(symbol.completed_pins, 4)
	assert_eq(symbol.pulse, 0.0)
	assert_eq(symbol.size.y, 43.0, "Additional authored passes fit another pin row")
	symbol.update_progress(true, 0.625, 8)
	assert_gt(symbol.pulse, 0.0)
	var pulse_tween: Tween = symbol._pulse_tween
	symbol.update_progress(false, 0.625, 8)
	assert_false(pulse_tween.is_valid())
	assert_false(symbol.visible)
	assert_eq(symbol.pulse, 0.0)
