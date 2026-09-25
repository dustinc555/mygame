extends "res://tests/validation/test_case.gd"

const FIXTURE = preload("res://tests/validation/helpers/navigation_fixture.gd")
var _failed := false

func _initialize() -> void:
	var world = FIXTURE.new()
	root.add_child(world)
	world.add_floor(Vector3(180, 1, 180))
	var floor_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(180, 0.1, 180)
	floor_mesh.mesh = box
	floor_mesh.position.y = -0.06
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.45, 0.34, 0.20)
	floor_mesh.material_override = material
	world.add_child(floor_mesh)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	world.add_child(sun)
	var party = world.add_actor("camp.proof.player", Vector3(0, 0, 65))
	if not await world.boot():
		_check(false, "fixture navigation boot")
		quit(1)
		return
	var context := BootstrapContext.active
	var marker := CampMarker.new()
	marker.camp_id = "proof.camp"

	marker.operational_radius = 35.0
	marker.squad_count = 1
	marker.squad_size = 3
	world.add_child(marker)
	var gecs := context.require(&"gecs_world")
	var population := context.require(&"population")
	var camps := context.require(&"camps")
	var projection := context.require(&"camp_realization")
	var clock := context.require(&"world_time")
	clock.set_time_of_day(12)
	# First rendered launch also compiles the real mixed-race shaders.
	var spawn_timeout := 20.0 if DisplayServer.get_name() == "headless" else 60.0
	_check(await world.wait_until(func(): return projection.get("_actors").size() == 16, spawn_timeout), "all medium camp members realized")
	if projection.get("_actors").size() != 16:
		print("CAMP_BOOT_DIAGNOSTIC ", {"actors": projection.get("_actors").size(), "paused": paused, "pause_reasons": clock.get("_pause_reasons"), "anchors": context.require(&"population_realization").get_realization_anchor_positions()})
		for slot in gecs.get_camp_state(marker.camp_id).get("slots", []):
			var record: Dictionary = population.get_actor_record(str(slot.actor_id))
			print("CAMP_MEMBER_DIAGNOSTIC ", slot.actor_id, " life=", record.get("life_state"), " live=", is_instance_valid(population.get_live_actor(str(slot.actor_id))))
		world.dispose()
		quit(1)
		return
	var state: Dictionary = gecs.get_camp_state(marker.camp_id)
	_check(not state.is_empty(), "durable camp generated")
	if state.is_empty():
		quit(1)
		return
	var patrol_id := str(state.slots[-1].actor_id)
	var patrol: Node3D = population.get_live_actor(patrol_id)
	var start: Vector3 = patrol.global_position
	_check(await world.wait_until(func(): return patrol.global_position.distance_to(start) > 3.0, 15), "patrol physically moves")
	var furniture: Node = projection.get("_furniture")[marker.camp_id]
	_check(await world.wait_until(func():
		for child in furniture.get_children():
			if child is FacilityGuardPost and child.get_assigned_worker() != null:
				return true
		return false, 4), "generated guard posts are claimed")
	_check(await world.wait_until(func(): return _seated(population, state) >= 2, 20), "residents physically sit on campfire stools")
	var seated_ids: Array[String] = []
	for slot in state.slots:
		var resident = population.get_live_actor(str(slot.actor_id))
		if resident != null and resident.get_interaction().is_sitting:
			seated_ids.append(str(slot.actor_id))
	await create_timer(3.0).timeout
	for actor_id in seated_ids:
		var resident = population.get_live_actor(actor_id)
		_check(resident.get_interaction().is_sitting and not resident.has_move_target(), "seated idle retains pose without restarting navigation")
	_check_seated_facing(furniture)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.global_position = Vector3(12, 17, 16)
	camera.look_at(Vector3(0, 0.5, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 20.0
	camera.current = true
	if DisplayServer.get_name() != "headless":
		for child in world.find_children("*", "CanvasLayer", true, false):
			child.visible = false
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.test-results/camp-seating.png")
	# Time only settled production routine steps, separate from rendering and
	# the rest of the world's frame cost. This is not a player FPS measurement.
	var idle_jobs: Array = []
	for slot in state.slots:
		var actor = population.get_live_actor(str(slot.actor_id))
		var ai = gecs.get_actor_entity(actor).get_component(CGameAiState)
		if str(slot.squad_id).is_empty() and ai.active_job != null and not actor.has_move_target():
			idle_jobs.append([actor, ai.active_job])
	var idle_start := Time.get_ticks_usec()
	for sample in 1000:
		for pair in idle_jobs:
			pair[1].steps[0].tick(pair[0], pair[1], 0.0)
	var idle_usec := float(Time.get_ticks_usec() - idle_start) / 1000.0
	print("CAMP_IDLE_COST ", JSON.stringify({"settled_residents": idle_jobs.size(), "routine_batch_usec": idle_usec}))
	var containers: Array = []
	for child in furniture.get_children():
		if child is WorldContainer:
			containers.append(child)
			_check(not child.inventory.entries.is_empty(), "container has rolled stock")
			_check(child.owner_faction_name == "roaming_desert_thugs", "container faction owner")
	_check(containers.size() >= 4, "lightweight containers generated")
	var container = containers[0]
	var container_id: String = container.container_id
	container.inventory.entries.clear()
	container.inventory.changed.emit()
	# Legacy layouts are compacted in place, without recreating looted containers.
	var container_instance: int = container.get_instance_id()
	var legacy := state.duplicate(true)
	legacy.erase("layout_version")
	legacy.camp_radius = 100.0
	for entry in legacy.furnishings:
		entry.offset *= 12.5
	gecs.upsert_camp_state(legacy)
	camps.register_marker(marker)
	state = gecs.get_camp_state(marker.camp_id)
	_check(container.get_instance_id() == container_instance and container.inventory.entries.is_empty(), "live migration preserves looted container instance")
	for child in furniture.get_children():
		_check(Vector2(child.global_position.x, child.global_position.z).length() <= 8.01, "migrated furniture stays compact")
	clock.advance_minutes(9.0 * 60.0)
	_check(await world.wait_until(func(): return _sleepers(population, state) == 11, 25), "thirteen residents leave two watches and eleven sleep")
	if _sleepers(population, state) != 11:
		for slot in state.slots:
			var actor = population.get_live_actor(str(slot.actor_id))
			var ai = gecs.get_actor_entity(actor).get_component(CGameAiState)
			print("CAMP_SLEEP_DIAGNOSTIC ", slot.resident_index, " life=", actor.life_state, " position=", actor.global_position, " job=", ai.active_job.data if ai.active_job != null else {})
	_check(patrol.life_state == NpcRules.LifeState.ALIVE, "patrol stays awake at night")
	for child in furniture.get_children():
		if child is LightFixture:
			_check(child.get_light_node().visible and child.get_node("FlameGlow").visible, "camp fire uses torch nighttime lighting")
	# Rendered runs save the actual production furnishings and actors, not mockups.
	if DisplayServer.get_name() != "headless":
		sun.light_energy = 0.08
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color(0.035, 0.04, 0.06)
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color(0.35, 0.4, 0.55)
		environment.environment.ambient_light_energy = 0.3
		world.add_child(environment)
		for child in world.find_children("*", "CanvasLayer", true, false):
			child.visible = false
		for frame in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.test-results/camp-night.png")
	clock.advance_minutes(15.0 * 60.0)
	sun.light_energy = 1.0
	_check(await world.wait_until(func(): return _sleepers(population, state) == 0, 10), "residents wake next morning")
	if DisplayServer.get_name() != "headless":
		await create_timer(3.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.test-results/camp-day.png")
	# Force normal LOD decision through its configured retention boundary.
	var lod := context.require(&"population_realization")
	lod.set_realization_retention_seconds(0.0)
	var squad_controller := context.require(&"world_sim_squad")
	squad_controller.set_process(false)
	var ids: Array = state.slots.map(func(slot): return str(slot.actor_id))
	var appearances: Dictionary = {}
	var instances: Dictionary = {}
	var equipment: Dictionary = {}
	for id in ids:
		appearances[id] = population.get_actor_record(id).appearance
		instances[id] = population.get_live_actor(id).get_instance_id()
		equipment[id] = population.get_actor_record(id).equipment_slots
	var old_furniture_id := furniture.get_instance_id()
	var target: Vector3 = gecs.get_world_sim_squads()[0].target_position
	projection.call("update_lod_swap", gecs, gecs.get_world_sim_squads(), [] as Array[Vector3], 120.0)
	await process_frame
	_check(projection.get("_actors").is_empty(), "LOD destroys all camp actors")
	for id in ids:
		_check(population.get_live_actor(id) == null, "no retained live body " + id)
	for batch in 4:
		projection.call("update_lod_swap", gecs, gecs.get_world_sim_squads(), [Vector3.ZERO] as Array[Vector3], 120.0)
		await process_frame
	await process_frame
	furniture = projection.get("_furniture")[marker.camp_id]
	_check(furniture.get_instance_id() != old_furniture_id, "furniture projection recreated")
	_check(await world.wait_until(func(): return _seated(population, state) >= 2, 20), "seats reacquired after full LOD destruction")
	_check_seated_facing(furniture)
	for child in furniture.get_children():
		if child is WorldContainer and child.container_id == container_id:
			_check(child.inventory.entries.is_empty(), "looted container remains empty after LOD")
	for id in ids:
		_check(population.get_actor_record(id).appearance == appearances[id], "appearance retained " + id)
		_check(population.get_live_actor(id).get_instance_id() != instances[id], "new projection same identity " + id)
		_check(population.get_actor_record(id).equipment_slots == equipment[id], "equipment retained " + id)
	_check(gecs.get_world_sim_squads()[0].target_position == target, "patrol destination retained across LOD")
	var simulation := context.require(WorldSimulationController.SERVICE_ID)
	var saved_time: float = clock.total_world_minutes
	# Save an actual old sprawling layout and resident transform, then load normally.
	legacy = gecs.get_camp_state(marker.camp_id)
	legacy.erase("layout_version")
	legacy.camp_radius = 100.0
	for entry in legacy.furnishings:
		entry.offset *= 12.5
	gecs.upsert_camp_state(legacy)
	var displaced = population.get_live_actor(str(state.slots[1].actor_id))
	displaced.global_position = Vector3(40, 0, 40)
	_check(simulation.save_world_to_file("user://camp-runtime-roundtrip.tres"), "live camp save")
	var saved_camp: Dictionary = gecs.get_camp_state(marker.camp_id)
	var changed := saved_camp.duplicate(true)
	changed.status = "empty"
	gecs.upsert_camp_state(changed)
	clock.advance_minutes(1440.0)
	_check(simulation.load_world_from_file("user://camp-runtime-roundtrip.tres"), "live camp load")
	for frame in 4:
		await process_frame
	_check(gecs.get_camp_state(marker.camp_id).slots == saved_camp.slots, "saved roster wins over current session")
	_check(absf(clock.total_world_minutes - saved_time) < 2.0, "saved clock restored before lifecycle")
	_check(float(gecs.get_camp_state(marker.camp_id).camp_radius) == 8.0, "legacy save layout migrated")
	_check(Vector2(displaced.global_position.x, displaced.global_position.z).length() <= 8.01, "legacy saved resident returns inside compact camp")
	projection.call("update_lod_swap", gecs, gecs.get_world_sim_squads(), [Vector3.ZERO] as Array[Vector3], 120.0)
	await process_frame
	for child in projection.get("_furniture")[marker.camp_id].get_children():
		if child is WorldContainer and child.container_id == container_id:
			_check(child.inventory.entries.is_empty(), "looted container remains empty after save load")
	squad_controller.set_process(true)
	population.mark_record_dead(str(state.slots[0].actor_id))
	clock.set_time_of_day(21)
	_check(await world.wait_until(func():
		var watch = population.get_live_actor(str(state.slots[1].actor_id))
		var ai = gecs.get_actor_entity(watch).get_component(CGameAiState)
		return _sleepers(population, state) == 10 and watch.life_state == NpcRules.LifeState.ALIVE and ai.active_job != null and str(ai.active_job.data.get("routine", "")) == "guard", 25), "survivor takes night watch after leader dies")
	var defender = population.get_live_actor(str(state.slots[1].actor_id))
	party.global_position = defender.global_position + Vector3(3, 0, 0)
	_check(await world.wait_until(func(): return defender.get_current_combat_target() == party, 10), "hostile camp guard acquires approaching player")
	# All but the patrol die; survivors prevent clearing and immediate replacement.
	for slot in state.slots:
		if str(slot.squad_id).is_empty():
			population.mark_record_dead(str(slot.actor_id))
	camps.advance_camp(marker.camp_id, clock.total_world_minutes)
	_check(gecs.get_camp_state(marker.camp_id).status == "occupied", "lingering patrol keeps camp occupied")
	for slot in state.slots:
		population.mark_record_dead(str(slot.actor_id))
	camps.advance_camp(marker.camp_id, clock.total_world_minutes)
	state = gecs.get_camp_state(marker.camp_id)
	_check(state.status == "cleared", "total wipe clears camp")
	camps.advance_camp(marker.camp_id, float(state.cleared_at) + 10080.0)
	_check(gecs.get_camp_state(marker.camp_id).status == "empty", "week removes camp permanently")
	projection.call("update_lod_swap", gecs, gecs.get_world_sim_squads(), [Vector3.ZERO] as Array[Vector3], 120.0)
	_check(not projection.get("_furniture").has(marker.camp_id), "empty camp has no furniture projection")
	print("CAMP_RUNTIME_RESULT ", "FAIL" if _failed else "PASS")
	world.dispose()
	await process_frame
	quit(1 if _failed else 0)

func _check_seated_facing(furniture: Node) -> void:
	var fires: Array[Node3D] = []
	for child in furniture.get_children():
		if str(child.get_meta("camp_purpose", "")) in ["center", "fire"]:
			fires.append(child)
	var checked := 0
	for child in furniture.get_children():
		if not child is SittableSeat:
			continue
		var actor: HumanoidCharacter = child.get_sitter()
		if actor == null or not actor.get_interaction().is_sitting:
			continue
		var body := actor.get_body_projection()
		var nearest := Vector3.ZERO
		var distance := INF
		for fire in fires:
			var delta: Vector3 = fire.global_position - body.global_position
			delta.y = 0.0
			if delta.length_squared() < distance:
				distance = delta.length_squared()
				nearest = delta
		_check((-body.global_basis.z).dot(nearest.normalized()) > 0.99, "seated visual faces nearest campfire")
		checked += 1
	_check(checked >= 2, "facing checked on multiple physically seated residents")

func _seated(population: Node, state: Dictionary) -> int:
	var count := 0
	for slot in state.slots:
		var actor = population.get_live_actor(str(slot.actor_id))
		if is_instance_valid(actor) and actor.get_interaction().is_sitting:
			count += 1
	return count

func _sleepers(population: Node, state: Dictionary) -> int:
	var count := 0
	for slot in state.slots:
		var actor = population.get_live_actor(str(slot.actor_id))
		if is_instance_valid(actor) and int(actor.life_state) == NpcRules.LifeState.ASLEEP:
			count += 1
	return count

func _check(value: bool, label: String) -> void:
	print("CAMP_CHECK ", "PASS " if value else "FAIL ", label)
	_failed = _failed or not value
