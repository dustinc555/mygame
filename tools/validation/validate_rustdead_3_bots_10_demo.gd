extends SceneTree

const BOT_DEMO_SCENE := preload("res://scenes/test_levels/rustdead_3_bots_10_demo.tscn")
const QUADBOT_RACE := preload("res://resources/character_races/quadbot.tres")
const RUSTDEAD_RACE := preload("res://resources/character_races/rustdead.tres")
const QUADBOT_CHARACTER_SCRIPT := preload("res://src/actors/projection/quadbot/quadbot_character.gd")
const QUADBOT_BODY_PROJECTION_SCRIPT := preload("res://src/actors/projection/quadbot/quadbot_body_projection.gd")
const COMBAT_VALIDATION_FRAMES := 660

var _failures: Array[String] = []
var _scene: Node


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	await _load_scene()
	var bots := _get_party_members()
	var rustdead := _get_rustdead_members()
	_validate_bots(bots)
	_validate_rustdead(rustdead)
	var initial_health := _capture_health_snapshot(bots, rustdead)
	# TODO(actor-decoupling): this validator used to be spawn-only; keep combat assertions so robot-only squads cannot silently lose targeting again.
	await _wait_simulation_frames(COMBAT_VALIDATION_FRAMES)
	_validate_combat_engagement(bots, rustdead, initial_health)
	bots.clear()
	rustdead.clear()
	initial_health.clear()
	await _cleanup_scene()
	if _failures.is_empty():
		print("RUSTDEAD_3_BOTS_10_DEMO_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("RUSTDEAD_3_BOTS_10_DEMO_FAILED count=%d" % _failures.size())
	quit(1)


func _load_scene() -> void:
	_scene = BOT_DEMO_SCENE.instantiate()
	root.add_child(_scene)
	await _wait_frames(16)


func _cleanup_scene() -> void:
	if _scene == null:
		return
	_scene.queue_free()
	_scene = null
	await _wait_frames(10)


func _get_party_members() -> Array[WorldActor]:
	var result: Array[WorldActor] = []
	var party_root := _scene.get_node_or_null("PartyMembers") if _scene != null else null
	if party_root == null:
		_fail("PartyMembers node was not found")
		return result
	for child in party_root.get_children():
		if child is WorldActor:
			result.append(child as WorldActor)
	return result


func _get_rustdead_members() -> Array[HumanoidCharacter]:
	var result: Array[HumanoidCharacter] = []
	if _scene == null:
		return result
	for child in _scene.get_children():
		if child is HumanoidCharacter and str(child.get("faction_name")) == "Rustdead":
			result.append(child as HumanoidCharacter)
	return result


func _validate_bots(bots: Array[WorldActor]) -> void:
	if bots.size() != 3:
		_fail("Expected 3 robot party members, got %d" % bots.size())
	var skill_signatures := {}
	for bot in bots:
		if bot.get_script() != QUADBOT_CHARACTER_SCRIPT:
			_fail("%s should use QuadBotCharacter" % bot.name)
			continue
		if bot.get("character_race") != QUADBOT_RACE:
			_fail("%s should use quadbot race" % bot.name)
		if not bot.is_player_party_member():
			_fail("%s should be a player party member" % bot.name)
		if bot.combat_stance != NpcRules.CombatStance.DEFENSIVE:
			_fail("%s should use defensive combat stance" % bot.name)
		if not bot.ai_brain_enabled:
			_fail("%s should keep AI enabled" % bot.name)
		var body = bot.call("get_body_projection") if bot.has_method("get_body_projection") else null
		if body == null or body.get_script() != QUADBOT_BODY_PROJECTION_SCRIPT:
			_fail("%s should use QuadBotBodyProjection" % bot.name)
		else:
			for animation_name in ["Idle", "Walk", "Run", "Attack"]:
				if not body.has_clip(animation_name):
					_fail("%s robot body missing %s animation" % [bot.name, animation_name])
		skill_signatures[_validate_robot_skill_variance(bot)] = true
	if skill_signatures.size() < 2:
		_fail("Robot demo bots should not all share the same skill profile")


func _validate_rustdead(rustdead_members: Array[HumanoidCharacter]) -> void:
	if rustdead_members.size() != 10:
		_fail("Expected 10 Rustdead, got %d" % rustdead_members.size())
	for member in rustdead_members:
		if member.character_race != RUSTDEAD_RACE:
			_fail("%s should use rustdead race" % member.name)
		if member.combat_stance != NpcRules.CombatStance.AGGRESSIVE:
			_fail("%s should use aggressive combat stance" % member.name)
		if not member.hostile_factions.has("Player"):
			_fail("%s should be hostile to Player" % member.name)


func _capture_health_snapshot(bots: Array[WorldActor], rustdead_members: Array[HumanoidCharacter]) -> Dictionary:
	var snapshot := {}
	for actor in bots:
		_snapshot_actor_health(snapshot, actor)
	for actor in rustdead_members:
		_snapshot_actor_health(snapshot, actor)
	return snapshot


func _snapshot_actor_health(snapshot: Dictionary, actor: Node) -> void:
	if actor == null:
		return
	snapshot[actor.get_instance_id()] = {
		"hp": float(actor.get("hp")),
		"blood": float(actor.get("blood")),
		"life_state": int(actor.get("life_state")),
	}


func _validate_combat_engagement(bots: Array[WorldActor], rustdead_members: Array[HumanoidCharacter], initial_health: Dictionary) -> void:
	var rustdead_targeting_bots := 0
	var bots_targeting_rustdead := 0
	for rustdead in rustdead_members:
		var target := _get_combat_target(rustdead)
		if target != null and bots.has(target):
			rustdead_targeting_bots += 1
	for bot in bots:
		var target := _get_combat_target(bot)
		if target != null and rustdead_members.has(target):
			bots_targeting_rustdead += 1
	if rustdead_targeting_bots <= 0:
		_fail("Rustdead should acquire robot combat targets in the 3-bots demo")
	if bots_targeting_rustdead <= 0:
		_fail("Robot bots should answer with Rustdead combat targets in the 3-bots demo")
	if not _has_any_combat_damage(bots, rustdead_members, initial_health):
		_fail("3-bots demo should produce damage/death after combat simulation")


func _get_combat_target(actor: Node) -> Node:
	if actor == null or not actor.has_method("get_current_combat_target"):
		return null
	return actor.call("get_current_combat_target") as Node


func _has_any_combat_damage(bots: Array[WorldActor], rustdead_members: Array[HumanoidCharacter], initial_health: Dictionary) -> bool:
	for actor in bots:
		if _actor_took_damage(actor, initial_health):
			return true
	for actor in rustdead_members:
		if _actor_took_damage(actor, initial_health):
			return true
	return false


func _actor_took_damage(actor: Node, initial_health: Dictionary) -> bool:
	if actor == null:
		return false
	var initial: Dictionary = initial_health.get(actor.get_instance_id(), {})
	if initial.is_empty():
		return false
	if int(actor.get("life_state")) != int(initial.get("life_state", NpcRules.LifeState.ALIVE)):
		return true
	if float(actor.get("hp")) < float(initial.get("hp", 0.0)) - 0.01:
		return true
	return float(actor.get("blood")) < float(initial.get("blood", 0.0)) - 0.01


func _validate_robot_skill_variance(bot: WorldActor) -> String:
	var unique_levels := {}
	var total := 0
	var count := 0
	var parts: Array[String] = []
	for definition in SkillRules.get_all_definitions():
		var skill_id := str(definition.skill_id)
		var level := bot.get_skill_level(skill_id)
		if level < QUADBOT_CHARACTER_SCRIPT.QUADBOT_SKILL_MIN_LEVEL or level > QUADBOT_CHARACTER_SCRIPT.QUADBOT_SKILL_MAX_LEVEL:
			_fail("%s robot skill %s should be varied around 40, got %d" % [bot.name, skill_id, level])
		unique_levels[level] = true
		total += level
		count += 1
		parts.append("%s=%d" % [skill_id, level])
	if unique_levels.size() < 4:
		_fail("%s robot skills should not be flat" % bot.name)
	if count > 0:
		var average := float(total) / float(count)
		if average < 32.0 or average > 48.0:
			_fail("%s robot skills should average near 40, got %.2f" % [bot.name, average])
	return "|".join(parts)


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _wait_simulation_frames(count: int) -> void:
	for _index in range(count):
		await physics_frame
		await process_frame


func _fail(message: String) -> void:
	_failures.append(message)
