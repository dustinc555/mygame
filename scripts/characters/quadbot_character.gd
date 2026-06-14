extends "res://scripts/characters/robot_actor.gd"

class_name QuadBotCharacter

signal appearance_changed

const WORLD_TEXT_NOTICE_SCENE = preload("res://scenes/world/effects/world_text_notice.tscn")
const COMBAT_ANIMATION_SET_SCRIPT = preload("res://scripts/characters/combat_animation_set.gd")
const COMBAT_ATTACK_ANIMATION_SCRIPT = preload("res://scripts/characters/combat_attack_animation.gd")
const CHARACTER_APPEARANCE_DATA_SCRIPT = preload("res://scripts/character_appearance/character_appearance_data.gd")
const QUADBOT_RACE = preload("res://resources/character_races/quadbot.tres")
const QUADBOT_BODY_ARCHETYPE = preload("res://resources/character_body_archetypes/quadbot.tres")
const QUADBOT_VISUAL_SCENE = preload("res://assets/vendor/quaternius/sci_fi_essentials_kit/gltf/Enemy_QuadOrb.gltf")
const QUADBOT_BODY_PROJECTION_SCRIPT = preload("res://scripts/projection/quadbot_body_projection.gd")
const SELECTION_RING_VISUAL = preload("res://scripts/projection/selection_ring_visual.gd")

const CHARACTER_VISUAL_NODE_NAME := "CharacterVisual"
const WALK_ANIMATION_NAME := "Walk"
const JOG_ANIMATION_NAME := "Jog_Fwd"
const QUADBOT_IDLE_ANIMATION_NAME := "Idle"
const QUADBOT_WALK_ANIMATION_NAME := "Walk"
const QUADBOT_RUN_ANIMATION_NAME := "Run"
const QUADBOT_ATTACK_ANIMATION_NAME := "Attack"
const QUADBOT_DEATH_ANIMATION_NAME := "RobotDeath"
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
const COMBAT_RANGE_HYSTERESIS := 0.18
const RAGDOLL_IMPULSE_MEMORY_SECONDS := 4.0
const UPRIGHT_SELECTION_GROUND_MARKER_HEIGHT := 0.34
const SELECTION_GROUND_MARKER_HEIGHT := 0.02
const GROUND_MARKER_RAYCAST_UP := 0.35
const GROUND_MARKER_RAYCAST_DOWN := 24.0
const ACTIVE_AI_DECISION_INTERVAL := 0.35
const ACTIVE_AI_DECISION_JITTER := 0.15
const BACKGROUND_AI_DECISION_INTERVAL := 1.25
const BACKGROUND_AI_DECISION_JITTER := 0.45

enum OrderType {
	NONE,
	MOVE,
	MINE,
	SCAVENGE,
	OPEN_CONTAINER,
	TRADE,
	TALK,
	ATTACK,
	HEAL,
	FINISH_OFF,
	CARRY,
	SLEEP,
	PLACE_IN_BED,
	PLACE_IN_CELL,
	PLACE_IN_FURNACE,
	SIT,
	PICKUP_ITEM,
}

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
var _combat_capability: CombatCapability
var _ai_targeting_capability
var _current_attack_target: Node
var _attack_origin_position := Vector3.ZERO
var _ai_tick_remaining := 0.0
var _downed_recover_delay_remaining := 0.0
var _downed_collision_applied := false
var _stored_collision_shape: Shape3D
var _stored_collision_transform := Transform3D.IDENTITY
var _stored_collision_disabled := false
var _stored_collision_layer := 1
var _stored_collision_mask := 1
var _stored_navigation_avoidance_enabled := true
var _is_getting_up := false
var _get_up_animation_name := ""
var _get_up_animation_remaining := 0.0
var _get_up_animation_total := 0.0
func _ready() -> void:
	_ensure_quadbot_defaults()
	super._ready()
	_combat_capability = get_actor_capability(&"combat") as CombatCapability
	_ai_targeting_capability = get_actor_capability(&"ai_targeting")
	_rng.randomize()
	_setup_body_projection()
	_setup_quadbot_selection_ring()
	_recalculate_vitals()
	_update_quadbot_selection_visual()


func _process(delta: float) -> void:
	_process_actor_capabilities(delta)
	_process_combat_cooldown(delta)
	_process_ragdoll_impulse_memory(delta)
	_process_ai(delta)
	_process_recovery(delta)
	_recalculate_vitals()
	_process_downed_animation_state(delta)
	_process_combat_animation_state(delta)
	_update_quadbot_animation(delta)
	_update_quadbot_selection_visual()


func _physics_process(delta: float) -> void:
	if life_state != NpcRules.LifeState.ALIVE:
		velocity = Vector3.ZERO
		_stabilize_active_ragdoll(delta)
		return
	if _is_combat_resolution_busy():
		_face_combat_focus()
		process_system_combat_movement(delta)
		return
	if _get_active_combat_target() != null or _current_order_type == OrderType.ATTACK:
		process_system_combat_movement(delta)
		return
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
	combat_stance = clampi(value, NpcRules.CombatStance.AGGRESSIVE, NpcRules.CombatStance.PASSIVE)
	state_changed.emit()


func set_move_target(target: Vector3, issued_by_player: bool = true) -> void:
	if life_state != NpcRules.LifeState.ALIVE:
		return
	if issued_by_player:
		_current_order_type = OrderType.MOVE
		_order_was_player_issued = true
		stop_attack_assignment()
	super.set_move_target(target, issued_by_player)


func assign_attack_target(target_actor: Node, issued_by_player: bool = true, notify_target: bool = true, notify_allies: bool = true) -> bool:
	var combat_job_type := AI_JOB_SCRIPT.JobType.PLAYER_ATTACK if issued_by_player else AI_JOB_SCRIPT.JobType.SELF_DEFENSE
	return _assign_combat_target(target_actor, combat_job_type, issued_by_player, notify_target, notify_allies)


func _assign_combat_target(target_actor: Node, combat_job_type: int, issued_by_player: bool, notify_target: bool, notify_allies: bool) -> bool:
	if target_actor == null or target_actor == self or not is_instance_valid(target_actor):
		return false
	if life_state != NpcRules.LifeState.ALIVE or not _is_valid_combat_target(target_actor):
		return false
	if not can_see_actor_for_combat(target_actor):
		return false
	_break_stealth_for_combat()
	if get_current_combat_target() == target_actor and _get_active_ai_job_type() == combat_job_type:
		return true
	var combat_job = AI_JOB_SCRIPT.new()
	combat_job.job_type = combat_job_type
	combat_job.priority = AI_JOB_SCRIPT.priority_for_type(combat_job_type)
	combat_job.target = target_actor
	combat_job.issued_by_player = issued_by_player
	combat_job.origin_position = global_position
	if _ai_brain != null:
		_ai_brain.request_job(combat_job)
	_current_order_type = OrderType.ATTACK
	_order_was_player_issued = issued_by_player
	_current_attack_target = target_actor
	_attack_origin_position = global_position
	COMBAT_COORDINATOR.register_combat_target(self, target_actor)
	_sync_active_combat_actor_group()
	mark_hostile(target_actor)
	if target_actor.has_method("mark_hostile"):
		target_actor.call("mark_hostile", self)
	if notify_target and target_actor.has_method("notify_incoming_attack"):
		target_actor.call("notify_incoming_attack", self)
	if notify_allies:
		_notify_defensive_allies_of_engagement(target_actor)
	combat_state_changed.emit()
	return true


func stop_attack_assignment() -> void:
	_current_attack_target = null
	_attack_origin_position = global_position
	if _ai_brain != null:
		_ai_brain.clear_combat_job()
	COMBAT_COORDINATOR.release_character(self)
	if _current_order_type == OrderType.ATTACK:
		_current_order_type = OrderType.NONE
	_sync_active_combat_actor_group()
	combat_state_changed.emit()


func get_current_combat_target() -> Node:
	return _get_active_combat_target()


func is_ready_for_combat_exchange(target: Node) -> bool:
	if not _is_valid_combat_target(target):
		return false
	if _get_active_combat_target() != target:
		return false
	if not _is_combat_resolution_ready():
		return false
	if COMBAT_COORDINATOR.is_character_locked(self):
		return false
	return _horizontal_distance_to((target as Node3D).global_position) <= _get_effective_combat_attack_range()


func notify_incoming_attack(attacker: Node) -> void:
	if attacker == null or attacker == self or not is_instance_valid(attacker):
		return
	if life_state != NpcRules.LifeState.ALIVE or is_protected_from_combat():
		return
	mark_hostile(attacker)
	if attacker.has_method("mark_hostile"):
		attacker.call("mark_hostile", self)
	_last_direct_attacker_id = attacker.get_instance_id()
	_notify_defensive_allies_of_attack(attacker)
	if combat_stance != NpcRules.CombatStance.PASSIVE:
		_try_start_self_defense(attacker)


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


static func make_varied_skill_levels(seed: int, base_level := QUADBOT_SKILL_BASE_LEVEL) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
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


func _get_combat_capability() -> CombatCapability:
	if _combat_capability == null:
		_combat_capability = get_actor_capability(&"combat") as CombatCapability
	return _combat_capability


func _get_ai_targeting_capability():
	if _ai_targeting_capability == null:
		_ai_targeting_capability = get_actor_capability(&"ai_targeting")
	return _ai_targeting_capability


func _process_combat_cooldown(_delta: float) -> void:
	pass


func _is_combat_resolution_busy() -> bool:
	return _system_combat_action_active or _system_combat_reaction_remaining > 0.0


func _is_combat_resolution_ready() -> bool:
	return not _is_combat_resolution_busy() and _system_combat_cooldown_remaining <= 0.0


func _get_combat_focus_actor() -> Node:
	if _system_combat_focus_id != 0:
		return instance_from_id(_system_combat_focus_id) as Node
	return null


func _process_combat_animation_state(_delta: float) -> void:
	pass


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


func _pick_combat_block_reaction_clip(_has_shield_block: bool) -> String:
	return ""


func _pick_combat_hit_reaction_clip(_attack_id: String, _hit_reaction_names: Array[String]) -> String:
	return ""


func _play_combat_reaction_clip(_animation_name: String) -> float:
	return 0.0


func _roll_combat_action_damage() -> Dictionary:
	return roll_combat_attack_damage(_rng)


func _roll_combat_resolution_chance() -> float:
	return _rng.randf()


func _get_default_combat_action_seconds() -> float:
	return DEFAULT_COMBAT_ACTION_SECONDS


func _get_default_combat_impact_ratio() -> float:
	return DEFAULT_COMBAT_IMPACT_RATIO


func _process_ai(delta: float) -> void:
	if life_state != NpcRules.LifeState.ALIVE:
		if _ai_brain != null and _ai_brain.has_active_job():
			_ai_brain.clear_active_job()
		_sync_active_combat_actor_group()
		return
	_clear_invalid_ai_job()
	if _ai_brain != null:
		_tick_active_ai_job(delta)
	if _current_attack_target != null and not _is_valid_active_combat_target(_current_attack_target):
		stop_attack_assignment()
	# Fast path: already engaging the targeting system's current pick — skip the retarget machinery.
	if _system_target_id != 0:
		var engaged_target := _get_active_combat_target()
		if engaged_target != null and engaged_target.get_instance_id() == _system_target_id:
			return
	if should_run_close_combat_retarget(delta):
		if _try_reconfigure_system_combat_target():
			return
	if _get_active_combat_target() != null:
		return
	if not _should_run_ai_decision_tick(delta):
		return
	if _should_seek_combat_target():
		var target := _get_system_combat_target()
		if target != null:
			assign_attack_target(target, false)


func _should_run_ai_decision_tick(delta: float) -> bool:
	_ai_tick_remaining -= delta
	if _ai_tick_remaining > 0.0:
		return false
	var interval := ACTIVE_AI_DECISION_INTERVAL if player_party_member or _get_active_combat_target() != null else BACKGROUND_AI_DECISION_INTERVAL
	var jitter := ACTIVE_AI_DECISION_JITTER if player_party_member or _get_active_combat_target() != null else BACKGROUND_AI_DECISION_JITTER
	_ai_tick_remaining = interval + _rng.randf_range(0.0, jitter)
	return true


func _clear_invalid_ai_job() -> void:
	if _ai_brain != null and _ai_brain.active_job != null and (not _ai_brain.active_job.is_valid_for(self) or (_ai_brain.active_job.is_combat() and not _is_valid_active_combat_target(_ai_brain.active_job.target))):
		_ai_brain.clear_active_job()
		if _get_active_combat_target() == null:
			COMBAT_COORDINATOR.clear_combat_target(self)
		_sync_active_combat_actor_group()


func _get_active_combat_target() -> Node:
	if _current_order_type == OrderType.ATTACK and _is_valid_active_combat_target(_current_attack_target):
		return _current_attack_target
	if _ai_brain != null:
		var ai_target := _ai_brain.get_active_combat_target() as Node
		if _is_valid_active_combat_target(ai_target):
			return ai_target
	return null


func _is_valid_combat_target(target: Node) -> bool:
	if target == null or not is_instance_valid(target) or not (target is Node3D):
		return false
	var target_life_state = target.get("life_state")
	return target_life_state != null and int(target_life_state) == NpcRules.LifeState.ALIVE and not _is_actor_protected_from_combat(target)


func _is_valid_active_combat_target(target: Node) -> bool:
	return _is_valid_combat_target(target) and has_hostility_with(target) and can_see_actor_for_combat(target)


func _get_active_ai_job_type() -> int:
	return _ai_brain.get_active_job_type() if _ai_brain != null else AI_JOB_SCRIPT.JobType.NONE


func _is_active_ai_combat_player_issued() -> bool:
	return _ai_brain != null and _ai_brain.has_active_combat_job() and _ai_brain.is_active_job_player_issued()


func _is_player_order_to_avoid_combat() -> bool:
	return has_active_player_order()


func _try_reconfigure_close_combat_target() -> bool:
	var targeting = _get_ai_targeting_capability()
	return targeting.try_reconfigure_close_combat_target() if targeting != null else false


func _should_seek_combat_target() -> bool:
	var targeting = _get_ai_targeting_capability()
	return targeting.should_seek_combat_target() if targeting != null else false


func _find_ai_target() -> Node:
	var targeting = _get_ai_targeting_capability()
	return targeting.find_ai_target() if targeting != null else null


func _try_start_self_defense(attacker: Node) -> void:
	var targeting = _get_ai_targeting_capability()
	if targeting != null:
		targeting.try_start_self_defense(attacker)


func _clear_combat_target_for_direct_self_defense() -> void:
	if _ai_brain != null and _ai_brain.has_active_combat_job():
		_ai_brain.clear_combat_job()
	_current_attack_target = null
	COMBAT_COORDINATOR.clear_combat_target(self)
	if _current_order_type == OrderType.ATTACK:
		_current_order_type = OrderType.NONE
	_sync_active_combat_actor_group()


func _notify_defensive_allies_of_attack(attacker: Node) -> void:
	var targeting = _get_ai_targeting_capability()
	if targeting != null:
		targeting.notify_defensive_allies_of_attack(attacker)


func _notify_defensive_allies_of_engagement(target: Node) -> void:
	var targeting = _get_ai_targeting_capability()
	if targeting != null:
		targeting.notify_defensive_allies_of_engagement(target)


func _respond_to_ally_under_attack(ally, attacker, support_targets: Array = []) -> void:
	var targeting = _get_ai_targeting_capability()
	if targeting != null:
		targeting.respond_to_ally_under_attack(ally, attacker, support_targets)


func _respond_to_ally_engagement(ally, target, support_targets: Array = []) -> void:
	var targeting = _get_ai_targeting_capability()
	if targeting != null:
		targeting.respond_to_ally_engagement(ally, target, support_targets)


func _should_help_against(protected_actor, threat, _allow_public_intervention: bool) -> bool:
	if protected_actor == null or threat == null or threat == self:
		return false
	if not _is_alive_combat_actor(protected_actor) or not _is_alive_combat_actor(threat):
		return false
	if _actors_have_hostility(self, protected_actor):
		return false
	return _are_party_allies(protected_actor) or _are_squad_allies(protected_actor) or _actors_have_hostility(self, threat)


func _find_humanoid_by_instance_id(instance_id: int) -> Node:
	var query_controller := _get_runtime_controller("actor_query_controller")
	if query_controller != null and query_controller.has_method("get_actor_by_instance_id"):
		var indexed_actor := query_controller.call("get_actor_by_instance_id", instance_id) as HumanoidCharacter
		if indexed_actor != null:
			return indexed_actor
	return null


func _is_alive_combat_actor(actor) -> bool:
	if actor == null or not is_instance_valid(actor) or not (actor is Node3D):
		return false
	var life_state_value = actor.get("life_state")
	return life_state_value != null and int(life_state_value) == NpcRules.LifeState.ALIVE


func _actors_have_hostility(actor_a, actor_b) -> bool:
	return actor_a != null and actor_a.has_method("has_hostility_with") and bool(actor_a.call("has_hostility_with", actor_b))


func _are_party_allies(other) -> bool:
	return other != null and player_party_member and bool(other.get("player_party_member"))


func _are_squad_allies(other) -> bool:
	var own_squad := get_actor_squad_id()
	return not own_squad.is_empty() and other != null and other.has_method("get_actor_squad_id") and own_squad == str(other.call("get_actor_squad_id"))


func _sync_active_combat_actor_group() -> void:
	var active_target := _get_active_combat_target()
	set_shared_combat_target(active_target)
	if active_target != null:
		add_to_group(ACTIVE_COMBAT_ACTOR_GROUP)
	else:
		remove_from_group(ACTIVE_COMBAT_ACTOR_GROUP)


func _get_effective_combat_attack_range() -> float:
	return get_attack_range() + maxf(COMBAT_RANGE_HYSTERESIS, combat_attack_forgiveness_buffer)


func _horizontal_distance_to(world_position: Vector3) -> float:
	var offset := world_position - global_position
	offset.y = 0.0
	return offset.length()


func _face_character(character: Node) -> void:
	if character is Node3D:
		_face_world_position((character as Node3D).global_position)


func _face_world_position(world_position: Vector3) -> void:
	var look_position := world_position
	look_position.y = global_position.y
	if global_position.distance_squared_to(look_position) > 0.0001:
		look_at(look_position, Vector3.UP)


func _face_combat_focus() -> void:
	var focus_actor := _get_combat_focus_actor()
	if focus_actor != null:
		_face_character(focus_actor)
		return
	var target := _get_active_combat_target()
	if target != null:
		_face_character(target)


func _get_actor_move_speed() -> float:
	return move_speed * QUADBOT_RUN_SPEED_MULTIPLIER if running else move_speed


func _on_actor_move_target_reached() -> void:
	if _current_order_type == OrderType.MOVE:
		_current_order_type = OrderType.NONE
		_order_was_player_issued = false


func _on_actor_move_target_unreachable() -> void:
	_on_actor_move_target_reached()


func _is_downed_recovery_locked() -> bool:
	return true


func _enter_unconscious_state() -> void:
	_enter_downed_life_state(NpcRules.LifeState.UNCONSCIOUS, 15.0, "Offline", Color(0.48, 0.62, 0.72, 1.0))


func _enter_recovery_coma_state() -> void:
	_enter_downed_life_state(NpcRules.LifeState.RECOVERY_COMA, 15.0, "Offline", Color(0.48, 0.62, 0.72, 1.0))


func _enter_downed_life_state(next_life_state: int, recover_delay: float, notice: String, notice_color: Color) -> void:
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
	stop_attack_assignment()
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
	stop_attack_assignment()
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


func _spend_fatigue(_amount: float) -> void:
	pass


func _award_combat_attack_xp() -> void:
	add_skill_xp(SkillRules.COMBAT_UNARMED, 0.85, "combat_attack")


func _award_toughness_xp(real_damage: float) -> void:
	if real_damage > 0.0:
		add_skill_xp(SkillRules.ATTRIBUTE_TOUGHNESS, real_damage * 0.18, "damage_taken")


func _break_stealth_for_combat() -> void:
	if sneaking:
		sneaking = false
		state_changed.emit()


func _is_incoming_law_arrest(_attacker: Node) -> bool:
	return false


func _is_nonlethal_authority_arrest_attack(_attacker: Node) -> bool:
	return false


func _clamp_nonlethal_arrest_damage(final_blunt: float, _final_cut: float) -> Dictionary:
	return {"blunt": final_blunt, "cut": 0.0}


func _ensure_quadbot_defaults() -> void:
	character_race = QUADBOT_RACE
	body_archetype = QUADBOT_BODY_ARCHETYPE
	visual_body_type = VisualBodyType.NONE
	base_attack_damage = 18.0
	attack_range = maxf(attack_range, 1.35)
	move_speed = maxf(move_speed, 3.35)
	max_hp = QUADBOT_BASE_MAX_HULL
	hp = max_hp
	base_max_blood = QUADBOT_BASE_MAX_OIL
	max_blood = QUADBOT_BASE_MAX_OIL
	blood = max_blood
	hunger_enabled = false
	fatigue_enabled = false
	_ensure_quadbot_skill_defaults()
	_ensure_quadbot_appearance_defaults()


func _ensure_quadbot_skill_defaults() -> void:
	var defaults := make_varied_skill_levels(_quadbot_skill_seed())
	for skill_id_value in starting_skill_levels.keys():
		var skill_id := str(skill_id_value)
		if not skill_id.is_empty():
			defaults[skill_id] = int(starting_skill_levels[skill_id_value])
	for definition in SkillRules.get_all_definitions():
		if definition == null:
			continue
		var skill_id := str(definition.get("skill_id"))
		if skill_id.is_empty() or defaults.has(skill_id):
			continue
		defaults[skill_id] = QUADBOT_SKILL_BASE_LEVEL
	starting_skill_levels = defaults


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
