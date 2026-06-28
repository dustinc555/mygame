extends Node

## Mining flow validator on the REAL mining_test scene: ordered mining must
## auto-equip the pick, walk to the node, loop the Mining clip, and climb the
## progress ratio the party HUD bar reads. Pickless members must be refused.

const PICKAXE := preload("res://features/inventory/resources/items/rusted_pickaxe.tres")

var _world: Node
var _elapsed := 0.0
var _phase := 0
var _no_pick_progress := -1.0
var _samples := []
var _fatigue_at_start := -1.0
var _mining_skill_at_start := -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_world = (load("res://scenes/test_levels/mining_test.tscn") as PackedScene).instantiate()
	add_child(_world)

func _member() -> WorldActor:
	# Mira: scene-authored WITH a rusted pickaxe (the mining check).
	for node in get_tree().get_nodes_in_group("humanoid_character"):
		var actor := node as WorldActor
		if actor != null and actor.is_player_party_member() and actor.member_name == "Mira":
			return actor
	return null


func _pickless_member() -> WorldActor:
	for node in get_tree().get_nodes_in_group("humanoid_character"):
		var actor := node as WorldActor
		if actor == null or not actor.is_player_party_member():
			continue
		var weapon := actor.get_equipped_item("weapon")
		if weapon == null or not str(weapon.display_name).to_lower().contains("pick"):
			return actor
	return null

func _node_target() -> Node:
	for node in get_tree().get_nodes_in_group("mining_resource"):
		return node
	return null

func _process(delta: float) -> void:
	_elapsed += delta
	get_tree().paused = false
	var m := _member()
	var target := _node_target()
	if m == null or target == null:
		return
	if _phase == 0 and _elapsed >= 2.0:
		_phase = 1
		var pickless := _pickless_member()
		if pickless != null:
			pickless.assign_mining_resource(target)
	elif _phase == 1 and _elapsed >= 6.0:
		_phase = 2
		var pickless := _pickless_member()
		if pickless != null:
			_no_pick_progress = 1.0 if pickless.is_actively_mining() else 0.0
			print("MINING_PROBE no_pick(%s): active=%s" % [pickless.member_name, pickless.is_actively_mining()])
		m.assign_mining_resource(target)
	elif _phase == 2 and _elapsed >= 9.0 and _fatigue_at_start < 0.0 and m.is_actively_mining():
		_fatigue_at_start = m.fatigue
		_mining_skill_at_start = m.get_skill_level("labor.mining") if m.has_method("get_skill_level") else -1
	elif _phase == 2 and _elapsed >= 10.0 and fmod(_elapsed, 2.0) < delta:
		var body = m.get_body_projection()
		_samples.append({"active": m.is_actively_mining(), "ratio": m.get_mining_progress_ratio(), "clip": body.get_current_clip()})
		print("MINING_PROBE t=%.0f active=%s ratio=%.2f clip=%s equipped=%s" % [_elapsed, m.is_actively_mining(), m.get_mining_progress_ratio(), body.get_current_clip(), m.get_equipped_item("weapon").display_name if m.get_equipped_item("weapon") != null else "none"])
	if _elapsed >= 20.0:
		set_process(false)
		var failures := 0
		if _no_pick_progress > 0.0:
			push_error("mined without a pick")
			failures += 1
		var mined := false
		var animated := false
		for s in _samples:
			if s["active"] and s["ratio"] > 0.0:
				mined = true
			if s["clip"] == "Mining":
				animated = true
		if not mined:
			push_error("never actively mined with pick (bar would stay hidden)")
			failures += 1
		if not animated:
			push_error("Mining clip never played")
			failures += 1
		var m2 := _member()
		if _fatigue_at_start >= 0.0 and m2 != null:
			var fatigue_drop: float = _fatigue_at_start - m2.fatigue
			print("MINING_PROBE energy: start=%.2f end=%.2f drop=%.2f" % [_fatigue_at_start, m2.fatigue, fatigue_drop])
			if fatigue_drop <= 0.0:
				push_error("mining consumed no energy (fatigue did not drop)")
				failures += 1
		print("MINING_PROBE_%s" % ("OK" if failures == 0 else "FAILED count=%d" % failures))
		get_tree().quit(0 if failures == 0 else 1)
