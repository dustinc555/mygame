extends Node

class_name OwnershipController

const OWNERSHIP_UTILS_SCRIPT = preload("res://scripts/ownership/ownership_utils.gd")

@export var notice_radius := 12.0
@export var warnings_before_attack := 2
@export var beloved_reputation_threshold := 75
@export var beloved_free_take_value := 5

const STEAL_ACTION_COLOR := Color(0.92, 0.34, 0.30, 1.0)
const THEFT_WARNING_LINES: Array[String] = [
	"That isn't yours.",
	"Put that back.",
	"I saw that.",
	"Don't touch our things.",
	"Careful. That belongs to someone.",
]
const THEFT_SUSPICION_LINES: Array[String] = [
	"What was that?",
	"Who's there?",
	"Careful around that.",
	"I heard something.",
]

var root_scene: Node
var _warning_counts: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	add_to_group("ownership_controller")


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


func request_take_item(actor: HumanoidCharacter, item) -> bool:
	if actor == null or item == null:
		return false
	if _can_take_legally(actor, item):
		return true
	if _actor_is_in_theft_combat(actor, item):
		return true
	var witnesses := _find_theft_witnesses(actor, item)
	if witnesses.is_empty():
		var suspicious_witness := _find_theft_suspicion_witness(actor, item)
		if suspicious_witness == null:
			return true
		_warn_suspicious_witness(suspicious_witness, actor)
		return false
	var key := _warning_key(actor, item)
	var warning_count := int(_warning_counts.get(key, 0))
	_warning_counts[key] = warning_count + 1
	if warning_count < warnings_before_attack:
		var warning_witness: HumanoidCharacter = witnesses[0]
		warning_witness.show_world_speech(THEFT_WARNING_LINES[_rng.randi_range(0, THEFT_WARNING_LINES.size() - 1)], 3.5)
		return false
	var lead_witness: HumanoidCharacter = witnesses[0]
	lead_witness.show_world_speech("Thief! Guards!", 4.0)
	for witness in witnesses:
		witness.assign_attack_target(actor, false)
	return true


func get_take_item_label(actor: HumanoidCharacter, item) -> String:
	return "Pick Up" if _can_take_legally(actor, item) or _actor_is_in_theft_combat(actor, item) else "Steal"


func get_take_item_color(actor: HumanoidCharacter, item) -> Color:
	return Color.TRANSPARENT if _can_take_legally(actor, item) or _actor_is_in_theft_combat(actor, item) else STEAL_ACTION_COLOR


func is_take_item_theft(actor: HumanoidCharacter, item) -> bool:
	return not (_can_take_legally(actor, item) or _actor_is_in_theft_combat(actor, item))


func _can_take_legally(actor: HumanoidCharacter, target) -> bool:
	if actor == null or target == null:
		return false
	if not OWNERSHIP_UTILS_SCRIPT.is_owned(target):
		return true
	if OWNERSHIP_UTILS_SCRIPT.is_authorized(actor, target):
		return true
	return _is_reputation_take_tolerated(actor, target)


func _is_reputation_take_tolerated(actor: HumanoidCharacter, target) -> bool:
	var owner_faction := _get_enforcing_faction_name(target)
	if owner_faction.is_empty() or actor.faction_name.is_empty() or actor.faction_name == owner_faction:
		return false
	var theft_value := _get_theft_value(target)
	if theft_value > beloved_free_take_value:
		return false
	var faction_controller := _get_faction_controller()
	if faction_controller == null or not faction_controller.has_method("get_reputation"):
		return false
	return int(faction_controller.call("get_reputation", actor.faction_name, owner_faction)) >= beloved_reputation_threshold


func _actor_is_in_theft_combat(actor: HumanoidCharacter, target) -> bool:
	for witness in _find_relevant_owner_witnesses(target):
		if actor.has_hostility_with(witness):
			return true
	return false


func _find_theft_witnesses(actor: HumanoidCharacter, target) -> Array[HumanoidCharacter]:
	var witnesses: Array[HumanoidCharacter] = []
	var perception_controller := _get_perception_controller()
	if perception_controller == null or not perception_controller.has_method("evaluate_observer"):
		return witnesses
	for humanoid in _find_relevant_owner_witnesses(target):
		if actor == humanoid or humanoid.life_state != NpcRules.LifeState.ALIVE:
			continue
		if humanoid.global_position.distance_to(actor.global_position) > notice_radius:
			continue
		var result := perception_controller.call("evaluate_observer", humanoid, actor) as Dictionary
		if bool(result.get("clearly_seen", false)):
			witnesses.append(humanoid)
	return witnesses


func _find_theft_suspicion_witness(actor: HumanoidCharacter, target) -> HumanoidCharacter:
	var noise_radius := _get_theft_noise_radius(target)
	if noise_radius <= 0.01 or not (target is Node3D):
		return null
	var target_node := target as Node3D
	var actor_skill := _get_actor_sleight_of_hand(actor)
	var best_witness: HumanoidCharacter = null
	var best_margin := -1.0
	for humanoid in _find_relevant_owner_witnesses(target):
		if actor == humanoid or humanoid.life_state != NpcRules.LifeState.ALIVE:
			continue
		var witness_distance := humanoid.global_position.distance_to(target_node.global_position)
		if witness_distance > noise_radius:
			continue
		var required_skill := _get_required_theft_skill(actor, target, witness_distance, noise_radius)
		if actor_skill >= required_skill:
			continue
		var margin := required_skill - actor_skill
		if margin > best_margin:
			best_margin = margin
			best_witness = humanoid
	return best_witness


func _warn_suspicious_witness(witness: HumanoidCharacter, actor: HumanoidCharacter) -> void:
	if witness == null or actor == null:
		return
	_turn_witness_toward_actor(witness, actor)
	witness.show_world_speech(THEFT_SUSPICION_LINES[_rng.randi_range(0, THEFT_SUSPICION_LINES.size() - 1)], 3.0)


func _turn_witness_toward_actor(witness: HumanoidCharacter, actor: HumanoidCharacter) -> void:
	var target_position := Vector3(actor.global_position.x, witness.global_position.y, actor.global_position.z)
	if witness.global_position.distance_squared_to(target_position) <= 0.001:
		return
	witness.look_at(target_position, Vector3.UP)
	witness.rotation.x = 0.0
	witness.rotation.z = 0.0


func _get_required_theft_skill(actor: HumanoidCharacter, target, witness_distance: float, noise_radius: float) -> float:
	var difficulty := float(_get_theft_difficulty(target))
	var proximity_pressure := 35.0 * (1.0 - clampf(witness_distance / maxf(noise_radius, 0.001), 0.0, 1.0))
	var posture_penalty := 0.0 if actor != null and actor.sneaking else 15.0
	return clampf(difficulty + proximity_pressure + posture_penalty, 0.0, 100.0)


func _get_actor_sleight_of_hand(actor: HumanoidCharacter) -> float:
	if actor == null:
		return 0.0
	var skill_value = actor.get("sleight_of_hand")
	return clampf(float(skill_value) if skill_value != null else 0.0, 0.0, 100.0)


func _find_relevant_owner_witnesses(target) -> Array[HumanoidCharacter]:
	var witnesses: Array[HumanoidCharacter] = []
	var explicit_owner = OWNERSHIP_UTILS_SCRIPT.get_explicit_owner(target)
	var owner_faction := _get_enforcing_faction_name(target)
	for node in get_tree().get_nodes_in_group("npc_character"):
		if not (node is HumanoidCharacter):
			continue
		var humanoid: HumanoidCharacter = node
		if humanoid.player_party_member or humanoid.life_state != NpcRules.LifeState.ALIVE:
			continue
		if explicit_owner != null:
			if humanoid == explicit_owner or (not explicit_owner.faction_name.is_empty() and humanoid.faction_name == explicit_owner.faction_name):
				witnesses.append(humanoid)
		elif not owner_faction.is_empty() and humanoid.faction_name == owner_faction:
			witnesses.append(humanoid)
	return witnesses


func _get_perception_controller() -> Node:
	for node in get_tree().get_nodes_in_group("perception_controller"):
		return node
	var bootstrap := root_scene.get_node_or_null("GameBootstrap") if root_scene != null else null
	return bootstrap.get_node_or_null("PerceptionController") if bootstrap != null else null


func _get_faction_controller() -> Node:
	for node in get_tree().get_nodes_in_group("faction_controller"):
		return node
	var bootstrap := root_scene.get_node_or_null("GameBootstrap") if root_scene != null else null
	return bootstrap.get_node_or_null("FactionController") if bootstrap != null else null


func _get_enforcing_faction_name(target) -> String:
	var explicit_owner = OWNERSHIP_UTILS_SCRIPT.get_explicit_owner(target)
	if explicit_owner != null and not explicit_owner.faction_name.is_empty():
		return explicit_owner.faction_name
	return OWNERSHIP_UTILS_SCRIPT.get_owner_faction_name(target)


func _get_theft_value(target) -> int:
	if target != null and target.has_method("get_theft_value"):
		return int(target.call("get_theft_value"))
	return 10


func _get_theft_noise_radius(target) -> float:
	if target != null and target.has_method("get_theft_noise_radius"):
		return float(target.call("get_theft_noise_radius"))
	return 0.0


func _get_theft_difficulty(target) -> int:
	if target != null and target.has_method("get_theft_difficulty"):
		return int(target.call("get_theft_difficulty"))
	return 25


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
