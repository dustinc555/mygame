extends Node

## Baseline 2026-07-04 (junkyard demo, 2 record members): base sliders foot-ground
## +0.0119/-0.0028; extremes +1.0/-1.0 measured +0.0149/-0.0054 — all within
## [-0.012, 0.045] band (visual ground includes 0.02 authored clearance).
## Custom height sliders (character creator) must keep feet on the
## ground with the new AnimationPositionScale compensation active.

const DEMO_SCENE := preload("res://scenes/test_levels/junkyard_scavenging_demo.tscn")

var _frames := 0
var _demo: Node3D
var _applied := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	_demo = DEMO_SCENE.instantiate()
	add_child(_demo)

func _members() -> Array:
	var result := []
	var party_root := _demo.get_node_or_null("PartyMembers")
	if party_root == null:
		return result
	for child in party_root.get_children():
		if child is HumanoidCharacter:
			result.append(child)
	return result

func _report(tag: String) -> bool:
	var all_ok := true
	for member in _members():
		var body := member.get_body_projection() as HumanoidBodyProjection
		if body == null:
			continue
		var foot_y: float = body.get_visual_foot_anchor_y()
		var ground_y: float = body.get_visual_ground_y()
		if foot_y == INF:
			continue
		var delta := foot_y - ground_y
		var ok := delta > -0.012 and delta < 0.045
		all_ok = all_ok and ok
		printerr("%s %s slider=%.2f foot-ground=%.4f %s" % [tag, member.name, member.appearance_data.height_slider if member.appearance_data != null else 0.0, delta, "ok" if ok else "OUT_OF_RANGE"])
	return all_ok

func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 100:
		_report("BASE")
		var members := _members()
		var sliders := [1.0, -1.0]
		for index in range(mini(members.size(), sliders.size())):
			var member: HumanoidCharacter = members[index]
			if member.appearance_data == null:
				continue
			var appearance := member.appearance_data.duplicate(true) as CharacterAppearanceData
			appearance.height_slider = sliders[index]
			member.apply_appearance_data(appearance)
		_applied = true
	if _frames == 220:
		var ok := _report("EXTREME")
		printerr("SLIDER_FEET_%s" % ("OK" if ok else "FAIL"))
		get_tree().quit()
