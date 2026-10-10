extends GutTest

const CONTROLLER_PATH := "res://features/world_sim/sim/player_party_controller.gd"
const SCENARIO := preload("res://features/world_sim/resources/start_scenario_definition.gd")

func test_spawner_uses_the_world_selection_and_finishes_membership_before_notification() -> void:
	var spawner = load("res://features/world_sim/bridge/character_record_party_spawner.gd").new()
	autofree(spawner)
	assert_true(spawner.has_method("_on_bootstrap_context_ready"), "Start spawning must consume the completed bootstrap, not race it")
	if not spawner.has_method("_on_bootstrap_context_ready"):
		return
	var root := WorldRoot.new()
	root.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(root)
	var scenario := SCENARIO.new()
	scenario.scenario_id = "test.selected"
	scenario.squad_name = "Selected Start"
	scenario.spawn_position = Vector3(3, 4, 5)
	var character := CharacterRecordDefinition.new()
	character.actor_id = "test.spawn.selected"
	character.member_name = "Chosen"
	scenario.characters.append(character)
	root.selected_start_scenario = scenario
	root.default_start_scenario = SCENARIO.new()
	var members := Node3D.new()
	members.name = "PartyMembers"
	members.position = Vector3(10, 0, 0)
	root.add_child(members)
	var party := PartyManager.new()
	party.name = "PartyManager"
	root.add_child(party)
	var context := BootstrapContext.new(root)
	var gecs := GecsWorldController.new()
	root.add_child(gecs)
	context.register(GecsWorldController.SERVICE_ID, gecs)
	gecs.initialize(context)
	gecs.set_process(false)
	var population := PopulationController.new()
	root.add_child(population)
	context.register(PopulationController.SERVICE_ID, population)
	population.initialize(context)
	var controller = load(CONTROLLER_PATH).new()
	root.add_child(controller)
	context.register(&"player_party", controller)
	var factions := FactionController.new()
	root.add_child(factions)
	context.register(FactionController.SERVICE_ID, factions)
	var realizer := PopulationCharacterRealizer.new()
	root.add_child(realizer)
	context.register(PopulationCharacterRealizer.SERVICE_ID, realizer)
	realizer.initialize(context)
	controller.initialize(context)
	var announced: Array[String] = []
	party.party_member_added.connect(func(member: WorldActor): announced.append(member.squad_name))
	members.add_child(spawner)
	spawner.call("_on_bootstrap_context_ready", context)
	assert_eq(party.party_members.size(), 1)
	assert_eq(announced, ["Selected Start"])
	if not party.party_members.is_empty():
		assert_eq(party.party_members[0].stable_id, "test.spawn.selected")
		assert_eq(party.party_members[0].global_position, Vector3(3, 4, 5), "Scenario coordinates do not inherit the PartyMembers translation twice")
	spawner.call("_on_bootstrap_context_ready", context)
	assert_eq(party.party_members.size(), 1)
	# autofree already owns this leaf; detach before releasing the containing world.
	members.remove_child(spawner)
	root.queue_free()
	await get_tree().process_frame

func test_start_seeds_durable_roster_once_and_loading_never_reseeds_it() -> void:
	assert_true(ResourceLoader.exists(CONTROLLER_PATH), "Starting a scenario needs a saved, one-time application boundary")
	if not ResourceLoader.exists(CONTROLLER_PATH):
		return
	var root := Node3D.new()
	add_child(root)
	var context := BootstrapContext.new(root)
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
	var controller = load(CONTROLLER_PATH).new()
	root.add_child(controller)
	controller.initialize(context)
	var scenario := SCENARIO.new()
	scenario.scenario_id = "test.exiles"
	scenario.squad_name = "Exiles"
	var character := CharacterRecordDefinition.new()
	character.actor_id = "test.exile"
	character.member_name = "Exile"
	scenario.characters.append(character)
	var started: Array = controller.start_scenario(scenario, Transform3D.IDENTITY)
	assert_eq(started.size(), 1)
	assert_eq(gecs.get_population_record(character.actor_id).squad_name, "Exiles")
	assert_eq(controller.get_squad_names(), ["Exiles"])
	assert_true(controller.has_method("create_squad"), "Explicitly named empty squads need saved state")
	if controller.has_method("create_squad"):
		assert_false(controller.create_squad(" "))
		assert_false(controller.create_squad("All"))
		assert_false(controller.create_squad("exiles"))
		assert_true(controller.create_squad("Camp Guard"))
		assert_true(controller.rename_squad("Exiles", "Travelers"))
		assert_eq(gecs.get_population_record(character.actor_id).squad_name, "Travelers", "Rename reaches unrealized members, not just portraits")
		assert_false(controller.rename_squad("Travelers", "Camp Guard"))
		assert_true(controller.rename_squad("Travelers", "Exiles"))
	assert_true(controller.start_scenario(scenario, Transform3D.IDENTITY).is_empty(), "A repeated bootstrap cannot spawn a second party")
	assert_true(gecs.save_gecs_world("user://party-start.tres"))
	population.update_actor_record(character.actor_id, {"squad_name": "Changed"})
	assert_true(gecs.load_gecs_world("user://party-start.tres"))
	if controller.has_method("create_squad"):
		assert_eq(controller.get_squad_names(), ["Exiles", "Camp Guard"], "Explicit empty squads survive saving")
	assert_eq(gecs.get_population_record(character.actor_id).squad_name, "Exiles")
	assert_true(controller.start_scenario(scenario, Transform3D.IDENTITY).is_empty(), "Loading restores the save, not starting conditions")
	root.queue_free()
	await get_tree().process_frame
