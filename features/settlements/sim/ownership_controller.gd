extends Node

class_name OwnershipController

const SERVICE_ID := &"ownership"

const OWNERSHIP_UTILS_SCRIPT = preload("res://features/settlements/sim/ownership_utils.gd")

@export var notice_radius := 12.0
@export var warnings_before_attack := 2
@export var beloved_reputation_threshold := 75
@export var beloved_free_take_value := 5

const STEAL_ACTION_COLOR := Color(0.92, 0.34, 0.30, 1.0)
const THEFT_ATTEMPT_XP := 0.7
const THEFT_SUCCESS_XP := 1.8
const THEFT_DEXTERITY_XP_FACTOR := 0.08
const THEFT_DETECTION_PERCEPTION_XP := 1.1
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
var _context: BootstrapContext
var _warning_counts: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	add_to_group("ownership_controller")


func initialize(context: BootstrapContext) -> void:
	_context = context
	root_scene = context.root_scene


func request_interaction(actor: HumanoidCharacter, target, _action_label: String) -> bool:
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
			_award_theft_attempt_xp(actor, true)
			return true
		_award_theft_attempt_xp(actor, false)
		var suspicious_witnesses: Array[HumanoidCharacter] = [suspicious_witness]
		_award_theft_detection_xp(suspicious_witnesses)
		_warn_suspicious_witness(suspicious_witness, actor)
		return false
	_award_theft_attempt_xp(actor, false)
	_award_theft_detection_xp(witnesses)
	var law_controller := _get_law_order_controller()
	if law_controller != null and law_controller.has_method("report_theft_if_witnessed"):
		law_controller.call("report_theft_if_witnessed", actor, item, witnesses)
	else:
		var lead_witness: HumanoidCharacter = witnesses[0]
		lead_witness.show_world_speech("Thief! Guards!", 4.0)
		for witness in witnesses:
			witness.assign_attack_target(actor, false)
	return true


func get_take_item_metadata(actor: HumanoidCharacter, item, current_metadata: Dictionary = {}) -> Dictionary:
	var metadata := current_metadata.duplicate(true)
	if actor == null or item == null or _can_take_legally(actor, item):
		return metadata
	var law_controller := _get_law_order_controller()
	if law_controller != null and law_controller.has_method("make_stolen_item_metadata"):
		var stolen_metadata: Dictionary = law_controller.call("make_stolen_item_metadata", actor, item)
		for key in stolen_metadata.keys():
			metadata[key] = stolen_metadata[key]
	return metadata


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
	var actor_skill := _get_actor_theft_skill(actor)
	var best_witness: HumanoidCharacter = null
	var best_margin := -1.0
	for humanoid in _find_relevant_owner_witnesses(target):
		if actor == humanoid or humanoid.life_state != NpcRules.LifeState.ALIVE:
			continue
		var witness_distance := humanoid.global_position.distance_to(target_node.global_position)
		if witness_distance > noise_radius:
			continue
		var required_skill := _get_required_theft_skill(actor, target, humanoid, witness_distance, noise_radius)
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


func _get_required_theft_skill(actor: HumanoidCharacter, target, observer: HumanoidCharacter, witness_distance: float, noise_radius: float) -> float:
	var difficulty := float(_get_theft_difficulty(target))
	var proximity_pressure := 35.0 * (1.0 - clampf(witness_distance / maxf(noise_radius, 0.001), 0.0, 1.0))
	var perception_pressure := SkillRules.get_diminishing_bonus(float(observer.get_skill_level(SkillRules.ATTRIBUTE_PERCEPTION)) if observer != null else 0.0, 24.0, 45.0)
	var posture_penalty := 0.0 if actor != null and actor.sneaking else 15.0
	return maxf(0.0, difficulty + proximity_pressure + perception_pressure + posture_penalty)


func _get_actor_theft_skill(actor: HumanoidCharacter) -> float:
	if actor == null:
		return 0.0
	return SkillRules.get_assisted_skill_score(
		float(actor.get_skill_level(SkillRules.SUBTERFUGE_SLEIGHT_OF_HAND)),
		float(actor.get_skill_level(SkillRules.ATTRIBUTE_DEXTERITY)),
		18.0,
		38.0
	)


func _award_theft_attempt_xp(actor: HumanoidCharacter, succeeded: bool) -> void:
	if actor == null:
		return
	var amount := THEFT_SUCCESS_XP if succeeded else THEFT_ATTEMPT_XP
	actor.add_skill_xp(SkillRules.SUBTERFUGE_SLEIGHT_OF_HAND, amount, "theft")
	actor.add_skill_xp(SkillRules.ATTRIBUTE_DEXTERITY, amount * THEFT_DEXTERITY_XP_FACTOR, "theft")


func _award_theft_detection_xp(witnesses: Array[HumanoidCharacter]) -> void:
	for witness in witnesses:
		if witness != null:
			witness.add_skill_xp(SkillRules.ATTRIBUTE_PERCEPTION, THEFT_DETECTION_PERCEPTION_XP, "theft_detection")


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
	return _context.get_optional(PerceptionController.SERVICE_ID) if _context != null else null


func _get_faction_controller() -> Node:
	return _context.get_optional(FactionController.SERVICE_ID) if _context != null else null


func _get_law_order_controller() -> Node:
	return _context.get_optional(LawOrderController.SERVICE_ID) if _context != null else null


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
	var explicit_owner = OWNERSHIP_UTILS_SCRIPT.get_explicit_owner(target)
	var owner_key := "faction:%s" % OWNERSHIP_UTILS_SCRIPT.get_owner_faction_name(target)
	if explicit_owner != null:
		owner_key = explicit_owner.stable_id if not explicit_owner.stable_id.is_empty() else str(explicit_owner.get_instance_id())
	return "%s:%s" % [actor_key, owner_key]
