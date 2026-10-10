extends GutTest

## Party consumers must never observe a partly hydrated actor.
func test_registration_publishes_the_authored_squad_not_a_blank_placeholder() -> void:
	var root := Node.new()
	add_child_autofree(root)
	var party := PartyManager.new()
	party.name = "PartyManager"
	root.add_child(party)
	var population := PopulationController.new()
	root.add_child(population)
	population.root_scene = root
	var actor := HumanoidCharacter.new()
	autofree(actor)
	var announced_squads: Array[String] = []
	party.party_member_added.connect(func(member: WorldActor):
		announced_squads.append(member.squad_name))
	population.apply_record_to_actor(actor, {
		"actor_id": "test.start.scout", "member_name": "Scout",
		"party_id": PartyManager.PLAYER_PARTY_ID, "faction_id": "Player",
		"squad_name": "The Wayfarers",
	})
	assert_eq(announced_squads, ["The Wayfarers"], "Membership is announced only after the squad has been applied")
	assert_eq(actor.squad_name, "The Wayfarers")
