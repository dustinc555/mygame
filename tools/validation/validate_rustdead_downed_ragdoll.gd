extends SceneTree

const FACTION_HUMANOID_SCRIPT := preload("res://features/actors/projection/humanoid/faction_humanoid.gd")
const RUSTDEAD_HUMANOID_SCRIPT := preload("res://features/actors/projection/rustdead/rustdead_humanoid_character.gd")

const VISUAL_BODY_TYPE_MALE := 2
const RAGDOLL_WAIT_FRAMES := 540

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _validate_repeated_lethal_vitals_do_not_restart_downed_preroll()
	await _validate_cinder_burn_keeps_pending_downed_ragdoll()
	if _failures.is_empty():
		print("RUSTDEAD_DOWNED_RAGDOLL_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("RUSTDEAD_DOWNED_RAGDOLL_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_repeated_lethal_vitals_do_not_restart_downed_preroll() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var attacker := _add_humanoid(scene, "Attacker", Vector3(-1.5, 0.0, 0.0))
	var rustdead := _add_rustdead(scene, "RepeatedVitalsRustdead", Vector3.ZERO)
	await _wait_process_frames(8)
	rustdead.force_kill(attacker)
	await process_frame
	if not rustdead.is_downed_state():
		_fail("Rustdead force_kill should leave actor downed, got %s" % rustdead.get_life_state_label())
		await _free_scene(scene)
		return
	if not rustdead._ragdoll_preroll_active and not rustdead._is_ragdoll_active:
		_fail("Downed Rustdead should start ragdoll preroll or ragdoll immediately")
	if rustdead._ragdoll_preroll_active:
		await physics_frame
		if not _ray_hits_actor(rustdead):
			_fail("Rustdead should remain ray-pickable while downed preroll is playing")
		var before_remaining := rustdead._ragdoll_preroll_remaining
		for _index in range(24):
			rustdead._recalculate_vitals()
			await process_frame
		if rustdead._ragdoll_preroll_active and rustdead._ragdoll_preroll_remaining >= before_remaining - 0.05:
			_fail("Repeated lethal Rustdead vitals should not restart downed preroll")
	await _wait_until_ragdoll_active("Repeated lethal vitals", rustdead, RAGDOLL_WAIT_FRAMES)
	for _index in range(16):
		rustdead._recalculate_vitals()
		await process_frame
	if not rustdead._is_ragdoll_active:
		_fail("Repeated lethal Rustdead vitals should not cancel active ragdoll")
	if not rustdead.is_downed_state():
		_fail("Unburned Rustdead should remain downed after lethal vitals, got %s" % rustdead.get_life_state_label())
	if not rustdead.can_be_destroyed_by_cinder():
		_fail("Downed unburned Rustdead should remain available for Cinder Flask destruction")
	await _free_scene(scene)


func _validate_cinder_burn_keeps_pending_downed_ragdoll() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var attacker := _add_humanoid(scene, "CinderAttacker", Vector3(-1.5, 0.0, 0.0))
	var rustdead := _add_rustdead(scene, "CinderPrerollRustdead", Vector3.ZERO)
	await _wait_process_frames(8)
	rustdead.cinder_burn_duration_seconds = 0.1
	rustdead.force_kill(attacker)
	await _wait_process_frames(2)
	var was_preroll_active := rustdead._ragdoll_preroll_active
	if not rustdead.begin_cinder_burn(attacker):
		_fail("Cinder burn should start on unconscious Rustdead")
		await _free_scene(scene)
		return
	if rustdead.life_state != NpcRules.LifeState.DEAD:
		_fail("Cinder burn should immediately mark Rustdead dead")
	if was_preroll_active and not rustdead._ragdoll_preroll_active and not rustdead._is_ragdoll_active:
		_fail("Cinder burn should not cancel pending downed ragdoll preroll")
	await _wait_until_ragdoll_active("Cinder burn preroll", rustdead, RAGDOLL_WAIT_FRAMES)
	if rustdead._ragdoll_preroll_active:
		_fail("Cinder-burned Rustdead preroll should finish")
	if not rustdead._is_ragdoll_active:
		_fail("Cinder-burned Rustdead should still enter ragdoll")
	await _free_scene(scene)


func _wait_until_ragdoll_active(label: String, actor: HumanoidCharacter, max_frames: int) -> void:
	for _index in range(max_frames):
		if actor == null or not is_instance_valid(actor):
			_fail("%s actor was freed before ragdoll activation" % label)
			return
		if actor._is_ragdoll_active:
			return
		await process_frame
	_fail("%s Rustdead ragdoll did not become active within %d frames" % [label, max_frames])


func _ray_hits_actor(actor: HumanoidCharacter) -> bool:
	var world := actor.get_world_3d()
	if world == null:
		return false
	var origin := actor.global_position + Vector3(0.0, 0.95, -3.0)
	var end := actor.global_position + Vector3(0.0, 0.95, 3.0)
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	var hit := world.direct_space_state.intersect_ray(query)
	return hit.get("collider", null) == actor


func _add_humanoid(scene: Node, actor_name: String, position: Vector3) -> HumanoidCharacter:
	var actor: HumanoidCharacter = FACTION_HUMANOID_SCRIPT.new()
	actor.name = actor_name
	actor.member_name = actor_name
	actor.position = position
	actor.faction_name = "Player"
	actor.visual_body_type = VISUAL_BODY_TYPE_MALE
	_add_basic_actor_children(actor, Color(0.42, 0.56, 0.75, 1.0))
	scene.add_child(actor)
	return actor


func _add_rustdead(scene: Node, actor_name: String, position: Vector3) -> HumanoidCharacter:
	var actor: HumanoidCharacter = RUSTDEAD_HUMANOID_SCRIPT.new()
	actor.name = actor_name
	actor.member_name = actor_name
	actor.position = position
	actor.faction_name = "Rustdead"
	actor.visual_body_type = VISUAL_BODY_TYPE_MALE
	_add_basic_actor_children(actor, Color(0.42, 0.08, 0.07, 1.0))
	scene.add_child(actor)
	return actor


func _add_basic_actor_children(actor: HumanoidCharacter, color: Color) -> void:
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.transform = Transform3D(Basis(), Vector3(0.0, 0.95, 0.0))
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = 0.45
	capsule_shape.height = 1.1
	collision.shape = capsule_shape
	actor.add_child(collision)

	var body := MeshInstance3D.new()
	body.name = "BodyMesh"
	body.transform = Transform3D(Basis(), Vector3(0.0, 0.95, 0.0))
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = 0.45
	body.mesh = capsule_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	body.material_override = material
	actor.add_child(body)


func _wait_process_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _free_scene(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
	await _wait_process_frames(3)


func _fail(message: String) -> void:
	_failures.append(message)
