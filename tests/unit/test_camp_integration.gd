extends GutTest

const CAMPS = preload("res://features/camps/sim/camp_controller.gd")
const MARKER = preload("res://features/camps/projection/camp_marker.gd")
const FACTION = preload("res://features/factions/resources/factions/roaming_desert_thugs.tres")

var _root: Node3D
var _context: BootstrapContext
var _gecs: GecsWorldController
var _population: PopulationController
var _camps: Node
var _clock: WorldTimeController

func before_each() -> void:
	_root = Node3D.new()
	add_child_autofree(_root)
	_context = BootstrapContext.new(_root)
	_gecs = GecsWorldController.new()
	_population = PopulationController.new()
	_clock = WorldTimeController.new()
	var factions := FactionController.new()
	var squads := WorldSimSquadController.new()
	_camps = CAMPS.new()
	for pair in [[&"gecs_world", _gecs], [&"population", _population], [&"world_time", _clock], [&"faction", factions], [&"world_sim_squad", squads], [&"camps", _camps]]:
		_root.add_child(pair[1])
		_context.register(pair[0], pair[1])
		pair[1].set_process(false)
	for node in [_gecs, _population, _clock, factions, squads, _camps]:
		node.initialize(_context)

func _generate() -> Dictionary:
	var marker = MARKER.new()
	marker.camp_id = "test.camp"

	marker.squad_count = 2
	marker.squad_size = 3
	_root.add_child(marker)
	_camps.register_marker(marker)
	return _gecs.get_camp_state(marker.camp_id)

func test_generation_is_idempotent_armed_and_uses_real_stock() -> void:
	var state := _generate()
	assert_eq(state.slots.size(), 16)
	assert_eq(_gecs.get_world_sim_squads().size(), 2)
	var before := state.duplicate(true)
	_camps.register_marker(_camps.get("_markers")["test.camp"])
	assert_eq(_gecs.get_camp_state("test.camp"), before)
	var humans := 0
	var desert := 0
	for slot in state.slots:
		var record := _population.get_actor_record(slot.actor_id)
		assert_false(record.available_for_work)
		assert_true(record.equipment_slots.has("weapon"))
		var race: String = str(record.appearance.get("character_race", ""))
		if race.ends_with("/human.tres"):
			humans += 1
		elif race.ends_with("/desert_puglin.tres"):
			desert += 1
	assert_gt(humans, 0)
	assert_gt(desert, 0)
	for furnishing in state.furnishings:
		assert_true(ResourceLoader.exists(furnishing.scene))
		if furnishing.purpose == "container":
			assert_gt(furnishing.stock.size(), 0)
			for item in furnishing.stock:
				assert_true(ResourceLoader.exists(item.item_path))

func test_save_round_trip_retains_roster_loot_and_clear_state() -> void:
	var state := _generate()
	state.status = "cleared"
	state.cleared_at = 320.0
	_gecs.upsert_camp_state(state)
	var path := "user://camp-roundtrip.tres"
	assert_true(_gecs.save_gecs_world(path))
	var expected := _gecs.get_camp_state("test.camp")
	state.status = "empty"
	_gecs.upsert_camp_state(state)
	assert_true(_gecs.load_gecs_world(path))
	var restored := _gecs.get_camp_state("test.camp")
	# Text resources round double-precision angles; all identities/stock stay exact.
	assert_eq(restored.furnishings.size(), expected.furnishings.size())
	for index in mini(restored.furnishings.size(), expected.furnishings.size()):
		assert_almost_eq(float(restored.furnishings[index].yaw), float(expected.furnishings[index].yaw), 0.000000000001)
		restored.furnishings[index].yaw = expected.furnishings[index].yaw
	assert_eq_deep(restored, expected)

func test_seats_form_an_inward_facing_fire_circle_with_clear_access() -> void:
	var state := _generate()
	for seed in 12:
		state.seed = seed
		var layout: Array = _camps._roll_layout(state, load(str(state.type_path)))
		var seats := 0
		for entry in layout:
			if entry.purpose != "seat":
				continue
			seats += 1
			assert_between(entry.offset.length(), 2.2, 3.0, "stools belong beside the main fire")
			_assert_seat_faces_fire(entry, layout)
			for other in layout:
				if other.id != entry.id:
					assert_gte(entry.offset.distance_to(other.offset), 1.5, "seat approach stays clear")
		assert_gte(seats, 2)

func _assert_seat_faces_fire(entry: Dictionary, layout: Array) -> void:
	var seat := (load(str(entry.scene)) as PackedScene).instantiate() as SittableSeat
	_root.add_child(seat)
	seat.position = entry.offset
	seat.rotation.y = float(entry.yaw)
	var closest := Vector3.INF
	var distance := INF
	for other in layout:
		if str(other.purpose) not in ["center", "fire"]:
			continue
		var delta: Vector3 = other.offset - entry.offset
		delta.y = 0.0
		if delta.length_squared() < distance:
			distance = delta.length_squared()
			closest = delta
	var facing := Vector3.FORWARD.rotated(Vector3.UP, seat.get_seat_rotation().y)
	assert_gt(facing.dot(closest.normalized()), 0.99, "actual seated actor faces nearest fire")
	seat.free()

func test_seating_orientation_migration_preserves_layout_and_faces_adjacent_fire() -> void:
	var state := _generate()
	state.layout_version = 3
	var seat: Dictionary = state.furnishings.filter(func(entry): return entry.purpose == "seat")[0]
	var fire: Dictionary = state.furnishings.filter(func(entry): return entry.purpose == "fire")[0]
	seat.offset = Vector3(4.0, 0.0, 2.0)
	fire.offset = Vector3(6.0, 0.0, 2.0)
	seat.yaw = 0.0
	var before := state.duplicate(true)
	_gecs.upsert_camp_state(state)
	_camps.register_marker(_camps.get("_markers")["test.camp"])
	var after: Dictionary = _gecs.get_camp_state("test.camp")
	assert_gt(int(after.layout_version), 3)
	assert_eq(after.slots, before.slots)
	assert_eq(after.furnishings.size(), before.furnishings.size())
	for index in after.furnishings.size():
		var entry: Dictionary = after.furnishings[index]
		assert_eq(entry.id, before.furnishings[index].id)
		assert_eq(entry.stock, before.furnishings[index].stock)
		assert_eq(entry.offset, before.furnishings[index].offset, "orientation repair must not rearrange camp")
		if entry.purpose == "seat":
			_assert_seat_faces_fire(entry, after.furnishings)
		else:
			assert_eq(entry.yaw, before.furnishings[index].yaw)
	_camps.register_marker(_camps.get("_markers")["test.camp"])
	assert_eq(_gecs.get_camp_state("test.camp"), after, "orientation migration is idempotent")

func test_faction_is_hostile_to_others_not_itself() -> void:
	var faction = _context.require(&"faction")
	faction.register_faction(FACTION)
	assert_true(faction.are_hostile("roaming_desert_thugs", "Player"))
	assert_false(faction.are_hostile("roaming_desert_thugs", "roaming_desert_thugs"))
	assert_has(_gecs.get_faction_state().permanently_hostile_faction_ids, "roaming_desert_thugs", "batched combat receives hostile-to-all setting")

func test_replacement_does_not_lose_members_to_old_patrol_snapshot() -> void:
	var state := _generate()
	var victim: String = state.slots[-1].actor_id
	_population.update_actor_record(victim, {"life_state": NpcRules.LifeState.DEAD})
	_camps.advance_camp("test.camp", 0.0)
	var stale := _gecs.get_world_sim_squads()
	_clock.total_world_minutes = 10080.0
	_camps.world_sim_tick(0.5, _gecs, stale, Vector3.INF, 120.0)
	for squad in _gecs.get_world_sim_squads():
		assert_eq(int(squad.member_count), 3, "replacement survives patrol retarget")
	state = _gecs.get_camp_state("test.camp")
	assert_ne(str(state.slots[-1].actor_id), victim)
	assert_eq(int(_population.get_actor_record(victim).life_state), NpcRules.LifeState.DEAD)

func test_offscreen_skirmish_has_durable_casualties_and_cooldown() -> void:
	var combat := FactionWorldSimController.new()
	_root.add_child(combat)
	_context.register(&"faction_world_sim", combat)
	combat.initialize(_context)
	combat.set_process(false)
	_generate()
	_gecs.upsert_settlement_state("test.town", {"faction_id": "Player", "world_position": Vector3.ZERO, "radius": 30.0})
	var squad: Dictionary = _gecs.get_world_sim_squads()[0]
	_camps.resolve_offscreen_skirmish(squad)
	assert_lt(int(squad.member_count), 3)
	var alive := 0
	for record in _population.get_records_for_squad(str(squad.squad_id)):
		if int(record.life_state) != NpcRules.LifeState.DEAD:
			alive += 1
	assert_eq(alive, int(squad.member_count))
	var survivors := int(squad.member_count)
	_camps.resolve_offscreen_skirmish(squad)
	assert_eq(int(squad.member_count), survivors, "one skirmish per cooldown")
	assert_gt(float(_gecs.get_camp_state("test.camp").skirmish_after[squad.squad_id]), _clock.total_world_minutes)

func test_last_death_clears_without_waiting_for_next_visit() -> void:
	var state := _generate()
	_clock.total_world_minutes = 1234.0
	for slot in state.slots:
		_population.mark_record_dead(str(slot.actor_id))
	state = _gecs.get_camp_state("test.camp")
	assert_eq(str(state.status), "cleared")
	assert_eq(float(state.cleared_at), 1234.0)

func test_crowded_layout_omits_props_instead_of_overlapping() -> void:
	var state := _generate()
	state.camp_radius = 4.0
	state.resident_count = 100
	var layout: Array = _camps._roll_layout(state, load(str(state.type_path)))
	var closest := INF
	for index in layout.size():
		for previous in index:
			closest = minf(closest, layout[index].offset.distance_to(layout[previous].offset))
	assert_gte(closest, 1.5, "bounded placement never accepts an occupied point")
	assert_eq(layout[0].purpose, "center")

func test_faction_race_weights_also_apply_to_non_camp_squads() -> void:
	var combat := FactionWorldSimController.new()
	_root.add_child(combat)
	combat.set_process(false)
	var definition: Resource = FACTION.duplicate()
	var weights: Dictionary[String, float] = {"desert_puglin": 1.0}
	definition.race_weights = weights
	var records: Array = combat._generate_squad_records(_population, definition, "roaming_desert_thugs", "test.generic.patrol", 4, [], Color.WHITE)
	assert_eq(records.size(), 4)
	for record in records:
		assert_eq(str(record.appearance.character_race), "res://features/actors/resources/character_races/desert_puglin.tres")

func test_size_presets_stay_compact_with_large_roaming_radius() -> void:
	var previous_count := 0
	for size in 3:
		var marker = MARKER.new()
		marker.camp_id = "size.%d" % size
		marker.set("camp_size", size)
		marker.population = 99 # Old scene fields must not override the selected size.
		marker.camp_radius = 100.0
		marker.operational_radius = 50000.0
		_root.add_child(marker)
		_camps.register_marker(marker)
		var state: Dictionary = _gecs.get_camp_state(marker.camp_id)
		assert_eq(int(state.population_limit), [8, 16, 24][size])
		assert_eq(float(state.camp_radius), [6.0, 8.0, 10.0][size])
		assert_eq(float(state.operational_radius), 50000.0)
		assert_gt(state.furnishings.size(), previous_count)
		previous_count = state.furnishings.size()
		for entry in state.furnishings:
			assert_lte(entry.offset.length(), [6.0, 8.0, 10.0][size])
		var squad: Dictionary = _gecs.get_world_sim_squads().filter(func(value): return value.owner_id == marker.camp_id)[0]
		assert_eq(float(squad.patrol_radius), 50000.0)
		var farthest := 0.0
		for attempt in 8:
			farthest = maxf(farthest, _camps.get_patrol_target(squad).distance_to(marker.global_position))
		assert_gt(farthest, 2000.0, "roaming is not clamped to the old editor maximum")

func test_legacy_sprawling_layout_migrates_without_resetting_history() -> void:
	var state := _generate()
	var victim: String = state.slots[1].actor_id
	_population.mark_record_dead(victim)
	state = _gecs.get_camp_state("test.camp")
	state.erase("layout_version")
	state.camp_radius = 100.0
	for entry in state.furnishings:
		entry.offset *= 12.5
	state.replacement_due = 9876.0
	_gecs.upsert_camp_state(state)
	var before := state.duplicate(true)
	_camps.register_marker(_camps.get("_markers")["test.camp"])
	var after: Dictionary = _gecs.get_camp_state("test.camp")
	assert_eq(float(after.camp_radius), 8.0)
	assert_eq(after.slots, before.slots)
	assert_eq(after.replacement_due, before.replacement_due)
	assert_eq(after.generation_index, before.generation_index)
	assert_eq(int(_population.get_actor_record(victim).life_state), NpcRules.LifeState.DEAD)
	assert_eq(after.furnishings.size(), before.furnishings.size())
	for index in after.furnishings.size():
		assert_eq(after.furnishings[index].id, before.furnishings[index].id)
		assert_eq(after.furnishings[index].stock, before.furnishings[index].stock)
		assert_lte(after.furnishings[index].offset.length(), 8.0)
	_camps.register_marker(_camps.get("_markers")["test.camp"])
	assert_eq(_gecs.get_camp_state("test.camp"), after, "migration is idempotent")
