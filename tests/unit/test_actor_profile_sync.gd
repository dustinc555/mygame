extends GutTest

class CountingSync extends GameActorSyncSystem:
	var profile_copies := 0
	func _sync_identity(component: CGameActorIdentity, actor: WorldActor) -> void:
		profile_copies += 1
		super._sync_identity(component, actor)

var _root: Node3D
var _bridge: GecsWorldController
var _actor: HumanoidCharacter
var _sync: CountingSync

func before_each() -> void:
	_root = Node3D.new()
	add_child(_root)
	var context := BootstrapContext.new(_root)
	_bridge = GecsWorldController.new()
	_root.add_child(_bridge)
	context.register(GecsWorldController.SERVICE_ID, _bridge)
	_bridge.initialize(context)
	_bridge.set_process(false)
	for system in _bridge.world.systems:
		if system is GameActorSyncSystem:
			system.set_script(CountingSync)
			_sync = system
	_actor = HumanoidCharacter.new()
	_actor.stable_id = "test.profile.actor"
	_actor.member_name = "Before"
	_actor.faction_name = "original"
	_actor.process_mode = Node.PROCESS_MODE_DISABLED
	_root.add_child(_actor)
	_bridge.register_actor(_actor)

func after_each() -> void:
	if is_instance_valid(_actor):
		_bridge.unregister_actor(_actor)
	_root.queue_free()
	await get_tree().process_frame

func test_unchanged_profile_is_not_copied_every_world_tick() -> void:
	_bridge.world.process(0.016)
	var initial := _sync.profile_copies
	for tick in range(8):
		_bridge.world.process(0.016)
	assert_gt(initial, 0, "Registration initializes the actual live profile")
	assert_eq(_sync.profile_copies, initial, "Idle actors leave profile-copy work until something changes")

func test_changed_profile_reaches_simulation_before_its_next_tick() -> void:
	_bridge.world.process(0.016)
	_actor.member_name = "After"
	_actor.faction_name = "replacement"
	_actor.combat_stance = 2
	_actor.player_party_member = true
	var entity = _bridge.get_actor_entity(_actor)
	var identity: CGameActorIdentity = entity.get_component(CGameActorIdentity)
	var faction: CGameActorFaction = entity.get_component(CGameActorFaction)
	assert_eq(identity.member_name, "After")
	assert_eq(faction.faction_id, "replacement")
	assert_eq(faction.combat_stance, 2)
	assert_true(faction.player_party_member)

func test_population_metadata_refreshes_without_waiting_for_an_unrelated_edit() -> void:
	_bridge.world.process(0.016)
	var population := PopulationController.new()
	add_child_autofree(population)
	population.apply_record_to_actor(_actor, {
		"actor_id": _actor.stable_id, "member_name": _actor.member_name,
		"faction_id": _actor.faction_name, "role_id": "guard", "settlement_id": "test.town",
	})
	var entity = _bridge.get_actor_entity(_actor)
	assert_eq(entity.get_component(CGameActorIdentity).role_id, "guard")
	assert_eq(entity.get_component(CGameActorSettlement).settlement_id, "test.town")

func test_authority_and_player_orders_update_the_same_registered_actor() -> void:
	_actor.set_settlement_authority(true)
	_actor.set_active_player_order(true)
	var entity = _bridge.get_actor_entity(_actor)
	assert_true(entity.get_component(CGameActorIdentity).authority_scopes.has("settlement_authority"))
	assert_true(entity.get_component(CGameActorFaction).player_order_active)
	_actor.set_active_player_order(false)
	assert_false(entity.get_component(CGameActorFaction).player_order_active)

func test_in_place_hostility_edits_remain_visible() -> void:
	_actor.hostile_factions = PackedStringArray(["first"])
	_actor.hostile_factions.append("second")
	var faction: CGameActorFaction = _bridge.get_actor_entity(_actor).get_component(CGameActorFaction)
	assert_eq(faction.hostile_faction_ids, PackedStringArray(["first", "second"]))

func test_load_rebinds_profile_commands_without_overwriting_saved_state() -> void:
	var path := "user://actor-profile-sync-roundtrip.tres"
	assert_true(_bridge.save_gecs_world(path))
	var previous: CGameActorIdentity = _bridge.get_actor_entity(_actor).get_component(CGameActorIdentity)
	_actor.member_name = "After save"
	_actor.faction_name = "Unsaved faction"
	assert_true(_bridge.load_gecs_world(path))
	var restored: CGameActorIdentity = _bridge.get_actor_entity(_actor).get_component(CGameActorIdentity)
	assert_eq(restored.member_name, "Before", "Rebinding must not copy pre-load scene state over the save")
	assert_eq(_actor.faction_name, "original", "The retained body reflects the restored profile")
	_actor.member_name = "After load"
	assert_eq(restored.member_name, "After load", "New edits reach the current entity")
	assert_eq(_bridge.get_actor_entity(_actor).get_component(CGameActorFaction).faction_id, "original", "A name edit cannot restore an unsaved faction")
	assert_eq(previous.member_name, "After save", "Removed components no longer receive edits")

func test_departed_projection_leaves_no_profile_binding() -> void:
	var previous: CGameActorIdentity = _bridge.get_actor_entity(_actor).get_component(CGameActorIdentity)
	_root.remove_child(_actor)
	_actor.member_name = "Outside world"
	assert_eq(previous.member_name, "Before")
	assert_eq(_sync._profile_bindings.size(), 0, "Leaving the tree releases the work registration")
	_root.add_child(_actor)
	_bridge.register_actor(_actor)
	_actor.member_name = "Reentered"
	assert_eq(_bridge.get_actor_entity(_actor).get_component(CGameActorIdentity).member_name, "Reentered")
	assert_eq(_sync._profile_bindings.size(), 1)

func test_party_departure_clears_membership_immediately() -> void:
	var party := PartyManager.new()
	add_child_autofree(party)
	party.register_party_member(_actor)
	var faction: CGameActorFaction = _bridge.get_actor_entity(_actor).get_component(CGameActorFaction)
	assert_eq(faction.party_id, PartyManager.PLAYER_PARTY_ID)
	party.unregister_party_member(_actor)
	assert_eq(faction.party_id, "")
	assert_false(faction.player_party_member)

func test_replaced_projection_cannot_edit_or_unregister_its_replacement() -> void:
	var replacement := HumanoidCharacter.new()
	replacement.stable_id = _actor.stable_id
	replacement.member_name = "Replacement"
	replacement.process_mode = Node.PROCESS_MODE_DISABLED
	_root.add_child(replacement)
	_bridge.register_actor(replacement)
	var identity: CGameActorIdentity = _bridge.get_actor_entity(replacement).get_component(CGameActorIdentity)
	_actor.member_name = "Departed body"
	assert_eq(identity.member_name, "Replacement")
	assert_eq(_sync._profile_bindings.size(), 1)
	_bridge.unregister_actor(_actor)
	assert_not_null(_bridge.get_actor_entity(replacement))
	_bridge.unregister_actor(replacement)
