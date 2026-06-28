extends Node3D
class_name BodyProjection

# Visual adapter ("Body") for an actor. PRESENTATION ONLY -- never owns durable truth.
#
# The owning actor (the truth owner) binds itself via bind_actor() and drives this
# interface every frame / on state changes. Species subclasses (HumanoidBodyProjection,
# QuadOrbBodyProjection, ...) implement the actual rendering/animation. Swapping the
# body must not change any simulation outcome.
#
# Lives under scripts/projection/. Owns no simulation state. Methods here are the
# contract the actor calls; defaults are safe no-ops so a body that lacks a feature
# (e.g. a clip-less robot) simply does nothing visual.

# Sim-agnostic: the base projection only STORES the actor + drives it via the methods the actor
# calls on THIS object (one-way, sim->visual). It makes no calls back into the actor, so it needs
# no WorldActor type. Concrete subclasses that DO call actor methods cache their own typed handle.
# This keeps the base off WorldActor and breaks the BodyProjection<->WorldActor dependency cycle.
var actor: Node3D = null


func bind_actor(owner_actor: Node3D) -> void:
	actor = owner_actor


# --- Visual build ---

func setup_visual() -> void:
	pass


func get_visual_root() -> Node3D:
	return null


func get_visual_local_bounds() -> AABB:
	return AABB()


func has_custom_skin_material() -> bool:
	return false


func apply_automatic_eyebrow_style() -> void:
	pass


func rebuild_visual_for_appearance() -> void:
	setup_visual()


func apply_appearance_materials(_root: Node, _body_type: int) -> void:
	pass


func set_base_eyebrow_visuals_visible(_root: Node, _visible_flag: bool) -> void:
	pass


# --- Ragdoll / downed visuals ---

func supports_downed_visuals() -> bool:
	return false


func supports_ragdoll_visuals() -> bool:
	return false

func process_ragdoll_impulse_memory(_delta: float) -> void:
	pass


func remember_ragdoll_impulse(_impulse: Vector3, _seconds: float) -> void:
	pass


func enter_downed_visuals(_is_dead: bool) -> bool:
	return false


func restore_from_downed_visuals() -> void:
	pass


func begin_get_up_visuals() -> void:
	pass


func process_downed_visuals(_delta: float) -> bool:
	return false


func cancel_get_up_visuals() -> void:
	pass


func start_ragdoll_simulation(_is_dead: bool) -> bool:
	return false


func stop_ragdoll_simulation(_reset_pose: bool) -> void:
	pass


func prepare_ragdoll_get_up() -> void:
	pass


func stabilize_ragdoll(_delta: float) -> void:
	pass


func is_ragdoll_active() -> bool:
	return false


func get_ragdoll_anchor_position() -> Variant:
	return null


func get_attack_ragdoll_impulse(_attacker: Node, _damage: float) -> Vector3:
	return Vector3.ZERO


func get_resolved_visual_body_type() -> int:
	return 0


func get_resolved_body_archetype() -> Resource:
	return null


func setup_animation(_model_root: Node3D) -> void:
	pass


# --- Clip playback ---

func update_idle_animation(_delta: float, _use_tired_idle: bool) -> void:
	pass


func play_random_idle_animation(_force: bool) -> void:
	pass


func start_crouch_enter_animation() -> void:
	pass


func start_crouch_exit_animation() -> void:
	pass


func cancel_crouch_transition() -> void:
	pass


func cancel_run_transition() -> void:
	pass


func update_crouch_enter_animation(_delta: float) -> bool:
	return false


func update_crouch_exit_animation(_delta: float) -> bool:
	return false


func update_run_transition(_delta: float, _wants_run_animation: bool) -> bool:
	return false


func start_sitting_enter_animation(_allow_talking_idle: bool = false) -> void:
	pass


func start_sitting_exit_animation() -> void:
	pass


func update_sitting_animation(_delta: float, _allow_talking_idle: bool) -> void:
	pass


func update_sitting_exit_animation(_delta: float) -> bool:
	return false


func cancel_sitting_exit_animation() -> void:
	pass


func play_clip(_animation_name: String, _speed_ratio: float = 0.0, _force_restart: bool = false, _blend_seconds: float = 0.0) -> bool:
	return false


func stop_clip(_keep_state: bool = true) -> void:
	pass


func clip_length(_animation_name: String) -> float:
	return 0.0


func has_clip(_animation_name: String) -> bool:
	return false


func get_current_clip() -> String:
	return ""


func is_current_clip_playing() -> bool:
	return false


func get_primary_animation_player() -> AnimationPlayer:
	return null


func get_animation_players() -> Array[AnimationPlayer]:
	var result: Array[AnimationPlayer] = []
	return result


func get_skeleton() -> Skeleton3D:
	return null


func seek_clip(_animation_name: String, _time: float, _update: bool = true, _speed_scale: float = 1.0) -> void:
	pass


func can_play_combat_action(_animation_names: Array[String]) -> bool:
	return false


func get_combat_action_timing(_animation_names: Array[String], impact_ratio: float, default_seconds: float = 0.45) -> Dictionary:
	var total_seconds := maxf(0.05, default_seconds)
	return {
		"total_seconds": total_seconds,
		"first_clip_seconds": 0.0,
		"impact_seconds": _get_combat_impact_seconds(total_seconds, impact_ratio),
	}


func pick_block_reaction_clip(_has_shield: bool, _animation_set, _shield_block_animation_names: Array[String], fallback_block_animation_name: String) -> String:
	return fallback_block_animation_name


func pick_hit_reaction_clip(_attack_id: String, _hit_reaction_names: Array[String] = []) -> String:
	return ""


func pick_available_clip(_animation_names: Array[String]) -> String:
	return ""


func pick_preferred_available_clip(_animation_names: Array[String]) -> String:
	return ""


func play_combat_reaction_clip(_animation_name: String, _blend_seconds: float) -> float:
	return 0.0


func _get_combat_impact_seconds(action_seconds: float, impact_ratio: float) -> float:
	if action_seconds <= 0.0:
		return 0.0
	return clampf(action_seconds * impact_ratio, 0.05, maxf(0.05, action_seconds - 0.03))


func is_idle_clip(_animation_name: String) -> bool:
	return false


func get_available_idle_clip_names() -> Array[String]:
	return []


# --- Foot IK / grounding ---

func apply_bone_pose_offsets() -> void:
	pass


func refresh_foot_ground_alignment() -> void:
	pass


func get_visual_foot_anchor_y() -> float:
	return INF


func get_visual_ground_y() -> float:
	return 0.0


# --- Equipment / attachment visuals ---

func set_equipped_clothing_visuals_visible(_visible_flag: bool) -> void:
	pass


func refresh_grip_sockets_for_body() -> void:
	pass


func rebuild_visual_for_equipment() -> void:
	setup_visual()


func can_refresh_bone_equipment_only(_changed_slots: Array) -> bool:
	return false


func refresh_bone_equipment_slots(_changed_slots: Array) -> void:
	rebuild_visual_for_equipment()
