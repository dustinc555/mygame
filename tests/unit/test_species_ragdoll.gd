extends GutTest

class QuietQuadBot extends QuadBotCharacter:
	func _process(_delta: float) -> void:
		pass
	func _physics_process(_delta: float) -> void:
		pass

class QuietHumanoid extends HumanoidCharacter:
	func _process(_delta: float) -> void:
		pass
	func _physics_process(_delta: float) -> void:
		pass

func _add_body(actor: WorldActor, height: float) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "BodyMesh"
	var capsule := CapsuleMesh.new()
	capsule.height = height
	capsule.radius = height * 0.22
	mesh.mesh = capsule
	mesh.position.y = height * 0.5
	actor.add_child(mesh)
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	var shape := CapsuleShape3D.new()
	shape.height = height
	shape.radius = capsule.radius
	collider.shape = shape
	collider.position.y = height * 0.5
	actor.add_child(collider)
	add_child_autofree(actor)

func after_each() -> void:
	await get_tree().process_frame

func test_quadbot_resolved_combat_damage_releases_offline_body_immediately() -> void:
	var actor := QuietQuadBot.new()
	_add_body(actor, 1.1)
	actor.handle_system_combat_resolution(null, "hit", "", PackedStringArray(), false, false, actor.max_hp + 1.0, 0.0, false)
	assert_eq(actor.life_state, NpcRules.LifeState.UNCONSCIOUS, "Hull failure takes the robot offline")
	assert_true(actor.is_ragdoll_active(), "The vitals transition must release the spider, not leave it standing")
	assert_true(actor.get_body_projection().is_physical_bone_ragdoll_active(), "Real native physics owns the downed body")

func test_quadbot_authoritative_death_releases_body() -> void:
	var actor := QuietQuadBot.new()
	_add_body(actor, 1.1)
	watch_signals(actor)
	actor.get_vitals().set_life_state(NpcRules.LifeState.DEAD)
	assert_true(actor.is_ragdoll_active(), "Death from vitals must use the same collapse path as debug kill")
	assert_signal_emit_count(actor, "died", 1)

func test_quadbot_offline_to_dead_does_not_restart_the_fall() -> void:
	var actor := QuietQuadBot.new()
	_add_body(actor, 1.1)
	actor.velocity = Vector3(0.8, 0.0, -0.3)
	actor.force_unconscious()
	var body := actor.get_body_projection() as QuadBotBodyProjection
	var root: PhysicalBone3D = body._ragdoll_physical_bones["Body"]
	assert_eq(root.linear_velocity, Vector3(0.8, 0.0, -0.3), "A moving robot retains its existing motion")
	root.linear_velocity = Vector3(0.1, -0.2, 0.3)
	var before := root.global_transform
	watch_signals(actor)
	actor.force_kill()
	assert_same(body._ragdoll_physical_bones["Body"], root)
	assert_true(root.global_transform.is_equal_approx(before))
	assert_eq(root.linear_velocity, Vector3(0.1, -0.2, 0.3))
	assert_signal_emit_count(actor, "died", 1, "Only the vitals observer emits death")

func test_quadbot_recovery_restores_collision_and_can_collapse_again() -> void:
	var actor := QuietQuadBot.new()
	_add_body(actor, 1.1)
	actor.force_unconscious()
	actor.get_vitals().set_life_state(NpcRules.LifeState.ALIVE)
	assert_false(actor.is_ragdoll_active())
	assert_false((actor.get_node("CollisionShape3D") as CollisionShape3D).disabled)
	actor.force_unconscious()
	assert_true(actor.is_ragdoll_active())

func test_quadbot_death_slumps_to_the_floor() -> void:
	var actor := QuietQuadBot.new()
	_add_body(actor, 1.1)
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 0.2, 10)
	collider.shape = box
	floor_body.add_child(collider)
	floor_body.position.y = -0.1
	add_child_autofree(floor_body)
	await get_tree().physics_frame
	actor.force_kill()
	var body := actor.get_body_projection() as QuadBotBodyProjection
	var root: PhysicalBone3D = body._ragdoll_physical_bones["Body"]
	var initial_height := root.global_position.y
	for frame in range(150):
		await get_tree().physics_frame
	assert_lt(root.global_position.y, initial_height - 0.35, "The spider's body visibly loses leg support")
	assert_gt(root.global_position.y, 0.1, "The body rests on the floor rather than falling through it")
	assert_lt(root.linear_velocity.length(), 0.15, "The corpse settles")

func test_puglin_ragdoll_preserves_world_bone_scale() -> void:
	var actor := QuietHumanoid.new()
	var appearance := CharacterAppearanceData.new()
	appearance.character_race = load("res://features/actors/resources/character_races/puglin.tres")
	appearance.body_archetype = load("res://features/actors/resources/character_body_archetypes/puglin.tres")
	actor.appearance_data = appearance
	_add_body(actor, 2.0)
	var body := actor.get_body_projection() as HumanoidBodyProjection
	body.play_clip("Idle", 0.0, true, 0.0)
	body.seek_clip("Idle", 0.35, true, 0.0)
	var skeleton := body.get_skeleton()
	var before := {}
	for bone_name in ["pelvis", "Head", "thigh_l", "calf_l"]:
		var transform := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone_name))
		before[bone_name] = transform.basis.get_scale()
	actor.force_kill()
	var displayed := {}
	var sample_pose := func() -> void:
		for bone_name in before:
			var transform := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone_name))
			displayed[bone_name] = transform.basis.get_scale()
	body._ragdoll_simulator.modification_processed.connect(sample_pose)
	for tick in range(8):
		await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.0).timeout
	body._ragdoll_simulator.modification_processed.disconnect(sample_pose)
	assert_eq(displayed.size(), before.size(), "Sample the modifier's displayed pose, not the restored animation pose")
	for bone_name in before:
		assert_almost_eq(displayed.get(bone_name, Vector3.ZERO), before[bone_name], Vector3.ONE * 0.01, bone_name + " keeps the fitted mesh size when physics takes ownership")
