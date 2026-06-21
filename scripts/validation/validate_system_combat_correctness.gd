extends SceneTree

var _failures: Array[String] = []


class ProbeActor:
	extends WorldActor

	var woke := false
	var stealth_broke := false
	var allies_notified := false
	var reaction_played := false

	func wake_up_from_rest(_show_notice := true) -> void:
		woke = true
		life_state = NpcRules.LifeState.ALIVE

	func _break_stealth_for_combat() -> void:
		stealth_broke = true
		sneaking = false

	func _notify_defensive_allies_of_attack(_attacker: Node) -> void:
		allies_notified = true

	func _play_combat_reaction_clip(_animation_name: String) -> float:
		reaction_played = true
		return 0.25

	func _pick_combat_hit_reaction_clip(_attack_id: String, _hit_reaction_names: Array[String]) -> String:
		return "probe_hit"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_system_receive_side_effects()
	if _failures.is_empty():
		print("SYSTEM_COMBAT_CORRECTNESS_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SYSTEM_COMBAT_CORRECTNESS_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_system_receive_side_effects() -> void:
	var attacker := ProbeActor.new()
	var defender := ProbeActor.new()
	root.add_child(attacker)
	root.add_child(defender)
	attacker.name = "SystemCombatAttacker"
	defender.name = "SystemCombatDefender"
	attacker.stable_id = "probe_attacker"
	defender.stable_id = "probe_defender"
	defender.life_state = NpcRules.LifeState.ASLEEP
	defender.sneaking = true
	var context: Dictionary = defender.prepare_system_combat_receive_attack(attacker, 2.0, 1.0)
	if not bool(context.get("accepted", false)):
		_fail("system receive should accept sleeping non-protected target")
	if not bool(context.get("can_actively_defend", false)):
		_fail("system receive should set can_actively_defend true for woken target")
	if not defender.woke:
		_fail("system receive should wake sleeping target")
	if not defender.stealth_broke or defender.sneaking:
		_fail("system receive should break target stealth")
	if not defender.allies_notified:
		_fail("system receive should notify defensive allies")
	if not defender.has_hostility_with(attacker):
		_fail("system receive should mark attacker hostile")
	if not attacker.has_hostility_with(defender):
		_fail("system receive should establish mutual hostility")
	var can_actively_defend := bool(context.get("can_actively_defend", true))
	var reaction_seconds := defender.handle_system_combat_resolution(attacker, "hit", "probe", PackedStringArray(), false, false, 1.0, 0.0, can_actively_defend)
	if reaction_seconds <= 0.0 or not defender.reaction_played:
		_fail("system receive should play active hit reaction")
	if not WorldActor.COMBAT_COORDINATOR.is_character_locked(defender):
		_fail("system receive should extend combat coordinator reaction lock")
	WorldActor.COMBAT_COORDINATOR.release_character(attacker)
	WorldActor.COMBAT_COORDINATOR.release_character(defender)
	if WorldActor.COMBAT_COORDINATOR.is_character_locked(defender):
		_fail("system receive cleanup should release defender lock")
	attacker.queue_free()
	defender.queue_free()

func _fail(message: String) -> void:
	_failures.append(message)
