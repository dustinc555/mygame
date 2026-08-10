extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_farming_worker_runtime.gd

var _root: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_root = load("res://scenes/test_levels/farming_test.tscn").instantiate()
	get_root().add_child(_root)
	await create_timer(3.0).timeout
	var context := BootstrapContext.active
	var farm = context.get_optional(&"farming") if context != null else null
	var work_bridge = context.get_optional(&"farm_work") if context != null else null
	var job_system = context.get_optional(&"job_system") if context != null else null
	var worker := _root.get_node_or_null("PartyMembers/Ada")
	if farm == null or work_bridge == null or job_system == null or worker == null:
		_fail("runtime farming dependencies exist")
		return
	var plots: Dictionary = farm.get_plots()
	var plot_id := str(plots.keys()[0])
	farm.request_cell_operation(plot_id, "0:0", "till")
	var initial_work: Dictionary = farm.get_cell_work(plot_id, "0:0")
	var initial_target: Vector3 = initial_work.get("world_position", worker.global_position)
	worker.global_position = initial_target + Vector3(1.0, 0.0, 0.0)
	worker.velocity = Vector3(0.75, 0.0, -0.35)
	var assignment := str(work_bridge.assign_cell(plot_id, "0:0", [worker]))
	if assignment.begins_with("Cannot"):
		_fail("worker accepted till order: %s" % assignment)
		return
	if not worker.has_meta(&"active_settlement_work"):
		_fail("physical farm assignment owns the actor against competing facility AI")
		return
	if not worker.has_move_target():
		_fail("farm travel probe starts with a live navigation target")
		return
	if Vector2(worker.velocity.x, worker.velocity.z).length_squared() <= 0.001:
		_fail("farm travel probe starts with residual movement velocity")
		return
	work_bridge.call("_process_assignment", worker.get_instance_id(), 0.05)
	var interaction = worker.get_interaction() if worker.has_method("get_interaction") else null
	if worker.has_move_target() \
			or Vector2(worker.velocity.x, worker.velocity.z).length_squared() > 0.001 \
			or worker.has_active_player_order() \
			or (interaction != null and int(interaction.current_order_type) == int(interaction.ORDER_TYPE_MOVE)):
		_fail("entering farming interaction range clears navigation and residual velocity immediately")
		return
	var tilled := 0
	var completion_seen := false
	for _step in 400:
		await create_timer(0.05).timeout
		tilled = 0
		for cell_value in (farm.get_plot(plot_id).get("cells", {}) as Dictionary).values():
			if str((cell_value as Dictionary).get("state", "")) == "tilled":
				tilled += 1
		if tilled > 0 and not work_bridge.has_active_work_for_actor(worker) and not worker.has_meta(&"active_settlement_work"):
			completion_seen = true
			break
	if tilled == 0:
		_fail("worker physically reached and tilled at least one cell")
		return
	if not completion_seen:
		_fail("completed farming reaches an observable idle state")
		return
	if worker.has_meta(&"active_settlement_work"):
		_fail("completed cell work releases actor ownership")
		return
	if worker.has_method("has_move_target") and bool(worker.call("has_move_target")):
		_fail("completed farming clears the final navigation target instead of repathing every two seconds")
		return
	if worker is CharacterBody3D and Vector2((worker as CharacterBody3D).velocity.x, (worker as CharacterBody3D).velocity.z).length_squared() > 0.001:
		_fail("completed farming clears residual horizontal velocity")
		return
	job_system.call("set_actor_jobs_enabled", worker, false)
	var city_positions: Array[Vector3] = [Vector3(10.0, 0.02, 8.0)]
	var city_plot: Dictionary = farm.create_plot(city_positions, Vector2i.ONE, "", "Player", "farming_test")
	var city_plot_id := str(city_plot.get("plot_id", ""))
	if city_plot_id.is_empty():
		_fail("same-faction basic-city field is created")
		return
	farm.request_cell_operation(city_plot_id, "0:0", "till")
	await create_timer(1.0).timeout
	if str(((farm.get_plot(city_plot_id).get("cells", {}) as Dictionary).get("0:0", {}) as Dictionary).get("state", "")) != "untilled" or work_bridge.has_active_work_for_actor(worker):
		_fail("Jobs off leaves designated farming work unclaimed")
		return
	job_system.call("set_actor_jobs_enabled", worker, true)
	var auto_tilled := false
	for _step in 200:
		await create_timer(0.1).timeout
		if str(((farm.get_plot(city_plot_id).get("cells", {}) as Dictionary).get("0:0", {}) as Dictionary).get("state", "")) == "tilled":
			auto_tilled = true
			break
	if not auto_tilled:
		_fail("Jobs on claims and completes same-faction farming by priority")
		return
	var rock := _root.get_node_or_null("RockObstacle")
	if rock != null:
		rock.queue_free()
	await create_timer(3.0).timeout
	var plot: Dictionary = farm.get_plot(plot_id)
	if str(((plot.get("cells", {}) as Dictionary).get("1:1", {}) as Dictionary).get("state", "")) == "blocked":
		_fail("blocked cell recovered after obstacle removal")
		return
	print("FARMING_WORKER_RUNTIME_OK tilled=%d" % tilled)
	_root.free()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	print("FARMING_WORKER_RUNTIME_FAILED")
	if _root != null and is_instance_valid(_root):
		_root.free()
	quit(1)
