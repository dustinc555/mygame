extends GutTest

const ACTIONS = preload("res://features/inventory/bridge/inventory_item_actions.gd")
const FOOD = preload("res://features/inventory/resources/items/food.tres")
const CUE_PATH := "res://features/inventory/resources/food_eating_sound.tres"

var _previous_context: BootstrapContext
var _cue: GameSoundCue
var _original_cache: Dictionary
var _viewport: SubViewport


func before_each() -> void:
	_previous_context = BootstrapContext.active
	BootstrapContext.active = null
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.audio_listener_enable_3d = true
	add_child_autofree(_viewport)
	var camera := Camera3D.new()
	_viewport.add_child(camera)
	camera.position = Vector3(0, 4, 5)
	camera.make_current()
	# Licensed files are verified separately; units still run on a fresh checkout.
	if ResourceLoader.exists(CUE_PATH):
		_cue = load(CUE_PATH)
		_original_cache = _cue._stream_cache.duplicate()
		var sample := AudioStreamWAV.new()
		sample.format = AudioStreamWAV.FORMAT_16_BITS
		sample.mix_rate = 8000
		var pcm := PackedByteArray()
		pcm.resize(16000)
		for frame in range(8000):
			pcm.encode_s16(frame * 2, roundi(sin(frame * 0.2) * 1000.0))
		sample.data = pcm
		for path in _cue.paths:
			_cue._stream_cache[path] = sample


func after_each() -> void:
	get_tree().paused = false
	if _cue != null:
		_cue._stream_cache = _original_cache
		_cue = null
	BootstrapContext.active = _previous_context


func _actor() -> WorldActor:
	var actor := WorldActor.new()
	actor.hunger_enabled = true
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	_viewport.add_child(actor)
	return actor


func test_non_party_actor_eating_without_a_button_starts_positional_audio() -> void:
	var actor := _actor()
	assert_false(actor.is_player_party_member())
	assert_true(actor.inventory.add_item(FOOD))
	assert_true(ACTIONS.eat(actor, actor.inventory.entries[0]))
	assert_eq(actor.inventory.count_item(FOOD), 0)
	var audio := actor.get_node_or_null("FoodEatingAudio") as AudioStreamPlayer3D
	assert_not_null(audio, "Successful food consumption, not a button, owns the sound")
	if audio == null:
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(audio.playing)
	assert_not_null(audio.get_stream_playback())
	assert_true(audio.get_stream_playback().is_playing())
	assert_eq(audio.global_position, actor.global_position)
	assert_true(str(audio.get_meta("clip_path", "")).get_file().begins_with("FOODEat"))


func test_manual_inventory_action_uses_the_same_eating_sound() -> void:
	var actor := _actor()
	actor.set_player_party_member(true)
	assert_true(actor.inventory.add_item(FOOD))
	var controller := PartyInventoryController.new()
	add_child_autofree(controller)
	controller._on_inventory_item_action_requested(actor, actor.inventory.entries[0], "eat")
	assert_true(actor.is_food_effect_active())
	assert_true(actor.get_node("FoodEatingAudio").playing)
	assert_eq(actor.inventory.count_item(FOOD), 0)


func test_successive_meals_vary_without_immediate_repeats_or_extra_voices() -> void:
	var actor := _actor()
	var heard: Dictionary = {}
	var previous := ""
	var first_voice: AudioStreamPlayer3D
	for meal in range(32):
		actor.get_needs().process_needs(NpcRules.FOOD_EFFECT_DURATION_SECONDS)
		assert_true(actor.inventory.add_item(FOOD))
		assert_true(ACTIONS.eat(actor, actor.inventory.entries[0]))
		var audio := actor.get_node("FoodEatingAudio") as AudioStreamPlayer3D
		if first_voice == null:
			first_voice = audio
			# Freeze only the test's RNG; production keeps its independent seed.
			audio._rng.seed = 12345
		assert_same(audio, first_voice)
		var path := str(audio.get_meta("clip_path"))
		assert_ne(path, previous)
		assert_true(_cue.paths.has(path))
		heard[path] = true
		previous = path
	assert_gt(heard.size(), 1)
	assert_eq(actor.find_children("*", "AudioStreamPlayer3D", false, false).size(), 1)
	assert_eq(first_voice.max_polyphony, 1)
	actor.position = Vector3(12, 1, -8)
	assert_eq(first_voice.global_position, actor.global_position)


func test_nonfood_and_refused_or_stale_meals_are_silent() -> void:
	var actor := _actor()
	var nonfood := ItemDefinition.new()
	assert_true(actor.inventory.add_item(nonfood))
	assert_false(ACTIONS.eat(actor, actor.inventory.entries[0]))
	assert_null(actor.get_node_or_null("FoodEatingAudio"))
	assert_true(actor.inventory.add_item_count(FOOD, 2))
	var entry = actor.inventory.entries.back()
	assert_true(ACTIONS.eat(actor, entry))
	var audio := actor.get_node("FoodEatingAudio") as AudioStreamPlayer3D
	await get_tree().physics_frame
	await get_tree().physics_frame
	var playback := audio.get_stream_playback()
	var path: String = audio.get_meta("clip_path")
	assert_false(ACTIONS.eat(actor, entry), "Already digesting")
	assert_eq(actor.inventory.count_item(FOOD), 1)
	assert_same(audio.get_stream_playback(), playback)
	assert_eq(str(audio.get_meta("clip_path")), path)
	actor.get_needs().process_needs(NpcRules.FOOD_EFFECT_DURATION_SECONDS)
	actor.inventory.remove_item_count(FOOD, 1)
	assert_false(ACTIONS.eat(actor, entry), "Entry removed before activation")
	assert_same(audio.get_stream_playback(), playback)


func test_restoring_digestion_is_not_a_new_eating_action() -> void:
	var actor := _actor()
	actor.get_needs().apply_durable_state({"food_effect_rate": 1.0, "food_effect_remaining_seconds": 10.0})
	assert_true(actor.is_food_effect_active())
	assert_null(actor.get_node_or_null("FoodEatingAudio"))
	actor.get_needs().process_needs(1.0)
	assert_null(actor.get_node_or_null("FoodEatingAudio"))


func test_missing_recording_does_not_prevent_consumption() -> void:
	var actor := _actor()
	var audio = load("res://features/inventory/projection/food_eating_audio.tscn").instantiate()
	audio.cue = GameSoundCue.new()
	audio.cue.paths = PackedStringArray(["res://missing_food_recording.wav"])
	actor.add_child(audio)
	assert_true(actor.inventory.add_item(FOOD))
	assert_true(ACTIONS.eat(actor, actor.inventory.entries[0]))
	assert_eq(actor.inventory.count_item(FOOD), 0)
	assert_true(actor.is_food_effect_active())
	assert_false(audio.playing)


func test_accepted_meal_plays_even_while_game_is_paused() -> void:
	var actor := _actor()
	assert_true(actor.inventory.add_item(FOOD))
	get_tree().paused = true
	assert_true(ACTIONS.eat(actor, actor.inventory.entries[0]))
	var audio := actor.get_node("FoodEatingAudio") as AudioStreamPlayer3D
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_false(audio.stream_paused)
	assert_true(audio.get_stream_playback().is_playing())


func test_destroyed_eater_releases_voice_and_replacement_can_eat() -> void:
	var actor := _actor()
	assert_true(actor.inventory.add_item(FOOD))
	assert_true(ACTIONS.eat(actor, actor.inventory.entries[0]))
	var audio := actor.get_node("FoodEatingAudio") as AudioStreamPlayer3D
	actor.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(is_instance_valid(audio))
	var replacement := _actor()
	assert_null(replacement.get_node_or_null("FoodEatingAudio"))
	assert_true(replacement.inventory.add_item(FOOD))
	assert_true(ACTIONS.eat(replacement, replacement.inventory.entries[0]))
	assert_true(replacement.get_node("FoodEatingAudio").playing)


func test_inventory_observer_can_remove_eater_without_stale_audio_access() -> void:
	var actor := _actor()
	assert_true(actor.inventory.add_item(FOOD))
	var inventory := actor.inventory
	var entry = inventory.entries[0]
	inventory.changed.connect(func(): actor.free(), CONNECT_ONE_SHOT)
	assert_true(ACTIONS.eat(actor, entry))
	assert_false(is_instance_valid(actor))
	assert_eq(inventory.count_item(FOOD), 0)


func test_authored_volume_and_range_controls_reach_native_player() -> void:
	var actor := _actor()
	var audio = load("res://features/inventory/projection/food_eating_audio.tscn").instantiate()
	audio.cue = _cue.duplicate()
	audio.cue._stream_cache = _cue._stream_cache.duplicate()
	audio.cue.volume_db = -17.0
	audio.max_distance = 29.0
	audio.unit_size = 8.0
	actor.add_child(audio)
	assert_true(actor.inventory.add_item(FOOD))
	assert_true(ACTIONS.eat(actor, actor.inventory.entries[0]))
	assert_eq(audio.volume_db, -17.0)
	assert_eq(audio.max_distance, 29.0)
	assert_eq(audio.unit_size, 8.0)
	assert_eq(audio.pitch_scale, 1.0)


func test_automatic_food_sharing_plays_at_recipient_not_donor() -> void:
	var root := Node3D.new()
	_viewport.add_child(root)
	var context := BootstrapContext.new(root)
	var bridge := GecsWorldController.new()
	root.add_child(bridge)
	context.register(GecsWorldController.SERVICE_ID, bridge)
	bridge.initialize(context)
	bridge.set_process(false)
	var party := PartyManager.new()
	party.name = "PartyManager"
	root.add_child(party)
	var donor := HumanoidCharacter.new()
	donor.appearance_data = CharacterAppearanceData.new()
	donor.appearance_data.character_race = load("res://features/actors/resources/character_races/human.tres")
	donor.appearance_data.body_archetype = load("res://features/actors/resources/character_body_archetypes/human_male.tres")
	donor.stable_id = "food.audio.donor"
	donor.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(donor)
	bridge.register_actor(donor)
	var recipient := HumanoidCharacter.new()
	recipient.stable_id = "food.audio.recipient"
	recipient.hunger_enabled = true
	recipient.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(recipient)
	recipient.position = Vector3(3, 0, 0)
	bridge.register_actor(recipient)
	party.set_party_members([donor, recipient])
	var bag = load("res://features/inventory/resources/items/medium_leather_bag.tres")
	assert_true(donor.inventory.add_entry_with_contents(bag, 1, {}, {}, "food.audio.bag"))
	var controller := PartyInventoryController.new()
	root.add_child(controller)
	controller._context = context
	controller.root_scene = root
	controller._on_inventory_equip_requested(donor, donor.inventory.entries[0], donor, "backpack")
	assert_eq(donor.get_equipped_item("backpack"), bag)
	var view = load("res://features/inventory/bridge/item_storage_view.gd").new()
	assert_true(view.bind(donor, "food.audio.bag", bridge))
	root.add_child(view)
	assert_true(view.inventory.add_item_count(FOOD, 2))
	var sharing = load("res://features/inventory/bridge/food_sharing_controller.gd").new()
	root.add_child(sharing)
	sharing.initialize(context)
	donor.set_share_food_enabled(true)
	recipient.get_needs().hunger_stage = NpcRules.HungerStage.HUNGRY
	sharing.check_pending_meals()
	assert_true(recipient.is_food_effect_active())
	assert_eq(view.inventory.count_item(FOOD), 1)
	assert_null(donor.get_node_or_null("FoodEatingAudio"))
	var audio := recipient.get_node_or_null("FoodEatingAudio") as AudioStreamPlayer3D
	assert_not_null(audio)
	if audio != null:
		await get_tree().physics_frame
		await get_tree().physics_frame
		assert_true(audio.get_stream_playback().is_playing())
		assert_eq(audio.global_position, recipient.global_position)
		var playback := audio.get_stream_playback()
		sharing.check_pending_meals()
		assert_same(audio.get_stream_playback(), playback, "No second sound without a second meal")
	sharing.free()
	bridge.unregister_actor(donor)
	bridge.unregister_actor(recipient)
