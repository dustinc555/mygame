extends "res://tests/validation/test_case.gd"

const PERCEPTION_CONTROLLER_SCRIPT := preload("res://features/actors/bridge/perception/perception_controller.gd")
const FACTION_HUMANOID_SCRIPT := preload("res://features/actors/projection/humanoid/faction_humanoid.gd")
const RUSTDEAD_HUMANOID_SCRIPT := preload("res://features/actors/projection/rustdead/rustdead_humanoid_character.gd")

# Visibility needs the real actor/capabilities, not a rendered skin. The 5v10
# production-scene validator separately keeps the complete visual/skin contract.
const VISUAL_BODY_TYPE_NONE := 1

var _failures: Array[String] = []
var _queries: ActorQueryController


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
	var context := BootstrapContext.new(scene)
	var previous_context := BootstrapContext.active
	BootstrapContext.active = context
	var gecs := GecsWorldController.new()
	scene.add_child(gecs)
	context.register(gecs.SERVICE_ID, gecs)
	gecs.initialize(context)
	gecs.set_process(false)
	_queries = ActorQueryController.new()
	scene.add_child(_queries)
	context.register(ActorQueryController.SERVICE_ID, _queries)
	_queries.initialize(context)
	var perception_controller := PERCEPTION_CONTROLLER_SCRIPT.new()
	perception_controller.name = "PerceptionController"
	scene.add_child(perception_controller)
	context.register(PerceptionController.SERVICE_ID, perception_controller)
	perception_controller.initialize(context)
	perception_controller.add_to_group("perception_controller")

	var rustdead := _add_rustdead(scene, "StealthRustdead", Vector3.ZERO)
	var player := _add_player(scene, "Sneaker", Vector3(0.0, 0.0, -7.5))
	await _wait_frames(8)
	if not rustdead is RustdeadHumanoidCharacter:
		_fail("Perception regression must use the production Rustdead subclass")
	for actor in [rustdead, player]:
		actor.set_physics_process(false)
		_queries.register_actor(actor)
		if gecs.get_actor_entity(actor) == null:
			_fail("Perception subject must be registered with stable GECS identity")
	rustdead.set_skill_level(SkillRules.ATTRIBUTE_PERCEPTION, 1)
	player.set_skill_level(SkillRules.SUBTERFUGE_SNEAKING, 80)
	player.set_sneaking_enabled(true)
	await _wait_frames(2)
	if not _queries.get_nearby_actors(rustdead.global_position, 18.0, true).has(player):
		_fail("Canonical actor query must contain the hidden subject before targeting")
	var hidden_result := perception_controller.evaluate_observer(rustdead, player)
	if bool(hidden_result.get("clearly_seen", false)):
		_fail("High-sneak player should not be clearly seen by low-perception Rustdead at normal range: %s" % hidden_result)
	_step_targeting(gecs)
	var combat_state = gecs.get_actor_entity(rustdead).get_component(CGameCombatState)
	if combat_state.system_target_id != 0 or not combat_state.system_target_actor_id.is_empty():
		_fail("GECS targeting must not acquire a hidden sneaking player")

	player.set_sneaking_enabled(false)
	await _wait_frames(2)
	_step_targeting(gecs)
	if combat_state.system_target_actor_id != player.stable_id:
		_fail("GECS targeting must acquire the standing hostile player")
	# Clear only combat state between independent acquisition cases.
	combat_state.current_target_id = 0
	combat_state.current_target_actor_id = ""
	combat_state.system_target_retarget_remaining = 0.0
	combat_state.system_target_id = 0
	combat_state.system_target_actor_id = ""

	player.global_position = Vector3(0.0, 0.0, -1.2)
	player.set_skill_level(SkillRules.SUBTERFUGE_SNEAKING, 1)
	player.set_sneaking_enabled(true)
	await _wait_frames(2)
	var detected_result := perception_controller.evaluate_observer(rustdead, player)
	if not bool(detected_result.get("clearly_seen", false)):
		_fail("Low-sneak player should be clearly seen by Rustdead up close: %s" % detected_result)
	_step_targeting(gecs)
	if combat_state.system_target_actor_id != player.stable_id:
		_fail("GECS targeting must acquire the close detected sneaking player; selected=%s observer_life=%s target_life=%s retarget=%.3f detected=%s" % [combat_state.system_target_actor_id, rustdead.life_state, player.life_state, combat_state.system_target_retarget_remaining, detected_result])

	print("RUSTDEAD_STEALTH_CASES_EXECUTED hidden standing close_detected")
	scene.queue_free()
	await _wait_frames(3)
	BootstrapContext.active = previous_context


func _step_targeting(gecs: GecsWorldController) -> void:
	for _tick in range(20):
		gecs.world.process(0.05)


func _add_player(scene: Node, actor_name: String, position: Vector3) -> HumanoidCharacter:
	var actor: HumanoidCharacter = FACTION_HUMANOID_SCRIPT.new()
	actor.name = actor_name
	actor.stable_id = actor_name
	actor.member_name = actor_name
	actor.position = position
	actor.faction_name = "Player"
	actor.appearance_data = CharacterAppearanceData.new()
	actor.appearance_data.visual_body_type = VISUAL_BODY_TYPE_NONE
	_add_basic_actor_children(actor, Color(0.42, 0.56, 0.75, 1.0))
	scene.add_child(actor)
	return actor


func _add_rustdead(scene: Node, actor_name: String, position: Vector3) -> HumanoidCharacter:
	var actor: HumanoidCharacter = RUSTDEAD_HUMANOID_SCRIPT.new()
	actor.name = actor_name
	actor.stable_id = actor_name
	actor.member_name = actor_name
	actor.position = position
	actor.faction_name = "Rustdead"
	actor.hostile_factions = PackedStringArray(["Player"])
	actor.combat_stance = NpcRules.CombatStance.AGGRESSIVE
	actor.aggressive_scan_radius = 18.0
	actor.assist_scan_radius = 18.0
	actor.appearance_data = CharacterAppearanceData.new()
	actor.appearance_data.visual_body_type = VISUAL_BODY_TYPE_NONE
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
