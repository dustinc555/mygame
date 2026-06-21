extends SceneTree

const FREE_FOR_ALL_SCENE := preload("res://scenes/test_levels/combat_free_for_all_5v5v5.tscn")
const SIM_FRAMES := 720
const TARGET_VALIDATION_FRAMES := 120
const PLAYER_FACTION := "Player"
const RAIDER_FACTION := "Raiders"
const CINDER_FACTION := "CinderHorde"
const QUADBOT_CHARACTER_SCRIPT := preload("res://scripts/characters/quadbot_character.gd")
const RUSTDEAD_CHARACTER_SCRIPT := preload("res://scripts/characters/rustdead_humanoid_character.gd")

var _failures: Array[String] = []
var _scene: Node


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	_scene = FREE_FOR_ALL_SCENE.instantiate()
	root.add_child(_scene)
	await _wait_frames(16)
	var actors := _get_alive_world_actors()
	var initial := _capture_actor_snapshot(actors)
	_validate_spawn(actors)
	await _wait_simulation_frames(TARGET_VALIDATION_FRAMES)
	var target_sample := _get_alive_world_actors()
	_validate_three_way_targets(target_sample)
	_validate_target_spread(target_sample)
	await _wait_simulation_frames(maxi(SIM_FRAMES - TARGET_VALIDATION_FRAMES, 0))
	var alive_after_sim := _get_alive_world_actors()
	_validate_damage_happened(actors, initial)
	_validate_no_floating(alive_after_sim, initial)
	await _cleanup_scene()
	if _failures.is_empty():
		print("COMBAT_FREE_FOR_ALL_5V5V5_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("COMBAT_FREE_FOR_ALL_5V5V5_FAILED count=%d" % _failures.size())
	quit(1)


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
