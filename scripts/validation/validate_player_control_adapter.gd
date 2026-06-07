extends SceneTree

class EcsPlaceholder:
	extends Node
	var debug := false

const DEMO_WORLD_SCENE_PATH := "res://scenes/worlds/demo_world/demo_world.tscn"

var _failures: Array[String] = []
var _ecs_placeholder: Node
var _registered_ecs_placeholder := false


func _initialize() -> void:
	_ensure_ecs_placeholder()
	var scene_resource := load(DEMO_WORLD_SCENE_PATH) as PackedScene
	if scene_resource == null:
		_failures.append("Demo world scene loads for move-order validation")
		_finish()
		return
	var scene := scene_resource.instantiate()
	root.add_child(scene)
	call_deferred("_run_validation", scene)


func _run_validation(scene: Node) -> void:
	for _index in range(18):
		await process_frame
	_promote_root_ecs_singleton()
	var bootstrap := scene.get_node_or_null("GameBootstrap")
	_expect(bootstrap != null, "GameBootstrap exists for move-order validation")
	if bootstrap == null:
		_finish()
		return
	var gecs := bootstrap.get_node_or_null("GecsWorldController")
	var projection_controller := bootstrap.get_node_or_null("WorldActorProjectionController")
	var selection_controller := bootstrap.get_node_or_null("WorldSelectionController")
	var control_controller := bootstrap.get_node_or_null("WorldPlayerControlController")
	var movement_sim := bootstrap.get_node_or_null("WorldMovementOrderSimController")
	_expect(gecs != null, "GecsWorldController exists")
	_expect(projection_controller != null, "WorldActorProjectionController exists")
	_expect(selection_controller != null, "WorldSelectionController exists")
	_expect(control_controller != null, "WorldPlayerControlController exists")
	_expect(movement_sim != null, "WorldMovementOrderSimController exists")
	if gecs == null or projection_controller == null or selection_controller == null or control_controller == null or movement_sim == null:
		_finish()
		return
	projection_controller.call("sync_projections")
	await process_frame

	_validate_multi_select_and_focus(scene, projection_controller, selection_controller, control_controller)
	_validate_controllable_move_order(gecs, projection_controller, selection_controller, control_controller, movement_sim, "player.mira", Vector3(4.0, 0.0, 0.0))
	_validate_controllable_move_order(gecs, projection_controller, selection_controller, control_controller, movement_sim, "player.tomas", Vector3(0.0, 0.0, 4.0))
	_validate_non_controllable_actor(gecs, selection_controller, control_controller)
	_finish()


func _validate_multi_select_and_focus(scene: Node, projection_controller: Node, selection_controller: Node, control_controller: Node) -> void:
	var accepted := bool(selection_controller.call("select_actor_ids", ["player.mira", "player.tomas"], false))
	_expect(accepted, "Drag-style actor-id selection accepts Mira and Tomas")
	var selected_ids: Array = selection_controller.call("get_selected_actor_ids")
	_expect(selected_ids.has("player.mira") and selected_ids.has("player.tomas"), "Drag-style selection stores Mira and Tomas")
	var projection := projection_controller.call("get_projection_for_actor", "player.mira") as Node3D
	var rig := scene.find_child("CameraRig", true, false)
	_expect(projection != null, "Mira projection exists for double-click focus")
	_expect(rig != null and rig.has_method("get_follow_target"), "Camera rig exposes follow target for focus validation")
	if projection == null or rig == null:
		return
	control_controller.call("_follow_projection", projection)
	_expect(rig.call("get_follow_target") == projection, "Double-click focus path follows selected projection")


func _validate_controllable_move_order(gecs: Node, projection_controller: Node, selection_controller: Node, control_controller: Node, movement_sim: Node, actor_id: String, offset: Vector3) -> void:
	var before: Dictionary = gecs.call("get_population_record", actor_id)
	_expect(not before.is_empty(), "%s GECS record exists before move order" % actor_id)
	if before.is_empty():
		return
	var before_position := _record_position(before)
	_expect(bool(selection_controller.call("select_actor_id", actor_id)), "Can select controllable %s" % actor_id)
	_expect(bool(control_controller.call("has_active_control")), "%s selection enables issuing orders" % actor_id)
	var accepted := bool(control_controller.call("issue_move_command_at_world_position", before_position + offset, false))
	_expect(accepted, "%s accepts RTS move order" % actor_id)
	var ordered: Dictionary = gecs.call("get_population_record", actor_id)
	var ordered_position := _record_position(ordered)
	_expect(ordered_position.is_equal_approx(before_position), "%s command write does not directly move GECS position" % actor_id)
	var order: Dictionary = ordered.get("move_order", {}) if ordered.get("move_order", {}) is Dictionary else {}
	_expect(bool(order.get("active", false)), "%s GECS record stores active move order" % actor_id)
	_expect(str((ordered.get("control_intent", {}) as Dictionary).get("mode", "")) == "move_order", "%s GECS intent stores move order mode" % actor_id)
	_expect(not bool(control_controller.call("blocks_camera_free_movement")), "%s move order does not block WASD camera" % actor_id)
	movement_sim.call("update_sim", 0.5)
	projection_controller.call("sync_projections")
	var after: Dictionary = gecs.call("get_population_record", actor_id)
	var after_position := _record_position(after)
	_expect(before_position.distance_to(after_position) > 0.5, "%s fixed movement sim advances GECS position" % actor_id)
	var locomotion: Dictionary = after.get("locomotion_state", {}) if after.get("locomotion_state", {}) is Dictionary else {}
	_expect(bool(locomotion.get("moving", false)), "%s GECS locomotion state is moving after sim tick" % actor_id)
	_expect(bool(after.get("world_facing_yaw_initialized", false)), "%s GECS facing yaw is initialized by sim" % actor_id)
	var projection := projection_controller.call("get_projection_for_actor", actor_id) as Node3D
	_expect(projection != null, "%s projection exists during move order" % actor_id)
	if projection != null:
		_expect(projection.global_position.is_equal_approx(after_position), "%s projection reconciles to GECS moved position" % actor_id)
	var details: Dictionary = selection_controller.call("get_selected_details_snapshot")
	_expect(is_equal_approx(float(details.get("hp", 0.0)), float(after.get("hp", 0.0))), "%s selection details remain GECS-backed during movement" % actor_id)


func _validate_non_controllable_actor(gecs: Node, selection_controller: Node, control_controller: Node) -> void:
	var other_actor_id := ""
	for node in get_nodes_in_group("projected_world_actor"):
		if not (node is Node):
			continue
		var actor_id := str((node as Node).get("actor_id"))
		if not actor_id.is_empty() and not actor_id.begins_with("player."):
			other_actor_id = actor_id
			break
	_expect(not other_actor_id.is_empty(), "At least one non-player projected actor exists for order rejection")
	if other_actor_id.is_empty():
		return
	var before: Dictionary = gecs.call("get_population_record", other_actor_id)
	var before_position := _record_position(before)
	_expect(bool(selection_controller.call("select_actor_id", other_actor_id)), "Can select non-controllable actor")
	_expect(not bool(control_controller.call("has_active_control")), "Non-player selection does not activate order control")
	var accepted := bool(control_controller.call("issue_move_command_at_world_position", before_position + Vector3(2.0, 0.0, 0.0), false))
	_expect(not accepted, "Non-controllable actor rejects RTS move order")
	var after: Dictionary = gecs.call("get_population_record", other_actor_id)
	_expect(_record_position(after).is_equal_approx(before_position), "Non-controllable actor GECS position is unchanged")


func _record_position(record: Dictionary) -> Vector3:
	var position = record.get("last_world_position", record.get("world_position", Vector3.ZERO))
	return position if position is Vector3 else Vector3.ZERO


func _finish() -> void:
	if _failures.is_empty():
		print("PLAYER_MOVE_ORDER_VALIDATION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _ensure_ecs_placeholder() -> void:
	if Engine.has_singleton("ECS"):
		return
	_ecs_placeholder = EcsPlaceholder.new()
	_ecs_placeholder.name = "ECSPlaceholder"
	Engine.register_singleton("ECS", _ecs_placeholder)
	_registered_ecs_placeholder = true


func _promote_root_ecs_singleton() -> void:
	if not _registered_ecs_placeholder:
		return
	var ecs_node := root.get_node_or_null("ECS")
	if ecs_node == null:
		return
	Engine.unregister_singleton("ECS")
	if _ecs_placeholder != null:
		_ecs_placeholder.free()
		_ecs_placeholder = null
	Engine.register_singleton("ECS", ecs_node)
	_registered_ecs_placeholder = false
