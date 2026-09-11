extends RefCounted
## Shared authored socket + inverse item-grip mounting; no equipment state.
const DEFAULT_GRIP_SOCKET_PROFILE = preload("res://features/actors/resources/humanoid_grip_socket_profiles/default.tres")
const HUMANOID_GRIP_SOCKET_MARKER_SCRIPT = preload("res://features/actors/projection/humanoid/humanoid_grip_socket_marker.gd")
const BONE_EQUIPMENT_SLOTS := {"weapon": "hand_r", "offhand": "hand_l"}
var grip_socket_profile: Resource
var body_archetype: Resource
var show_grip_socket_markers := false

func _init(profile: Resource = null, archetype: Resource = null, show_markers := false) -> void:
	grip_socket_profile = profile
	body_archetype = archetype
	show_grip_socket_markers = show_markers

func _get_grip_socket_profile() -> Resource:
	return grip_socket_profile if grip_socket_profile != null else DEFAULT_GRIP_SOCKET_PROFILE

func mount(skeleton: Skeleton3D, slot_name: String, item: ItemDefinition) -> Node3D:
	if item == null:
		return null
	var equipped_scene := item.get_equipped_scene_for_body_archetype(body_archetype)
	if equipped_scene == null:
		return null
	var instance := equipped_scene.instantiate()
	if not (instance is Node3D):
		instance.queue_free()
		return null
	var socket_id := _get_equipment_socket_id(item, slot_name)
	var fallback_bone_name := _get_equipment_attachment_bone(item, slot_name)
	var socket := _get_or_create_humanoid_grip_socket(skeleton, socket_id, fallback_bone_name)
	if socket == null:
		instance.queue_free()
		return null
	var slot_visual := Node3D.new()
	slot_visual.name = _get_bone_equipment_visual_name(slot_name)
	socket.add_child(slot_visual)
	var model_root := instance as Node3D
	model_root.transform = item.equipped_transform * _get_item_grip_transform(model_root, item, slot_name).affine_inverse()
	slot_visual.add_child(model_root)
	return slot_visual


func _get_bone_equipment_visual_name(slot_name: String) -> String:
	return "Equipped%sVisual" % slot_name.capitalize()


func _get_or_create_humanoid_grip_socket(skeleton: Skeleton3D, socket_id: String, fallback_bone_name := "") -> Node3D:
	if socket_id.is_empty():
		return null
	var socket_name := _get_equipment_socket_node_name(socket_id)
	var attachment_name := _get_humanoid_grip_socket_attachment_name(socket_id)
	var bone_name := _get_equipment_socket_bone_name(socket_id)
	if bone_name.is_empty():
		bone_name = fallback_bone_name
	var attachment := skeleton.get_node_or_null(attachment_name) as BoneAttachment3D
	if attachment == null:
		if bone_name.is_empty() or skeleton.find_bone(bone_name) < 0:
			return null
		attachment = BoneAttachment3D.new()
		attachment.name = attachment_name
		attachment.bone_name = bone_name
		skeleton.add_child(attachment)
	elif not bone_name.is_empty() and skeleton.find_bone(bone_name) >= 0 and attachment.bone_name != bone_name:
		attachment.bone_name = bone_name
	var socket := attachment.get_node_or_null(socket_name) as Node3D
	if socket == null:
		socket = HUMANOID_GRIP_SOCKET_MARKER_SCRIPT.new() as Node3D
		socket.name = socket_name
		attachment.add_child(socket)
	if socket.get_script() == HUMANOID_GRIP_SOCKET_MARKER_SCRIPT:
		socket.set("socket_id", socket_id)
		socket.set("show_runtime_visual", show_grip_socket_markers)
	socket.transform = _get_equipment_socket_transform(socket_id)
	return socket


func _get_humanoid_grip_socket_attachment_name(socket_id: String) -> String:
	return "%sAttachment" % _get_equipment_socket_node_name(socket_id)


func _get_equipment_socket_transform(socket_id: String) -> Transform3D:
	var socket_profile := _get_grip_socket_profile()
	if socket_profile != null and socket_profile.has_method("get_socket_transform"):
		return socket_profile.get_socket_transform(socket_id)
	return Transform3D.IDENTITY


func _get_equipment_socket_node_name(socket_id: String) -> String:
	var socket_profile := _get_grip_socket_profile()
	if socket_profile != null and socket_profile.has_method("get_socket_node_name"):
		return socket_profile.get_socket_node_name(socket_id)
	return "GripSocket"


func _get_equipment_socket_bone_name(socket_id: String) -> String:
	var socket_profile := _get_grip_socket_profile()
	if socket_profile != null and socket_profile.has_method("get_socket_bone_name"):
		return socket_profile.get_socket_bone_name(socket_id)
	return ""


func _get_equipment_socket_id(item: ItemDefinition, slot_name: String) -> String:
	if item != null and item.grip_profile != null:
		var socket_id := str(item.grip_profile.get("primary_socket_id"))
		if not socket_id.is_empty():
			return socket_id
	match slot_name:
		"weapon":
			return "right_hand_one_hand"
		"offhand":
			return "left_hand_shield"
	return ""


func _get_item_grip_transform(model_root: Node3D, item: ItemDefinition, slot_name: String) -> Transform3D:
	var marker_name := _get_item_grip_marker_name(item, slot_name)
	if marker_name.is_empty():
		return Transform3D.IDENTITY
	var marker := _find_node3d_by_name(model_root, marker_name)
	if marker == null:
		push_warning("Missing %s marker in %s; using wrapper root as grip point." % [marker_name, item.display_name])
		return Transform3D.IDENTITY
	return _get_node3d_transform_relative_to_root(model_root, marker)


func _get_item_grip_marker_name(item: ItemDefinition, _slot_name: String) -> String:
	if item != null and item.grip_profile != null:
		var marker_name := str(item.grip_profile.get("primary_grip_marker"))
		if not marker_name.is_empty():
			return marker_name
	return "GripPoint_Primary"


func _find_node3d_by_name(root: Node, node_name: String) -> Node3D:
	if root is Node3D and root.name == node_name:
		return root as Node3D
	for child in root.get_children():
		var found := _find_node3d_by_name(child, node_name)
		if found != null:
			return found
	return null


func _get_node3d_transform_relative_to_root(root: Node3D, target: Node3D) -> Transform3D:
	if target == root:
		return Transform3D.IDENTITY
	var current: Node = target
	var result := Transform3D.IDENTITY
	while current != null and current != root:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


func _get_equipment_attachment_bone(item: ItemDefinition, slot_name: String) -> String:
	if item != null and item.grip_profile != null:
		var primary_bone := str(item.grip_profile.get("primary_bone"))
		if not primary_bone.is_empty():
			return primary_bone
	return str(BONE_EQUIPMENT_SLOTS.get(slot_name, ""))
