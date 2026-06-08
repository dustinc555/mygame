extends RefCounted

class_name SettlementStaffSlotUtils


static func collect_authored_staff_slots(root: Node, path_owner: Node, slots: Array[Dictionary]) -> void:
	if root == null:
		return
	for child in root.get_children():
		if child.has_meta("settlement_staff_slot_id"):
			var slot_id := str(child.get_meta("settlement_staff_slot_id", "")).strip_edges()
			if not slot_id.is_empty():
				var role_id := str(child.get_meta("settlement_staff_role", "guard")).strip_edges()
				var role_index := int(child.get_meta("settlement_staff_role_index", 0))
				slots.append(staff_slot_record(path_owner, slot_id, role_id, role_index, actor_display_name(child), true, child))
		collect_authored_staff_slots(child, path_owner, slots)


static func staff_slot_record(path_owner: Node, slot_id: String, role_id: String, role_index: int, display: String, filled: bool, actor: Node) -> Dictionary:
	var record := {
		"slot_id": slot_id,
		"role_id": role_id if not role_id.is_empty() else "guard",
		"role_index": role_index,
		"display_name": display if not display.is_empty() else slot_id.capitalize(),
		"population_cost": 1,
		"filled": filled,
	}
	if actor != null:
		record["actor_id"] = actor_id(actor)
		record["actor_path"] = path_owner.get_path_to(actor) if path_owner != null and actor.is_inside_tree() else NodePath()
	return record


static func actor_display_name(actor: Node) -> String:
	if has_property(actor, "member_name"):
		var value := str(actor.get("member_name")).strip_edges()
		if not value.is_empty():
			return value
	return str(actor.name) if actor != null else ""


static func actor_id(actor: Node) -> String:
	if has_property(actor, "stable_id"):
		var value := str(actor.get("stable_id")).strip_edges()
		if not value.is_empty():
			return value
	return str(actor.get_path()) if actor != null and actor.is_inside_tree() else (str(actor.get_instance_id()) if actor != null else "")


static func has_property(target: Object, property_name: String) -> bool:
	if target == null:
		return false
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false
