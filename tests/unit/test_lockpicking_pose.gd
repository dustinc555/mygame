extends GutTest

const PICK := preload("res://features/inventory/resources/items/lockpick.tres")
const SWORD := preload("res://features/inventory/resources/items/steel_sword.tres")
const SHIELD := preload("res://features/inventory/resources/items/round_shield.tres")
var actor: HumanoidCharacter
var body: HumanoidBodyProjection

func before_each() -> void:
	actor = HumanoidCharacter.new()
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.appearance_data = CharacterAppearanceData.new()
	actor.appearance_data.body_archetype = load("res://features/actors/resources/character_body_archetypes/human_male.tres")
	actor.appearance_data.visual_body_type = 2
	actor.starting_equipment.assign([SWORD, SHIELD])
	var placeholder := MeshInstance3D.new()
	placeholder.name = "BodyMesh"
	placeholder.mesh = CapsuleMesh.new()
	actor.add_child(placeholder)
	add_child_autofree(actor)
	await get_tree().process_frame
	body = actor.get_body_projection()

func start_work() -> void:
	actor.set_lockpick_work_visual(true, Vector3(0, 1.35, -0.55), 0.25, PICK)


func advance_work(seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.0:
		var step := minf(remaining, 1.0 / 30.0)
		actor._advance_lockpick_rise(step)
		actor._update_locomotion_animation(step)
		body.get_primary_animation_player().advance(step)
		remaining -= step


func test_work_remains_kneeling_across_attempt_updates() -> void:
	start_work()
	advance_work(1.6)
	var skeleton := body.get_skeleton()
	var pelvis := skeleton.find_bone("pelvis")
	var kneeling_height := skeleton.get_bone_global_pose(pelvis).origin.y
	var highest := kneeling_height
	for attempt in range(3):
		# Pass/fail UI updates must not restart kneeling or end the work loop.
		actor.set_lockpick_work_visual(true, Vector3(0, 1.35, -0.55), attempt / 3.0, PICK, 0.0)
		for frame in range(180):
			advance_work(1.0 / 30.0)
			highest = maxf(highest, skeleton.get_bone_global_pose(pelvis).origin.y)
	assert_lt(highest - kneeling_height, 0.08, "The pelvis stays kneeling through multiple full repair-clip durations and attempt changes")

func test_work_uses_existing_fixing_clip_without_one_arm_ik() -> void:
	start_work()
	actor._update_locomotion_animation(0.1)
	assert_eq(body.get_current_clip(), "Kneeling_Work_Enter")
	assert_null(body.get_skeleton().get_node_or_null("LockpickArmReach"))
	assert_null(body.get_skeleton().get_node_or_null("LockpickWristAim"))

func test_fixing_animation_moves_both_hands_for_both_body_archetypes() -> void:
	for appearance in [{"body": "human_male", "visual": 2}, {"body": "human_female", "visual": 3}]:
		actor.appearance_data.body_archetype = load("res://features/actors/resources/character_body_archetypes/%s.tres" % appearance.body)
		actor.appearance_data.visual_body_type = appearance.visual
		body.rebuild_visual_for_appearance()
		await get_tree().process_frame
		start_work()
		advance_work(1.6)
		assert_eq(body.get_current_clip(), "Kneeling_Work_Loop")
		# Disabled fixture actors need the normal blend clock advanced explicitly;
		# seeking alone changes clip time but keeps its initial zero blend weight.
		body.get_primary_animation_player().advance(HumanoidBodyProjection.DEFAULT_MOVE_BLEND_SECONDS + 0.01)
		var skeleton := body.get_skeleton()
		for bone_name in ["hand_r", "hand_l"]:
			var bone := skeleton.find_bone(bone_name)
			body.seek_clip("Kneeling_Work_Loop", 0.1)
			var first := skeleton.get_bone_global_pose(bone)
			var moved := false
			for sample in range(1, 12):
				body.seek_clip("Kneeling_Work_Loop", body.clip_length("Kneeling_Work_Loop") * sample / 12.0)
				moved = moved or not skeleton.get_bone_global_pose(bone).is_equal_approx(first)
			assert_true(moved, "%s %s moves across the existing repair clip" % [appearance.body, bone_name])
		actor.set_lockpick_work_visual(false, Vector3.ZERO, 0.0, null)

func test_work_hides_equipment_and_restores_it_without_changing_slots() -> void:
	start_work()
	var pose: Node = body._lockpick_pose
	assert_true(pose._prop.visible)
	assert_eq(pose._hidden.size(), 2)
	for record in pose._hidden:
		assert_false(record.node.get_ref().visible)
	assert_same(actor.get_equipped_item("weapon"), SWORD)
	assert_same(actor.get_equipped_item("offhand"), SHIELD)
	var hidden: Array = pose._hidden.duplicate()
	actor.set_lockpick_work_visual(false, Vector3.ZERO, 0.0, null)
	assert_null(pose._prop)
	assert_false(pose.is_processing())
	for record in hidden:
		assert_eq(record.node.get_ref().visible, record.visible)
	assert_same(actor.get_equipped_item("weapon"), SWORD)
	assert_same(actor.get_equipped_item("offhand"), SHIELD)

func test_stop_rises_once_before_idle() -> void:
	start_work()
	advance_work(1.6)
	var skeleton := body.get_skeleton()
	var pelvis := skeleton.find_bone("pelvis")
	var low := skeleton.get_bone_global_pose(pelvis).origin.y
	actor.set_lockpick_work_visual(false, Vector3.ZERO, 0.0, null)
	actor._update_locomotion_animation(0.01)
	assert_eq(body.get_current_clip(), "Kneeling_Work_Exit", "Finishing or cancelling work starts the authored rise, not idle")
	advance_work(0.6)
	assert_gt(skeleton.get_bone_global_pose(pelvis).origin.y, low + 0.1, "Rise physically lifts the pelvis")
	advance_work(1.0)
	assert_ne(body.get_current_clip(), "Kneeling_Work_Exit", "Rise completes once and releases ordinary animation")

func test_move_waits_for_rise_without_losing_the_new_order() -> void:
	start_work()
	advance_work(1.6)
	actor.set_lockpick_work_visual(false, Vector3.ZERO, 0.0, null)
	actor.set_move_target(Vector3(8, 0, 0))
	var start := actor.global_position
	actor.velocity = Vector3(2, 0, 0)
	actor.process_world_actor_movement(0.1)
	assert_eq(actor.global_position, start, "Do not slide away while kneeling")
	assert_eq(actor.velocity, Vector3.ZERO)
	assert_true(actor.has_move_target(), "The replacement order is retained")
	assert_false(actor._advance_lockpick_rise(2.0), "Physics releases movement without needing rendered frames")
	assert_true(actor.has_move_target())

func test_combat_preempts_rise_without_stomping_attack() -> void:
	start_work()
	advance_work(1.6)
	actor.set_lockpick_work_visual(false, Vector3.ZERO, 0.0, null)
	actor._system_combat_action_active = true
	body.play_clip("Sword_Light_A", 0.0, true)
	assert_false(actor._advance_lockpick_rise(0.01))
	actor._update_locomotion_animation(0.01)
	assert_eq(body.get_current_clip(), "Sword_Light_A")
	assert_eq(actor._lockpick_rise_remaining, 0.0, "No stale movement hold after combat takes over")

func test_cancel_during_descent_reverses_only_the_entered_motion() -> void:
	start_work()
	advance_work(0.35)
	var skeleton := body.get_skeleton()
	var pelvis := skeleton.find_bone("pelvis")
	var before := skeleton.get_bone_global_pose(pelvis).origin.y
	actor.set_lockpick_work_visual(false, Vector3.ZERO, 0.0, null)
	assert_lt(body.get_primary_animation_player().get_playing_speed(), 0.0)
	advance_work(0.2)
	assert_gt(skeleton.get_bone_global_pose(pelvis).origin.y, before, "Early cancellation rises rather than dropping into the full kneeling exit")
	advance_work(0.4)
	assert_eq(actor._lockpick_rise_remaining, 0.0)
	assert_ne(body.get_current_clip(), "Kneeling_Work_Enter")

func test_resume_during_rise_restores_work_and_clears_movement_hold() -> void:
	start_work()
	advance_work(1.6)
	actor.set_lockpick_work_visual(false, Vector3.ZERO, 0.0, null)
	advance_work(0.2)
	start_work()
	advance_work(0.4)
	assert_eq(actor._lockpick_rise_remaining, 0.0)
	assert_eq(body.get_current_clip(), "Kneeling_Work_Loop")
	assert_true(body._lockpick_pose._prop.visible)

func test_body_rebuild_releases_stale_rise_hold() -> void:
	start_work()
	advance_work(1.6)
	actor.set_lockpick_work_visual(false, Vector3.ZERO, 0.0, null)
	body.rebuild_visual_for_appearance()
	await get_tree().process_frame
	assert_false(actor._advance_lockpick_rise(0.01))
	assert_eq(actor._lockpick_rise_remaining, 0.0)

func test_loop_seam_preserves_pose_for_both_archetypes() -> void:
	for appearance in [{"body": "human_male", "visual": 2}, {"body": "human_female", "visual": 3}]:
		actor.appearance_data.body_archetype = load("res://features/actors/resources/character_body_archetypes/%s.tres" % appearance.body)
		actor.appearance_data.visual_body_type = appearance.visual
		body.rebuild_visual_for_appearance()
		await get_tree().process_frame
		start_work()
		advance_work(1.6)
		var skeleton := body.get_skeleton()
		var clip := body.get_primary_animation_player().get_animation("Kneeling_Work_Loop")
		body.seek_clip("Kneeling_Work_Loop", clip.length - 0.001)
		var before: Array[Transform3D] = []
		for bone in range(skeleton.get_bone_count()):
			before.append(skeleton.get_bone_global_pose(bone))
		body.seek_clip("Kneeling_Work_Loop", 0.0)
		var max_distance := 0.0
		var max_angle := 0.0
		for bone in range(skeleton.get_bone_count()):
			var after := skeleton.get_bone_global_pose(bone)
			max_distance = maxf(max_distance, before[bone].origin.distance_to(after.origin))
			max_angle = maxf(max_angle, before[bone].basis.get_rotation_quaternion().angle_to(after.basis.get_rotation_quaternion()))
		assert_lt(max_distance, 0.005, "%s loop has no positional snap" % appearance.body)
		assert_lt(max_angle, 0.02, "%s loop has no angular snap" % appearance.body)
		actor.set_lockpick_work_visual(false, Vector3.ZERO, 0.0, null)

func test_equipment_refresh_and_body_rebuild_do_not_leave_stale_work_props() -> void:
	start_work()
	body.refresh_bone_equipment_slots(["weapon"])
	await get_tree().process_frame
	var sword_visual := body.get_skeleton().find_child("EquippedWeaponVisual", true, false) as Node3D
	assert_not_null(sword_visual)
	assert_false(sword_visual.visible, "Replacement held gear stays hidden while picking")
	var old_prop: WeakRef = weakref(body._lockpick_pose._prop)
	body.rebuild_visual_for_appearance()
	await get_tree().process_frame
	start_work()
	assert_null(old_prop.get_ref())
	assert_true(body._lockpick_pose._prop.visible)
	assert_same(body._lockpick_pose._skeleton, body.get_skeleton())
	var hidden: Array = body._lockpick_pose._hidden.duplicate()
	assert_eq(hidden.size(), 2)
	actor.set_lockpick_work_visual(false, Vector3.ZERO, 0.0, null)
	for record in hidden:
		assert_eq(record.node.get_ref().visible, record.visible)
