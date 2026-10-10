extends "res://tests/validation/test_case.gd"

const FREE_FOR_ALL_SCENE := preload("res://scenes/test_levels/combat_free_for_all_5v5v5.tscn")
const SIM_FRAMES := 720
const PLAYER_FACTION := "Player"
const RAIDER_FACTION := "Raiders"
const CINDER_FACTION := "CinderHorde"
const QUADBOT_CHARACTER_SCRIPT := preload("res://features/actors/projection/quadbot/quadbot_character.gd")
const RUSTDEAD_CHARACTER_SCRIPT := preload("res://features/actors/projection/rustdead/rustdead_humanoid_character.gd")
const FIXTURE := preload("res://tests/validation/helpers/combat_fixture.gd")

var _failures: Array[String] = []
var _scene: Node
var _party_ids: Dictionary = {}
var _party_engaged: Dictionary = {}
var _party_impacts: Dictionary = {}
var _party_max_displacement: Dictionary = {}
var _resolved_impacts: Array[Dictionary] = []
var _first_attacked_party_id := ""


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	# Bootstrap can start a fight before an arbitrary startup frame wait ends.
	get_tree().node_added.connect(_on_runtime_node_added)
	_scene = FREE_FOR_ALL_SCENE.instantiate()
	root.add_child(_scene)
	await _wait_frames(16)
	var actors := _get_alive_world_actors()
	var initial := _capture_actor_snapshot(actors)
	_validate_spawn(actors)
	for actor in actors:
		if actor.faction_name == PLAYER_FACTION:
			_party_ids[actor.stable_id] = true
	var responses := BootstrapContext.service(GameCombatResponseSystem.SERVICE_ID) as GameCombatResponseSystem
	var resolution := _scene.find_child("GameCombatResolutionSystem", true, false) as GameCombatResolutionSystem
	if responses == null or resolution == null:
		_fail("The real combat response and resolution systems must be running")
	if not await FIXTURE.wait_world_ready(get_tree()):
		_fail("5v5v5 must finish normal startup before measuring assistance")
	var all_factions_engaged := false
	for frame in range(SIM_FRAMES):
		await physics_frame
		await process_frame
		var target_sample := _get_alive_world_actors()
		for actor in target_sample:
			if not _party_ids.has(actor.stable_id):
				continue
			var target := actor.get_current_combat_target() as WorldActor
			if target != null and target.faction_name != PLAYER_FACTION:
				_party_engaged[actor.stable_id] = true
				var before: Dictionary = initial.get(actor.get_instance_id(), {})
				var distance := _horizontal_distance(before.get("position", actor.global_position), actor.global_position)
				_party_max_displacement[actor.stable_id] = maxf(float(_party_max_displacement.get(actor.stable_id, 0.0)), distance)
		if not all_factions_engaged and _factions_have_targets(target_sample):
			all_factions_engaged = true
			_validate_three_way_targets(target_sample)
			_validate_target_spread(target_sample)
	if not all_factions_engaged:
		_fail("All three factions must acquire hostile targets during the unchanged 12s simulation")
	var alive_after_sim := _get_alive_world_actors()
	_validate_damage_happened(actors, initial)
	_validate_no_floating(alive_after_sim, initial)
	_validate_party_assistance(actors)
	await _cleanup_scene()
	if _failures.is_empty():
		print("COMBAT_FREE_FOR_ALL_5V5V5_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("COMBAT_FREE_FOR_ALL_5V5V5_FAILED count=%d" % _failures.size())
	quit(1)


func _on_runtime_node_added(node: Node) -> void:
	if node is GameCombatResolutionSystem:
		node.impact_resolved.connect(_on_impact)


func _on_impact(attacker_id: String, target_id: String, _sequence: int, _outcome: String, _damage: float) -> void:
	_resolved_impacts.append({"attacker": attacker_id, "target": target_id})


func _validate_party_assistance(actors: Array[WorldActor]) -> void:
	for impact in _resolved_impacts:
		# Observe physical attacks, not the law system's deduplicated incidents.
		if _first_attacked_party_id.is_empty() and _party_ids.has(impact.target) and not _party_ids.has(impact.attacker):
			_first_attacked_party_id = impact.target
		if _party_ids.has(impact.attacker) and not _party_ids.has(impact.target):
			_party_impacts[impact.attacker] = true
	if _first_attacked_party_id.is_empty():
		_fail("An enemy must actually attack the party to exercise Defend assistance")
	for actor in actors:
		if not _party_ids.has(actor.stable_id):
			continue
		if actor.combat_stance != NpcRules.CombatStance.DEFENSIVE:
			_fail("%s must remain in Defend for this regression" % actor.member_name)
		if not _party_engaged.has(actor.stable_id):
			_fail("%s never automatically joined their party's defense" % actor.member_name)
		# A defender already in striking range need not walk away to prove aid.
		# Track the approach throughout combat, not just its final net offset.
		if float(_party_max_displacement.get(actor.stable_id, 0.0)) <= 0.5 and not _party_impacts.has(actor.stable_id):
			_fail("%s neither physically approached nor struck an enemy" % actor.member_name)
	if not _party_impacts.keys().any(func(actor_id): return actor_id != _first_attacked_party_id):
		_fail("A companion other than the first victim must execute a real combat strike")
	print("PARTY_DEFEND engaged=%d/%d striking=%d first_victim=%s" % [_party_engaged.size(), _party_ids.size(), _party_impacts.size(), _first_attacked_party_id])


func _validate_spawn(actors: Array[WorldActor]) -> void:
	if actors.size() != 15:
		_fail("Expected 15 alive actors, got %d" % actors.size())
	var counts := _faction_counts(actors)
	for faction in [PLAYER_FACTION, RAIDER_FACTION, CINDER_FACTION]:
		if int(counts.get(faction, 0)) != 5:
			_fail("Expected 5 actors for %s, got %d" % [faction, int(counts.get(faction, 0))])
	var rustdead_count := 0
	var quadbot_count := 0
	for actor in actors:
		if str(actor.get("faction_name")) != CINDER_FACTION:
			continue
		if actor.get_script() == RUSTDEAD_CHARACTER_SCRIPT:
			rustdead_count += 1
		elif actor.get_script() == QUADBOT_CHARACTER_SCRIPT:
			quadbot_count += 1
	if rustdead_count != 4 or quadbot_count != 1:
		_fail("Cinder squad should be 4 Rustdead and 1 quad bot, got rustdead=%d quadbot=%d" % [rustdead_count, quadbot_count])


func _factions_have_targets(actors: Array[WorldActor]) -> bool:
	var factions := {}
	for actor in actors:
		var target := actor.get_current_combat_target() as WorldActor
		if target != null and target.faction_name != actor.faction_name:
			factions[actor.faction_name] = true
	return factions.has(PLAYER_FACTION) and factions.has(RAIDER_FACTION) and factions.has(CINDER_FACTION)


func _validate_three_way_targets(actors: Array[WorldActor]) -> void:
	var factions_with_targets := {}
	for actor in actors:
		var faction := str(actor.get("faction_name"))
		var target := actor.get_current_combat_target() as WorldActor
		if target == null:
			continue
		var target_faction := str(target.get("faction_name"))
		if target_faction != faction and [PLAYER_FACTION, RAIDER_FACTION, CINDER_FACTION].has(target_faction):
			factions_with_targets[faction] = true
	for faction in [PLAYER_FACTION, RAIDER_FACTION, CINDER_FACTION]:
		if not bool(factions_with_targets.get(faction, false)):
			_fail("%s should acquire hostile targets in 5v5v5" % faction)


func _validate_target_spread(actors: Array[WorldActor]) -> void:
	var targets_by_attacker_faction := {}
	var pressure := {}
	for actor in actors:
		var attacker_faction := str(actor.get("faction_name"))
		var target := actor.get_current_combat_target() as WorldActor
		if target == null:
			continue
		var target_faction := str(target.get("faction_name"))
		if target_faction == attacker_faction:
			_fail("%s should not target same-faction actor %s" % [actor.name, target.name])
			continue
		var faction_targets: Dictionary = targets_by_attacker_faction.get(attacker_faction, {})
		faction_targets[target_faction] = true
		targets_by_attacker_faction[attacker_faction] = faction_targets
		pressure[target.get_instance_id()] = int(pressure.get(target.get_instance_id(), 0)) + 1
	for faction in [PLAYER_FACTION, RAIDER_FACTION, CINDER_FACTION]:
		var faction_targets: Dictionary = targets_by_attacker_faction.get(faction, {})
		if faction_targets.size() < 1:
			_fail("%s should target at least one enemy faction" % faction)
	var max_pressure := 0
	for value in pressure.values():
		max_pressure = maxi(max_pressure, int(value))
	if max_pressure > 4:
		_fail("5v5v5 should not dogpile one target, max_pressure=%d pressure=%s" % [max_pressure, str(pressure)])


func _validate_damage_happened(actors: Array[WorldActor], initial: Dictionary) -> void:
	for actor in actors:
		var before: Dictionary = initial.get(actor.get_instance_id(), {})
		if before.is_empty():
			continue
		if float(actor.get("hp")) < float(before.get("hp", 0.0)) - 0.01:
			return
		if float(actor.get("blood")) < float(before.get("blood", 0.0)) - 0.01:
			return
	_fail("5v5v5 should produce combat damage")


func _validate_no_floating(actors: Array[WorldActor], initial: Dictionary) -> void:
	for actor in actors:
		var before: Dictionary = initial.get(actor.get_instance_id(), {})
		if before.is_empty():
			continue
		var initial_position: Vector3 = before.get("position", actor.global_position)
		if actor.global_position.y > initial_position.y + 0.35 and not actor.is_on_floor():
			_fail("%s appears floating y=%.3f initial=%.3f" % [actor.name, actor.global_position.y, initial_position.y])


func _is_alive(actor: WorldActor) -> bool:
	return actor != null and is_instance_valid(actor) and int(actor.get("life_state")) == NpcRules.LifeState.ALIVE


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var offset := b - a
	offset.y = 0.0
	return offset.length()


func _get_alive_world_actors() -> Array[WorldActor]:
	var result: Array[WorldActor] = []
	for node in root.get_tree().get_nodes_in_group("world_actor"):
		var actor := node as WorldActor
		if actor != null and int(actor.get("life_state")) == NpcRules.LifeState.ALIVE:
			result.append(actor)
	return result


func _capture_actor_snapshot(actors: Array[WorldActor]) -> Dictionary:
	var snapshot := {}
	for actor in actors:
		snapshot[actor.get_instance_id()] = {
			"hp": float(actor.get("hp")),
			"blood": float(actor.get("blood")),
			"position": actor.global_position,
		}
	return snapshot


func _faction_counts(actors: Array[WorldActor]) -> Dictionary:
	var counts := {}
	for actor in actors:
		var faction := str(actor.get("faction_name"))
		counts[faction] = int(counts.get(faction, 0)) + 1
	return counts


func _cleanup_scene() -> void:
	if get_tree().node_added.is_connected(_on_runtime_node_added):
		get_tree().node_added.disconnect(_on_runtime_node_added)
	if _scene != null and is_instance_valid(_scene):
		root.remove_child(_scene)
		_scene.free()
	_scene = null
	await _wait_frames(8)


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _wait_simulation_frames(count: int) -> void:
	for _index in range(count):
		await physics_frame
		await process_frame


func _fail(message: String) -> void:
	_failures.append(message)
