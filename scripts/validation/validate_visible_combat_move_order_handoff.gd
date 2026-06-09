extends SceneTree

const TEST_SCENE_PATH := "res://scenes/test_levels/combat_beat_5v5_test.tscn"
const ACTOR_ID := "combat_beat.combat_beat_5v5.side_a.001"
const WAIT_FRAMES := 180
const SNAP_EPSILON := 0.12

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	var scene_resource := load(TEST_SCENE_PATH) as PackedScene
	_expect(scene_resource != null, "CombatBeat 5v5 scene loads")
	if scene_resource == null:
		_finish()
		return
	var scene := scene_resource.instantiate()
	root.add_child(scene)
	for _frame in range(WAIT_FRAMES):
		await process_frame
	var bootstrap := scene.get_node_or_null("GameBootstrap")
	_expect(bootstrap != null, "GameBootstrap exists")
	if bootstrap == null:
		_finish()
		return
	var gecs := bootstrap.get_node_or_null("GecsWorldController")
	var projection_controller := bootstrap.get_node_or_null("WorldActorProjectionController")
	var selection_controller := bootstrap.get_node_or_null("WorldSelectionController")
	var control_controller := bootstrap.get_node_or_null("WorldPlayerControlController")
	var movement_sim := bootstrap.get_node_or_null("WorldMovementOrderSimController")
	_expect(gecs != null, "GECS controller exists")
	_expect(projection_controller != null, "Projection controller exists")
	_expect(selection_controller != null, "Selection controller exists")
	_expect(control_controller != null, "Player control controller exists")
	_expect(movement_sim != null, "Movement sim exists")
	if gecs == null or projection_controller == null or selection_controller == null or control_controller == null or movement_sim == null:
		_finish()
		return
	var projection := projection_controller.call("get_projection_for_actor", ACTOR_ID) as Node3D
	_expect(projection != null, "Selected actor projection exists")
	if projection == null:
		_finish()
		return
	var live_position := projection.global_position
	_expect(bool(selection_controller.call("select_actor_id", ACTOR_ID)), "Actor can be selected")
	var target := live_position + Vector3(-4.0, 0.0, 0.0)
	_expect(bool(control_controller.call("issue_move_command_at_world_position", target, false)), "Move command accepted from visible combat")
	var projection_after_command := projection_controller.call("get_projection_for_actor", ACTOR_ID) as Node3D
	_expect(projection_after_command != null, "Projection still exists after command")
	if projection_after_command != null:
		_expect(projection_after_command.global_position.distance_to(live_position) <= SNAP_EPSILON, "Projection does not snap when command is issued")
	var ordered_record: Dictionary = gecs.call("get_population_record_core", ACTOR_ID)
	_expect(_record_position(ordered_record).distance_to(live_position) <= SNAP_EPSILON, "Move order starts from live projected position")
	movement_sim.call("update_sim", 0.1)
	projection_controller.call("sync_projections")
	var projection_after_tick := projection_controller.call("get_projection_for_actor", ACTOR_ID) as Node3D
	var moved_record: Dictionary = gecs.call("get_population_record_core", ACTOR_ID)
	if projection_after_tick != null:
		_expect(projection_after_tick.global_position.distance_to(_record_position(moved_record)) <= SNAP_EPSILON, "Projection reconciles to fixed-tick movement without old-position snap")
	_finish()


func _record_position(record: Dictionary) -> Vector3:
	var position = record.get("last_world_position", record.get("world_position", Vector3.ZERO))
	return position if position is Vector3 else Vector3.ZERO


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("VISIBLE_COMBAT_MOVE_ORDER_HANDOFF_VALIDATION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("VISIBLE_COMBAT_MOVE_ORDER_HANDOFF_VALIDATION_FAILED")
	quit(1)
