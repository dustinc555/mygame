@tool
extends RefCounted

const SCENE = preload("res://features/settlements/bridge/venues/facility_guard_post.tscn")

## Both authoring surfaces use native scene ownership and the same undo action.
static func place(plugin: EditorPlugin, parent: Node3D, root_name: String, world_transform: Transform3D, scope: String) -> Node3D:
	var owner_root := plugin.get_editor_interface().get_edited_scene_root()
	if not is_instance_valid(parent) or owner_root == null:
		return null
	var container := parent.get_node_or_null(root_name) as Node3D
	var history := plugin.get_undo_redo()
	history.create_action("Place Guard Spot")
	if container == null:
		container = Node3D.new()
		container.name = root_name
		history.add_do_method(parent, "add_child", container)
		history.add_do_method(container, "set_owner", owner_root)
		history.add_undo_method(parent, "remove_child", container)
		history.add_do_reference(container)
	var post := SCENE.instantiate() as Node3D
	var suffix := 1
	while container.get_node_or_null("GuardSpot%d" % suffix) != null:
		suffix += 1
	post.name = "GuardSpot%d" % suffix
	post.set("post_id", "guard.%s" % ResourceUID.create_id())
	post.set("guard_scope", scope)
	var parent_transform := container.global_transform if container.is_inside_tree() else parent.global_transform
	post.transform = parent_transform.affine_inverse() * world_transform
	history.add_do_method(container, "add_child", post)
	history.add_do_method(post, "set_owner", owner_root)
	history.add_undo_method(container, "remove_child", post)
	history.add_do_reference(post)
	history.commit_action()
	return post
