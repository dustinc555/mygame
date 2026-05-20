extends Node3D

const PARTY_MEMBER_SCRIPT = preload("res://scripts/party_member.gd")
const FACTION_HUMANOID_SCRIPT = preload("res://scripts/characters/faction_humanoid.gd")
const SNEAK_DEMO_BUTTON_SCRIPT = preload("res://scripts/test_scenes/sneak_demo_button.gd")
const WORLD_ITEM_SCENE = preload("res://scenes/world/items/world_item.tscn")
const IRON_SWORD = preload("res://resources/items/iron_sword.tres")

@export var observer_turn_interval := 15.0
@export var observer_turn_seconds := 1.8
@export var show_vision_cone := false
@export var observer_rotation_enabled := true

var player: HumanoidCharacter
var observer: HumanoidCharacter
var perception_controller: Node
var vision_cone: MeshInstance3D
var _turn_timer := 15.0
var _turn_progress := 1.0
var _turn_start_yaw := 0.0
var _turn_target_yaw := 0.0


func _ready() -> void:
	_ensure_level_geometry()
	_ensure_characters()
	_ensure_owned_sword_placeholder()
	_ensure_demo_buttons()
	_ensure_vision_cone()
	call_deferred("_finish_demo_setup")


func _process(delta: float) -> void:
	_process_observer_rotation(delta)
	_update_vision_cone()


func perform_sneak_demo_action(key: String, _actors: Array = []) -> String:
	match key:
		"toggle_vision_cone":
			show_vision_cone = not show_vision_cone
			_update_vision_cone()
			return "Vision cone: %s" % ("shown" if show_vision_cone else "hidden")
		"toggle_los_rays":
			_ensure_perception_controller()
			if perception_controller == null:
				return "Perception controller is not ready"
			var next_value := not bool(perception_controller.get("debug_show_los_rays"))
			perception_controller.set("debug_show_los_rays", next_value)
			return "Line-of-sight rays: %s" % ("shown" if next_value else "hidden")
		"toggle_rotation":
			observer_rotation_enabled = not observer_rotation_enabled
			return "Observer rotation: %s" % ("running" if observer_rotation_enabled else "paused")
	return "Unknown sneak demo action"


func _finish_demo_setup() -> void:
	await get_tree().process_frame
	_ensure_perception_controller()
	var party_manager := get_node_or_null("PartyManager") as PartyManager
	if party_manager != null and player != null:
		party_manager.select_only(player)
		player.set_sneaking_enabled(true)
	var world_time := get_node_or_null("GameBootstrap/WorldTimeController") as WorldTimeController
	if world_time != null:
		world_time.total_world_minutes = 16.0 * 60.0 + 30.0


func _ensure_perception_controller() -> void:
	if perception_controller == null:
		perception_controller = get_node_or_null("GameBootstrap/PerceptionController")


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


func _ensure_characters() -> void:
	var party_root := get_node_or_null("PartyMembers") as Node3D
	if party_root == null:
		party_root = Node3D.new()
		party_root.name = "PartyMembers"
		add_child(party_root)
	if player == null:
		player = _make_humanoid("Mira", PARTY_MEMBER_SCRIPT, Vector3(0.0, 0.6, -7.5), Color(0.82, 0.43, 0.31, 1.0), "Player", true)
		player.stable_id = "player.sneak_demo.mira"
		player.fatigue_enabled = false
		party_root.add_child(player)
	if observer == null:
		observer = _make_humanoid("Watcher", FACTION_HUMANOID_SCRIPT, Vector3.ZERO + Vector3(0.0, 0.6, 0.0), Color(0.52, 0.60, 0.70, 1.0), "Townsfolk", false)
		observer.member_name = "Watcher"
		observer.stable_id = "town.sneak_demo.watcher"
		observer.combat_stance = NpcRules.CombatStance.PASSIVE
		observer.fatigue_enabled = false
		observer.add_to_group("sneak_demo_observer")
		party_root.add_child(observer)
		_turn_target_yaw = observer.rotation.y
		_turn_start_yaw = observer.rotation.y


func _make_humanoid(node_name: String, script_resource: Script, position: Vector3, color: Color, faction: String, with_selection_ring: bool) -> HumanoidCharacter:
	var character := CharacterBody3D.new()
	character.name = node_name
	character.set_script(script_resource)
	character.position = position
	character.rotation = Vector3.ZERO
	character.set("base_color", color)
	character.set("member_name", node_name)
	character.set("faction_name", faction)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.1
	collision.shape = capsule
	collision.position.y = 0.95
	character.add_child(collision)
	var body_mesh := MeshInstance3D.new()
	body_mesh.name = "BodyMesh"
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = 0.45
	body_mesh.mesh = capsule_mesh
	body_mesh.position.y = 0.95
	character.add_child(body_mesh)
	if with_selection_ring:
		var ring := MeshInstance3D.new()
		ring.name = "SelectionRing"
		var ring_mesh := CylinderMesh.new()
		ring_mesh.top_radius = 0.72
		ring_mesh.bottom_radius = 0.72
		ring_mesh.height = 0.05
		ring_mesh.radial_segments = 24
		ring.mesh = ring_mesh
		ring.position.y = 0.03
		character.add_child(ring)
	return character as HumanoidCharacter


func _ensure_owned_sword_placeholder() -> void:
	if get_node_or_null("OwnedSword") != null:
		return
	var item := WORLD_ITEM_SCENE.instantiate() as WorldItem
	item.name = "OwnedSword"
	item.position = Vector3(2.15, 0.08, -1.7)
	item.setup(IRON_SWORD, 1)
	item.owner_faction_name = "Townsfolk"
	add_child(item)


func _ensure_demo_buttons() -> void:
	if get_node_or_null("DemoButtons") != null:
		return
	var buttons := Node3D.new()
	buttons.name = "DemoButtons"
	add_child(buttons)
	_make_button(buttons, "VisionConeButton", Vector3(-7.5, 0.22, -7.8), "toggle_vision_cone", "Toggle Vision Cone", Color(0.16, 0.44, 0.95, 1.0))
	_make_button(buttons, "LosRaysButton", Vector3(-5.9, 0.22, -7.8), "toggle_los_rays", "Toggle LOS Rays", Color(0.95, 0.66, 0.14, 1.0))
	_make_button(buttons, "RotationButton", Vector3(-4.3, 0.22, -7.8), "toggle_rotation", "Pause/Resume Watcher", Color(0.32, 0.74, 0.35, 1.0))


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
	if vision_cone != null:
		return
	vision_cone = MeshInstance3D.new()
	vision_cone.name = "WatcherVisionCone"
	vision_cone.top_level = true
	vision_cone.mesh = _build_vision_cone_mesh(15.0, 105.0)
	vision_cone.material_override = _make_transparent_material(Color(1.0, 0.62, 0.08, 0.23))
	vision_cone.visible = false
	add_child(vision_cone)


func _build_vision_cone_mesh(range: float, degrees: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 32
	var half_angle := deg_to_rad(degrees) * 0.5
	for index in range(segments):
		var a0 := lerpf(-half_angle, half_angle, float(index) / float(segments))
		var a1 := lerpf(-half_angle, half_angle, float(index + 1) / float(segments))
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(sin(a0) * range, 0.0, -cos(a0) * range))
		st.add_vertex(Vector3(sin(a1) * range, 0.0, -cos(a1) * range))
	return st.commit()


func _update_vision_cone() -> void:
	if vision_cone == null or observer == null:
		return
	vision_cone.visible = show_vision_cone
	if not show_vision_cone:
		return
	vision_cone.global_position = Vector3(observer.global_position.x, 0.045, observer.global_position.z)
	vision_cone.rotation = Vector3(0.0, observer.rotation.y, 0.0)


func _process_observer_rotation(delta: float) -> void:
	if observer == null or not observer_rotation_enabled:
		return
	if _turn_progress < 1.0:
		_turn_progress = minf(1.0, _turn_progress + delta / maxf(observer_turn_seconds, 0.01))
		var eased := _smoothstep(0.0, 1.0, _turn_progress)
		observer.rotation.y = lerp_angle(_turn_start_yaw, _turn_target_yaw, eased)
		return
	_turn_timer -= delta
	if _turn_timer > 0.0:
		return
	_turn_start_yaw = observer.rotation.y
	_turn_target_yaw = _turn_start_yaw - PI * 0.5
	_turn_progress = 0.0
	_turn_timer = observer_turn_interval


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
