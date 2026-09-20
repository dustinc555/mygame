extends Node3D

## Controlled navigation integration world: real bootstrap, baker, colliders
## and party actor. No mutable zone coordinates, fake ECS or manual steering.
const ACTOR_PATH := "res://features/core/party/party_member.tscn"
var navigation: Node

func add_floor(size := Vector3(48, 1, 48), at := Vector3(0, -0.5, 0)) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	body.position = at
	add_child(body)
	return body

func add_actor(id: String, at: Vector3, player := true) -> CharacterBody3D:
	var actor: CharacterBody3D = load(ACTOR_PATH).instantiate()
	actor.stable_id = id
	actor.player_party_member = player
	actor.position = at
	var members := get_node_or_null("PartyMembers")
	if members == null:
		members = Node3D.new()
		members.name = "PartyMembers"
		add_child(members)
	members.add_child(actor)
	# PartyMember sets this in ready; an NPC fixture opts out afterward.
	actor.player_party_member = player
	if not player:
		actor.remove_from_group("party_member")
	return actor

func boot() -> bool:
	if get_node_or_null("PartyMembers") == null:
		var members := Node3D.new()
		members.name = "PartyMembers"
		add_child(members)
	var rig := Node3D.new()
	rig.name = "CameraRig"
	add_child(rig)
	var pivot := Node3D.new()
	pivot.name = "CameraPivot"
	rig.add_child(pivot)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	pivot.add_child(camera)
	camera.position = Vector3(0, 14, 18)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var party := Node.new()
	party.name = "PartyManager"
	party.set_script(load("res://features/core/party/party_manager.gd"))
	add_child(party)
	var bootstrap: Node = load("res://features/core/game_bootstrap.gd").new()
	bootstrap.name = "GameBootstrap"
	add_child(bootstrap)
	return await wait_ready()

func wait_ready(seconds := 30.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		navigation = get_tree().get_first_node_in_group("world_navigation_controller")
		if navigation == null or navigation._mode == 0 or navigation.is_initial_navigation_pending() or not navigation.is_idle():
			continue
		if NavigationServer3D.map_get_iteration_id(get_world_3d().navigation_map) > 0:
			await get_tree().physics_frame
			await get_tree().physics_frame
			return true
	return false

func path_reaches(start: Vector3, target: Vector3) -> bool:
	var path := NavigationServer3D.map_get_path(get_world_3d().navigation_map, start, target, true)
	return path.size() >= 2 and path[-1].distance_to(target) < 0.5

func walk(actor: CharacterBody3D, target: Vector3, seconds := 15.0) -> bool:
	var start := actor.global_position
	if not await wait_until(func(): return path_reaches(start, target), 5.0):
		print("NAV_FIXTURE_NO_PATH start=%s target=%s iteration=%s" % [start, target, NavigationServer3D.map_get_iteration_id(get_world_3d().navigation_map)])
		return false
	actor.set_move_target(target)
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	var moved := false
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		moved = moved or actor.global_position.distance_to(start) > 0.5
		# Door use temporarily finishes the approach target before the command
		# resolves and restores the original route. That is not final arrival.
		if not actor.has_move_target() and Vector2(actor.global_position.x - target.x, actor.global_position.z - target.z).length() <= actor.navigation_target_desired_distance + 0.05 and absf(actor.global_position.y - target.y) < 0.8:
			break
	var end := actor.global_position
	var agent := actor.get_node("NavigationAgent3D") as NavigationAgent3D
	print("NAV_FIXTURE_WALK start=%s end=%s target=%s moved=%s pending=%s order=%s final=%s path=%s" % [start, end, target, moved, actor.has_move_target(), actor.get_current_order_type(), agent.get_final_position(), agent.get_current_navigation_path()])
	return moved and not actor.has_move_target() and Vector2(end.x - target.x, end.z - target.z).length() <= actor.navigation_target_desired_distance + 0.05 and absf(end.y - target.y) < 0.8

func add_door(id: String) -> Node3D:
	var door: Node3D = load("res://scenes/building_pieces/quaternius/medieval_village_woodbrick/door_wood_flat.tscn").instantiate()
	door.door_id = id
	door.building_id = "navigation.fixture.building"
	add_child(door)
	return door

func wait_until(condition: Callable, seconds := 12.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		if condition.call():
			return true
	return false

## Read current movement owners without advancing navigation or changing state.
static func actor_motion_snapshot(actor: WorldActor) -> Dictionary:
	var bridge := BootstrapContext.service(GecsWorldController.SERVICE_ID) as GecsWorldController
	var entity = bridge.get_actor_entity(actor)
	var ai = entity.get_component(CGameAiState) if entity != null else null
	var navigation = actor.get_node("NavigationAgent3D")
	var collisions: Array = []
	for index in range(actor.get_slide_collision_count()):
		var collision := actor.get_slide_collision(index)
		var collider := collision.get_collider()
		collisions.append({"node": str(collider.get_path()) if is_instance_valid(collider) and collider is Node else str(collider), "normal": collision.get_normal()})
	return {
		"order": actor.get_current_order_type(), "player_order": actor.has_active_player_order(),
		"life": actor.life_state, "seated": actor.is_sitting(), "carried": actor.is_carried(),
		"position": actor.global_position, "target": actor.get_move_target(), "has_target": actor.has_move_target(),
		"velocity": actor.velocity, "collisions": collisions,
		"system_move": actor.get("_system_move_active"), "system_velocity": actor.get("_system_desired_velocity"),
		"job": ai.active_job_id if ai != null else "",
		"driver": ai.active_driver.get_debug_snapshot() if ai != null and ai.active_driver != null else {},
		"native_finished": navigation.is_navigation_finished(), "native_final": navigation.get_final_position(),
		"path": navigation.get_current_navigation_path(), "requested_velocity": navigation.velocity,
		"safe_velocity": navigation.safe_velocity, "has_safe_velocity": navigation.has_safe_velocity,
		"query_grace": navigation.get("_query_grace_remaining"), "stuck_repaths": navigation.get("_stuck_repath_attempts"),
	}

func dispose() -> void:
	get_tree().paused = false
	queue_free()
