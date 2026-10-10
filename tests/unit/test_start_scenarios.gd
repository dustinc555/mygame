extends GutTest

const SCENARIO_PATH := "res://features/world_sim/resources/start_scenario_definition.gd"

func test_scenario_supplies_named_roster_faction_and_world_relative_placement() -> void:
	assert_true(ResourceLoader.exists(SCENARIO_PATH), "A start is an authored resource, not a HUD fallback")
	if not ResourceLoader.exists(SCENARIO_PATH):
		return
	var scenario = load(SCENARIO_PATH).new()
	scenario.scenario_id = "test.wayfarers"
	scenario.display_name = "Wayfarers"
	scenario.squad_name = "The Wayfarers"
	scenario.faction_id = "TestFaction"
	scenario.spawn_position = Vector3(10, 2, 20)
	scenario.member_spacing_meters = 4.0
	var first := CharacterRecordDefinition.new()
	first.actor_id = "test.start.first"
	first.member_name = "First"
	var second := CharacterRecordDefinition.new()
	second.actor_id = "test.start.second"
	second.member_name = "Second"
	scenario.characters.assign([first, second])
	var records: Array = scenario.create_records(Transform3D(Basis.IDENTITY, Vector3(100, 0, 0)))
	assert_eq(records.size(), 2)
	assert_eq(records[0].actor_id, first.actor_id)
	assert_eq(records[1].actor_id, second.actor_id)
	assert_eq(records[0].squad_name, "The Wayfarers")
	assert_eq(records[1].faction_id, "TestFaction")
	assert_eq(records[0].party_id, PartyManager.PLAYER_PARTY_ID)
	assert_eq(records[0].last_world_position, Vector3(110, 2, 18))
	assert_eq(records[1].last_world_position, Vector3(110, 2, 22))
	assert_false(first.to_record().has("squad_name"), "Scenario application never mutates character definitions")

func test_world_default_is_replaceable_by_a_selected_scenario_without_changing_authorship() -> void:
	var world := WorldRoot.new()
	autofree(world)
	assert_true(world.has_method("get_start_scenario"), "World startup must resolve a scenario input")
	if not world.has_method("get_start_scenario"):
		return
	var default_start = load(SCENARIO_PATH).new()
	default_start.scenario_id = "test.default"
	var selected_start = load(SCENARIO_PATH).new()
	selected_start.scenario_id = "test.selected"
	world.set("default_start_scenario", default_start)
	assert_same(world.call("get_start_scenario"), default_start)
	world.set("selected_start_scenario", selected_start)
	assert_same(world.call("get_start_scenario"), selected_start)
	assert_same(world.get("default_start_scenario"), default_start, "A future menu selection is not an editor mutation")

func test_invalid_scenario_rejects_missing_identity_duplicates_and_bad_placement() -> void:
	var scenario = load(SCENARIO_PATH).new()
	assert_false(scenario.validation_error().is_empty())
	scenario.scenario_id = "test.invalid"
	scenario.squad_name = "Travelers"
	assert_false(scenario.validation_error().is_empty())
	var character := CharacterRecordDefinition.new()
	character.actor_id = "test.one"
	scenario.characters.append(character)
	assert_eq(scenario.validation_error(), "")
	scenario.characters.append(character)
	assert_false(scenario.validation_error().is_empty(), "Duplicate identity cannot seed twice")
	scenario.characters.pop_back()
	scenario.spawn_position = Vector3.INF
	assert_false(scenario.validation_error().is_empty())
	scenario.spawn_position = Vector3.ZERO
	scenario.member_spacing_meters = 0
	assert_false(scenario.validation_error().is_empty())
	scenario.member_spacing_meters = 2
	scenario.squad_name = " "
	assert_false(scenario.validation_error().is_empty(), "An unnamed start cannot delegate naming to the HUD")
