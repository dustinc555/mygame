extends Node

class_name PerceptionController

const SAMPLE_OFFSETS: Array[Vector3] = [
	Vector3(0.0, 0.65, 0.0),
	Vector3(0.0, 1.15, 0.0),
	Vector3(-0.28, 1.15, 0.0),
	Vector3(0.28, 1.15, 0.0),
	Vector3(0.0, 1.65, 0.0),
]
const BARK_LINES: Array[String] = [
	"... what are you doing?",
	"Hey. Why are you sneaking around?",
	"I can see you.",
	"You lost?",
	"That looks suspicious.",
	"Step out where I can see you.",
	"What are you hiding?",
	"Don't creep around here.",
	"Careful. I'm watching.",
	"That's close enough.",
]
const SNEAK_DETECTION_PERCEPTION_XP_PER_SECOND := 0.08
const SNEAKING_RISK_XP_PER_SECOND := 5.0
const SNEAKING_RISK_SCORE_FLOOR := 0.02
const SNEAKING_RISK_PRESSURE_CAP := 1.0
const SNEAKING_IDLE_XP_MULTIPLIER := 0.5
const SNEAKING_MOVING_SPEED_THRESHOLD := 0.18
const SNEAKING_OBSERVER_GRACE_LEVELS := 4.0
const SNEAKING_OBSERVER_FADE_LEVELS := 12.0
const SNEAKING_NOVICE_MIN_TRAINING_PRESSURE := 0.45
const SNEAKING_NOVICE_PRESSURE_FLOOR_END_LEVEL := 10.0
const SUSTAINED_MOVING_EXPOSURE_MIN_LIGHT := 0.25
const SUSTAINED_MOVING_EXPOSURE_SCORE_CAP := 0.22
const SUSTAINED_MOVING_EXPOSURE_IDLE_DECAY_PER_SECOND := 0.75

@export var observer_radius := 18.0
@export var view_distance := 15.0
@export var view_cone_degrees := 105.0
@export var clear_seen_threshold := 0.36
@export var partial_seen_threshold := 0.14
@export var standing_posture_visibility := 1.0
@export var novice_sneak_posture_visibility := 0.98
@export var master_sneak_posture_visibility := 0.18
@export var sneak_posture_skill_curve := 0.75
@export var sneak_contested_skill_curve := 28.0
@export var novice_close_reveal_multiplier := 1.12
@export var master_close_reveal_multiplier := 0.12
@export var close_reveal_skill_curve := 0.8
@export var novice_clear_los_visibility_floor := 0.35
@export var novice_suspicion_seconds := 0.55
@export var master_suspicion_seconds := 4.0
@export var bark_chance := 0.55
@export var bark_min_grace := 0.28
@export var bark_max_grace := 0.72
@export var bark_min_cooldown := 7.0
@export var bark_max_cooldown := 12.0
@export var perception_tick_seconds := 0.12
@export var light_cache_seconds := 0.5

var root_scene: Node
var hud_layer: CanvasLayer
var party_manager: PartyManager
var world_time: WorldTimeController
var day_night_lighting: DayNightLightingController
var actor_query_controller: Node
var camera: Camera3D
var debug_show_los_rays := false

var _latest_results_by_subject: Dictionary = {}
var _latest_results_by_pair: Dictionary = {}
var _indicators: Dictionary = {}
var _bark_states: Dictionary = {}
var _suspicion_states: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _debug_ray_mesh_instance: MeshInstance3D
var _debug_ray_mesh := ImmediateMesh.new()
var _debug_ray_material := StandardMaterial3D.new()
var _initialized := false
var _perception_tick_accumulator := 0.0
var _local_light_cache: Array[Light3D] = []
var _local_light_cache_remaining := 0.0


func initialize(target_root: Node, target_hud: CanvasLayer = null) -> void:
	root_scene = target_root
	hud_layer = target_hud
	_try_initialize()


func _ready() -> void:
	_rng.randomize()
	_try_initialize()


func _process(delta: float) -> void:
	_try_initialize()
	if party_manager == null or root_scene == null:
		return
	_local_light_cache_remaining = maxf(0.0, _local_light_cache_remaining - delta)
	var active_subjects := _get_active_sneaking_subjects()
	if active_subjects.is_empty():
		_perception_tick_accumulator = maxf(perception_tick_seconds, 0.0)
		_clear_perception_state()
		return
	_perception_tick_accumulator += delta
	var should_update := _latest_results_by_subject.is_empty()
	for subject in active_subjects:
		if not _latest_results_by_subject.has(subject.get_instance_id()):
			should_update = true
			break
	var tick_seconds := maxf(perception_tick_seconds, 0.0)
	if not should_update and tick_seconds > 0.0 and _perception_tick_accumulator < tick_seconds:
		return
	var update_delta := maxf(_perception_tick_accumulator, delta)
	_perception_tick_accumulator = 0.0
	_update_perception(update_delta, active_subjects)


func get_latest_results_for_subject(subject: HumanoidCharacter) -> Array[Dictionary]:
	if subject == null:
		return []
	var raw_results: Array = _latest_results_by_subject.get(subject.get_instance_id(), []) as Array
	var results: Array[Dictionary] = []
	for result in raw_results:
		if result is Dictionary:
			results.append(result)
	return results


func get_latest_result(observer: HumanoidCharacter, subject: HumanoidCharacter) -> Dictionary:
	if observer == null or subject == null:
		return {}
	return (_latest_results_by_pair.get(_pair_key(observer, subject), {}) as Dictionary).duplicate()


func evaluate_observer(observer: HumanoidCharacter, subject: HumanoidCharacter) -> Dictionary:
	return _evaluate_observer(observer, subject, -1.0, debug_show_los_rays)


func is_clearly_seen_by_anyone(subject: HumanoidCharacter) -> bool:
	for result in get_latest_results_for_subject(subject):
		if bool(result.get("clearly_seen", false)):
			return true
	return false


func _try_initialize() -> void:
	if _initialized:
		return
	if root_scene == null or not is_inside_tree():
		return
	if party_manager == null:
		party_manager = root_scene.get_node_or_null("PartyManager") as PartyManager
	if world_time == null:
		world_time = get_parent().get_node_or_null("WorldTimeController") as WorldTimeController
	if day_night_lighting == null:
		day_night_lighting = get_parent().get_node_or_null("DayNightLightingController") as DayNightLightingController
	if actor_query_controller == null:
		actor_query_controller = get_parent().get_node_or_null("ActorQueryController")
	if camera == null:
		camera = root_scene.get_node_or_null("CameraRig/CameraPivot/Camera3D") as Camera3D
	if party_manager == null:
		return
	_ensure_debug_ray_mesh()
	add_to_group("perception_controller")
	_initialized = true


func _update_perception(delta: float, active_subjects: Array[HumanoidCharacter]) -> void:
	var observer_candidates := _get_alive_non_party_observers()
	var local_lights := _get_local_lights()
	var active_keys: Dictionary = {}
	var next_by_subject: Dictionary = {}
	var next_by_pair: Dictionary = {}
	var debug_segments: Array[Dictionary] = []
	for subject in active_subjects:
		var subject_results: Array[Dictionary] = []
		var subject_light_exposure := _calculate_light_exposure(subject, local_lights)
		var best_training_pressure := 0.0
		for observer in _get_observers_for_subject(subject, observer_candidates):
			var key := _pair_key(observer, subject)
			var result := _evaluate_observer(observer, subject, subject_light_exposure, debug_show_los_rays)
			result = _apply_suspicion_memory(delta, key, result)
			_award_observer_perception_xp(delta, observer, result)
			var training_pressure := _get_sneaking_training_pressure(result)
			result["sneak_training_pressure"] = training_pressure
			best_training_pressure = maxf(best_training_pressure, training_pressure)
			active_keys[key] = true
			next_by_pair[key] = result
			subject_results.append(result)
			_update_indicator(key, observer, subject, result)
			_update_bark_state(delta, key, observer, result)
			if debug_show_los_rays:
				for segment in result.get("sample_segments", []):
					debug_segments.append(segment)
		var subject_sneaking_xp := _get_sneaking_risk_xp(delta, best_training_pressure, _get_sneaking_activity_multiplier(subject))
		if subject_sneaking_xp > 0.0:
			subject.add_skill_xp(SkillRules.SUBTERFUGE_SNEAKING, subject_sneaking_xp, "sneaking_risk")
		next_by_subject[subject.get_instance_id()] = subject_results
	_latest_results_by_subject = next_by_subject
	_latest_results_by_pair = next_by_pair
	_remove_inactive_indicators(active_keys)
	_update_debug_rays(debug_segments)


func _clear_perception_state() -> void:
	if _latest_results_by_subject.is_empty() and _latest_results_by_pair.is_empty() and _indicators.is_empty() and _bark_states.is_empty() and _suspicion_states.is_empty():
		return
	_latest_results_by_subject.clear()
	_latest_results_by_pair.clear()
	_suspicion_states.clear()
	_remove_inactive_indicators({})
	_update_debug_rays([])


func _get_active_sneaking_subjects() -> Array[HumanoidCharacter]:
	var subjects: Array[HumanoidCharacter] = []
	if party_manager == null:
		return subjects
	for member in party_manager.selected_members:
		if member is HumanoidCharacter and member.sneaking and member.life_state == NpcRules.LifeState.ALIVE:
			subjects.append(member)
	return subjects

func _get_alive_non_party_observers() -> Array[HumanoidCharacter]:
	var observers: Array[HumanoidCharacter] = []
	var candidates: Array = actor_query_controller.call("get_alive_humanoids", false) if actor_query_controller != null and actor_query_controller.has_method("get_alive_humanoids") else get_tree().get_nodes_in_group("npc_character")
	for node in candidates:
		if not (node is HumanoidCharacter):
			continue
		var observer := node as HumanoidCharacter
		if observer.player_party_member or observer.life_state != NpcRules.LifeState.ALIVE:
			continue
		observers.append(observer)
	return observers


func _get_observers_for_subject(subject: HumanoidCharacter, observer_candidates: Array[HumanoidCharacter]) -> Array[HumanoidCharacter]:
	var observers: Array[HumanoidCharacter] = []
	var observer_radius_squared := observer_radius * observer_radius
	for observer in observer_candidates:
		if observer == null or not is_instance_valid(observer):
			continue
		if observer == subject or observer.life_state != NpcRules.LifeState.ALIVE:
			continue
		if observer.global_position.distance_squared_to(subject.global_position) > observer_radius_squared:
			continue
		observers.append(observer)
	return observers


func _evaluate_observer(observer: HumanoidCharacter, subject: HumanoidCharacter, cached_light_exposure := -1.0, collect_debug_segments := false) -> Dictionary:
	if observer == null or subject == null:
		return {}
	var eye_position := observer.global_position + Vector3(0.0, 1.65, 0.0)
	var visible_samples := 0
	var cone_samples := 0
	var segments: Array[Dictionary] = []
	var max_distance_factor := 0.0
	var nearest_visible_distance := INF
	var ray_exclusions: Array[RID] = [observer.get_rid(), subject.get_rid()]
	for offset in SAMPLE_OFFSETS:
		var sample_position := subject.global_position + offset
		var to_sample := sample_position - eye_position
		var distance := to_sample.length()
		var in_cone := distance <= view_distance and _is_in_front_cone(observer, to_sample)
		var clear_los := false
		if in_cone:
			cone_samples += 1
			clear_los = _has_clear_ray(eye_position, sample_position, ray_exclusions)
			if clear_los:
				visible_samples += 1
				max_distance_factor = maxf(max_distance_factor, _distance_factor(distance, view_distance))
				nearest_visible_distance = minf(nearest_visible_distance, distance)
		if collect_debug_segments:
			segments.append({"from": eye_position, "to": sample_position, "visible": in_cone and clear_los})
	var los_fraction := float(visible_samples) / float(SAMPLE_OFFSETS.size())
	var light_exposure := cached_light_exposure
	if light_exposure < 0.0:
		light_exposure = _calculate_light_exposure(subject, _get_local_lights())
	var subject_sneaking := float(subject.get_skill_level(SkillRules.SUBTERFUGE_SNEAKING))
	var observer_perception := float(observer.get_skill_level(SkillRules.ATTRIBUTE_PERCEPTION))
	var posture := _get_posture_visibility(subject, subject_sneaking)
	var base_visibility_score := los_fraction * light_exposure * max_distance_factor * posture
	var skill_gap := subject_sneaking - observer_perception
	var contested_multiplier := exp(-maxf(skill_gap, 0.0) / maxf(sneak_contested_skill_curve, 0.001))
	if skill_gap < 0.0:
		contested_multiplier = 1.0 + SkillRules.get_diminishing_bonus(-skill_gap, 0.65, 35.0)
	var close_ratio := 0.0
	if nearest_visible_distance < INF:
		close_ratio = clampf(1.0 - (nearest_visible_distance - 1.0) / 3.0, 0.0, 1.0)
	var close_reveal := los_fraction * light_exposure * posture * close_ratio * _get_close_reveal_multiplier(subject_sneaking, observer_perception)
	var novice_visibility_floor := _get_novice_clear_los_visibility_floor(subject_sneaking, observer_perception, los_fraction, max_distance_factor, close_ratio)
	var visibility_score := clampf(maxf(base_visibility_score * contested_multiplier + close_reveal, novice_visibility_floor), 0.0, 1.0)
	return {
		"observer": observer,
		"subject": subject,
		"observer_id": observer.get_instance_id(),
		"subject_id": subject.get_instance_id(),
		"line_of_sight_fraction": los_fraction,
		"cone_fraction": float(cone_samples) / float(SAMPLE_OFFSETS.size()),
		"light_exposure": light_exposure,
		"distance_factor": max_distance_factor,
		"posture_visibility": posture,
		"observer_perception": observer_perception,
		"subject_sneaking": subject_sneaking,
		"contested_multiplier": contested_multiplier,
		"close_reveal": close_reveal,
		"novice_visibility_floor": novice_visibility_floor,
		"base_visibility_score": base_visibility_score,
		"visibility_score": visibility_score,
		"clearly_seen": visibility_score >= clear_seen_threshold,
		"partially_seen": visibility_score >= partial_seen_threshold and visibility_score < clear_seen_threshold,
		"sample_segments": segments,
	}


func _award_observer_perception_xp(delta: float, observer: HumanoidCharacter, result: Dictionary) -> void:
	if observer == null:
		return
	if bool(result.get("clearly_seen", false)):
		observer.add_skill_xp(SkillRules.ATTRIBUTE_PERCEPTION, SNEAK_DETECTION_PERCEPTION_XP_PER_SECOND * delta, "sneak_detection")
	elif bool(result.get("partially_seen", false)):
		observer.add_skill_xp(SkillRules.ATTRIBUTE_PERCEPTION, SNEAK_DETECTION_PERCEPTION_XP_PER_SECOND * 0.35 * delta, "sneak_detection")


func _get_sneaking_training_pressure(result: Dictionary) -> float:
	if bool(result.get("clearly_seen", false)):
		return 0.0
	if float(result.get("line_of_sight_fraction", 0.0)) <= 0.0 or float(result.get("cone_fraction", 0.0)) <= 0.0:
		return 0.0
	var score := float(result.get("visibility_score", 0.0))
	if score <= SNEAKING_RISK_SCORE_FLOOR:
		return 0.0
	var visibility_pressure := clampf(score / maxf(clear_seen_threshold, 0.001), 0.1, 1.0)
	var subject_sneaking := float(result.get("subject_sneaking", SkillRules.DEFAULT_LEVEL))
	var observer_perception := float(result.get("observer_perception", SkillRules.DEFAULT_LEVEL))
	var observer_relevance := _get_sneaking_observer_relevance(subject_sneaking, observer_perception)
	if observer_relevance <= 0.0:
		return 0.0
	var challenge_gap := observer_perception - subject_sneaking
	var challenge_pressure := 1.0
	if challenge_gap >= 0.0:
		challenge_pressure += SkillRules.get_diminishing_bonus(challenge_gap, 0.55, 35.0)
	var pressure := visibility_pressure * challenge_pressure * observer_relevance
	var novice_floor_ratio := clampf((SNEAKING_NOVICE_PRESSURE_FLOOR_END_LEVEL - subject_sneaking) / maxf(SNEAKING_NOVICE_PRESSURE_FLOOR_END_LEVEL - float(SkillRules.DEFAULT_LEVEL), 0.001), 0.0, 1.0)
	var novice_floor := SNEAKING_NOVICE_MIN_TRAINING_PRESSURE * novice_floor_ratio * observer_relevance
	return maxf(pressure, novice_floor)


func _get_sneaking_observer_relevance(subject_sneaking: float, observer_perception: float) -> float:
	var overmatch := subject_sneaking - observer_perception
	if overmatch <= SNEAKING_OBSERVER_GRACE_LEVELS:
		return 1.0
	var fade_ratio := clampf((overmatch - SNEAKING_OBSERVER_GRACE_LEVELS) / maxf(SNEAKING_OBSERVER_FADE_LEVELS, 0.001), 0.0, 1.0)
	return pow(1.0 - fade_ratio, 1.5)


func _get_sneaking_risk_xp(delta: float, raw_pressure: float, activity_multiplier: float) -> float:
	if raw_pressure <= 0.0 or activity_multiplier <= 0.0:
		return 0.0
	var capped_pressure := SNEAKING_RISK_PRESSURE_CAP * (1.0 - exp(-raw_pressure / maxf(SNEAKING_RISK_PRESSURE_CAP, 0.001)))
	return SNEAKING_RISK_XP_PER_SECOND * capped_pressure * activity_multiplier * delta


func _get_sneaking_activity_multiplier(subject: HumanoidCharacter) -> float:
	if subject == null or not subject.sneaking:
		return 0.0
	var horizontal_speed_squared := subject.velocity.x * subject.velocity.x + subject.velocity.z * subject.velocity.z
	if horizontal_speed_squared >= SNEAKING_MOVING_SPEED_THRESHOLD * SNEAKING_MOVING_SPEED_THRESHOLD:
		return 1.0
	return SNEAKING_IDLE_XP_MULTIPLIER


func _get_posture_visibility(subject: HumanoidCharacter, subject_sneaking: float) -> float:
	if subject == null or not subject.sneaking:
		return standing_posture_visibility
	var skill_ratio := _get_sneak_mastery_ratio(subject_sneaking)
	var mastery := pow(skill_ratio, maxf(sneak_posture_skill_curve, 0.001))
	return lerpf(novice_sneak_posture_visibility, master_sneak_posture_visibility, mastery)


func _get_close_reveal_multiplier(subject_sneaking: float, observer_perception: float) -> float:
	var skill_ratio := _get_sneak_mastery_ratio(subject_sneaking)
	var mastery := pow(skill_ratio, maxf(close_reveal_skill_curve, 0.001))
	var sneak_multiplier := lerpf(novice_close_reveal_multiplier, master_close_reveal_multiplier, mastery)
	var observer_pressure := 1.0 + SkillRules.get_diminishing_bonus(observer_perception, 0.22, 35.0)
	return sneak_multiplier * observer_pressure


func _get_novice_clear_los_visibility_floor(subject_sneaking: float, observer_perception: float, los_fraction: float, distance_factor: float, close_ratio: float) -> float:
	if los_fraction <= 0.0:
		return 0.0
	var novice_factor := clampf((10.0 - subject_sneaking) / 9.0, 0.0, 1.0)
	if novice_factor <= 0.0:
		return 0.0
	var observer_pressure := 0.85 + SkillRules.get_diminishing_bonus(observer_perception, 0.35, 35.0)
	var floor_score := novice_clear_los_visibility_floor * novice_factor * los_fraction * distance_factor * observer_pressure
	floor_score += 0.12 * novice_factor * los_fraction * close_ratio * observer_pressure
	return floor_score


func _get_sneak_mastery_ratio(subject_sneaking: float) -> float:
	return clampf((subject_sneaking - float(SkillRules.DEFAULT_LEVEL)) / 79.0, 0.0, 1.0)


func _apply_suspicion_memory(delta: float, key: String, result: Dictionary) -> Dictionary:
	var state: Dictionary = _suspicion_states.get(key, {})
	result = _apply_sustained_moving_exposure(delta, result, state)
	var suspicion := float(state.get("suspicion", 0.0))
	var threshold := _get_suspicion_threshold(result)
	if bool(result.get("clearly_seen", false)):
		suspicion = threshold
	elif bool(result.get("partially_seen", false)):
		suspicion += delta * _get_suspicion_charge_multiplier(result)
	else:
		suspicion = maxf(0.0, suspicion - delta * 1.35)
	var escalated := not bool(result.get("clearly_seen", false)) and bool(result.get("partially_seen", false)) and suspicion >= threshold
	if escalated:
		result["visibility_score"] = maxf(float(result.get("visibility_score", 0.0)), clear_seen_threshold)
		result["clearly_seen"] = true
		result["partially_seen"] = false
	result["suspicion_escalated"] = escalated
	result["suspicion_progress"] = clampf(suspicion / maxf(threshold, 0.001), 0.0, 1.0)
	result["suspicion_threshold"] = threshold
	state["suspicion"] = minf(suspicion, threshold)
	_suspicion_states[key] = state
	return result


func _apply_sustained_moving_exposure(delta: float, result: Dictionary, state: Dictionary) -> Dictionary:
	var exposure := float(state.get("sustained_moving_exposure", 0.0))
	var cone_fraction := float(result.get("cone_fraction", 0.0))
	var los_fraction := float(result.get("line_of_sight_fraction", 0.0))
	if cone_fraction <= 0.0 or los_fraction <= 0.0:
		exposure = 0.0
	elif _is_sustained_moving_exposure_active(result):
		exposure = clampf(exposure + delta * _get_sustained_moving_exposure_charge_rate(result), 0.0, 1.0)
	else:
		exposure = maxf(0.0, exposure - delta * SUSTAINED_MOVING_EXPOSURE_IDLE_DECAY_PER_SECOND)
	state["sustained_moving_exposure"] = exposure
	var bonus := exposure * SUSTAINED_MOVING_EXPOSURE_SCORE_CAP
	if bonus > 0.0:
		if not result.has("raw_visibility_score"):
			result["raw_visibility_score"] = float(result.get("visibility_score", 0.0))
		var visibility_score := clampf(float(result.get("visibility_score", 0.0)) + bonus, 0.0, 1.0)
		result["visibility_score"] = visibility_score
		result["clearly_seen"] = visibility_score >= clear_seen_threshold
		result["partially_seen"] = visibility_score >= partial_seen_threshold and visibility_score < clear_seen_threshold
	result["sustained_moving_exposure"] = exposure
	result["sustained_moving_exposure_bonus"] = bonus
	result["sustained_moving_exposure_active"] = _is_sustained_moving_exposure_active(result)
	return result


func _is_sustained_moving_exposure_active(result: Dictionary) -> bool:
	if float(result.get("cone_fraction", 0.0)) <= 0.0 or float(result.get("line_of_sight_fraction", 0.0)) <= 0.0:
		return false
	if float(result.get("light_exposure", 0.0)) <= SUSTAINED_MOVING_EXPOSURE_MIN_LIGHT:
		return false
	var subject := result.get("subject") as HumanoidCharacter
	return subject != null and _get_sneaking_activity_multiplier(subject) >= 1.0


func _get_sustained_moving_exposure_charge_rate(result: Dictionary) -> float:
	var light_pressure := clampf((float(result.get("light_exposure", 0.0)) - SUSTAINED_MOVING_EXPOSURE_MIN_LIGHT) / 0.7, 0.0, 1.0)
	var sight_pressure := clampf(float(result.get("line_of_sight_fraction", 0.0)) * float(result.get("distance_factor", 0.0)), 0.0, 1.0)
	var subject_sneaking := float(result.get("subject_sneaking", SkillRules.DEFAULT_LEVEL))
	var observer_perception := float(result.get("observer_perception", SkillRules.DEFAULT_LEVEL))
	var mastery_resistance := lerpf(1.25, 0.18, _get_sneak_mastery_ratio(subject_sneaking))
	var observer_pressure := 0.75 + SkillRules.get_diminishing_bonus(observer_perception, 0.85, 55.0)
	var challenge_ratio := clampf((observer_perception + 20.0) / maxf(subject_sneaking, 1.0), 0.2, 1.4)
	return light_pressure * sight_pressure * mastery_resistance * observer_pressure * challenge_ratio


func _get_suspicion_threshold(result: Dictionary) -> float:
	var subject_sneaking := float(result.get("subject_sneaking", SkillRules.DEFAULT_LEVEL))
	var observer_perception := float(result.get("observer_perception", SkillRules.DEFAULT_LEVEL))
	var mastery := pow(_get_sneak_mastery_ratio(subject_sneaking), 0.7)
	var threshold := lerpf(novice_suspicion_seconds, master_suspicion_seconds, mastery)
	var observer_pressure := 1.0 + SkillRules.get_diminishing_bonus(observer_perception, 0.45, 35.0)
	return maxf(0.25, threshold / observer_pressure)


func _get_suspicion_charge_multiplier(result: Dictionary) -> float:
	var score := float(result.get("visibility_score", 0.0))
	var score_pressure := clampf((score - partial_seen_threshold) / maxf(clear_seen_threshold - partial_seen_threshold, 0.001), 0.0, 1.0)
	var subject_sneaking := float(result.get("subject_sneaking", SkillRules.DEFAULT_LEVEL))
	var novice_pressure := clampf((20.0 - subject_sneaking) / 19.0, 0.0, 1.0)
	return lerpf(0.85, 1.45, score_pressure) * lerpf(1.25, 1.0, _get_sneak_mastery_ratio(subject_sneaking)) * lerpf(1.0, 1.2, novice_pressure)


func _is_in_front_cone(observer: HumanoidCharacter, to_sample: Vector3) -> bool:
	var flat_to_sample := Vector3(to_sample.x, 0.0, to_sample.z)
	if flat_to_sample.length_squared() <= 0.0001:
		return true
	var forward := -observer.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		return false
	var dot := forward.normalized().dot(flat_to_sample.normalized())
	var half_angle := deg_to_rad(view_cone_degrees) * 0.5
	return dot >= cos(half_angle)


func _has_clear_ray(from: Vector3, to: Vector3, exclusions: Array[RID]) -> bool:
	var world := _get_world_3d()
	if world == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = exclusions
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return world.direct_space_state.intersect_ray(query).is_empty()


func _get_world_3d() -> World3D:
	if root_scene is Node3D:
		return (root_scene as Node3D).get_world_3d()
	var viewport := get_viewport()
	return viewport.world_3d if viewport != null else null


func _distance_factor(distance: float, max_distance: float) -> float:
	var ratio := clampf(distance / maxf(max_distance, 0.001), 0.0, 1.0)
	return clampf(1.0 - ratio * 0.55, 0.0, 1.0)


func _calculate_light_exposure(subject: HumanoidCharacter, local_lights: Array[Light3D]) -> float:
	var exposure := _get_day_night_exposure()
	var sample_position := subject.global_position + Vector3(0.0, 1.1, 0.0)
	for light in local_lights:
		exposure += _get_light_contribution(light, sample_position, subject)
	return clampf(exposure, 0.08, 1.35)


func _get_day_night_exposure() -> float:
	if day_night_lighting != null and day_night_lighting.has_method("get_stealth_ambient_visibility"):
		return float(day_night_lighting.get_stealth_ambient_visibility())
	if world_time == null:
		return 0.75
	var day_fraction := world_time.get_day_fraction()
	var sun_altitude := sin((day_fraction - 0.25) * TAU)
	return lerpf(0.16, 0.95, _smoothstep(-0.08, 0.35, sun_altitude))


func _get_local_lights(force_refresh := false) -> Array[Light3D]:
	if not force_refresh and _local_light_cache_remaining > 0.0:
		return _local_light_cache
	var lights: Array[Light3D] = []
	var seen: Dictionary = {}
	for node in get_tree().get_nodes_in_group("stealth_light_source"):
		if node is Light3D and is_instance_valid(node) and not seen.has(node.get_instance_id()):
			lights.append(node as Light3D)
			seen[node.get_instance_id()] = true
	if root_scene != null:
		_collect_local_lights(root_scene, lights, seen)
	_local_light_cache = lights
	_local_light_cache_remaining = maxf(light_cache_seconds, 0.0)
	return lights


func _collect_local_lights(node: Node, lights: Array[Light3D], seen: Dictionary) -> void:
	if (node is OmniLight3D or node is SpotLight3D) and not seen.has(node.get_instance_id()):
		lights.append(node as Light3D)
		seen[node.get_instance_id()] = true
	for child in node.get_children():
		_collect_local_lights(child, lights, seen)


func _get_light_contribution(light: Light3D, sample_position: Vector3, subject: HumanoidCharacter) -> float:
	if light == null or not is_instance_valid(light) or not light.visible or light.light_energy <= 0.0:
		return 0.0
	if light is OmniLight3D:
		var omni := light as OmniLight3D
		var distance := light.global_position.distance_to(sample_position)
		if distance > omni.omni_range:
			return 0.0
		if not _has_clear_ray(light.global_position, sample_position, [subject.get_rid()]):
			return 0.0
		var ratio := clampf(distance / maxf(omni.omni_range, 0.001), 0.0, 1.0)
		var attenuation := pow(1.0 - ratio, maxf(0.35, omni.omni_attenuation))
		return light.light_energy * attenuation * 0.65
	if light is SpotLight3D:
		var spot := light as SpotLight3D
		var to_sample := sample_position - light.global_position
		var distance := to_sample.length()
		if distance > spot.spot_range or distance <= 0.001:
			return 0.0
		var forward := -light.global_transform.basis.z.normalized()
		var dot := forward.dot(to_sample.normalized())
		if dot < cos(deg_to_rad(spot.spot_angle)):
			return 0.0
		if not _has_clear_ray(light.global_position, sample_position, [subject.get_rid()]):
			return 0.0
		var distance_ratio := clampf(distance / maxf(spot.spot_range, 0.001), 0.0, 1.0)
		var distance_attenuation := pow(1.0 - distance_ratio, maxf(0.35, spot.spot_attenuation))
		var angle_attenuation := pow(clampf(dot, 0.0, 1.0), maxf(0.35, spot.spot_angle_attenuation))
		return light.light_energy * distance_attenuation * angle_attenuation * 0.75
	return 0.0


func _update_indicator(key: String, observer: HumanoidCharacter, subject: HumanoidCharacter, result: Dictionary) -> void:
	var indicator := _indicators.get(key, null) as Node3D
	if indicator == null or not is_instance_valid(indicator):
		indicator = _create_indicator()
		_indicators[key] = indicator
	var score := float(result.get("visibility_score", 0.0))
	indicator.visible = true
	indicator.global_position = observer.global_position + Vector3(0.0, 2.65, 0.0)
	var arrow_root := indicator.get_node_or_null("ArrowRoot") as Node3D
	if arrow_root != null:
		var look_target := Vector3(subject.global_position.x, indicator.global_position.y, subject.global_position.z)
		if indicator.global_position.distance_squared_to(look_target) > 0.001:
			arrow_root.look_at(look_target, Vector3.UP)
	var color := Color(0.2, 0.34, 0.72, 0.42)
	var eye_scale_y := 0.035
	if bool(result.get("clearly_seen", false)):
		color = Color(1.0, 0.2, 0.08, 1.0)
		eye_scale_y = 0.13
	elif bool(result.get("partially_seen", false)):
		color = Color(1.0, 0.68, 0.16, 0.82)
		eye_scale_y = 0.075
	_set_indicator_color(indicator, color, eye_scale_y, score)
	if camera != null:
		var eye_root := indicator.get_node_or_null("EyeRoot") as Node3D
		if eye_root != null:
			eye_root.look_at(camera.global_position, Vector3.UP)


func _create_indicator() -> Node3D:
	var root := Node3D.new()
	root.name = "SneakObserverIndicator"
	root.top_level = true
	root.visible = false
	root_scene.add_child(root)

	var eye_root := Node3D.new()
	eye_root.name = "EyeRoot"
	root.add_child(eye_root)

	var eye := MeshInstance3D.new()
	eye.name = "Eye"
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 1.0
	eye_mesh.height = 2.0
	eye_mesh.radial_segments = 24
	eye_mesh.rings = 12
	eye.mesh = eye_mesh
	eye.scale = Vector3(0.28, 0.08, 0.055)
	eye.material_override = _make_unshaded_material(Color(0.2, 0.34, 0.72, 0.42))
	eye_root.add_child(eye)

	var pupil := MeshInstance3D.new()
	pupil.name = "Pupil"
	var pupil_mesh := SphereMesh.new()
	pupil_mesh.radius = 1.0
	pupil_mesh.height = 2.0
	pupil_mesh.radial_segments = 16
	pupil_mesh.rings = 8
	pupil.mesh = pupil_mesh
	pupil.scale = Vector3(0.07, 0.07, 0.03)
	pupil.position = Vector3(0.0, 0.0, -0.055)
	pupil.material_override = _make_unshaded_material(Color(0.02, 0.015, 0.01, 0.42))
	eye_root.add_child(pupil)

	var arrow_root := Node3D.new()
	arrow_root.name = "ArrowRoot"
	root.add_child(arrow_root)
	var shaft := MeshInstance3D.new()
	shaft.name = "ArrowShaft"
	var shaft_mesh := BoxMesh.new()
	shaft_mesh.size = Vector3(0.055, 0.055, 0.78)
	shaft.mesh = shaft_mesh
	shaft.position = Vector3(0.0, -0.26, -0.52)
	shaft.material_override = _make_unshaded_material(Color(0.2, 0.34, 0.72, 0.30))
	arrow_root.add_child(shaft)
	var head := MeshInstance3D.new()
	head.name = "ArrowHead"
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.18, 0.09, 0.18)
	head.mesh = head_mesh
	head.position = Vector3(0.0, -0.26, -0.94)
	head.rotation.y = deg_to_rad(45.0)
	head.material_override = _make_unshaded_material(Color(0.2, 0.34, 0.72, 0.30))
	arrow_root.add_child(head)

	return root


func _set_indicator_color(indicator: Node3D, color: Color, eye_scale_y: float, score: float) -> void:
	var eye := indicator.get_node_or_null("EyeRoot/Eye") as MeshInstance3D
	if eye != null:
		eye.scale.y = eye_scale_y
		_set_unshaded_material_color(eye, color)
	var pupil := indicator.get_node_or_null("EyeRoot/Pupil") as MeshInstance3D
	if pupil != null:
		pupil.visible = score >= partial_seen_threshold
		_set_unshaded_material_color(pupil, Color(0.02, 0.015, 0.01, color.a))
	var arrow_color := Color(color.r, color.g, color.b, clampf(color.a * 0.72, 0.18, 0.86))
	for node_path in ["ArrowRoot/ArrowShaft", "ArrowRoot/ArrowHead"]:
		var mesh_instance := indicator.get_node_or_null(node_path) as MeshInstance3D
		if mesh_instance != null:
			mesh_instance.visible = score >= 0.02
			_set_unshaded_material_color(mesh_instance, arrow_color)


func _set_unshaded_material_color(mesh_instance: MeshInstance3D, color: Color) -> void:
	var material := mesh_instance.material_override as StandardMaterial3D
	if material == null:
		mesh_instance.material_override = _make_unshaded_material(color)
		return
	material.albedo_color = color


func _make_unshaded_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.no_depth_test = true
	return material


func _remove_inactive_indicators(active_keys: Dictionary) -> void:
	for key in _indicators.keys():
		if active_keys.has(key):
			continue
		var indicator := _indicators.get(key, null) as Node3D
		if indicator != null and is_instance_valid(indicator):
			indicator.queue_free()
		_indicators.erase(key)
	for key in _bark_states.keys():
		if not active_keys.has(key):
			_bark_states.erase(key)
	for key in _suspicion_states.keys():
		if not active_keys.has(key):
			_suspicion_states.erase(key)


func _update_bark_state(delta: float, key: String, observer: HumanoidCharacter, result: Dictionary) -> void:
	var state: Dictionary = _bark_states.get(key, {})
	if state.is_empty():
		state = {"seen_time": 0.0, "threshold": _rng.randf_range(bark_min_grace, bark_max_grace), "cooldown": 0.0}
	state["cooldown"] = maxf(0.0, float(state.get("cooldown", 0.0)) - delta)
	if bool(result.get("clearly_seen", false)):
		state["seen_time"] = float(state.get("seen_time", 0.0)) + delta
		if float(state["seen_time"]) >= float(state["threshold"]) and float(state["cooldown"]) <= 0.0:
			if _rng.randf() <= bark_chance:
				observer.show_world_speech(BARK_LINES[_rng.randi_range(0, BARK_LINES.size() - 1)], 3.2)
			state["cooldown"] = _rng.randf_range(bark_min_cooldown, bark_max_cooldown)
			state["seen_time"] = 0.0
			state["threshold"] = _rng.randf_range(bark_min_grace, bark_max_grace)
	else:
		state["seen_time"] = 0.0
		state["threshold"] = _rng.randf_range(bark_min_grace, bark_max_grace)
	_bark_states[key] = state


func _ensure_debug_ray_mesh() -> void:
	if _debug_ray_mesh_instance != null and is_instance_valid(_debug_ray_mesh_instance):
		return
	if root_scene == null:
		return
	_debug_ray_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debug_ray_material.vertex_color_use_as_albedo = true
	_debug_ray_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_debug_ray_mesh_instance = MeshInstance3D.new()
	_debug_ray_mesh_instance.name = "SneakDebugLosRays"
	_debug_ray_mesh_instance.mesh = _debug_ray_mesh
	_debug_ray_mesh_instance.top_level = true
	_debug_ray_mesh_instance.visible = false
	root_scene.add_child(_debug_ray_mesh_instance)


func _update_debug_rays(segments: Array[Dictionary]) -> void:
	_ensure_debug_ray_mesh()
	if _debug_ray_mesh_instance == null:
		return
	_debug_ray_mesh.clear_surfaces()
	_debug_ray_mesh_instance.visible = debug_show_los_rays and not segments.is_empty()
	if not _debug_ray_mesh_instance.visible:
		return
	_debug_ray_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _debug_ray_material)
	for segment in segments:
		var color := Color(0.2, 1.0, 0.35, 0.9) if bool(segment.get("visible", false)) else Color(1.0, 0.18, 0.12, 0.75)
		_debug_ray_mesh.surface_set_color(color)
		_debug_ray_mesh.surface_add_vertex(segment.get("from", Vector3.ZERO))
		_debug_ray_mesh.surface_add_vertex(segment.get("to", Vector3.ZERO))
	_debug_ray_mesh.surface_end()


func _pair_key(observer: HumanoidCharacter, subject: HumanoidCharacter) -> String:
	return "%d:%d" % [observer.get_instance_id(), subject.get_instance_id()]


func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	var x := clampf((value - edge0) / maxf(edge1 - edge0, 0.0001), 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)
