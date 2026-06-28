extends "res://features/actors/projection/quadbot/robot_actor.gd"

class_name QuadBotCharacter

## Thin GECS actuator for the quadbot enemy (S5 reshape, 2026-06-30).
##
## Robots are driven by the GECS combat systems exactly like humanoids: the
## targeting system picks the target and PUSHES it via `set_system_target_bridge`
## (`_system_target_id`), the resolution system pushes combat action/reaction state
## (`_system_combat_*`), the movement system pushes desired velocity. This node only
## READS that pushed state and ACTUATES it — presentation, the combat-animation state
## machine, movement/facing, and quadbot's SPECIAL ragdoll death.
##
## The old self-driven AI/targeting/order block (`_ai_brain`, `AI_JOB_SCRIPT`,
## `_process_ai`, `assign_attack_target`, hostility/ally response, order tracking) was
## DELETED here — that concern now belongs to the GECS AI/targeting systems. Its
## semantics (retarget cadence, self-defense, ally response, player-order rules) are
## preserved in git history + clean-HEAD `main` for when that system is built out for
## robots. See cleanup.md "S5 EXECUTION".

@warning_ignore("unused_signal")
signal appearance_changed

const WORLD_TEXT_NOTICE_SCENE = preload("res://features/world/projection/effects/world_text_notice.tscn")
const COMBAT_ANIMATION_SET_SCRIPT = preload("res://features/actors/resources/characters/combat_animation_set.gd")
const COMBAT_ATTACK_ANIMATION_SCRIPT = preload("res://features/actors/resources/characters/combat_attack_animation.gd")
const CHARACTER_APPEARANCE_DATA_SCRIPT = preload("res://features/actors/resources/character_appearance/character_appearance_data.gd")
const QUADBOT_RACE = preload("res://features/actors/resources/character_races/quadbot.tres")
const QUADBOT_BODY_ARCHETYPE = preload("res://features/actors/resources/character_body_archetypes/quadbot.tres")
const QUADBOT_VISUAL_SCENE = preload("res://assets/vendor/quaternius/sci_fi_essentials_kit/gltf/Enemy_QuadOrb.gltf")
const QUADBOT_BODY_PROJECTION_SCRIPT = preload("res://features/actors/projection/quadbot/quadbot_body_projection.gd")
const SELECTION_RING_VISUAL = preload("res://features/actors/projection/selection_ring_visual.gd")

const CHARACTER_VISUAL_NODE_NAME := "CharacterVisual"
const QUADBOT_IDLE_ANIMATION_NAME := "Idle"
const QUADBOT_WALK_ANIMATION_NAME := "Walk"
const QUADBOT_RUN_ANIMATION_NAME := "Run"
const QUADBOT_ATTACK_ANIMATION_NAME := "Attack"
const UNARMED_STANCE_ID := "unarmed"
const QUADBOT_SKILL_BASE_LEVEL := 40
const QUADBOT_SKILL_VARIANCE := 8
const QUADBOT_SKILL_MIN_LEVEL := 24
const QUADBOT_SKILL_MAX_LEVEL := 58
const QUADBOT_BASE_MAX_HULL := 200.0
const QUADBOT_BASE_MAX_OIL := 120.0
const QUADBOT_RUN_SPEED_MULTIPLIER := 1.35
const COMBAT_ACTION_BLEND_SECONDS := 0.05
const DEFAULT_COMBAT_ACTION_SECONDS := 0.45
const DEFAULT_COMBAT_IMPACT_RATIO := 0.45
const RAGDOLL_IMPULSE_MEMORY_SECONDS := 4.0
const UPRIGHT_SELECTION_GROUND_MARKER_HEIGHT := 0.34
const SELECTION_GROUND_MARKER_HEIGHT := 0.02
const GROUND_MARKER_RAYCAST_UP := 0.35
const GROUND_MARKER_RAYCAST_DOWN := 24.0

enum VisualBodyType {
	AUTO,
	NONE,
	MALE,
	FEMALE,
}

@export var show_nameplate := true
@export var overhead_text_height := 1.8
@export var character_race: Resource = QUADBOT_RACE
@export var body_archetype: Resource = QUADBOT_BODY_ARCHETYPE
@export_enum("Auto", "None", "Male", "Female") var visual_body_type: int = VisualBodyType.NONE
@export var appearance_data: Resource

var is_selected := false
var is_focused := false
var is_inspected := false
var _body: BodyProjection
var _selection_ring: Node3D
var _quadbot_ring_material := StandardMaterial3D.new()
var _rng := RandomNumberGenerator.new()
var _combat_animation_sets: Dictionary = {}
var _pending_skill_levels: Dictionary = {}
var _downed_recover_delay_remaining := 0.0
var _is_getting_up := false
var _get_up_animation_name := ""
var _get_up_animation_remaining := 0.0
var _get_up_animation_total := 0.0


func _ready() -> void:
	_ensure_quadbot_defaults()
	super._ready()
	_apply_quadbot_skill_defaults()
	_rng.randomize()
	_setup_body_projection()
	_setup_quadbot_selection_ring()
	_recalculate_vitals()
	_update_quadbot_selection_visual()


func _process(delta: float) -> void:
	super._process(delta)
	if is_in_cell_custody():
		_process_recovery(delta)
		_recalculate_vitals()
		_update_quadbot_selection_visual()
		return
	_process_ragdoll_impulse_memory(delta)
	_process_recovery(delta)
	_recalculate_vitals()
	_process_downed_animation_state(delta)
	_update_quadbot_animation(delta)
	_update_quadbot_selection_visual()


func _physics_process(delta: float) -> void:
	if is_in_cell_custody():
		velocity = Vector3.ZERO
		return
	if life_state != NpcRules.LifeState.ALIVE:
		velocity = Vector3.ZERO
		_stabilize_active_ragdoll(delta)
		return
	# Combat movement/target is chosen by the GECS systems and pushed via the bridges;
	# the node reads that state and actuates nav movement + faces the combat focus.
	if _is_combat_resolution_busy() or _system_target_id != 0:
		_face_combat_focus()
	process_world_actor_movement(delta)


func set_selected(value: bool) -> void:
	is_selected = value
	_update_quadbot_selection_visual()


func set_focused(value: bool) -> void:
	is_focused = value
	_update_quadbot_selection_visual()


func set_inspected(value: bool) -> void:
	is_inspected = value


func set_running_enabled(value: bool) -> bool:
	running = value and life_state == NpcRules.LifeState.ALIVE
	state_changed.emit()
	return true


func is_running_enabled() -> bool:
	return running


func set_combat_stance(value: int) -> void:
	combat_stance = clampi(value, NpcRules.CombatStance.AGGRESSIVE, NpcRules.CombatStance.PASSIVE) as NpcRules.CombatStance
	state_changed.emit()


func set_move_target(target: Vector3, issued_by_player: bool = true) -> void:
	if is_in_cell_custody():
		return
	if life_state != NpcRules.LifeState.ALIVE:
		return
	super.set_move_target(target, issued_by_player)


func force_kill(_attacker: Node = null) -> void:
	blood = get_blood_death_point()
	hp = get_death_point(max_hp)
	_enter_dead_state()


func force_unconscious() -> void:
	if life_state == NpcRules.LifeState.DEAD:
		return
	_enter_unconscious_state()


func get_body_projection() -> BodyProjection:
	return _body if _body != null and is_instance_valid(_body) else null


func get_character_visual_root() -> Node3D:
	if _body != null:
		var visual_root := _body.get_visual_root()
		if visual_root != null:
			return visual_root
	return get_node_or_null(CHARACTER_VISUAL_NODE_NAME) as Node3D


func get_quadbot_visual_scene() -> PackedScene:
	return QUADBOT_VISUAL_SCENE


func is_ragdoll_active() -> bool:
	return _body != null and _body.is_ragdoll_active()


func get_follow_anchor_position() -> Vector3:
	if _body != null:
		var anchor = _body.get_ragdoll_anchor_position()
		if anchor is Vector3:
			return anchor
	return global_position


func get_body_weapon_damage_profile() -> Dictionary:
	return {"blunt_base": 8.0, "cut_base": 4.0}


static func make_varied_skill_levels(skill_seed: int, base_level := QUADBOT_SKILL_BASE_LEVEL) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = skill_seed
	return roll_varied_skill_levels(rng, base_level)


static func roll_varied_skill_levels(rng: RandomNumberGenerator, base_level := QUADBOT_SKILL_BASE_LEVEL) -> Dictionary:
	var result := {}
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	for definition in SkillRules.get_all_definitions():
		if definition == null:
			continue
		var skill_id := str(definition.get("skill_id"))
		if skill_id.is_empty():
			continue
		var level := base_level + _quadbot_skill_bias(skill_id) + rng.randi_range(-QUADBOT_SKILL_VARIANCE, QUADBOT_SKILL_VARIANCE)
		result[skill_id] = clampi(level, QUADBOT_SKILL_MIN_LEVEL, QUADBOT_SKILL_MAX_LEVEL)
	return result


func _setup_body_projection() -> void:
	if _body != null and is_instance_valid(_body):
		return
	_body = _create_body_projection()
	if _body == null:
		return
	_body.name = "BodyProjection"
	_body.bind_actor(self)
	add_child(_body)
	_body.setup_visual()


func _create_body_projection() -> BodyProjection:
	return QUADBOT_BODY_PROJECTION_SCRIPT.new() as BodyProjection


# ---------------------------------------------------------------------------
# Combat ACTUATION — the animation state machine reads the system-pushed
# `_system_combat_*` bridge state (set by GameCombatResolutionSystem). It does
# NOT decide combat; it presents it.
# ---------------------------------------------------------------------------

func _is_combat_resolution_busy() -> bool:
	return _system_combat_action_active or _system_combat_reaction_remaining > 0.0


func _get_combat_focus_actor() -> Node:
	if _system_combat_focus_id != 0:
		return instance_from_id(_system_combat_focus_id) as Node
	return null


func _get_current_combat_animation_set():
	_ensure_default_combat_animation_sets()
	return _combat_animation_sets.get(UNARMED_STANCE_ID, null)


func _ensure_default_combat_animation_sets() -> void:
	if not _combat_animation_sets.is_empty():
		return
	_combat_animation_sets[UNARMED_STANCE_ID] = _build_unarmed_combat_animation_set()


func _build_unarmed_combat_animation_set():
	var animation_set = COMBAT_ANIMATION_SET_SCRIPT.new()
	animation_set.stance_id = UNARMED_STANCE_ID
	animation_set.idle_animation_name = QUADBOT_IDLE_ANIMATION_NAME
	animation_set.block_animation_name = ""
	animation_set.fallback_hit_reaction_names = PackedStringArray()
	animation_set.attacks = [
		_make_combat_attack("quadbot_strike", [QUADBOT_ATTACK_ANIMATION_NAME], 1.0, 0.48, []),
	]
	return animation_set


func _make_combat_attack(attack_id: String, animation_names: Array[String], weight: float, impact_ratio: float, hit_reaction_names: Array[String]):
	var attack = COMBAT_ATTACK_ANIMATION_SCRIPT.new()
	attack.attack_id = attack_id
	attack.animation_names = PackedStringArray(animation_names)
	attack.weight = weight
	attack.impact_ratio = impact_ratio
	attack.hit_reaction_names = PackedStringArray(hit_reaction_names)
	return attack


func _choose_combat_attack(animation_set):
	if animation_set == null:
		return null
	var available_attacks: Array = []
	var total_weight := 0.0
	for attack in animation_set.attacks:
		if attack == null:
			continue
		var action_names: Array[String] = attack.get_animation_names()
		if _body == null or not _body.can_play_combat_action(action_names):
			continue
		available_attacks.append(attack)
		total_weight += maxf(float(attack.weight), 0.0)
	if available_attacks.is_empty() or total_weight <= 0.0:
		return null
	var roll := _rng.randf_range(0.0, total_weight)
	for attack in available_attacks:
		roll -= maxf(float(attack.weight), 0.0)
		if roll <= 0.0:
			return attack
	return available_attacks[available_attacks.size() - 1]


func _get_combat_action_timing(animation_names: Array[String], impact_ratio: float) -> Dictionary:
	if _body != null:
		return _body.get_combat_action_timing(animation_names, impact_ratio, DEFAULT_COMBAT_ACTION_SECONDS)
	return {
		"total_seconds": DEFAULT_COMBAT_ACTION_SECONDS,
		"first_clip_seconds": 0.0,
		"impact_seconds": clampf(DEFAULT_COMBAT_ACTION_SECONDS * impact_ratio, 0.05, DEFAULT_COMBAT_ACTION_SECONDS - 0.03),
	}


func _play_combat_action_clip(animation_name: String) -> float:
	var clip_seconds := _body.clip_length(animation_name) if _body != null else 0.0
	if _body != null:
		_body.play_clip(animation_name, 0.0, true, COMBAT_ACTION_BLEND_SECONDS)
	return clip_seconds


func _get_default_combat_action_seconds() -> float:
	return DEFAULT_COMBAT_ACTION_SECONDS


func _get_default_combat_impact_ratio() -> float:
	return DEFAULT_COMBAT_IMPACT_RATIO


# ---------------------------------------------------------------------------
# Movement / facing actuation
# ---------------------------------------------------------------------------

func _get_actor_move_speed() -> float:
	return move_speed * QUADBOT_RUN_SPEED_MULTIPLIER if running else move_speed


func _face_combat_focus() -> void:
	var focus_actor := _get_combat_focus_actor()
	if focus_actor != null:
		_face_character(focus_actor)


func _face_character(character: Node) -> void:
	if character is Node3D:
		_face_world_position((character as Node3D).global_position)


func _face_world_position(world_position: Vector3) -> void:
	var look_position := world_position
	look_position.y = global_position.y
	if global_position.distance_squared_to(look_position) > 0.0001:
		look_at(look_position, Vector3.UP)


# ---------------------------------------------------------------------------
# Life state — quadbot's SPECIAL ragdoll death / downed / get-up model.
# (robot_actor `_recalculate_vitals`/`_process_recovery` route damage/oil here.)
# ---------------------------------------------------------------------------

func _is_downed_recovery_locked() -> bool:
	return true


func _enter_unconscious_state() -> void:
	_enter_downed_life_state(NpcRules.LifeState.UNCONSCIOUS, 15.0, "Offline", Color(0.48, 0.62, 0.72, 1.0))


func _enter_recovery_coma_state() -> void:
	_enter_downed_life_state(NpcRules.LifeState.RECOVERY_COMA, 15.0, "Offline", Color(0.48, 0.62, 0.72, 1.0))


func _enter_downed_life_state(next_life_state: NpcRules.LifeState, recover_delay: float, notice: String, notice_color: Color) -> void:
	if life_state == NpcRules.LifeState.DEAD:
		return
	var previous_state := life_state
	if previous_state == next_life_state:
		_downed_recover_delay_remaining = maxf(_downed_recover_delay_remaining, recover_delay)
		return
	life_state = next_life_state
	_cancel_get_up()
	COMBAT_COORDINATOR.release_character(self)
	running = false
	_clear_actor_move_target()
	_downed_recover_delay_remaining = maxf(_downed_recover_delay_remaining, recover_delay)
	_enter_downed_state(false)
	_show_world_notice(notice, notice_color)
	life_state_changed.emit(previous_state, life_state)
	state_changed.emit()


func _enter_dead_state() -> void:
	if life_state == NpcRules.LifeState.DEAD:
		return
	var previous_state := life_state
	life_state = NpcRules.LifeState.DEAD
	_cancel_get_up()
	COMBAT_COORDINATOR.release_character(self)
	running = false
	_clear_actor_move_target()
	_enter_downed_state(true)
	_show_world_notice("Dead", Color(1.0, 0.2, 0.2, 1.0))
	velocity = Vector3.ZERO
	life_state_changed.emit(previous_state, life_state)
	died.emit(self)
	state_changed.emit()


func _enter_downed_state(is_dead: bool) -> void:
	_clear_actor_move_target()
	velocity = Vector3.ZERO
	if _body != null:
		_body.enter_downed_visuals(is_dead)


func _begin_get_up() -> void:
	if _is_getting_up or life_state == NpcRules.LifeState.DEAD:
		return
	_clear_actor_move_target()
	velocity = Vector3.ZERO
	_is_getting_up = true
	if _body != null:
		_body.begin_get_up_visuals()
	else:
		call_deferred("_finish_get_up")
	_show_world_notice("Getting up", Color(0.5, 1.0, 0.65, 1.0))
	state_changed.emit()


func _process_downed_animation_state(delta: float) -> void:
	if _body != null and _body.process_downed_visuals(delta):
		_finish_get_up()


func _finish_get_up() -> void:
	if not _is_getting_up:
		return
	_is_getting_up = false
	_get_up_animation_name = ""
	_get_up_animation_remaining = 0.0
	_get_up_animation_total = 0.0
	var previous_state := life_state
	life_state = NpcRules.LifeState.ALIVE
	_restore_from_downed_state()
	life_state_changed.emit(previous_state, life_state)
	state_changed.emit()


func _cancel_get_up() -> void:
	if _body != null:
		_body.cancel_get_up_visuals()
	_is_getting_up = false
	_get_up_animation_name = ""
	_get_up_animation_remaining = 0.0
	_get_up_animation_total = 0.0


func _restore_from_downed_state() -> void:
	if _body != null:
		_body.restore_from_downed_visuals()
	_restore_downed_collision_shape()


func _apply_downed_collision_shape() -> void:
	var collision_shape := _get_main_collision_shape()
	if collision_shape == null:
		return
	if not _downed_collision_applied:
		_stored_collision_shape = collision_shape.shape
		_stored_collision_transform = collision_shape.transform
		_stored_collision_disabled = collision_shape.disabled
		_stored_collision_layer = collision_layer
		_stored_collision_mask = collision_mask
		_stored_navigation_avoidance_enabled = navigation_avoidance_enabled
	collision_shape.disabled = true
	collision_layer = 0
	collision_mask = 0
	_downed_collision_applied = true
	_set_navigation_avoidance_enabled(false)


func _restore_downed_collision_shape() -> void:
	var collision_shape := _get_main_collision_shape()
	if _downed_collision_applied and collision_shape != null:
		collision_shape.shape = _stored_collision_shape
		collision_shape.transform = _stored_collision_transform
		collision_shape.disabled = _stored_collision_disabled
		collision_layer = _stored_collision_layer
		collision_mask = _stored_collision_mask
	_downed_collision_applied = false
	_set_navigation_avoidance_enabled(_stored_navigation_avoidance_enabled)


func _get_main_collision_shape() -> CollisionShape3D:
	return get_node_or_null("CollisionShape3D") as CollisionShape3D


func _set_navigation_avoidance_enabled(enabled: bool) -> void:
	navigation_avoidance_enabled = enabled
	var agent := get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if agent != null:
		agent.avoidance_enabled = enabled


# ---------------------------------------------------------------------------
# Ragdoll impulse memory (presentation — driven by combat-hit FX)
# ---------------------------------------------------------------------------

func _process_ragdoll_impulse_memory(delta: float) -> void:
	if _body != null:
		_body.process_ragdoll_impulse_memory(delta)


func _remember_combat_attack_impulse(attacker: Node, damage: float) -> void:
	if _body != null:
		_body.remember_ragdoll_impulse(_get_attack_ragdoll_impulse(attacker, damage), RAGDOLL_IMPULSE_MEMORY_SECONDS)


func _stabilize_active_ragdoll(delta: float) -> void:
	if _body != null:
		_body.stabilize_ragdoll(delta)


func _get_attack_ragdoll_impulse(attacker: Node, damage: float) -> Vector3:
	return _body.get_attack_ragdoll_impulse(attacker, damage) if _body != null else Vector3.ZERO


func _update_quadbot_animation(delta: float) -> void:
	if _body == null or life_state != NpcRules.LifeState.ALIVE:
		return
	if _is_combat_resolution_busy():
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed <= 0.05:
		_body.update_idle_animation(delta, false)
	elif running:
		_body.play_clip(QUADBOT_RUN_ANIMATION_NAME, clampf(horizontal_speed / maxf(move_speed * QUADBOT_RUN_SPEED_MULTIPLIER, 0.001), 0.0, 1.0))
	else:
		_body.play_clip(QUADBOT_WALK_ANIMATION_NAME, clampf(horizontal_speed / maxf(move_speed, 0.001), 0.0, 1.0))


func _show_world_notice(message: String, color: Color = Color(1.0, 0.28, 0.28, 1.0), lifetime: float = 1.0, rise_height: float = 0.4) -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var notice = WORLD_TEXT_NOTICE_SCENE.instantiate()
	tree.current_scene.add_child(notice)
	if notice.has_method("setup"):
		notice.setup(global_position + Vector3(0.0, overhead_text_height, 0.0), message, color, lifetime, rise_height)


func _award_combat_attack_xp() -> void:
	add_skill_xp(SkillRules.COMBAT_UNARMED, 0.85, "combat_attack")


func _award_toughness_xp(real_damage: float) -> void:
	if real_damage > 0.0:
		add_skill_xp(SkillRules.ATTRIBUTE_TOUGHNESS, real_damage * 0.18, "damage_taken")


# ---------------------------------------------------------------------------
# Non-lethal-arrest combat hooks (safe robot defaults; the resolution system
# consults these on incoming attacks).
# ---------------------------------------------------------------------------

func _is_incoming_law_arrest(_attacker: Node) -> bool:
	return false


func _is_nonlethal_authority_arrest_attack(_attacker: Node) -> bool:
	return false


func _clamp_nonlethal_arrest_damage(final_blunt: float, _final_cut: float) -> Dictionary:
	return {"blunt": final_blunt, "cut": 0.0}


# ---------------------------------------------------------------------------
# Config — robot defaults + skills/appearance. Skills are authored INTO the
# StatsCapability (which owns `starting_skill_levels`), not onto the node.
# ---------------------------------------------------------------------------

func _ensure_quadbot_defaults() -> void:
	character_race = QUADBOT_RACE
	body_archetype = QUADBOT_BODY_ARCHETYPE
	visual_body_type = VisualBodyType.NONE
	move_speed = maxf(move_speed, 3.35)
	max_hp = QUADBOT_BASE_MAX_HULL
	hp = max_hp
	base_max_blood = QUADBOT_BASE_MAX_OIL
	max_blood = QUADBOT_BASE_MAX_OIL
	blood = max_blood
	_ensure_quadbot_skill_defaults()
	_ensure_quadbot_appearance_defaults()


func _ensure_quadbot_skill_defaults() -> void:
	var defaults := make_varied_skill_levels(_quadbot_skill_seed())
	for definition in SkillRules.get_all_definitions():
		if definition == null:
			continue
		var skill_id := str(definition.get("skill_id"))
		if skill_id.is_empty() or defaults.has(skill_id):
			continue
		defaults[skill_id] = QUADBOT_SKILL_BASE_LEVEL
	_pending_skill_levels = defaults


func _apply_quadbot_skill_defaults() -> void:
	var stats := get_stats()
	if stats == null or _pending_skill_levels.is_empty():
		return
	# Seed only skills the capability doesn't already carry (preserve spawner/operator overrides),
	# then apply — StatsCapability.ready() already ran its one-shot apply before we get here.
	var to_seed := {}
	for skill_id_value in _pending_skill_levels.keys():
		if not stats.starting_skill_levels.has(skill_id_value):
			to_seed[skill_id_value] = _pending_skill_levels[skill_id_value]
	if not to_seed.is_empty():
		stats.apply_starting_skill_levels(to_seed)


static func _quadbot_skill_bias(skill_id: String) -> int:
	match skill_id:
		SkillRules.ATTRIBUTE_STRENGTH, SkillRules.ATTRIBUTE_TOUGHNESS, SkillRules.COMBAT_UNARMED:
			return 6
		SkillRules.ATTRIBUTE_ENDURANCE, SkillRules.TECH_ROBOTICS:
			return 8
		SkillRules.ATTRIBUTE_DEXTERITY, SkillRules.MOVEMENT_RUNNING:
			return 3
		SkillRules.ATTRIBUTE_CHARISMA:
			return -10
		SkillRules.KNOWLEDGE_MEDICINE:
			return -6
	return 0


func _quadbot_skill_seed() -> int:
	var seed_text := "%s:%s" % [str(member_name), str(name)]
	var raw_seed := int(seed_text.hash())
	return raw_seed if raw_seed >= 0 else -raw_seed + 1


func _ensure_quadbot_appearance_defaults() -> void:
	if appearance_data == null:
		appearance_data = CHARACTER_APPEARANCE_DATA_SCRIPT.new()
	elif appearance_data.has_method("make_copy"):
		appearance_data = appearance_data.make_copy()
	appearance_data.character_race = QUADBOT_RACE
	appearance_data.body_archetype = QUADBOT_BODY_ARCHETYPE
	appearance_data.visual_body_type = VisualBodyType.NONE
	appearance_data.hair_style = null
	appearance_data.beard_style = null
	appearance_data.eyebrow_style = null
	appearance_data.skin_color_customized = false


func _setup_quadbot_selection_ring() -> void:
	_selection_ring = get_node_or_null("SelectionRing") as Node3D
	var selection_mesh := _selection_ring as MeshInstance3D
	if selection_mesh != null:
		SELECTION_RING_VISUAL.setup_ring(selection_mesh, _quadbot_ring_material)


func _update_quadbot_selection_visual() -> void:
	if _selection_ring == null or not is_instance_valid(_selection_ring):
		_selection_ring = get_node_or_null("SelectionRing") as Node3D
	var selection_mesh := _selection_ring as MeshInstance3D
	if selection_mesh == null:
		return
	SELECTION_RING_VISUAL.apply_state(selection_mesh, _quadbot_ring_material, is_selected, is_focused)
	_update_ground_marker_transform(selection_mesh, UPRIGHT_SELECTION_GROUND_MARKER_HEIGHT if life_state == NpcRules.LifeState.ALIVE and not is_ragdoll_active() else SELECTION_GROUND_MARKER_HEIGHT)


func _update_ground_marker_transform(marker: Node3D, marker_height: float) -> void:
	if marker == null or not is_instance_valid(marker) or not marker.visible:
		return
	marker.top_level = true
	marker.global_position = get_ground_marker_position(marker_height)
	marker.global_rotation = Vector3.ZERO


func get_ground_marker_position(marker_height: float = SELECTION_GROUND_MARKER_HEIGHT) -> Vector3:
	if not is_inside_tree():
		return global_position + Vector3(0.0, marker_height, 0.0)
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * GROUND_MARKER_RAYCAST_UP, global_position - Vector3.UP * GROUND_MARKER_RAYCAST_DOWN)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return (hit["position"] as Vector3) + Vector3(0.0, marker_height, 0.0)
	return global_position + Vector3(0.0, marker_height, 0.0)
