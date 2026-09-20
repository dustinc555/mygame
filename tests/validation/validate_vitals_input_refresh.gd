extends "res://tests/validation/test_case.gd"

## 40 actors previously rebuilt both vitals inputs on every GECS pass (~2.21 ms
## average in the instrumented 20v20 captures). Count real resolver work, not FPS.
## Run: python3 tests/run_validation.py --jobs 1 --filter validate_vitals_input_refresh
class CountingStats:
	extends StatsCapability
	var derivations := 0

	func get_stat_value(stat_name: String, include_secondary_modifiers := true) -> float:
		if stat_name == "toughness" or stat_name == "healing_rate":
			derivations += 1
		return super.get_stat_value(stat_name, include_secondary_modifiers)

	func uncached_inputs() -> Array[float]:
		return [super.get_stat_value("toughness"), super.get_stat_value("healing_rate")]

class CountingModifier:
	extends ItemStatModifier
	var conversions := 0

	func to_modifier_dictionary() -> Dictionary:
		conversions += 1
		return super.to_modifier_dictionary()

class CountingActor:
	extends WorldActor

	func _create_actor_capabilities() -> void:
		super._create_actor_capabilities()
		var stats := CountingStats.new()
		stats.starting_skill_levels = get_stats().starting_skill_levels
		add_capability(stats)
		get_needs().bind_stats(stats)

const ACTOR_COUNT := 40
const HYDRATED_ITEM_PATH := "user://vitals_refresh_item.tres"
var _scene: Node3D
var _gecs: GecsWorldController
var _actors: Array[CountingActor] = []
var _failures: Array[String] = []
var _checks := 0

func _initialize() -> void:
	_scene = Node3D.new()
	root.add_child(_scene)
	var context := BootstrapContext.new(_scene)
	BootstrapContext.active = context
	_gecs = GecsWorldController.new()
	context.register(GecsWorldController.SERVICE_ID, _gecs)
	_scene.add_child(_gecs)
	_gecs.initialize(context)
	_gecs.set_process(false)
	# Use the registered production World and system ordering, without unrelated
	# combat/AI work. Vitals and population simulation remain real and active.
	for system in _gecs.world.systems_by_group[""]:
		system.active = system is GameActorSyncSystem or system is GameVitalsSystem or system is GamePopulationVitalsSystem
	var modifier := _modifier("toughness", 3.0, 1.2)
	var gear := _item("chest", [modifier])
	for index in range(ACTOR_COUNT):
		var actor := _actor("vitals.refresh.%d" % index)
		actor.equip_item_to_slot(gear, "chest")
		_actors.append(actor)
	var before := _derivations()
	_gecs.world.process(0.0)
	_expect(_derivations() - before == ACTOR_COUNT * 2, "Every first-seen actor derives both inputs immediately")
	for actor in _actors:
		_matches(actor, "first-seen")
	await _unchanged_cohort(modifier)
	var subject := _actors[0]
	_skills(subject)
	_equipment(subject)
	_next_vitals_tick(subject)
	await _carry()
	await _projection_lifecycle()
	await _unloaded_simulation()
	_scene.queue_free()
	await process_frame
	BootstrapContext.active = null
	for failure in _failures:
		push_error(failure)
	print("VITALS_INPUT_REFRESH_%s checks=%d failures=%d" % ["OK" if _failures.is_empty() else "FAILED", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _unchanged_cohort(modifier: CountingModifier) -> void:
	var before := _derivations()
	var conversions := modifier.conversions
	var multiple_batches := false
	for frame in range(12):
		var previous := Engine.get_process_frames()
		while Engine.get_process_frames() == previous:
			await process_frame
		# Real archetype migration/reordering, plus repeat dispatch in one frame.
		var entity = _gecs.get_actor_entity(_actors[frame])
		entity.remove_component(CGameMovementState)
		var sync := _gecs.find_child("GameActorSyncSystem", true, false) as GameActorSyncSystem
		var batches := 0
		for archetype in sync.query().archetypes():
			if not archetype.entities.is_empty():
				batches += 1
		multiple_batches = multiple_batches or batches > 1
		_gecs.world.process(0.0)
		_gecs.world.process(0.0)
	_expect(multiple_batches, "Unchanged fixture really exercises multiple GECS archetypes")
	var work := _derivations() - before
	var conversions_done := modifier.conversions - conversions
	_expect(work == 0, "Unchanged actors must stop full derivations: observed %d" % work)
	_expect(conversions_done == 0, "Unchanged actors must not rebuild modifier dictionaries: observed %d" % conversions_done)
	print("VITALS_INPUT_STEADY actors=%d frames=12 passes=24 derivations=%d modifier_conversions=%d" % [ACTOR_COUNT, work, conversions_done])
	for actor in _actors:
		var entity = _gecs.get_actor_entity(actor)
		if not entity.has_component(CGameMovementState):
			entity.add_component(CGameMovementState.new())

func _skills(actor: CountingActor) -> void:
	var stats := actor.get_stats() as CountingStats
	actor.set_skill_level(SkillRules.ATTRIBUTE_TOUGHNESS, 19)
	_sync(actor, "actor direct level", 2)
	stats.skill_set.set_skill_level(SkillRules.ATTRIBUTE_TOUGHNESS, 23)
	_sync(actor, "resource direct level", 2)
	stats.skill_set.set_skill_progress(SkillRules.ATTRIBUTE_TOUGHNESS, 27, 0.0)
	_sync(actor, "resource direct progress", 2)
	stats.skill_set.add_skill_xp(SkillRules.ATTRIBUTE_TOUGHNESS, stats.get_skill_xp_to_next(SkillRules.ATTRIBUTE_TOUGHNESS))
	_sync(actor, "resource direct XP level", 2)
	var signals := {"level": 0, "progress": 0}
	stats.skill_level_changed.connect(func(_id): signals.level += 1)
	stats.skill_progress_changed.connect(func(_id): signals.progress += 1)
	var gained := stats.add_skill_xp(SkillRules.ATTRIBUTE_TOUGHNESS, stats.get_skill_xp_to_next(SkillRules.ATTRIBUTE_TOUGHNESS))
	_expect(gained > 0 and signals.level == 0 and signals.progress == 0, "XP level changes before batched public notifications")
	_sync(actor, "XP level before flush", 2)
	stats.flush_pending_xp()
	_expect(signals.level == 1 and signals.progress == 1, "Public XP notifications retain their batching")
	_sync(actor, "XP signal flush is not a new input", 0)
	stats.add_skill_xp(SkillRules.ATTRIBUTE_TOUGHNESS, 0.01)
	_sync(actor, "non-level toughness XP", 0)
	stats.skill_set.set_skill_progress(SkillRules.ATTRIBUTE_TOUGHNESS, stats.get_skill_level(SkillRules.ATTRIBUTE_TOUGHNESS), 0.02)
	_sync(actor, "non-level resource progress", 0)
	stats.skill_set.set_skill_level(SkillRules.ATTRIBUTE_STRENGTH, 43)
	stats.skill_set.add_skill_xp(SkillRules.MOVEMENT_RUNNING, 0.01)
	_sync(actor, "unrelated skills and entry creation", 0)
	var old_set := stats.skill_set
	var replacement := ActorSkillSet.new()
	replacement.entries = [ActorSkillEntry.new().setup(SkillRules.ATTRIBUTE_TOUGHNESS, 37)]
	stats.set_skill_set(replacement)
	_sync(actor, "set_skill_set replacement", 2)
	old_set.set_skill_level(SkillRules.ATTRIBUTE_TOUGHNESS, 72)
	_sync(actor, "detached skill set cannot invalidate", 0)
	stats.skill_set = ActorSkillSet.new()
	stats.skill_set.set_skill_level(SkillRules.ATTRIBUTE_TOUGHNESS, 41)
	_sync(actor, "public skill_set assignment", 2)
	stats.hydrate_skill_progress({SkillRules.ATTRIBUTE_TOUGHNESS: 46}, {SkillRules.ATTRIBUTE_TOUGHNESS: 1.25})
	_sync(actor, "live progress hydration", 2)
	stats.apply_starting_skill_levels({SkillRules.ATTRIBUTE_TOUGHNESS: 51})
	_sync(actor, "post-ready starting levels", 2)
	# Entry resources are public too; compare to what the real indexed resolver sees.
	(stats.skill_set.entries[0] as ActorSkillEntry).level = 54
	_sync(actor, "nested skill entry level", 2)
	stats.starting_skill_levels.clear()
	stats.skill_set = null
	_sync(actor, "null skill set recreation", 2)

func _equipment(actor: CountingActor) -> void:
	var equipment := actor.get_equipment()
	var first := _modifier("toughness", 7.0, 1.3)
	var healing := _modifier("healing_rate", 0.4, 1.5)
	var gear := _item("chest", [first, healing])
	actor.equip_item_to_slot(gear, "chest")
	_sync(actor, "equipment replacement", 2)
	var extra := _item("head", [_modifier("toughness", -2.0, 0.8)])
	actor.equip_item_to_slot(extra, "head")
	_sync(actor, "multiple slots preserve layer sum/product", 2)
	first.add = 9.0
	_sync(actor, "nested additive edit without signal", 2)
	first.mul = 1.7
	_sync(actor, "nested multiplier edit without signal", 2)
	first.stat_name = "healing_rate"
	_sync(actor, "nested target-stat edit without signal", 2)
	gear.stat_modifiers = [_modifier("toughness", 12.0, 1.2)]
	_sync(actor, "modifier array replacement", 2)
	gear.stat_modifiers.append(healing)
	_sync(actor, "modifier array append", 2)
	gear.stat_modifiers[0] = _modifier("toughness", 15.0, 0.9)
	_sync(actor, "modifier array indexed replacement", 2)
	gear.stat_modifiers.erase(healing)
	_sync(actor, "modifier array erase", 2)
	gear.stat_modifiers.append(null)
	_sync(actor, "null modifiers do not affect inputs", 0)
	var unrelated := _modifier("attack_damage", 99.0, 1.0)
	gear.stat_modifiers.append(unrelated)
	_sync(actor, "unrelated modifier append", 0)
	unrelated.add = 100.0
	_sync(actor, "unrelated modifier edit", 0)
	unrelated.stat_name = "healing_rate"
	_sync(actor, "unrelated modifier becomes a vitals input", 2)
	gear.stat_modifiers.clear()
	_sync(actor, "modifier array clear", 2)
	actor.unequip_item_from_slot("head")
	_sync(actor, "unequip", 2)
	var emitted := {"count": 0}
	equipment.equipment_changed.connect(func(_slots): emitted.count += 1)
	equipment.begin_equipment_update_batch()
	equipment.begin_equipment_update_batch()
	actor.equip_item_to_slot(extra, "head")
	_sync(actor, "equip visible during nested batch", 2)
	_expect(emitted.count == 0, "Nested equip retains deferred equipment signal")
	equipment.end_equipment_update_batch()
	actor.unequip_item_from_slot("head")
	_sync(actor, "unequip visible before outer batch flush", 2)
	equipment.end_equipment_update_batch()
	_expect(emitted.count == 1, "Nested equipment batch still emits exactly once")
	_sync(actor, "equipment signal flush is not a new input", 0)
	# Exercise actual ResourceSaver/load + the silent hydration route.
	var saved_modifier := ItemStatModifier.new()
	saved_modifier.stat_name = "healing_rate"
	saved_modifier.add = 0.2
	saved_modifier.mul = 1.1
	var saved := _item("head", [saved_modifier])
	_expect(ResourceSaver.save(saved, HYDRATED_ITEM_PATH) == OK, "Hydration item must really save")
	equipment.hydrate_gecs_slots([{"slot_name": "head", "item_definition_path": HYDRATED_ITEM_PATH, "stack_id": "refresh.hydrated"}], false)
	_sync(actor, "silent equipment hydration", 2)
	_expect(emitted.count == 1 and equipment.get_equipped_stack_id("head") == "refresh.hydrated", "Silent hydration preserves stack identity without public notification")
	equipment.hydrate_gecs_slots([], true)
	_sync(actor, "empty equipment hydration", 2)
	# The public dictionary is observable by the resolver even without equip APIs.
	equipment.equipped_items = {"chest": _item("chest", [_modifier("toughness", 2.0, 1.0)])}
	_sync(actor, "public equipment dictionary replacement", 2)
	equipment.equipped_items.clear()
	_sync(actor, "public equipment dictionary in-place clear", 2)
	first.add = 500.0
	_sync(actor, "detached modifiers cannot invalidate", 0)

func _next_vitals_tick(actor: CountingActor) -> void:
	var stats := actor.get_stats() as CountingStats
	var healing := _modifier("healing_rate", 2.0, 1.4)
	actor.equip_item_to_slot(_item("chest", [healing]), "chest")
	_sync(actor, "tick setup", 2)
	var vitals := _vitals(actor)
	vitals.blunt_damage = 25.0
	VitalsStateMachine.recalculate(vitals, _inputs(actor).toughness)
	_gecs.world.process(0.049)
	var expected := CGameActorVitals.new()
	expected.apply_durable_state(vitals.durable_state())
	var before_wound := expected.blunt_damage
	stats.add_skill_xp(SkillRules.ATTRIBUTE_TOUGHNESS, stats.get_skill_xp_to_next(SkillRules.ATTRIBUTE_TOUGHNESS))
	healing.add = 5.0
	var values := stats.uncached_inputs()
	VitalsStateMachine.tick(expected, values[0], values[1], 0.05)
	_gecs.world.process(0.001)
	_matches(actor, "change immediately before fixed tick")
	_expect(vitals.durable_state() == expected.durable_state(), "Next applicable vitals tick must equal uncached-input state-machine result")
	_expect(vitals.blunt_damage < before_wound, "Fixed-tick oracle must exercise actual healing")
	_inputs(actor).pending_rest_state = NpcRules.LifeState.ASLEEP
	_sync(actor, "rest mailbox does not derive stats", 0)
	_expect(_inputs(actor).pending_rest_state == NpcRules.LifeState.ASLEEP, "Input refresh must preserve pending rest command")
	_gecs.world.process(0.05)
	_expect(vitals.life_state == NpcRules.LifeState.ASLEEP and _inputs(actor).pending_rest_state == -1, "Fixed tick still consumes rest mailbox")

func _carry() -> void:
	# WorldActor's base is_carried() deliberately returns false. Exercise the
	# actual humanoid override and real CarryCapability, not a fixture boolean.
	var actor := HumanoidCharacter.new()
	var carrier := HumanoidCharacter.new()
	actor.stable_id = "vitals.carry.passenger"
	carrier.stable_id = "vitals.carry.carrier"
	for member in [actor, carrier]:
		_scene.add_child(member)
		member.set_process(false)
		member.set_physics_process(false)
		_gecs.register_actor(member)
	_gecs.world.process(0.0)
	_expect(carrier.get_carry().begin_carry(actor.get_carry(), true), "Real carry must attach")
	_gecs.world.process(0.0)
	_expect(_inputs(actor).held_externally, "Held input updates independently of cached stats")
	_expect(carrier.get_carry().drop() == actor, "Real carry must drop")
	_gecs.world.process(0.0)
	_expect(not _inputs(actor).held_externally, "Drop clears held input on the very next pass")
	for member in [actor, carrier]:
		_gecs.unregister_actor(member)
		member.queue_free()
	await process_frame

func _projection_lifecycle() -> void:
	var actor := _actor("vitals.replaced", 35)
	_sync(actor, "late actor with authored skills", 2)
	var entity = _gecs.get_actor_entity(actor)
	var inputs := _inputs(actor)
	inputs.dirty = true
	_sync(actor, "explicit dirty refresh", 2)
	var old_skills := actor.get_stats().skill_set
	var old_stats: WeakRef = weakref(actor.get_stats())
	actor.queue_free()
	await process_frame
	_gecs.world.process(0.0)
	_expect(entity.get_component(CGameActorNode).get_actor() == null, "Destroyed projection really leaves the GECS node binding")
	_expect(old_stats.get_ref() == null, "Input tracking must not retain torn-down StatsCapability")
	actor = _actor("vitals.replaced", 57)
	_expect(_gecs.get_actor_entity(actor) == entity, "Projection replacement must reuse the same entity and input component")
	_sync(actor, "replacement projection first pass", 2)
	old_skills.set_skill_level(SkillRules.ATTRIBUTE_TOUGHNESS, 80)
	_sync(actor, "old projection skill signals have no callback", 0)
	entity.remove_component(CGameActorVitalsInputs)
	var replacement := CGameActorVitalsInputs.new()
	replacement.apply_durable_state({"toughness": 1.0, "healing_rate": 9.0})
	replacement.dirty = false
	entity.add_component(replacement)
	_sync(actor, "new hydrated input component first pass", 2)
	_inputs(actor).apply_durable_state({"toughness": 2.0, "healing_rate": 8.0})
	_sync(actor, "in-place durable input hydration", 2)
	_expect(_inputs(actor).durable_state().size() == 2, "Cache bindings stay outside the durable schema")
	_gecs.unregister_actor(actor)
	actor.queue_free()
	await process_frame

func _unloaded_simulation() -> void:
	var id := "vitals.unloaded"
	_gecs.upsert_population_record({"actor_id": id, "stable_id": id, "realization_state": "ledger"})
	var actor := _actor(id, 31)
	actor.get_stats().hydrate_skill_progress({SkillRules.ATTRIBUTE_TOUGHNESS: 39}, {})
	_sync(actor, "realized hydrated population", 2)
	# register_actor also supports an existing projection. A loaded population
	# record copies inputs into that SAME already-bound component.
	_gecs.upsert_population_record({"actor_id": id, "stable_id": id, "realization_state": "realized", "vitals": _vitals(actor).durable_state(), "vitals_inputs": {"toughness": 1.0, "healing_rate": 7.0}})
	_gecs.register_actor(actor)
	_sync(actor, "population hydration on existing projection", 2)
	var vitals := _vitals(actor)
	vitals.blunt_damage = 30.0
	vitals.blood = 80.0
	vitals.bleed_rate = 0.5
	VitalsStateMachine.recalculate(vitals, _inputs(actor).toughness)
	var expected := CGameActorVitals.new()
	expected.apply_durable_state(vitals.durable_state())
	var durable_inputs := _inputs(actor).durable_state()
	_gecs.unregister_actor(actor)
	actor.queue_free()
	await process_frame
	_expect(_gecs.get_population_record(id).get("vitals_inputs", {}) == durable_inputs, "Derealization copies exact resolver inputs")
	VitalsStateMachine.tick(expected, float(durable_inputs.toughness), float(durable_inputs.healing_rate), 0.05)
	_gecs.world.process(0.05)
	var record := _gecs.get_population_record(id)
	_expect(record.get("vitals", {}) == expected.durable_state(), "Unloaded durable simulation continues with retained inputs and no projection")
	actor = _actor(id)
	actor.get_stats().hydrate_skill_progress({SkillRules.ATTRIBUTE_TOUGHNESS: 44}, {})
	_sync(actor, "re-realized hydrated identity first pass", 2)
	actor.get_stats().skill_set.set_skill_level(SkillRules.ATTRIBUTE_TOUGHNESS, 45)
	_sync(actor, "re-realized actor continues updating", 2)
	_gecs.unregister_actor(actor)
	actor.queue_free()
	await process_frame

func _actor(id: String, toughness := 0) -> CountingActor:
	var actor := CountingActor.new()
	actor.stable_id = id
	if toughness > 0:
		actor.starting_skill_levels = {SkillRules.ATTRIBUTE_TOUGHNESS: toughness}
	_scene.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	_gecs.register_actor(actor)
	return actor

func _modifier(stat: String, additive: float, multiplier: float) -> CountingModifier:
	var modifier := CountingModifier.new()
	modifier.stat_name = stat
	modifier.add = additive
	modifier.mul = multiplier
	return modifier

func _item(slot: String, modifiers: Array[ItemStatModifier]) -> ItemDefinition:
	var item := ItemDefinition.new()
	item.equip_slot = slot
	item.stat_modifiers = modifiers
	return item

func _inputs(actor: WorldActor) -> CGameActorVitalsInputs:
	return _gecs.get_actor_entity(actor).get_component(CGameActorVitalsInputs)

func _vitals(actor: WorldActor) -> CGameActorVitals:
	return _gecs.get_actor_entity(actor).get_component(CGameActorVitals)

func _sync(actor: CountingActor, label: String, expected_derivations: int) -> void:
	var stats := actor.get_stats() as CountingStats
	var before := stats.derivations
	_gecs.world.process(0.0)
	_expect(stats.derivations - before == expected_derivations, "%s: expected %d full derivations, observed %d" % [label, expected_derivations, stats.derivations - before])
	_matches(actor, label)

func _matches(actor: CountingActor, label: String) -> void:
	var expected := (actor.get_stats() as CountingStats).uncached_inputs()
	var inputs := _inputs(actor)
	_expect(inputs.toughness == expected[0] and inputs.healing_rate == expected[1] and not inputs.dirty, "%s: inputs must equal the uncached authoritative resolver" % label)

func _derivations() -> int:
	var result := 0
	for actor in _actors:
		result += (actor.get_stats() as CountingStats).derivations
	return result

func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)

func _finalize() -> void:
	if FileAccess.file_exists(HYDRATED_ITEM_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(HYDRATED_ITEM_PATH))
