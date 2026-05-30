@tool
extends StaticBody3D

class_name JailCell

@export var cell_id := ""
@export_range(1, 12, 1) var prisoner_capacity := 1
@export_range(0, 100, 1) var lock_difficulty := 10
@export var occupant_paths: Array[NodePath] = []
@export var interaction_point_path: NodePath = NodePath("InteractionPoint")
@export var prisoner_point_path: NodePath = NodePath("PrisonerPoint")
@export var release_point_path: NodePath = NodePath("ReleasePoint")
@export var prisoner_stand_offset := Vector3(0.0, 0.08, 0.0)
@export var visual_scene: PackedScene:
	set(value):
		visual_scene = value
		_refresh_visual()
@export var visual_transform := Transform3D.IDENTITY:
	set(value):
		visual_transform = value
		_refresh_visual()
@export var collision_shape: Shape3D:
	set(value):
		collision_shape = value
		_refresh_collision()
@export var collision_transform := Transform3D(Basis.IDENTITY, Vector3(0.04147339, 1.5626037, -0.02746582)):
	set(value):
		collision_transform = value
		_refresh_collision()


func _ready() -> void:
	add_to_group("jail_cell")
	if Engine.is_editor_hint() and not _can_editor_modify_preview():
		return
	_refresh_collision()
	_refresh_visual()


func get_cell_id() -> String:
	return cell_id if not cell_id.strip_edges().is_empty() else str(name)


func get_interaction_position(_actor = null) -> Vector3:
	var point := get_node_or_null(interaction_point_path) as Node3D
	return point.global_position if point != null else global_transform * Vector3(0.0, 0.6, 1.4)


func get_interaction_route(actor = null) -> Array[Vector3]:
	var current := get_parent()
	while current != null:
		if current.has_method("get_cell_interaction_route"):
			return current.call("get_cell_interaction_route", self, actor)
		current = current.get_parent()
	return [get_interaction_position(actor)]


func get_available_capacity() -> int:
	return max(0, prisoner_capacity - get_occupant_count())


func get_occupant_count() -> int:
	var count := 0
	for path in occupant_paths:
		if get_node_or_null(path) != null:
			count += 1
	return count


func can_assign_prisoner(actor: Node) -> bool:
	return actor != null and get_available_capacity() > 0


func assign_prisoner(actor: Node) -> bool:
	if not can_assign_prisoner(actor):
		return false
	var path := get_path_to(actor)
	if occupant_paths.has(path):
		return true
	occupant_paths.append(path)
	return true


func release_prisoner(actor: Node) -> void:
	if actor == null:
		return
	var path := get_path_to(actor)
	occupant_paths.erase(path)


func get_prisoner_position(_actor = null) -> Vector3:
	var point := get_node_or_null(prisoner_point_path) as Node3D
	return point.global_position if point != null else global_transform * Vector3(0.0, -0.35, 0.0)


func get_prisoner_stand_position(actor = null) -> Vector3:
	return get_prisoner_position(actor) + prisoner_stand_offset


func get_prisoner_rotation(_actor = null) -> Vector3:
	var point := get_node_or_null(prisoner_point_path) as Node3D
	return point.global_rotation if point != null else global_rotation + Vector3(0.0, PI, 0.0)


func get_release_position() -> Vector3:
	var point := get_node_or_null(release_point_path) as Node3D
	return point.global_position if point != null else global_transform * Vector3(0.0, 0.6, 1.4)


func get_release_rotation() -> Vector3:
	var point := get_node_or_null(release_point_path) as Node3D
	return point.global_rotation if point != null else global_rotation


func place_carried_prisoner(carrier: HumanoidCharacter, prisoner: HumanoidCharacter) -> bool:
	if carrier == null or prisoner == null:
		return false
	if not can_assign_prisoner(prisoner):
		return false
	if not assign_prisoner(prisoner):
		return false
	if prisoner.has_method("enter_cell_custody"):
		prisoner.call("enter_cell_custody", self, get_prisoner_position(prisoner), get_prisoner_rotation(prisoner))
	else:
		prisoner.global_position = get_prisoner_position(prisoner)
		prisoner.global_rotation = get_prisoner_rotation(prisoner)
		prisoner.velocity = Vector3.ZERO
	return true


func attempt_unlock(actor: HumanoidCharacter) -> bool:
	_report_lockpicking(actor)
	var skill := actor.get_skill_level(SkillRules.SUBTERFUGE_LOCKPICKING) if actor != null and actor.has_method("get_skill_level") else 0
	if skill < lock_difficulty:
		_show_lockpick_failure_notice(actor)
		if actor != null and actor.has_method("show_world_speech"):
			actor.show_world_speech("The cage lock resists.", 2.5)
		return false
	if actor != null and actor.has_method("show_world_speech"):
		actor.show_world_speech("Cell unlocked.", 2.0)
	return true


func get_world_context_actions(_actor) -> Array:
	return [{"key": "pick_lock", "label": "Pick Lock"}]


func perform_world_context_action(action_key: String, actors: Array) -> String:
	if action_key != "pick_lock":
		return ""
	var actor := actors[0] as HumanoidCharacter if not actors.is_empty() else null
	return "Unlocked" if attempt_unlock(actor) else "Lock too hard"


func get_cell_record() -> Dictionary:
	return {
		"cell_id": get_cell_id(),
		"prisoner_capacity": prisoner_capacity,
		"occupant_count": get_occupant_count(),
		"lock_difficulty": lock_difficulty,
	}


func _report_lockpicking(actor: HumanoidCharacter) -> void:
	if actor == null:
		return
	var tree := get_tree()
	if tree == null:
		return
	for controller in tree.get_nodes_in_group("law_order_controller"):
		if controller != null and controller.has_method("report_lockpicking_if_witnessed"):
			controller.call("report_lockpicking_if_witnessed", actor, self)
			return


func _show_lockpick_failure_notice(actor: HumanoidCharacter) -> void:
	if actor == null or not actor.has_signal("center_notice_requested"):
		return
	actor.center_notice_requested.emit("Lock too hard")


func _refresh_collision() -> void:
	if not is_inside_tree():
		return
	if Engine.is_editor_hint() and not _can_editor_modify_preview():
		return
	var collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null:
		collision = CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		add_child(collision)
		_set_editor_owner(collision)
	if collision_shape == null:
		var box := BoxShape3D.new()
		box.size = Vector3(1.8305054, 3.1252077, 1.4450684)
		collision_shape = box
	collision.shape = collision_shape
	collision.transform = collision_transform


func _refresh_visual() -> void:
	if not is_inside_tree():
		return
	if Engine.is_editor_hint() and not _can_editor_modify_preview():
		return
	var root := get_node_or_null("ModelRoot") as Node3D
	if root == null:
		root = Node3D.new()
		root.name = "ModelRoot"
		add_child(root)
		_set_editor_owner(root)
	for child in root.get_children():
		root.remove_child(child)
		child.queue_free()
	if visual_scene == null:
		return
	var visual := visual_scene.instantiate()
	root.add_child(visual)
	_set_editor_owner(visual)
	if visual is Node3D:
		(visual as Node3D).transform = visual_transform


func _set_editor_owner(node: Node) -> void:
	if not Engine.is_editor_hint() or node == null:
		return
	var tree := get_tree()
	if tree != null and tree.edited_scene_root != null:
		node.owner = tree.edited_scene_root


func _can_editor_modify_preview() -> bool:
	if not Engine.is_editor_hint():
		return true
	var tree := get_tree()
	var edited_root := tree.edited_scene_root if tree != null else null
	return edited_root == self
