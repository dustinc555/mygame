@tool
extends RefCounted

const PICKS := preload("res://features/lockpicking/sim/lockpick_rules.gd")

## Leaf-node adapter; controllers use their injected context instead.
static func bind(target: Node) -> void:
	if Engine.is_editor_hint() or not target.is_inside_tree():
		return
	target.add_to_group("lockpick_target")
	var bridge := BootstrapContext.service(&"lockpick_interactions")
	if bridge != null:
		bridge.register_target(target)

static func actions(target: Node, actor: Node) -> Array:
	if actor == null or PICKS.find_pick(actor.get("inventory") as InventoryData) == null:
		return []
	var bridge := BootstrapContext.service(&"lockpick_interactions")
	if bridge == null or not bridge.can_pick(target, actor):
		return []
	return [{"key": "pick_lock", "label": "Pick Lock (Careful)"},
		{"key": "pick_lock_rushed", "label": "Pick Lock (Rushed)"}]

static func request(target: Node, action: String, actors: Array) -> String:
	if action not in ["pick_lock", "pick_lock_rushed", "lockpick"]:
		return ""
	var bridge := BootstrapContext.service(&"lockpick_interactions")
	if bridge == null:
		return "Lockpicking unavailable."
	for actor in actors:
		if actor is WorldActor and bridge.request_pick(actor, target, "rushed" if action == "pick_lock_rushed" else "careful"):
			return ""
	return "A usable lockpick and sufficient skill are required; the lock must be free."

static func scoped_cell_id(cell: Node, local_id: String) -> String:
	var parent := cell.get_parent()
	while parent != null:
		if parent.has_method("get_facility_id"):
			return "cell:%s:%s" % [parent.get_facility_id(), local_id]
		parent = parent.get_parent()
	return "cell:%s" % local_id
