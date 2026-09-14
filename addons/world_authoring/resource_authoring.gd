@tool
extends RefCounted

## Scene authoring only. The catalog reads the same definitions the runtime uses;
## authored deposits are ordinary independent scene nodes, never field-owned.
const DEFINITIONS_DIR := "res://features/world/resources/resource_deposits"

static func load_catalog() -> Array[Resource]:
	var entries: Array[Resource] = []
	if not DirAccess.dir_exists_absolute(DEFINITIONS_DIR):
		return entries
	var seen := {}
	for file_name in DirAccess.get_files_at(DEFINITIONS_DIR):
		if file_name.get_extension() != "tres":
			continue
		var definition := load(DEFINITIONS_DIR.path_join(file_name)) as Resource
		if definition == null or not definition.has_method("validation_errors"):
			continue
		var errors = definition.call("validation_errors")
		if not errors.is_empty():
			push_warning("Resource catalog: %s — %s" % [file_name, "; ".join(errors)])
			continue
		var id := str(definition.get("deposit_type_id"))
		if seen.has(id):
			push_warning("Resource catalog has duplicate type ID: %s" % id)
			continue
		seen[id] = true
		entries.append(definition)
	entries.sort_custom(func(a: Resource, b: Resource):
		var first := "%s/%s" % [a.get("category"), a.get("display_name")]
		var second := "%s/%s" % [b.get("category"), b.get("display_name")]
		return first.naturalnocasecmp_to(second) < 0)
	return entries

static func place_resource(parent: Node3D, scene_owner: Node, definition: Resource, world_transform: Transform3D, undo: Object) -> Node3D:
	if not is_instance_valid(parent) or not is_instance_valid(scene_owner) or definition == null or undo == null:
		return null
	if not definition.has_method("validation_errors") or not definition.call("validation_errors").is_empty():
		return null
	var packed := load(str(definition.get("scene_path"))) as PackedScene
	if packed == null:
		return null
	var node := packed.instantiate() as Node3D
	if node == null:
		return null
	node.name = str(definition.get("display_name")).validate_node_name().replace(" ", "")
	node.set("resource_node_id", new_deposit_id())
	node.set("deposit_definition", definition)
	var parent_transform := parent.global_transform if parent.is_inside_tree() else parent.transform
	node.transform = parent_transform.affine_inverse() * world_transform
	if undo is EditorUndoRedoManager:
		undo.create_action("Place %s" % definition.get("display_name"), UndoRedo.MERGE_DISABLE, scene_owner)
		undo.add_do_method(parent, "add_child", node, true)
		undo.add_do_method(node, "set_owner", scene_owner)
		undo.add_undo_method(parent, "remove_child", node)
	else:
		undo.create_action("Place %s" % definition.get("display_name"))
		undo.add_do_method(parent.add_child.bind(node, true))
		undo.add_do_method(node.set_owner.bind(scene_owner))
		undo.add_undo_method(parent.remove_child.bind(node))
	undo.add_do_reference(node)
	undo.commit_action()
	return node

static func new_deposit_id() -> String:
	return "deposit_" + Crypto.new().generate_random_bytes(16).hex_encode()

static func is_deposit(node: Node) -> bool:
	if node == null:
		return false
	# Script methods are discoverable on non-@tool nodes in the editor even when
	# calling gameplay methods there is deliberately disabled.
	var script := node.get_script() as Script
	while script != null:
		for method in script.get_script_method_list():
			if str(method.name) == "get_resource_progress_key":
				return true
		script = script.get_base_script()
	return false

static func collect_deposits(root: Node) -> Array[Node]:
	var deposits: Array[Node] = []
	if not is_instance_valid(root):
		return deposits
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if is_deposit(node):
			deposits.append(node)
		# Preserve authored order: a new Ctrl+D copy follows its source, so the
		# original keeps its durable ID when duplicate IDs are repaired.
		var children := node.get_children()
		for index in range(children.size() - 1, -1, -1):
			pending.append(children[index])
	return deposits

static func repair_duplicate_ids(root: Node, undo: Object) -> int:
	# Called at the editor save boundary, not on every click or runtime frame.
	# This also covers ordinary Godot Ctrl+D/scene-tree duplication.
	var used := {}
	var changed: Array[Dictionary] = []
	for node in collect_deposits(root):
		if node.owner != root:
			continue  # Never rewrite a nested scene's authored source from its host.
		var previous := str(node.get("resource_node_id"))
		if previous.is_empty() or used.has(previous):
			changed.append({"node": node, "old": previous, "new": new_deposit_id()})
		else:
			used[previous] = true
	if changed.is_empty():
		return 0
	if undo is EditorUndoRedoManager:
		undo.create_action("Assign Resource Deposit IDs", UndoRedo.MERGE_DISABLE, root)
	else:
		undo.create_action("Assign Resource Deposit IDs")
	for edit in changed:
		undo.add_do_property(edit.node, "resource_node_id", edit.new)
		undo.add_undo_property(edit.node, "resource_node_id", edit.old)
	undo.commit_action()
	return changed.size()
