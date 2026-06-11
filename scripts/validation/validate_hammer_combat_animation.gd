extends SceneTree

const WAR_HAMMER := preload("res://resources/items/war_hammer.tres")
const IRON_AXE := preload("res://resources/items/iron_axe.tres")
const ROUND_SHIELD := preload("res://resources/items/round_shield.tres")
const UAL2_ANIMATION_SOURCE_SCENE := preload("res://assets/vendor/quaternius/universal_animation_library_2/UAL2.glb")

var _failures: Array[String] = []


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	await _validate_weapon_action("hammer", WAR_HAMMER)
	await _validate_weapon_action("axe", IRON_AXE)
	await _validate_weapon_action("hammer_shield", WAR_HAMMER, ROUND_SHIELD)
	await _validate_weapon_action("axe_shield", IRON_AXE, ROUND_SHIELD)
	await _validate_one_hand_shield_combat_idle("hammer_shield", WAR_HAMMER)
	await _validate_one_hand_shield_combat_idle("axe_shield", IRON_AXE)
	await _validate_lift_air_carry_pose_available()
	await _validate_clipless_default_combat_timing()
	if _failures.is_empty():
		print("HAMMER_COMBAT_ANIMATION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("HAMMER_COMBAT_ANIMATION_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_weapon_action(label: String, weapon: ItemDefinition, offhand: ItemDefinition = null) -> void:
	var attacker := _make_actor("%s_attacker" % label, weapon, Vector3.ZERO, offhand)
	var defender := _make_actor("%s_defender" % label, null, Vector3(1.0, 0.6, 0.0))
	root.add_child(attacker)
	root.add_child(defender)
	await _wait_frames(6)
	attacker.global_position = Vector3.ZERO
	defender.global_position = Vector3(1.0, 0.6, 0.0)
	attacker.base_dodge_chance = 0.0
	attacker.base_block_chance = 0.0
	defender.base_dodge_chance = 0.0
	defender.base_block_chance = 0.0
	var stance_id := str(attacker.call("_get_current_combat_animation_stance_id"))
	if stance_id != EquipmentGripProfile.GRIP_CLASS_ONE_HAND_MELEE:
		_fail("%s should use shared one-hand melee stance, got '%s'" % [label, stance_id])
	attacker.call("assign_attack_target", defender, false, false, false)
	attacker.call("_start_combat_attack", defender)
	await process_frame
	var started := bool(attacker.get("_combat_action_active"))
	var action_name := _get_current_animation(attacker)
	var action_names: Array = attacker.get("_combat_action_names")
	var started_remaining := float(attacker.get("_combat_action_remaining"))
	if not started:
		_fail("%s combat action should start" % label)
		attacker.queue_free()
		defender.queue_free()
		return
	var legal_names := ["Sword_Light_A", "Sword_Light_A_Rec", "Sword_Light_B", "Sword_Light_B_Rec"]
	if action_name.is_empty() or not legal_names.has(action_name):
		_fail("%s combat action should use legal one-hand light animation, got '%s'" % [label, action_name])
	for sequence_name in action_names:
		if not legal_names.has(str(sequence_name)):
			_fail("%s combat action sequence contains illegal one-hand animation '%s'" % [label, str(sequence_name)])
	var interrupted := false
	var previous_remaining := started_remaining
	for _frame in range(90):
		await process_frame
		var active := bool(attacker.get("_combat_action_active"))
		var remaining := float(attacker.get("_combat_action_remaining"))
		var current_animation := _get_current_animation(attacker)
		if active and not action_names.has(current_animation):
			interrupted = true
			_fail("%s combat action animation changed early from attack sequence %s to '%s'" % [label, action_names, current_animation])
			break
		if not active and previous_remaining > 0.05 and remaining <= 0.0:
			break
		previous_remaining = remaining
	if interrupted:
		pass
	attacker.COMBAT_COORDINATOR.release_character(attacker)
	attacker.COMBAT_COORDINATOR.release_character(defender)
	attacker.queue_free()
	defender.queue_free()
	await _wait_frames(2)


func _validate_one_hand_shield_combat_idle(label: String, weapon: ItemDefinition) -> void:
	var attacker := _make_actor("%s_idle_attacker" % label, weapon, Vector3.ZERO, ROUND_SHIELD)
	var defender := _make_actor("%s_idle_defender" % label, null, Vector3(1.0, 0.6, 0.0))
	root.add_child(attacker)
	root.add_child(defender)
	await _wait_frames(6)
	attacker.global_position = Vector3.ZERO
	defender.global_position = Vector3(1.0, 0.6, 0.0)
	attacker.call("assign_attack_target", defender, false, false, false)
	attacker.set("_combat_cooldown_remaining", 1.0)
	attacker.call("_update_character_animation", 0.016)
	var current_animation := _get_current_animation(attacker)
	if current_animation != "Sword_Idle":
		_fail("%s one-hand weapon with shield should hold Sword_Idle combat idle, got '%s'" % [label, current_animation])
	attacker.queue_free()
	defender.queue_free()
	await _wait_frames(2)


func _make_actor(actor_name: String, weapon: ItemDefinition, position: Vector3, offhand: ItemDefinition = null) -> HumanoidCharacter:
	var actor := HumanoidCharacter.new()
	actor.name = actor_name
	actor.member_name = actor_name
	actor.faction_name = actor_name
	actor.position = position
	var equipment: Array[Resource] = []
	if weapon != null:
		equipment.append(weapon)
	if offhand != null:
		equipment.append(offhand)
	actor.starting_equipment = equipment
	actor.use_navigation_pathing = false
	actor.navigation_avoidance_enabled = false
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.1
	collision.transform = Transform3D(Basis(), Vector3(0.0, 0.95, 0.0))
	collision.shape = capsule
	actor.add_child(collision)
	var mesh := MeshInstance3D.new()
	mesh.name = "BodyMesh"
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = 0.45
	mesh.mesh = capsule_mesh
	mesh.transform = Transform3D(Basis(), Vector3(0.0, 0.95, 0.0))
	actor.add_child(mesh)
	return actor


func _validate_lift_air_carry_pose_available() -> void:
	var actor := _make_actor("carry_pose_actor", null, Vector3.ZERO)
	root.add_child(actor)
	await _wait_frames(6)
	var body := actor.get_body_projection()
	var player: AnimationPlayer = body.get_primary_animation_player() if body != null else null
	if player == null or not player.has_animation("LiftAir_Fall"):
		_fail("Humanoid animation library should include LiftAir_Fall; lift_air_available=%s source=%s" % [_available_animation_names_containing(player, "LiftAir"), _get_ual2_lift_air_names()])
	else:
		actor.call("_play_carried_pose_animation")
		if _get_current_animation(actor) != "LiftAir_Fall":
			_fail("Carried pose should use LiftAir_Fall")
	actor.queue_free()
	await _wait_frames(2)


func _validate_clipless_default_combat_timing() -> void:
	var attacker := _make_actor("clipless_attacker", null, Vector3.ZERO)
	var defender := _make_actor("clipless_defender", null, Vector3(1.0, 0.6, 0.0))
	attacker.visual_body_type = HumanoidCharacter.VisualBodyType.NONE
	defender.visual_body_type = HumanoidCharacter.VisualBodyType.NONE
	root.add_child(attacker)
	root.add_child(defender)
	await _wait_frames(6)
	attacker.base_dodge_chance = 0.0
	attacker.base_block_chance = 0.0
	defender.base_dodge_chance = 0.0
	defender.base_block_chance = 0.0
	attacker.call("assign_attack_target", defender, false, false, false)
	attacker.call("_start_combat_attack", defender)
	await process_frame
	if not bool(attacker.get("_combat_action_active")):
		_fail("clipless combat should use actor-owned timed default action")
	elif float(attacker.get("_combat_action_impact_remaining")) <= 0.0:
		_fail("clipless combat should keep a positive actor-owned impact countdown")
	if _get_current_animation(attacker) != "":
		_fail("clipless combat should not require a presentation clip, got '%s'" % _get_current_animation(attacker))
	attacker.COMBAT_COORDINATOR.release_character(attacker)
	attacker.COMBAT_COORDINATOR.release_character(defender)
	attacker.queue_free()
	defender.queue_free()
	await _wait_frames(2)


func _available_animation_names_containing(player: AnimationPlayer, text: String) -> Array[String]:
	var result: Array[String] = []
	if player == null:
		return result
	for animation_name in player.get_animation_list():
		if str(animation_name).contains(text):
			result.append(str(animation_name))
	return result


func _get_current_animation(actor: HumanoidCharacter) -> String:
	var body := actor.get_body_projection()
	return body.get_current_clip() if body != null else ""


func _get_ual2_lift_air_names() -> Array[String]:
	var source := UAL2_ANIMATION_SOURCE_SCENE.instantiate()
	var player := _find_animation_player(source)
	var result := _available_animation_names_containing(player, "LiftAir")
	source.queue_free()
	return result


func _find_animation_player(root_node: Node) -> AnimationPlayer:
	if root_node is AnimationPlayer:
		return root_node as AnimationPlayer
	for child in root_node.get_children():
		var player := _find_animation_player(child)
		if player != null:
			return player
	return null


func _wait_frames(frame_count: int) -> void:
	for _index in range(frame_count):
		await process_frame


func _fail(message: String) -> void:
	_failures.append(message)
