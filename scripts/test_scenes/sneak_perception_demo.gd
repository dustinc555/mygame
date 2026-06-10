extends Node3D

const SNEAK_DEMO_BUTTON_SCRIPT := preload("res://scripts/test_scenes/sneak_demo_button.gd")
const WORLD_ITEM_SCENE := preload("res://scenes/world/items/world_item.tscn")
const IRON_SWORD := preload("res://resources/items/equipment/weapons/swords/iron_sword.tres")
const EXPENSIVE_VASE := preload("res://resources/items/junk/expensive_vase.tres")

const BOOTSTRAP_PATH := NodePath("GameBootstrap")
const BOOTSTRAP_WAIT_FRAMES := 180
const MOVEMENT_MODE_WALK := 0
const MOVEMENT_MODE_SNEAK := 2
const PLAYER_FACTION_ID := "player"
const TOWNSFOLK_FACTION_ID := "townsfolk"
const MIRA_ID := "player.sneak_demo.mira"
const NOISY_ID := "player.sneak_demo.noisy"
const INVISIBLE_ID := "player.sneak_demo.invisible"
const WATCHER_ID := "town.sneak_demo.watcher"

@export var observer_turn_interval := 15.0
@export var observer_turn_seconds := 1.8
@export var show_vision_cone := false
@export var show_theft_noise_radius := false
@export var observer_rotation_enabled := true

var _bootstrap: Node
var _gecs: Node
var _projection: Node
var _selection: Node
var _perception_controller: Node
var _world_time: Node
var _camera_rig: Node
var _vision_cone: MeshInstance3D
var _theft_noise_radius_visuals: Array[MeshInstance3D] = []
var _turn_timer := 15.0
var _turn_progress := 1.0
var _turn_start_yaw := 0.0
var _turn_target_yaw := 0.0
var _setup_complete := false


func _ready() -> void:
	add_to_group("sneak_perception_demo")
	_ensure_level_geometry()
	_ensure_demo_buttons()
	_ensure_vision_cone()
	call_deferred("_prepare_demo")


func _process(delta: float) -> void:
	if not _setup_complete:
		return
	_process_observer_rotation(delta)
	_update_vision_cone()
	_update_theft_noise_radius_visuals()


func perform_sneak_demo_action(key: String, _actors: Array = []) -> String:
	match key:
		"toggle_vision_cone":
			show_vision_cone = not show_vision_cone
			_update_vision_cone()
			return "Vision cone: %s" % ("shown" if show_vision_cone else "hidden")
		"toggle_los_rays":
			_bind_systems()
			if _perception_controller == null:
				return "Perception controller is not ready"
			var next_value := not bool(_perception_controller.get("debug_show_los_rays"))
			_perception_controller.set("debug_show_los_rays", next_value)
			return "Line-of-sight rays: %s" % ("shown" if next_value else "hidden")
		"toggle_theft_noise_radius":
			show_theft_noise_radius = not show_theft_noise_radius
			_update_theft_noise_radius_visuals()
			return "Theft noise radius: %s" % ("shown" if show_theft_noise_radius else "hidden")
		"toggle_rotation":
			observer_rotation_enabled = not observer_rotation_enabled
			return "Observer rotation: %s" % ("running" if observer_rotation_enabled else "paused")
	return "Unknown sneak demo action"


func get_demo_actor_ids() -> Dictionary:
	return {"mira": MIRA_ID, "noisy": NOISY_ID, "invisible": INVISIBLE_ID, "watcher": WATCHER_ID}


func get_demo_state() -> Dictionary:
	return {
		"ready": _setup_complete,
		"mira_id": MIRA_ID,
		"noisy_id": NOISY_ID,
		"invisible_id": INVISIBLE_ID,
		"watcher_id": WATCHER_ID,
		"projection_count": int(_projection.call("get_projection_count")) if _projection != null and _projection.has_method("get_projection_count") else 0,
		"selected_actor_id": str(_selection.call("get_selected_actor_id")) if _selection != null and _selection.has_method("get_selected_actor_id") else "",
	}


func set_actor_position(actor_id: String, position: Vector3) -> void:
	_upsert_actor_patch(actor_id, {"last_world_position": position, "last_world_position_initialized": true})
	var projection := _projection_for_actor(actor_id)
	if projection is Node3D:
		(projection as Node3D).global_position = position


func set_actor_skill_level(actor_id: String, skill_id: String, level: int) -> void:
	var record := _population_record(actor_id)
	var skill_levels: Dictionary = record.get("skill_levels", {}) if record.get("skill_levels", {}) is Dictionary else {}
	skill_levels = skill_levels.duplicate(true)
	skill_levels[skill_id] = level
	_upsert_actor_patch(actor_id, {"skill_levels": skill_levels})


func set_actor_sneaking(actor_id: String, enabled: bool) -> void:
	_upsert_actor_patch(actor_id, {"movement_mode": MOVEMENT_MODE_SNEAK if enabled else MOVEMENT_MODE_WALK})


func face_watcher_to_actor(actor_id: String) -> void:
	_face_actor_to_actor(WATCHER_ID, actor_id)


func face_watcher_away_from_actor(actor_id: String) -> void:
	var watcher_position := _actor_position(WATCHER_ID)
	var subject_position := _actor_position(actor_id)
	var target := watcher_position * 2.0 - subject_position
	target.y = watcher_position.y
	_set_actor_facing_toward(WATCHER_ID, target)


func evaluate_demo_case(subject_id: String, position: Vector3) -> Dictionary:
	set_actor_position(subject_id, position)
	set_actor_sneaking(subject_id, true)
	face_watcher_to_actor(subject_id)
	await _wait_frames(4)
	if _perception_controller == null or not _perception_controller.has_method("evaluate_observer"):
		return {}
	return _perception_controller.call("evaluate_observer", WATCHER_ID, subject_id) as Dictionary


func _prepare_demo() -> void:
	for _frame in range(BOOTSTRAP_WAIT_FRAMES):
		await get_tree().process_frame
		if _bind_systems():
			_start_demo()
			return
	push_error("Sneak perception demo timed out waiting for GECS systems")


func _bind_systems() -> bool:
	_bootstrap = get_node_or_null(BOOTSTRAP_PATH)
	if _bootstrap == null:
		return false
	_gecs = _bootstrap.get_node_or_null("GecsWorldController")
	_projection = _bootstrap.get_node_or_null("WorldActorProjectionController")
	_selection = _bootstrap.get_node_or_null("WorldSelectionController")
	_perception_controller = _bootstrap.get_node_or_null("PerceptionController")
	_world_time = _bootstrap.get_node_or_null("WorldTimeController")
	_camera_rig = get_node_or_null("CameraRig")
	return _gecs != null and _projection != null and _selection != null and _perception_controller != null


func _start_demo() -> void:
	if _setup_complete:
		return
	if _gecs.has_method("clear_population_records"):
		_gecs.call("clear_population_records")
	_seed_population_records()
	if _projection != null:
		_projection.set("auto_project", true)
		_projection.set("max_projected_actor_count", 0)
		_projection.set("projection_update_interval_seconds", 0.05)
		_projection.set("visible_combat_runtime_enabled", false)
		_projection.call("sync_projections")
	_ensure_owned_items()
	_ensure_theft_noise_radius_visuals()
	if _selection != null and _selection.has_method("select_actor_id"):
		_selection.call("select_actor_id", MIRA_ID)
	if _world_time != null:
		_world_time.set("total_world_minutes", 16.0 * 60.0 + 30.0)
	if _camera_rig != null and _camera_rig.has_method("focus_world_position"):
		_camera_rig.call("focus_world_position", Vector3(0.0, 0.0, -2.5))
	_face_actor_to_actor(WATCHER_ID, MIRA_ID)
	_setup_complete = true


func _seed_population_records() -> void:
	_upsert_actor_record(MIRA_ID, "Mira", PLAYER_FACTION_ID, Vector3(0.0, 0.6, -7.5), 0.0, true, {
		SkillRules.SUBTERFUGE_SLEIGHT_OF_HAND: 20,
	})
	_upsert_actor_record(NOISY_ID, "Noisy", PLAYER_FACTION_ID, Vector3(-1.2, 0.6, -7.5), 0.0, true, {
		SkillRules.SUBTERFUGE_SNEAKING: 1,
		SkillRules.SUBTERFUGE_SLEIGHT_OF_HAND: 1,
	})
	_upsert_actor_record(INVISIBLE_ID, "Invisible", PLAYER_FACTION_ID, Vector3(1.2, 0.6, -7.5), 0.0, true, {
		SkillRules.SUBTERFUGE_SNEAKING: 80,
		SkillRules.SUBTERFUGE_SLEIGHT_OF_HAND: 80,
	})
	_upsert_actor_record(WATCHER_ID, "Watcher", TOWNSFOLK_FACTION_ID, Vector3(0.0, 0.6, 0.0), 0.0, false, {
		SkillRules.ATTRIBUTE_PERCEPTION: 1,
	})


func _upsert_actor_record(actor_id: String, member_name: String, faction_id: String, position: Vector3, facing_yaw: float, player_party: bool, skill_levels: Dictionary) -> void:
	if _gecs == null or not _gecs.has_method("upsert_population_record_core"):
		return
	_gecs.call("upsert_population_record_core", {
		"actor_id": actor_id,
		"stable_id": actor_id,
		"member_id": actor_id,
		"member_name": member_name,
		"faction_id": faction_id,
		"party_id": "player_party" if player_party else "",
		"squad_name": "Player Party" if player_party else "Townsfolk",
		"player_party_member": player_party,
		"player_controllable": player_party,
		"role_id": "sneak_demo_actor",
		"projection_kind": "humanoid",
		"life_state": NpcRules.LifeState.ALIVE,
		"hp": 100.0,
		"max_hp": 100.0,
		"base_max_blood": 100.0,
		"blood": 100.0,
		"max_blood": 100.0,
		"combat_stance": NpcRules.CombatStance.PASSIVE,
		"movement_mode": MOVEMENT_MODE_SNEAK if player_party else MOVEMENT_MODE_WALK,
		"realization_state": "ledger",
		"ledger_activity_state": "sneak_demo",
		"last_world_position": position,
		"last_world_position_initialized": true,
		"world_facing_yaw": facing_yaw,
		"world_facing_yaw_initialized": true,
		"locomotion_state": {"animation_state": "sneak_idle" if player_party else "idle", "speed": 0.0, "horizontal_speed": 0.0},
		"base_color": Color(0.82, 0.43, 0.31, 1.0) if actor_id == MIRA_ID else (Color(0.66, 0.48, 0.34, 1.0) if actor_id == NOISY_ID else (Color(0.38, 0.50, 0.86, 1.0) if actor_id == INVISIBLE_ID else Color(0.52, 0.60, 0.70, 1.0))),
		"skill_levels": skill_levels.duplicate(true),
		"important": true,
	})


func _ensure_level_geometry() -> void:
	_ensure_floor()
	_ensure_pillars()
	_ensure_torches()


func _ensure_floor() -> void:
	if get_node_or_null("Floor") != null:
		return
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	add_child(floor_body)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(24.0, 1.0, 24.0)
	shape.shape = box_shape
	floor_body.add_child(shape)
	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box_shape.size
	mesh_instance.mesh = box_mesh
	mesh_instance.material_override = _make_material(Color(0.16, 0.17, 0.15, 1.0), 0.95)
	floor_body.add_child(mesh_instance)


func _ensure_pillars() -> void:
	if get_node_or_null("Pillars") != null:
		return
	var pillar_root := Node3D.new()
	pillar_root.name = "Pillars"
	add_child(pillar_root)
	var radius := 3.7
	for index in range(8):
		var angle := TAU * float(index) / 8.0
		var position := Vector3(sin(angle) * radius, 0.0, -cos(angle) * radius)
		_make_pillar(pillar_root, "Pillar%d" % index, position)


func _make_pillar(parent: Node, node_name: String, position: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	body.add_to_group("perception_occluder")
	parent.add_child(body)
	var collision := CollisionShape3D.new()
	var cylinder_shape := CylinderShape3D.new()
	cylinder_shape.radius = 0.52
	cylinder_shape.height = 3.2
	collision.shape = cylinder_shape
	collision.position.y = 1.6
	body.add_child(collision)
	var mesh_instance := MeshInstance3D.new()
	var cylinder_mesh := CylinderMesh.new()
	cylinder_mesh.top_radius = 0.52
	cylinder_mesh.bottom_radius = 0.52
	cylinder_mesh.height = 3.2
	cylinder_mesh.radial_segments = 18
	mesh_instance.mesh = cylinder_mesh
	mesh_instance.position.y = 1.6
	mesh_instance.material_override = _make_material(Color(0.38, 0.34, 0.29, 1.0), 0.82)
	body.add_child(mesh_instance)


func _ensure_torches() -> void:
	if get_node_or_null("Torches") != null:
		return
	var torch_root := Node3D.new()
	torch_root.name = "Torches"
	add_child(torch_root)
	_make_torch(torch_root, "TorchA", Vector3(-5.8, 0.0, -4.7))
	_make_torch(torch_root, "TorchB", Vector3(5.8, 0.0, 4.7))
	_make_torch(torch_root, "TorchC", Vector3(-5.8, 0.0, 4.7))


func _make_torch(parent: Node, node_name: String, position: Vector3) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = position
	parent.add_child(root)
	var post := MeshInstance3D.new()
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.08
	post_mesh.bottom_radius = 0.08
	post_mesh.height = 1.45
	post.mesh = post_mesh
	post.position.y = 0.72
	post.material_override = _make_material(Color(0.23, 0.13, 0.07, 1.0), 0.9)
	root.add_child(post)
	var flame := MeshInstance3D.new()
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.18
	flame_mesh.height = 0.34
	flame.mesh = flame_mesh
	flame.position.y = 1.55
	flame.material_override = _make_emissive_material(Color(1.0, 0.46, 0.08, 1.0))
	root.add_child(flame)
	var light := OmniLight3D.new()
	light.name = "TorchLight"
	light.position.y = 1.55
	light.omni_range = 7.0
	light.omni_attenuation = 1.15
	light.light_energy = 1.8
	light.light_color = Color(1.0, 0.55, 0.22, 1.0)
	light.shadow_enabled = true
	light.add_to_group("stealth_light_source")
	root.add_child(light)


func _ensure_owned_items() -> void:
	var sword := get_node_or_null("OwnedSword") as WorldItem
	if sword == null:
		sword = WORLD_ITEM_SCENE.instantiate() as WorldItem
		sword.name = "OwnedSword"
		sword.position = Vector3(2.15, 0.08, -1.7)
		sword.owner_faction_name = TOWNSFOLK_FACTION_ID
		sword.theft_value = 45
		sword.theft_noise_radius = 1.8
		sword.theft_difficulty = 25
		add_child(sword)
		sword.setup(IRON_SWORD, 1)
	var vase := get_node_or_null("OwnedVase") as WorldItem
	if vase == null:
		vase = WORLD_ITEM_SCENE.instantiate() as WorldItem
		vase.name = "OwnedVase"
		vase.position = Vector3(-2.25, 0.08, -1.45)
		vase.owner_faction_name = TOWNSFOLK_FACTION_ID
		vase.theft_value = 80
		vase.theft_noise_radius = 5.0
		vase.theft_difficulty = 45
		add_child(vase)
		vase.setup(EXPENSIVE_VASE, 1)


func _ensure_demo_buttons() -> void:
	if get_node_or_null("DemoButtons") != null:
		return
	var buttons := Node3D.new()
	buttons.name = "DemoButtons"
	add_child(buttons)
	_make_button(buttons, "VisionConeButton", Vector3(-7.5, 0.22, -7.8), "toggle_vision_cone", "Toggle Vision Cone", Color(0.16, 0.44, 0.95, 1.0))
	_make_button(buttons, "LosRaysButton", Vector3(-5.9, 0.22, -7.8), "toggle_los_rays", "Toggle LOS Rays", Color(0.95, 0.66, 0.14, 1.0))
	_make_button(buttons, "RotationButton", Vector3(-4.3, 0.22, -7.8), "toggle_rotation", "Pause/Resume Watcher", Color(0.32, 0.74, 0.35, 1.0))
	_make_button(buttons, "TheftNoiseButton", Vector3(-2.7, 0.22, -7.8), "toggle_theft_noise_radius", "Toggle Noise Radius", Color(0.56, 0.35, 0.94, 1.0))


func _make_button(parent: Node, node_name: String, position: Vector3, key: String, label_text: String, color: Color) -> void:
	var button := StaticBody3D.new()
	button.name = node_name
	button.set_script(SNEAK_DEMO_BUTTON_SCRIPT)
	button.set("target_path", NodePath("../.."))
	button.set("action_key", key)
	button.set("action_label", label_text)
	button.position = position
	parent.add_child(button)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, 0.35, 0.9)
	collision.shape = shape
	button.add_child(collision)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _make_material(color, 0.6)
	button.add_child(mesh_instance)
	var label := Label3D.new()
	label.text = label_text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 28
	label.outline_size = 4
	label.position = Vector3(0.0, 0.58, 0.0)
	button.add_child(label)


func _ensure_vision_cone() -> void:
	if _vision_cone != null:
		return
	_vision_cone = MeshInstance3D.new()
	_vision_cone.name = "WatcherVisionCone"
	_vision_cone.top_level = true
	_vision_cone.mesh = _build_vision_cone_mesh(15.0, 105.0)
	_vision_cone.material_override = _make_transparent_material(Color(1.0, 0.62, 0.08, 0.23))
	_vision_cone.visible = false
	add_child(_vision_cone)


func _build_vision_cone_mesh(range: float, degrees: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 32
	var half_angle := deg_to_rad(degrees) * 0.5
	for index in range(segments):
		var a0 := lerpf(-half_angle, half_angle, float(index) / float(segments))
		var a1 := lerpf(-half_angle, half_angle, float(index + 1) / float(segments))
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(sin(a0) * range, 0.0, cos(a0) * range))
		st.add_vertex(Vector3(sin(a1) * range, 0.0, cos(a1) * range))
	return st.commit()


func _update_vision_cone() -> void:
	if _vision_cone == null:
		return
	_vision_cone.visible = show_vision_cone
	if not show_vision_cone:
		return
	var watcher_projection := _projection_for_actor(WATCHER_ID)
	if not (watcher_projection is Node3D):
		return
	var watcher := watcher_projection as Node3D
	_vision_cone.global_position = Vector3(watcher.global_position.x, 0.045, watcher.global_position.z)
	_vision_cone.rotation = Vector3(0.0, watcher.rotation.y, 0.0)


func _ensure_theft_noise_radius_visuals() -> void:
	if not _theft_noise_radius_visuals.is_empty():
		return
	var root := Node3D.new()
	root.name = "TheftNoiseRadiusVisuals"
	add_child(root)
	for node_name in ["OwnedSword", "OwnedVase"]:
		var item := get_node_or_null(node_name) as WorldItem
		if item == null or item.theft_noise_radius <= 0.01:
			continue
		var visual := MeshInstance3D.new()
		visual.name = "%sNoiseRadius" % node_name
		visual.top_level = true
		visual.mesh = _build_radius_disc_mesh(item.theft_noise_radius)
		visual.material_override = _make_transparent_material(Color(0.56, 0.35, 0.94, 0.18))
		visual.visible = false
		visual.set_meta("item_path", get_path_to(item))
		root.add_child(visual)
		_theft_noise_radius_visuals.append(visual)


func _update_theft_noise_radius_visuals() -> void:
	if _theft_noise_radius_visuals.is_empty():
		return
	for visual in _theft_noise_radius_visuals:
		if visual == null:
			continue
		var item_path := NodePath(str(visual.get_meta("item_path", "")))
		var item := get_node_or_null(item_path) as WorldItem
		visual.visible = show_theft_noise_radius and item != null and is_instance_valid(item)
		if item == null or not is_instance_valid(item):
			continue
		visual.global_position = Vector3(item.global_position.x, 0.04, item.global_position.z)


func _build_radius_disc_mesh(radius: float) -> Mesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.025
	mesh.radial_segments = 72
	return mesh


func _process_observer_rotation(delta: float) -> void:
	if not observer_rotation_enabled:
		return
	if _turn_progress < 1.0:
		_turn_progress = minf(1.0, _turn_progress + delta / maxf(observer_turn_seconds, 0.01))
		var eased := _smoothstep(0.0, 1.0, _turn_progress)
		_set_actor_yaw(WATCHER_ID, lerp_angle(_turn_start_yaw, _turn_target_yaw, eased))
		return
	_turn_timer -= delta
	if _turn_timer > 0.0:
		return
	_turn_start_yaw = _actor_yaw(WATCHER_ID)
	_turn_target_yaw = _turn_start_yaw - PI * 0.5
	_turn_progress = 0.0
	_turn_timer = observer_turn_interval


func _face_actor_to_actor(actor_id: String, target_actor_id: String) -> void:
	_set_actor_facing_toward(actor_id, _actor_position(target_actor_id))


func _set_actor_facing_toward(actor_id: String, target_position: Vector3) -> void:
	var actor_position := _actor_position(actor_id)
	var flat := Vector3(target_position.x - actor_position.x, 0.0, target_position.z - actor_position.z)
	if flat.length_squared() <= 0.001:
		return
	var direction := flat.normalized()
	_set_actor_yaw(actor_id, atan2(direction.x, direction.z))


func _set_actor_yaw(actor_id: String, yaw: float) -> void:
	_upsert_actor_patch(actor_id, {"world_facing_yaw": yaw, "world_facing_yaw_initialized": true})
	var projection := _projection_for_actor(actor_id)
	if projection is Node3D:
		(projection as Node3D).rotation.y = yaw


func _actor_yaw(actor_id: String) -> float:
	var projection := _projection_for_actor(actor_id)
	if projection is Node3D:
		return (projection as Node3D).rotation.y
	return float(_population_record(actor_id).get("world_facing_yaw", 0.0))


func _actor_position(actor_id: String) -> Vector3:
	var projection := _projection_for_actor(actor_id)
	if projection is Node3D:
		return (projection as Node3D).global_position
	var value = _population_record(actor_id).get("last_world_position", Vector3.ZERO)
	return value if value is Vector3 else Vector3.ZERO


func _projection_for_actor(actor_id: String) -> Node:
	if _projection != null and _projection.has_method("get_projection_for_actor"):
		return _projection.call("get_projection_for_actor", actor_id) as Node
	return null


func _population_record(actor_id: String) -> Dictionary:
	if _gecs != null and _gecs.has_method("get_population_record_core"):
		var record = _gecs.call("get_population_record_core", actor_id)
		return record if record is Dictionary else {}
	return {}


func _upsert_actor_patch(actor_id: String, patch_fields: Dictionary) -> void:
	if _gecs == null or not _gecs.has_method("upsert_population_record_core") or actor_id.strip_edges().is_empty():
		return
	var patch := {"actor_id": actor_id}
	for key in patch_fields.keys():
		patch[key] = patch_fields[key]
	_gecs.call("upsert_population_record_core", patch)


func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


func _make_transparent_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _make_emissive_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.8
	return material


func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	var x := clampf((value - edge0) / maxf(edge1 - edge0, 0.0001), 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _wait_frames(frames: int) -> void:
	for _index in range(frames):
		await get_tree().process_frame
		await get_tree().physics_frame
