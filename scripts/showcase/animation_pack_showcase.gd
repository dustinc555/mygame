extends Node3D


const MALE_AVATAR_SCENE = preload("res://assets/vendor/quaternius/universal_base_characters/base_characters/Superhero_Male_FullBody.gltf")
const FEMALE_AVATAR_SCENE = preload("res://assets/vendor/quaternius/universal_base_characters/base_characters/Superhero_Female_FullBody.gltf")
const UAL1_PRO_SCENE = preload("res://assets/vendor/quaternius/universal_animation_library_1_pro/UAL1_Pro.glb")
const UAL2_STANDARD_SCENE = preload("res://assets/vendor/quaternius/universal_animation_library_2/UAL2_Standard.glb")

const AVATAR_SPACING := 3.6
const ROW_SPACING := 4.8
const PLATFORM_MARGIN := 5.0
const PLATFORM_GAP := 12.0
const LABEL_HEIGHT := 2.45
const PLATFORM_HEIGHT := 0.45

var _avatar_count := 0


func _ready() -> void:
	_build_showcase()
	_add_hud_label()


func _build_showcase() -> void:
	var packs := [
		{
			"key": "ual1_pro",
			"title": "Universal Animation Library 1 Pro - Unarmed Combat/Movement",
			"source_scene": UAL1_PRO_SCENE,
			"columns": 8,
			"color": Color(0.34, 0.22, 0.12, 1.0),
		},
		{
			"key": "ual2_standard",
			"title": "Universal Animation Library 2 Standard - Blocks/Melee/Stance",
			"source_scene": UAL2_STANDARD_SCENE,
			"columns": 6,
			"color": Color(0.34, 0.22, 0.12, 1.0),
		},
	]

	var next_x := 0.0
	for pack in packs:
		var source_scene := pack["source_scene"] as PackedScene
		var source_root := source_scene.instantiate()
		var source_player := _find_animation_player(source_root)
		if source_player == null:
			source_root.free()
			continue

		var animation_names := _get_pack_animation_names(String(pack["key"]), source_player)
		var columns := int(pack["columns"])
		var rows := ceili(float(animation_names.size()) / float(columns))
		var width := maxf(float(columns - 1) * AVATAR_SPACING + PLATFORM_MARGIN * 2.0, 12.0)
		var depth := maxf(float(maxi(rows - 1, 0)) * ROW_SPACING + PLATFORM_MARGIN * 2.0, 12.0)
		var center := Vector3(next_x + width * 0.5, 0.0, 0.0)

		_add_platform(String(pack["title"]), center, width, depth, pack["color"] as Color, animation_names.size())
		_populate_pack_platform(String(pack["key"]), source_player, animation_names, center, columns, rows)

		source_root.free()
		next_x += width + PLATFORM_GAP


func _get_pack_animation_names(pack_key: String, source_player: AnimationPlayer) -> Array[String]:
	var result: Array[String] = []
	for animation_name in source_player.get_animation_list():
		var clip_name := String(animation_name)
		if _should_include_animation(pack_key, clip_name):
			result.append(clip_name)
	return result


func _should_include_animation(pack_key: String, animation_name: String) -> bool:
	var key := animation_name.to_lower()
	match pack_key:
		"ual1_pro":
			return _contains_any(key, [
				"punch", "kick", "hit", "dodge", "roll", "walk", "jog", "sprint",
				"idle", "crouch", "turn", "death", "jump",
			]) and not _contains_any(key, [
				"pistol", "sword", "spell", "torch", "paper", "rock", "scissors", "climb",
				"crawl", "counter", "sitting", "swim", "push", "pickup", "driving",
				"fixing", "drink", "dance", "celebration", "crying", "groundsit", "talking",
			])
		"ual2_standard":
			return _contains_any(key, [
				"melee", "shield", "block", "hit", "ninjajump", "zombie", "sword_block",
				"idle_foldarms", "slide", "walk_carry",
			])
	return false


func _contains_any(value: String, needles: Array) -> bool:
	for needle in needles:
		if value.contains(String(needle)):
			return true
	return false


func _populate_pack_platform(pack_key: String, source_player: AnimationPlayer, animation_names: Array[String], center: Vector3, columns: int, rows: int) -> void:
	var start_x := -float(columns - 1) * AVATAR_SPACING * 0.5
	var start_z := -float(maxi(rows - 1, 0)) * ROW_SPACING * 0.5
	for index in range(animation_names.size()):
		var column := index % columns
		var row := index / columns
		var avatar_position := center + Vector3(start_x + float(column) * AVATAR_SPACING, 0.0, start_z + float(row) * ROW_SPACING)
		_add_animated_avatar(pack_key, source_player, animation_names[index], avatar_position)


func _add_animated_avatar(pack_key: String, source_player: AnimationPlayer, animation_name: String, position: Vector3) -> void:
	var avatar_scene := FEMALE_AVATAR_SCENE if _avatar_count % 2 == 0 else MALE_AVATAR_SCENE
	_avatar_count += 1

	var avatar := avatar_scene.instantiate() as Node3D
	avatar.name = _sanitize_node_name(animation_name)
	avatar.position = position
	add_child(avatar)

	var target_skeleton := _find_skeleton(avatar)
	if target_skeleton == null:
		_add_clip_label(animation_name + "\n(no skeleton)", position)
		return

	var source_animation := source_player.get_animation(animation_name)
	var retargeted_animation := _retarget_animation(pack_key, source_animation, avatar, target_skeleton)
	if retargeted_animation == null:
		_add_clip_label(animation_name + "\n(no tracks)", position)
		return

	var animation_player := AnimationPlayer.new()
	animation_player.name = "ShowcaseAnimationPlayer"
	animation_player.root_node = NodePath("..")
	avatar.add_child(animation_player)

	var library := AnimationLibrary.new()
	library.add_animation(animation_name, retargeted_animation)
	animation_player.add_animation_library("", library)
	animation_player.play(animation_name)

	_add_clip_label(animation_name, position)


func _retarget_animation(pack_key: String, source_animation: Animation, target_root: Node3D, target_skeleton: Skeleton3D) -> Animation:
	if source_animation == null:
		return null

	var skeleton_path := String(target_root.get_path_to(target_skeleton))
	var retargeted := Animation.new()
	retargeted.length = source_animation.length
	retargeted.loop_mode = Animation.LOOP_LINEAR

	for source_track_index in range(source_animation.get_track_count()):
		var track_type := source_animation.track_get_type(source_track_index)
		if not _is_supported_track_type(track_type):
			continue

		var source_bone := _get_track_bone_name(source_animation.track_get_path(source_track_index))
		if source_bone.is_empty():
			continue
		var target_bone := _map_source_bone(pack_key, source_bone)
		var target_bone_index := target_skeleton.find_bone(target_bone)
		if target_bone.is_empty() or target_bone_index == -1:
			continue

		var target_track_index := retargeted.add_track(track_type)
		retargeted.track_set_path(target_track_index, NodePath("%s:%s" % [skeleton_path, target_bone]))
		retargeted.track_set_interpolation_type(target_track_index, source_animation.track_get_interpolation_type(source_track_index))

		for key_index in range(source_animation.track_get_key_count(source_track_index)):
			var key_value = source_animation.track_get_key_value(source_track_index, key_index)
			retargeted.track_insert_key(
				target_track_index,
				source_animation.track_get_key_time(source_track_index, key_index),
				key_value,
				source_animation.track_get_key_transition(source_track_index, key_index)
			)

	return retargeted if retargeted.get_track_count() > 0 else null


func _is_supported_track_type(track_type: int) -> bool:
	return track_type == Animation.TYPE_POSITION_3D or track_type == Animation.TYPE_ROTATION_3D or track_type == Animation.TYPE_SCALE_3D


func _get_track_bone_name(track_path: NodePath) -> String:
	var path_text := String(track_path)
	var separator_index := path_text.rfind(":")
	if separator_index == -1 or separator_index >= path_text.length() - 1:
		return ""
	return path_text.substr(separator_index + 1)


func _map_source_bone(pack_key: String, source_bone: String) -> String:
	return source_bone


func _add_platform(title: String, center: Vector3, width: float, depth: float, color: Color, clip_count: int) -> void:
	var platform_body := StaticBody3D.new()
	platform_body.name = _sanitize_node_name(title) + "Platform"
	platform_body.position = center + Vector3(0.0, -PLATFORM_HEIGHT * 0.5, 0.0)
	add_child(platform_body)

	var shape := BoxShape3D.new()
	shape.size = Vector3(width, PLATFORM_HEIGHT, depth)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	platform_body.add_child(collision)

	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, PLATFORM_HEIGHT, depth)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _make_platform_material(color)
	platform_body.add_child(mesh_instance)

	var label := Label3D.new()
	label.name = _sanitize_node_name(title) + "Label"
	label.position = center + Vector3(0.0, 3.25, -depth * 0.5 + 1.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.text = "%s\n%d clips" % [title, clip_count]
	label.font_size = 54
	label.outline_size = 10
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	add_child(label)


func _add_clip_label(text: String, position: Vector3) -> void:
	var label := Label3D.new()
	label.name = _sanitize_node_name(text) + "Label"
	label.position = position + Vector3(0.0, LABEL_HEIGHT, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.text = text
	label.font_size = 25
	label.outline_size = 5
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	add_child(label)


func _add_hud_label() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ShowcaseHUD"
	add_child(layer)

	var label := Label.new()
	label.offset_left = 18.0
	label.offset_top = 18.0
	label.offset_right = 820.0
	label.offset_bottom = 96.0
	label.text = "Animation Pack Showcase: WASD fly, mouse look, Space/E up, Ctrl/Q down, Shift faster, Esc releases mouse. Clips loop on Quaternius base avatars."
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layer.add_child(label)


func _make_platform_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var player := _find_animation_player(child)
		if player != null:
			return player
	return null


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var skeleton := _find_skeleton(child)
		if skeleton != null:
			return skeleton
	return null


func _sanitize_node_name(value: String) -> String:
	var sanitized := value
	for character in [" ", "-", "/", "\\", ":", ".", "\n"]:
		sanitized = sanitized.replace(character, "_")
	return sanitized
