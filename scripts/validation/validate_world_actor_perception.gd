extends SceneTree

const WORLD_ACTOR_SCRIPT := preload("res://scripts/actors/world_actor.gd")
const PERCEPTION_CONTROLLER_SCRIPT := preload("res://scripts/controllers/perception_controller.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _validate_plain_world_actor_perception()
	if _failures.is_empty():
		print("WORLD_ACTOR_PERCEPTION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("WORLD_ACTOR_PERCEPTION_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_plain_world_actor_perception() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var perception_controller := PERCEPTION_CONTROLLER_SCRIPT.new()
	perception_controller.name = "PerceptionController"
	scene.add_child(perception_controller)
	perception_controller.initialize(scene)
	perception_controller.add_to_group("perception_controller")

	var observer := _add_world_actor(scene, "WorldObserver", Vector3.ZERO, "Observer")
	var subject := _add_world_actor(scene, "WorldSneaker", Vector3(0.0, 0.0, -7.5), "Subject")
	subject.hostile_factions = PackedStringArray(["Observer"])
	observer.hostile_factions = PackedStringArray(["Subject"])
	await _wait_frames(4)
	observer.look_at(Vector3(subject.global_position.x, observer.global_position.y, subject.global_position.z), Vector3.UP)
	observer.set_skill_level(SkillRules.ATTRIBUTE_PERCEPTION, 1)
	subject.set_skill_level(SkillRules.SUBTERFUGE_SNEAKING, 80)
	subject.set_sneaking_enabled(true)
	var hidden_result := perception_controller.evaluate_observer(observer, subject)
	if bool(hidden_result.get("clearly_seen", false)):
		_fail("Plain WorldActor high-sneak subject should not be clearly seen at range: %s" % hidden_result)
	if observer.can_see_actor_for_combat(subject):
		_fail("Plain WorldActor observer should not see hidden sneaking subject for combat")

	subject.set_sneaking_enabled(false)
	if not observer.can_see_actor_for_combat(subject):
		_fail("Plain WorldActor non-sneaking subject should be combat-visible by default")

	subject.global_position = Vector3(0.0, 0.0, -1.2)
	observer.look_at(Vector3(subject.global_position.x, observer.global_position.y, subject.global_position.z), Vector3.UP)
	subject.set_skill_level(SkillRules.SUBTERFUGE_SNEAKING, 1)
	subject.set_sneaking_enabled(true)
	var detected_result := perception_controller.evaluate_observer(observer, subject)
	if not bool(detected_result.get("clearly_seen", false)):
		_fail("Plain WorldActor low-sneak subject should be clearly seen up close: %s" % detected_result)
	if not observer.can_see_actor_for_combat(subject):
		_fail("Plain WorldActor observer should see detected sneaking subject for combat")

	scene.queue_free()
	await _wait_frames(3)


func _add_world_actor(scene: Node, actor_name: String, position: Vector3, faction: String) -> WorldActor:
	var actor: WorldActor = WORLD_ACTOR_SCRIPT.new()
	actor.name = actor_name
	actor.member_name = actor_name
	actor.position = position
	actor.faction_name = faction
	actor.navigation_agent_height = 2.0
	actor.navigation_agent_radius = 0.45
	scene.add_child(actor)
	return actor


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _fail(message: String) -> void:
	_failures.append(message)
