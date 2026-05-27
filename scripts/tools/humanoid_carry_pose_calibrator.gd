@tool
extends Node3D

class_name HumanoidCarryPoseCalibrator

const DEFAULT_CARRY_POSE_PROFILE := preload("res://resources/humanoid_carry_pose_profiles/default.tres")
const HUMAN_MALE_BODY_ARCHETYPE := preload("res://resources/character_body_archetypes/human_male.tres")
const HUMAN_FEMALE_BODY_ARCHETYPE := preload("res://resources/character_body_archetypes/human_female.tres")
const CHARACTER_APPEARANCE_DATA_SCRIPT := preload("res://scripts/character_appearance/character_appearance_data.gd")
const UAL2_ANIMATION_SOURCE_SCENE := preload("res://assets/vendor/quaternius/universal_animation_library_2/UAL2.glb")

const CARRY_ANIMATION_NAME := "LiftAir_Fall"
const CARRIER_PATH := NodePath("Carrier")
const SHOULDER_ORIGIN_PATH := NodePath("ShoulderOrigin")
const CARRIED_POSE_PATH := NodePath("ShoulderOrigin/CarriedPose")
const STATUS_LABEL_PATH := NodePath("StatusLabel")
const GENERATED_MODEL_NAME := "__GeneratedModel"
const GENERATED_ANIMATION_PLAYER_NAME := "__CarryPoseAnimationPlayer"
const CHARACTER_VISUAL_NODE_NAME := "CharacterVisual"
const BODY_MESH_NODE_NAME := "BodyMesh"
const COLLISION_SHAPE_NODE_NAME := "CollisionShape3D"
const CHARACTER_VISUAL_YAW_OFFSET := PI
const CHARACTER_VISUAL_FOOT_CLEARANCE := 0.02

@export var carry_pose_profile: Resource = DEFAULT_CARRY_POSE_PROFILE:
	set(value):
		carry_pose_profile = value
		_load_pose_from_profile_deferred()
@export_group("Save")
@export var save_now := false:
	set(value):
		save_now = false
		if value:
			_save_pose_to_profile()
@export var load_now := false:
	set(value):
		load_now = false
		if value:
			_load_pose_from_profile()
@export_group("Preview")
@export var carrier_body_archetype: Resource = HUMAN_MALE_BODY_ARCHETYPE:
	set(value):
		carrier_body_archetype = value
		_rebuild_preview_deferred()
@export var carried_body_archetype: Resource = HUMAN_FEMALE_BODY_ARCHETYPE:
	set(value):
		carried_body_archetype = value
		_rebuild_preview_deferred()
@export_range(-1.0, 1.0, 0.01) var carrier_height_slider := 0.0:
	set(value):
		carrier_height_slider = clampf(value, -1.0, 1.0)
		_rebuild_preview_deferred()
@export_range(-1.0, 1.0, 0.01) var carrier_shoulder_width_slider := 0.0:
	set(value):
		carrier_shoulder_width_slider = clampf(value, -1.0, 1.0)
		_rebuild_preview_deferred()
@export_range(-1.0, 1.0, 0.01) var carrier_arm_length_slider := 0.0:
	set(value):
		carrier_arm_length_slider = clampf(value, -1.0, 1.0)
		_rebuild_preview_deferred()
@export_range(-1.0, 1.0, 0.01) var carrier_neck_length_slider := 0.0:
	set(value):
		carrier_neck_length_slider = clampf(value, -1.0, 1.0)
		_rebuild_preview_deferred()
@export_range(-1.0, 1.0, 0.01) var carried_height_slider := 0.0:
	set(value):
		carried_height_slider = clampf(value, -1.0, 1.0)
		_rebuild_preview_deferred()
@export_range(-1.0, 1.0, 0.01) var carried_shoulder_width_slider := 0.0:
	set(value):
		carried_shoulder_width_slider = clampf(value, -1.0, 1.0)
		_rebuild_preview_deferred()
@export_range(-1.0, 1.0, 0.01) var carried_arm_length_slider := 0.0:
	set(value):
		carried_arm_length_slider = clampf(value, -1.0, 1.0)
		_rebuild_preview_deferred()
@export_range(-1.0, 1.0, 0.01) var carried_neck_length_slider := 0.0:
	set(value):
		carried_neck_length_slider = clampf(value, -1.0, 1.0)
		_rebuild_preview_deferred()
@export_range(0.0, 1.0, 0.01) var carried_pose_time_ratio := 0.0:
	set(value):
		carried_pose_time_ratio = clampf(value, 0.0, 1.0)
		_rebuild_preview_deferred()
@export var show_carrier_preview := false:
	set(value):
		show_carrier_preview = value
		_apply_preview_visibility()
@export_group("Legacy")
@export var save_pose_to_profile := false:
	set(value):
		save_pose_to_profile = false
		if value:
			_save_pose_to_profile()
@export var load_pose_from_profile := false:
	set(value):
		load_pose_from_profile = false
		if value:
			_load_pose_from_profile()
@export var rebuild_preview := false:
	set(value):
		rebuild_preview = false
		if value:
			_rebuild_preview_deferred()
@export_multiline var current_pose_text := "ShoulderOrigin is the shoulder. Edit ShoulderOrigin/CarriedPose locally, then Save > Save Now.":
	set(value):
		current_pose_text = value
		_update_status_label_deferred()


func _ready() -> void:
	set_process(Engine.is_editor_hint())
	call_deferred("_rebuild_preview")
	call_deferred("_load_pose_from_profile")


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_update_shoulder_origin()
	_update_pose_text()


func _rebuild_preview_deferred() -> void:
	if not is_inside_tree():
		return
	call_deferred("_rebuild_preview")


func _rebuild_preview() -> void:
	_rebuild_model(CARRIER_PATH, carrier_body_archetype, false)
	_rebuild_model(CARRIED_POSE_PATH, carried_body_archetype, true)
	_apply_preview_visibility()
	_update_shoulder_origin()
	_update_pose_text()


func _rebuild_model(root_path: NodePath, body_archetype: Resource, apply_carried_pose: bool) -> void:
	var root := get_node_or_null(root_path) as Node3D
	if root == null:
		return
	_clear_generated_model(root)
	var visual_scene := _get_visual_scene(body_archetype)
	if visual_scene == null:
		return
	var instance := visual_scene.instantiate()
	if not (instance is Node3D):
		instance.queue_free()
		return
	var holder := Node3D.new()
	holder.name = GENERATED_MODEL_NAME
	holder.visible = show_carrier_preview if root_path == CARRIER_PATH else true
	root.add_child(holder)
	var body_mesh := _make_preview_body_mesh()
	holder.add_child(body_mesh)
	var collision_shape := _make_preview_collision_shape()
	holder.add_child(collision_shape)
	var visual_root := Node3D.new()
	visual_root.name = CHARACTER_VISUAL_NODE_NAME
	holder.add_child(visual_root)
	var model_root := instance as Node3D
	model_root.rotation.y = CHARACTER_VISUAL_YAW_OFFSET
	visual_root.add_child(model_root)
	_fit_visual_to_body_mesh(visual_root, body_mesh, collision_shape)
	if apply_carried_pose:
		_setup_carried_animation(model_root)
	var skeleton := _find_skeleton(visual_root)
	var is_carrier := root_path == CARRIER_PATH
	_apply_body_pose_offsets(skeleton, body_archetype, is_carrier, visual_root)


func _make_preview_body_mesh() -> MeshInstance3D:
	var body_mesh := MeshInstance3D.new()
	body_mesh.name = BODY_MESH_NODE_NAME
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.45
	body_mesh.mesh = capsule
	body_mesh.position.y = 0.95
	body_mesh.visible = false
	return body_mesh


func _make_preview_collision_shape() -> CollisionShape3D:
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = COLLISION_SHAPE_NODE_NAME
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.1
	collision_shape.shape = capsule
	collision_shape.position.y = 0.95
	return collision_shape


func _fit_visual_to_body_mesh(visual_root: Node3D, body_mesh: MeshInstance3D, collision_shape: CollisionShape3D) -> float:
	var body_bounds := _calculate_local_mesh_bounds(body_mesh)
	var visual_bounds := _calculate_local_mesh_bounds(visual_root)
	if body_bounds.size.y <= 0.001 or visual_bounds.size.y <= 0.001:
		return 1.0
	var fit_scale := body_bounds.size.y / visual_bounds.size.y
	var body_center := body_bounds.position + body_bounds.size * 0.5
	var visual_center := visual_bounds.position + visual_bounds.size * 0.5
	var visual_ground_y := _get_visual_ground_y(collision_shape, body_bounds.position.y) + CHARACTER_VISUAL_FOOT_CLEARANCE
	visual_root.scale = Vector3.ONE * fit_scale
	visual_root.position = Vector3(
		body_center.x - visual_center.x * fit_scale,
		visual_ground_y - visual_bounds.position.y * fit_scale,
		body_center.z - visual_center.z * fit_scale
	)
	return fit_scale


func _get_visual_ground_y(collision_shape: CollisionShape3D, fallback_y: float) -> float:
	if collision_shape == null or collision_shape.shape == null:
		return fallback_y
	var shape_bounds := _get_collision_shape_local_bounds(collision_shape)
	if shape_bounds.size.y <= 0.001:
		return fallback_y
	return shape_bounds.position.y


func _get_collision_shape_local_bounds(collision_shape: CollisionShape3D) -> AABB:
	var shape := collision_shape.shape
	var shape_bounds := AABB()
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		shape_bounds = AABB(Vector3(-capsule.radius, -capsule.height * 0.5, -capsule.radius), Vector3(capsule.radius * 2.0, capsule.height, capsule.radius * 2.0))
	elif shape is SphereShape3D:
		var sphere := shape as SphereShape3D
		shape_bounds = AABB(Vector3(-sphere.radius, -sphere.radius, -sphere.radius), Vector3(sphere.radius * 2.0, sphere.radius * 2.0, sphere.radius * 2.0))
	elif shape is BoxShape3D:
		var box := shape as BoxShape3D
		shape_bounds = AABB(-box.size * 0.5, box.size)
	else:
		return AABB()
	return _transform_aabb(shape_bounds, collision_shape.transform)


func _calculate_local_mesh_bounds(root: Node) -> AABB:
	var result := {
		"has_bounds": false,
		"bounds": AABB(),
	}
	_accumulate_local_mesh_bounds(root, Transform3D.IDENTITY, result)
	return result["bounds"]


func _accumulate_local_mesh_bounds(node: Node, parent_transform: Transform3D, result: Dictionary) -> void:
	var local_transform := parent_transform
	if node is Node3D:
		local_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_bounds := _transform_aabb((node as MeshInstance3D).mesh.get_aabb(), local_transform)
		if bool(result["has_bounds"]):
			result["bounds"] = (result["bounds"] as AABB).merge(mesh_bounds)
		else:
			result["bounds"] = mesh_bounds
			result["has_bounds"] = true
	for child in node.get_children():
		_accumulate_local_mesh_bounds(child, local_transform, result)


func _transform_aabb(bounds: AABB, transform: Transform3D) -> AABB:
	var first := true
	var transformed_bounds := AABB()
	for x in [bounds.position.x, bounds.position.x + bounds.size.x]:
		for y in [bounds.position.y, bounds.position.y + bounds.size.y]:
			for z in [bounds.position.z, bounds.position.z + bounds.size.z]:
				var point := transform * Vector3(x, y, z)
				if first:
					transformed_bounds = AABB(point, Vector3.ZERO)
					first = false
				else:
					transformed_bounds = transformed_bounds.expand(point)
	return transformed_bounds


func _clear_generated_model(root: Node3D) -> void:
	var existing := root.get_node_or_null(GENERATED_MODEL_NAME)
	if existing != null:
		root.remove_child(existing)
		existing.free()


func _setup_carried_animation(model_root: Node3D) -> void:
	var animation_player := AnimationPlayer.new()
	animation_player.name = GENERATED_ANIMATION_PLAYER_NAME
	animation_player.root_node = NodePath("..")
	model_root.add_child(animation_player)
	var animation_library := AnimationLibrary.new()
	var source := UAL2_ANIMATION_SOURCE_SCENE.instantiate()
	var source_player := _find_animation_player(source)
	if source_player != null and source_player.has_animation(CARRY_ANIMATION_NAME):
		var source_animation := source_player.get_animation(CARRY_ANIMATION_NAME)
		if source_animation != null:
			animation_library.add_animation(CARRY_ANIMATION_NAME, source_animation.duplicate(true))
	source.queue_free()
	if animation_library.get_animation_list().is_empty():
		animation_player.queue_free()
		return
	animation_player.add_animation_library("", animation_library)
	var animation := animation_player.get_animation(CARRY_ANIMATION_NAME)
	var sample_time := animation.length * carried_pose_time_ratio if animation != null else 0.0
	animation_player.speed_scale = 0.0
	animation_player.play(CARRY_ANIMATION_NAME)
	animation_player.seek(sample_time, true)
	animation_player.advance(0.0)


func _load_pose_from_profile_deferred() -> void:
	if not is_inside_tree():
		return
	call_deferred("_load_pose_from_profile")


func _load_pose_from_profile() -> void:
	var carried_pose := get_node_or_null(CARRIED_POSE_PATH) as Node3D
	if carried_pose == null:
		return
	var profile := _get_profile()
	carried_pose.position = _get_profile_vector(profile, "carried_local_position", Vector3.ZERO)
	carried_pose.rotation_degrees = _get_profile_vector(profile, "rotation_degrees", Vector3.ZERO)
	carried_pose_time_ratio = clampf(_get_profile_float(profile, "carried_pose_time_ratio", carried_pose_time_ratio), 0.0, 1.0)
	_update_shoulder_origin()
	_update_pose_text("Loaded profile.")


func _save_pose_to_profile() -> void:
	var carried_pose := get_node_or_null(CARRIED_POSE_PATH) as Node3D
	var profile := _get_profile()
	if carried_pose == null or profile == null:
		return
	profile.set("carried_local_position", carried_pose.position)
	profile.set("rotation_degrees", carried_pose.rotation_degrees)
	profile.set("carried_pose_time_ratio", carried_pose_time_ratio)
	profile.set("carrier_anchor_local_offset", Vector3.ZERO)
	profile.set("carried_anchor_local_offset", Vector3.ZERO)
	if profile.resource_path.is_empty():
		_update_pose_text("Profile has no resource path; cannot save.")
		return
	var error := ResourceSaver.save(profile, profile.resource_path)
	if error != OK:
		_update_pose_text("Profile save failed: %s" % error)
		return
	_update_pose_text("Saved profile. Runtime uses this shoulder-local transform.")


func _update_shoulder_origin() -> void:
	var carrier := get_node_or_null(CARRIER_PATH) as Node3D
	var shoulder_origin := get_node_or_null(SHOULDER_ORIGIN_PATH) as Node3D
	if carrier == null or shoulder_origin == null:
		return
	var profile := _get_profile()
	var shoulder_position := _get_actor_anchor_global_position(
		carrier,
		_get_profile_bone_names(profile, "carrier_anchor_bones", PackedStringArray(["upperarm_r", "clavicle_r", "spine_03"])),
		"carrier"
	)
	shoulder_origin.global_transform = Transform3D(carrier.global_transform.basis.orthonormalized(), shoulder_position)


func _get_actor_anchor_global_position(actor_root: Node3D, bone_names: PackedStringArray, anchor_role: String) -> Vector3:
	var skeleton := _find_skeleton(actor_root)
	if skeleton != null:
		skeleton.force_update_all_bone_transforms()
		var bone_index := _find_carry_anchor_bone_index(skeleton, bone_names, anchor_role)
		if bone_index >= 0:
			return skeleton.global_transform * skeleton.get_bone_global_pose(bone_index).origin
	return actor_root.global_transform * (Vector3(0.24, 1.55, 0.08) if anchor_role == "carrier" else Vector3.ZERO)


func _apply_preview_visibility() -> void:
	var carrier := get_node_or_null(CARRIER_PATH) as Node3D
	if carrier != null:
		var carrier_model := carrier.get_node_or_null(GENERATED_MODEL_NAME) as Node3D
		if carrier_model != null:
			carrier_model.visible = show_carrier_preview


func _apply_body_pose_offsets(skeleton: Skeleton3D, body_archetype: Resource, is_carrier: bool, visual_root: Node3D) -> void:
	if skeleton == null:
		return
	var base_offsets: Dictionary = {}
	if body_archetype != null and body_archetype.get("bone_pose_position_offsets") is Dictionary:
		base_offsets = (body_archetype.get("bone_pose_position_offsets") as Dictionary).duplicate()
	var appearance = CHARACTER_APPEARANCE_DATA_SCRIPT.new()
	appearance.height_slider = carrier_height_slider if is_carrier else carried_height_slider
	appearance.shoulder_width_slider = carrier_shoulder_width_slider if is_carrier else carried_shoulder_width_slider
	appearance.arm_length_slider = carrier_arm_length_slider if is_carrier else carried_arm_length_slider
	appearance.neck_length_slider = carrier_neck_length_slider if is_carrier else carried_neck_length_slider
	var offsets: Dictionary = appearance.get_body_pose_offsets(base_offsets)
	for bone_name_value in offsets.keys():
		var bone_index := skeleton.find_bone(str(bone_name_value))
		if bone_index >= 0:
			skeleton.set_bone_pose_position(bone_index, skeleton.get_bone_rest(bone_index).origin)
	skeleton.force_update_all_bone_transforms()
	for bone_name_value in offsets.keys():
		var bone_index := skeleton.find_bone(str(bone_name_value))
		if bone_index < 0:
			continue
		var offset := offsets[bone_name_value] as Vector3
		skeleton.set_bone_pose_position(bone_index, skeleton.get_bone_rest(bone_index).origin + offset)
	skeleton.force_update_all_bone_transforms()
	if visual_root != null and appearance.has_method("get_foot_anchor_correction_y"):
		visual_root.position.y += float(appearance.get_foot_anchor_correction_y()) * visual_root.scale.y


func _update_pose_text(extra_status := "") -> void:
	var carried_pose := get_node_or_null(CARRIED_POSE_PATH) as Node3D
	if carried_pose == null:
		return
	var profile_path := _get_profile().resource_path if _get_profile() != null else "<none>"
	current_pose_text = "ShoulderOrigin is the shoulder origin. Edit ShoulderOrigin/CarriedPose locally, then use Save > Save Now.\nprofile = %s\ncarried_local_position = %s\nrotation_degrees = %s\ncarried_pose_time_ratio = %.2f" % [
		profile_path,
		_format_vector(carried_pose.position, 3),
		_format_vector(carried_pose.rotation_degrees, 2),
		carried_pose_time_ratio,
	]
	if not extra_status.is_empty():
		current_pose_text += "\n%s" % extra_status
	_update_status_label()


func _update_status_label_deferred() -> void:
	if not is_inside_tree():
		return
	call_deferred("_update_status_label")


func _update_status_label() -> void:
	var status_label := get_node_or_null(STATUS_LABEL_PATH) as Label3D
	if status_label == null:
		return
	status_label.text = current_pose_text


func _get_profile() -> Resource:
	return carry_pose_profile if carry_pose_profile != null else DEFAULT_CARRY_POSE_PROFILE


func _get_visual_scene(body_archetype: Resource) -> PackedScene:
	if body_archetype != null:
		var visual_scene := body_archetype.get("visual_scene") as PackedScene
		if visual_scene != null:
			return visual_scene
	return HUMAN_MALE_BODY_ARCHETYPE.get("visual_scene") as PackedScene


func _get_profile_bone_names(profile: Resource, property_name: String, fallback: PackedStringArray) -> PackedStringArray:
	if profile == null:
		return fallback
	var value = profile.get(property_name)
	var result := PackedStringArray()
	if value is PackedStringArray:
		result = value
	elif value is Array:
		for item in value:
			result.append(str(item))
	elif value is String and not str(value).is_empty():
		result.append(str(value))
	return result if not result.is_empty() else fallback


func _get_profile_vector(profile: Resource, property_name: String, fallback: Vector3) -> Vector3:
	if profile == null:
		return fallback
	var value = profile.get(property_name)
	return value if value is Vector3 else fallback


func _get_profile_float(profile: Resource, property_name: String, fallback: float) -> float:
	if profile == null:
		return fallback
	var value = profile.get(property_name)
	if value is float or value is int:
		return float(value)
	return fallback


func _find_carry_anchor_bone_index(skeleton: Skeleton3D, bone_names: PackedStringArray, anchor_role: String) -> int:
	for bone_name in bone_names:
		var exact_index := skeleton.find_bone(str(bone_name))
		if exact_index >= 0:
			return exact_index
	var semantic_index := _find_semantic_carry_anchor_bone_index(skeleton, anchor_role)
	if semantic_index >= 0:
		return semantic_index
	for bone_index in range(skeleton.get_bone_count()):
		return bone_index
	return -1


func _find_semantic_carry_anchor_bone_index(skeleton: Skeleton3D, anchor_role: String) -> int:
	if anchor_role == "carrier":
		var shoulder_index := _find_bone_index_by_keyword_groups(skeleton, [
			["upperarm", "r"],
			["right", "upperarm"],
			["clavicle", "r"],
			["right", "clavicle"],
			["shoulder", "r"],
			["right", "shoulder"],
		])
		if shoulder_index >= 0:
			return shoulder_index
		return _find_highest_spine_bone_index(skeleton)
	return _find_bone_index_by_keyword_groups(skeleton, [["spine02"], ["spine2"], ["spine", "02"], ["spine", "2"], ["stomach"], ["abdomen"], ["torso"], ["chest"], ["spine03"], ["spine3"], ["pelvis"], ["hips"]])


func _find_bone_index_by_keyword_groups(skeleton: Skeleton3D, keyword_groups: Array) -> int:
	for keyword_group in keyword_groups:
		for bone_index in range(skeleton.get_bone_count()):
			var normalized_name := _normalize_bone_name(skeleton.get_bone_name(bone_index))
			var matches := true
			for keyword in keyword_group:
				if not normalized_name.contains(_normalize_bone_name(str(keyword))):
					matches = false
					break
			if matches:
				return bone_index
	return -1


func _find_highest_spine_bone_index(skeleton: Skeleton3D) -> int:
	var best_index := -1
	var best_score := -1
	for bone_index in range(skeleton.get_bone_count()):
		var normalized_name := _normalize_bone_name(skeleton.get_bone_name(bone_index))
		if not normalized_name.contains("spine") and not normalized_name.contains("chest"):
			continue
		var score := 0
		for character in normalized_name:
			if character.is_valid_int():
				score = score * 10 + int(character)
		if score >= best_score:
			best_score = score
			best_index = bone_index
	return best_index


func _normalize_bone_name(bone_name: String) -> String:
	return bone_name.to_lower().replace("_", "").replace("-", "").replace(" ", "").replace(".", "").replace(":", "")


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


func _format_vector(value: Vector3, decimals: int) -> String:
	var format := "%%.%df" % decimals
	return "Vector3(%s, %s, %s)" % [format % value.x, format % value.y, format % value.z]
