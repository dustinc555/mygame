extends SceneTree

const DEMO_PATH := "res://scenes/test_levels/chair_exit_obstacle_demo.tscn"

var failures: Array[String] = []
var ecs_placeholder: Node


func _init() -> void:
	if not Engine.has_singleton("ECS"):
		ecs_placeholder = Node.new()
		Engine.register_singleton("ECS", ecs_placeholder)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(DEMO_PATH) as PackedScene
	_expect(packed != null, "chair exit obstacle demo loads")
	if packed == null:
		_finish()
		return
	var demo := packed.instantiate()
	demo.set("auto_run_sequence", false)
	root.add_child(demo)
	for _frame in range(180):
		await physics_frame
		if bool(demo.get("ready_for_test")):
			break
	_expect(bool(demo.get("ready_for_test")), "demo navigation bake completes")
	if not bool(demo.get("ready_for_test")):
		demo.queue_free()
		_finish()
		return
	var actor = demo.get_node("NavigationRegion3D/Actor")
	var chair = demo.get_node("NavigationRegion3D/Chair")
	for table_name in ["TableFront", "TableBack", "TableLeft"]:
		var table: Node3D = demo.get_node("NavigationRegion3D/%s" % table_name)
		_expect(table.global_position.distance_to(chair.global_position) <= 1.06, "%s tightly blocks its side of the chair" % table_name)
	var entry_start: Vector3 = actor.global_position
	_expect(bool(demo.call("seat_actor")), "actor accepts the chair through production interaction capability")
	var walked_to_chair := false
	for _frame in 300:
		await physics_frame
		walked_to_chair = walked_to_chair or actor.global_position.distance_to(entry_start) > 0.2
		if actor.is_sitting():
			break
	_expect(walked_to_chair, "actor physically walks from the open corridor to chair interaction range")
	_expect(actor.is_sitting(), "actor sits only after physically reaching the chair")
	var physics_anchor: Vector3 = actor.global_position
	var reached_anchor: Vector3 = actor.get_interaction().current_seat_stand_position
	_expect(physics_anchor.distance_to(reached_anchor) < 0.05,
			"physics root remains on the clear floor point physically reached beside the chair")
	await create_timer(0.3).timeout
	_expect(actor.get_body_projection().global_position.distance_to(chair.get_seat_position(actor)) < 0.05, "visual body sits in the chair")
	demo.call("issue_exit_order")
	var moved_from_anchor := false
	var rose_above_floor := false
	for _frame in range(900):
		await physics_frame
		moved_from_anchor = moved_from_anchor or actor.global_position.distance_to(physics_anchor) > 0.5
		rose_above_floor = rose_above_floor or actor.global_position.y > 0.25
		if bool(demo.call("reached_exit")):
			break
	_expect(moved_from_anchor, "movement order makes the actor leave the chair anchor")
	_expect(not rose_above_floor, "actor never climbs or teleports onto surrounding tables")
	_expect(bool(demo.call("reached_exit")), "actor walks through the only open corridor to the far target")
	_expect(not actor.is_sitting(), "actor leaves sitting state")
	demo.queue_free()
	await process_frame
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _finish() -> void:
	if ecs_placeholder != null and is_instance_valid(ecs_placeholder):
		ecs_placeholder.free()
	if failures.is_empty():
		print("CHAIR_EXIT_OBSTACLE_OK")
		quit(0)
		return
	print("CHAIR_EXIT_OBSTACLE_FAILED count=%d" % failures.size())
	quit(1)
