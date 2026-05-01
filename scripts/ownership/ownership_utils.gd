extends RefCounted

class_name OwnershipUtils


static func get_explicit_owner(target):
	if target == null:
		return null
	if target.has_method("get_explicit_owner_character"):
		return target.get_explicit_owner_character()
	return null


static func get_owner_faction_name(target) -> String:
	if target == null:
		return ""
	if target.has_method("get_owner_faction_name"):
		return str(target.get_owner_faction_name())
	return ""


static func get_effective_owner(target):
	var explicit_owner = get_explicit_owner(target)
	if explicit_owner != null:
		return explicit_owner
	var faction_name := get_owner_faction_name(target)
	if faction_name.is_empty():
		return null
	var tree: SceneTree = target.get_tree() if target != null else null
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("npc_character"):
		if node is HumanoidCharacter and node.faction_name == faction_name:
			return node
	return null


static func is_owned(target) -> bool:
	return get_explicit_owner(target) != null or not get_owner_faction_name(target).is_empty()


static func is_authorized(actor: HumanoidCharacter, target) -> bool:
	if actor == null or target == null:
		return false
	var owner_character = get_explicit_owner(target)
	var faction_name := get_owner_faction_name(target)
	if owner_character == null and faction_name.is_empty():
		return true
	if actor.has_method("is_authorized_for_owner"):
		return actor.is_authorized_for_owner(owner_character, faction_name)
	if owner_character != null and actor == owner_character:
		return true
	return not faction_name.is_empty() and actor.faction_name == faction_name
