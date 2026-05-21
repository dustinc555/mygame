extends SceneTree

const JUNKYARD_SCENE := preload("res://scenes/test_levels/junkyard_scavenging_demo.tscn")

var _failures: Array[String] = []
var _scene: Node
var _novice: HumanoidCharacter
var _expert: HumanoidCharacter


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	await _load_scene()
	await _run_scavenging_case()
	_run_demo_button_cases()
	if _failures.is_empty():
		print("JUNKYARD_SCAVENGING_DEMO_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("JUNKYARD_SCAVENGING_DEMO_FAILED count=%d" % _failures.size())
	quit(1)


func _load_scene() -> void:
	_scene = JUNKYARD_SCENE.instantiate()
	root.add_child(_scene)
	await _wait_frames(50)
	_novice = _scene.get_node_or_null("PartyMembers/NoviceScavenger") as HumanoidCharacter
	_expert = _scene.get_node_or_null("PartyMembers/ExpertScavenger") as HumanoidCharacter
	if _novice == null:
		_fail("Novice scavenger was not found")
	if _expert == null:
		_fail("Expert scavenger was not found")
	if _novice != null and _novice.get_skill_level(SkillRules.LABOR_SCAVENGING) != 1:
		_fail("Expected novice scavenging to start at 1")
	if _expert != null and _expert.get_skill_level(SkillRules.LABOR_SCAVENGING) < 35:
		_fail("Expected expert scavenging to start high")
	if _scene.get_node_or_null("ScrapPiles/RobotScrapPile") == null:
		_fail("Robot scrap pile was not found")
	if _scene.get_node_or_null("ScrapPiles/OldWorldPile") == null:
		_fail("Old-world scrap pile was not found")
	if _scene.get_node_or_null("DemoButtons/NoiseButton") == null:
		_fail("Expected scavenging demo noise toggle button")


func _run_scavenging_case() -> void:
	if _novice == null or _scene == null:
		return
	var pile := _scene.get_node_or_null("ScrapPiles/RobotScrapPile") as ScavengingResourceNode
	if pile == null:
		return
	pile.current_charges = 1
	pile.min_useful_chance = 0.0
	pile.max_useful_chance = 0.0
	pile.junk_chance_on_failure = 0.0
	pile.set_show_charge_count(true)
	_novice.global_position = pile.get_scavenging_position(_novice)
	_novice._current_scavenging_node = pile
	pile.register_scavenger(_novice)
	var xp_before := _novice.get_skill_xp(SkillRules.LABOR_SCAVENGING)
	_novice._process_scavenging(pile.get_effective_scavenge_duration(_novice) + 0.5)
	var xp_after := _novice.get_skill_xp(SkillRules.LABOR_SCAVENGING)
	if xp_after <= xp_before:
		_fail("Expected junkyard scavenging to award XP")
	if pile.current_charges != 0:
		_fail("Expected junkyard pile to consume one charge")
	if not pile.is_depleted():
		_fail("Expected junkyard pile to be depleted after its last charge")
	var label := pile.get_node_or_null("Label3D") as Label3D
	if label == null or not label.text.contains("Depleted"):
		_fail("Expected depleted junkyard pile to say Depleted")
	if not pile.is_inside_tree():
		_fail("Expected depleted junkyard pile to remain in the scene")


func _run_demo_button_cases() -> void:
	if _scene == null or not _scene.has_method("perform_sneak_demo_action"):
		return
	var message := str(_scene.perform_sneak_demo_action("toggle_noise_radius"))
	if not message.contains("shown"):
		_fail("Expected noise radius toggle to report shown")
	message = str(_scene.perform_sneak_demo_action("reset_piles"))
	if not message.contains("reset"):
		_fail("Expected reset piles button action to report reset")


func _wait_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _fail(message: String) -> void:
	_failures.append(message)
