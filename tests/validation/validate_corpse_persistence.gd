extends "res://tests/validation/test_case.gd"
## Ordinary human death through real capabilities, corpse LOD and GECS disk IO.
## Cremation is covered separately by validate_body_furnace_auto_burn.gd.
const ACTOR_ID := "validation.corpse.person"
const LOOT := preload("res://features/inventory/resources/items/tomato_seeds.tres")
const C_POPULATION := preload("res://features/world_sim/sim/population/c_game_population_record.gd")
const C_VITALS := preload("res://features/actors/sim/c_game_actor_vitals.gd")
const STACK_ID := "validation.corpse.loot"
const LOOT_METADATA := {"origin": "corpse", "quality": 0.625}
var _failures: Array[String] = []
var _checks := 0
var _gecs: GecsWorldController
var _population: PopulationController
var _lod: PopulationRealizationController


func _initialize() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var context := BootstrapContext.new(scene)
	BootstrapContext.active = context
	_gecs = GecsWorldController.new()
	_population = PopulationController.new()
	_lod = PopulationRealizationController.new()
	var factions := FactionController.new()
	var query := ActorQueryController.new()
	var realizer := PopulationCharacterRealizer.new()
	for service in [_gecs, query, _population, factions, realizer, _lod]:
		context.register(service.SERVICE_ID, service)
		scene.add_child(service)
	_gecs.initialize(context)
	_gecs.set_process(false)
	query.initialize(context)
	_population.initialize(context)
	realizer.initialize(context)
	_lod.initialize(context)
	_lod.set_process(false)
	_lod.set_realization_retention_seconds(0.0)
	var actor := HumanoidCharacter.new()
	actor.name = "OrdinaryHuman"
	actor.stable_id = ACTOR_ID
	realizer._ensure_projection_bootstrap(actor)
	scene.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	_population.register_actor(actor, "corpse_town")
	# Seed real GECS vitals before exercising the ordinary death command.
	_gecs.world.process(0.05)
	var assigned := _population.assign_record_to_slot(ACTOR_ID, {
		"settlement_id": "corpse_town", "assignment_domain": "employment",
		"slot_id": "corpse_town.worker", "role_id": "worker",
	}, true)
	_expect(not assigned.is_empty() and not assigned.get("assignments", {}).is_empty(), "living fixture holds an assignment that death must release")
	var death_transform := Transform3D(Basis.from_euler(Vector3(0.0, 0.7, 0.0)), Vector3(8.25, 2.5, -6.75))
	actor.global_transform = death_transform
	actor.get_inventory().hydrate_population_entries([{
		"item_id": LOOT.resource_path, "count": 7, "grid_position": Vector2i(2, 1),
		"stack_id": STACK_ID, "contained_item_counts": {}, "metadata": LOOT_METADATA,
	}])
	_expect(actor.life_state == NpcRules.LifeState.ALIVE and actor.inventory.entries.size() == 1 and actor.inventory.count_item(LOOT) == 7, "living fixture has one valid loot stack before death")
	var deaths: Array[String] = []
	_population.person_died.connect(func(id: String): deaths.append(id))
	actor.force_kill()
	_expect(actor.life_state == NpcRules.LifeState.DEAD, "ordinary force_kill terminates the live human")
	_expect(deaths == [ACTOR_ID], "death publishes the permanent identity once")
	_check_record(death_transform, "immediate death")
	var original_parent := actor.get_parent()
	_lod._resync_corpses([death_transform.origin])
	_expect(actor.get_parent() == original_parent and actor.global_transform.is_equal_approx(death_transform), "near corpse reconciliation does not reparent or displace a live death")
	# Consume some loot before unloading: a saved corpse must not reseed it.
	_expect(actor.inventory.remove_item_count(LOOT, 2), "remove two seeds from corpse before LOD")
	var moved_transform := Transform3D(Basis.from_euler(Vector3(0.0, -1.1, 0.0)), Vector3(12.5, 3.25, -9.5))
	actor.global_transform = moved_transform
	var old_id := actor.get_instance_id()
	_lod._resync_corpses([moved_transform.origin + Vector3(2000, 0, 0)])
	await process_frame
	await process_frame
	_expect(not is_instance_id_valid(old_id) and _population.get_live_actor(ACTOR_ID) == null, "far corpse LOD actually destroys the old projection")
	_check_record(moved_transform, "unloaded corpse")
	_check_ledger_loot("unloaded corpse")
	_lod._resync_corpses([moved_transform.origin])
	var restored := _population.get_live_actor(ACTOR_ID) as HumanoidCharacter
	_check_projection(restored, moved_transform, "LOD return")
	if restored != null:
		_expect(restored.get_instance_id() != old_id, "LOD return builds a fresh projection of the same person")
		_lod._resync_corpses([moved_transform.origin])
		_expect(_population.get_live_actor(ACTOR_ID) == restored, "repeated near reconciliation reuses the existing corpse")
	var save_path := "user://ordinary_corpse_%d.tres" % OS.get_process_id()
	_expect(_gecs.save_gecs_world(save_path), "save corpse and its remaining loot through GECS IO")
	_lod._resync_corpses([moved_transform.origin + Vector3(2000, 0, 0)])
	await process_frame
	await process_frame
	_expect(_population.get_live_actor(ACTOR_ID) == null, "second LOD unload removes the re-realized corpse")
	_expect(_gecs.load_gecs_world(save_path), "load saved corpse into the real GECS world")
	await process_frame
	await process_frame
	_check_record(moved_transform, "disk load")
	_check_ledger_loot("disk load")
	_lod._resync_corpses([moved_transform.origin])
	restored = _population.get_live_actor(ACTOR_ID) as HumanoidCharacter
	_check_projection(restored, moved_transform, "post-load return")
	_expect(_gecs.get_population_records().keys() == [ACTOR_ID], "unload and load retain exactly one permanent person")
	var corpse_ids: Array[String] = []
	for record in _gecs.get_corpse_population_records_near(moved_transform.origin, 1.0):
		corpse_ids.append(str(record.get("actor_id", "")))
	_expect(corpse_ids == [ACTOR_ID], "spatial corpse index returns the same person exactly once")
	var projections := 0
	for child in scene.get_node("CorpseProjections").get_children():
		if child is WorldActor and child.stable_id == ACTOR_ID:
			projections += 1
	_expect(projections == 1, "post-load corpse root contains no duplicate body")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	scene.queue_free()
	await process_frame
	await process_frame
	BootstrapContext.active = null
	for failure in _failures:
		push_error(failure)
	print("CORPSE_PERSISTENCE_%s checks=%d" % ["OK" if _failures.is_empty() else "FAILED", _checks])
	quit(0 if _failures.is_empty() else 1)


func _check_record(expected: Transform3D, label: String) -> void:
	var record := _gecs.get_population_record(ACTOR_ID)
	_expect(str(record.get("body_state", "")) == "corpse" and int(record.get("life_state", -1)) == NpcRules.LifeState.DEAD, label + ": durable death and body disposition")
	# Unseeded ledger records legitimately omit the vitals dictionary; inspect
	# the actual authoritative component rather than requiring a serialization detail.
	var matching_vitals := 0
	for entity in _gecs.world.query.with_all([C_POPULATION, C_VITALS]).execute():
		if str(entity.get_component(C_POPULATION).actor_id) == ACTOR_ID:
			matching_vitals += 1
			_expect(entity.get_component(C_VITALS).life_state == NpcRules.LifeState.DEAD, label + ": authoritative vitals remain dead")
	_expect(matching_vitals == 1, label + ": exactly one authoritative person/vitals entity")
	_expect(bool(record.get("last_world_transform_initialized", false)) and (record.get("last_world_transform", Transform3D.IDENTITY) as Transform3D).is_equal_approx(expected), label + ": exact body position and facing")
	_expect((record.get("assignments", {}) as Dictionary).is_empty(), label + ": corpse has no live assignment")


func _check_ledger_loot(label: String) -> void:
	var entries: Array = _gecs.get_population_record(ACTOR_ID).get("inventory_entries", [])
	_expect(entries.size() == 1, label + ": exactly one remaining loot stack")
	if entries.size() != 1:
		return
	var entry: Dictionary = entries[0]
	_expect(str(entry.get("stack_id", "")) == STACK_ID and int(entry.get("count", -1)) == 5 and entry.get("metadata", {}) == LOOT_METADATA, label + ": consumed loot stays consumed; identity and metadata survive")


func _check_projection(actor: HumanoidCharacter, expected: Transform3D, label: String) -> void:
	_expect(actor != null, label + ": production corpse realizer returns a human")
	if actor == null:
		return
	actor.set_process(false)
	actor.set_physics_process(false)
	_gecs.world.process(0.05)
	_expect(_gecs.get_actor_entity(actor) != null, label + ": re-realized corpse is bound to the real GECS actor lifecycle")
	_expect(actor.stable_id == ACTOR_ID and actor.life_state == NpcRules.LifeState.DEAD, label + ": same dead identity, not a replacement living person")
	_expect(actor.global_transform.is_equal_approx(expected), label + ": reconstructed body position and facing")
	_expect(actor.inventory.entries.size() == 1 and actor.inventory.count_item(LOOT) == 5, label + ": remaining loot restored without duplication")
	if actor.inventory.entries.size() == 1:
		var entry = actor.inventory.entries[0]
		_expect(entry.stack_id == STACK_ID and entry.metadata == LOOT_METADATA and entry.grid_position == Vector2i(2, 1), label + ": loot stable ID, metadata and grid position")


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
