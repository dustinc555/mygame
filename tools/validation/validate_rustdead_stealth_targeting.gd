extends SceneTree

const PERCEPTION_CONTROLLER_SCRIPT := preload("res://src/actors/bridge/perception/perception_controller.gd")
const FACTION_HUMANOID_SCRIPT := preload("res://src/actors/projection/humanoid/faction_humanoid.gd")
const RUSTDEAD_HUMANOID_SCRIPT := preload("res://src/actors/projection/rustdead/rustdead_humanoid_character.gd")

const VISUAL_BODY_TYPE_MALE := 2

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _validate_rustdead_stealth_targeting()
	if _failures.is_empty():
		print("RUSTDEAD_STEALTH_TARGETING_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("RUSTDEAD_STEALTH_TARGETING_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_rustdead_stealth_targeting() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var perception_controller := PERCEPTION_CONTROLLER_SCRIPT.new()
	perception_controller.name = "PerceptionController"
	scene.add_child(perception_controller)
	perception_controller.initialize(scene)
	perception_controller.add_to_group("perception_controller")

	var rustdead := _add_rustdead(scene, "StealthRustdead", Vector3.ZERO)
	var player := _add_player(scene, "Sneaker", Vector3(0.0, 0.0, -7.5))
	await _wait_frames(8)
	rustdead.set_skill_level(SkillRules.ATTRIBUTE_PERCEPTION, 1)
	player.set_skill_level(SkillRules.SUBTERFUGE_SNEAKING, 80)
	player.set_sneaking_enabled(true)
	await _wait_frames(2)
	var hidden_result := perception_controller.evaluate_observer(rustdead, player)
	if bool(hidden_result.get("clearly_seen", false)):
		_fail("High-sneak player should not be clearly seen by low-perception Rustdead at normal range: %s" % hidden_result)
	if rustdead.can_see_actor_for_combat(player):
		_fail("Rustdead should not see hidden sneaking player for combat")
	if rustdead.call("_find_ai_target") == player:
		_fail("Rustdead should not acquire hidden sneaking player as AI target")
	if rustdead.assign_attack_target(player, false):
		_fail("Rustdead should not accept an unseen sneaking player as an AI attack target")
	if rustdead.get_current_combat_target() == player:
		_fail("Rustdead should not keep hidden sneaking player as combat target")

	player.set_sneaking_enabled(false)
	await _wait_frames(2)
	if not rustdead.can_see_actor_for_combat(player):
		_fail("Non-sneaking hostile player should be combat-visible by default")
	if rustdead.call("_find_ai_target") != player:
		_fail("Rustdead should acquire non-sneaking hostile player by default visibility")
	rustdead.stop_attack_assignment()

	player.global_position = Vector3(0.0, 0.0, -1.2)
	player.set_skill_level(SkillRules.SUBTERFUGE_SNEAKING, 1)
	player.set_sneaking_enabled(true)
	await _wait_frames(2)
	var detected_result := perception_controller.evaluate_observer(rustdead, player)
	if not bool(detected_result.get("clearly_seen", false)):
		_fail("Low-sneak player should be clearly seen by Rustdead up close: %s" % detected_result)
	if not rustdead.can_see_actor_for_combat(player):
		_fail("Rustdead should see detected sneaking player for combat")
	if rustdead.call("_find_ai_target") != player:
		_fail("Rustdead should acquire detected sneaking player as AI target")

	scene.queue_free()
	await _wait_frames(3)


func _add_player(scene: Node, actor_name: String, position: Vector3) -> HumanoidCharacter:
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
	actor.hostile_factions = PackedStringArray(["Player"])
	actor.combat_stance = NpcRules.CombatStance.AGGRESSIVE
	actor.aggressive_scan_radius = 18.0
	actor.assist_scan_radius = 18.0
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


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _fail(message: String) -> void:
	_failures.append(message)
