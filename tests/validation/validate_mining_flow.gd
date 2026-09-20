extends "res://tests/validation/test_case.gd"
## Real mining demo: authored miner, actual work/animation/energy, causal tool refusal.
const PICKAXE := preload("res://features/inventory/resources/items/rusted_pickaxe.tres")

var _world: Node
var _started_msec := 0
var _elapsed := 0.0
var _phase := 0
var _ready_for_play := false
var _no_pick_progress := -1.0
var _samples: Array[Dictionary] = []
var _fatigue_at_start := -1.0
var _pickless: WorldActor
var _refused := false
var _eligible_control := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_started_msec = Time.get_ticks_msec()
	_world = (load("res://scenes/test_levels/mining_test.tscn") as PackedScene).instantiate()
	add_child(_world)

func _member() -> WorldActor:
	for node in get_tree().get_nodes_in_group("humanoid_character"):
		var actor := node as WorldActor
		if actor != null and actor.is_player_party_member() and actor.member_name == "Mira" and _world.is_ancestor_of(actor):
			return actor
	return null

func _node_target() -> Node:
	for node in get_tree().get_nodes_in_group("mining_resource"):
		if _world.is_ancestor_of(node):
			return node
	return null

func _create_pickless_control(miner: WorldActor, target: Node) -> bool:
	# Current demo members may both carry picks. Do not strip their authored gear
	# or weaken refusal coverage: a separate real actor supplies the negative case.
	_pickless = HumanoidCharacter.new()
	_pickless.name = "ValidationPicklessControl"
	_pickless.member_name = "Validation Pickless"
	_pickless.stable_id = "validation.pickless_control"
	_world.add_child(_pickless)
	_pickless.set_player_party_member(true)
	_pickless.global_position = miner.global_position + Vector3(1.0, 0.0, 0.0)
	var bridge := _world.find_child("GecsWorldController", true, false) as GecsWorldController
	if bridge == null or bridge.register_actor(_pickless).is_empty():
		return false
	var interaction := _pickless.get_interaction()
	var equipment := _pickless.get_equipment()
	# Prove this same living actor is eligible when equipped, so its later refusal
	# cannot be explained by a bad fixture, unavailable work, or disabled orders.
	equipment.equip_item_to_slot(PICKAXE, ItemDefinition.EQUIP_SLOT_WEAPON, "validation.control.pick")
	_pickless.assign_mining_resource(target)
	_eligible_control = interaction.has_mining_assignment()
	interaction.stop_mining_assignment()
	equipment.unequip_item_from_slot(ItemDefinition.EQUIP_SLOT_WEAPON)
	if interaction.find_inventory_tool(str(target.required_tool_tag)) != null:
		return false
	_pickless.assign_mining_resource(target)
	_refused = not interaction.has_mining_assignment()
	return _eligible_control and _refused

func _process(delta: float) -> void:
	var clock := _world.find_child("WorldTimeController", true, false) as WorldTimeController
	var miner := _member()
	var target := _node_target()
	if not _ready_for_play:
		if clock == null or clock.is_world_paused() or miner == null or target == null:
			if Time.get_ticks_msec() - _started_msec >= 40000:
				push_error("Real mining demo did not finish loading with actor/resource prerequisites")
				quit(1)
			return
		_ready_for_play = true
		return
	_elapsed += delta
	if _phase == 0:
		_phase = 1
		if not _create_pickless_control(miner, target):
			push_error("Real tool-refusal control must accept with a pick and refuse without one")
			quit(1)
			return
	elif _phase == 1 and _elapsed >= 2.0:
		_phase = 2
		_no_pick_progress = 1.0 if _pickless.get_interaction().is_actively_mining() else 0.0
		miner.assign_mining_resource(target)
	elif _phase == 2:
		var interaction := miner.get_interaction()
		if interaction.is_actively_mining() and _fatigue_at_start < 0.0:
			_fatigue_at_start = miner.fatigue
		if _elapsed >= 4.0 and fmod(_elapsed, 1.0) < delta:
			var body := miner.get_body_projection()
			_samples.append({"active": interaction.is_actively_mining(), "ratio": interaction.get_mining_progress_ratio(), "clip": body.get_current_clip() if body != null else ""})
			print("MINING_PROBE t=%.0f active=%s ratio=%.2f clip=%s" % [_elapsed, _samples[-1].active, _samples[-1].ratio, _samples[-1].clip])
	if _elapsed >= 20.0:
		_finish_mining(miner)

func _finish_mining(miner: WorldActor) -> void:
	set_process(false)
	var failures := 0
	if not _eligible_control or not _refused or _no_pick_progress != 0.0:
		push_error("Tool requirement must be the causal reason the control actor cannot mine")
		failures += 1
	var animated := false
	for sample in _samples:
		if not is_finite(float(sample.ratio)):
			push_error("Mining progress must remain finite")
			failures += 1
		if sample.active and sample.clip == "Mining" and is_finite(float(sample.ratio)) and float(sample.ratio) > 0.0:
			animated = true
	if _samples.is_empty() or not animated:
		push_error("Authored miner must actually work, show progress, and play the Mining clip")
		failures += 1
	var fatigue_drop := _fatigue_at_start - miner.fatigue
	print("MINING_PROBE energy: start=%.2f end=%.2f drop=%.2f" % [_fatigue_at_start, miner.fatigue, fatigue_drop])
	if _fatigue_at_start < 0.0 or not is_finite(fatigue_drop) or fatigue_drop <= 0.0:
		push_error("Actual mining must consume finite positive energy")
		failures += 1
	print("MINING_PROBE_%s" % ("OK" if failures == 0 else "FAILED count=%d" % failures))
	quit(0 if failures == 0 else 1)
