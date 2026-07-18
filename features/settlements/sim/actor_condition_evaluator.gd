extends RefCounted

class_name ActorConditionEvaluator


## The jail a staff member speaks for: walk up from the conversation target
## (a warden) to the facility that employs them.
static func find_jail_ancestor(node) -> Node:
	var current := node as Node
	while current != null:
		if current.has_method("admit_prisoner"):
			return current
		current = current.get_parent()
	return null


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
		"law.has_bailable_prisoners":
			var law = context.get("law_order")
			var bail_jail := find_jail_ancestor(context.get("conversation_target"))
			passed = law != null and bail_jail != null and law.has_method("get_bailable_prisoners") \
					and not (law.call("get_bailable_prisoners", context.get("speaker_member"), bail_jail) as Array).is_empty()
		"law.can_pay_bail":
			var law = context.get("law_order")
			var bail_jail := find_jail_ancestor(context.get("conversation_target"))
			passed = law != null and bail_jail != null and law.has_method("can_pay_bail") \
					and bool(law.call("can_pay_bail", context.get("speaker_member"), bail_jail))
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
