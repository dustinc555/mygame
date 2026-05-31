extends Node3D

const PARTY_MEMBER_SCRIPT = preload("res://scripts/party_member.gd")
const SCRAP_PILE_SCENE = preload("res://scenes/world/resource_nodes/scrap_pile_node.tscn")
const TWISTED_SCRAP_HEAP_SCENE = preload("res://scenes/world/resource_nodes/scrap_pile_variant_2_node.tscn")
const HALF_BURIED_ROBOT_WRECK_SCENE = preload("res://scenes/world/resource_nodes/half_buried_robot_wreck_node.tscn")
const SNEAK_DEMO_BUTTON_SCRIPT = preload("res://scripts/test_scenes/sneak_demo_button.gd")
const ROBOT_PARTS = preload("res://resources/items/robot_parts.tres")

@export var show_charge_labels := true
@export var show_noise_radius := false

var novice: HumanoidCharacter
var expert: HumanoidCharacter
var noise_radius_visuals: Array[MeshInstance3D] = []


func _ready() -> void:
	_ensure_level_geometry()
	_ensure_characters()
	_ensure_scrap_piles()
	_ensure_demo_buttons()
	_ensure_noise_radius_visuals()
	call_deferred("_finish_demo_setup")


func _process(_delta: float) -> void:
	_update_noise_radius_visuals()


func perform_sneak_demo_action(key: String, _actors: Array = []) -> String:
	match key:
		"reset_piles":
			for pile in _get_scrap_piles():
				pile.reset_charges()
				pile.set_show_charge_count(show_charge_labels)
			return "Scrap piles reset"
		"toggle_charge_labels":
			show_charge_labels = not show_charge_labels
			for pile in _get_scrap_piles():
				pile.set_show_charge_count(show_charge_labels)
			return "Charge labels: %s" % ("shown" if show_charge_labels else "hidden")
		"toggle_noise_radius":
			show_noise_radius = not show_noise_radius
			_update_noise_radius_visuals()
			return "Scavenge noise radius: %s" % ("shown" if show_noise_radius else "hidden")
		"select_novice":
			_select_member(novice)
			return "Selected novice scavenger"
		"select_expert":
			_select_member(expert)
			return "Selected expert scavenger"
		"fill_inventory":
			var filled := _fill_selected_inventories()
			return "Filled %d inventories" % filled
	return "Unknown junkyard demo action"


func _finish_demo_setup() -> void:
	await get_tree().process_frame
	_select_member(novice)
	var world_time := get_node_or_null("GameBootstrap/WorldTimeController") as WorldTimeController
	if world_time != null:
		world_time.total_world_minutes = 16.0 * 60.0 + 30.0


func _ensure_level_geometry() -> void:
	_ensure_floor()
	_ensure_fences()
	_ensure_lighting()


func _ensure_floor() -> void:
	if get_node_or_null("Floor") != null:
		return
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	add_child(floor_body)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(34.0, 1.0, 26.0)
	shape.shape = box_shape
	floor_body.add_child(shape)
	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box_shape.size
	mesh_instance.mesh = box_mesh
	mesh_instance.material_override = _make_material(Color(0.21, 0.18, 0.15, 1.0), 0.96)
	floor_body.add_child(mesh_instance)


func _ensure_fences() -> void:
	if get_node_or_null("FenceRoot") != null:
		return
	var root_node := Node3D.new()
	root_node.name = "FenceRoot"
	add_child(root_node)
	_make_wall(root_node, "NorthFence", Vector3(0.0, 1.0, -12.8), Vector3(34.0, 2.0, 0.35))
	_make_wall(root_node, "SouthFence", Vector3(0.0, 1.0, 12.8), Vector3(34.0, 2.0, 0.35))
	_make_wall(root_node, "WestFence", Vector3(-16.8, 1.0, 0.0), Vector3(0.35, 2.0, 26.0))
	_make_wall(root_node, "EastFence", Vector3(16.8, 1.0, 0.0), Vector3(0.35, 2.0, 26.0))
	_make_wall(root_node, "CrushedCarBlock", Vector3(7.5, 0.45, 4.8), Vector3(4.8, 0.9, 2.2), Color(0.31, 0.22, 0.18, 1.0))
	_make_wall(root_node, "RobotHullBlock", Vector3(-7.8, 0.6, 5.4), Vector3(3.1, 1.2, 2.8), Color(0.16, 0.2, 0.22, 1.0))


func _make_wall(parent: Node, node_name: String, position: Vector3, size: Vector3, color: Color = Color(0.18, 0.17, 0.15, 1.0)) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	parent.add_child(body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _make_material(color, 0.88)
	body.add_child(mesh_instance)


func _ensure_lighting() -> void:
	if get_node_or_null("JunkyardLight") != null:
		return
	var sun := DirectionalLight3D.new()
	sun.name = "JunkyardLight"
	sun.light_energy = 1.25
	sun.rotation_degrees = Vector3(-52.0, 28.0, 0.0)
	add_child(sun)
	var glow := OmniLight3D.new()
	glow.name = "OldWorldCoreGlow"
	glow.position = Vector3(4.8, 1.1, -3.2)
	glow.light_color = Color(0.3, 0.72, 1.0, 1.0)
	glow.light_energy = 1.35
	glow.omni_range = 6.5
	add_child(glow)


func _ensure_characters() -> void:
	if novice != null and expert != null:
		return
	var party_root := get_node_or_null("PartyMembers")
	if party_root == null:
		party_root = Node3D.new()
		party_root.name = "PartyMembers"
		add_child(party_root)
	novice = _make_humanoid("Novice Scavenger", Vector3(-6.2, 0.0, -6.2), Color(0.72, 0.58, 0.35, 1.0))
	expert = _make_humanoid("Expert Scavenger", Vector3(-4.8, 0.0, -6.2), Color(0.34, 0.67, 0.84, 1.0))
	party_root.add_child(novice)
	party_root.add_child(expert)
	novice.set_skill_level(SkillRules.LABOR_SCAVENGING, 1)
	novice.set_skill_level(SkillRules.TECH_ROBOTICS, 1)
	expert.set_skill_level(SkillRules.LABOR_SCAVENGING, 38)
	expert.set_skill_level(SkillRules.TECH_ROBOTICS, 32)
	expert.set_skill_level(SkillRules.ATTRIBUTE_PERCEPTION, 24)
	expert.set_skill_level(SkillRules.ATTRIBUTE_DEXTERITY, 20)


func _make_humanoid(node_name: String, position: Vector3, color: Color) -> HumanoidCharacter:
	var character := CharacterBody3D.new()
	character.name = node_name.replace(" ", "")
	character.set_script(PARTY_MEMBER_SCRIPT)
	character.position = position
	character.set("base_color", color)
	character.set("member_name", node_name)
	character.set("faction_name", "Player")
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


func _ensure_scrap_piles() -> void:
	if get_node_or_null("ScrapPiles") != null:
		return
	var root_node := Node3D.new()
	root_node.name = "ScrapPiles"
	add_child(root_node)
	_make_scrap_pile(root_node, "SmallScrapPile", Vector3(-5.8, 0.0, -1.0), 0, ScavengingResourceNode.PileSize.SMALL, Vector3.ONE * 0.82)
	_make_twisted_scrap_heap(root_node, Vector3(-8.0, 0.0, 3.0))
	_make_half_buried_robot_wreck(root_node, Vector3(0.5, 0.0, 0.2))
	_make_scrap_pile(root_node, "LargeScrapPile", Vector3(6.8, 0.0, -2.0), 28, ScavengingResourceNode.PileSize.LARGE, Vector3.ONE * 1.25)


func _make_scrap_pile(parent: Node, node_name: String, position: Vector3, difficulty: int, size_id: int, pile_scale: Vector3) -> void:
	var pile := SCRAP_PILE_SCENE.instantiate() as ScavengingResourceNode
	pile.name = node_name
	pile.position = position
	pile.scale = pile_scale
	pile.pile_size = size_id
	pile.scavenging_difficulty = difficulty
	pile.show_charge_count = show_charge_labels
	if difficulty >= 25:
		pile.slow_scavenge_seconds = 15.0
		pile.fast_scavenge_seconds = 6.5
		pile.scavenge_noise_radius = 16.0
	elif difficulty >= 10:
		pile.scavenge_noise_radius = 12.0
	parent.add_child(pile)


func _make_twisted_scrap_heap(parent: Node, position: Vector3) -> void:
	var pile := TWISTED_SCRAP_HEAP_SCENE.instantiate() as ScavengingResourceNode
	pile.name = "TwistedScrapHeap"
	pile.position = position
	pile.show_charge_count = show_charge_labels
	parent.add_child(pile)


func _make_half_buried_robot_wreck(parent: Node, position: Vector3) -> void:
	var pile := HALF_BURIED_ROBOT_WRECK_SCENE.instantiate() as ScavengingResourceNode
	pile.name = "HalfBuriedRobotWreck"
	pile.position = position
	pile.show_charge_count = show_charge_labels
	parent.add_child(pile)


func _ensure_demo_buttons() -> void:
	if get_node_or_null("DemoButtons") != null:
		return
	var buttons := Node3D.new()
	buttons.name = "DemoButtons"
	add_child(buttons)
	_make_button(buttons, "ResetPilesButton", Vector3(-12.6, 0.22, -9.8), "reset_piles", "Reset Piles", Color(0.35, 0.66, 0.36, 1.0))
	_make_button(buttons, "ChargeLabelsButton", Vector3(-10.7, 0.22, -9.8), "toggle_charge_labels", "Toggle Charges", Color(0.72, 0.58, 0.25, 1.0))
	_make_button(buttons, "NoiseButton", Vector3(-8.8, 0.22, -9.8), "toggle_noise_radius", "Toggle Noise", Color(0.56, 0.35, 0.94, 1.0))
	_make_button(buttons, "NoviceButton", Vector3(-6.9, 0.22, -9.8), "select_novice", "Select Novice", Color(0.68, 0.45, 0.28, 1.0))
	_make_button(buttons, "ExpertButton", Vector3(-5.0, 0.22, -9.8), "select_expert", "Select Expert", Color(0.2, 0.55, 0.82, 1.0))
	_make_button(buttons, "FillInventoryButton", Vector3(-3.1, 0.22, -9.8), "fill_inventory", "Fill Inventory", Color(0.78, 0.28, 0.22, 1.0))


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
	shape.size = Vector3(1.0, 0.35, 0.9)
	collision.shape = shape
	button.add_child(collision)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _make_material(color, 0.62)
	button.add_child(mesh_instance)
	var label := Label3D.new()
	label.text = label_text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 26
	label.outline_size = 4
	label.position = Vector3(0.0, 0.58, 0.0)
	button.add_child(label)


func _ensure_noise_radius_visuals() -> void:
	if not noise_radius_visuals.is_empty():
		return
	var root_node := Node3D.new()
	root_node.name = "NoiseRadiusVisuals"
	add_child(root_node)
	for pile in _get_scrap_piles():
		var visual := MeshInstance3D.new()
		visual.name = "%sNoiseRadius" % pile.name
		visual.top_level = true
		visual.mesh = _build_radius_disc_mesh(pile.scavenge_noise_radius)
		visual.material_override = _make_transparent_material(Color(0.56, 0.35, 0.94, 0.18))
		visual.visible = false
		visual.set_meta("pile_path", get_path_to(pile))
		root_node.add_child(visual)
		noise_radius_visuals.append(visual)


func _update_noise_radius_visuals() -> void:
	for visual in noise_radius_visuals:
		if visual == null:
			continue
		var pile_path := NodePath(str(visual.get_meta("pile_path", "")))
		var pile := get_node_or_null(pile_path) as ScavengingResourceNode
		visual.visible = show_noise_radius and pile != null and is_instance_valid(pile)
		if pile == null or not is_instance_valid(pile):
			continue
		visual.global_position = Vector3(pile.global_position.x, 0.045, pile.global_position.z)


func _build_radius_disc_mesh(radius: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 48
	for index in range(segments):
		var a0 := TAU * float(index) / float(segments)
		var a1 := TAU * float(index + 1) / float(segments)
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(cos(a0) * radius, 0.0, sin(a0) * radius))
		st.add_vertex(Vector3(cos(a1) * radius, 0.0, sin(a1) * radius))
	return st.commit()


func _get_scrap_piles() -> Array[ScavengingResourceNode]:
	var piles: Array[ScavengingResourceNode] = []
	var root_node := get_node_or_null("ScrapPiles")
	if root_node == null:
		return piles
	for child in root_node.get_children():
		if child is ScavengingResourceNode:
			piles.append(child as ScavengingResourceNode)
	return piles


func _select_member(member: HumanoidCharacter) -> void:
	var party_manager := get_node_or_null("PartyManager") as PartyManager
	if party_manager != null and member != null:
		party_manager.select_only(member)


func _fill_selected_inventories() -> int:
	var party_manager := get_node_or_null("PartyManager") as PartyManager
	if party_manager == null:
		return 0
	var filled := 0
	for member in party_manager.selected_members:
		while member.inventory.can_add_item(ROBOT_PARTS):
			if not member.inventory.add_item(ROBOT_PARTS):
				break
		filled += 1
	return filled


func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


func _make_transparent_material(color: Color) -> StandardMaterial3D:
	var material := _make_material(color, 0.8)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
