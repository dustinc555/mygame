extends SceneTree

const GECS_WORLD_CONTROLLER_PATH := "res://features/core/gecs_world_controller.gd"
const WORLD_TIME_CONTROLLER_PATH := "res://features/core/world_time_controller.gd"
const C_VITALS_PATH := "res://features/actors/sim/c_game_actor_vitals.gd"
const C_VITALS_INPUTS_PATH := "res://features/actors/sim/c_game_actor_vitals_inputs.gd"
const SAVE_PATH := "user://population_vitals_lod_validation.tres"
const EXPECTED_VITALS_FIELDS := ["life_state", "hp", "max_hp", "blood", "max_blood", "base_max_blood", "blunt_damage", "open_cut_damage", "bandaged_cut_damage", "bleed_rate", "bleed_burst_rate", "recovery_multiplier", "dying_timer_remaining", "death_profile"]
const EXPECTED_INPUT_FIELDS := ["toughness", "healing_rate"]

var _failures: Array[String] = []
var _c_vitals
var _c_vitals_inputs


class FakeActor:
	extends Node3D

	var stable_id := ""
	var member_name := "LOD Vitals"
	var faction_name := "Settlers"
	var squad_name := ""
	var hostile_factions := PackedStringArray()
	var combat_stance := 0
	var player_party_member := false
	var life_state := NpcRules.LifeState.ALIVE
	var hp := 100.0
	var max_hp := 100.0
	var blood := 100.0
	var max_blood := 100.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_remove_save()
	var first := _make_bridge()
	var bridge = first["bridge"]
	_c_vitals = load(C_VITALS_PATH)
	_c_vitals_inputs = load(C_VITALS_INPUTS_PATH)
	var actor := FakeActor.new()
	actor.stable_id = "person.lod.vitals"
	first["root"].add_child(actor)
	bridge.upsert_population_record({
		"actor_id": actor.stable_id,
		"stable_id": actor.stable_id,
		"settlement_id": "lod_town",
		"assigned_slot_id": "lod_town.guard.0",
		"realization_state": "ledger",
		"last_world_position": Vector3(11.0, 0.0, -7.0),
		"last_world_position_initialized": true,
	})
	bridge.register_actor(actor, "lod_town", {"role_id": "guard"})
	var live_entity = bridge.get_actor_entity(actor)
	var live_vitals = live_entity.get_component(_c_vitals)
	var live_inputs = live_entity.get_component(_c_vitals_inputs)
	_set_wounded_state(live_vitals, live_inputs)
	var expected: Dictionary = live_vitals.durable_state()
	var expected_inputs: Dictionary = live_inputs.durable_state()
	_expect_fields("durable vitals schema", expected, EXPECTED_VITALS_FIELDS)
	_expect_fields("durable vitals input schema", expected_inputs, EXPECTED_INPUT_FIELDS)
	bridge.unregister_actor(actor)

	var ledger_record: Dictionary = bridge.get_population_record(actor.stable_id)
	_expect_state("LOD unload", ledger_record.get("vitals", {}), expected)
	_expect_state("LOD unload inputs", ledger_record.get("vitals_inputs", {}), expected_inputs)
	_expect(bridge.get_active_population_vitals_count() == 1, "LOD unload should index exactly one active injury")
	_expect(str(ledger_record.get("assigned_slot_id", "")) == "lod_town.guard.0", "Unconscious staff should keep their assignment")
	_expect(bridge.save_gecs_world(SAVE_PATH), "Wounded ledger person should save")

	var second := _make_bridge()
	var loaded = second["bridge"]
	var world_time = load(WORLD_TIME_CONTROLLER_PATH).new()
	second["root"].add_child(world_time)
	second["context"].register(world_time.SERVICE_ID, world_time)
	world_time.initialize(second["context"])
	_expect(loaded.load_gecs_world(SAVE_PATH), "Wounded ledger person should load")
	var loaded_record: Dictionary = loaded.get_population_record(actor.stable_id)
	_expect_state("save/load", loaded_record.get("vitals", {}), expected)
	_expect_state("save/load inputs", loaded_record.get("vitals_inputs", {}), expected_inputs)
	_expect(loaded.get_active_population_vitals_count() == 1, "Save/load should restore the sparse injury index")

	var control = _c_vitals.new()
	control.apply_durable_state(expected)
	control.vitals_seeded = true
	for _step in range(10):
		VitalsStateMachine.tick(control, float(expected_inputs["toughness"]), float(expected_inputs["healing_rate"]), 0.05)
		loaded.world.process(0.05)
	loaded_record = loaded.get_population_record(actor.stable_id)
	_expect_state("offscreen parity", loaded_record.get("vitals", {}), control.durable_state())

	var realized_actor := FakeActor.new()
	realized_actor.stable_id = actor.stable_id
	second["root"].add_child(realized_actor)
	loaded.register_actor(realized_actor, "lod_town", {"role_id": "guard"})
	var restored_vitals = loaded.get_actor_entity(realized_actor).get_component(_c_vitals)
	var restored_inputs = loaded.get_actor_entity(realized_actor).get_component(_c_vitals_inputs)
	_expect_state("LOD reload", restored_vitals.durable_state(), control.durable_state())
	_expect_state("LOD reload inputs", restored_inputs.durable_state(), expected_inputs)
	_expect(loaded.get_active_population_vitals_count() == 0, "Realized people must leave the offscreen injury query")
	var realized_control = _c_vitals.new()
	realized_control.apply_durable_state(restored_vitals.durable_state())
	for _step in range(10):
		VitalsStateMachine.tick(realized_control, float(expected_inputs["toughness"]), float(expected_inputs["healing_rate"]), 0.05)
	world_time.advance_minutes(0.5)
	_expect_state("realized time skip", restored_vitals.durable_state(), realized_control.durable_state())

	loaded.unregister_actor(realized_actor)
	var day_control = _c_vitals.new()
	day_control.apply_durable_state(loaded.get_population_record(actor.stable_id).get("vitals", {}))
	for _step in range(24 * 60 * 20):
		VitalsStateMachine.tick(day_control, float(expected_inputs["toughness"]), float(expected_inputs["healing_rate"]), 0.05)
	world_time.advance_days(1.0)
	loaded_record = loaded.get_population_record(actor.stable_id)
	_expect_state("one-day healing", loaded_record.get("vitals", {}), day_control.durable_state())
	_expect(loaded.get_active_population_vitals_count() == 0, "Healed people should leave the sparse injury index")

	_validate_offscreen_death(loaded, world_time)
	_validate_realized_skip_death(loaded, world_time, second["root"])
	_validate_staff_slot_sources()
	_remove_save()
	first["root"].queue_free()
	second["root"].queue_free()
	if _failures.is_empty():
		print("POPULATION_VITALS_LOD_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _make_bridge() -> Dictionary:
	var scene_root := Node.new()
	root.add_child(scene_root)
	var context := BootstrapContext.new(scene_root)
	var bridge = load(GECS_WORLD_CONTROLLER_PATH).new()
	scene_root.add_child(bridge)
	context.register(bridge.SERVICE_ID, bridge)
	bridge.initialize(context)
	return {"root": scene_root, "bridge": bridge, "context": context}


func _set_wounded_state(vitals, inputs) -> void:
	vitals.life_state = NpcRules.LifeState.UNCONSCIOUS
	vitals.hp = 53.0
	vitals.max_hp = 120.0
	vitals.blood = 61.5
	vitals.max_blood = 135.0
	vitals.base_max_blood = 110.0
	vitals.blunt_damage = 31.0
	vitals.open_cut_damage = 20.0
	vitals.bandaged_cut_damage = 16.0
	vitals.bleed_rate = 0.35
	vitals.bleed_burst_rate = 0.15
	vitals.recovery_multiplier = 1.25
	vitals.dying_timer_remaining = 8.75
	vitals.vitals_seeded = true
	inputs.toughness = 27.0
	inputs.healing_rate = 0.8


func _validate_offscreen_death(bridge, world_time) -> void:
	bridge.upsert_population_record({
		"actor_id": "person.lod.dying",
		"stable_id": "person.lod.dying",
		"settlement_id": "lod_town",
		"assigned_slot_id": "lod_town.guard.1",
		"realization_state": "ledger",
		"last_world_position": Vector3(3.0, 0.0, 2.0),
		"last_world_position_initialized": true,
		"vitals": {
			"life_state": NpcRules.LifeState.DYING,
			"hp": -120.0,
			"max_hp": 100.0,
			"blood": -120.0,
			"max_blood": 100.0,
			"base_max_blood": 100.0,
			"blunt_damage": 220.0,
			"open_cut_damage": 0.0,
			"bandaged_cut_damage": 0.0,
			"bleed_rate": 0.0,
			"bleed_burst_rate": 0.0,
			"recovery_multiplier": 0.0,
			"dying_timer_remaining": 0.25,
			"death_profile": 0,
		},
		"vitals_inputs": {"toughness": 0.0, "healing_rate": 0.0},
	})
	_expect(bridge.get_active_population_vitals_count() == 1, "Dying ledger person should enter the sparse injury index")
	_expect(str(bridge.get_population_record("person.lod.dying").get("realization_state", "")) == "ledger", "Dying person should remain in ledger realization")
	var found_system := false
	for system in bridge.world.systems:
		if system.name == "GamePopulationVitalsSystem":
			found_system = true
			_expect(system.active and not system.paused, "Population vitals system should remain active")
	_expect(found_system, "Population vitals system should remain registered")
	world_time.advance_minutes(0.5)
	var dead: Dictionary = bridge.get_population_record("person.lod.dying")
	_expect(int(dead.get("life_state", -1)) == NpcRules.LifeState.DEAD, "Dying ledger person should die offscreen")
	_expect(str(dead.get("body_state", "")) == "corpse", "Offscreen death should create a durable corpse")
	_expect(str(dead.get("assigned_slot_id", "")) == "", "Offscreen death should release the staff assignment")
	_expect(bridge.get_active_population_vitals_count() == 0, "Stable corpses should leave the sparse injury index")


func _validate_realized_skip_death(bridge, world_time, scene_root: Node) -> void:
	const ACTOR_ID := "person.realized.skip.dying"
	bridge.upsert_population_record({
		"actor_id": ACTOR_ID,
		"stable_id": ACTOR_ID,
		"settlement_id": "lod_town",
		"assigned_slot_id": "lod_town.guard.2",
		"realization_state": "ledger",
	})
	var actor := FakeActor.new()
	actor.stable_id = ACTOR_ID
	actor.global_transform = Transform3D(Basis(Vector3.UP, 0.6), Vector3(17.0, 0.5, -4.0))
	scene_root.add_child(actor)
	bridge.register_actor(actor, "lod_town", {"role_id": "guard"})
	bridge.update_population_realization(ACTOR_ID, "realized", actor.global_position, true)
	var entity = bridge.get_actor_entity(actor)
	var vitals = entity.get_component(_c_vitals)
	var inputs = entity.get_component(_c_vitals_inputs)
	vitals.life_state = NpcRules.LifeState.DYING
	vitals.hp = -120.0
	vitals.max_hp = 100.0
	vitals.blood = -120.0
	vitals.max_blood = 100.0
	vitals.blunt_damage = 220.0
	vitals.dying_timer_remaining = 0.25
	vitals.vitals_seeded = true
	inputs.toughness = 0.0
	inputs.healing_rate = 0.0
	var states_at_hour: Array[int] = []
	world_time.hour_changed.connect(func(_absolute_hour: int, _day: int, _hour: int) -> void:
		states_at_hour.append(int(bridge.get_population_record(ACTOR_ID).get("life_state", -1)))
	)
	world_time.advance_hours(1.0)
	var record: Dictionary = bridge.get_population_record(ACTOR_ID)
	_expect(int(record.get("life_state", -1)) == NpcRules.LifeState.DEAD, "Realized person should die during a world-time skip")
	_expect(not states_at_hour.is_empty() and states_at_hour.all(func(state: int) -> bool: return state == NpcRules.LifeState.DEAD), "Hourly reconciliation should observe realized skip deaths")
	_expect((record.get("last_world_transform", Transform3D.IDENTITY) as Transform3D).is_equal_approx(actor.global_transform), "Realized skip death should preserve the exact corpse transform")


func _validate_staff_slot_sources() -> void:
	for path in [
		"res://features/settlements/bridge/settlement_bar.gd",
		"res://features/settlements/bridge/settlement_jail.gd",
		"res://features/settlements/bridge/settlement_keep.gd",
		"res://features/settlements/bridge/settlement_town.gd",
	]:
		var source := FileAccess.get_file_as_string(path)
		_expect(source.contains("actor_dead := actor != null and int(actor.get(\"life_state\")) == NpcRules.LifeState.DEAD"), "%s must only open a vacancy for DEAD staff" % path)


func _expect_state(label: String, actual: Dictionary, expected: Dictionary) -> void:
	for field in expected:
		var actual_value = actual.get(field)
		var expected_value = expected[field]
		if expected_value is float:
			_expect(is_equal_approx(float(actual_value), expected_value), "%s changed %s: expected %.6f got %.6f" % [label, field, expected_value, float(actual_value)])
		else:
			_expect(actual_value == expected_value, "%s changed %s" % [label, field])


func _expect_fields(label: String, state: Dictionary, fields: Array) -> void:
	for field in fields:
		_expect(state.has(field), "%s is missing %s" % [label, field])


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)


func _remove_save() -> void:
	var absolute := ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)
