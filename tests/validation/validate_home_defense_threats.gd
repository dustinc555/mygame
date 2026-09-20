extends "res://tests/validation/law_order_cases.gd"

## Bounded Home-defense combat seam. The full Home realization validator owns
## furniture, occupancy/warning and routine checks; this does not load Canyon.
func _run() -> void:
	if await _load_fixture():
		await _validate_home_defense_threats()
	await FIXTURE.release_world(_scene, get_tree())
	for failure in _failures:
		push_error(failure)
	print("HOME_DEFENSE_THREATS_%s" % ["OK" if _failures.is_empty() else "FAILED"])
	quit(0 if _failures.is_empty() else 1)

func _validate_home_defense_threats() -> void:
	var intruder := _get_player()
	var witness := _scene.get_node("CustodyTown/Residents/Witness") as HumanoidCharacter
	# The fixture's civilian is authored passive; Home residents defend.
	witness.combat_stance = NpcRules.CombatStance.DEFENSIVE
	var companion := preload("res://features/core/party/party_member.tscn").instantiate() as HumanoidCharacter
	companion.name = "HomeDefenseCompanion"
	companion.member_name = "Home Defense Companion"
	companion.stable_id = "validation.home.companion"
	companion.faction_name = intruder.faction_name
	companion.combat_stance = NpcRules.CombatStance.DEFENSIVE
	companion.fatigue_enabled = false
	_scene.get_node("PartyMembers").add_child(companion)
	var party := _scene.get_node("PartyManager") as PartyManager
	party.register_party_member(companion)
	_reset_validation_combat_actors([intruder, witness, companion, _city_guard, _jail_guard, _warden])
	intruder.global_position = Vector3(-10.0, 0.0, -7.0)
	witness.global_position = Vector3(-9.1, 0.0, -7.0)
	companion.global_position = Vector3(-11.0, 0.0, -7.0)
	_city_guard.global_position = Vector3(-7.0, 0.0, -7.0)
	_jail_guard.global_position = Vector3(-6.0, 0.0, -7.0)
	_warden.global_position = Vector3(-5.0, 0.0, -7.0)
	var gecs := BootstrapContext.service(GecsWorldController.SERVICE_ID) as GecsWorldController
	await _wait_until(func() -> bool: return gecs.get_actor_entity(companion) != null, 120)
	var responses := BootstrapContext.service(GameCombatResponseSystem.SERVICE_ID) as GameCombatResponseSystem
	var law := _get_law_controller()
	var defense := {}
	var impacts: Array[Dictionary] = []
	gecs.find_child("GameCombatResolutionSystem", true, false).connect("impact_resolved", func(attacker_id: String, target_id: String, sequence: int, outcome: String, damage: float) -> void:
		impacts.append({"attacker": attacker_id, "target": target_id, "sequence": sequence, "outcome": outcome, "damage": damage})
	)
	law.call("_start_home_defense", witness, intruder, defense, "validation.home.building")
	law.call("report_crime", intruder, FACTION_ID, SETTLEMENT_ID, LawOrderController.CRIME_TRESPASS, 5, witness, null)
	await _wait_until(func() -> bool:
		return responses.get_active_intents().any(func(intent: Dictionary) -> bool: return intent.responder_actor_id == witness.stable_id and intent.target_actor_id == intruder.stable_id and int(intent.kind) == CGameCombatResponseIntent.Kind.PRIVATE_DEFENSE)
	, 120)
	var threat_ids := FIXTURE.defense_threat_actor_ids(responses, intruder.stable_id)
	if not threat_ids.has(witness.stable_id) or not threat_ids.has(_city_guard.stable_id):
		_fail("Home threat set must independently contain its private defender and dispatched city guard")
	var impacted := await _wait_until(func() -> bool:
		return impacts.any(func(impact: Dictionary) -> bool: return threat_ids.has(str(impact.attacker)) and str(impact.target) == intruder.stable_id and float(impact.damage) > 0.0)
	, 600)
	if not impacted:
		_fail("Home defense must actually impact the intruder before companion response is accepted")
	var defended := await _wait_until(func() -> bool:
		var target := companion.get_current_combat_target() as WorldActor
		return target != null and threat_ids.has(target.stable_id)
	, 360)
	var target := companion.get_current_combat_target() as WorldActor
	print("HOME_THREAT_TRACE threats=%s witness=%s companion_target=%s impacts=%s encounters=%s" % [threat_ids, witness.stable_id, target.stable_id if target != null else "", impacts, responses.get_active_encounters()])
	if not defended:
		_fail("Nearby non-passive companion must acquire a real active Home-defense threat, not an unrelated actor")
	if target == intruder or target == companion:
		_fail("Home-defense response must never select a friendly party member")
	law.call("_clear_home_defense", defense, intruder)
