@tool
extends Node3D

class_name HumanoidGripSocketCalibrator

const DEFAULT_GRIP_SOCKET_PROFILE = preload("res://resources/humanoid_grip_socket_profiles/default.tres")
const HUMAN_MALE_BODY_ARCHETYPE = preload("res://resources/character_body_archetypes/human_male.tres")
const PREVIEW_ITEMS := [
	preload("res://resources/items/iron_sword.tres"),
	preload("res://resources/items/iron_axe.tres"),
	preload("res://resources/items/iron_dagger.tres"),
	preload("res://resources/items/round_shield.tres"),
]
const RIGHT_SOCKET_ID := "right_hand_one_hand"
const LEFT_SOCKET_ID := "left_hand_shield"
const PREVIEW_ITEM_NAME := "PreviewItem"
const PREVIEW_HUMANOID_PATH := NodePath("PreviewHumanoid")
const RIGHT_GRIP_GUIDE_PATH := NodePath("GripHandles/RightHandBoneGuide")
const LEFT_GRIP_GUIDE_PATH := NodePath("GripHandles/LeftHandBoneGuide")
const RIGHT_GRIP_PATH := NodePath("GripHandles/RightHandBoneGuide/RightHandGrip")
const LEFT_GRIP_PATH := NodePath("GripHandles/LeftHandBoneGuide/LeftHandGrip")
const STATUS_LABEL_PATH := NodePath("StatusLabel")
const RIGHT_BONE_NAME := "hand_r"
const LEFT_BONE_NAME := "hand_l"
const RIGHT_PROFILE_PROPERTY := "right_hand_one_hand"
const LEFT_PROFILE_PROPERTY := "left_hand_shield"
const SKELETON_OVERLAY_NAME := "__SkeletonOverlay"
const SKELETON_COLOR := Color(0.55, 0.85, 1.0, 0.82)
const RIGHT_HAND_COLOR := Color(1.0, 0.9, 0.2, 1.0)
const LEFT_HAND_COLOR := Color(0.2, 1.0, 0.95, 1.0)
const JOINT_COLOR := Color(0.85, 0.95, 1.0, 0.92)

@export var preview_body_archetype: Resource = HUMAN_MALE_BODY_ARCHETYPE:
	set(value):
		preview_body_archetype = value
		_rebuild_preview_humanoid_deferred()
@export var socket_profile: Resource:
	set(value):
		socket_profile = value
		_load_grips_from_profile_deferred()
@export_enum("RightHandGrip", "LeftHandGrip") var preview_socket := "RightHandGrip":
	set(value):
		preview_socket = value
		_rebuild_preview_item_deferred()
@export_range(0, 3, 1) var preview_item_index := 0:
	set(value):
		preview_item_index = clampi(value, 0, PREVIEW_ITEMS.size() - 1)
		_rebuild_preview_item_deferred()
@export var live_apply_to_profile := true
@export var profile_dirty := false
@export var show_skeleton_overlay := true:
	set(value):
		show_skeleton_overlay = value
		_rebuild_skeleton_overlay_deferred()
@export var load_grips_from_profile := false:
	set(value):
		load_grips_from_profile = false
		if value:
			_load_grips_from_profile()
@export var save_grips_to_profile := false:
	set(value):
		save_grips_to_profile = false
		if value:
			_save_grips_to_profile()
@export var rebuild_preview_item := false:
	set(value):
		rebuild_preview_item = false
		if value:
			_rebuild_preview_item()
@export_multiline var last_status := "Ready. Move RightHandGrip/LeftHandGrip, then toggle save_grips_to_profile.":
	set(value):
		last_status = value
		_update_status_label_deferred()

var _last_right_grip_transform := Transform3D.IDENTITY
var _last_left_grip_transform := Transform3D.IDENTITY
var _has_grip_snapshot := false


func _ready() -> void:
	set_process(Engine.is_editor_hint())
	call_deferred("_rebuild_preview_humanoid")
	call_deferred("_sync_preview")
	call_deferred("_rebuild_preview_item")
	call_deferred("_rebuild_skeleton_overlay")
	call_deferred("_capture_grip_snapshot")
	call_deferred("_update_status_label")


func _process(_delta: float) -> void:
	_sync_grip_guides_to_bones()
	_track_grip_changes()


func _sync_preview() -> void:
	_sync_grip_guides_to_bones()
	_prepare_grip_marker(RIGHT_GRIP_PATH, RIGHT_SOCKET_ID)
	_prepare_grip_marker(LEFT_GRIP_PATH, LEFT_SOCKET_ID)
	_rebuild_skeleton_overlay()


func _rebuild_preview_humanoid_deferred() -> void:
	if not is_inside_tree():
		return
	call_deferred("_rebuild_preview_humanoid")


func _rebuild_preview_humanoid() -> void:
	var preview_root := get_node_or_null(PREVIEW_HUMANOID_PATH) as Node3D
	if preview_root == null:
		return
	for child in preview_root.get_children():
		preview_root.remove_child(child)
		child.free()
	var visual_scene := _get_preview_visual_scene()
	if visual_scene == null:
		return
	var instance := visual_scene.instantiate()
	if not (instance is Node3D):
		instance.queue_free()
		return
	preview_root.add_child(instance)
	_sync_preview()
	_load_grips_from_profile()


func _sync_grip_guides_to_bones() -> void:
	_sync_grip_guide_to_bone(RIGHT_GRIP_GUIDE_PATH, RIGHT_SOCKET_ID)
	_sync_grip_guide_to_bone(LEFT_GRIP_GUIDE_PATH, LEFT_SOCKET_ID)


func _sync_grip_guide_to_bone(guide_path: NodePath, socket_id: String) -> void:
	if not is_inside_tree():
		return
	var guide := get_node_or_null(guide_path) as Node3D
	var skeleton := _get_preview_skeleton()
	if guide == null or skeleton == null or not guide.is_inside_tree() or not skeleton.is_inside_tree():
		return
	var bone_name := _get_socket_bone_name(socket_id)
	var bone_index := skeleton.find_bone(bone_name)
	if bone_index < 0:
		return
	guide.global_transform = skeleton.global_transform * skeleton.get_bone_global_rest(bone_index)


func _prepare_grip_marker(grip_path: NodePath, socket_id: String) -> void:
	var grip := get_node_or_null(grip_path)
	if grip == null:
		return
	grip.set("socket_id", socket_id)
	grip.set("show_runtime_visual", true)
	grip.set("axis_length", 0.36)
	grip.set("center_radius", 0.035)


func _load_grips_from_profile() -> void:
	var right_grip := get_node_or_null(RIGHT_GRIP_PATH) as Node3D
	var left_grip := get_node_or_null(LEFT_GRIP_PATH) as Node3D
	if right_grip != null:
		right_grip.transform = _get_profile_transform(RIGHT_PROFILE_PROPERTY)
	if left_grip != null:
		left_grip.transform = _get_profile_transform(LEFT_PROFILE_PROPERTY)
	profile_dirty = false
	_capture_grip_snapshot()
	_rebuild_preview_item()
	_set_status("Loaded hand grip transforms from %s." % _get_profile_path())


func _load_grips_from_profile_deferred() -> void:
	if not is_inside_tree():
		return
	call_deferred("_load_grips_from_profile")


func _save_grips_to_profile() -> void:
	var active_profile := _get_socket_profile()
	if active_profile == null:
		push_warning("Grip socket calibrator has no writable socket profile.")
		_set_status("Save failed: no socket_profile resource assigned.")
		return
	_apply_grips_to_profile_memory()
	var save_path := active_profile.resource_path
	if save_path.is_empty():
		push_warning("Grip socket profile has no resource path; cannot save socket calibration.")
		_set_status("Save failed: socket profile has no resource path.")
		return
	var save_error := ResourceSaver.save(active_profile, save_path)
	if save_error != OK:
		push_error("Failed to save grip socket profile '%s' with error %s." % [save_path, save_error])
		_set_status("Save failed: ResourceSaver error %s." % save_error)
		return
	profile_dirty = false
	_capture_grip_snapshot()
	_set_status("Saved %s and %s to %s." % [RIGHT_PROFILE_PROPERTY, LEFT_PROFILE_PROPERTY, save_path])
	print(last_status)


func _track_grip_changes() -> void:
	var right_grip := get_node_or_null(RIGHT_GRIP_PATH) as Node3D
	var left_grip := get_node_or_null(LEFT_GRIP_PATH) as Node3D
	if right_grip == null or left_grip == null:
		return
	if not _has_grip_snapshot:
		_capture_grip_snapshot()
		return
	if right_grip.transform.is_equal_approx(_last_right_grip_transform) and left_grip.transform.is_equal_approx(_last_left_grip_transform):
		return
	_capture_grip_snapshot()
	profile_dirty = true
	if live_apply_to_profile:
		_apply_grips_to_profile_memory()
		_set_status("Preview applied to profile in memory. Toggle save_grips_to_profile to write %s." % _get_profile_path())
	else:
		_set_status("Grip handles changed. Toggle save_grips_to_profile to write %s." % _get_profile_path())


func _capture_grip_snapshot() -> void:
	var right_grip := get_node_or_null(RIGHT_GRIP_PATH) as Node3D
	var left_grip := get_node_or_null(LEFT_GRIP_PATH) as Node3D
	if right_grip == null or left_grip == null:
		return
	_last_right_grip_transform = right_grip.transform
	_last_left_grip_transform = left_grip.transform
	_has_grip_snapshot = true


func _apply_grips_to_profile_memory() -> void:
	var active_profile := _get_socket_profile()
	if active_profile == null:
		return
	var right_grip := get_node_or_null(RIGHT_GRIP_PATH) as Node3D
	var left_grip := get_node_or_null(LEFT_GRIP_PATH) as Node3D
	if right_grip != null:
		active_profile.set(RIGHT_PROFILE_PROPERTY, right_grip.transform)
	if left_grip != null:
		active_profile.set(LEFT_PROFILE_PROPERTY, left_grip.transform)


func _rebuild_preview_item_deferred() -> void:
	if not is_inside_tree():
		return
	call_deferred("_rebuild_preview_item")


func _rebuild_preview_item() -> void:
	_clear_preview_items()
	var grip := _get_preview_grip()
	if grip == null:
		return
	var item := _get_preview_item()
	if item == null:
		return
	var equipped_scene := item.get("equipped_scene") as PackedScene
	if equipped_scene == null:
		return
	var instance := equipped_scene.instantiate()
	if not (instance is Node3D):
		instance.queue_free()
		return
	var item_root := Node3D.new()
	item_root.name = PREVIEW_ITEM_NAME
	grip.add_child(item_root)
	var model_root := instance as Node3D
	model_root.transform = _get_item_equipped_transform(item) * _get_item_grip_transform(model_root, item).affine_inverse()
	item_root.add_child(model_root)


func _clear_preview_items() -> void:
	for grip_path in [RIGHT_GRIP_PATH, LEFT_GRIP_PATH]:
		var grip := get_node_or_null(grip_path)
		if grip == null:
			continue
		var existing := grip.get_node_or_null(PREVIEW_ITEM_NAME)
		if existing != null:
			grip.remove_child(existing)
			existing.free()


func _rebuild_skeleton_overlay_deferred() -> void:
	if not is_inside_tree():
		return
	call_deferred("_rebuild_skeleton_overlay")


func _rebuild_skeleton_overlay() -> void:
	if not is_inside_tree():
		return
	_clear_skeleton_overlay()
	if not show_skeleton_overlay:
		return
	var skeleton := _get_preview_skeleton()
	if skeleton == null or not skeleton.is_inside_tree():
		return
	var overlay := Node3D.new()
	overlay.name = SKELETON_OVERLAY_NAME
	add_child(overlay)
	_add_skeleton_lines(overlay, skeleton)
	_add_hand_highlights(overlay, skeleton)


func _clear_skeleton_overlay() -> void:
	var existing := get_node_or_null(SKELETON_OVERLAY_NAME)
	if existing != null:
		remove_child(existing)
		existing.free()


func _add_skeleton_lines(parent: Node3D, skeleton: Skeleton3D) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for bone_index in skeleton.get_bone_count():
		var parent_index := skeleton.get_bone_parent(bone_index)
		if parent_index < 0:
			continue
		var color := _get_bone_color(skeleton, bone_index)
		_add_line_vertices(mesh, _get_bone_local_rest_position(skeleton, parent_index), _get_bone_local_rest_position(skeleton, bone_index), color)
	mesh.surface_end()
	_add_mesh_instance(parent, mesh, _make_unshaded_material(true, SKELETON_COLOR))


func _add_hand_highlights(parent: Node3D, skeleton: Skeleton3D) -> void:
	_add_bone_joint(parent, skeleton, skeleton.find_bone("hand_r"), RIGHT_HAND_COLOR, 0.045)
	_add_bone_joint(parent, skeleton, skeleton.find_bone("hand_l"), LEFT_HAND_COLOR, 0.045)
	for bone_index in skeleton.get_bone_count():
		if bone_index == skeleton.find_bone("hand_r") or bone_index == skeleton.find_bone("hand_l"):
			continue
		_add_bone_joint(parent, skeleton, bone_index, JOINT_COLOR, 0.012)


func _add_bone_joint(parent: Node3D, skeleton: Skeleton3D, bone_index: int, color: Color, radius: float) -> void:
	if bone_index < 0:
		return
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = sphere
	mesh_instance.material_override = _make_unshaded_material(false, color)
	mesh_instance.position = _get_bone_local_rest_position(skeleton, bone_index)
	parent.add_child(mesh_instance)


func _get_bone_color(skeleton: Skeleton3D, bone_index: int) -> Color:
	var bone_name := skeleton.get_bone_name(bone_index)
	if bone_name == "hand_r" or _bone_has_parent(skeleton, bone_index, "hand_r"):
		return RIGHT_HAND_COLOR
	if bone_name == "hand_l" or _bone_has_parent(skeleton, bone_index, "hand_l"):
		return LEFT_HAND_COLOR
	return SKELETON_COLOR


func _bone_has_parent(skeleton: Skeleton3D, bone_index: int, parent_bone_name: String) -> bool:
	var current := skeleton.get_bone_parent(bone_index)
	while current >= 0:
		if skeleton.get_bone_name(current) == parent_bone_name:
			return true
		current = skeleton.get_bone_parent(current)
	return false


func _get_bone_local_rest_position(skeleton: Skeleton3D, bone_index: int) -> Vector3:
	var bone_global := skeleton.global_transform * skeleton.get_bone_global_rest(bone_index)
	return to_local(bone_global.origin)


func _get_preview_grip() -> Node3D:
	if preview_socket == "LeftHandGrip":
		return get_node_or_null(LEFT_GRIP_PATH) as Node3D
	return get_node_or_null(RIGHT_GRIP_PATH) as Node3D


func _get_preview_item() -> Resource:
	if preview_item_index < 0 or preview_item_index >= PREVIEW_ITEMS.size():
		return null
	return PREVIEW_ITEMS[preview_item_index]


func _get_preview_skeleton() -> Skeleton3D:
	var preview_humanoid := get_node_or_null(PREVIEW_HUMANOID_PATH)
	if preview_humanoid == null:
		return null
	return _find_skeleton(preview_humanoid)


func _get_preview_visual_scene() -> PackedScene:
	var body := _get_preview_body_archetype()
	if body != null:
		var visual_scene := body.get("visual_scene") as PackedScene
		if visual_scene != null:
			return visual_scene
	return HUMAN_MALE_BODY_ARCHETYPE.get("visual_scene") as PackedScene


func _get_preview_body_archetype() -> Resource:
	if preview_body_archetype != null:
		return preview_body_archetype
	return HUMAN_MALE_BODY_ARCHETYPE


func _get_socket_profile() -> Resource:
	if socket_profile != null:
		return socket_profile
	var body := _get_preview_body_archetype()
	if body != null:
		var body_profile := body.get("grip_socket_profile") as Resource
		if body_profile != null:
			return body_profile
	return DEFAULT_GRIP_SOCKET_PROFILE


func _get_socket_bone_name(socket_id: String) -> String:
	match socket_id:
		RIGHT_SOCKET_ID:
			return RIGHT_BONE_NAME
		LEFT_SOCKET_ID:
			return LEFT_BONE_NAME
	return ""


func _get_profile_transform(property_name: String) -> Transform3D:
	var active_profile := _get_socket_profile()
	if active_profile == null:
		return Transform3D.IDENTITY
	var value = active_profile.get(property_name)
	if value is Transform3D:
		return value
	return Transform3D.IDENTITY


func _get_profile_path() -> String:
	var active_profile := _get_socket_profile()
	if active_profile == null or active_profile.resource_path.is_empty():
		return "<unsaved profile>"
	return active_profile.resource_path


func _set_status(message: String) -> void:
	last_status = message


func _update_status_label_deferred() -> void:
	if not is_inside_tree():
		return
	call_deferred("_update_status_label")


func _update_status_label() -> void:
	var status_label := get_node_or_null(STATUS_LABEL_PATH) as Label3D
	if status_label == null:
		return
	var dirty_text := ""
	if profile_dirty:
		dirty_text = "\nProfile dirty: toggle save_grips_to_profile before testing runtime."
	status_label.text = last_status + dirty_text


func _get_item_equipped_transform(item: Resource) -> Transform3D:
	var value = item.get("equipped_transform")
	if value is Transform3D:
		return value
	return Transform3D.IDENTITY


func _get_item_grip_transform(model_root: Node3D, item: Resource) -> Transform3D:
	var marker_name := _get_item_grip_marker_name(item)
	if marker_name.is_empty():
		return Transform3D.IDENTITY
	var marker := _find_node3d_by_name(model_root, marker_name)
	if marker == null:
		return Transform3D.IDENTITY
	return _get_node3d_transform_relative_to_root(model_root, marker)


func _get_item_grip_marker_name(item: Resource) -> String:
	var grip_profile = item.get("grip_profile")
	if grip_profile != null:
		var marker_name := str(grip_profile.get("primary_grip_marker"))
		if not marker_name.is_empty():
			return marker_name
	return "GripPoint_Primary"


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var skeleton := _find_skeleton(child)
		if skeleton != null:
			return skeleton
	return null


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


func _add_line_vertices(mesh: ImmediateMesh, from_position: Vector3, to_position: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(from_position)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(to_position)


func _add_mesh_instance(parent: Node3D, mesh: Mesh, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)


func _make_unshaded_material(use_vertex_color: bool, color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = use_vertex_color
	material.no_depth_test = true
	if not use_vertex_color:
		material.albedo_color = color
	return material
