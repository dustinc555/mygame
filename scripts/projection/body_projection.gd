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

var actor: Node = null


func bind_actor(owner_actor: Node) -> void:
	actor = owner_actor


# --- Visual build ---

func setup_visual() -> void:
	pass


func get_visual_root() -> Node3D:
	return null


func has_custom_skin_material() -> bool:
	return false


func apply_automatic_eyebrow_style() -> void:
	pass


func rebuild_visual_for_appearance() -> void:
	setup_visual()
	refresh_grip_sockets_for_body()


func apply_appearance_materials(_root: Node, _body_type: int) -> void:
	pass


func set_base_eyebrow_visuals_visible(_root: Node, _visible_flag: bool) -> void:
	pass


func get_resolved_visual_body_type() -> int:
	return 0


func get_resolved_body_archetype() -> Resource:
	return null


func setup_animation(_model_root: Node3D) -> void:
	pass


# --- Clip playback ---

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
