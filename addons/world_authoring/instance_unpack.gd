@tool
extends RefCounted

## Shared "make local" for authoring concepts (towns, facilities). Expands a
## scene instance into plain nodes owned by the edited scene root: the root
## keeps its script and property values, loses its scene link, and every
## internal node becomes visible, editable, and saved with the open scene.
## Nested scene instances inside (building shells, furniture pieces) keep
## their own scene links. Undoable: repack restores the scene link and the
## prior owner of every node.
##
## Safety rule enforced by callers: never unpack a node that still has a
## scene-instance ancestor below the edited root — the ancestor's packed
## file would keep providing the original children while the open scene
## saved duplicates of them.


func unpack(instance: Node, edited_root: Node, undo_redo: EditorUndoRedoManager) -> void:
	if instance == null or edited_root == null or instance == edited_root:
		return
	if instance.scene_file_path.is_empty():
		return
	var scene_path := instance.scene_file_path
	var prior_owners := {}
	_collect_owners(instance, prior_owners)
	undo_redo.create_action("Unpack %s" % instance.name)
	undo_redo.add_do_method(self, "_apply_unpack", instance, edited_root)
	undo_redo.add_undo_method(self, "_apply_repack", instance, scene_path, prior_owners)
	undo_redo.commit_action()


func _collect_owners(node: Node, owners: Dictionary) -> void:
	for child in node.get_children():
		owners[child] = child.owner
		if child.scene_file_path.is_empty():
			_collect_owners(child, owners)


func _apply_unpack(instance: Node, edited_root: Node) -> void:
	instance.scene_file_path = ""
	# Detach/reattach: scene_file_path and owner edits alone don't emit
	# tree_changed, so the editor's Scene dock would keep drawing the node as
	# a childless instance. Removing clears owners in the subtree, which is
	# why re-owning happens after the reattach.
	_reattach_in_place(instance)
	instance.owner = edited_root
	_own_recursive(instance, edited_root)
	instance.set_display_folded(true)
	EditorInterface.mark_scene_as_unsaved()


func _reattach_in_place(node: Node) -> void:
	var parent := node.get_parent()
	if parent == null:
		return
	var index := node.get_index()
	parent.remove_child(node)
	parent.add_child(node)
	parent.move_child(node, index)


func _own_recursive(node: Node, edited_root: Node) -> void:
	# An instance root owns its internals. Claiming them makes the editor save
	# duplicate type+instance entries that load as phantom off-tree nodes.
	if not node.scene_file_path.is_empty():
		return
	for child in node.get_children():
		child.owner = edited_root
		if child.get_child_count() > 0:
			child.set_display_folded(true)
		if child.scene_file_path.is_empty():
			_own_recursive(child, edited_root)


func _apply_repack(instance: Node, scene_path: String, prior_owners: Dictionary) -> void:
	if instance == null or not is_instance_valid(instance):
		return
	instance.scene_file_path = scene_path
	_reattach_in_place(instance)
	for node_value in prior_owners:
		var node := node_value as Node
		if node != null and is_instance_valid(node):
			node.owner = prior_owners[node_value]
	EditorInterface.mark_scene_as_unsaved()
