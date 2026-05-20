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

@export var observer_radius := 18.0
@export var view_distance := 15.0
@export var view_cone_degrees := 105.0
@export var clear_seen_threshold := 0.36
@export var partial_seen_threshold := 0.14
@export var sneak_posture_visibility := 0.58
@export var standing_posture_visibility := 1.0
@export var bark_chance := 0.55
@export var bark_min_grace := 0.28
@export var bark_max_grace := 0.72
@export var bark_min_cooldown := 7.0
@export var bark_max_cooldown := 12.0

var root_scene: Node
var hud_layer: CanvasLayer
var party_manager: PartyManager
var world_time: WorldTimeController
var day_night_lighting: DayNightLightingController
var camera: Camera3D
var debug_show_los_rays := false

var _latest_results_by_subject: Dictionary = {}
var _latest_results_by_pair: Dictionary = {}
var _indicators: Dictionary = {}
var _bark_states: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _debug_ray_mesh_instance: MeshInstance3D
var _debug_ray_mesh := ImmediateMesh.new()
var _debug_ray_material := StandardMaterial3D.new()


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
	_update_perception(delta)


func get_latest_results_for_subject(subject: HumanoidCharacter) -> Array[Dictionary]:
	if subject == null:
		return []
	return (_latest_results_by_subject.get(subject.get_instance_id(), []) as Array).duplicate()


func get_latest_result(observer: HumanoidCharacter, subject: HumanoidCharacter) -> Dictionary:
	if observer == null or subject == null:
		return {}
	return (_latest_results_by_pair.get(_pair_key(observer, subject), {}) as Dictionary).duplicate()


func evaluate_observer(observer: HumanoidCharacter, subject: HumanoidCharacter) -> Dictionary:
	return _evaluate_observer(observer, subject)


func is_clearly_seen_by_anyone(subject: HumanoidCharacter) -> bool:
	for result in get_latest_results_for_subject(subject):
		if bool(result.get("clearly_seen", false)):
			return true
	return false


func _try_initialize() -> void:
	if root_scene == null or not is_inside_tree():
		return
	if party_manager == null:
		party_manager = root_scene.get_node_or_null("PartyManager") as PartyManager
	if world_time == null:
		world_time = get_parent().get_node_or_null("WorldTimeController") as WorldTimeController
	if day_night_lighting == null:
		day_night_lighting = get_parent().get_node_or_null("DayNightLightingController") as DayNightLightingController
	if camera == null:
		camera = root_scene.get_node_or_null("CameraRig/CameraPivot/Camera3D") as Camera3D
	_ensure_debug_ray_mesh()
	add_to_group("perception_controller")


func _update_perception(delta: float) -> void:
	var active_subjects := _get_active_sneaking_subjects()
	var active_keys: Dictionary = {}
	var next_by_subject: Dictionary = {}
	var next_by_pair: Dictionary = {}
	var debug_segments: Array[Dictionary] = []
	for subject in active_subjects:
		var subject_results: Array[Dictionary] = []
		for observer in _get_observers_for_subject(subject):
			var result := _evaluate_observer(observer, subject)
			var key := _pair_key(observer, subject)
			active_keys[key] = true
			next_by_pair[key] = result
			subject_results.append(result)
			_update_indicator(key, observer, subject, result)
			_update_bark_state(delta, key, observer, result)
			if debug_show_los_rays:
				for segment in result.get("sample_segments", []):
					debug_segments.append(segment)
		next_by_subject[subject.get_instance_id()] = subject_results
	_latest_results_by_subject = next_by_subject
	_latest_results_by_pair = next_by_pair
	_remove_inactive_indicators(active_keys)
	_update_debug_rays(debug_segments)


func _get_active_sneaking_subjects() -> Array[HumanoidCharacter]:
	var subjects: Array[HumanoidCharacter] = []
	if party_manager == null:
		return subjects
	for member in party_manager.selected_members:
		if member is HumanoidCharacter and member.sneaking and member.life_state == NpcRules.LifeState.ALIVE:
			subjects.append(member)
	return subjects


func _get_observers_for_subject(subject: HumanoidCharacter) -> Array[HumanoidCharacter]:
	var observers: Array[HumanoidCharacter] = []
	for node in get_tree().get_nodes_in_group("npc_character"):
		if not (node is HumanoidCharacter):
			continue
		var observer := node as HumanoidCharacter
		if observer == subject or observer.player_party_member or observer.life_state != NpcRules.LifeState.ALIVE:
			continue
		if observer.global_position.distance_to(subject.global_position) > observer_radius:
			continue
		observers.append(observer)
	return observers


func _evaluate_observer(observer: HumanoidCharacter, subject: HumanoidCharacter) -> Dictionary:
	if observer == null or subject == null:
		return {}
	var eye_position := observer.global_position + Vector3(0.0, 1.65, 0.0)
	var visible_samples := 0
	var cone_samples := 0
	var segments: Array[Dictionary] = []
	var max_distance_factor := 0.0
	for offset in SAMPLE_OFFSETS:
		var sample_position := subject.global_position + offset
		var to_sample := sample_position - eye_position
		var distance := to_sample.length()
		var in_cone := distance <= view_distance and _is_in_front_cone(observer, to_sample)
		var clear_los := false
		if in_cone:
			cone_samples += 1
			clear_los = _has_clear_ray(eye_position, sample_position, [observer.get_rid(), subject.get_rid()])
			if clear_los:
				visible_samples += 1
				max_distance_factor = maxf(max_distance_factor, _distance_factor(distance, view_distance))
		segments.append({"from": eye_position, "to": sample_position, "visible": in_cone and clear_los})
	var los_fraction := float(visible_samples) / float(SAMPLE_OFFSETS.size())
	var light_exposure := _calculate_light_exposure(subject)
	var posture := sneak_posture_visibility if subject.sneaking else standing_posture_visibility
	var visibility_score := clampf(los_fraction * light_exposure * max_distance_factor * posture, 0.0, 1.0)
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
		"visibility_score": visibility_score,
		"clearly_seen": visibility_score >= clear_seen_threshold,
		"partially_seen": visibility_score >= partial_seen_threshold and visibility_score < clear_seen_threshold,
		"sample_segments": segments,
	}


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


func _calculate_light_exposure(subject: HumanoidCharacter) -> float:
	var exposure := _get_day_night_exposure()
	var sample_position := subject.global_position + Vector3(0.0, 1.1, 0.0)
	for light in _get_local_lights():
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


func _get_local_lights() -> Array[Light3D]:
	var lights: Array[Light3D] = []
	var seen: Dictionary = {}
	for node in get_tree().get_nodes_in_group("stealth_light_source"):
		if node is Light3D and not seen.has(node.get_instance_id()):
			lights.append(node)
			seen[node.get_instance_id()] = true
	if root_scene != null:
		_collect_local_lights(root_scene, lights, seen)
	return lights


func _collect_local_lights(node: Node, lights: Array[Light3D], seen: Dictionary) -> void:
	if (node is OmniLight3D or node is SpotLight3D) and not seen.has(node.get_instance_id()):
		lights.append(node as Light3D)
		seen[node.get_instance_id()] = true
	for child in node.get_children():
		_collect_local_lights(child, lights, seen)


func _get_light_contribution(light: Light3D, sample_position: Vector3, subject: HumanoidCharacter) -> float:
	if light == null or not light.visible or light.light_energy <= 0.0:
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
	arrow_root.add_child(shaft)
	var head := MeshInstance3D.new()
	head.name = "ArrowHead"
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.18, 0.09, 0.18)
	head.mesh = head_mesh
	head.position = Vector3(0.0, -0.26, -0.94)
	head.rotation.y = deg_to_rad(45.0)
	arrow_root.add_child(head)

	return root


func _set_indicator_color(indicator: Node3D, color: Color, eye_scale_y: float, score: float) -> void:
	var eye := indicator.get_node_or_null("EyeRoot/Eye") as MeshInstance3D
	if eye != null:
		eye.scale.y = eye_scale_y
		eye.material_override = _make_unshaded_material(color)
	var pupil := indicator.get_node_or_null("EyeRoot/Pupil") as MeshInstance3D
	if pupil != null:
		pupil.visible = score >= partial_seen_threshold
		pupil.material_override = _make_unshaded_material(Color(0.02, 0.015, 0.01, color.a))
	var arrow_color := Color(color.r, color.g, color.b, clampf(color.a * 0.72, 0.18, 0.86))
	for node_path in ["ArrowRoot/ArrowShaft", "ArrowRoot/ArrowHead"]:
		var mesh_instance := indicator.get_node_or_null(node_path) as MeshInstance3D
		if mesh_instance != null:
			mesh_instance.visible = score >= 0.02
			mesh_instance.material_override = _make_unshaded_material(arrow_color)


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
