extends RefCounted

class_name WorldContextActionMenu

const CANCEL_KEY := "world_context_cancel"


static func expand_children(action: Dictionary) -> Array:
	var expanded: Array = []
	for child in action.get("children", []):
		if child is Dictionary:
			expanded.append((child as Dictionary).duplicate(true))
	expanded.append({"key": CANCEL_KEY, "label": "Cancel"})
	return expanded
