extends RefCounted

class_name ActorConditionEvaluator


static func evaluate(condition, context: Dictionary = {}) -> Dictionary:
	if condition == null:
		return {"passed": true, "reason": ""}

	var passed := false
	match str(condition.condition_id):
		"inventory.has_item_count":
			var actor = _resolve_subject(condition.parameters.get("subject", "speaker_member"), context)
			var item_definition = condition.parameters.get("item_definition")
			var count := int(condition.parameters.get("count", 0))
			passed = actor != null and actor.inventory != null and item_definition != null and actor.inventory.count_item(item_definition) >= count
		"actor.property_gte":
			passed = _compare_property(condition.parameters, context, true)
		"actor.property_lte":
			passed = _compare_property(condition.parameters, context, false)
		"actor.faction_in":
			var faction_actor = _resolve_subject(condition.parameters.get("subject", "speaker_member"), context)
			var factions: PackedStringArray = PackedStringArray(condition.parameters.get("factions", PackedStringArray()))
			passed = faction_actor != null and factions.has(str(faction_actor.faction_name))
		"actor.is_player_party_member":
			var party_actor = _resolve_subject(condition.parameters.get("subject", "speaker_member"), context)
			passed = party_actor != null and party_actor.has_method("is_player_party_member") and party_actor.is_player_party_member()
		_:
			passed = false

	if condition.negate:
		passed = not passed
	return {"passed": passed, "reason": "" if passed else str(condition.disabled_reason)}


static func passes_all(conditions: Array, context: Dictionary = {}) -> Dictionary:
	for condition in conditions:
		var result := evaluate(condition, context)
		if not result.get("passed", false):
			return result
	return {"passed": true, "reason": ""}


static func _compare_property(parameters: Dictionary, context: Dictionary, use_gte: bool) -> bool:
	var actor = _resolve_subject(parameters.get("subject", "speaker_member"), context)
	if actor == null:
		return false
	var property_name := str(parameters.get("property_name", ""))
	if property_name.is_empty():
		return false
	var target_value = float(parameters.get("value", 0.0))
	var actor_value: Variant = actor.get(property_name)
	if typeof(actor_value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	return float(actor_value) >= target_value if use_gte else float(actor_value) <= target_value


static func _resolve_subject(subject_key: Variant, context: Dictionary):
	match str(subject_key):
		"speaker_member", "worker":
			return context.get("speaker_member")
		"conversation_target", "provider_owner", "npc_self":
			return context.get("conversation_target")
		"job_provider":
			return context.get("job_provider")
	return null
