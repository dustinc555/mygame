extends GutTest

class ResolutionProbe extends GameCombatResolutionSystem:
	var accept := true
	var defend := false
	func _prepare_receive_attack(_target: Node, _attacker: Node, _vitals: CGameActorVitals) -> Dictionary:
		return {"accepted": accept, "can_actively_defend": defend}

class Fighter extends WorldActor:
	var weapon: ItemDefinition
	func _enter_tree() -> void:
		pass
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
	func get_equipped_item(slot: String) -> ItemDefinition:
		return weapon if slot == "weapon" else null
	func get_system_combat_attack_spec() -> Dictionary:
		return {"attack_id": "bite", "total_seconds": 0.8, "impact_seconds": 0.3}

var _root: Node3D
var _system: ResolutionProbe
var _data: Array
var _events: Array

func before_each() -> void:
	_root = Node3D.new()
	add_child(_root)
	_system = ResolutionProbe.new()
	_root.add_child(_system)
	var nodes := [CGameActorNode.new(), CGameActorNode.new()]
	var identities := [CGameActorIdentity.new(), CGameActorIdentity.new()]
	var spatial := [CGameActorSpatial.new(), CGameActorSpatial.new()]
	for i in range(2):
		var actor := Fighter.new()
		actor.collision_layer = 2
		var shape := CollisionShape3D.new()
		shape.name = "CollisionShape3D"
		shape.shape = CapsuleShape3D.new()
		actor.add_child(shape)
		_root.add_child(actor)
		actor.position = Vector3(i, 0, 0)
		nodes[i].actor = actor
		identities[i].actor_id = "a" if i == 0 else "b"
		spatial[i].world_position = actor.position
	var configs := [CGameCombatConfig.new(), CGameCombatConfig.new()]
	configs[0].blunt_damage = 10.0
	configs[0].crit_chance = 0.0
	var slots := [CGameCombatSlotState.new(), CGameCombatSlotState.new()]
	slots[0].slot_state = CGameCombatSlotState.FightState.FIGHTING
	slots[0].slot_target_actor_id = "b"
	slots[0].tempo_actor_id = "a"
	_data = [nodes, identities, spatial, [CGameActorVitals.new(), CGameActorVitals.new()], configs, [CGameCombatAction.new(), CGameCombatAction.new()], slots]
	_events = []
	if _system.has_signal("combat_audio_event"):
		_system.connect("combat_audio_event", func(event: Dictionary): _events.append(event))

func after_each() -> void:
	_root.free()

func _start() -> void:
	_system._try_start_slot_action(0, _data[0], _data[1], _data[2], _data[3], _data[4], _data[5], _data[6], {"a": 0, "b": 1}, {})

func _impact() -> void:
	_system._resolve_action_impact(0, _data[0], _data[1], _data[2], _data[3], _data[4], _data[5], _data[6], {"a": 0, "b": 1})

func test_real_gecs_start_and_contact_emit_distinct_audio_edges_once() -> void:
	_start()
	assert_true(_data[5][0].action_active)
	assert_eq(_events.size(), 1, "A genuine attack emits the start edge used for creature vocals")
	if _events.size() != 1:
		return
	assert_eq(_events[0].phase, "swing")
	assert_eq(_events[0].attack_id, "bite")
	assert_eq(_events[0].attacker_id, "a")
	assert_almost_eq(_data[5][0].action_impact_remaining, 0.3, 0.0001)
	_impact()
	_impact()
	assert_eq(_events.size(), 2, "One contact, even if impact is requested twice")
	assert_eq(_events[1].phase, "contact")
	assert_eq(_events[1].outcome, "hit")
	assert_gt(_data[3][1].blunt_damage, 0.0)

func test_refused_start_is_silent() -> void:
	_data[4][1].protected_from_combat = true
	_start()
	assert_true(_events.is_empty())
	assert_eq(_data[5][0].action_sequence, 0)

func test_refused_impact_emits_no_dodge_or_contact_edge() -> void:
	_start()
	_system.accept = false
	_impact()
	assert_eq(_events.size(), 1)
	assert_eq(_data[3][1].blunt_damage, 0.0)

func test_confirmed_dodge_emits_one_dodge_edge_and_no_contact() -> void:
	_system.defend = true
	_data[4][0].hit_score = 0.0
	_data[4][1].dodge_score = 1000000.0
	seed(10)
	_start()
	_impact()
	_impact()
	assert_eq(_events.size(), 2, "Only the resolved opponent dodge adds the whoosh edge, once")
	assert_eq(_data[3][1].blunt_damage, 0.0)
	if _events.size() != 2:
		return
	assert_eq(_events[1].phase, "dodge")
	assert_eq(_events[1].outcome, "dodged")
	assert_eq(_events[1].sequence, _events[0].sequence)
	assert_eq(_events[1].attacker_position, Vector3.ZERO)
	assert_true(_events[1].is_read_only())

func test_block_with_zero_damage_still_emits_one_contact_and_captured_values() -> void:
	_system.defend = true
	_data[4][0].hit_score = 1000000.0
	_data[4][1].block_score = 100000000.0
	_data[4][1].block_damage_multiplier = 0.0
	_data[4][1].has_shield = true
	seed(1)
	randf() # critical draw at start
	assert_lte(randf(), 0.95, "Fixture hit draw")
	assert_lte(randf(), 0.75, "Fixture block draw")
	seed(1)
	_start()
	_impact()
	_impact()
	assert_eq(_events.size(), 2)
	assert_eq(_events[1].outcome, "blocked")
	assert_true(_events[1].has_shield)
	assert_true(_events[1].is_read_only())
	assert_eq(_events[1].target_position, Vector3(1, 0, 0))
	assert_eq(_data[3][1].blunt_damage, 0.0)
	_data[0][1].actor.free()
	assert_eq(_events[1].target_position, Vector3(1, 0, 0))

func test_out_of_leash_impact_is_silent() -> void:
	_start()
	_data[2][1].world_position = Vector3(100, 0, 0)
	_impact()
	assert_eq(_events.size(), 1)
	assert_eq(_data[3][1].blunt_damage, 0.0)

func test_fixed_step_path_emits_at_real_start_and_impact_time() -> void:
	_system.process([], _data, 0.05)
	assert_eq(_events.size(), 1)
	_system.process([], _data, 0.20)
	assert_eq(_events.size(), 1, "No premature contact during windup")
	_system.process([], _data, 0.15)
	assert_eq(_events.size(), 2)
	assert_eq(_events[1].phase, "contact")

func test_production_world_starts_whoosh_only_when_opponent_dodge_resolves() -> void:
	_data[0][0].actor.weapon = load("res://features/inventory/resources/items/iron_sword.tres")
	var controller := GecsWorldController.new()
	_root.add_child(controller)
	controller.set_process(false)
	if not controller.has_signal("combat_audio_event"):
		fail_test("Production world does not publish combat audio")
		return
	var forwarded: Array = []
	controller.connect("combat_audio_event", func(event: Dictionary): forwarded.append(event))
	for i in range(2):
		_data[0][i].actor.set_meta("actor_record_id", _data[1][i].actor_id)
		assert_eq(controller.register_actor(_data[0][i].actor), _data[1][i].actor_id)
	var camera := Camera3D.new()
	_root.add_child(camera)
	camera.current = true
	var audio = load("res://features/combat/projection/combat_audio_controller.gd").new()
	_root.add_child(audio)
	audio.bank = load("res://features/combat/resources/audio/combat_sound_bank.gd").new()
	var cue = load("res://features/audio/resources/game_sound_cue.gd").new()
	cue.cue_id = &"swing_blade"
	cue.paths = PackedStringArray(["unit_stream"])
	var stream := AudioStreamWAV.new()
	var pcm := PackedByteArray()
	pcm.resize(8000)
	stream.mix_rate = 8000
	stream.data = pcm
	cue._stream_cache["unit_stream"] = stream
	audio.bank.cues.append(cue)
	var context := BootstrapContext.new(_root)
	context.register(&"gecs_world", controller)
	audio.initialize(context)
	var resolution: GameCombatResolutionSystem
	for group in controller.world.systems_by_group.values():
		for system in group:
			if system is GameCombatResolutionSystem:
				resolution = system
	assert_not_null(resolution)
	if resolution == null:
		return
	_data[4][0].hit_score = 0.0
	_data[4][1].dodge_score = 1000000.0
	seed(10)
	resolution.process([], _data, 0.05)
	assert_eq(forwarded.size(), 1)
	assert_eq(forwarded[0].phase, "swing")
	assert_eq(audio.get_child_count(), 0, "Attack start is not permission to play a whoosh")
	resolution.process([], _data, 0.20)
	assert_eq(forwarded.size(), 1)
	assert_eq(audio.get_child_count(), 0, "No premature whoosh during windup")
	resolution.process([], _data, 0.15)
	assert_eq(forwarded.size(), 2, "Registered resolution forwards the actual dodge outcome")
	assert_eq(audio.get_child_count(), 1, "Resolved dodge reaches native playback through injected world lookup")
	if forwarded.size() != 2 or audio.get_child_count() != 1:
		return
	assert_eq(forwarded[1].phase, "dodge")
	assert_eq(forwarded[1].outcome, "dodged")
	assert_true(audio.get_child(0).playing)
	assert_same(audio.get_child(0).stream, stream)
	assert_eq(audio.get_child(0).global_position, Vector3.ZERO)
	assert_eq(_data[3][1].blunt_damage, 0.0)
	resolution._resolve_action_impact(0, _data[0], _data[1], _data[2], _data[3], _data[4], _data[5], _data[6], {"a": 0, "b": 1})
	controller.combat_audio_event.emit(forwarded[1])
	assert_eq(audio.get_child_count(), 1)
	assert_eq(audio.get_child(0).get_meta("play_serial"), 1, "Neither repeated impact nor repeated delivery replays the whoosh")
