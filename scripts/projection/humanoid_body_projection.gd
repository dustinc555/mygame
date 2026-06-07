extends "res://scripts/projection/body_projection_adapter.gd"

class_name HumanoidBodyProjection

const HUMAN_RACE := preload("res://resources/character_races/human.tres")
const HUMAN_MALE_BODY := preload("res://resources/character_body_archetypes/human_male.tres")
const UAL1_ANIMATION_SOURCE_SCENE := preload("res://assets/vendor/quaternius/universal_animation_library_1_pro/UAL1_Pro.glb")
const DEFAULT_GRIP_SOCKET_PROFILE := preload("res://resources/humanoid_grip_socket_profiles/default.tres")

const WORLD_VISUAL_NODE_NAME := "BodyVisual"
const PORTRAIT_SOURCE_NODE_NAME := "PortraitVisualSource"
const CHARACTER_VISUAL_NODE_NAME := "CharacterVisual"
const CHARACTER_ANIMATION_PLAYER_NAME := "CharacterAnimationPlayer"
const PORTRAIT_CHARACTER_VISUAL_YAW_OFFSET := PI
const IDLE_ANIMATION_NAME := "Idle"
const WALK_ANIMATION_NAME := "Walk"
const CROUCH_IDLE_ANIMATION_NAME := "Crouch_Idle"
const CROUCH_WALK_ANIMATION_NAME := "Crouch_Fwd"
const JOG_ANIMATION_NAME := "Jog_Fwd"
const IDLE_SAMPLE_SECONDS := 0.45
const EQUIPMENT_VISUAL_META := "projection_equipment_visual"
const BONE_EQUIPMENT_SLOTS := {
	"weapon": "hand_r",
	"offhand": "hand_l",
}

var _body_archetype: Resource
var _body_archetype_path := ""
var _body_visual: Node3D
var _skeleton: Skeleton3D
var _equipment_root: Node3D
var _label: Label3D
var _equipment_signature := ""
var _character_animation_player: AnimationPlayer
var _current_world_animation := ""

var _portrait_source: Node3D
var _portrait_character_visual: Node3D
var _portrait_skeleton: Skeleton3D
var _portrait_animation_player: AnimationPlayer
var _portrait_equipment_signature := ""


func apply_projection_snapshot(record: Dictionary, equipment_slots: Dictionary, combat_state: Dictionary = {}) -> void:
	var body_archetype := _body_archetype_from_record(record)
	_ensure_body_visual(body_archetype)
	_ensure_portrait_source(body_archetype)
	_apply_label(record)
	_apply_life_state(record, combat_state)
	_sync_equipment(equipment_slots)
	_sync_portrait_equipment(equipment_slots)
	_apply_locomotion_state(record)


func get_body_adapter_id() -> String:
	return "humanoid"


func get_portrait_source() -> Node:
	return _portrait_source if _portrait_source != null and is_instance_valid(_portrait_source) else self


func get_projection_debug_state() -> Dictionary:
	return {
		"body_adapter_id": get_body_adapter_id(),
		"body_archetype": _body_archetype_path,
		"world_visual_ready": _body_visual != null and _body_visual.name == WORLD_VISUAL_NODE_NAME,
		"world_skeleton_ready": _skeleton != null,
		"world_idle_animation_ready": _character_animation_player != null and _character_animation_player.has_animation(IDLE_ANIMATION_NAME),
		"world_animation": _current_world_animation,
		"portrait_source_ready": _portrait_source != null,
		"portrait_character_visual_ready": _portrait_character_visual != null and _portrait_character_visual.name == CHARACTER_VISUAL_NODE_NAME,
		"portrait_skeleton_ready": _portrait_skeleton != null,
		"portrait_idle_animation_ready": _portrait_animation_player != null and _portrait_animation_player.has_animation(IDLE_ANIMATION_NAME),
		"attached_item_paths": _attached_item_paths(),
	}


func _body_archetype_from_record(record: Dictionary) -> Resource:
	var appearance: Dictionary = record.get("appearance", {}) if record.get("appearance", {}) is Dictionary else {}
	var body_path := str(appearance.get("body_archetype", "")).strip_edges()
	var body := load(body_path) as Resource if not body_path.is_empty() else null
	if body != null:
		return body
	var race_path := str(appearance.get("character_race", "")).strip_edges()
	var race := load(race_path) as Resource if not race_path.is_empty() else null
	var visual_body_type := int(appearance.get("visual_body_type", 2))
	if race != null:
		var property_name := "default_female_archetype" if visual_body_type == 3 else "default_male_archetype"
		body = race.get(property_name) as Resource
		if body != null:
			return body
	return HUMAN_MALE_BODY


func _ensure_body_visual(body_archetype: Resource) -> void:
	var target_path := _resource_path(body_archetype)
	if _body_visual != null and target_path == _body_archetype_path:
		return
	_clear_children()
	_body_archetype = body_archetype
	_body_archetype_path = target_path
	_body_visual = Node3D.new()
	_body_visual.name = WORLD_VISUAL_NODE_NAME
	add_child(_body_visual)
	var model_root := _instantiate_body_model(body_archetype)
	if model_root != null:
		_body_visual.add_child(model_root)
		_character_animation_player = _setup_character_animation(model_root)
		_play_idle_pose(_character_animation_player)
		_skeleton = _find_skeleton(model_root)
	_equipment_root = Node3D.new()
	_equipment_root.name = "EquipmentProjection"
	add_child(_equipment_root)
	_label = Label3D.new()
	_label.name = "NameLabel"
	_label.position = Vector3(0.0, 2.05, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 22
	add_child(_label)
	_equipment_signature = ""
	_portrait_equipment_signature = ""
	_current_world_animation = ""


func _ensure_portrait_source(body_archetype: Resource) -> void:
	if _portrait_source != null and is_instance_valid(_portrait_source):
		return
	_portrait_source = Node3D.new()
	_portrait_source.name = PORTRAIT_SOURCE_NODE_NAME
	_portrait_source.visible = false
	add_child(_portrait_source)
	_portrait_character_visual = Node3D.new()
	_portrait_character_visual.name = CHARACTER_VISUAL_NODE_NAME
	_portrait_source.add_child(_portrait_character_visual)
	var model_root := _instantiate_body_model(body_archetype)
	if model_root == null:
		return
	model_root.rotation.y = PORTRAIT_CHARACTER_VISUAL_YAW_OFFSET
	_portrait_character_visual.add_child(model_root)
	_portrait_animation_player = _setup_character_animation(model_root)
	_play_idle_pose(_portrait_animation_player)
	_portrait_skeleton = _find_skeleton(model_root)


func _instantiate_body_model(body_archetype: Resource) -> Node3D:
	var visual_scene: PackedScene
	if body_archetype != null:
		visual_scene = body_archetype.get("visual_scene") as PackedScene
	if visual_scene == null:
		return null
	var instance := visual_scene.instantiate()
	if instance is Node3D:
		return instance as Node3D
	if instance != null:
		instance.queue_free()
	return null


func _clear_children() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_body_visual = null
	_equipment_root = null
	_skeleton = null
	_label = null
	_character_animation_player = null
	_portrait_source = null
	_portrait_character_visual = null
	_portrait_skeleton = null
	_portrait_animation_player = null


func _apply_label(record: Dictionary) -> void:
	if _label != null:
		_label.text = str(record.get("member_name", record.get("actor_id", "Actor")))


func _apply_life_state(record: Dictionary, _combat_state: Dictionary) -> void:
	if _label != null:
		_label.modulate = Color(0.65, 0.65, 0.65, 1.0) if int(record.get("life_state", 0)) != 0 else Color.WHITE


func _apply_locomotion_state(record: Dictionary) -> void:
	if _character_animation_player == null:
		return
	if int(record.get("life_state", 0)) != 0:
		_play_world_animation(IDLE_ANIMATION_NAME)
		return
	var locomotion_state: Dictionary = record.get("locomotion_state", {}) if record.get("locomotion_state", {}) is Dictionary else {}
	var animation_state := str(locomotion_state.get("animation_state", ""))
	if animation_state.is_empty():
		var movement_mode := int(record.get("movement_mode", 0))
		animation_state = "sneak_idle" if movement_mode == 2 else "idle"
	match animation_state:
		"run":
			_play_world_animation(JOG_ANIMATION_NAME, _animation_speed_scale(float(locomotion_state.get("horizontal_speed", 0.0)), float(locomotion_state.get("speed", 0.0)), 0.9, 1.35))
		"sneak":
			_play_world_animation(CROUCH_WALK_ANIMATION_NAME, _animation_speed_scale(float(locomotion_state.get("horizontal_speed", 0.0)), float(locomotion_state.get("speed", 0.0)), 0.85, 1.15))
		"sneak_idle":
			_play_world_animation(CROUCH_IDLE_ANIMATION_NAME)
		"walk":
			_play_world_animation(WALK_ANIMATION_NAME, _animation_speed_scale(float(locomotion_state.get("horizontal_speed", 0.0)), float(locomotion_state.get("speed", 0.0)), 0.85, 1.25))
		_:
			_play_world_animation(IDLE_ANIMATION_NAME)


func _play_world_animation(animation_name: String, speed_scale := 1.0) -> void:
	if _character_animation_player == null or not _character_animation_player.has_animation(animation_name):
		return
	_character_animation_player.speed_scale = maxf(speed_scale, 0.01)
	if _current_world_animation == animation_name and _character_animation_player.is_playing():
		return
	_current_world_animation = animation_name
	_character_animation_player.play(animation_name, 0.12)
	_character_animation_player.advance(0.0)


func _animation_speed_scale(horizontal_speed: float, reference_speed: float, min_scale: float, max_scale: float) -> float:
	var ratio := clampf(horizontal_speed / maxf(reference_speed, 0.001), 0.0, 1.0)
	return lerpf(min_scale, max_scale, ratio)


func _sync_equipment(equipment_slots: Dictionary) -> void:
	if _equipment_root == null:
		return
	var signature := _equipment_signature_for(equipment_slots)
	if signature == _equipment_signature:
		return
	_equipment_signature = signature
	_clear_equipment_children(_equipment_root)
	_clear_tagged_equipment_visuals(_body_visual)
	var slot_names := equipment_slots.keys()
	slot_names.sort()
	for slot_name_value in slot_names:
		var slot_name := str(slot_name_value)
		var item := load(str(equipment_slots[slot_name_value])) as Resource
		if item == null:
			continue
		if BONE_EQUIPMENT_SLOTS.has(slot_name):
			_attach_bone_item(_skeleton, slot_name, item)
		else:
			_attach_wearable(_equipment_root, _skeleton, slot_name, item, 0.0)


func _sync_portrait_equipment(equipment_slots: Dictionary) -> void:
	if _portrait_character_visual == null:
		return
	var signature := _equipment_signature_for(equipment_slots)
	if signature == _portrait_equipment_signature:
		return
	_portrait_equipment_signature = signature
	_clear_tagged_equipment_visuals(_portrait_character_visual)
	var slot_names := equipment_slots.keys()
	slot_names.sort()
	for slot_name_value in slot_names:
		var slot_name := str(slot_name_value)
		var item := load(str(equipment_slots[slot_name_value])) as Resource
		if item == null:
			continue
		if BONE_EQUIPMENT_SLOTS.has(slot_name):
			_attach_bone_item(_portrait_skeleton, slot_name, item)
		else:
			_attach_wearable(_portrait_character_visual, _portrait_skeleton, slot_name, item, PORTRAIT_CHARACTER_VISUAL_YAW_OFFSET)


func _setup_character_animation(model_root: Node3D) -> AnimationPlayer:
	var animation_player := AnimationPlayer.new()
	animation_player.name = CHARACTER_ANIMATION_PLAYER_NAME
	animation_player.root_node = NodePath("..")
	model_root.add_child(animation_player)
	var animation_library := AnimationLibrary.new()
	var source := UAL1_ANIMATION_SOURCE_SCENE.instantiate()
	var source_player := _find_animation_player(source)
	if source_player != null:
		_copy_animation(source_player, animation_library, IDLE_ANIMATION_NAME)
		_copy_animation(source_player, animation_library, WALK_ANIMATION_NAME)
		_copy_animation(source_player, animation_library, CROUCH_IDLE_ANIMATION_NAME)
		_copy_animation(source_player, animation_library, CROUCH_WALK_ANIMATION_NAME)
		_copy_animation(source_player, animation_library, JOG_ANIMATION_NAME)
	source.queue_free()
	if animation_library.get_animation_list().is_empty():
		animation_player.queue_free()
		return null
	animation_player.add_animation_library("", animation_library)
	return animation_player


func _copy_animation(source_player: AnimationPlayer, animation_library: AnimationLibrary, animation_name: String) -> void:
	if not source_player.has_animation(animation_name) or animation_library.has_animation(animation_name):
		return
	var source_animation := source_player.get_animation(animation_name)
	if source_animation == null:
		return
	animation_library.add_animation(animation_name, source_animation.duplicate(true) as Animation)


func _play_idle_pose(animation_player: AnimationPlayer) -> void:
	if animation_player == null or not animation_player.has_animation(IDLE_ANIMATION_NAME):
		return
	animation_player.play(IDLE_ANIMATION_NAME)
	animation_player.seek(IDLE_SAMPLE_SECONDS, true)
	animation_player.advance(0.0)


func _attach_wearable(target_root: Node3D, target_skeleton: Skeleton3D, slot_name: String, item: Resource, visual_yaw_offset: float) -> void:
	if target_root == null or item == null:
		return
	var equipment_visual := _equipment_visual_for_item(item)
	var visual_scene := _equipped_scene_for_item(item)
	if visual_scene == null:
		return
	var instance := visual_scene.instantiate()
	if not (instance is Node3D):
		if instance != null:
			instance.queue_free()
		return
	var source_root := instance as Node3D
	source_root.name = "Equipped_%s" % slot_name.capitalize()
	source_root.set_meta("item_definition_path", _resource_path(item))
	var visual_transform := _equipment_visual_transform(item, equipment_visual)
	if target_skeleton != null and _setup_shared_skeleton_clothing_visual(target_root, target_skeleton, source_root, visual_transform, visual_yaw_offset):
		source_root.free()
		return
	_setup_legacy_clothing_visual(target_root, source_root, visual_transform, visual_yaw_offset)


func _setup_shared_skeleton_clothing_visual(target_root: Node3D, target_skeleton: Skeleton3D, source_root: Node3D, visual_transform: Transform3D, visual_yaw_offset: float) -> bool:
	var source_meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(source_root, source_meshes)
	if source_meshes.is_empty():
		return false
	var slot_root := Node3D.new()
	slot_root.name = source_root.name
	slot_root.set_meta(EQUIPMENT_VISUAL_META, true)
	if source_root.has_meta("item_definition_path"):
		slot_root.set_meta("item_definition_path", source_root.get_meta("item_definition_path"))
	slot_root.transform = Transform3D(Basis(Vector3.UP, visual_yaw_offset), Vector3.ZERO) * visual_transform
	target_root.add_child(slot_root)
	var copied_mesh_count := 0
	for source_mesh in source_meshes:
		if source_mesh == null or source_mesh.mesh == null:
			continue
		var clothing_mesh := _copy_clothing_mesh_instance(source_root, source_mesh)
		slot_root.add_child(clothing_mesh)
		clothing_mesh.skeleton = clothing_mesh.get_path_to(target_skeleton)
		copied_mesh_count += 1
	if copied_mesh_count <= 0:
		slot_root.free()
		return false
	return true


func _setup_legacy_clothing_visual(target_root: Node3D, model_root: Node3D, visual_transform: Transform3D, visual_yaw_offset: float) -> void:
	model_root.set_meta(EQUIPMENT_VISUAL_META, true)
	model_root.transform = Transform3D(Basis(Vector3.UP, visual_yaw_offset), Vector3.ZERO) * visual_transform
	target_root.add_child(model_root)
	var animation_player := _setup_character_animation(model_root)
	_play_idle_pose(animation_player)


func _collect_mesh_instances(root: Node, meshes: Array[MeshInstance3D]) -> void:
	if root is MeshInstance3D:
		meshes.append(root as MeshInstance3D)
	for child in root.get_children():
		_collect_mesh_instances(child, meshes)


func _copy_clothing_mesh_instance(source_root: Node3D, source_mesh: MeshInstance3D) -> MeshInstance3D:
	var clothing_mesh := MeshInstance3D.new()
	clothing_mesh.name = source_mesh.name
	clothing_mesh.transform = _node3d_transform_relative_to_root(source_root, source_mesh)
	clothing_mesh.mesh = source_mesh.mesh
	clothing_mesh.skin = source_mesh.skin
	clothing_mesh.visible = source_mesh.visible
	clothing_mesh.layers = source_mesh.layers
	clothing_mesh.cast_shadow = source_mesh.cast_shadow
	if source_mesh.material_override != null:
		clothing_mesh.material_override = source_mesh.material_override
	for surface_index in range(source_mesh.get_surface_override_material_count()):
		var surface_material := source_mesh.get_surface_override_material(surface_index)
		if surface_material != null:
			clothing_mesh.set_surface_override_material(surface_index, surface_material)
	for blend_shape_index in range(source_mesh.get_blend_shape_count()):
		clothing_mesh.set_blend_shape_value(blend_shape_index, source_mesh.get_blend_shape_value(blend_shape_index))
	return clothing_mesh


func _attach_bone_item(target_skeleton: Skeleton3D, slot_name: String, item: Resource) -> void:
	if target_skeleton == null or item == null:
		return
	var equipped_scene := _equipped_scene_for_item(item)
	if equipped_scene == null:
		return
	var instance := equipped_scene.instantiate()
	if not (instance is Node3D):
		if instance != null:
			instance.queue_free()
		return
	var socket_id := _equipment_socket_id(item, slot_name)
	var bone_name := _equipment_socket_bone_name(socket_id)
	if bone_name.is_empty():
		bone_name = _equipment_attachment_bone(item, slot_name)
	if bone_name.is_empty() or target_skeleton.find_bone(bone_name) < 0:
		instance.queue_free()
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = _bone_attachment_name(slot_name)
	attachment.bone_name = bone_name
	attachment.set_meta(EQUIPMENT_VISUAL_META, true)
	target_skeleton.add_child(attachment)
	var socket := Node3D.new()
	socket.name = _equipment_socket_node_name(socket_id)
	socket.transform = _equipment_socket_transform(socket_id)
	attachment.add_child(socket)
	var slot_visual := Node3D.new()
	slot_visual.name = _bone_equipment_visual_name(slot_name)
	slot_visual.set_meta("item_definition_path", _resource_path(item))
	socket.add_child(slot_visual)
	var model_root := instance as Node3D
	model_root.transform = _item_equipped_transform(item) * _item_grip_transform(model_root, item).affine_inverse()
	slot_visual.add_child(model_root)


func _equipment_visual_for_item(item: Resource) -> Resource:
	if item != null and item.has_method("get_equipment_visual_for_body_archetype"):
		var visual = item.call("get_equipment_visual_for_body_archetype", _body_archetype)
		if visual is Resource:
			return visual as Resource
	return null


func _equipped_scene_for_item(item: Resource) -> PackedScene:
	if item == null:
		return null
	if item.has_method("get_equipped_scene_for_body_archetype"):
		var scene = item.call("get_equipped_scene_for_body_archetype", _body_archetype)
		if scene is PackedScene:
			return scene as PackedScene
	return item.get("equipped_scene") as PackedScene


func _equipment_visual_transform(item: Resource, equipment_visual: Resource) -> Transform3D:
	if equipment_visual != null:
		var visual_transform = equipment_visual.get("equipped_transform")
		if visual_transform is Transform3D:
			return visual_transform
	var item_transform = item.get("equipped_transform") if item != null else null
	return item_transform if item_transform is Transform3D else Transform3D.IDENTITY


func _equipment_socket_id(item: Resource, slot_name: String) -> String:
	var grip_profile := item.get("grip_profile") as Resource if item != null else null
	if grip_profile != null:
		var socket_id := str(grip_profile.get("primary_socket_id"))
		if not socket_id.is_empty():
			return socket_id
	match slot_name:
		"weapon":
			return "right_hand_one_hand"
		"offhand":
			return "left_hand_shield"
	return ""


func _equipment_attachment_bone(item: Resource, slot_name: String) -> String:
	var grip_profile := item.get("grip_profile") as Resource if item != null else null
	if grip_profile != null:
		var primary_bone := str(grip_profile.get("primary_bone"))
		if not primary_bone.is_empty():
			return primary_bone
	return str(BONE_EQUIPMENT_SLOTS.get(slot_name, ""))


func _equipment_socket_bone_name(socket_id: String) -> String:
	var profile := _socket_profile()
	if profile != null and profile.has_method("get_socket_bone_name"):
		return str(profile.call("get_socket_bone_name", socket_id))
	return ""


func _equipment_socket_transform(socket_id: String) -> Transform3D:
	var profile := _socket_profile()
	if profile != null and profile.has_method("get_socket_transform"):
		var socket_transform = profile.call("get_socket_transform", socket_id)
		if socket_transform is Transform3D:
			return socket_transform
	return Transform3D.IDENTITY


func _equipment_socket_node_name(socket_id: String) -> String:
	var profile := _socket_profile()
	if profile != null and profile.has_method("get_socket_node_name"):
		return str(profile.call("get_socket_node_name", socket_id))
	return "GripSocket"


func _socket_profile() -> Resource:
	if _body_archetype != null:
		var profile := _body_archetype.get("grip_socket_profile") as Resource
		if profile != null:
			return profile
	return DEFAULT_GRIP_SOCKET_PROFILE


func _item_equipped_transform(item: Resource) -> Transform3D:
	var value = item.get("equipped_transform") if item != null else null
	return value if value is Transform3D else Transform3D.IDENTITY


func _item_grip_transform(model_root: Node3D, item: Resource) -> Transform3D:
	var marker_name := "GripPoint_Primary"
	var grip_profile := item.get("grip_profile") as Resource if item != null else null
	if grip_profile != null and not str(grip_profile.get("primary_grip_marker")).is_empty():
		marker_name = str(grip_profile.get("primary_grip_marker"))
	var marker := _find_node3d_by_name(model_root, marker_name)
	return _node3d_transform_relative_to_root(model_root, marker) if marker != null else Transform3D.IDENTITY


func _bone_attachment_name(slot_name: String) -> String:
	return "Equipped%sAttachment" % slot_name.capitalize()


func _bone_equipment_visual_name(slot_name: String) -> String:
	return "Equipped%sVisual" % slot_name.capitalize()


func _clear_equipment_children(root: Node) -> void:
	if root == null:
		return
	for child in root.get_children():
		root.remove_child(child)
		child.queue_free()


func _clear_tagged_equipment_visuals(root: Node) -> void:
	if root == null:
		return
	for child in root.get_children():
		if child.has_meta(EQUIPMENT_VISUAL_META):
			root.remove_child(child)
			child.queue_free()
		else:
			_clear_tagged_equipment_visuals(child)


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var skeleton := _find_skeleton(child)
		if skeleton != null:
			return skeleton
	return null


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var player := _find_animation_player(child)
		if player != null:
			return player
	return null


func _find_node3d_by_name(root: Node, node_name: String) -> Node3D:
	if root is Node3D and root.name == node_name:
		return root as Node3D
	for child in root.get_children():
		var found := _find_node3d_by_name(child, node_name)
		if found != null:
			return found
	return null


func _node3d_transform_relative_to_root(root: Node3D, target: Node3D) -> Transform3D:
	if target == root:
		return Transform3D.IDENTITY
	var current: Node = target
	var result := Transform3D.IDENTITY
	while current != null and current != root:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


func _equipment_signature_for(equipment_slots: Dictionary) -> String:
	var parts: Array[String] = []
	var slot_names := equipment_slots.keys()
	slot_names.sort()
	for slot_name in slot_names:
		parts.append("%s=%s" % [str(slot_name), str(equipment_slots[slot_name])])
	return "|".join(parts)


func _attached_item_paths() -> Array[String]:
	var paths: Array[String] = []
	_collect_attached_item_paths(self, paths)
	paths.sort()
	var unique_paths: Array[String] = []
	for path in paths:
		if not unique_paths.has(path):
			unique_paths.append(path)
	return unique_paths


func _collect_attached_item_paths(root: Node, paths: Array[String]) -> void:
	if root.has_meta("item_definition_path"):
		paths.append(str(root.get_meta("item_definition_path")))
	for child in root.get_children():
		_collect_attached_item_paths(child, paths)


func _resource_path(value) -> String:
	if value is Resource:
		return (value as Resource).resource_path
	return ""
