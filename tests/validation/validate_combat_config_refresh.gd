extends "res://tests/validation/test_case.gd"

## 40 real actors previously refreshed together every 121 calls (10.811–12.812 ms
## in the measured 20v20 run). Count actual authoring, not a machine-dependent timer.
class CountingActor:
	extends WorldActor
	var writes := 0
	var config_reads := 0
	var last_write_frame := -1

	func get_attack_range() -> float:
		config_reads += 1 # Config authoring reads this; delegate the real value.
		return super.get_attack_range()

	func write_combat_loadout(loadout: CGameCombatLoadout) -> void:
		writes += 1
		last_write_frame = Engine.get_process_frames()
		super.write_combat_loadout(loadout)

	func expected_loadout() -> CGameCombatLoadout:
		var result := CGameCombatLoadout.new()
		super.write_combat_loadout(result)
		return result

const ACTOR_COUNT := 40
const SWORD = preload("res://features/inventory/resources/items/bronze_sword.tres")

var _failures: Array[String] = []
var _checks := 0
var _scene: Node3D
var _gecs: GecsWorldController
var _actors: Array[CountingActor] = []
var _interval := 0

func _initialize() -> void:
	_interval = GameCombatStateSyncSystem.config_sync_interval_frames
	_scene = Node3D.new()
	root.add_child(_scene)
	var context := BootstrapContext.new(_scene)
	BootstrapContext.active = context
	_gecs = GecsWorldController.new()
	context.register(GecsWorldController.SERVICE_ID, _gecs)
	_scene.add_child(_gecs)
	_gecs.initialize(context)
	_gecs.set_process(false)
	# Real registered systems and GECS archetype/column dispatch; unrelated combat
	# consequences are exercised by their own validators, not this cadence fixture.
	for system in _gecs.world.systems_by_group[""]:
		system.active = system is GameActorSyncSystem or system is GameCombatStateSyncSystem or system is GameCombatScoreSystem
	for i in range(ACTOR_COUNT):
		_actors.append(_actor("refresh.%d" % i))
	_gecs.world.process(1.0 / 60.0)
	for actor in _actors:
		_expect(actor.writes == 1, "First-seen actor must author immediately: %s" % actor.stable_id)
		_expect(_matches_authority(actor), "Initial loadout and derived score must use WorldActor: %s" % actor.stable_id)
	await _steady_frames()
	await _reordered_batches()
	await _membership_churn()
	await _projection_lifecycle()
	await _independent_world()
	_public_orders()
	await _configured_interval()
	await _empty_query()
	GameCombatStateSyncSystem.config_sync_interval_frames = _interval
	_scene.queue_free()
	await process_frame
	BootstrapContext.active = null
	for failure in _failures:
		push_error(failure)
	print("COMBAT_CONFIG_REFRESH_%s checks=%d" % ["OK" if _failures.is_empty() else "FAILED", _checks])
	quit(0 if _failures.is_empty() else 1)

func _steady_frames() -> void:
	var peak := 0
	var authored := 0
	var max_age := 0
	var initial := _write_count()
	# Mutate through the real equipment/skill capabilities after initial hydration.
	for actor in _actors:
		actor.equip_item_to_slot(SWORD, ItemDefinition.EQUIP_SLOT_WEAPON)
		actor.set_skill_level(SkillRules.ATTRIBUTE_STRENGTH, 31)
		actor.set_skill_level(SkillRules.COMBAT_SWORDS_ONE_HANDED, 23)
	for frame in range(_interval * 3):
		await _next_frame()
		for actor in _actors:
			actor.set_sneaking_enabled(frame % 2 == 0)
		var before := _write_count()
		_gecs.world.process(1.0 / 60.0)
		var work := _write_count() - before
		peak = maxi(peak, work)
		authored += work
		for actor in _actors:
			max_age = maxi(max_age, Engine.get_process_frames() - actor.last_write_frame)
			var entity = _gecs.get_actor_entity(actor)
			_expect(entity.get_component(CGameCombatState).sneaking == actor.sneaking, "Volatile state must sync on every frame")
		if frame == _interval - 1:
			for actor in _actors:
				_expect(_matches_authority(actor), "Equipment/stat edits must reach config within the interval: %s" % actor.stable_id)
	_expect(peak <= ceili(float(ACTOR_COUNT) / _interval), "No cohort sweep: peak refreshes=%d, expected <=%d" % [peak, ceili(float(ACTOR_COUNT) / _interval)])
	_expect(max_age < _interval, "Refresh age must stay below %d process frames, observed %d" % [_interval, max_age])
	_expect(authored == ACTOR_COUNT * 3 and _write_count() - initial == authored, "Steady work must be one refresh per actor per interval, not one actor every frame: %d" % authored)
	for actor in _actors:
		_expect(actor.writes == 4, "Every actor must receive all three refreshes: %s writes=%d" % [actor.stable_id, actor.writes])
		_expect(actor.config_reads == actor.writes, "Config authoring must be spread with loadout authoring, not run every frame")
	print("REFRESH_STEADY actors=%d frames=%d authored=%d peak=%d max_age=%d" % [ACTOR_COUNT, _interval * 3, authored, peak, max_age])

func _reordered_batches() -> void:
	var initial := _write_count()
	var before_by_actor := {}
	var peak := 0
	var max_age := 0
	var multiple_archetypes := false
	for actor in _actors:
		before_by_actor[actor.get_instance_id()] = actor.writes
		actor.unequip_item_from_slot(ItemDefinition.EQUIP_SLOT_WEAPON)
		actor.aggressive_scan_radius += 2.0
		actor.set_skill_level(SkillRules.ATTRIBUTE_TOUGHNESS, 17)
	for frame in range(_interval * 2):
		await process_frame
		# Real archetype migration performs GECS swap-removal/reordering and keeps
		# columns aligned. Never shuffle entity arrays independently of columns.
		var entity = _gecs.get_actor_entity(_actors[frame % ACTOR_COUNT])
		if entity.has_component(CGameMovementState):
			entity.remove_component(CGameMovementState)
		else:
			entity.add_component(CGameMovementState.new())
		var live_batches := 0
		var sync := _gecs.find_child("GameCombatStateSyncSystem", true, false) as GameCombatStateSyncSystem
		for archetype in sync.query().archetypes():
			if not archetype.entities.is_empty():
				live_batches += 1
		multiple_archetypes = multiple_archetypes or live_batches > 1
		var before := _write_count()
		# Repeated world processing within the SAME engine frame must not advance
		# the refresh clock, even when each pass invokes several archetype batches.
		for pass_index in range(2):
			var observer := _actors[0]
			var target := _actors[1] if (frame + pass_index) % 2 == 0 else _actors[2]
			observer.clear_all_personal_hostility()
			observer.mark_hostile(target)
			observer.set_system_target_bridge(target.get_instance_id(), Engine.get_process_frames())
			observer._last_direct_attacker_id = target.get_instance_id()
			_gecs.world.process(1.0 / 60.0)
			var state = _gecs.get_actor_entity(observer).get_component(CGameCombatState)
			_expect(state.current_target_id == target.get_instance_id() and state.current_target_actor_id == target.stable_id, "Target state must update even within the same engine frame")
			_expect(state.last_direct_attacker_actor_id == target.stable_id and state.personal_hostile_actor_ids == PackedStringArray([target.stable_id]), "Attacker/grudge state must update independently of config cadence")
		peak = maxi(peak, _write_count() - before)
		for actor in _actors:
			max_age = maxi(max_age, Engine.get_process_frames() - actor.last_write_frame)
	_expect(multiple_archetypes, "Fixture must really dispatch multiple matching archetypes")
	_expect(peak <= ceili(float(ACTOR_COUNT) / _interval), "Reordered/multiple batches must not multiply refresh work: peak=%d" % peak)
	_expect(max_age < _interval, "Query migration must not starve actors: age=%d" % max_age)
	_expect(_write_count() - initial == ACTOR_COUNT * 2, "Batch callbacks must not be counted as global frames")
	for actor in _actors:
		_expect(actor.writes - int(before_by_actor[actor.get_instance_id()]) == 2, "Reordering must preserve each actor's refresh coverage")
		_expect(actor.config_reads == actor.writes, "Batch dispatch must not multiply config-only authoring")
		_expect(_matches_authority(actor), "Unequip/toughness/config edits must propagate after reordering")
	print("REFRESH_BATCHES frames=%d authored=%d peak=%d max_age=%d" % [_interval * 2, _write_count() - initial, peak, max_age])

func _membership_churn() -> void:
	var peak_recurring := 0
	var max_age := 0
	# More replacements than phases exposes unreclaimed slots and unstable cursors.
	# Keep 40 actors: first-seen work is immediate; recurring work stays bounded.
	for frame in range(_interval + ACTOR_COUNT):
		await _next_frame()
		var index := ACTOR_COUNT - 1 - frame % 2
		var old := _actors[index]
		var actor_id := old.stable_id
		_gecs.unregister_actor(old)
		old.free()
		_actors[index] = _actor(actor_id)
		var before := _write_count()
		_gecs.world.process(1.0 / 60.0)
		_expect(_actors[index].writes == 1 and _matches_authority(_actors[index]), "Churn must hydrate each new projection on its first frame")
		peak_recurring = maxi(peak_recurring, _write_count() - before - 1)
		for actor in _actors:
			max_age = maxi(max_age, Engine.get_process_frames() - actor.last_write_frame)
	_expect(peak_recurring <= ceili(float(ACTOR_COUNT) / _interval), "Membership churn must reclaim departed phases without cohort sweeps")
	_expect(max_age < _interval, "Membership churn must not delay a surviving actor beyond the interval")
	print("REFRESH_CHURN replacements=%d recurring_peak=%d max_age=%d" % [_interval + ACTOR_COUNT, peak_recurring, max_age])

func _projection_lifecycle() -> void:
	await process_frame
	var late := _actor("refresh.late")
	late.set_skill_level(SkillRules.ATTRIBUTE_STRENGTH, 47)
	_gecs.world.process(1.0 / 60.0)
	_expect(late.writes == 1 and _matches_authority(late), "Late registration must hydrate on its first seen batch")
	# Ordinary unregister/free/re-realize of the same durable identity.
	_gecs.unregister_actor(late)
	late.queue_free()
	await process_frame
	_gecs.world.process(1.0 / 60.0)
	late = _actor("refresh.late")
	late.equip_item_to_slot(SWORD, ItemDefinition.EQUIP_SLOT_WEAPON)
	_gecs.world.process(1.0 / 60.0)
	_expect(late.writes == 1 and _matches_authority(late), "Re-realized identity must not inherit its old projection's cadence or loadout")
	# Projection can vanish before unregister; get_actor must safely reject it.
	var retained_entity = _gecs.get_actor_entity(late)
	late.queue_free()
	await process_frame
	_gecs.world.process(1.0 / 60.0)
	_expect(retained_entity.get_component(CGameActorNode).get_actor() == null, "Destroyed projection must be absent from its real component")
	late = _actor("refresh.late")
	late.set_skill_level(SkillRules.ATTRIBUTE_DEXTERITY, 43)
	_gecs.world.process(1.0 / 60.0)
	_expect(_gecs.get_actor_entity(late) == retained_entity, "Replacement case must reuse the existing entity/config")
	_expect(late.writes == 1 and _matches_authority(late), "A new node on the same entity must hydrate immediately")
	# Membership can change while the node remains live, too.
	retained_entity.remove_component(CGameCombatConfig)
	await process_frame
	_gecs.world.process(1.0 / 60.0)
	retained_entity.add_component(CGameCombatConfig.new())
	_gecs.world.process(1.0 / 60.0)
	_expect(late.writes == 2 and _matches_authority(late), "New config on a live actor must receive first-seen hydration")
	_gecs.unregister_actor(late)
	late.queue_free()
	await process_frame
	_gecs.world.process(1.0 / 60.0)

func _independent_world() -> void:
	# The same real source actor in a separate world must not share refresh state.
	var other := World.new()
	_scene.add_child(other)
	other.add_system(GameCombatStateSyncSystem.new())
	other.add_system(GameCombatScoreSystem.new())
	other.finalize_system_setup()
	var actor := _actors[0]
	var entity := Entity.new()
	other.add_entity(entity, [CGameActorNode.new(), CGameCombatConfig.new(), CGameCombatState.new(), CGameCombatLoadout.new()])
	# World.add_entity duplicates component resources; hydrate the owned copy,
	# just as GecsWorldController.register_actor does after adding the entity.
	entity.get_component(CGameActorNode).actor = actor
	var config = entity.get_component(CGameCombatConfig)
	var before := actor.writes
	other.process(1.0 / 60.0)
	_expect(actor.writes == before + 1 and config.aggro_scan_radius == actor.aggressive_scan_radius, "Independent world must hydrate without sharing another system's cadence")
	other.queue_free()
	await process_frame

func _public_orders() -> void:
	# GameActorSyncSystem publishes faction.player_order_active every tick. These
	# public commands must not wait for the slow config/loadout refresh to disengage.
	var actor := _actors[0]
	var target := _actors[1]
	actor.set_sneaking_enabled(false)
	target.set_sneaking_enabled(false)
	for member in _actors:
		member.clear_all_personal_hostility()
		member.set_system_target_bridge(0, Engine.get_process_frames())
	# Restore the ordinary shared archetype before exercising targeting (this test
	# is about config scheduling across batches, not changing targeting's query).
	for member in _actors:
		var entity = _gecs.get_actor_entity(member)
		if not entity.has_component(CGameMovementState):
			entity.add_component(CGameMovementState.new())
	var targeting := _gecs.find_child("GameCombatTargetingSystem", true, false) as GameCombatTargetingSystem
	targeting.active = true
	actor.set_move_target(Vector3(12.0, 0.0, 0.0), true)
	_expect(actor.has_active_player_order() and actor.get_current_combat_target() == null, "Public move must disengage immediately")
	_gecs.world.process(0.05)
	var faction = _gecs.get_actor_entity(actor).get_component(CGameActorFaction)
	_expect(faction.player_order_active and actor.get_current_combat_target() == null, "Registered targeting must honor move suppression on the next tick")
	_expect(actor.assign_attack_target(target), "Public attack order must be accepted")
	_expect(not actor.has_active_player_order(), "Attack must release move suppression immediately")
	for _tick in range(20):
		_gecs.world.process(0.05)
	_expect(not faction.player_order_active and actor.get_current_combat_target() == target, "Attack order must acquire through registered targeting without waiting for config refresh")
	actor.set_move_target(Vector3(15.0, 0.0, 0.0), true)
	_gecs.world.process(0.05)
	_expect(faction.player_order_active and actor.get_current_combat_target() == null, "Move must override an acquired combat target")
	actor.stop_movement()
	_gecs.world.process(0.05)
	_expect(not faction.player_order_active and not actor.has_move_target(), "Public stop must release order suppression on the next tick")
	targeting.active = false

func _configured_interval() -> void:
	GameCombatStateSyncSystem.config_sync_interval_frames = 7
	await _next_frame()
	var before := _write_count()
	_gecs.world.process(1.0 / 60.0)
	_expect(_write_count() - before == ACTOR_COUNT, "Explicit interval edit must rehydrate at the next process frame")
	var initial := _write_count()
	var peak := 0
	var max_age := 0
	for _frame in range(14):
		await _next_frame()
		before = _write_count()
		_gecs.world.process(1.0 / 60.0)
		_gecs.world.process(1.0 / 60.0)
		peak = maxi(peak, _write_count() - before)
		for actor in _actors:
			max_age = maxi(max_age, Engine.get_process_frames() - actor.last_write_frame)
	_expect(_write_count() - initial == ACTOR_COUNT * 2 and peak <= ceili(ACTOR_COUNT / 7.0), "Short interval must allocate proportional work, not collide by actor hash")
	_expect(max_age < 7, "Interval setting is measured in process frames, not batches")
	print("REFRESH_TUNING interval=7 frames=14 authored=%d peak=%d max_age=%d" % [_write_count() - initial, peak, max_age])

func _empty_query() -> void:
	for actor in _actors:
		_gecs.unregister_actor(actor)
		actor.free()
	_actors.clear()
	for _frame in range(2):
		await _next_frame()
		_gecs.world.process(1.0 / 60.0)
	# A bounded cache is a lifecycle invariant; all behavior above uses real data.
	var sync := _gecs.find_child("GameCombatStateSyncSystem", true, false) as GameCombatStateSyncSystem
	var entries = sync.get("_config_refreshes")
	_expect(entries is Dictionary and entries.is_empty(), "Empty query must reclaim all projection scheduling entries")
	var reborn := _actor("refresh.empty_world_reborn")
	_gecs.world.process(1.0 / 60.0)
	_expect(reborn.writes == 1 and _matches_authority(reborn), "An empty world must immediately hydrate its next actor")

func _actor(actor_id: String) -> CountingActor:
	var actor := CountingActor.new()
	actor.name = actor_id.replace(".", "_")
	actor.stable_id = actor_id
	actor.combat_stance = NpcRules.CombatStance.AGGRESSIVE
	_scene.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	_gecs.register_actor(actor)
	return actor

func _write_count() -> int:
	var total := 0
	for actor in _actors:
		total += actor.writes
	return total

func _matches_authority(actor: CountingActor) -> bool:
	var expected := actor.expected_loadout()
	var entity = _gecs.get_actor_entity(actor)
	var actual = entity.get_component(CGameCombatLoadout)
	var authored_fields := expected.serialize()
	authored_fields.erase("dirty")
	var actual_fields: Dictionary = actual.serialize()
	actual_fields.erase("dirty")
	if actual_fields != authored_fields:
		return false
	var expected_config := CGameCombatConfig.new()
	var scorer := GameCombatScoreSystem.new()
	scorer.process([entity], [[expected], [expected_config]], 0.0)
	scorer.free()
	var config = entity.get_component(CGameCombatConfig)
	return not actual.dirty and config.aggro_scan_radius == actor.aggressive_scan_radius and is_equal_approx(config.blunt_damage, expected_config.blunt_damage) and is_equal_approx(config.hit_score, expected_config.hit_score) and config.weapon_skill_id == expected_config.weapon_skill_id

func _next_frame() -> void:
	# The deferred host can start before the first process_frame signal, while
	# Engine.get_process_frames() is still zero. Count distinct frames, not signals.
	var previous := Engine.get_process_frames()
	while Engine.get_process_frames() == previous:
		await process_frame

func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition and not _failures.has(message):
		_failures.append(message)
