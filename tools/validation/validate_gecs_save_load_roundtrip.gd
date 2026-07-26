extends SceneTree

const GECS_WORLD_CONTROLLER_PATH := "res://features/core/gecs_world_controller.gd"
const WORLD_TIME_CONTROLLER_PATH := "res://features/core/world_time_controller.gd"

const SAVE_PATH := "user://gecs_save_load_roundtrip_validation.tres"

var _failures: Array[String] = []


class FakeHumanoid:
	extends CharacterBody3D

	var stable_id := ""
	var member_name := "Vitals Actor"
	var faction_name := "RoundtripFaction"
	var squad_name := ""
	var hostile_factions: PackedStringArray = PackedStringArray()
	var combat_stance := NpcRules.CombatStance.DEFENSIVE
	var player_party_member := false
	var life_state := NpcRules.LifeState.ALIVE
	var hp := 100.0
	var max_hp := 100.0
	var blood := 100.0
	var max_blood := 100.0
	var inventory: InventoryData = InventoryData.new(4, 4, 0.0, false)
	var equipped_items: Dictionary = {}

	func assign_attack_target(_target = null) -> void:
		pass


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_remove_file(SAVE_PATH)
	var root_node := Node.new()
	root.add_child(root_node)

	var context := BootstrapContext.new(root_node)

	var bridge = load(GECS_WORLD_CONTROLLER_PATH).new()
	bridge.name = "GecsWorldController"
	root_node.add_child(bridge)
	context.register(bridge.SERVICE_ID, bridge)
	bridge.initialize(context)

	var world_time = load(WORLD_TIME_CONTROLLER_PATH).new()
	world_time.name = "WorldTimeController"
	root_node.add_child(world_time)
	context.register(world_time.SERVICE_ID, world_time)
	world_time.initialize(context)
	world_time.advance_hours(9.5)
	world_time.set_speed_index(2)
	world_time.request_manual_pause()

	var vitals_actor := FakeHumanoid.new()
	vitals_actor.name = "VitalsActor"
	vitals_actor.stable_id = "actor.vitals"
	root_node.add_child(vitals_actor)
	bridge.register_actor(vitals_actor, "roundtrip_town", {"role_id": "guard"})
	vitals_actor.global_position = Vector3(3.0, 0.0, 4.0)
	vitals_actor.hp = 37.0
	vitals_actor.blood = 12.5
	vitals_actor.life_state = NpcRules.LifeState.UNCONSCIOUS

	bridge.upsert_population_record({
		"actor_id": "actor.roundtrip",
		"stable_id": "actor.roundtrip",
		"settlement_id": "roundtrip_town",
		"generation_source": "validation",
		"generation_index": 4,
		"member_name": "Roundtrip Worker",
		"actor_script_path": "res://features/core/party/party_member.gd",
		"character_realizer_id": "settler_common",
		"character_realizer_path": "res://realizers/settler_common.tres",
		"character_realizer_signature": "settler-signature",
		"character_type_id": "soldier",
		"character_type_path": "res://character_types/soldier.tres",
		"character_type_signature": "soldier-signature",
		"faction_id": "RoundtripFaction",
		"role_id": "worker",
		"assigned_slot_id": "roundtrip_town.guard.0",
		"staff_assignment_realized_once": true,
		"life_state": NpcRules.LifeState.DEAD,
		"body_state": "corpse",
		"last_world_position": Vector3(18.0, 0.5, -27.0),
		"last_world_position_initialized": true,
		"last_world_transform": Transform3D(Basis.from_euler(Vector3(0.0, 0.7, 0.0)), Vector3(18.0, 0.5, -27.0)),
		"last_world_transform_initialized": true,
		"realization_state": "ledger",
		"ledger_work_minutes": 90,
		"skill_levels": {SkillRules.MOVEMENT_RUNNING: 5},
		"skill_xp": {SkillRules.MOVEMENT_RUNNING: 12.5},
		"needs_state": {"hunger": 42.25, "fatigue": 71.5, "hunger_stage": 2, "food_effect_rate": 1.75, "food_effect_remaining_seconds": 8.5},
		"movement_state": {"has_move_target": true, "move_target": Vector3(21.0, 0.5, -31.0), "running": false, "sneaking": true, "issued_by_player": true},
		"inventory_entries": [
			{
				"item_id": "res://items/validation/iron_ore.tres",
				"count": 7,
				"grid_position": Vector2i(1, 2),
				"metadata": {"quality": "test"},
			},
		],
		"equipment_slots": {"main_hand": "res://items/validation/hammer.tres"},
	})
	bridge.upsert_population_record({
		"actor_id": "actor.corpse_transform",
		"stable_id": "actor.corpse_transform",
		"settlement_id": "roundtrip_town",
		"member_name": "Moved Corpse",
		"faction_id": "RoundtripFaction",
		"life_state": NpcRules.LifeState.DEAD,
		"body_state": "corpse",
		"last_world_position": Vector3(30.0, 0.0, 30.0),
		"last_world_position_initialized": true,
	})
	var corpse_actor := FakeHumanoid.new()
	corpse_actor.name = "CorpseTransformActor"
	corpse_actor.stable_id = "actor.corpse_transform"
	corpse_actor.life_state = NpcRules.LifeState.DEAD
	root_node.add_child(corpse_actor)
	bridge.register_actor(corpse_actor, "roundtrip_town", {"role_id": "worker"})
	corpse_actor.global_transform = Transform3D(Basis.from_euler(Vector3(0.0, 1.1, 0.0)), Vector3(31.0, 0.75, 29.0))
	bridge.upsert_settlement_state("roundtrip_town", {
		"settlement_id": "roundtrip_town",
		"faction_id": "RoundtripFaction",
		"display_name": "Roundtrip Town",
		"population": 12,
		"population_target": 16,
		"facilities": {"forge": 1},
		"staff_slots": {
			"guard_0": {
				"slot_id": "guard_0",
				"settlement_id": "roundtrip_town",
				"role_id": "guard",
				"filled": true,
				"population_cost": 1,
			},
		},
	})
	bridge.upsert_staff_slot("roundtrip_town", "guard_0", {
		"slot_id": "guard_0",
		"settlement_id": "roundtrip_town",
		"role_id": "guard",
		"filled": true,
		"population_cost": 1,
		"world_position": Vector3(12.0, 1.5, -8.0),
	})
	bridge.record_settlement_event({
		"event_id": "roundtrip:event:1",
		"settlement_id": "roundtrip_town",
		"type": "validation",
		"absolute_minute": 1530,
		"data": {"ok": true},
	})
	bridge.upsert_law_order_state({
		"warrants": {
			"actor.roundtrip": {
				"RoundtripFaction": {
					"case_id": "case.roundtrip",
					"actor_key": "actor.roundtrip",
					"faction_id": "RoundtripFaction",
					"settlement_id": "roundtrip_town",
					"state": "wanted",
					"bad_person_points": 12,
					"sentence_minutes": 600,
					"crimes": [{"crime_type": "theft", "severity": 12}],
				},
			},
		},
		"prisoner_records": {
			"prisoner.roundtrip": {
				"case_id": "case.prisoner",
				"actor_key": "prisoner.roundtrip",
				"faction_id": "RoundtripFaction",
				"state": "jailed",
				"jail_id": "roundtrip_jail",
				"release_at_minute": 2200,
			},
		},
	})
	bridge.upsert_faction_state({
		"reputations": {"Player:RoundtripFaction": -25},
		"favor_points": {"RoundtripFaction": 3},
		"diplomatic_states": {"Player:RoundtripFaction": {"state": "truce", "primary_faction_id": "Player", "secondary_faction_id": "RoundtripFaction"}},
		"help_allies": true,
	})
	bridge.upsert_world_squad_state({
		"squad_index": 3,
		"active_squads": {
			"squad_0003": {
				"squad_id": "squad_0003",
				"source_settlement_id": "roundtrip_town",
				"target_settlement_id": "other_town",
				"phase_id": "planning",
				"phase_elapsed": 4.0,
				"resolved": false,
				"actor_paths": [NodePath("/root/TestActor")],
			},
		},
	})
	bridge.upsert_world_event_state({
		"active_prompt_event_id": "conflict.roundtrip",
		"events": {
			"conflict.roundtrip": {
				"event_id": "conflict.roundtrip",
				"title": "Roundtrip Conflict",
				"side_a_faction_id": "RoundtripFaction",
				"side_b_faction_id": "OtherFaction",
				"committed": true,
				"chosen_faction_id": "RoundtripFaction",
				"opposed_faction_id": "OtherFaction",
				"participation_seconds": 9.5,
			},
		},
	})
	bridge.upsert_job_system_state({"sim_time": 12.75})
	bridge.upsert_ledger_simulation_state({"last_processed_minute": 1530, "last_batch_summary": {"updated_actor_count": 2}})
	bridge.upsert_ai_scheduler_state({"sim_time": 7.25, "default_tick_interval_seconds": 0.35, "default_tick_jitter_seconds": 0.05})
	bridge.upsert_population_realization_state({"default_realization_policy": "near_player", "near_player_radius": 44.0, "realization_preload_margin": 30.0, "realization_resync_interval_seconds": 0.75, "realization_retention_seconds": 321.0})
	bridge.upsert_building_record({
		"building_id": "building.roundtrip.home",
		"settlement_id": "roundtrip_town",
		"facility_id": "roundtrip_town.housing",
		"type_id": "home",
		"display_name": "Roundtrip Home",
		"owner_faction_id": "RoundtripFaction",
		"access_state": "private",
		"abandoned": false,
		"operational_state": "operational",
		"bed_count": 4,
		"housing_capacity": 6,
		"world_transform": Transform3D(Basis(Vector3.UP, 0.4), Vector3(7.0, 2.0, -3.0)),
		"source": "authored",
		"catalog_id": "woodbrick_house",
		"foundation_height": 0.5,
	})

	if not bool(bridge.save_gecs_world(SAVE_PATH, false)):
		_fail("GECS bridge should save the validation world")
	world_time.release_manual_pause()

	var loaded_root := Node.new()
	root.add_child(loaded_root)
	var loaded_context := BootstrapContext.new(loaded_root)
	var loaded_bridge = load(GECS_WORLD_CONTROLLER_PATH).new()
	loaded_bridge.name = "GecsWorldController"
	loaded_root.add_child(loaded_bridge)
	loaded_context.register(loaded_bridge.SERVICE_ID, loaded_bridge)
	loaded_bridge.initialize(loaded_context)
	var loaded_world_time = load(WORLD_TIME_CONTROLLER_PATH).new()
	loaded_world_time.name = "WorldTimeController"
	loaded_root.add_child(loaded_world_time)
	loaded_context.register(loaded_world_time.SERVICE_ID, loaded_world_time)
	loaded_world_time.initialize(loaded_context)
	if not bool(loaded_bridge.load_gecs_world(SAVE_PATH)):
		_fail("GECS bridge should load the validation world")
	else:
		_validate_loaded_state(loaded_bridge, loaded_world_time)

	root_node.queue_free()
	loaded_root.queue_free()
	_remove_file(SAVE_PATH)

	if _failures.is_empty():
		print("GECS_SAVE_LOAD_ROUNDTRIP_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("GECS_SAVE_LOAD_ROUNDTRIP_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_loaded_state(bridge: Node, world_time: Node) -> void:
	var time_state: Dictionary = bridge.call("get_world_time_state")
	if absf(float(time_state.get("total_world_minutes", 0.0)) - ((6.0 * 60.0) + 9.5 * 60.0)) > 0.01:
		_fail("GECS save/load should round-trip total world minutes")
	if int(time_state.get("speed_index", -1)) != 2:
		_fail("GECS save/load should round-trip world speed index")
	if not bool(time_state.get("manual_paused", false)):
		_fail("GECS save/load should round-trip manual pause state")

	var vitals_state: Dictionary = bridge.call("get_actor_state", "actor.vitals")
	if int(vitals_state.get("life_state", -1)) != NpcRules.LifeState.UNCONSCIOUS:
		_fail("GECS save/load should capture live actor life state before save")
	if absf(float(vitals_state.get("hp", 0.0)) - 37.0) > 0.01:
		_fail("GECS save/load should capture live actor HP before save")
	if absf(float(vitals_state.get("blood", 0.0)) - 12.5) > 0.01:
		_fail("GECS save/load should capture live actor blood before save")
	if (vitals_state.get("world_position", Vector3.ZERO) as Vector3).distance_to(Vector3(3.0, 0.0, 4.0)) > 0.01:
		_fail("GECS save/load should capture live actor world position before save")

	var actor_record: Dictionary = bridge.call("get_population_record", "actor.roundtrip")
	if str(actor_record.get("member_name", "")) != "Roundtrip Worker":
		_fail("GECS save/load should round-trip population records")
	if str(actor_record.get("actor_script_path", "")) != "res://features/core/party/party_member.gd":
		_fail("GECS save/load should preserve the person's projection script")
	if int(actor_record.get("life_state", -1)) != NpcRules.LifeState.DEAD or str(actor_record.get("body_state", "")) != "corpse":
		_fail("GECS save/load should preserve a dead person's corpse state")
	var expected_corpse_transform := Transform3D(Basis.from_euler(Vector3(0.0, 0.7, 0.0)), Vector3(18.0, 0.5, -27.0))
	var saved_corpse_transform: Transform3D = actor_record.get("last_world_transform", Transform3D.IDENTITY)
	if not bool(actor_record.get("last_world_transform_initialized", false)) or not saved_corpse_transform.is_equal_approx(expected_corpse_transform):
		_fail("GECS save/load should preserve a corpse's world transform")
	var nearby_corpses: Array = bridge.call("get_corpse_population_records_near", Vector3(18.0, 0.0, -27.0), 2.0)
	if nearby_corpses.size() != 1 or str((nearby_corpses[0] as Dictionary).get("actor_id", "")) != "actor.roundtrip":
		_fail("GECS corpse spatial index should restore nearby dead people without a global scan")
	bridge.call("_rebuild_actor_spatial_index")
	nearby_corpses = bridge.call("get_corpse_population_records_near", Vector3(18.0, 0.0, -27.0), 2.0)
	if nearby_corpses.size() != 1:
		_fail("Live actor spatial rebuilds must not erase the durable corpse index")
	if int(actor_record.get("ledger_work_minutes", 0)) != 90:
		_fail("GECS save/load should round-trip population ledger fields")
	if str(actor_record.get("character_realizer_id", "")) != "settler_common" or str(actor_record.get("character_realizer_signature", "")) != "settler-signature":
		_fail("GECS save/load should round-trip Character Realizer provenance")
	if str(actor_record.get("character_type_id", "")) != "soldier" or str(actor_record.get("character_type_signature", "")) != "soldier-signature":
		_fail("GECS save/load should round-trip Character Type provenance")
	if not bool(actor_record.get("staff_assignment_realized_once", false)):
		_fail("GECS save/load should preserve whether staff assignment placement already occurred")
	if int((actor_record.get("skill_levels", {}) as Dictionary).get(SkillRules.MOVEMENT_RUNNING, 0)) != 5 or not is_equal_approx(float((actor_record.get("skill_xp", {}) as Dictionary).get(SkillRules.MOVEMENT_RUNNING, 0.0)), 12.5):
		_fail("GECS save/load should round-trip skill level and XP provenance")
	var needs_state: Dictionary = actor_record.get("needs_state", {})
	if not is_equal_approx(float(needs_state.get("hunger", 0.0)), 42.25) or not is_equal_approx(float(needs_state.get("food_effect_remaining_seconds", 0.0)), 8.5):
		_fail("GECS save/load should round-trip exact actor needs and timed effects")
	var movement_state: Dictionary = actor_record.get("movement_state", {})
	if not bool(movement_state.get("has_move_target", false)) or movement_state.get("move_target", Vector3.ZERO) != Vector3(21.0, 0.5, -31.0) or not bool(movement_state.get("sneaking", false)) or not bool(movement_state.get("issued_by_player", false)):
		_fail("GECS save/load should round-trip actor movement intent and stance")
	var inventory_entries: Array = actor_record.get("inventory_entries", [])
	if inventory_entries.size() != 1 or int((inventory_entries[0] as Dictionary).get("count", 0)) != 7:
		_fail("GECS save/load should round-trip actor inventory stacks")
	var equipment_slots: Dictionary = actor_record.get("equipment_slots", {})
	if str(equipment_slots.get("main_hand", "")) != "res://items/validation/hammer.tres":
		_fail("GECS save/load should round-trip actor equipment slots")
	var moved_corpse_record: Dictionary = bridge.call("get_population_record", "actor.corpse_transform")
	var expected_moved_transform := Transform3D(Basis.from_euler(Vector3(0.0, 1.1, 0.0)), Vector3(31.0, 0.75, 29.0))
	if not (moved_corpse_record.get("last_world_transform", Transform3D.IDENTITY) as Transform3D).is_equal_approx(expected_moved_transform):
		_fail("Direct GECS save should capture a live corpse's exact current transform")
	world_time.advance_hours(24.0 * 30.0)
	actor_record = bridge.call("get_population_record", "actor.roundtrip")
	if int(actor_record.get("life_state", -1)) != NpcRules.LifeState.DEAD or str(actor_record.get("body_state", "")) != "corpse":
		_fail("Thirty days of world time must not remove or alter an untouched corpse")
	if not bool(bridge.call("update_population_body_state", "actor.roundtrip", "buried", "grave.roundtrip")):
		_fail("Explicit burial should update body disposition")
	actor_record = bridge.call("get_population_record", "actor.roundtrip")
	if str(actor_record.get("body_state", "")) != "buried" or str(actor_record.get("body_container_id", "")) != "grave.roundtrip":
		_fail("Burial should retain the person and link their grave")
	nearby_corpses = bridge.call("get_corpse_population_records_near", Vector3(18.0, 0.0, -27.0), 2.0)
	if not nearby_corpses.is_empty():
		_fail("Buried people should leave the world-corpse spatial index")

	var settlement_state: Dictionary = bridge.call("get_settlement_state", "roundtrip_town")
	if int(settlement_state.get("population", 0)) != 12:
		_fail("GECS save/load should round-trip settlement population")
	if int(settlement_state.get("population_assigned", 0)) != 1:
		_fail("GECS save/load should derive settlement staff counts from GECS staff slots")
	var staff_slots: Array = bridge.call("get_staff_slots", "roundtrip_town")
	if staff_slots.size() != 1 or str((staff_slots[0] as Dictionary).get("role_id", "")) != "guard":
		_fail("GECS save/load should round-trip staff slot entities")
	elif (staff_slots[0] as Dictionary).get("world_position", Vector3.INF) != Vector3(12.0, 1.5, -8.0):
		_fail("GECS save/load should round-trip staff slot world positions")
	var building_records: Array = bridge.call("get_building_records")
	if building_records.size() != 1:
		_fail("GECS save/load should round-trip building entities")
	else:
		var building: Dictionary = building_records[0]
		if str(building.get("building_id", "")) != "building.roundtrip.home" or int(building.get("bed_count", 0)) != 4 or int(building.get("housing_capacity", 0)) != 6:
			_fail("GECS save/load should preserve canonical building fields")
		if str(building.get("catalog_id", "")) != "medium_wood_l_hall":
			_fail("GECS load should normalize legacy woodbrick_house catalog IDs once")
		if (building.get("world_transform", Transform3D.IDENTITY) as Transform3D).origin.distance_to(Vector3(7.0, 2.0, -3.0)) > 0.001:
			_fail("GECS save/load should preserve exact building transforms")

	var event_count := 0
	for _entity in bridge.get("world").query.with_all([bridge.get("C_SETTLEMENT_EVENT")]).execute():
		event_count += 1
	if event_count != 1:
		_fail("GECS save/load should round-trip settlement event entities")

	var law_state: Dictionary = bridge.call("get_law_order_state")
	var warrants: Dictionary = law_state.get("warrants", {})
	if int(((warrants.get("actor.roundtrip", {}) as Dictionary).get("RoundtripFaction", {}) as Dictionary).get("bad_person_points", 0)) != 12:
		_fail("GECS save/load should round-trip law warrant records")
	var prisoner_records: Dictionary = law_state.get("prisoner_records", {})
	if str((prisoner_records.get("prisoner.roundtrip", {}) as Dictionary).get("state", "")) != "jailed":
		_fail("GECS save/load should round-trip prisoner records")

	var faction_state: Dictionary = bridge.call("get_faction_state")
	if int((faction_state.get("reputations", {}) as Dictionary).get("Player:RoundtripFaction", 0)) != -25:
		_fail("GECS save/load should round-trip faction reputations")
	if int((faction_state.get("favor_points", {}) as Dictionary).get("RoundtripFaction", 0)) != 3:
		_fail("GECS save/load should round-trip faction favors")
	if str(((faction_state.get("diplomatic_states", {}) as Dictionary).get("Player:RoundtripFaction", {}) as Dictionary).get("state", "")) != "truce":
		_fail("GECS save/load should round-trip faction diplomacy")
	if not bool(faction_state.get("help_allies", false)):
		_fail("GECS save/load should round-trip faction help-allies policy")

	var squad_state: Dictionary = bridge.call("get_world_squad_state")
	if int(squad_state.get("squad_index", 0)) != 3:
		_fail("GECS save/load should round-trip world squad index")
	if str(((squad_state.get("active_squads", {}) as Dictionary).get("squad_0003", {}) as Dictionary).get("phase_id", "")) != "planning":
		_fail("GECS save/load should round-trip active world squads")

	var world_event_state: Dictionary = bridge.call("get_world_event_state")
	if str(world_event_state.get("active_prompt_event_id", "")) != "conflict.roundtrip":
		_fail("GECS save/load should round-trip active world-event prompt id")
	var event_record: Dictionary = (world_event_state.get("events", {}) as Dictionary).get("conflict.roundtrip", {})
	if not bool(event_record.get("committed", false)) or absf(float(event_record.get("participation_seconds", 0.0)) - 9.5) > 0.01:
		_fail("GECS save/load should round-trip world conflict event records")

	var job_state: Dictionary = bridge.call("get_job_system_state")
	if absf(float(job_state.get("sim_time", 0.0)) - 12.75) > 0.01:
		_fail("GECS save/load should round-trip job system clock")
	var ledger_state: Dictionary = bridge.call("get_ledger_simulation_state")
	if int(ledger_state.get("last_processed_minute", 0)) != 1530 or int((ledger_state.get("last_batch_summary", {}) as Dictionary).get("updated_actor_count", 0)) != 2:
		_fail("GECS save/load should round-trip ledger simulation state")
	var ai_scheduler_state: Dictionary = bridge.call("get_ai_scheduler_state")
	if absf(float(ai_scheduler_state.get("sim_time", 0.0)) - 7.25) > 0.01 or absf(float(ai_scheduler_state.get("default_tick_interval_seconds", 0.0)) - 0.35) > 0.01:
		_fail("GECS save/load should round-trip AI scheduler state")
	var realization_state: Dictionary = bridge.call("get_population_realization_state")
	if str(realization_state.get("default_realization_policy", "")) != "near_player" or absf(float(realization_state.get("near_player_radius", 0.0)) - 44.0) > 0.01 or absf(float(realization_state.get("realization_preload_margin", 0.0)) - 30.0) > 0.01 or absf(float(realization_state.get("realization_retention_seconds", 0.0)) - 321.0) > 0.01:
		_fail("GECS save/load should round-trip population realization settings")


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _fail(message: String) -> void:
	_failures.append(message)
