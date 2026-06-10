extends HumanoidBodyProjection
class_name RustdeadBodyProjection

# Rustdead (zombie) humanoid visual adapter. PRESENTATION ONLY -- never owns truth.
#
# Holds the rustdead-specific clip overrides migrated from RustdeadHumanoidCharacter:
# remapped zombie locomotion/idle clips and the extra zombie clip set. Rustdead
# constants are read through the untyped `actor` at runtime (the actor is a
# RustdeadHumanoidCharacter, which defines them). Cinder-burn visuals migrate later.


func play_clip(animation_name: String, speed_ratio: float = 0.0, force_restart: bool = false, blend_seconds: float = DEFAULT_MOVE_BLEND_SECONDS) -> bool:
	var resolved_animation := _resolve_rustdead_clip_name(animation_name)
	if actor._character_animation_player != null and resolved_animation != animation_name and not actor._character_animation_player.has_animation(resolved_animation):
		resolved_animation = animation_name
	return super.play_clip(resolved_animation, speed_ratio, force_restart, blend_seconds)


func _resolve_rustdead_clip_name(animation_name: String) -> String:
	if animation_name == actor.IDLE_ANIMATION_NAME or animation_name == actor.TIRED_IDLE_ANIMATION_NAME or animation_name == actor.UNARMED_COMBAT_IDLE_ANIMATION_NAME:
		return actor.RUSTDEAD_IDLE_ANIMATION_NAME
	elif animation_name == actor.WALK_ANIMATION_NAME:
		return actor.RUSTDEAD_WALK_ANIMATION_NAME
	elif animation_name == actor.JOG_ANIMATION_NAME:
		return actor.RUSTDEAD_RUN_ANIMATION_NAME
	return animation_name


func _get_clip_speed(animation_name: String, speed_ratio: float) -> float:
	if animation_name == actor.RUSTDEAD_WALK_ANIMATION_NAME:
		return lerpf(0.72, 1.08, speed_ratio)
	elif animation_name == actor.RUSTDEAD_RUN_ANIMATION_NAME:
		return lerpf(0.82, 1.22, speed_ratio)
	return super._get_clip_speed(animation_name, speed_ratio)


func _copy_character_animations(animation_library: AnimationLibrary) -> void:
	super._copy_character_animations(animation_library)
	var ual2_source: Node = actor.UAL2_ANIMATION_SOURCE_SCENE.instantiate()
	var ual2_player := _find_animation_player(ual2_source)
	if ual2_player != null:
		_copy_named_animations(ual2_player, animation_library, actor.RUSTDEAD_ANIMATION_NAMES)
	ual2_source.queue_free()


func get_available_idle_clip_names() -> Array[String]:
	if actor._character_animation_player != null and actor._character_animation_player.has_animation(actor.RUSTDEAD_IDLE_ANIMATION_NAME):
		var names: Array[String] = []
		names.append(String(actor.RUSTDEAD_IDLE_ANIMATION_NAME))
		return names
	return super.get_available_idle_clip_names()
