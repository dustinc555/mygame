extends BodyProjection
class_name HumanoidBodyProjection

# Humanoid visual adapter. PRESENTATION ONLY -- never owns durable truth.
#
# Holds humanoid animation + foot-IK behavior migrated out of HumanoidCharacter.
# Animation/skeleton STATE still lives on the actor during migration (other systems
# and tests read it directly); this projection owns the LOGIC and reads/writes that
# state via `actor`. Constants are read through the untyped `actor` at runtime so this
# file never statically depends on HumanoidCharacter (which would be a cyclic dep).
#
# Migrated in increment A1: animation library setup/copy, clip playback, idle-clip
# selection, foot-ground IK. Rustdead clip overrides live in RustdeadBodyProjection.

const DEFAULT_MOVE_BLEND_SECONDS := 0.12


# --- Animation library setup / copy ---

func setup_animation(model_root: Node3D) -> void:
	var animation_player := AnimationPlayer.new()
	animation_player.name = actor.CHARACTER_ANIMATION_PLAYER_NAME
	animation_player.root_node = NodePath("..")
	model_root.add_child(animation_player)
	var animation_library := AnimationLibrary.new()
	_copy_character_animations(animation_library)
	if animation_library.get_animation_list().is_empty():
		animation_player.queue_free()
		return
	animation_player.add_animation_library("", animation_library)
	actor._character_animation_players.append(animation_player)
	if actor._character_animation_player == null:
		actor._character_animation_player = animation_player


func _copy_character_animations(animation_library: AnimationLibrary) -> void:
	var ual1_source: Node = actor.UAL1_ANIMATION_SOURCE_SCENE.instantiate()
	var ual1_player := _find_animation_player(ual1_source)
	if ual1_player != null:
		_copy_animation(ual1_player, animation_library, actor.IDLE_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, actor.TIRED_IDLE_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, actor.WALK_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, actor.CROUCH_ENTER_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, actor.CROUCH_IDLE_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, actor.CROUCH_WALK_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, actor.CROUCH_EXIT_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, actor.RUN_ENTER_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, actor.JOG_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, actor.RUN_EXIT_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, actor.SITTING_ENTER_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, actor.SITTING_IDLE_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, actor.SITTING_TALKING_ANIMATION_NAME)
		_copy_animation(ual1_player, animation_library, actor.SITTING_EXIT_ANIMATION_NAME)
		_copy_default_combat_set_animations(ual1_player, animation_library)
		_copy_contextual_combat_reaction_animations(ual1_player, animation_library)
		_copy_ragdoll_profile_animations(ual1_player, animation_library)
		_copy_unarmed_combat_idle_animation(ual1_player, animation_library)
	ual1_source.queue_free()

	var ual2_source: Node = actor.UAL2_ANIMATION_SOURCE_SCENE.instantiate()
	var ual2_player := _find_animation_player(ual2_source)
	if ual2_player != null:
		_copy_animation(ual2_player, animation_library, actor.FOLD_ARMS_IDLE_ANIMATION_NAME)
		_copy_animation(ual2_player, animation_library, actor.MINING_ANIMATION_NAME)
		_copy_default_combat_set_animations(ual2_player, animation_library)
		_copy_contextual_combat_reaction_animations(ual2_player, animation_library)
		_copy_ragdoll_profile_animations(ual2_player, animation_library)
		_copy_named_animations(ual2_player, animation_library, actor.CARRY_POSE_ANIMATION_NAMES)
		_copy_named_animations(ual2_player, animation_library, actor.CELL_CUSTODY_ANIMATION_NAMES)
	ual2_source.queue_free()


func _copy_animation(source_player: AnimationPlayer, animation_library: AnimationLibrary, animation_name: String) -> void:
	if not source_player.has_animation(animation_name) or animation_library.has_animation(animation_name):
		return
	var source_animation := source_player.get_animation(animation_name)
	if source_animation == null:
		return
	var copied_animation := source_animation.duplicate(true) as Animation
	animation_library.add_animation(animation_name, copied_animation)


func _copy_named_animations(source_player: AnimationPlayer, animation_library: AnimationLibrary, animation_names: Array) -> void:
	for animation_name in animation_names:
		_copy_animation(source_player, animation_library, String(animation_name))


func _copy_default_combat_set_animations(source_player: AnimationPlayer, animation_library: AnimationLibrary) -> void:
	actor._ensure_default_combat_animation_sets()
	for animation_set_value in actor._combat_animation_sets.values():
		var animation_set = animation_set_value
		if animation_set == null:
			continue
		for animation_name in animation_set.get_all_animation_names():
			_copy_animation(source_player, animation_library, animation_name)


func _copy_contextual_combat_reaction_animations(source_player: AnimationPlayer, animation_library: AnimationLibrary) -> void:
	_copy_animation(source_player, animation_library, actor.SHIELD_COMBAT_IDLE_ANIMATION_NAME)
	for animation_name in actor.SHIELD_BLOCK_ANIMATION_NAMES:
		_copy_animation(source_player, animation_library, String(animation_name))


func _copy_ragdoll_profile_animations(source_player: AnimationPlayer, animation_library: AnimationLibrary) -> void:
	for animation_name in actor._get_ragdoll_profile_animation_names():
		_copy_animation(source_player, animation_library, String(animation_name))


func _copy_unarmed_combat_idle_animation(source_player: AnimationPlayer, animation_library: AnimationLibrary) -> void:
	if animation_library.has_animation(actor.UNARMED_COMBAT_IDLE_ANIMATION_NAME):
		return
	if not source_player.has_animation(actor.UNARMED_STANCE_ENTER_ANIMATION_NAME) or not source_player.has_animation(actor.UNARMED_STANCE_EXIT_ANIMATION_NAME):
		return
	var enter_animation := source_player.get_animation(actor.UNARMED_STANCE_ENTER_ANIMATION_NAME)
	var exit_animation := source_player.get_animation(actor.UNARMED_STANCE_EXIT_ANIMATION_NAME)
	if enter_animation == null or exit_animation == null:
		return
	var enter_duration := minf(actor.UNARMED_COMBAT_IDLE_SEGMENT_SECONDS, enter_animation.length)
	var exit_duration := minf(actor.UNARMED_COMBAT_IDLE_SEGMENT_SECONDS, exit_animation.length)
	if enter_duration <= 0.0 or exit_duration <= 0.0:
		return
	var generated_animation := Animation.new()
	generated_animation.length = enter_duration + exit_duration
	generated_animation.loop_mode = Animation.LOOP_LINEAR
	var track_map: Dictionary = {}
	_copy_animation_time_window(enter_animation, generated_animation, maxf(0.0, enter_animation.length - enter_duration), enter_animation.length, 0.0, track_map)
	_copy_animation_time_window(exit_animation, generated_animation, 0.0, exit_duration, enter_duration, track_map)
	if generated_animation.get_track_count() == 0:
		return
	animation_library.add_animation(actor.UNARMED_COMBAT_IDLE_ANIMATION_NAME, generated_animation)


func _copy_animation_time_window(source_animation: Animation, target_animation: Animation, source_start: float, source_end: float, target_offset: float, track_map: Dictionary) -> void:
	for source_track_index in range(source_animation.get_track_count()):
		var target_track_index := _get_or_create_copied_animation_track(source_animation, target_animation, source_track_index, track_map)
		var did_insert_key := false
		for key_index in range(source_animation.track_get_key_count(source_track_index)):
			var key_time := source_animation.track_get_key_time(source_track_index, key_index)
			if key_time < source_start or key_time > source_end:
				continue
			_target_insert_animation_key(source_animation, target_animation, source_track_index, target_track_index, key_index, target_offset + key_time - source_start)
			did_insert_key = true
		if not did_insert_key:
			var sample_key_index := _get_animation_sample_key_index(source_animation, source_track_index, source_start)
			if sample_key_index >= 0:
				_target_insert_animation_key(source_animation, target_animation, source_track_index, target_track_index, sample_key_index, target_offset)


func _get_or_create_copied_animation_track(source_animation: Animation, target_animation: Animation, source_track_index: int, track_map: Dictionary) -> int:
	var track_key := "%s|%s" % [str(source_animation.track_get_path(source_track_index)), str(source_animation.track_get_type(source_track_index))]
	if track_map.has(track_key):
		return int(track_map[track_key])
	var target_track_index := target_animation.add_track(source_animation.track_get_type(source_track_index))
	target_animation.track_set_path(target_track_index, source_animation.track_get_path(source_track_index))
	target_animation.track_set_interpolation_type(target_track_index, source_animation.track_get_interpolation_type(source_track_index))
	track_map[track_key] = target_track_index
	return target_track_index


func _get_animation_sample_key_index(source_animation: Animation, source_track_index: int, sample_time: float) -> int:
	var key_count := source_animation.track_get_key_count(source_track_index)
	if key_count <= 0:
		return -1
	var sample_key_index := 0
	for key_index in range(key_count):
		if source_animation.track_get_key_time(source_track_index, key_index) <= sample_time:
			sample_key_index = key_index
		else:
			break
	return sample_key_index


func _target_insert_animation_key(source_animation: Animation, target_animation: Animation, source_track_index: int, target_track_index: int, source_key_index: int, target_time: float) -> void:
	target_animation.track_insert_key(
		target_track_index,
		clampf(target_time, 0.0, target_animation.length),
		source_animation.track_get_key_value(source_track_index, source_key_index),
		source_animation.track_get_key_transition(source_track_index, source_key_index)
	)


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for child in root.get_children():
		var player := _find_animation_player(child)
		if player != null:
			return player
	return null


# --- Clip playback ---

func play_clip(animation_name: String, speed_ratio: float = 0.0, force_restart: bool = false, blend_seconds: float = DEFAULT_MOVE_BLEND_SECONDS) -> bool:
	if actor._character_animation_player == null or not actor._character_animation_player.has_animation(animation_name):
		return false
	var custom_speed := _get_clip_speed(animation_name, speed_ratio)
	var already_current: bool = actor._current_character_animation == animation_name
	actor._current_character_animation = animation_name
	var started_animation := false
	for animation_player in actor._character_animation_players:
		if animation_player == null or not animation_player.has_animation(animation_name):
			continue
		animation_player.speed_scale = custom_speed
		if not force_restart and already_current and animation_player.is_playing():
			continue
		animation_player.play(animation_name, blend_seconds)
		animation_player.advance(0.0)
		started_animation = true
	if started_animation:
		apply_bone_pose_offsets()
		refresh_foot_ground_alignment()
	return true


func stop_clip(keep_state: bool = true) -> void:
	actor._current_character_animation = ""
	for animation_player in actor._character_animation_players:
		if animation_player == null:
			continue
		animation_player.stop(keep_state)
		animation_player.speed_scale = 1.0


func clip_length(animation_name: String) -> float:
	var player: AnimationPlayer = actor._character_animation_player
	if player == null or not player.has_animation(animation_name):
		return 0.0
	var animation := player.get_animation(animation_name)
	return animation.length if animation != null else 0.0


func has_clip(animation_name: String) -> bool:
	var player: AnimationPlayer = actor._character_animation_player
	return player != null and player.has_animation(animation_name)


func get_current_clip() -> String:
	return str(actor._current_character_animation)


func _get_clip_speed(animation_name: String, speed_ratio: float) -> float:
	if animation_name == actor.WALK_ANIMATION_NAME:
		return lerpf(0.85, 1.25, speed_ratio)
	elif animation_name == actor.CROUCH_WALK_ANIMATION_NAME:
		return lerpf(0.85, 1.15, speed_ratio)
	elif animation_name == actor.JOG_ANIMATION_NAME:
		return lerpf(0.9, 1.35, speed_ratio)
	return 1.0


# --- Idle clip selection (clip-name knowledge) ---

func get_available_idle_clip_names() -> Array[String]:
	var idle_names: Array[String] = []
	if actor._character_animation_player == null:
		return idle_names
	for animation_name_value in actor.IDLE_ANIMATION_NAMES:
		var animation_name := String(animation_name_value)
		if actor._character_animation_player.has_animation(animation_name):
			idle_names.append(animation_name)
	return idle_names


func is_idle_clip(animation_name: String) -> bool:
	return actor.IDLE_ANIMATION_NAMES.has(animation_name)


# --- Foot IK / grounding ---

func apply_bone_pose_offsets() -> void:
	var skeleton: Skeleton3D = actor._character_skeleton
	if skeleton == null or not is_instance_valid(skeleton):
		return
	if actor._bone_pose_position_offsets.is_empty() or actor._is_ragdoll_active:
		if not is_zero_approx(actor._visual_foot_anchor_correction_y):
			var reset_visual_root := actor.get_node_or_null(actor.CHARACTER_VISUAL_NODE_NAME) as Node3D
			_apply_visual_foot_anchor_correction(reset_visual_root, 0.0)
		return
	var visual_root := actor.get_node_or_null(actor.CHARACTER_VISUAL_NODE_NAME) as Node3D
	for bone_name in actor._bone_pose_position_offsets.keys():
		var bone_index := skeleton.find_bone(str(bone_name))
		if bone_index < 0:
			continue
		var offset: Vector3 = actor._bone_pose_position_offsets[bone_name]
		var rest_position := skeleton.get_bone_rest(bone_index).origin
		skeleton.set_bone_pose_position(bone_index, rest_position + offset)
	skeleton.force_update_all_bone_transforms()
	var desired_correction := 0.0
	if actor.appearance_data != null and actor.appearance_data.has_method("get_foot_anchor_correction_y") and visual_root != null:
		desired_correction = float(actor.appearance_data.get_foot_anchor_correction_y()) * visual_root.scale.y
	_apply_visual_foot_anchor_correction(visual_root, desired_correction)


func _apply_visual_foot_anchor_correction(visual_root: Node3D, desired_correction: float) -> void:
	if visual_root == null or not is_instance_valid(visual_root):
		return
	visual_root.position.y += desired_correction - actor._visual_foot_anchor_correction_y
	actor._visual_foot_anchor_correction_y = desired_correction


func refresh_foot_ground_alignment() -> void:
	if actor._is_ragdoll_active or actor._character_skeleton == null or not is_instance_valid(actor._character_skeleton):
		return
	var skeleton: Skeleton3D = actor._character_skeleton
	var visual_root := actor.get_node_or_null(actor.CHARACTER_VISUAL_NODE_NAME) as Node3D
	if visual_root == null:
		return
	skeleton.force_update_all_bone_transforms()
	var foot_y := _get_skeleton_foot_anchor_global_y(skeleton)
	if foot_y == INF:
		return
	var ground_y := get_visual_ground_y()
	var desired_correction := clampf(ground_y - foot_y, -actor.CHARACTER_VISUAL_FOOT_GROUND_CORRECTION_MAX_DOWN, actor.CHARACTER_VISUAL_FOOT_GROUND_CORRECTION_MAX_UP)
	var correction_delta: float = desired_correction - actor._visual_foot_ground_correction_y
	if absf(correction_delta) <= 0.001:
		return
	visual_root.position.y += correction_delta
	actor._visual_foot_ground_correction_y = desired_correction
	skeleton.force_update_all_bone_transforms()


func _get_skeleton_foot_anchor_global_y(skeleton: Skeleton3D) -> float:
	if skeleton == null or not is_instance_valid(skeleton):
		return INF
	var result := INF
	for bone_name in ["foot_l", "foot_r", "ball_l", "ball_r"]:
		var bone_index := skeleton.find_bone(bone_name)
		if bone_index < 0:
			continue
		var bone_global_position := skeleton.global_transform * skeleton.get_bone_global_pose(bone_index).origin
		result = minf(result, bone_global_position.y)
	return result


func get_visual_foot_anchor_y() -> float:
	var skeleton: Skeleton3D = actor._character_skeleton
	if skeleton == null or not is_instance_valid(skeleton):
		return INF
	skeleton.force_update_all_bone_transforms()
	return _get_skeleton_foot_anchor_global_y(skeleton)


func get_visual_ground_y() -> float:
	var fallback_y := 0.0
	var body_mesh := actor.get_node_or_null("BodyMesh") as MeshInstance3D
	if body_mesh != null:
		var body_bounds: AABB = actor._calculate_local_mesh_bounds(body_mesh)
		fallback_y = body_bounds.position.y
	var local_ground_y: float = actor._get_visual_ground_y(fallback_y) + actor.CHARACTER_VISUAL_FOOT_CLEARANCE
	return (actor.global_transform * Vector3(0.0, local_ground_y, 0.0)).y
