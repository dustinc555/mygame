extends "res://tests/validation/test_case.gd"

## Shared test-owned setup and named law/custody cases. Thin validate_law_*
## entrypoints choose cases; each case gets a fresh world and unconditional
## cleanup. Production behavior is never reimplemented here.

const CUSTODY_SCENE := preload("res://tests/validation/fixtures/jail_custody/custody_world.tscn")
const ACTOR_SCENE := preload("res://features/core/party/party_member.tscn")
const WORLD_ITEM_SCENE := preload("res://features/world/projection/items/world_item.tscn")
const FACTION_HUMANOID_SCRIPT := preload("res://features/actors/projection/humanoid/faction_humanoid.gd")
const SETTLEMENT_TOWN_SCRIPT := preload("res://features/settlements/bridge/settlement_town.gd")
const SETTLEMENT_DEFINITION_SCRIPT := preload("res://features/world_sim/resources/settlement_definition.gd")
const FARMERS_FACTION := preload("res://features/factions/resources/factions/farmers.tres")
const LEGAL_ITEM := preload("res://features/inventory/resources/items/watering_can.tres")
const LEGAL_CONTENTS := {"water_liters": 2.75}
const LEGAL_METADATA := {"quality": 0.63, "origin": {"maker": "custody fixture"}}
const EXPENSIVE_VASE := preload("res://features/inventory/resources/items/expensive_vase.tres")
const SILVER := preload("res://features/inventory/resources/items/silver.tres")

const FACTION_ID := "Farmers"
const SETTLEMENT_ID := "jail_custody"
const PLAYER_START_POSITION := Vector3(-10.0, 0.6, -7.0)
const THEFT_PICKUP_POSITION := Vector3(-7.0, 0.6, -4.8)
# Independent upper bound for these theft scenarios, not a value copied
# from the release deadline being tested. Preserve the original 11-hour gate.
const THEFT_RELEASE_LIMIT_MINUTES := 11 * 60

var _failures: Array[String] = []
var _scene: Node
const FIXTURE = preload("res://tests/validation/helpers/combat_fixture.gd")
const CONTROLLED_COMBAT = preload("res://tests/validation/helpers/law_combat_resolution_fixture.gd")
var _city_guard: HumanoidCharacter
var _jail_guard: HumanoidCharacter
var _warden: HumanoidCharacter
var _undetected_stack_id := ""
var _law_boundary_observations: Array[Dictionary] = []
var _law_impacts: Array[Dictionary] = []
var _law_probe: Callable
var _law_impact_probe: Callable
var _active_case := "fixture"
var _started_msec := Time.get_ticks_msec()


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _case_names() -> Array[String]:
	return []


func _run() -> void:
	var cases := _case_names()
	if cases.is_empty():
		_fail("Jail validator must select at least one named case")
	for case_name in cases:
		_active_case = case_name
		var before := _failures.size()
		if not has_method(case_name):
			_fail("Unknown jail case: %s" % case_name)
		elif await _load_fixture():
			await call(case_name)
		await _release_fixture()
		print("JAIL_CASE %s %s" % ["PASS" if before == _failures.size() else "FAIL", case_name])
	for failure in _failures:
		push_error(failure)
	print("LAW_ORDER_JAIL_%s cases=%d failures=%d" % ["OK" if _failures.is_empty() else "FAILED", cases.size(), _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _validate_victim_only_case() -> void:
	await _validate_victim_only_assault_clears_on_death(_get_player(), _get_law_controller(), _scene.get_node("CustodyTown"))


func _validate_cell_authoring_case() -> void:
	await _validate_jail_cell_authoring(_get_jail())


func _validate_arrest_to_release() -> void:
	await _validate_unwitnessed_stolen_metadata()
	if not await _validate_witnessed_theft_jail_release():
		_fail("Full arrest-to-release case must reach exact property return and cleared custody")


func _load_fixture() -> bool:
	await _release_fixture()
	_phase("fixture_start")
	_undetected_stack_id = ""
	_scene = CUSTODY_SCENE.instantiate()
	get_tree().node_added.connect(CONTROLLED_COMBAT.configure_controller)
	root.add_child(_scene)
	_city_guard = await FIXTURE.staff(get_tree(), SETTLEMENT_ID, SETTLEMENT_ID, "guard")
	_jail_guard = await FIXTURE.staff(get_tree(), SETTLEMENT_ID, "jail_custody.jail", "guard")
	_warden = await FIXTURE.staff(get_tree(), SETTLEMENT_ID, "jail_custody.jail", "warden")
	get_tree().node_added.disconnect(CONTROLLED_COMBAT.configure_controller)
	var gecs := BootstrapContext.service(GecsWorldController.SERVICE_ID) as GecsWorldController
	var resolution := gecs.find_child("GameCombatResolutionSystem", true, false) if gecs != null else null
	if resolution == null or resolution.get_script() != CONTROLLED_COMBAT:
		_fail("Fixture must install controlled RNG in the ordinary combat resolution slot before initialization")
		return false
	if _city_guard == null or _jail_guard == null or _warden == null:
		_fail("Registered fixture employment must realize city guard, jail guard and warden")
		return false
	# Staff availability precedes deferred navigation and projection startup.
	# Wait for the normal loading owner; never clear its pause from a fixture.
	var navigation := BootstrapContext.service(WorldNavigationController.SERVICE_ID) as WorldNavigationController
	var time := BootstrapContext.service(WorldTimeController.SERVICE_ID) as WorldTimeController
	if not await FIXTURE.wait_world_ready(get_tree()):
		_fail("Fixture must finish actual navigation startup before gameplay mode=%s pending=%s pauses=%s" % [navigation.get("_mode"), navigation.gate_tiles_pending(), time.get("_pause_reasons")])
		return false
	time.total_world_minutes = 13.0 * 60.0
	(_get_law_controller().get("_rng") as RandomNumberGenerator).seed = CONTROLLED_COMBAT.ROLL_SEED
	for actor in [_get_player(), _city_guard, _jail_guard, _warden, _scene.get_node("CustodyTown/Residents/Witness")]:
		(actor.get("_combat_rng") as RandomNumberGenerator).seed = CONTROLLED_COMBAT.ROLL_SEED
	_phase("fixture_ready")
	print("JAIL_SETUP_TRACE nav_mode=%s map_iteration=%d pending=%d" % [navigation.get("_mode"), NavigationServer3D.map_get_iteration_id((_scene as Node3D).get_world_3d().navigation_map), navigation.pending_tile_count()])
	return true

func _validate_guard_command_priority() -> void:
	var player := _get_player()
	await _validate_guard_post_preserves_combat(_scene.get_node("CustodyTown"), _city_guard, player, "Town")
	await _validate_guard_post_preserves_combat(_get_jail(), _jail_guard, player, "Jail")
	await _validate_combat_order_priority(_city_guard, player)
	await _validate_long_range_combat_chase(_city_guard, player)


func _validate_context_attack_on_guard() -> void:
	await _validate_context_attack_response(_jail_guard)


func _validate_context_attack_on_warden() -> void:
	await _validate_context_attack_response(_warden)


func _validate_context_attack_response(victim: HumanoidCharacter) -> void:
	var player := _get_player()
	var law := _get_law_controller()
	var interaction := BootstrapContext.service(WorldInteractionController.SERVICE_ID) as WorldInteractionController
	var party := _scene.get_node("PartyManager") as PartyManager
	if interaction == null:
		_fail("Context-menu Attack requires the real world interaction controller")
		return
	_city_guard.global_position = Vector3(-5.1, 0.6, -2.0)
	_jail_guard.global_position = Vector3(-8.0, 0.6, -2.0)
	_warden.global_position = Vector3(-7.0, 0.6, -4.0)
	var soldier := _make_validation_humanoid("PassingSoldier", "fixture.law.soldier", Vector3(-4.0, 0.6, 0.0))
	soldier.set_faction_soldier(true)
	soldier.set_settlement_authority(true)
	var private_guard := _make_validation_humanoid("PrivateSecurity", "fixture.law.private", Vector3(-4.0, 0.6, -4.0))
	private_guard.set_private_security(true)
	private_guard.set_faction_soldier(false)
	var ruler := _make_validation_humanoid("Ruler", "fixture.law.ruler", Vector3(-8.0, 0.6, -5.0))
	# Exercise the keep's real role classifier without an unrelated authored
	# town, terrain, shell or hand-built actor projection.
	var keep := preload("res://features/settlements/bridge/settlement_keep.gd").new()
	keep.call("_apply_authority_group", ruler, "ruler")
	ruler.set_meta("settlement_staff_role", "ruler")
	keep.free()
	var extras: Array[HumanoidCharacter] = [soldier, private_guard, ruler]
	for actor in extras:
		actor.faction_name = FACTION_ID
		actor.set_meta("settlement_id", SETTLEMENT_ID)
		_scene.add_child(actor)
	var gecs := BootstrapContext.service(GecsWorldController.SERVICE_ID) as GecsWorldController
	if not await _wait_until(func() -> bool: return extras.all(func(actor: HumanoidCharacter) -> bool: return gecs.get_actor_entity(actor) != null), 120):
		_fail("Response classification requires registered real actor projections")
		return
	if ruler.is_faction_soldier() or not ruler.is_settlement_authority() or str(gecs.get_actor_state(ruler.stable_id).get("role_id", "")) != "ruler":
		_fail("Keep ruler must register as political authority without being a law soldier")
	player.global_position = victim.global_position + Vector3(0.9, 0.0, 0.0)
	var prior_attack := _attack_sequence(player)
	var command = gecs.get_actor_entity(player).get_component(gecs.C_COMBAT_STATE)
	if not str(command.commanded_target_actor_id).is_empty():
		_fail("Context-menu fixture must begin without an existing attack command")
	party.select_only(player)
	interaction.context_humanoid = victim
	interaction.call("_on_context_menu_id_pressed", WorldInteractionController.ACTION_ATTACK)
	# Assert the actual canonical command before guards can interrupt its
	# windup. Positive impacts and nonlethal arrest have a separate oracle.
	if str(command.commanded_target_actor_id) != victim.stable_id:
		_fail("Context-menu Attack must command the exact clicked jail officer")
	var responders: Array[HumanoidCharacter] = [_city_guard, _jail_guard, _warden, soldier]
	if not await _wait_until(func() -> bool: return responders.all(func(actor: HumanoidCharacter) -> bool: return FIXTURE.is_law_response(actor, player)), 360):
		_fail("Jail assault must authorize the victim, warden, guards and passing same-settlement soldier")
	var warrant: Dictionary = law.call("get_warrant_record", player, FACTION_ID)
	if not _record_has_crime(warrant, LawOrderController.CRIME_ASSAULT):
		_fail("Context-menu jail assault must create the offender's assault warrant")
	for actor in responders + [ruler, private_guard]:
		var state := gecs.get_actor_state(actor.stable_id)
		print("LAW_AUDIENCE_TRACE ", JSON.stringify({"actor":actor.stable_id,"role":state.get("role_id"),"scopes":state.get("authority_scopes"),"party":actor.is_player_party_member(),"soldier":actor.is_faction_soldier(),"private":actor.is_private_security(),"law":FIXTURE.is_law_response(actor, player),"position":actor.global_position}))
	print("LAW_UI_ATTACK_TRACE ", JSON.stringify({"player":player.stable_id,"life":player.life_state,"position":player.global_position,"victim":victim.stable_id,"sequence":_attack_sequence(player),"prior":prior_attack,"target":str(player.get_current_combat_target())}))
	if FIXTURE.is_law_response(ruler, player):
		_fail("Political authority must not become a general law responder")
	if FIXTURE.is_law_response(private_guard, player):
		_fail("Private security must not become a general law responder")


func _validate_player_assault_local_law_response() -> void:
	var player := _get_player()
	var law := _get_law_controller()
	var town := _scene.get_node_or_null("CustodyTown") if _scene != null else null
	var jail := _get_jail()
	var city_guard := _city_guard
	var jail_guard := _jail_guard
	var warden := _warden
	if player == null or law == null or town == null or city_guard == null or jail_guard == null or warden == null:
		_fail("Player assault validation requires player, law controller, town, city guard, jail guard, and warden")
		return
	var saved_transforms := _save_actor_transforms([player, city_guard, jail_guard, warden])
	_reset_validation_combat_actors([player, city_guard, jail_guard, warden])
	law.call("_clear_warrant_for_actor", player, FACTION_ID)
	player.global_position = Vector3(-6.1, 0.6, -2.0)
	city_guard.global_position = Vector3(-5.1, 0.6, -2.0)
	jail_guard.global_position = Vector3(-8.0, 0.6, -2.0)
	warden.global_position = Vector3(-7.0, 0.6, -4.0)
	var prior_attack := _attack_sequence(player)
	player.assign_attack_target(city_guard, true, true, true)
	if not await _wait_until(func() -> bool: return _attack_started_against(player, city_guard, prior_attack), 180):
		_fail("Player Attack command must start a new GECS action against the exact authority guard")
	await _wait_until(func() -> bool: return bool(law.call("actor_has_active_warrant", player, FACTION_ID)), 120)
	var record: Dictionary = law.call("get_warrant_record", player, FACTION_ID)
	if record.is_empty() or not bool(law.call("actor_has_active_warrant", player, FACTION_ID)):
		_fail("Player-issued Attack on a settlement guard should immediately create an assault warrant")
	elif not _record_has_crime(record, LawOrderController.CRIME_ASSAULT):
		_fail("Player-issued Attack warrant should include an assault crime")
	elif str(record.get("authority_alert_mode", "")) != "local":
		_fail("Player-issued Attack should use a local combat alarm, got '%s'" % str(record.get("authority_alert_mode", "")))
	elif not bool(record.get("public_known", false)):
		_fail("Nearby same-settlement witnesses should make the assault public")
	await _wait_until(func() -> bool: return _is_law_responder_arresting_actor(city_guard, player) and _is_law_responder_arresting_actor(jail_guard, player) and _is_law_responder_arresting_actor(warden, player), 360)
	if not _is_law_responder_arresting_actor(city_guard, player):
		_fail("Attacked authority guard should answer the assault as a law arrest")
	if not _is_law_responder_arresting_actor(jail_guard, player):
		_fail("Nearby jail guard should answer the local assault alarm")
	if not _is_law_responder_arresting_actor(warden, player):
		_fail("Warden should answer detected local assault as a soldier")
	law.call("_clear_warrant_for_actor", player, FACTION_ID)
	_reset_validation_combat_actors([player, city_guard, jail_guard, warden])
	_restore_actor_transforms(saved_transforms)


func _validate_victim_only_assault_clears_on_death(player: HumanoidCharacter, law: Node, town: Node) -> void:
	if player == null or law == null or town == null:
		_fail("Victim-only assault validation requires player, law controller, and town")
		return
	var saved_transforms := _save_actor_transforms([player])
	var victim := _make_validation_humanoid("IsolatedAssaultVictim", "npc.jail_custody.isolated_victim", Vector3(70.0, 0.6, 0.0))
	victim.set("faction_name", FACTION_ID)
	town.add_child(victim)
	await _wait_frames(8)
	_reset_validation_combat_actors([player, victim])
	law.call("_clear_warrant_for_actor", player, FACTION_ID)
	player.global_position = Vector3(69.2, 0.6, 0.0)
	var prior_attack := _attack_sequence(player)
	player.assign_attack_target(victim, true, true, true)
	if not await _wait_until(func() -> bool: return _attack_started_against(player, victim, prior_attack), 180):
		_fail("Isolated assault must start a new GECS action against the exact victim")
	await _wait_until(func() -> bool: return bool(law.call("actor_has_active_warrant", player, FACTION_ID)), 120)
	var record: Dictionary = law.call("get_warrant_record", player, FACTION_ID)
	print("VICTIM_ONLY_TRACE actor=%s victim=%s attack_sequence=%d warrant=%s" % [player.stable_id, victim.stable_id, _attack_sequence(player), record])
	if record.is_empty() or not bool(law.call("actor_has_active_warrant", player, FACTION_ID)):
		_fail("Victim-only player assault should create an active provisional warrant while the victim lives")
	elif bool(record.get("public_known", false)):
		_fail("Victim-only assault should not become public without a nearby civilian or guard witness")
	victim.set("_last_direct_attacker_id", player.get_instance_id())
	victim.force_kill(player)
	# The law maintenance pass revisits active encounter aggression. Verify the
	# dead sole witness's case stays gone across that pass, not only at death.
	await _wait_frames(60)
	if victim.life_state != NpcRules.LifeState.DEAD:
		_fail("Victim-only cleanup must observe actual persistent death, not only disappearance of a warrant")
	if bool(law.call("actor_has_active_warrant", player, FACTION_ID)):
		_fail("Victim-only assault and murder should clear when the only witness dies")
	_reset_validation_combat_actors([player, victim])
	law.call("_clear_warrant_for_actor", player, FACTION_ID)
	victim.queue_free()
	_restore_actor_transforms(saved_transforms)


func _validate_expired_warrant_cleanup() -> void:
	var player := _get_player()
	var law := _get_law_controller()
	var world_time := _get_world_time_controller()
	var city_guard := _city_guard
	if player == null or law == null or world_time == null or city_guard == null:
		_fail("Expired warrant cleanup validation requires player, law controller, world time, and city guard")
		return
	var saved_transforms := _save_actor_transforms([player, city_guard])
	_reset_validation_combat_actors([player, city_guard])
	law.call("_clear_warrant_for_actor", player, FACTION_ID)
	player.global_position = city_guard.global_position + Vector3(0.9, 0.0, 0.0)
	law.call("report_crime", player, FACTION_ID, SETTLEMENT_ID, LawOrderController.CRIME_THEFT, 1, city_guard, city_guard)
	var responses := BootstrapContext.service(GameCombatResponseSystem.SERVICE_ID) as GameCombatResponseSystem
	var response_world = (BootstrapContext.service(GecsWorldController.SERVICE_ID) as GecsWorldController).world
	var response_deadline := Time.get_ticks_msec() + 2000
	while not _is_law_responder_arresting_actor(city_guard, player) and Time.get_ticks_msec() < response_deadline:
		await process_frame
	if not _is_law_responder_arresting_actor(city_guard, player):
		_fail("Expiry fixture must first establish the exact guard's active law response")
	if str(player.call("get_legal_status").status_label).is_empty() or not bool(law.call("actor_has_active_warrant", player, FACTION_ID)):
		_fail("Witnessed theft should create visible law status before warrant expiry")
	var before_expiry: Dictionary = law.call("get_warrant_record", player, FACTION_ID)
	var authority_id := str(before_expiry.get("response_authority_id", ""))
	var queued_before := _pending_revoke_ids(response_world, authority_id, player.stable_id)
	var process_before := Engine.get_process_frames()
	world_time.call("advance_days", 2.0)
	var revoke_ids: Array[String] = []
	for event_id in _pending_revoke_ids(response_world, authority_id, player.stable_id):
		if not queued_before.has(event_id):
			revoke_ids.append(event_id)
	if authority_id.is_empty() or revoke_ids.size() != 1:
		_fail("Expiry must enqueue exactly one revoke for the active warrant authority: %s" % revoke_ids)
	var consume_deadline := Time.get_ticks_msec() + 2000
	while not revoke_ids.is_empty() and response_world.get_entity_by_id(revoke_ids[0]) != null and Time.get_ticks_msec() < consume_deadline:
		await process_frame
	var consumed := revoke_ids.size() == 1 and response_world.get_entity_by_id(revoke_ids[0]) == null
	if not consumed:
		_fail("Expiry revoke must be consumed by the actual process-driven response system")
	print("LAW_EXPIRY_CONSUMED authority=%s events=%s consumed=%s process_frames=%d intents=%s" % [authority_id, revoke_ids, consumed, Engine.get_process_frames() - process_before, JSON.stringify(responses.get_active_intents())])
	if bool(law.call("actor_has_active_warrant", player, FACTION_ID)):
		_fail("Expired warrant should clear the active warrant record")
	if not str(player.call("get_legal_status").status_label).is_empty() or not str(player.call("get_legal_status").warrant_summary).is_empty():
		_fail("Expired warrant should clear actor law status metadata")
	for _frame in range(3):
		await process_frame
		if responses.has_active_authority_response(authority_id, player.stable_id) or _is_law_responder_arresting_actor(city_guard, player) or city_guard.has_hostility_with(player) or city_guard.get_current_combat_target() == player:
			_fail("Consumed expiry revoke must remove matching authority and subsequent guard hostility/targeting")
			break
	_reset_validation_combat_actors([player, city_guard])
	_restore_actor_transforms(saved_transforms)


func _pending_revoke_ids(response_world, authority_id: String, actor_id: String) -> Array[String]:
	var ids: Array[String] = []
	for entity in response_world.query.with_all([CGameCombatEvent]).execute():
		var event = entity.get_component(CGameCombatEvent)
		if event.type == CGameCombatEvent.Type.RESPONSE_REVOKED and event.authority_id == authority_id and event.target_actor_id == actor_id:
			ids.append(str(entity.id))
	return ids


func _validate_unwitnessed_stolen_metadata() -> void:
	var player := _get_player()
	var law := _get_law_controller()
	if player == null or law == null:
		_fail("Player and LawOrderController should exist for unwitnessed theft validation")
		return
	var hidden_item := WORLD_ITEM_SCENE.instantiate() as WorldItem
	hidden_item.name = "HiddenOwnedVase"
	hidden_item.item_definition = EXPENSIVE_VASE
	hidden_item.owner_faction_name = FACTION_ID
	hidden_item.theft_value = 10
	hidden_item.theft_noise_radius = 0.0
	_scene.add_child(hidden_item)
	hidden_item.global_position = Vector3(44.0, 0.45, 0.0)
	player.global_position = Vector3(44.0, 0.6, -1.0)
	var picked_up := hidden_item.try_pickup(player)
	await _wait_frames(4)
	if not picked_up:
		_fail("Unwitnessed owned item pickup should succeed")
		return
	var entry: InventoryData.InventoryEntry = _find_inventory_entry(player.inventory, EXPENSIVE_VASE)
	if entry == null:
		_fail("Unwitnessed stolen item should enter player inventory")
		return
	if not player.inventory.is_entry_stolen(entry):
		_fail("Unwitnessed theft should still mark the item as stolen")
	if bool(law.call("actor_has_active_warrant", player, FACTION_ID)):
		_fail("Unwitnessed theft should not create an active warrant")
	_undetected_stack_id = entry.stack_id
	player.global_position = PLAYER_START_POSITION


func _validate_arrest_only() -> void:
	await _validate_unwitnessed_stolen_metadata()
	if (await _arrest_for_theft()).is_empty():
		_fail("Arrest case must complete the exact-officer, nonlethal knockout boundary")


func _arrest_for_theft() -> Dictionary:
	var player := _get_player()
	var law := _get_law_controller()
	var world_time := _get_world_time_controller()
	var jail := _get_jail()
	var city_guard := _city_guard
	var warden := _warden
	var vase := _scene.get_node_or_null("CustodyTown/OwnedVase") as WorldItem
	if player == null or law == null or world_time == null or jail == null or city_guard == null or warden == null or vase == null:
		_fail("Custody fixture should provide player, law controller, world time, jail, warden, city guard, and owned vase")
		return {}
	var legal_property := _seed_legal_property(player)
	if legal_property.is_empty():
		return {}
	player.global_position = THEFT_PICKUP_POSITION
	# Assignment staff have randomized ambient placement. Make the named city
	# guard the nearest approaching officer, without selecting a combat target
	# or removing the civilian, warden or other guard from the real encounter.
	city_guard.global_position = player.global_position + Vector3(-2.0, 0.0, 0.0)
	var lifecycle := BootstrapContext.service(ItemLifecycleController.SERVICE_ID) as ItemLifecycleController
	var inventory_before := FIXTURE.inventory_snapshot(player.inventory)
	var world_stack_before := lifecycle.get_stack_record(vase.stack_id)
	var vase_stack_id := vase.stack_id
	_configure_arrest_combat(city_guard, player)
	_start_law_boundary_probe(player, city_guard)
	var picked_up := vase.try_pickup(player)
	if picked_up:
		_fail("Caught theft must be refused by canonical ownership")
	if FIXTURE.inventory_snapshot(player.inventory) != inventory_before:
		_fail("Refused witnessed theft must not mutate any inventory entry or allocation state")
	if lifecycle.get_stack_record(vase_stack_id) != world_stack_before or not is_instance_valid(vase):
		_fail("Refused witnessed theft must not remove or mutate the exact authored world stack")
	await _wait_frames(8)
	var stolen_entry: InventoryData.InventoryEntry = _find_inventory_entry(player.inventory, EXPENSIVE_VASE)
	if stolen_entry == null or stolen_entry.stack_id != _undetected_stack_id or not player.inventory.is_entry_stolen(stolen_entry):
		_fail("The separately successful undetected theft must supply the exact contraband stack for custody")
		return {}
	var stolen_property := _entry_payload(stolen_entry)
	if not bool(law.call("actor_has_active_warrant", player, FACTION_ID)):
		_fail("Witnessed theft should create a faction warrant")
	await _wait_until(func() -> bool: return FIXTURE.is_law_response(city_guard, player), 360)
	if not FIXTURE.is_law_response(city_guard, player):
		_fail("Refused witnessed theft must still authorize the exact city-guard-to-player law response")
	if warden.has_hostility_with(city_guard) or warden.get_current_combat_target() == city_guard:
		_fail("Jail warden should not defend the thief by fighting the city guard")
	_phase("arrest_combat_start")
	var live_combat_resolved := await _validate_live_law_combat(city_guard, player)
	_phase("arrest_combat_end")
	_stop_law_probe()
	print("LAW_BOUNDARY_TRACE observations=%s impacts=%s" % [JSON.stringify(_law_boundary_observations), JSON.stringify(_law_impacts)])
	if player.life_state == NpcRules.LifeState.DEAD:
		_fail("Authority arrest damage should not kill a wanted actor")
		return {}
	if not player.is_downed_state():
		_fail("Authority arrest damage should knock out a wanted actor")
		return {}
	if player.hp <= player.get_death_point(player.max_hp):
		_fail("Authority arrest damage should clamp HP above the death threshold")
	if player.blood < 80.0:
		_fail("Authority arrest damage should not cause severe blood loss")
	if not live_combat_resolved:
		return {}
	return {"legal": legal_property, "stolen": stolen_property}


func _validate_witnessed_theft_jail_release() -> bool:
	var property := await _arrest_for_theft()
	if property.is_empty():
		return false
	var player := _get_player()
	var law := _get_law_controller()
	var jail := _get_jail()
	var warden := _warden
	var legal_property: Dictionary = property.legal
	var stolen_property: Dictionary = property.stolen
	# Arrest is already proved by attributed impacts and actual knock-out.
	# Keep a genuinely wounded canonical body through the physical lay test;
	# the law clamp's -1 HP otherwise heals during the walk while held down.
	player.get_vitals().set_blunt_damage(player.max_hp + 8.0)
	if player.life_state != NpcRules.LifeState.UNCONSCIOUS:
		_fail("Cell placement fixture must begin with canonical unconscious wounds")
	law.call("_process_warrants")
	await _wait_frames(2)
	if bool(player.call("is_law_prisoner")):
		_fail("Unconscious wanted actor should not teleport directly into jail")
	if player.inventory.count_item(LEGAL_ITEM) != 1 or player.inventory.count_item(EXPENSIVE_VASE) != 1:
		_fail("Jail intake should not confiscate inventory before cell placement")
	var carried := await _wait_until(func() -> bool: return _find_guard_carrying_actor(player) != null, 180)
	var custody_guard := _find_guard_carrying_actor(player)
	if not carried:
		_fail("Authority guard should carry the unconscious wanted actor before jail intake")
		return false
	if bool(player.call("is_law_prisoner")):
		_fail("Carried actor should not be finalized as a prisoner before cell placement")
	if bool(jail.call("is_actor_inside_jail", custody_guard)):
		_fail("First custody route must start outside the jail, not already at a cell")
	_print_custody_route(custody_guard, jail)
	var jailed := await _wait_for_intake(player, custody_guard, jail, 2400, 6.0)
	if not jailed:
		_print_custody_route(custody_guard, jail)
		_fail("Carried wanted actor should be placed in a jail cell and admitted guard_order=%s guard_carried=%s guard_has_move=%s guard_move=%s guard_pos=%s player_life=%s player_pos=%s player_carried=%s" % [str(custody_guard.get_current_order_type() if custody_guard != null else -1), str(custody_guard.get_carried_character() if custody_guard != null else null), str(custody_guard.has_move_target() if custody_guard != null else false), str(custody_guard.get_move_target() if custody_guard != null else Vector3.ZERO), str(custody_guard.global_position if custody_guard != null else Vector3.ZERO), str(player.life_state), str(player.global_position), str(player.is_carried())])
		return false
	_phase("cell_intake")
	await _validate_cell_lay_building_visibility(player, jail)
	if custody_guard != null and (warden.has_hostility_with(custody_guard) or warden.get_current_combat_target() == custody_guard):
		_fail("Jail warden should not become hostile to the arresting guard during custody")
	var cell := _find_cell_holding(jail, player)
	if cell == null:
		_fail("Jail admission should assign the prisoner to a cell")
	else:
		var prisoner_position: Vector3 = cell.call("get_prisoner_position", player)
		if player.global_position.distance_to(prisoner_position) > 0.35:
			_fail("Prisoner should be placed at the authored cell prisoner point")
		var prisoner_rotation: Vector3 = cell.call("get_prisoner_rotation", player)
		if absf(angle_difference(player.global_rotation.y, prisoner_rotation.y)) > 0.1:
			_fail("Prisoner should face the authored cell prisoner direction")
	if player.is_carried() or _find_guard_carrying_actor(player) != null:
		_fail("Prisoner should no longer be carried after cell placement")
	if not bool(player.call("is_in_cell_custody")):
		_fail("Prisoner should enter locked cell custody after placement")
	if bool(player.call("is_ragdoll_active")):
		_fail("Prisoner should not keep ragdoll simulation active in the cell")
	var lay_frozen := await _wait_until(func() -> bool: return bool(player.get("_cell_custody_lay_pose_frozen")), 420)
	if not lay_frozen:
		_fail("Unconscious prisoner should settle into the cell lay pose anim=%s remaining=%.3f current=%s life=%s" % [str(player.get("_cell_custody_unconscious_pose_animation")), float(player.get("_cell_custody_lay_freeze_remaining")), _get_current_animation(player), str(player.life_state)])
	if custody_guard != null and custody_guard.has_hostility_with(player):
		_fail("Authority guard should disengage combat after custody placement")
	if not bool(player.call("is_law_prisoner")):
		_fail("Unconscious wanted actor should be admitted to jail")
	if player.inventory.count_item(LEGAL_ITEM) != 0 or player.inventory.count_item(EXPENSIVE_VASE) != 0:
		_fail("Jail intake should confiscate legal and stolen inventory")
	var locker = jail.call("get_prisoner_locker")
	var locker_inventory = locker.get("inventory") if locker != null else null
	if locker_inventory == null:
		_fail("Jail should have a prisoner locker inventory after intake")
	elif locker_inventory.count_item(LEGAL_ITEM) != 1 or locker_inventory.count_item(EXPENSIVE_VASE) != 1:
		_fail("Prisoner locker should hold confiscated legal and stolen items")
	if locker_inventory != null:
		_validate_confiscated_records(locker, player.stable_id, [legal_property, stolen_property], "intake")
		if _entry_payload(_find_inventory_entry(locker_inventory, LEGAL_ITEM), true) != legal_property or _entry_payload(_find_inventory_entry(locker_inventory, EXPENSIVE_VASE), true) != stolen_property:
			_fail("Intake must preserve both exact stack IDs, counts, contents and original metadata")
		var exact_contraband := false
		for entry in locker_inventory.entries:
			if entry.stack_id == _undetected_stack_id and entry.definition == EXPENSIVE_VASE and entry.count == 1:
				exact_contraband = true
		if not exact_contraband:
			_fail("Confiscation must transfer the exact successfully undetected world stack, not a replacement vase")
	print("JAIL_LIFECYCLE_TRACE stage=unconscious_cell_intake legal_stack=%s stolen_stack=%s life=%d" % [legal_property.stack_id, stolen_property.stack_id, player.life_state])
	await _recover_prisoner(player)
	await _validate_sentence_delivery(player)
	await _validate_sentence_release(player, legal_property, stolen_property)
	return true


func _recover_prisoner(player: HumanoidCharacter) -> void:
	var healing_rate := player.get_vitals()._get_healing_rate()
	var recovery_frames := int(ceil((maxf(-player.hp, 0.0) / maxf(healing_rate, 0.001) + 2.0) * Engine.physics_ticks_per_second))
	print("JAIL_LIFECYCLE_TRACE stage=recovery hp=%s healing_rate=%s frame_bound=%d" % [player.hp, healing_rate, recovery_frames])
	_phase("recovery_start")
	var woke := await _wait_until(func() -> bool: return player.life_state == NpcRules.LifeState.ALIVE, recovery_frames)
	_phase("recovery_end")
	if not woke:
		_fail("Prisoner should wake in cell after recovery delay")
	var wake_animation := str(player.get("_cell_custody_wake_animation"))
	if wake_animation.is_empty() or _get_current_animation(player) != wake_animation:
		_fail("Recovered prisoner must perform its configured wake animation")
	if not await _wait_until(func() -> bool: return str(player.get("_cell_custody_wake_animation")).is_empty(), 240):
		_fail("Recovered prisoner must finish waking and return to normal idle")


func _recreate_prisoner(player: HumanoidCharacter, legal_property: Dictionary, stolen_property: Dictionary) -> HumanoidCharacter:
	var jail := _get_jail()
	# Discard the actual projection and realize a new body from the permanent
	# record. Toggling custody on the same node cannot prove an LOD boundary.
	var pre_lod_cell := _find_cell_holding(jail, player)
	var population := BootstrapContext.service(PopulationController.SERVICE_ID) as PopulationController
	var actor_key := player.stable_id
	var sentence_before: Dictionary = _get_law_controller().get("prisoner_records").get(actor_key, {}).duplicate(true)
	if sentence_before.is_empty():
		_fail("Prisoner recreation requires its existing durable sentence schedule")
		return null
	var old_instance_id := player.get_instance_id()
	var party := _scene.get_node("PartyManager") as PartyManager
	party.set_followed_member(player)
	var actor_parent := player.get_parent()
	var actor_name := player.name
	if population.get_actor_record(actor_key).is_empty():
		_fail("Prisoner must have a permanent population record before projection round-trip")
		return null
	population.unregister_actor(player)
	player.queue_free()
	var discarded := await _wait_until(func() -> bool: return not is_instance_id_valid(old_instance_id) and population.get_live_actor(actor_key) == null, 180)
	if not discarded:
		_fail("Prisoner projection must actually be discarded before re-realization")
		return null
	if str(population.get_actor_record(actor_key).get("party_id", "")) != PartyManager.PLAYER_PARTY_ID or not pre_lod_cell.occupant_ids.has(actor_key):
		_fail("Offscreen prisoner must retain durable party membership and reserved cell occupancy")
	var realizer := BootstrapContext.service(PopulationCharacterRealizer.SERVICE_ID) as PopulationCharacterRealizer
	player = realizer.realize_record_actor(actor_key, actor_parent, actor_name) as HumanoidCharacter
	if player == null:
		_fail("Permanent prisoner record must realize a new humanoid projection")
		return null
	var restored := await _wait_until(func() -> bool: return player.is_in_cell_custody(), 180)
	if not restored or player.get_instance_id() == old_instance_id or player.stable_id != actor_key:
		_fail("New prisoner projection must preserve stable identity and regain custody")
	if not party.party_members.has(player) or not party.selected_members.has(player) or party.followed_member != player:
		_fail("The same prisoner identity must automatically rebind party membership, selection and follow")
	var post_lod_cell := _find_cell_holding(jail, player)
	if post_lod_cell == null or post_lod_cell != pre_lod_cell:
		_fail("New prisoner projection must return to the same durable cell")
	var sentence_after: Dictionary = _get_law_controller().get("prisoner_records").get(actor_key, {})
	for deadline in ["sentence_decision_at_minute", "release_at_minute"]:
		if not sentence_before.has(deadline) or sentence_after.get(deadline) != sentence_before.get(deadline):
			_fail("Prisoner recreation must not reroll recorded sentencing deadlines (%s)" % deadline)
	_validate_confiscated_records(jail.call("get_prisoner_locker"), actor_key, [legal_property, stolen_property], "after_prisoner_recreation")
	if player.inventory.count_item(LEGAL_ITEM) != 0 or player.inventory.count_item(EXPENSIVE_VASE) != 0:
		_fail("Prisoner recreation must not duplicate confiscated property into the new body's inventory")
	print("JAIL_LIFECYCLE_TRACE stage=prisoner_re_realized old_instance=%d new_instance=%d actor=%s cell=%s" % [old_instance_id, player.get_instance_id(), actor_key, player.get_legal_status().cell_id])
	_phase("projection_recreated")
	return player


func _validate_sentence_delivery(player: HumanoidCharacter, elevated_post := false) -> void:
	var jail := _get_jail()
	var law := _get_law_controller()
	var warden := _warden
	var warden_ground_y := warden.global_position.y
	var warden_post := _get_warden_home_post(jail)
	if warden_post == null:
		_fail("Jail should have a warden post before sentence delivery")
		return
	var original_post_position := warden_post.global_position
	if elevated_post:
		warden_post.global_position.y = warden_ground_y + 1.25
	_advance_to_sentence_decision(law, player)
	law.call("_process_prisoners")
	var sentence_delivered := await _wait_until(func() -> bool: return _sentence_notification_given(law, player), 1500)
	if not sentence_delivered:
		print("JAIL_SENTENCE_TRACE prisoner_record=%s warden_live=%s post=%s" % [JSON.stringify(law.get("prisoner_records").get(player.stable_id, {})), is_instance_valid(warden), warden_post.global_position])
		if is_instance_valid(warden):
			_print_sentence_route(warden, jail)
		_fail("Warden should tell the prisoner their sentence before release; post-return coverage is blocked until delivery succeeds")
		_phase("sentence_delivery_failed")
	else:
		_phase("sentence_delivered")
		var conversation := BootstrapContext.service(ConversationController.SERVICE_ID) as ConversationController
		if conversation == null or conversation.active_speaker != warden or conversation.active_target != player or not is_instance_valid(conversation.conversation_window) or not conversation.conversation_window.visible:
			_fail("Delivered sentence must open the visible conversation for the exact warden and prisoner")
		_close_active_conversation()
		var warden_returned := await _wait_until(func() -> bool: return _is_warden_at_home_post(jail, warden), 900)
		if not warden_returned:
			var post := _get_warden_home_post(jail)
			_fail("Warden should return to the warden post after sentencing warden_pos=%s post_pos=%s law_returning=%s sentence_move=%s has_move=%s move_target=%s" % [str(warden.global_position), str(post.global_position if post != null else Vector3.ZERO), str(warden.call("is_law_custody_returning") if warden.has_method("is_law_custody_returning") else false), str(warden.call("is_law_sentence_moving") if warden.has_method("is_law_sentence_moving") else false), str(warden.get("_has_move_target")), str(warden.get("_move_target"))])
		if absf(warden.global_position.y - warden_ground_y) > 0.08:
			_fail("Warden should not snap to the elevated warden-post marker height warden_y=%.3f expected_y=%.3f post_y=%.3f" % [warden.global_position.y, warden_ground_y, warden_post.global_position.y])
		_phase("warden_return_checked")
	warden_post.global_position = original_post_position


func _validate_sentence_release(player: HumanoidCharacter, legal_property: Dictionary, stolen_property: Dictionary) -> void:
	var jail := _get_jail()
	var law := _get_law_controller()
	var world_time := _get_world_time_controller()
	var cell := _find_cell_holding(jail, player)
	var locker_inventory: InventoryData = jail.call("get_prisoner_locker").get("inventory")
	var lifecycle := BootstrapContext.service(ItemLifecycleController.SERVICE_ID) as ItemLifecycleController
	if cell == null or locker_inventory == null:
		_fail("Release must start with real cell occupancy and confiscated property")
		return
	# Validate the duration independently before following the recorded
	# deadline through the real clock. Never forge release/notification flags.
	_advance_to_sentence_decision(law, player)
	law.call("_process_prisoners")
	var record: Dictionary = law.get("prisoner_records").get(player.stable_id, {})
	var release_at := int(record.get("release_at_minute", -1))
	if release_at < 0:
		_fail("Sentence decision must record its real release deadline")
		return
	var sentence_started := int(record.get("sentence_started_at_minute", -1))
	var duration := release_at - sentence_started
	if sentence_started < 0 or duration <= 0 or duration > THEFT_RELEASE_LIMIT_MINUTES:
		_fail("Theft sentence must release within the independent duration limit expected_max=%d actual=%d" % [THEFT_RELEASE_LIMIT_MINUTES, duration])
	world_time.call("advance_minutes", maxf(0.0, release_at - 1 - world_time.call("get_absolute_minute")))
	law.call("_process_prisoners")
	if not player.is_law_prisoner() or player.inventory.count_item(LEGAL_ITEM) != 0:
		_fail("Prisoner and legal property must remain in custody before the sentence deadline")
	world_time.call("advance_minutes", maxf(0.0, release_at + 1 - world_time.call("get_absolute_minute")))
	law.call("_process_prisoners")
	await _wait_frames(8)
	if bool(player.call("is_law_prisoner")):
		_fail("Sentence expiry should release the prisoner")
	_validate_physical_release(player, "Sentence release")
	if player.inventory.count_item(LEGAL_ITEM) != 1:
		_fail("Legal confiscated item should be returned on release")
	if _entry_payload(_find_inventory_entry(player.inventory, LEGAL_ITEM)) != legal_property:
		_fail("Sentence release must return the exact legal stack, contents and original metadata")
	if player.inventory.count_item(EXPENSIVE_VASE) != 0:
		_fail("Stolen goods should be forfeited on legal release")
	if bool(law.call("actor_has_active_warrant", player, FACTION_ID)):
		_fail("Release after sentence should clear the active warrant")
	if law.get("prisoner_records").has(player.stable_id) or cell.call("has_occupant", player) or locker_inventory.count_item(LEGAL_ITEM) != 0 or locker_inventory.count_item(EXPENSIVE_VASE) != 0:
		_fail("Sentence release must remove durable custody and settle both locker stacks exactly once")
	_validate_returned_property(player, legal_property, "sentence_release")
	if not (BootstrapContext.service(GecsWorldController.SERVICE_ID) as GecsWorldController).get_item_stack(stolen_property.stack_id).is_empty() or not lifecycle.get_stack_record(stolen_property.stack_id).is_empty():
		_fail("Sentence release must destroy the exact forfeited contraband stack in both durable and lifecycle views")
	print("JAIL_LIFECYCLE_TRACE stage=sentence_release legal_stack=%s stolen_forfeited=%s" % [legal_property.stack_id, stolen_property.stack_id])


func _seed_legal_property(prisoner: HumanoidCharacter) -> Dictionary:
	# Nonempty nested metadata and liquid contents must survive confiscation,
	# projection loss and return, not just an empty payload with the right ID.
	if not prisoner.inventory.add_entry_with_contents(LEGAL_ITEM, 1, LEGAL_CONTENTS, LEGAL_METADATA):
		_fail("Custody fixture must create contents-bearing legal property")
		return {}
	var payload := _entry_payload(_find_inventory_entry(prisoner.inventory, LEGAL_ITEM))
	if payload.get("contents", {}) != LEGAL_CONTENTS or payload.get("metadata", {}) != LEGAL_METADATA:
		_fail("Legal property fixture must contain its distinctive contents and metadata")
		return {}
	return payload


func _prepare_custody(with_contraband := false) -> Dictionary:
	# Independent downstream setup. This is still the real report/carry/intake
	# route, but does not depend on winning a fight or a previous case's release.
	var prisoner := _get_player()
	var legal_property := _seed_legal_property(prisoner)
	if legal_property.is_empty():
		return {}
	var property := {"legal": legal_property}
	if with_contraband:
		await _validate_unwitnessed_stolen_metadata()
		property["stolen"] = _entry_payload(_find_inventory_entry(prisoner.inventory, EXPENSIVE_VASE))
		if property.stolen.is_empty():
			_fail("Custody fixture requires its own exact undetected contraband")
			return {}
	prisoner.global_position = THEFT_PICKUP_POSITION
	FIXTURE.reset_order(_city_guard)
	_city_guard.global_position = prisoner.global_position + Vector3(-2.0, 0.0, 0.0)
	if not await _carry_into_custody(prisoner):
		return {}
	return property


func _carry_into_custody(prisoner: HumanoidCharacter) -> bool:
	# Shared real intake for fresh and repeat custody. Do not reset the actor's
	# released state, create replacement property, or forge a prisoner record.
	var law := _get_law_controller()
	var jail := _get_jail()
	law.call("report_crime", prisoner, FACTION_ID, SETTLEMENT_ID, LawOrderController.CRIME_THEFT, 3, _city_guard, _city_guard)
	prisoner.get_vitals().set_blunt_damage(prisoner.max_hp + 8.0)
	if prisoner.life_state != NpcRules.LifeState.UNCONSCIOUS:
		_fail("Custody fixture must begin with genuinely wounded canonical unconscious vitals")
		return false
	law.call("_process_warrants")
	if not await _wait_until(func() -> bool: return _find_guard_carrying_actor(prisoner) != null, 360):
		_fail("Custody fixture must physically carry the prisoner")
		return false
	var custody_guard := _find_guard_carrying_actor(prisoner)
	if not await _wait_for_intake(prisoner, custody_guard, jail, 2400):
		_fail("Custody fixture must complete real cell placement and intake")
		return false
	return true


func _wake_fixture_prisoner(prisoner: HumanoidCharacter) -> void:
	# Sentence/projection cases supply an awake prisoner as an input. Natural
	# recovery and both lay/wake animations remain in the full-route case.
	prisoner.get_vitals().set_blunt_damage(0.0)
	if not await _wait_until(func() -> bool: return prisoner.life_state == NpcRules.LifeState.ALIVE and str(prisoner.get("_cell_custody_wake_animation")).is_empty(), 240):
		_fail("Downstream fixture must reach an awake, settled prisoner before its check")


func _validate_sentence_case() -> void:
	var property := await _prepare_custody(true)
	if property.is_empty():
		return
	await _wake_fixture_prisoner(_get_player())
	await _validate_sentence_delivery(_get_player())


func _validate_elevated_warden_post() -> void:
	var property := await _prepare_custody()
	if property.is_empty():
		return
	await _wake_fixture_prisoner(_get_player())
	await _validate_sentence_delivery(_get_player(), true)


func _validate_prisoner_recreation() -> void:
	var property := await _prepare_custody(true)
	if property.is_empty():
		return
	await _wake_fixture_prisoner(_get_player())
	var player := await _recreate_prisoner(_get_player(), property.legal, property.stolen)
	if player != null:
		await _validate_sentence_release(player, property.legal, property.stolen)


func _validate_pending_sentence_recreation() -> void:
	var property := await _prepare_custody(true)
	if property.is_empty():
		return
	var law := _get_law_controller()
	var player := _get_player()
	await _wake_fixture_prisoner(player)
	_advance_to_sentence_decision(law, player)
	law.call("_process_prisoners")
	if not bool(law.call("has_pending_prisoner_sentence_notification", player)):
		_fail("Pending-notification recreation must first queue the real sentence")
		return
	player = await _recreate_prisoner(player, property.legal, property.stolen)
	if player == null:
		return
	if not bool(law.call("has_pending_prisoner_sentence_notification", player)):
		_fail("Prisoner recreation must preserve the undelivered sentence for the same identity")
	await _validate_sentence_delivery(player)
	await _validate_sentence_release(player, property.legal, property.stolen)


func _validate_physical_release(prisoner: HumanoidCharacter, stage: String) -> void:
	if prisoner.is_in_cell_custody() or prisoner.get_cell_custody_target() != null or prisoner.is_carried():
		_fail("%s must clear physical custody, not only legal status and cell occupancy" % stage)


func _validate_repeat_custody() -> void:
	var property := await _prepare_custody(true)
	if property.is_empty():
		return
	var prisoner := _get_player()
	await _wake_fixture_prisoner(prisoner)
	await _validate_sentence_release(prisoner, property.legal, property.stolen)
	await _repeat_custody_and_bail(prisoner, property.legal)


func _repeat_custody_and_bail(prisoner: HumanoidCharacter, legal_property: Dictionary) -> void:
	if prisoner.is_law_prisoner() or prisoner.is_in_cell_custody() or _entry_payload(_find_inventory_entry(prisoner.inventory, LEGAL_ITEM)) != legal_property:
		_fail("Repeat custody requires the same released prisoner and exact returned legal stack")
		return
	var identity := prisoner.stable_id
	var instance_id := prisoner.get_instance_id()
	if not await _carry_into_custody(prisoner):
		_fail("Second arrest must physically carry and admit the same released prisoner")
		return
	if prisoner.stable_id != identity or prisoner.get_instance_id() != instance_id:
		_fail("Repeat custody must not replace the released prisoner")
	_validate_confiscated_records(_get_jail().call("get_prisoner_locker"), identity, [legal_property], "repeat_intake")
	_validate_bail_transaction(prisoner, legal_property)
	print("JAIL_LIFECYCLE_TRACE stage=repeat_custody_complete actor=%s instance=%d legal_stack=%s" % [identity, instance_id, legal_property.stack_id])


func _validate_bail_release() -> void:
	var property := await _prepare_custody()
	if property.is_empty():
		return
	_validate_bail_transaction(_get_player(), property.legal)


func _validate_bail_transaction(prisoner: HumanoidCharacter, returned_property: Dictionary) -> void:
	var law := _get_law_controller()
	var jail := _get_jail()
	var payer := _scene.get_node("CustodyTown/Residents/Witness") as HumanoidCharacter
	var cell := _find_cell_holding(jail, prisoner)
	var record: Dictionary = law.get("prisoner_records").get(prisoner.stable_id, {})
	if cell == null or int(record.get("bad_person_points", -1)) != 3 or prisoner.inventory.count_item(LEGAL_ITEM) != 0:
		_fail("Bail case must preserve severity three and confiscate the returned legal stack")
		return
	var party := _scene.get_node("PartyManager") as PartyManager
	party.register_party_member(payer)
	var expected_cost := LawOrderController.BAIL_BASE_COST + LawOrderController.BAIL_COST_PER_SEVERITY * 3
	var silver_before := payer.inventory.count_item(SILVER)
	var inventory_before := FIXTURE.inventory_snapshot(payer.inventory)
	if silver_before >= expected_cost:
		_fail("Unfunded bail fixture must begin below the required silver cost")
	var unfunded_eligible := bool(law.call("can_pay_bail", payer, jail))
	var unfunded_paid := bool(law.call("pay_bail", payer, jail))
	if unfunded_eligible or unfunded_paid:
		_fail("Unfunded bail must be refused")
	if FIXTURE.inventory_snapshot(payer.inventory) != inventory_before or not prisoner.is_law_prisoner() or not cell.call("has_occupant", prisoner):
		_fail("Refused bail must conserve exact payer inventory and custody")
	if not payer.inventory.add_item_count(SILVER, expected_cost):
		_fail("Bail payer must receive real silver before payment")
		return
	silver_before = payer.inventory.count_item(SILVER)
	var quoted_cost := int(law.call("get_bail_cost", payer, jail))
	print("JAIL_BAIL_TRACE expected=%d quoted=%d record=%s" % [expected_cost, quoted_cost, JSON.stringify(record)])
	if quoted_cost != expected_cost or not bool(law.call("can_pay_bail", payer, jail)):
		_fail("Bail should cost base plus severity for jailed party companions expected=%d actual=%d points=%d" % [expected_cost, quoted_cost, int(record.get("bad_person_points", -1))])
	# A price failure must not short-circuit the real payment/release coverage.
	var paid := bool(law.call("pay_bail", payer, jail))
	if not paid:
		_fail("Funded bail payment should release the prisoner")
	if payer.inventory.count_item(SILVER) != silver_before - expected_cost:
		_fail("Bail payment should remove the exact silver cost expected=%d actual=%d" % [expected_cost, silver_before - payer.inventory.count_item(SILVER)])
	if prisoner.is_law_prisoner() or cell.call("has_occupant", prisoner):
		_fail("Bail should clear prisoner status and cell occupancy")
	_validate_physical_release(prisoner, "Bail release")
	if _entry_payload(_find_inventory_entry(prisoner.inventory, LEGAL_ITEM)) != returned_property:
		_fail("Bail release must return the same confiscated legal stack with its contents and metadata")
	if law.get("prisoner_records").has(prisoner.stable_id) or bool(law.call("actor_has_active_warrant", prisoner, FACTION_ID)):
		_fail("Bail must remove the durable prisoner record and warrant")
	_validate_returned_property(prisoner, returned_property, "bail_release")
	var locker := jail.call("get_prisoner_locker") as Node
	if (locker.get("inventory") as InventoryData).count_item(LEGAL_ITEM) != 0:
		_fail("Bail must settle the confiscated legal stack out of the locker exactly once")
	party.unregister_party_member(payer)
	_phase("bail_complete")
	print("JAIL_LIFECYCLE_TRACE stage=bail_complete paid=%s silver_debit=%d expected_debit=%d" % [paid, silver_before - payer.inventory.count_item(SILVER), expected_cost])


func _validate_cell_lay_building_visibility(player: HumanoidCharacter, jail: Node) -> void:
	var building := jail.get_node_or_null("BuildingSlot/CurrentBuilding") if jail != null else null
	var visibility_controller := root.find_child("BuildingVisibilityController", true, false)
	var party_manager := _scene.get_node_or_null("PartyManager") as PartyManager if _scene != null else null
	if player == null or building == null or visibility_controller == null or party_manager == null:
		_fail("Cell lay visibility validation requires player, jail building, visibility controller, and party manager")
		return
	party_manager.select_only(player)
	party_manager.set_followed_member(player)
	if not await _wait_until(func() -> bool: return visibility_controller.call("get_active_building") == building, 120):
		_fail("Focused prisoner must make the jail cut away during its cell lay transition")
	if not bool(building.call("is_actor_inside", player)):
		_fail("Jail building must consider the focused prisoner inside during cell lay-down")


func _stop_law_probe() -> void:
	if _law_probe.is_valid() and get_tree().physics_frame.is_connected(_law_probe):
		get_tree().physics_frame.disconnect(_law_probe)
	var gecs := BootstrapContext.service(GecsWorldController.SERVICE_ID) as GecsWorldController
	var resolution := gecs.find_child("GameCombatResolutionSystem", true, false) if is_instance_valid(gecs) else null
	if is_instance_valid(resolution) and _law_impact_probe.is_valid() and resolution.is_connected("impact_resolved", _law_impact_probe):
		resolution.disconnect("impact_resolved", _law_impact_probe)
	_law_probe = Callable()
	_law_impact_probe = Callable()


func _release_fixture() -> void:
	_stop_law_probe()
	_close_active_conversation()
	if get_tree().node_added.is_connected(CONTROLLED_COMBAT.configure_controller):
		get_tree().node_added.disconnect(CONTROLLED_COMBAT.configure_controller)
	await FIXTURE.release_world(_scene, get_tree())
	_scene = null


func _start_law_boundary_probe(player: HumanoidCharacter, guard: HumanoidCharacter) -> void:
	_law_boundary_observations.clear()
	_law_impacts.clear()
	_law_probe = func() -> void: _observe_law_boundary(player, guard, "physics")
	get_tree().physics_frame.connect(_law_probe)
	var gecs := BootstrapContext.service(GecsWorldController.SERVICE_ID) as GecsWorldController
	var resolution := gecs.find_child("GameCombatResolutionSystem", true, false)
	_law_impact_probe = func(attacker_id: String, target_id: String, sequence: int, outcome: String, damage: float) -> void:
		if target_id != player.stable_id and attacker_id != player.stable_id:
			return
		_law_impacts.append({"attacker_id": attacker_id, "target_id": target_id, "sequence": sequence, "outcome": outcome, "damage": damage})
		_observe_law_boundary(player, guard, "impact")
	resolution.connect("impact_resolved", _law_impact_probe)
	_observe_law_boundary(player, guard, "before_theft")


func _observe_law_boundary(player: HumanoidCharacter, guard: HumanoidCharacter, boundary: String) -> void:
	var gecs := BootstrapContext.service(GecsWorldController.SERVICE_ID) as GecsWorldController
	var player_entity = gecs.get_actor_entity(player)
	var guard_entity = gecs.get_actor_entity(guard)
	var target := player.get_current_combat_target()
	var guard_action = guard_entity.get_component(gecs.C_COMBAT_ACTION)
	var guard_state = guard_entity.get_component(gecs.C_COMBAT_STATE)
	var bridge_id := int(guard.get("_system_target_id"))
	var bridge_target := instance_from_id(bridge_id) if bridge_id != 0 else null
	var observation := {"boundary": boundary, "player_life": player.life_state, "canonical_life": player_entity.get_component(gecs.C_VITALS).life_state,
		"player_target": target.stable_id if is_instance_valid(target) else "",
		"guard_target": guard_action.action_active and guard_action.action_target_actor_id == player.stable_id,
		"guard_projected_target": guard.get_current_combat_target() == player,
		"guard_bridge_id": bridge_id, "player_instance_id": player.get_instance_id(),
		"guard_system_id": guard_state.system_target_id, "guard_system_actor_id": guard_state.system_target_actor_id,
		"guard_bridge_target_life": bridge_target.get("life_state") if is_instance_valid(bridge_target) else null,
		"guard_player_order": guard.get("_active_player_order"),
		"guard_canonical_player_order": guard_entity.get_component(gecs.C_FACTION).player_order_active,
		"defending": player.is_in_combat() and _is_law_responder_arresting_actor(target, player),
		"guard_sequence": guard_action.action_sequence, "guard_windup": guard_action.action_active and not guard_action.action_has_impacted,
		"wounds": player.get_total_wound_damage()}
	var comparison := observation.duplicate()
	comparison.erase("wounds")
	var previous: Dictionary = _law_boundary_observations.back().duplicate() if not _law_boundary_observations.is_empty() else {}
	previous.erase("wounds")
	if comparison != previous:
		_law_boundary_observations.append(observation)
		print("LAW_TARGET_BRIDGE ", JSON.stringify(observation))


func _configure_arrest_combat(city_guard: HumanoidCharacter, player: HumanoidCharacter) -> void:
	# These are scenario inputs, set BEFORE the crime/first attack, not a retry
	# or a claim that high stats guarantee a hit. Native rolls are controlled
	# separately at the synchronous production resolution boundary.
	player.set("base_dodge_chance", 0.0)
	player.set("base_block_chance", 0.0)
	player.set_skill_level(SkillRules.ATTRIBUTE_DEXTERITY, 0)
	city_guard.set_skill_level(SkillRules.COMBAT_AXES_ONE_HANDED, 100)
	city_guard.set_skill_level(SkillRules.ATTRIBUTE_DEXTERITY, 100)
	city_guard.set("base_attack_damage", 38.0)
	city_guard.set("attack_cooldown_seconds", 0.25)


func _validate_live_law_combat(city_guard: HumanoidCharacter, player: HumanoidCharacter) -> bool:
	if city_guard == null or player == null:
		_fail("Live law combat validation requires guard and player")
		return false
	var guard_engaged := await _wait_until(func() -> bool: return city_guard.is_in_combat() and city_guard.get_current_combat_target() == player, 180)
	if not guard_engaged:
		_fail("Authority guard should keep a live law-arrest combat target after witnessed theft")
		return false
	var gecs := BootstrapContext.service(GecsWorldController.SERVICE_ID) as GecsWorldController
	var guard_config = gecs.get_actor_entity(city_guard).get_component(gecs.C_COMBAT_CONFIG)
	var player_config = gecs.get_actor_entity(player).get_component(gecs.C_COMBAT_CONFIG)
	var draws := CONTROLLED_COMBAT.native_draws()
	if draws.x > CombatMath.hit_chance(guard_config.hit_score, player_config.dodge_score) or draws.y <= CombatMath.defense_chance(player_config.block_score, guard_config.hit_score):
		_fail("Controlled native rolls must select a real unblocked officer hit under the current production scores")
		return false
	print("LAW_CONTROLLED_ROLLS hit=%.9f block=%.9f" % [draws.x, draws.y])
	var initial_distance := city_guard.global_position.distance_to(player.global_position)
	var closed_distance_condition := func() -> bool:
		var distance := city_guard.global_position.distance_to(player.global_position)
		return distance <= city_guard.get_attack_range() + 0.45 or distance < initial_distance - 0.35
	var closed_distance := await _wait_until(closed_distance_condition, 360)
	if not closed_distance:
		_fail("Authority guard should close distance during live law combat")
		return false
	var player_vitals = gecs.get_actor_entity(player).get_component(gecs.C_VITALS)
	var landed_hit := await _wait_until(func() -> bool:
		var attributed := _law_impacts.any(func(impact: Dictionary) -> bool: return impact.attacker_id == city_guard.stable_id and impact.target_id == player.stable_id and impact.sequence > 0 and impact.damage > 0.0)
		var canonical_wounds := VitalsMath.total_wound_damage(player_vitals.blunt_damage, player_vitals.open_cut_damage, player_vitals.bandaged_cut_damage)
		return attributed and canonical_wounds > 0.0 and player.get_total_wound_damage() > 0.0
	, 900)
	if not landed_hit:
		_fail("Authority guard should land a real combat hit during law arrest")
		return false
	# Capture the whole real encounter before evaluating the retained pre/at-
	# impact observations. The first hit can precede response-event consumption;
	# sampling only then rejects valid retaliation on the next live attack.
	var subdued := await _wait_until(func() -> bool: return player.is_downed_state() or player.life_state == NpcRules.LifeState.DEAD, 1500)
	var player_defending := _law_boundary_observations.any(func(observation: Dictionary) -> bool:
		return observation.defending and observation.canonical_life == NpcRules.LifeState.ALIVE and observation.guard_target and (observation.guard_windup or observation.boundary == "impact")
	)
	if not player_defending:
		_fail("Wanted player party member should self-defend when the guard engages player_order=%s player_ai=%s player_target=%s player_protected=%s player_stance=%s guard_ai=%s guard_target=%s player_hostile=%s guard_hostile=%s" % [str(player.get("_current_order_type")), str(player.get_current_order_type()), str(player.get_current_combat_target()), str(player.call("is_protected_from_combat")), str(player.get("combat_stance")), str(city_guard.get_current_order_type()), str(city_guard.get_current_combat_target()), str(player.has_hostility_with(city_guard)), str(city_guard.has_hostility_with(player))])
	if not subdued:
		_fail("Authority guard should subdue the wanted player through live combat")
		return false
	return player.is_downed_state()


func _wait_for_intake(prisoner: HumanoidCharacter, guard: HumanoidCharacter, jail: Node, max_frames: int, minimum_travel := 0.0) -> bool:
	var start := guard.global_position
	var previous := start
	var travelled := 0.0
	var largest_step := 0.0
	var place_order_seen := false
	var conserved_until_intake := true
	var reciprocal_carry := true
	var inventory_before := FIXTURE.inventory_snapshot(prisoner.inventory)
	_phase("carry_route_start")
	for _frame in range(max_frames):
		var step := guard.global_position.distance_to(previous)
		largest_step = maxf(largest_step, step)
		travelled += step
		previous = guard.global_position
		place_order_seen = place_order_seen or guard.get_interaction().current_order_type == InteractionCapability.ORDER_TYPE_PLACE_IN_CELL
		if prisoner.is_law_prisoner():
			break
		conserved_until_intake = conserved_until_intake and FIXTURE.inventory_snapshot(prisoner.inventory) == inventory_before
		reciprocal_carry = reciprocal_carry and _find_guard_carrying_actor(prisoner) == guard
		await physics_frame
	var admitted := prisoner.is_law_prisoner()
	print("JAIL_CARRY_TRACE admitted=%s actor=%s guard=%s start=%s end=%s travel=%.3f max_step=%.3f placement_order=%s reciprocal=%s inventory_conserved=%s" % [admitted, prisoner.stable_id, guard.stable_id, start, guard.global_position, travelled, largest_step, place_order_seen, reciprocal_carry, conserved_until_intake])
	if not reciprocal_carry or not conserved_until_intake:
		_fail("Custody route must retain the exact reciprocal carrier and all property until physical intake")
	if admitted and (not place_order_seen or travelled < minimum_travel or largest_step > 1.0):
		_fail("Custody must execute PLACE_IN_CELL and physically walk the route without teleporting the carrier")
	if admitted and not bool(jail.call("is_actor_inside_jail", guard)):
		_fail("Custody carrier must actually enter the jail before admission")
	# Outside escorts must leave; a jail employee may already have resumed
	# its own guard post by this frame instead of keeping the exit target.
	if admitted and guard == _city_guard:
		var interaction := guard.get_interaction()
		var exit_position: Vector3 = jail.call("get_exit_position", guard)
		if interaction.current_order_type != InteractionCapability.ORDER_TYPE_MOVE or not interaction.is_law_custody_returning() or not guard.has_move_target() or guard.get_move_target().distance_to(exit_position) > 0.1:
			_fail("Cell placement must preserve the escort's law return order and exit target after intake")
	_phase("carry_route_end")
	return admitted


func _print_sentence_route(warden: HumanoidCharacter, jail: Node) -> void:
	var entries: Array[Dictionary] = []
	for entry: Dictionary in jail.get("_pending_sentence_announcements"):
		var actor = entry.get("actor")
		entries.append({"actor": actor.stable_id if is_instance_valid(actor) else "<freed>",
			"route": entry.get("route", []), "route_index": entry.get("route_index", 0),
			"stall_seconds": entry.get("sentence_route_stall_seconds", 0.0),
			"final_close": entry.get("sentence_route_final_close", false)})
	var motion: Dictionary = preload("res://tests/validation/helpers/navigation_fixture.gd").actor_motion_snapshot(warden)
	# That helper reads the agent property, not direct NavigationServer RID
	# submissions. Do not label it proof of zero requested movement.
	motion["agent_velocity_property"] = motion.get("requested_velocity")
	motion.erase("requested_velocity")
	print("JAIL_SENTENCE_ROUTE warden=%s announcements=%s motion=%s" % [warden.stable_id, JSON.stringify(entries), JSON.stringify(motion)])


func _print_custody_route(guard: HumanoidCharacter, jail: Node) -> void:
	if guard == null:
		return
	var collisions: Array[Dictionary] = []
	for index in guard.get_slide_collision_count():
		var collision := guard.get_slide_collision(index)
		var collider = collision.get_collider()
		collisions.append({"path": str(collider.get_path()) if is_instance_valid(collider) else "", "normal": collision.get_normal(), "point": collision.get_position()})
	var interaction := guard.get_interaction()
	print("CUSTODY_ROUTE_TRACE guard=%s position=%s order=%s waypoints=%s entry=%s inside=%s cell=%s collisions=%s" % [guard.stable_id, guard.global_position, interaction.current_order_type, interaction.current_place_cell_waypoints, jail.call("get_entry_position", guard), jail.call("is_actor_inside_jail", guard), interaction.current_place_cell_target, collisions])
	print("CUSTODY_MOTION_TRACE ", JSON.stringify(preload("res://tests/validation/helpers/navigation_fixture.gd").actor_motion_snapshot(guard)))


func _validate_stolen_metadata_expiry_and_transfer() -> void:
	var metadata: Dictionary = {
		InventoryData.META_STOLEN: true,
		InventoryData.META_STOLEN_FROM_FACTION_ID: FACTION_ID,
		InventoryData.META_STOLEN_FROM_SETTLEMENT_ID: SETTLEMENT_ID,
		InventoryData.META_STOLEN_BY_ACTOR_ID: "player.validation",
		InventoryData.META_STOLEN_AT_MINUTE: 0,
		InventoryData.META_STOLEN_EXPIRES_AT_MINUTE: 10 * 24 * 60,
	}
	var source := InventoryData.new(4, 4, 100.0, false)
	var target := InventoryData.new(4, 4, 100.0, false)
	if not source.add_item_count_with_metadata(EXPENSIVE_VASE, 1, metadata):
		_fail("Inventory should accept metadata-bearing stolen entry")
		return
	var entry := source.entries[0]
	if not source.move_entry_to_inventory(entry, target, Vector2i.ZERO):
		_fail("Metadata-bearing stolen entry should transfer between inventories")
		return
	var moved_entry := target.entries[0]
	if not target.is_entry_stolen(moved_entry):
		_fail("Transferred stolen entry should preserve stolen metadata")
	var cleared := target.clear_expired_stolen_metadata((10 * 24 * 60) + 1)
	if cleared != 1 or target.is_entry_stolen(moved_entry):
		_fail("Stolen metadata should clear after the ten day expiry")


func _validate_same_settlement_stolen_sale_rules() -> void:
	var player := _get_player()
	var law := _get_law_controller()
	var witness := _scene.get_node_or_null("CustodyTown/Residents/Witness") as HumanoidCharacter
	if player == null or law == null or witness == null:
		_fail("Sale validation requires player, law controller, and same-settlement merchant witness")
		return
	var metadata: Dictionary = {
		"validation_sale_case": "local_stolen_sale",
		InventoryData.META_STOLEN: true,
		InventoryData.META_STOLEN_FROM_FACTION_ID: FACTION_ID,
		InventoryData.META_STOLEN_FROM_SETTLEMENT_ID: SETTLEMENT_ID,
		InventoryData.META_STOLEN_BY_ACTOR_ID: player.stable_id,
		InventoryData.META_STOLEN_AT_MINUTE: 0,
		InventoryData.META_STOLEN_EXPIRES_AT_MINUTE: 10 * 24 * 60,
	}
	if not player.inventory.add_item_count_with_metadata(EXPENSIVE_VASE, 1, metadata):
		_fail("Player inventory should accept a metadata-bearing stolen sale item")
		return
	var entry: InventoryData.InventoryEntry = null
	for candidate in player.inventory.entries:
		if candidate.definition == EXPENSIVE_VASE and str(candidate.metadata.get("validation_sale_case", "")) == "local_stolen_sale":
			entry = candidate
			break
	if entry == null:
		_fail("Could not find the exact metadata-bearing sale item created by this case")
		return
	if bool(law.call("can_sell_entry_to_merchant", player, witness, entry)):
		_fail("Same-settlement merchant should refuse actively stolen goods")
	law.call("_clear_warrant_for_actor", player, FACTION_ID)
	var distant_merchant := Node3D.new()
	distant_merchant.name = "DistantMerchant"
	distant_merchant.position = Vector3(180.0, 0.0, 0.0)
	_scene.add_child(distant_merchant)
	if not bool(law.call("can_sell_entry_to_merchant", player, distant_merchant, entry)):
		_fail("Merchant outside the source settlement should accept still-tagged stolen goods")
	distant_merchant.queue_free()
	player.inventory.remove_entry(entry)


func _validate_no_jail_ejection_fallback() -> void:
	var law := _get_law_controller()
	if law == null:
		_fail("Law controller should exist for no-jail fallback validation")
		return
	var settlement: Node3D = SETTLEMENT_TOWN_SCRIPT.new()
	settlement.name = "NoJailTown"
	settlement.set("settlement_definition", _make_settlement_definition("no_jail_town", "No Jail Town"))
	settlement.set("town_border_radius", 12.0)
	_scene.add_child(settlement)
	var actor := _make_validation_humanoid("NoJailCriminal", "npc.no_jail.criminal", Vector3.ZERO)
	settlement.add_child(actor)
	await _wait_frames(8)
	actor.global_position = settlement.global_position
	law.call("report_crime", actor, FACTION_ID, "no_jail_town", LawOrderController.CRIME_THEFT, 10, null, null)
	# Arrange a genuinely wounded prisoner in canonical vitals. A healthy actor
	# with only its presentation enum set to UNCONSCIOUS correctly wakes next tick.
	var gecs := BootstrapContext.service(GecsWorldController.SERVICE_ID) as GecsWorldController
	var vitals = gecs.get_actor_entity(actor).get_component(gecs.C_VITALS)
	vitals.blunt_damage = vitals.max_hp + 5.0
	var vitals_inputs = gecs.get_actor_entity(actor).get_component(gecs.C_VITALS_INPUTS)
	VitalsStateMachine.recalculate(vitals, float(vitals_inputs.toughness))
	await _wait_frames(4)
	if actor.life_state != NpcRules.LifeState.UNCONSCIOUS:
		_fail("No-jail fixture must first reach a genuinely wounded unconscious state")
	var wounds_before: float = VitalsMath.total_wound_damage(vitals.blunt_damage, vitals.open_cut_damage, vitals.bandaged_cut_damage)
	law.call("_process_warrants")
	var wounds_after: float = VitalsMath.total_wound_damage(vitals.blunt_damage, vitals.open_cut_damage, vitals.bandaged_cut_damage)
	if not is_equal_approx(wounds_before, wounds_after):
		_fail("No-jail ejection must conserve the prisoner's canonical wound damage")
	await _wait_frames(4)
	if settlement.global_position.distance_to(actor.global_position) <= 12.0:
		_fail("No-jail fallback should eject the prisoner outside the town border")
	if int(actor.get("life_state")) != NpcRules.LifeState.UNCONSCIOUS:
		_fail("No-jail fallback should not heal or revive the ejected prisoner")
	if bool(law.call("actor_has_active_warrant", actor, FACTION_ID)):
		_fail("No-jail fallback should clear the processed warrant after ejection")
	settlement.queue_free()


func _make_settlement_definition(settlement_id: String, display_name: String) -> Resource:
	var definition: Resource = SETTLEMENT_DEFINITION_SCRIPT.new()
	definition.set("settlement_id", settlement_id)
	definition.set("display_name", display_name)
	definition.set("faction_definition", FARMERS_FACTION)
	return definition


func _make_validation_humanoid(node_name: String, stable_id: String, local_position: Vector3) -> HumanoidCharacter:
	# Use the complete production projection contract, including its collider,
	# body and selection ring; only choose the NPC script before tree entry.
	var actor := ACTOR_SCENE.instantiate() as HumanoidCharacter
	actor.set_script(FACTION_HUMANOID_SCRIPT)
	actor.name = node_name
	actor.position = local_position
	actor.member_name = node_name
	actor.stable_id = stable_id
	actor.faction_name = "Player"
	return actor


func _validate_confiscated_records(locker: Node, prisoner_id: String, expected: Array, boundary: String) -> void:
	var gecs := BootstrapContext.service(GecsWorldController.SERVICE_ID) as GecsWorldController
	var lifecycle := BootstrapContext.service(ItemLifecycleController.SERVICE_ID) as ItemLifecycleController
	if not is_instance_valid(locker) or str(locker.get("container_id")).is_empty():
		_fail("%s: confiscated property requires the authored locker identity" % boundary)
		return
	var locker_id := str(locker.get("container_id"))
	var stacks := gecs.get_inventory_stacks()
	for payload: Dictionary in expected:
		var stack_id := str(payload.stack_id)
		var durable := gecs.get_item_stack(stack_id)
		var cached := lifecycle.get_stack_record(stack_id)
		var matches := stacks.filter(func(record: Dictionary) -> bool: return record.stack_id == stack_id)
		if matches.size() != 1 or str(durable.get("container_id", "")) != locker_id:
			_fail("%s: exact confiscated stack %s must exist once in the authored durable locker" % [boundary, stack_id])
		var metadata: Dictionary = durable.get("metadata", {}).duplicate(true)
		if str(metadata.get(InventoryData.META_LAW_PRISONER_KEY, "")) != prisoner_id or str(metadata.get(InventoryData.META_LAW_CASE_ID, "")).is_empty():
			_fail("%s: confiscated stack must retain prisoner identity and its custody case" % boundary)
		metadata.erase(InventoryData.META_LAW_PRISONER_KEY)
		metadata.erase(InventoryData.META_LAW_CASE_ID)
		if durable.get("item_definition_path") != payload.definition.resource_path or int(durable.get("count", 0)) != int(payload.count) or durable.get("contained_item_counts", {}) != payload.contents or metadata != payload.metadata:
			_fail("%s: fresh durable property record must preserve the exact original payload" % boundary)
		if cached != durable:
			_fail("%s: lifecycle read view must agree with fresh confiscated-property authority" % boundary)
		print("LAW_PROPERTY_BOUNDARY ", JSON.stringify({"boundary": boundary, "stack_id": stack_id, "copies": matches.size(), "durable": durable, "lifecycle": cached}))


func _validate_returned_property(actor: HumanoidCharacter, expected: Dictionary, boundary: String) -> void:
	var gecs := BootstrapContext.service(GecsWorldController.SERVICE_ID) as GecsWorldController
	var lifecycle := BootstrapContext.service(ItemLifecycleController.SERVICE_ID) as ItemLifecycleController
	var stack_id := str(expected.stack_id)
	var durable := gecs.get_item_stack(stack_id)
	var copies := gecs.get_inventory_stacks().filter(func(record: Dictionary) -> bool: return record.stack_id == stack_id)
	var entry := _find_inventory_entry(actor.inventory, expected.definition)
	if copies.size() != 1 or _entry_payload(entry) != expected or durable.get("container_id", "") != "%s.inventory" % actor.stable_id or durable.get("owner_actor_id", "") != actor.stable_id:
		_fail("%s: returned property must retain the exact identity/payload once in the prisoner's durable inventory" % boundary)
	if durable.get("item_definition_path", "") != expected.definition.resource_path or durable.get("metadata", {}) != expected.metadata or durable.get("contained_item_counts", {}) != expected.contents or int(durable.get("count", 0)) != int(expected.count) or lifecycle.get_stack_record(stack_id) != durable:
		_fail("%s: returned durable property and lifecycle view must preserve the original payload" % boundary)
	print("LAW_RETURNED_PROPERTY boundary=%s stack=%s copies=%d record=%s" % [boundary, stack_id, copies.size(), JSON.stringify(durable)])


func _entry_payload(entry: InventoryData.InventoryEntry, strip_custody := false) -> Dictionary:
	if entry == null:
		return {}
	var metadata := entry.metadata.duplicate(true)
	if strip_custody:
		metadata.erase(InventoryData.META_LAW_PRISONER_KEY)
		metadata.erase(InventoryData.META_LAW_CASE_ID)
	return {"stack_id": entry.stack_id, "definition": entry.definition, "count": entry.count, "contents": entry.contained_item_counts.duplicate(true), "metadata": metadata}


func _find_inventory_entry(inventory: InventoryData, definition: Resource) -> InventoryData.InventoryEntry:
	if inventory == null:
		return null
	for entry in inventory.entries:
		if entry.definition == definition:
			return entry
	return null


func _find_cell_holding(jail: Node, actor: Node) -> Node:
	if jail == null or actor == null or not jail.has_method("get_cells"):
		return null
	for cell in jail.call("get_cells"):
		if cell == null or not cell.has_method("get_cell_id"):
			continue
		if cell.has_method("has_occupant") and bool(cell.call("has_occupant", actor)):
			return cell
	return null


func _validate_jail_cell_authoring(jail: Node) -> void:
	if jail == null:
		_fail("Custody fixture must supply a jail")
		return
	var cells: Array = jail.call("get_cells")
	if cells.is_empty() or jail.call("get_prisoner_locker") == null:
		_fail("Jail must discover its reusable cells and prisoner locker")
		return
	var prisoners: Array[HumanoidCharacter] = []
	var reserved: Array[Node] = []
	var prisoner_positions: Array[Vector3] = []
	for index in range(cells.size() + 1):
		var prisoner := _make_validation_humanoid("Reservation%d" % index, "fixture.reservation.%d" % index, Vector3(40.0 + index, 0.6, 0.0))
		_scene.add_child(prisoner)
		prisoners.append(prisoner)
		var cell := jail.call("get_reserved_or_available_cell", prisoner, prisoner) as Node
		if index == cells.size():
			if cell != null:
				_fail("A full jail must refuse one more reservation")
		elif cell == null or reserved.has(cell):
			_fail("Each prisoner must reserve a different discovered cell")
		else:
			reserved.append(cell)
			# Read this cell's authored marker directly. Comparing physical
			# placement only with the production getter would share its bugs.
			var marker := cell.get_node_or_null("PrisonerPoint") as Node3D
			var position: Vector3 = cell.call("get_prisoner_position", prisoner)
			if marker == null or not position.is_equal_approx(marker.global_position):
				_fail("Each cell must resolve its own authored prisoner marker")
			for previous_position in prisoner_positions:
				if position.is_equal_approx(previous_position):
					_fail("Different reserved cells must not share one prisoner position")
			prisoner_positions.append(position)
			if jail.call("get_reserved_or_available_cell", prisoner, prisoner) != cell:
				_fail("Repeated reservation for the same prisoner must keep its exact cell")
	if reserved.size() == cells.size():
		jail.call("release_cell_reservation", prisoners[0])
		if jail.call("get_reserved_or_available_cell", prisoners[-1], prisoners[-1]) != reserved[0]:
			_fail("Releasing one reservation must make exactly that cell reusable")
	for prisoner in prisoners:
		jail.call("release_cell_reservation", prisoner)
		prisoner.queue_free()
	await process_frame


func _validate_guard_post_preserves_combat(owner: Node, guard: HumanoidCharacter, target: HumanoidCharacter, label: String) -> void:
	if owner == null or guard == null or target == null:
		_fail("%s guard-post combat validation requires owner, guard, and target" % label)
		return
	if not owner.has_method("_process_guard_post_assignment"):
		if label == "Town":
			return
		_fail("%s should expose guard-post assignment for validation" % label)
		return
	var original_transform := guard.global_transform
	FIXTURE.reset_order(guard)
	FIXTURE.reset_order(target)
	guard.global_position = target.global_position + Vector3(0.9, 0.0, 0.0)
	guard.assign_attack_target(target, false, false, false)
	if not await _wait_until(func() -> bool: return guard.get_current_combat_target() == target, 120):
		_fail("%s guard must acquire the nearby live target before guard-post preservation is exercised" % label)
		return
	if owner is SettlementJail:
		owner.call("_process_guard_post_assignment", guard, 0.0)
	else:
		owner.call("_process_guard_post_assignment", guard)
	if guard.get_current_combat_target() != target or not guard.is_in_combat():
		_fail("%s guard-post assignment should not cancel active combat" % label)
	FIXTURE.reset_order(guard)
	FIXTURE.reset_order(target)
	guard.global_transform = original_transform
	guard.velocity = Vector3.ZERO


func _validate_combat_order_priority(guard: HumanoidCharacter, target: HumanoidCharacter) -> void:
	if guard == null or target == null:
		_fail("Combat order priority validation requires guard and target")
		return
	var guard_transform := guard.global_transform
	var target_transform := target.global_transform
	_reset_validation_combat_pair(guard, target)
	guard.global_position = Vector3(-7.0, 0.6, -2.0)
	target.global_position = Vector3(-4.5, 0.6, -2.0)
	guard.assign_attack_target(target, false, false, false)
	if not await _wait_until(func() -> bool: return guard.get_current_combat_target() == target, 360):
		_fail("Order-priority precondition must acquire the real requested target before movement (guard_life=%d target_life=%d)" % [guard.life_state, target.life_state])
		_restore_validation_combat_pair(guard, target, guard_transform, target_transform)
		return
	guard.set_move_target(guard.global_position + Vector3(5.0, 0.0, 0.0), false)
	if guard.get_current_combat_target() != target or not guard.is_in_combat():
		_fail("Non-player movement should not cancel active combat")
	guard.set_move_target(guard.global_position + Vector3(5.0, 0.0, 0.0), true)
	if guard.is_in_combat():
		_fail("Player-issued movement should be able to cancel active combat")
	_restore_validation_combat_pair(guard, target, guard_transform, target_transform)


func _validate_long_range_combat_chase(guard: HumanoidCharacter, target: HumanoidCharacter) -> void:
	if guard == null or target == null:
		_fail("Long-range combat chase validation requires guard and target")
		return
	var guard_transform := guard.global_transform
	var target_transform := target.global_transform
	_reset_validation_combat_pair(guard, target)
	guard.global_position = Vector3(-12.0, 0.6, -6.0)
	target.global_position = Vector3(-2.0, 0.6, -6.0)
	var initial_distance := guard.global_position.distance_to(target.global_position)
	guard.assign_attack_target(target, false, false, false)
	var chased := await _wait_until(func() -> bool: return guard.get_current_combat_target() == target and guard.global_position.distance_to(target.global_position) < initial_distance - 0.25, 360)
	if guard.get_current_combat_target() != target or not guard.is_in_combat():
		_fail("Long-range combat chase should not drop attack orders in the custody fixture")
	elif not chased:
		_fail("Long-range combat chase should physically pursue its assigned target")
	_restore_validation_combat_pair(guard, target, guard_transform, target_transform)


func _reset_validation_combat_pair(left: HumanoidCharacter, right: HumanoidCharacter) -> void:
	FIXTURE.reset_order(left)
	FIXTURE.reset_order(right)


func _reset_validation_combat_actors(actors: Array) -> void:
	for actor in actors:
		FIXTURE.reset_order(actor)


func _restore_validation_combat_pair(left: HumanoidCharacter, right: HumanoidCharacter, left_transform: Transform3D, right_transform: Transform3D) -> void:
	_reset_validation_combat_pair(left, right)
	left.global_transform = left_transform
	right.global_transform = right_transform


func _save_actor_transforms(actors: Array) -> Dictionary:
	var transforms := {}
	for actor in actors:
		if actor is HumanoidCharacter:
			transforms[actor] = (actor as HumanoidCharacter).global_transform
	return transforms


func _restore_actor_transforms(transforms: Dictionary) -> void:
	for actor in transforms.keys():
		if actor is HumanoidCharacter:
			(actor as HumanoidCharacter).global_transform = transforms[actor]
			(actor as HumanoidCharacter).velocity = Vector3.ZERO


func _record_has_crime(record: Dictionary, crime_type: String) -> bool:
	var crimes: Array = record.get("crimes", [])
	for crime in crimes:
		if crime is Dictionary and str(crime.get("crime_type", "")) == crime_type:
			return true
	return false


func _advance_to_sentence_decision(law: Node, actor: HumanoidCharacter) -> void:
	var record: Dictionary = law.get("prisoner_records").get(actor.stable_id, {})
	if record.is_empty():
		_fail("Sentence scheduling requires a real admitted prisoner record")
		return
	var time := _get_world_time_controller()
	var decision_at := int(record.get("sentence_decision_at_minute", -1))
	time.call("advance_minutes", maxf(0.0, decision_at - time.call("get_absolute_minute")))


func _sentence_notification_given(law: Node, actor: HumanoidCharacter) -> bool:
	if law == null or actor == null:
		return false
	var key := str(actor.get("stable_id"))
	var records: Dictionary = law.get("prisoner_records") if law.get("prisoner_records") != null else {}
	if not records.has(key):
		return false
	var record: Dictionary = records[key]
	return bool(record.get("sentence_notification_given", false))


func _close_active_conversation() -> void:
	var controller := root.find_child("ConversationController", true, false)
	if controller != null and controller.has_method("_end_conversation"):
		controller.call("_end_conversation")


func _is_warden_at_home_post(jail: Node, warden: HumanoidCharacter) -> bool:
	var post := _get_warden_home_post(jail)
	if post == null or warden == null:
		return false
	var home_position: Vector3 = post.call("get_staff_stand_position") if post.has_method("get_staff_stand_position") else post.global_position
	return _horizontal_distance(warden.global_position, home_position) <= 0.75


func _horizontal_distance(left: Vector3, right: Vector3) -> float:
	return Vector2(left.x - right.x, left.z - right.z).length()


func _get_warden_home_post(jail: Node) -> Node3D:
	return jail.call("get_warden_service_point") as Node3D if jail != null and jail.has_method("get_warden_service_point") else null


func _is_law_responder_arresting_actor(responder: HumanoidCharacter, actor: HumanoidCharacter) -> bool:
	return FIXTURE.is_law_response(responder, actor)


func _find_guard_carrying_actor(actor: HumanoidCharacter) -> HumanoidCharacter:
	if actor == null or actor.get_carry() == null:
		return null
	var carrier := actor.get_carry().get_carrier() as HumanoidCharacter
	if carrier == null or carrier.get_carry().get_carried_character() != actor:
		return null
	return carrier

func _attack_sequence(actor: WorldActor) -> int:
	var gecs := BootstrapContext.service(GecsWorldController.SERVICE_ID) as GecsWorldController
	return int(gecs.get_actor_entity(actor).get_component(gecs.C_COMBAT_ACTION).action_sequence)


func _attack_started_against(actor: WorldActor, target: WorldActor, previous_sequence: int) -> bool:
	var gecs := BootstrapContext.service(GecsWorldController.SERVICE_ID) as GecsWorldController
	var action = gecs.get_actor_entity(actor).get_component(gecs.C_COMBAT_ACTION)
	return int(action.action_sequence) > previous_sequence and str(action.action_target_actor_id) == target.stable_id


func _get_player() -> HumanoidCharacter:
	return _scene.get_node_or_null("PartyMembers/Mira") as HumanoidCharacter if _scene != null else null


func _get_jail() -> Node:
	return _scene.get_node_or_null("CustodyTown/Facilities/Jail") if _scene != null else null


func _get_law_controller() -> Node:
	return root.find_child("LawOrderController", true, false)


func _get_world_time_controller() -> Node:
	return root.find_child("WorldTimeController", true, false)


func _get_current_animation(actor: HumanoidCharacter) -> String:
	var body := actor.get_body_projection()
	return body.get_current_clip() if body != null else ""


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await physics_frame


func _wait_until(condition: Callable, max_frames: int) -> bool:
	for _index in range(max_frames):
		if bool(condition.call()):
			return true
		await physics_frame
	return bool(condition.call())


func _phase(label: String) -> void:
	print("JAIL_PHASE stage=%s elapsed_seconds=%.3f physics_frame=%d" % [label, (Time.get_ticks_msec() - _started_msec) / 1000.0, Engine.get_physics_frames()])


func _fail(message: String) -> void:
	var named_message := "%s: %s" % [_active_case, message]
	_failures.append(named_message)
	print("LAW_ASSERTION_FAILED: %s" % named_message)
