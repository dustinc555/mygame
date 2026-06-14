extends SceneTree

const RUSTDEAD_5V10_SCENE := preload("res://scenes/test_levels/rustdead_5v10_demo.tscn")
const ARMORY_10V10_SCENE := preload("res://scenes/test_levels/combat_skirmish_10v10_armory.tscn")
const SIM_FRAMES := 660

var _failures: Array[String] = []
var _scene: Node


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	await _validate_scene("rustdead_5v10", RUSTDEAD_5V10_SCENE, 3, 5)
	await _validate_scene("armory_10v10", ARMORY_10V10_SCENE, 4, 5)
	if _failures.is_empty():
		print("VISIBLE_COMBAT_BELIEVABILITY_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("VISIBLE_COMBAT_BELIEVABILITY_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_scene(label: String, packed_scene: PackedScene, min_distinct_targets: int, max_pressure_on_one_target: int) -> void:
	_scene = packed_scene.instantiate()
	root.add_child(_scene)
	await _wait_frames(16)
	var actors := _get_alive_world_actors()
	var initial := _capture_actor_snapshot(actors)
	await _wait_simulation_frames(SIM_FRAMES)
	actors = _get_alive_world_actors()
	_validate_no_stare_off(label, actors)
	_validate_target_spread(label, actors, min_distinct_targets, max_pressure_on_one_target)
	_validate_damage_happened(label, actors, initial)
	_validate_no_floating(label, actors, initial)
	await _cleanup_scene()


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


func _validate_no_stare_off(label: String, actors: Array[WorldActor]) -> void:
	var party_targeting_hostiles := 0
	var hostiles_targeting_party := 0
	for actor in actors:
		var target := actor.get_current_combat_target() as WorldActor
		if target == null:
			continue
		if actor.player_party_member and not target.player_party_member:
			party_targeting_hostiles += 1
		elif not actor.player_party_member and target.player_party_member:
			hostiles_targeting_party += 1
	if party_targeting_hostiles <= 0:
		_fail("%s party should acquire hostile combat targets" % label)
	if hostiles_targeting_party <= 0:
		_fail("%s hostiles should acquire party combat targets" % label)


func _validate_target_spread(label: String, actors: Array[WorldActor], min_distinct_targets: int, max_pressure_on_one_target: int) -> void:
	var pressure := {}
	for actor in actors:
		if actor.player_party_member:
			continue
		var target := actor.get_current_combat_target() as WorldActor
		if target == null or not target.player_party_member:
			continue
		var target_id := target.get_instance_id()
		pressure[target_id] = int(pressure.get(target_id, 0)) + 1
	if pressure.size() < mini(min_distinct_targets, _party_count(actors)):
		_fail("%s hostiles should spread across targets, distinct=%d pressure=%s" % [label, pressure.size(), str(pressure)])
	var max_pressure := 0
	for value in pressure.values():
		max_pressure = maxi(max_pressure, int(value))
	if max_pressure > max_pressure_on_one_target:
		_fail("%s too many hostiles on one target, max=%d pressure=%s" % [label, max_pressure, str(pressure)])


func _validate_damage_happened(label: String, actors: Array[WorldActor], initial: Dictionary) -> void:
	for actor in actors:
		var before: Dictionary = initial.get(actor.get_instance_id(), {})
		if before.is_empty():
			continue
		if float(actor.get("hp")) < float(before.get("hp", 0.0)) - 0.01:
			return
		if float(actor.get("blood")) < float(before.get("blood", 0.0)) - 0.01:
			return
	_fail("%s should produce combat damage" % label)


func _validate_no_floating(label: String, actors: Array[WorldActor], initial: Dictionary) -> void:
	for actor in actors:
		var before: Dictionary = initial.get(actor.get_instance_id(), {})
		if before.is_empty():
			continue
		var initial_position: Vector3 = before.get("position", actor.global_position)
		if actor.global_position.y > initial_position.y + 0.35 and not actor.is_on_floor():
			_fail("%s %s appears floating y=%.3f initial=%.3f" % [label, actor.name, actor.global_position.y, initial_position.y])


func _party_count(actors: Array[WorldActor]) -> int:
	var count := 0
	for actor in actors:
		if actor.player_party_member:
			count += 1
	return count


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
