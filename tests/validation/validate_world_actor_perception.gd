extends Node

## Real actor, physics perception and the registered GECS targeting pipeline.
var _failures: Array[String] = []
var _checks := 0
var _scene: Node3D
var _gecs: GecsWorldController
var _queries: ActorQueryController

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_scene = Node3D.new()
	add_child(_scene)
	var context := BootstrapContext.new(_scene)
	BootstrapContext.active = context
	var perception := PerceptionController.new()
	_scene.add_child(perception)
	context.register(PerceptionController.SERVICE_ID, perception)
	perception.initialize(context)
	_gecs = GecsWorldController.new()
	context.register(GecsWorldController.SERVICE_ID, _gecs)
	_scene.add_child(_gecs)
	_gecs.initialize(context)
	_gecs.set_process(false)
	_queries = ActorQueryController.new()
	_scene.add_child(_queries)
	context.register(ActorQueryController.SERVICE_ID, _queries)
	_queries.initialize(context)
	var observer := _add_actor("observer", Vector3.ZERO, "Observer")
	var subject := _add_actor("subject", Vector3(0, 0, -7.5), "Subject")
	observer.hostile_factions = PackedStringArray(["Subject"])
	observer.combat_stance = NpcRules.CombatStance.AGGRESSIVE
	subject.combat_stance = NpcRules.CombatStance.PASSIVE
	observer.set_skill_level(SkillRules.ATTRIBUTE_PERCEPTION, 1)
	subject.set_skill_level(SkillRules.SUBTERFUGE_SNEAKING, 80)
	subject.set_sneaking_enabled(true)
	await get_tree().physics_frame
	observer.look_at(subject.global_position)
	var targeting := AiTargetingCapability.new()
	targeting.setup(observer)
	_expect(_queries.get_nearby_actors(observer.global_position, 12.0, true).has(subject), "Canonical actor query must contain the hidden subject before visibility filtering")
	_expect(targeting.get_query_actors(observer.global_position, 12.0, true).has(subject), "Public AI candidate query must use the registered actor-query authority")
	_expect(not bool(perception.evaluate_observer(observer, subject).get("clearly_seen", false)), "High-sneak fixture must actually be hidden")
	_expect(observer.has_method("can_see_actor_for_combat"), "WorldActor must expose its combat visibility contract")
	if observer.has_method("can_see_actor_for_combat"):
		_expect(not bool(observer.call("can_see_actor_for_combat", subject)), "Hidden subject must be invisible to the actor contract")
	_expect(targeting.find_closest_hostile(12.0) == null, "Public AI acquisition must refuse a hidden hostile")
	_step_targeting()
	_expect(observer.get_current_combat_target() == null, "Registered GECS acquisition must refuse a hidden hostile")

	subject.set_sneaking_enabled(false)
	_expect(targeting.find_closest_hostile(12.0) == subject, "Public AI acquisition must accept a visible hostile")
	_step_targeting()
	_expect(observer.get_current_combat_target() == subject, "Registered GECS acquisition must accept a visible hostile")
	# An already-selected target must not bypass visibility through its slot lock.
	subject.set_sneaking_enabled(true)
	_step_targeting()
	_expect(observer.get_current_combat_target() == null, "Existing GECS pursuit must release a now-hidden subject")

	subject.global_position = Vector3(0, 0, -1.2)
	subject.set_skill_level(SkillRules.SUBTERFUGE_SNEAKING, 1)
	_expect(bool(perception.evaluate_observer(observer, subject).get("clearly_seen", false)), "Low-sneak close fixture must actually be detected")
	_expect(targeting.find_closest_hostile(12.0) == subject, "Public AI must positively acquire a detected target that is still sneaking")
	_step_targeting()
	_expect(observer.get_current_combat_target() == subject, "Detected sneaking hostile must be acquired")
	subject.queue_free()
	await get_tree().process_frame
	_step_targeting()
	_expect(observer.get_current_combat_target() == null, "Freed target must not remain acquired")
	targeting.teardown()
	_scene.queue_free()
	await get_tree().process_frame
	BootstrapContext.active = null
	for failure in _failures:
		push_error(failure)
	print("WORLD_ACTOR_PERCEPTION_%s checks=%d" % ["OK" if _failures.is_empty() else "FAILED", _checks])
	get_tree().quit(0 if _failures.is_empty() else 1)

func _add_actor(actor_id: String, position: Vector3, faction: String) -> WorldActor:
	var actor := WorldActor.new()
	actor.name = actor_id
	actor.stable_id = actor_id
	actor.member_name = actor_id
	actor.faction_name = faction
	actor.position = position
	_scene.add_child(actor)
	actor.set_physics_process(false)
	_queries.register_actor(actor)
	return actor

func _step_targeting() -> void:
	# Fixed small ticks also run state sync, slots and the ordinary query wiring.
	for _tick in range(20):
		_gecs.world.process(0.05)

func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
