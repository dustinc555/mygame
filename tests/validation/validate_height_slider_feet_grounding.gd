extends Node

## Real demo body anchors at baseline and both authored height extremes.
const DEMO_SCENE := preload("res://scenes/test_levels/junkyard_scavenging_demo.tscn")
const EXPECTED_MEMBERS := 2
const READINESS_SECONDS := 40.0
var _demo: Node3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	_demo = DEMO_SCENE.instantiate()
	add_child(_demo)
	_run.call_deferred()

func _members() -> Array[HumanoidCharacter]:
	var result: Array[HumanoidCharacter] = []
	var party_root := _demo.get_node_or_null("PartyMembers")
	if party_root != null:
		for child in party_root.get_children():
			if child is HumanoidCharacter:
				result.append(child)
	return result

func _bodies_ready() -> bool:
	var members := _members()
	if members.size() != EXPECTED_MEMBERS:
		return false
	for member in members:
		var body := member.get_body_projection() as HumanoidBodyProjection
		if body == null or member.appearance_data == null:
			return false
		if not is_finite(body.get_visual_foot_anchor_y()) or not is_finite(body.get_visual_ground_y()):
			return false
	return true

func _wait_bodies() -> bool:
	var deadline := Time.get_ticks_msec() + int(READINESS_SECONDS * 1000)
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		if _bodies_ready():
			# Let the updated skeleton and grounding run through a full physics cycle.
			for _frame in range(4):
				await get_tree().physics_frame
			return _bodies_ready()
	return false

func _report(tag: String) -> bool:
	if not _bodies_ready():
		return false
	var all_ok := true
	for member in _members():
		var body := member.get_body_projection() as HumanoidBodyProjection
		var delta := body.get_visual_foot_anchor_y() - body.get_visual_ground_y()
		var ok := is_finite(delta) and delta > -0.012 and delta < 0.045
		all_ok = all_ok and ok
		print("%s %s slider=%.2f foot-ground=%.4f %s" % [tag, member.name, member.appearance_data.height_slider, delta, "ok" if ok else "OUT_OF_RANGE"])
	return all_ok

func _run() -> void:
	var ok := await _wait_bodies()
	if ok:
		ok = _report("BASE")
		# Every expected actor must be exercised at each extreme, not only one each.
		for slider in [1.0, -1.0]:
			for member in _members():
				var appearance := member.appearance_data.duplicate(true) as CharacterAppearanceData
				appearance.height_slider = slider
				member.apply_appearance_data(appearance)
			var ready := await _wait_bodies()
			var sample_ok := _report("EXTREME") if ready else false
			ok = sample_ok and ok
	print("SLIDER_FEET_%s" % ("OK" if ok else "FAIL"))
	_demo.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if ok else 1)
