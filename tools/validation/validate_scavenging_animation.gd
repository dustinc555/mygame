extends Node

## Scavenging presentation: ordered scavenge in the junkyard demo must reach
## scavenging_active and loop the Fixing_Kneeling clip (kneel-and-rummage).
## Baseline 2026-07-04: both flags true well inside the 500-frame window.

const DEMO_SCENE := preload("res://scenes/test_levels/junkyard_scavenging_demo.tscn")

var _frames := 0
var _demo: Node3D
var _ordered := false
var _clip_seen := false
var _active_seen := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	_demo = DEMO_SCENE.instantiate()
	add_child(_demo)

func _member() -> HumanoidCharacter:
	var party_root := _demo.get_node_or_null("PartyMembers")
	if party_root == null:
		return null
	for child in party_root.get_children():
		if child is HumanoidCharacter:
			return child
	return null

func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 60 and not _ordered:
		var member := _member()
		var pile := _demo.get_node_or_null("ScrapPiles/SmallScrapPile")
		if member == null or pile == null:
			printerr("SCAVENGE_ANIM_FAIL: missing member/pile member=%s pile=%s" % [member, pile])
			get_tree().quit()
			return
		member.assign_scavenging_resource(pile)
		_ordered = true
	if _ordered and _frames > 60:
		var member := _member()
		var interaction = member.get_interaction()
		if interaction != null and interaction.scavenging_active:
			_active_seen = true
			var body := member.get_body_projection() as HumanoidBodyProjection
			if body != null and body.get_current_clip() == HumanoidBodyProjection.SCAVENGING_ANIMATION_NAME:
				_clip_seen = true
	if _frames == 500 or (_clip_seen and _active_seen):
		printerr("scavenging_active_seen=%s Fixing_Kneeling_seen=%s" % [_active_seen, _clip_seen])
		printerr("SCAVENGE_ANIM_%s" % ("OK" if (_clip_seen and _active_seen) else "FAIL"))
		get_tree().quit()
