extends "res://tests/validation/test_case.gd"

const FACTION_HUMANOID_SCRIPT := preload("res://features/actors/projection/humanoid/faction_humanoid.gd")
const RUSTDEAD_HUMANOID_SCRIPT := preload("res://features/actors/projection/rustdead/rustdead_humanoid_character.gd")

const VISUAL_BODY_TYPE_MALE := 2


var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _validate_registered_medical_commands()
	await _validate_repeated_lethal_vitals_preserve_ragdoll()
	await _validate_cinder_burn_preserves_ragdoll()
	if _failures.is_empty():
		print("RUSTDEAD_DOWNED_RAGDOLL_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("RUSTDEAD_DOWNED_RAGDOLL_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_registered_medical_commands() -> void:
	var before := _failures.size()
	var scene := Node3D.new()
	root.add_child(scene)
	_add_controllers_and_floor(scene)
	var bridge := scene.get_node("GecsWorldController") as GecsWorldController
	bridge.set_process(false)
	var actor := RustdeadHumanoidCharacter.new()
	actor.stable_id = "rustdead.medical.boundary"
	scene.add_child(actor)
	actor.set_physics_process(false)
	bridge.upsert_population_record({"actor_id": actor.stable_id, "stable_id": actor.stable_id, "realization_state": "ledger"})
	bridge.register_actor(actor)
	var registered_component = bridge.get_actor_entity(actor).get_component(CGameActorVitals)
	actor.get_vitals().set_bleed_rate(1.25)
	if registered_component.bleed_rate != 1.25:
		_fail("Registration must bind medical commands before the first GECS tick")
	actor.get_vitals().set_bleed_rate(0.0)
	bridge.world.process(0.05)
	var component = bridge.get_actor_entity(actor).get_component(CGameActorVitals)
	actor.force_kill()
	print("RUSTDEAD_COMMAND_IMMEDIATE actor=%s component=%s actor_hp=%s component_hp=%s" % [actor.life_state, component.life_state, actor.hp, component.hp])
	if component.life_state != actor.life_state or component.hp != actor.hp or component.blood != actor.blood:
		_fail("Registered force_kill must update GECS before returning, not only its projection")
	# Real fixed ticks exceed an ordinary human's dying countdown. A single
	# oversized delta would be clamped by the fixed-step catch-up budget.
	for _tick in range(1200):
		bridge.world.process(0.05)
	if not actor.is_downed_state() or component.life_state == NpcRules.LifeState.DEAD:
		_fail("Lethal non-fire wounds must remain downed across 1200 fixed GECS ticks")
	# Ordinary humanoids use this same public boundary. A medical command must
	# preserve a newer combat wound that has not yet reached the projection.
	var human := WorldActor.new()
	human.stable_id = "human.medical.boundary"
	scene.add_child(human)
	human.set_physics_process(false)
	bridge.register_actor(human)
	bridge.world.process(0.05)
	var human_component = bridge.get_actor_entity(human).get_component(CGameActorVitals)
	human_component.open_cut_damage = 13.0
	VitalsStateMachine.recalculate(human_component, 1.0)
	human.get_vitals().set_bleed_rate(2.0)
	if human_component.bleed_rate != 2.0 or human_component.open_cut_damage != 13.0:
		_fail("Medical command must write through without overwriting newer GECS wounds")
	human.get_vitals().set_open_cut_damage(0.0)
	human.get_vitals().set_bleed_rate(0.0)
	human.get_vitals().set_bleed_burst_rate(0.0)
	bridge.world.process(0.05)
	if human_component.open_cut_damage != 0.0 or human_component.bleed_rate != 0.0:
		_fail("Ordinary jail/bandage wound stabilization commands must survive GECS sync")
	human.force_kill()
	for _tick in range(20):
		bridge.world.process(0.05)
	if human.life_state != NpcRules.LifeState.DEAD or human_component.life_state != NpcRules.LifeState.DEAD:
		_fail("Ordinary humanoid force_kill must remain authoritatively DEAD")
	# Keep the old component alive deliberately: a weak handle can remain valid
	# after load while no longer being the component that owns this actor.
	var warm_path := "user://rustdead_medical_warm_boundary.tres"
	if not bridge.save_gecs_world(warm_path):
		_fail("Medical reload boundary must save the actual registered world")
	else:
		actor.get_vitals().set_bleed_rate(7.0)
		# Names/paths are projection details, not the loaded actor's identity.
		actor.name = "RetainedRustdeadAfterSave"
		var omitted := WorldActor.new()
		omitted.stable_id = "human.omitted.from.medical.snapshot"
		scene.add_child(omitted)
		omitted.set_physics_process(false)
		bridge.register_actor(omitted)
		var omitted_component = bridge.get_actor_entity(omitted).get_component(CGameActorVitals)
		var observer_rates: Array[float] = []
		bridge.world_reindexed.connect(func():
			actor.get_vitals().set_bleed_rate(3.0)
			observer_rates.append(bridge.get_actor_entity(actor).get_component(CGameActorVitals).bleed_rate)
		, CONNECT_ONE_SHOT)
		if not bridge.load_gecs_world(warm_path):
			_fail("Medical reload boundary must replace the registered world")
		else:
			var loaded_component = bridge.get_actor_entity(actor).get_component(CGameActorVitals)
			if loaded_component == component:
				_fail("Medical reload fixture must replace component identity")
			if observer_rates != [3.0]:
				_fail("Loaded medical authority must be bound before world-reindexed observers run")
			actor.get_vitals().set_bleed_rate(2.0)
			if loaded_component.bleed_rate != 2.0:
				_fail("Medical command immediately after load must update the loaded component before any tick")
			if component.bleed_rate != 7.0:
				_fail("Medical command after load must not mutate the retired component")
			actor.get_vitals().set_bleed_rate(0.0)
			bridge.world.process(0.05)
			if bridge.get_actor_entity(omitted) != null:
				_fail("Medical reload fixture must omit the later registered actor")
			omitted.force_kill()
			if omitted_component.life_state != NpcRules.LifeState.ALIVE:
				_fail("An actor absent from the loaded snapshot must release its retired medical authority")
		omitted.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(warm_path))
	var actor_id := actor.stable_id
	bridge.unregister_actor(actor)
	actor.queue_free()
	await process_frame
	for _tick in range(20):
		bridge.world.process(0.05)
	var record := bridge.get_population_record(actor_id)
	if not VitalsCapability.is_life_state_downed(int(record.get("life_state", -1))):
		_fail("Derealized unburned Rustdead must remain downed in the population ledger")
	var save_path := "user://rustdead_medical_boundary.tres"
	if not bridge.save_gecs_world(save_path):
		_fail("Rustdead command regression must save the actual GECS world")
	await _free_scene(scene)
	var loaded_scene := Node3D.new()
	root.add_child(loaded_scene)
	_add_controllers_and_floor(loaded_scene)
	var loaded := loaded_scene.get_node("GecsWorldController") as GecsWorldController
	loaded.set_process(false)
	if not loaded.load_gecs_world(save_path):
		_fail("Rustdead command regression must reload the actual saved GECS world")
	for _tick in range(20):
		loaded.world.process(0.05)
	var restored := RustdeadHumanoidCharacter.new()
	restored.stable_id = actor_id
	loaded_scene.add_child(restored)
	restored.set_physics_process(false)
	loaded.register_actor(restored)
	for _tick in range(20):
		loaded.world.process(0.05)
	if not restored.is_downed_state() or not restored.can_be_destroyed_by_cinder():
		_fail("Saved unburned Rustdead must re-realize downed and remain burnable")
	if not restored.begin_cinder_burn():
		_fail("Restored registered Rustdead must accept authoritative fire destruction")
	else:
		for _tick in range(20):
			loaded.world.process(0.05)
		if restored.life_state != NpcRules.LifeState.DEAD:
			_fail("Fire destruction must remain DEAD across fixed GECS ticks")
		loaded.unregister_actor(restored)
		var burned := loaded.get_population_record(actor_id)
		if int(burned.get("life_state", -1)) != NpcRules.LifeState.DEAD:
			_fail("Fire destruction must persist after unregister")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	await _free_scene(loaded_scene)
	print("RUSTDEAD_MEDICAL_BOUNDARY_EXECUTED failures=%d nonfire_fixed_ticks=1200" % (_failures.size() - before))


func _validate_repeated_lethal_vitals_preserve_ragdoll() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	_add_controllers_and_floor(scene)
	var attacker := _add_humanoid(scene, "Attacker", Vector3(-1.5, 0.0, 0.0))
	var rustdead := _add_rustdead(scene, "RepeatedVitalsRustdead", Vector3.ZERO)
	await _wait_process_frames(8)
	rustdead.force_kill(attacker)
	await process_frame
	if not rustdead.is_downed_state():
		_fail("Rustdead force_kill should leave actor downed, got %s" % rustdead.get_life_state_label())
		await _free_scene(scene)
		return
	var body := rustdead.get_body_projection()
	if not body.is_ragdoll_active():
		_fail("Downed Rustdead should start ragdoll immediately")
		await _free_scene(scene)
		return
	await physics_frame
	if not _ray_hits_actor(rustdead):
		_fail("Player picking must still select the falling Rustdead")
	var pelvis: PhysicalBone3D = body._ragdoll_physical_bones["pelvis"]
	for _index in range(16):
		var before := pelvis.global_transform
		var velocity_before := pelvis.linear_velocity
		rustdead._recalculate_vitals()
		if body._ragdoll_physical_bones["pelvis"] != pelvis or not pelvis.global_transform.is_equal_approx(before) or not pelvis.linear_velocity.is_equal_approx(velocity_before):
			_fail("Repeated lethal vitals must not restart or kick the existing ragdoll")
		await process_frame
	if not rustdead.get_body_projection().is_ragdoll_active():
		_fail("Repeated lethal Rustdead vitals should not cancel active ragdoll")
	if not rustdead.is_downed_state():
		_fail("Unburned Rustdead should remain downed after lethal vitals, got %s" % rustdead.get_life_state_label())
	if not rustdead.can_be_destroyed_by_cinder():
		_fail("Downed unburned Rustdead should remain available for Cinder Flask destruction")
	print("RUSTDEAD_IMMEDIATE_RAGDOLL_PICK_AND_REPEATED_VITALS_EXECUTED")
	await _free_scene(scene)


func _validate_cinder_burn_preserves_ragdoll() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	_add_controllers_and_floor(scene)
	var attacker := _add_humanoid(scene, "CinderAttacker", Vector3(-1.5, 0.0, 0.0))
	var rustdead := _add_rustdead(scene, "CinderRagdollRustdead", Vector3.ZERO)
	await _wait_process_frames(8)
	rustdead.cinder_burn_duration_seconds = 0.1
	rustdead.force_kill(attacker)
	await _wait_process_frames(2)
	var body := rustdead.get_body_projection()
	if not body.is_ragdoll_active():
		_fail("Rustdead must already be physically downed before fire destruction")
		await _free_scene(scene)
		return
	var pelvis: PhysicalBone3D = body._ragdoll_physical_bones["pelvis"]
	var before := pelvis.global_transform
	var velocity_before := pelvis.linear_velocity
	if not rustdead.has_method("begin_cinder_burn"):
		_fail("Production Rustdead must implement the advertised cinder action")
		await _free_scene(scene)
		return
	if not rustdead.call("begin_cinder_burn", attacker):
		_fail("Cinder burn should start on unconscious Rustdead")
		await _free_scene(scene)
		return
	if rustdead.life_state != NpcRules.LifeState.DEAD:
		_fail("Cinder burn should immediately mark Rustdead dead")
	if body._ragdoll_physical_bones["pelvis"] != pelvis or not pelvis.global_transform.is_equal_approx(before) or not pelvis.linear_velocity.is_equal_approx(velocity_before):
		_fail("Fire destruction must preserve physical pose and momentum")
	if not rustdead.get_body_projection().is_ragdoll_active():
		_fail("Cinder-burned Rustdead should still enter ragdoll")
	print("RUSTDEAD_CINDER_PRESERVES_RAGDOLL_EXECUTED")
	await _free_scene(scene)


func _ray_hits_actor(actor: HumanoidCharacter) -> bool:
	# Downed physical collision belongs to ragdoll bones, not the standing
	# capsule. Exercise the player's real ray + actor-pick resolution instead
	# of requiring that disabled capsule to remain a physical obstacle.
	var camera := Camera3D.new()
	actor.get_parent().add_child(camera)
	var torso: PhysicalBone3D = actor.get_body_projection()._ragdoll_physical_bones["spine_03"]
	var anchor := torso.global_position
	camera.global_position = anchor + Vector3(0.0, 0.0, -3.0)
	camera.look_at(anchor)
	camera.make_current()
	var interaction := WorldInteractionController.new()
	actor.get_parent().add_child(interaction)
	interaction.camera = camera
	var hit := interaction._raycast_target_from_screen(camera.unproject_position(anchor))
	var selected: bool = hit.get("collider", null) == actor
	interaction.free()
	camera.free()
	return selected


func _add_humanoid(scene: Node, actor_name: String, position: Vector3) -> HumanoidCharacter:
	var actor: HumanoidCharacter = FACTION_HUMANOID_SCRIPT.new()
	actor.name = actor_name
	actor.stable_id = actor_name
	actor.member_name = actor_name
	actor.position = position
	actor.faction_name = "Player"
	actor.appearance_data = CharacterAppearanceData.new()
	actor.appearance_data.visual_body_type = VISUAL_BODY_TYPE_MALE
	_add_basic_actor_children(actor, Color(0.42, 0.56, 0.75, 1.0))
	scene.add_child(actor)
	scene.get_node("GecsWorldController").register_actor(actor)
	return actor


func _add_rustdead(scene: Node, actor_name: String, position: Vector3) -> HumanoidCharacter:
	var actor: HumanoidCharacter = RUSTDEAD_HUMANOID_SCRIPT.new()
	actor.name = actor_name
	actor.stable_id = actor_name
	actor.member_name = actor_name
	actor.position = position
	actor.faction_name = "Rustdead"
	actor.appearance_data = CharacterAppearanceData.new()
	actor.appearance_data.visual_body_type = VISUAL_BODY_TYPE_MALE
	_add_basic_actor_children(actor, Color(0.42, 0.08, 0.07, 1.0))
	scene.add_child(actor)
	scene.get_node("GecsWorldController").register_actor(actor)
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


func _add_controllers_and_floor(scene: Node3D) -> void:
	var gecs := GecsWorldController.new()
	gecs.name = "GecsWorldController"
	scene.add_child(gecs)
	var context := BootstrapContext.new(scene)
	context.register(gecs.SERVICE_ID, gecs)
	gecs.initialize(context)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(30.0, 0.2, 30.0)
	collision.shape = shape
	collision.position.y = -0.1
	floor_body.add_child(collision)
	scene.add_child(floor_body)


func _wait_process_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _free_scene(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
	await _wait_process_frames(3)


func _fail(message: String) -> void:
	_failures.append(message)
