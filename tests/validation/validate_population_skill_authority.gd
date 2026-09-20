extends "res://tests/validation/test_case.gd"
## Immediate progress authority is independent of batched presentation and save-time flushing.
const ACTOR_ID := "validation.population.skill_authority"
var _failures: Array[String] = []
var _checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var context := BootstrapContext.new(scene)
	BootstrapContext.active = context
	var bridge := GecsWorldController.new()
	scene.add_child(bridge)
	context.register(GecsWorldController.SERVICE_ID, bridge)
	bridge.initialize(context)
	bridge.set_process(false)
	var population := PopulationController.new()
	scene.add_child(population)
	context.register(PopulationController.SERVICE_ID, population)
	population.initialize(context)
	var actor := WorldActor.new()
	actor.stable_id = ACTOR_ID
	scene.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	bridge.register_actor(actor)
	population.register_actor(actor)
	var stats := actor.get_stats()
	var progress := [0]
	var levels := [0]
	var record_events := [0]
	stats.skill_progress_changed.connect(func(_id: String): progress[0] += 1)
	stats.skill_level_changed.connect(func(_id: String): levels[0] += 1)
	population.population_record_changed.connect(func(_settlement: String, _id: String): record_events[0] += 1)
	var skill := SkillRules.MOVEMENT_RUNNING
	stats.add_skill_xp(skill, 1.0, "first_pending")
	stats.add_skill_xp(skill, 2.0, "second_pending")
	_expect(is_equal_approx(stats.get_skill_xp(skill), 3.0), "raw pending XP is immediately readable")
	_expect(is_equal_approx(float(bridge.get_population_record(ACTOR_ID).get("skill_xp", {}).get(skill, 0.0)), 3.0), "pending XP reaches GECS before any flush or save")
	_expect(progress[0] == 0 and levels[0] == 0 and record_events[0] == 0, "XP does not wake batched UI or whole-population subscribers")
	var save_path := "user://population_skill_authority_%d.tres" % OS.get_process_id()
	# Exercise the actual GECS serializer without the public save's legacy UI flush.
	var io = bridge.get("_gecs_io_script")
	_expect(io.save(io.serialize_entities(bridge.world.entities), save_path, false), "serialize real GECS entities while XP remains pending")
	_expect(progress[0] == 0, "snapshot did not accidentally flush pending presentation")
	stats.add_skill_xp(skill, 4.0, "discard_on_load")
	stats.add_skill_xp(SkillRules.ATTRIBUTE_TOUGHNESS, stats.get_skill_xp_to_next(SkillRules.ATTRIBUTE_TOUGHNESS), "discard_level_on_load")
	_expect(stats.get_skill_level(SkillRules.ATTRIBUTE_TOUGHNESS) == SkillRules.DEFAULT_LEVEL + 1, "level and stat input change immediately before notification")
	_expect(levels[0] == 0, "level-up presentation stays batched")
	_expect(bridge.load_gecs_world(save_path), "warm load succeeds before pending notifications flush")
	# A UI flush in the same stack as load must never write the old projection back.
	stats.flush_pending_xp()
	_expect(is_equal_approx(float(bridge.get_population_record(ACTOR_ID).get("skill_xp", {}).get(skill, 0.0)), 3.0), "pre-hydration UI flush cannot overwrite loaded durable XP")
	await process_frame
	await process_frame
	_expect(is_equal_approx(stats.get_skill_xp(skill), 3.0), "warm hydration restores saved pending XP")
	_expect(stats.get_skill_level(SkillRules.ATTRIBUTE_TOUGHNESS) == SkillRules.DEFAULT_LEVEL and is_zero_approx(stats.get_skill_xp(SkillRules.ATTRIBUTE_TOUGHNESS)), "skills absent from sparse snapshot reset to defaults")
	_expect(stats.flush_pending_xp() == 0, "hydration cancels obsolete queued level notifications")
	progress[0] = 0
	levels[0] = 0
	record_events[0] = 0
	stats.add_skill_xp(skill, stats.get_skill_xp_to_next(skill) - stats.get_skill_xp(skill), "post_load_level")
	_expect(stats.get_skill_level(skill) == SkillRules.DEFAULT_LEVEL + 1, "post-load XP continues from restored progress")
	_expect(int(bridge.get_population_record(ACTOR_ID).get("skill_levels", {}).get(skill, 0)) == stats.get_skill_level(skill), "level-up reaches GECS without waiting for UI")
	_expect(progress[0] == 0 and levels[0] == 0 and record_events[0] == 0, "immediate authority does not undo notification batching")
	_expect(stats.flush_pending_xp() == 1 and progress[0] == 1 and levels[0] == 1, "one batched progress and level notification is emitted")
	stats.set_skill_level(skill, SkillRules.DEFAULT_LEVEL)
	_expect(not bridge.get_population_record(ACTOR_ID).get("skill_levels", {}).has(skill), "explicit reset removes sparse durable level")
	stats.add_skill_xp(skill, 1.0, "retiring_pending")
	population.unregister_actor(actor)
	var retired_xp: Dictionary = bridge.get_population_record(ACTOR_ID).get("skill_xp", {}).duplicate(true)
	stats.add_skill_xp(skill, 2.0, "detached_projection")
	stats.flush_pending_xp()
	_expect(bridge.get_population_record(ACTOR_ID).get("skill_xp", {}) == retired_xp, "detached projection no longer writes progress")
	bridge.unregister_actor(actor)
	actor.free()
	BootstrapContext.active = null
	scene.free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	for failure in _failures:
		push_error(failure)
	print("POPULATION_SKILL_AUTHORITY_%s checks=%d" % ["OK" if _failures.is_empty() else "FAILED", _checks])
	quit(0 if _failures.is_empty() else 1)

func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
