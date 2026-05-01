extends Node

class_name OwnershipController

const OWNERSHIP_UTILS_SCRIPT = preload("res://scripts/ownership/ownership_utils.gd")

@export var notice_radius := 12.0
@export var warnings_before_attack := 2

var root_scene: Node
var _warning_counts: Dictionary = {}


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root


func request_interaction(actor: HumanoidCharacter, target, action_label: String) -> bool:
	if actor == null or target == null:
		return false
	if not OWNERSHIP_UTILS_SCRIPT.is_owned(target):
		return true
	if OWNERSHIP_UTILS_SCRIPT.is_authorized(actor, target):
		return true
	var witnesses := _find_witnesses(target)
	if witnesses.is_empty():
		return true
	var key := _warning_key(actor, target)
	var warning_count := int(_warning_counts.get(key, 0))
	_warning_counts[key] = warning_count + 1
	if warning_count < warnings_before_attack:
		var warning_witness: HumanoidCharacter = witnesses[0]
		warning_witness.show_world_notice("Hey, leave that alone!", Color(1.0, 0.86, 0.42, 1.0), 5.0)
		return false
	var lead_witness: HumanoidCharacter = witnesses[0]
	lead_witness.show_world_notice("That's it! I warned you!", Color(1.0, 0.48, 0.38, 1.0), 5.0)
	for witness in witnesses:
		witness.assign_attack_target(actor, false)
	return false


func _find_witnesses(target) -> Array[HumanoidCharacter]:
	var witnesses: Array[HumanoidCharacter] = []
	var explicit_owner = OWNERSHIP_UTILS_SCRIPT.get_explicit_owner(target)
	var faction_name: String = OWNERSHIP_UTILS_SCRIPT.get_owner_faction_name(target)
	for node in get_tree().get_nodes_in_group("npc_character"):
		if not (node is HumanoidCharacter):
			continue
		var humanoid: HumanoidCharacter = node
		if humanoid.life_state != NpcRules.LifeState.ALIVE:
			continue
		if humanoid.global_position.distance_to(target.global_position) > notice_radius:
			continue
		if explicit_owner != null:
			if humanoid == explicit_owner or humanoid.faction_name == explicit_owner.faction_name:
				witnesses.append(humanoid)
		elif not faction_name.is_empty() and humanoid.faction_name == faction_name:
			witnesses.append(humanoid)
	return witnesses


func _warning_key(actor: HumanoidCharacter, target) -> String:
	var actor_key := actor.stable_id if not actor.stable_id.is_empty() else str(actor.get_instance_id())
	var owner = OWNERSHIP_UTILS_SCRIPT.get_explicit_owner(target)
	var owner_key := "faction:%s" % OWNERSHIP_UTILS_SCRIPT.get_owner_faction_name(target)
	if owner != null:
		owner_key = owner.stable_id if not owner.stable_id.is_empty() else str(owner.get_instance_id())
	return "%s:%s" % [actor_key, owner_key]
