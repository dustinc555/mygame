extends GutTest

class QuietHumanoid extends HumanoidCharacter:
	func _process(_delta: float) -> void:
		pass
	func _physics_process(_delta: float) -> void:
		pass

var actor: HumanoidCharacter
var body: HumanoidBodyProjection

func before_each() -> void:
	actor = QuietHumanoid.new()
	actor.member_name = "Ragdoll fixture"
	var mesh := MeshInstance3D.new()
	mesh.name = "BodyMesh"
	mesh.mesh = CapsuleMesh.new()
	mesh.position.y = 1.0
	actor.add_child(mesh)
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	collider.shape = CapsuleShape3D.new()
	collider.position.y = 1.0
	actor.add_child(collider)
	add_child_autofree(actor)
	body = actor.get_body_projection()

func after_each() -> void:
	# Animation imports enqueue their temporary source scenes for deletion.
	await get_tree().process_frame

func test_death_starts_physics_immediately_without_replacing_visible_pose() -> void:
	body.play_clip("Walk", 0.0, true, 0.0)
	body.seek_clip("Walk", 0.3, true, 0.0)
	var skeleton := body.get_skeleton()
	var pelvis := skeleton.find_bone("pelvis")
	var before := skeleton.get_bone_global_pose(pelvis)
	actor.force_kill()
	assert_true(body.is_ragdoll_active(), "Death releases directly into physics, not a death clip")
	assert_eq(body.get_current_clip(), "", "No death animation owns the body")
	assert_almost_eq(skeleton.get_bone_global_pose(pelvis).origin, before.origin, Vector3.ONE * 0.0001, "Handoff preserves the visible pose")
	for bone_name in body._ragdoll_physical_bones:
		var bone: PhysicalBone3D = body._ragdoll_physical_bones[bone_name]
		var expected := (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone_name)) * bone.body_offset).orthonormalized()
		assert_true(bone.global_transform.is_equal_approx(expected), bone_name + " starts in the displayed pose, including its collider offset")

func test_knees_and_elbows_hinge_on_the_skeleton_flexion_axis() -> void:
	assert_true(body._ensure_runtime_ragdoll())
	for bone_name in ["calf_l", "calf_r", "lowerarm_l", "lowerarm_r"]:
		var bone: PhysicalBone3D = body._ragdoll_physical_bones[bone_name]
		var joint_in_bone := bone.body_offset.basis * bone.joint_offset.basis
		assert_gt(joint_in_bone.z.normalized().dot(Vector3.RIGHT), 0.999, bone_name + " must bend around the rig's flexion X axis, not sideways")

func test_standing_collapse_keeps_the_spine_connected() -> void:
	body.play_clip("Idle", 0.0, true, 0.0)
	body.seek_clip("Idle", 0.35, true, 0.0)
	actor.force_kill()
	var maximum := 0.0
	for tick in range(45):
		await get_tree().physics_frame
		var pelvis: PhysicalBone3D = body._ragdoll_physical_bones["pelvis"]
		var head: PhysicalBone3D = body._ragdoll_physical_bones["Head"]
		maximum = maxf(maximum, pelvis.global_position.distance_to(head.global_position))
	assert_lt(maximum, 1.2, "An out-of-rest animation pose must not explosively stretch the spine")

func test_idle_collapse_lands_lengthwise_instead_of_folding_onto_its_heels() -> void:
	await _assert_lengthwise_collapse("Idle")

func test_combat_pose_collapse_lands_lengthwise_instead_of_folding_onto_its_heels() -> void:
	await _assert_lengthwise_collapse("Sword_Idle")

func test_walk_pose_collapse_lands_lengthwise_instead_of_folding_onto_its_heels() -> void:
	await _assert_lengthwise_collapse("Walk")

func _assert_lengthwise_collapse(clip: String) -> void:
	body.play_clip(clip, 0.0, true, 0.0)
	body.seek_clip(clip, 0.35, true, 0.0)
	var skeleton := body.get_skeleton()
	var foot_height := INF
	for side in ["l", "r"]:
		var ankle := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("foot_" + side))
		foot_height = minf(foot_height, ankle.origin.y)
	var ground_y := foot_height - float(body.get_ragdoll_profile().foot_radius)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12.0, 0.2, 12.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = ground_y - 0.1
	add_child_autofree(floor_body)
	await get_tree().physics_frame
	actor.force_kill()
	for tick in range(240):
		await get_tree().physics_frame
	var head: PhysicalBone3D = body._ragdoll_physical_bones["Head"]
	var pelvis: PhysicalBone3D = body._ragdoll_physical_bones["pelvis"]
	var torso_direction := Vector2(head.global_position.x - pelvis.global_position.x, head.global_position.z - pelvis.global_position.z).normalized()
	assert_lt(head.global_position.y - ground_y, 0.35, "The body actually falls, rather than balancing in a crouch")
	for side in ["l", "r"]:
		var foot: PhysicalBone3D = body._ragdoll_physical_bones["foot_" + side]
		var leg := Vector2(foot.global_position.x - pelvis.global_position.x, foot.global_position.z - pelvis.global_position.z)
		assert_lt(leg.dot(torso_direction), -0.2, clip + " foot " + side + " stays beyond the hips, not folded beside the torso")

func test_foot_colliders_follow_toes_instead_of_continuing_the_shin() -> void:
	assert_true(body._ensure_runtime_ragdoll())
	for side in ["l", "r"]:
		var bone: PhysicalBone3D = body._ragdoll_physical_bones["foot_" + side]
		assert_gt(bone.body_offset.basis.y.normalized().dot(Vector3.UP), 0.999, "Foot follows its authored toe even though toes are not physical bones")
	var chest := body._get_ragdoll_child_vector(body.get_ragdoll_profile(), body.get_skeleton().find_bone("spine_03"))
	assert_gt(chest.y, 0.2, "Chest collider reaches toward the neck rather than using a short fallback")

func test_bent_knee_cannot_fold_past_its_anatomical_limit() -> void:
	body.stop_clip(true)
	var skeleton := body.get_skeleton()
	skeleton.reset_bone_poses()
	var index := skeleton.find_bone("calf_l")
	skeleton.set_bone_pose_rotation(index, skeleton.get_bone_rest(index).basis.get_rotation_quaternion() * Quaternion(Vector3.RIGHT, deg_to_rad(100.0)))
	var profile := HumanoidRagdollProfile.new()
	# This test exercises an authored full-flexion override, independently of
	# the more restrained default passive-collapse range.
	profile.knee_flexion_degrees = 140.0
	profile.gravity_scale = 0.0
	body.ragdoll_profile = profile
	actor.force_kill()
	var calf: PhysicalBone3D = body._ragdoll_physical_bones["calf_l"]
	var thigh: PhysicalBone3D = body._ragdoll_physical_bones["thigh_l"]
	var maximum := 0.0
	for tick in range(45):
		var axis := (calf.global_basis * calf.body_offset.basis.inverse().x).normalized()
		PhysicsServer3D.body_apply_torque_impulse(calf.get_rid(), axis * 0.12)
		await get_tree().physics_frame
		var parent_basis := thigh.global_basis * thigh.body_offset.basis.inverse()
		var child_basis := calf.global_basis * calf.body_offset.basis.inverse()
		var relative := parent_basis.inverse() * child_basis
		var angle := rad_to_deg(atan2(relative.y.z, relative.y.y))
		maximum = maxf(maximum, angle)
	assert_gt(maximum, 130.0, "A knee starting bent can still reach its normal flexion range")
	assert_lt(maximum, 160.0, "Starting bent must not redefine the knee's straight/fully-folded limits")

func test_knees_and_elbows_resist_backwards_bending() -> void:
	body.stop_clip(true)
	var skeleton := body.get_skeleton()
	skeleton.reset_bone_poses()
	var profile := HumanoidRagdollProfile.new()
	profile.gravity_scale = 0.0
	body.ragdoll_profile = profile
	actor.force_kill()
	var pairs := {"calf_l": "thigh_l", "calf_r": "thigh_r", "lowerarm_l": "upperarm_l", "lowerarm_r": "upperarm_r"}
	var minimum := {}
	for name in pairs:
		minimum[name] = 0.0
	for tick in range(45):
		for name in pairs:
			var bone: PhysicalBone3D = body._ragdoll_physical_bones[name]
			# A fitted visual scale must not multiply the applied physical load.
			var axis := (bone.global_basis * bone.body_offset.basis.inverse().x).normalized()
			PhysicsServer3D.body_apply_torque_impulse(bone.get_rid(), axis * -0.12)
		await get_tree().physics_frame
		for name in pairs:
			var bone: PhysicalBone3D = body._ragdoll_physical_bones[name]
			var parent: PhysicalBone3D = body._ragdoll_physical_bones[pairs[name]]
			var rest := skeleton.get_bone_rest(skeleton.find_bone(name)).basis
			var parent_basis := parent.global_basis * parent.body_offset.basis.inverse()
			var relative := (parent_basis * rest).inverse() * bone.global_basis * bone.body_offset.basis.inverse()
			minimum[name] = minf(minimum[name], rad_to_deg(atan2(relative.y.z, relative.y.y)))
	for name in pairs:
		assert_lt(float(minimum[name]), -1.0, name + " was actually loaded against its extension stop")
		assert_gt(float(minimum[name]), -15.0, name + " must resist backwards bending under torque")

func test_collapse_keeps_existing_motion_without_an_upward_velocity_override() -> void:
	actor.velocity = Vector3(1.2, 0.0, -0.7)
	actor.force_kill()
	for bone_name in body._ragdoll_physical_bones:
		var bone: PhysicalBone3D = body._ragdoll_physical_bones[bone_name]
		assert_almost_eq(bone.linear_velocity, Vector3(1.2, 0.0, -0.7), Vector3.ONE * 0.001, bone_name + " inherits movement instead of stopping dead")
		assert_eq(bone.get("upward_velocity_suppression_frames"), 0, "Ground contact must be free to lift a limb; do not release trapped motion later")

func test_hip_resists_excessive_backwards_extension() -> void:
	body.stop_clip(true)
	var skeleton := body.get_skeleton()
	skeleton.reset_bone_poses()
	var profile := HumanoidRagdollProfile.new()
	profile.gravity_scale = 0.0
	body.ragdoll_profile = profile
	actor.force_kill()
	var thigh: PhysicalBone3D = body._ragdoll_physical_bones["thigh_l"]
	var pelvis: PhysicalBone3D = body._ragdoll_physical_bones["pelvis"]
	var rest := skeleton.get_bone_rest(skeleton.find_bone("thigh_l")).basis
	var maximum := 0.0
	for tick in range(45):
		var axis := (thigh.global_basis * thigh.body_offset.basis.inverse().x).normalized()
		PhysicsServer3D.body_apply_torque_impulse(thigh.get_rid(), axis * 0.12)
		await get_tree().physics_frame
		var parent_basis := pelvis.global_basis * pelvis.body_offset.basis.inverse()
		var relative := (parent_basis * rest).inverse() * thigh.global_basis * thigh.body_offset.basis.inverse()
		maximum = maxf(maximum, rad_to_deg(atan2(relative.y.z, relative.y.y)))
	assert_lt(maximum, 35.0, "The thigh stops behind the hip instead of hyperextending under load")

func test_repeated_downed_entry_preserves_body_pose_and_momentum() -> void:
	actor.force_unconscious()
	var pelvis: PhysicalBone3D = body._ragdoll_physical_bones["pelvis"]
	pelvis.linear_velocity = Vector3(0.8, -0.4, 0.2)
	var before := pelvis.global_transform
	assert_true(body.enter_downed_visuals(true))
	actor.force_kill()
	assert_same(body._ragdoll_physical_bones["pelvis"], pelvis)
	assert_true(pelvis.global_transform.is_equal_approx(before))
	assert_eq(pelvis.linear_velocity, Vector3(0.8, -0.4, 0.2), "Downed-to-dead is not another physics handoff")

func test_recovery_and_second_collapse_reuse_the_anatomical_rig() -> void:
	actor.force_unconscious()
	var pelvis: PhysicalBone3D = body._ragdoll_physical_bones["pelvis"]
	actor.get_vitals().set_life_state(NpcRules.LifeState.ALIVE)
	assert_false(body.is_ragdoll_active(), "Recovery releases physical pose ownership")
	assert_false(body._ragdoll_simulator.is_simulating_physics())
	body.play_clip("Sword_Idle", 0.0, true, 0.0)
	body.seek_clip("Sword_Idle", 0.35, true, 0.0)
	actor.force_kill()
	assert_true(body.is_ragdoll_active())
	assert_same(body._ragdoll_physical_bones["pelvis"], pelvis, "A second collapse keeps rest-bound joint frames")
	assert_eq(pelvis.linear_velocity, Vector3.ZERO, "Stopped simulation contributes no stale velocity")

func test_profile_controls_reach_the_native_joint_and_contact_settings() -> void:
	var shared = load("res://features/actors/resources/characters/humanoid_ragdoll_profile.tres")
	assert_same(body.get_ragdoll_profile(), shared, "Default humanoids consume the Inspector resource")
	var custom = shared.duplicate(true)
	custom.knee_flexion_degrees = 120.0
	custom.hip_extension_degrees = 15.0
	custom.friction = 0.7
	custom.angular_limit_error_reduction = 0.12
	custom.angular_limit_softness = 0.8
	body.ragdoll_profile = custom
	actor.force_kill()
	var calf: PhysicalBone3D = body._ragdoll_physical_bones["calf_l"]
	var thigh: PhysicalBone3D = body._ragdoll_physical_bones["thigh_l"]
	assert_almost_eq(float(calf.get("joint_constraints/angular_limit_lower")), -120.0, 0.001)
	assert_almost_eq(float(thigh.get("joint_constraints/x/angular_limit_lower")), -15.0, 0.001)
	assert_almost_eq(calf.friction, 0.7, 0.001)
	assert_almost_eq(float(thigh.get("joint_constraints/x/erp")), 0.12, 0.001)
	assert_almost_eq(float(thigh.get("joint_constraints/x/angular_limit_softness")), 0.8, 0.001)
	assert_eq(shared.knee_flexion_degrees, 60.0, "Per-body overrides do not mutate the shared design")
