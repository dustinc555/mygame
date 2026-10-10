extends GutTest

const SCENARIO := preload("res://features/world_sim/resources/start_scenario_definition.gd")
const SPAWNER := preload("res://features/world_sim/bridge/character_record_party_spawner.gd")
const CONTROLLER := preload("res://features/world_sim/sim/player_party_controller.gd")
const SHARING := preload("res://features/inventory/bridge/food_sharing_controller.gd")

func _host() -> Dictionary:
	var root := WorldRoot.new()
	root.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(root)
	var context := BootstrapContext.new(root)
	var members := Node3D.new()
	members.name = "PartyMembers"
	root.add_child(members)
	var party := PartyManager.new()
	party.name = "PartyManager"
	root.add_child(party)
	var gecs := GecsWorldController.new()
	root.add_child(gecs)
	context.register(GecsWorldController.SERVICE_ID, gecs)
	gecs.initialize(context)
	gecs.set_process(false)
	var population := PopulationController.new()
	root.add_child(population)
	context.register(PopulationController.SERVICE_ID, population)
	population.initialize(context)
	var factions := FactionController.new()
	root.add_child(factions)
	context.register(FactionController.SERVICE_ID, factions)
	var realizer := PopulationCharacterRealizer.new()
	root.add_child(realizer)
	context.register(PopulationCharacterRealizer.SERVICE_ID, realizer)
	realizer.initialize(context)
	var controller := CONTROLLER.new()
	root.add_child(controller)
	context.register(CONTROLLER.SERVICE_ID, controller)
	controller.initialize(context)
	var simulation := WorldSimulationController.new()
	root.add_child(simulation)
	context.register(WorldSimulationController.SERVICE_ID, simulation)
	simulation.initialize(context)
	var sharing := SHARING.new()
	root.add_child(sharing)
	sharing.initialize(context)
	var spawner := SPAWNER.new()
	members.add_child(spawner)
	var scenario := SCENARIO.new()
	scenario.scenario_id = "test.restore"
	scenario.squad_name = "Travelers"
	for id in ["test.survivor", "test.departed"]:
		var character := CharacterRecordDefinition.new()
		character.actor_id = id
		character.member_name = id
		scenario.characters.append(character)
	root.default_start_scenario = scenario
	return {"root": root, "context": context, "party": party, "gecs": gecs,
		"population": population, "controller": controller, "simulation": simulation, "spawner": spawner,
		"sharing": sharing}

func test_cold_load_restores_saved_party_without_reapplying_scenario() -> void:
	var first := _host()
	first.spawner._on_bootstrap_context_ready(first.context)
	assert_eq(first.party.party_members.size(), 2)
	assert_true(first.controller.rename_squad("Travelers", "Survivors"))
	assert_true(first.controller.create_squad("Camp Guard"))
	var survivor: WorldActor = first.party.party_members[0]
	survivor.global_position = Vector3(25, 3, -10)
	survivor.rotation.y = 1.25
	first.party.unregister_party_member(first.party.party_members[1])
	assert_true(first.simulation.save_world_to_file("user://party-cold-load.tres"))
	first.root.queue_free()
	await get_tree().process_frame
	var loaded := _host()
	loaded.root.saved_game_path = "user://party-cold-load.tres"
	var bootstrap = load("res://features/core/game_bootstrap.gd").new()
	autofree(bootstrap)
	bootstrap.root_scene = loaded.root
	bootstrap._context = loaded.context
	assert_true(bootstrap._load_saved_start(), "The launch input loads the session before consumers seed or realize it")
	loaded.spawner._on_bootstrap_context_ready(loaded.context)
	assert_eq(loaded.party.party_members.size(), 1, "Load realizes saved members, not the default scenario roster")
	if loaded.party.party_members.size() == 1:
		var restored: WorldActor = loaded.party.party_members[0]
		assert_eq(restored.stable_id, "test.survivor")
		assert_eq(restored.squad_name, "Survivors")
		assert_eq(restored.global_position, Vector3(25, 3, -10))
		assert_almost_eq(restored.rotation.y, 1.25, 0.001, "Loading restores the saved pose, not the scenario placement")
		restored.hunger_enabled = true
		restored.get_needs().hunger_stage = NpcRules.HungerStage.HUNGRY
		assert_true(loaded.sharing._hungry.has(restored.get_instance_id()), "Restored members must acquire their real hunger subscription, not just skip the null access")
	assert_eq(loaded.controller.get_squad_names(), ["Survivors", "Camp Guard"])
	assert_eq(loaded.gecs.get_population_record("test.departed").party_id, "")
	loaded.root.queue_free()
	await get_tree().process_frame

func test_invalid_save_input_refuses_start_instead_of_creating_a_new_campaign() -> void:
	var host := _host()
	host.root.saved_game_path = "user://missing-start-scenario-save.tres"
	var bootstrap = load("res://features/core/game_bootstrap.gd").new()
	autofree(bootstrap)
	bootstrap.root_scene = host.root
	bootstrap._context = host.context
	assert_false(bootstrap._load_saved_start())
	assert_false(host.controller.state.start_applied)
	assert_true(host.party.party_members.is_empty())
	host.root.queue_free()
	await get_tree().process_frame

func test_loading_with_retained_bodies_restores_name_without_reseeding() -> void:
	var host := _host()
	host.spawner._on_bootstrap_context_ready(host.context)
	assert_true(host.simulation.save_world_to_file("user://party-retained.tres"))
	assert_true(host.controller.rename_squad("Travelers", "Unsaved"))
	assert_true(host.simulation.load_world_from_file("user://party-retained.tres"))
	await get_tree().process_frame
	assert_eq(host.party.party_members.size(), 2)
	assert_eq(host.party.party_members[0].squad_name, "Travelers")
	assert_eq(host.controller.get_squad_names(), ["Travelers"])
	assert_true(host.controller.rename_squad("Travelers", "After Load"))
	assert_eq(host.gecs.get_population_record("test.survivor").squad_name, "After Load")
	host.root.queue_free()
	await get_tree().process_frame
