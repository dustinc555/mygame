extends Node3D

const PARTY_MEMBER_SCRIPT = preload("res://scripts/party_member.gd")
const FACTION_HUMANOID_SCRIPT = preload("res://scripts/characters/faction_humanoid.gd")
const SETTLEMENT_TOWN_SCRIPT = preload("res://scripts/world_sim/settlement_town.gd")
const SETTLEMENT_DEFINITION_SCRIPT = preload("res://scripts/world_sim/settlement_definition.gd")
const SETTLEMENT_JAIL_SCENE = preload("res://scenes/world_sim/settlement_jail.tscn")
const WORLD_ITEM_SCENE = preload("res://scenes/world/items/world_item.tscn")
const FARMERS_FACTION = preload("res://resources/world_sim/factions/farmers.tres")
const EXPENSIVE_VASE = preload("res://resources/items/expensive_vase.tres")

const DEMO_FACTION_ID := "Farmers"
const DEMO_SETTLEMENT_ID := "jail_demo_town"
const JAIL_POSITION := Vector3(10.0, 0.0, 4.0)
const PLAYER_START_POSITION := Vector3(-10.0, 0.6, -7.0)
const WITNESS_POSITION := Vector3(-5.0, 0.6, -3.0)
const VASE_POSITION := Vector3(-7.0, 0.45, -4.0)
const INSTRUCTION_LABEL_POSITION := Vector3(-14.5, 3.0, -13.0)

var player: HumanoidCharacter
var witness: HumanoidCharacter


func _ready() -> void:
	_ensure_lighting()
	_ensure_floor()
	_ensure_demo_settlement()
	_ensure_player()
	call_deferred("_finish_demo_setup")


func _finish_demo_setup() -> void:
	await get_tree().process_frame
	var party_manager := get_node_or_null("PartyManager") as PartyManager
	if party_manager != null and player != null:
		party_manager.select_only(player)
	var world_time := get_node_or_null("GameBootstrap/WorldTimeController") as WorldTimeController
	if world_time != null:
		world_time.total_world_minutes = 13.0 * 60.0


func _ensure_demo_settlement() -> void:
	var settlement := get_node_or_null("JailDemoTown") as Node3D
	if settlement == null:
		settlement = SETTLEMENT_TOWN_SCRIPT.new()
		settlement.name = "JailDemoTown"
		add_child(settlement)
	settlement.set("settlement_definition", _make_demo_settlement_definition())
	settlement.set("resident_root_path", NodePath("Residents"))
	settlement.set("guard_count", 1)
	settlement.set("guard_post_count", 1)
	settlement.set("guard_name", "City Guard")
	settlement.set("staff_stable_id_prefix", "npc.jail_demo_town.town")
	settlement.set("staff_squad_name", "JailDemoTown")
	settlement.set("town_border_radius", 26.0)
	settlement.set("editor_show_debug_shape", false)

	var facilities := settlement.get_node_or_null("Facilities") as Node3D
	if facilities == null:
		facilities = Node3D.new()
		facilities.name = "Facilities"
		settlement.add_child(facilities)

	var residents := settlement.get_node_or_null("Residents") as Node3D
	if residents == null:
		residents = Node3D.new()
		residents.name = "Residents"
		settlement.add_child(residents)

	_ensure_jail(facilities)
	_ensure_witness(residents)
	_ensure_owned_vase(settlement)


func _make_demo_settlement_definition() -> Resource:
	var definition: Resource = SETTLEMENT_DEFINITION_SCRIPT.new()
	definition.set("settlement_id", DEMO_SETTLEMENT_ID)
	definition.set("display_name", "Jail Demo Town")
	definition.set("faction_definition", FARMERS_FACTION)
	definition.set("starting_food", 80.0)
	definition.set("max_food", 80.0)
	return definition


func _ensure_jail(facilities: Node) -> void:
	var jail := facilities.get_node_or_null("Jail") as Node3D
	var created := false
	if jail == null:
		jail = SETTLEMENT_JAIL_SCENE.instantiate() as Node3D
		jail.name = "Jail"
		facilities.add_child(jail)
		created = true
	if created:
		jail.position = JAIL_POSITION
		jail.set("facility_id", "%s.jail" % DEMO_SETTLEMENT_ID)
		jail.set("display_name", "Demo Jail")
		jail.set("owner_faction_id", DEMO_FACTION_ID)
		jail.set("warden_name", "Demo Warden")
		jail.set("guard_name", "Jail Guard")
		jail.set("guard_count", 1)
		jail.set("guard_post_count", 1)
		jail.set("cell_count", 3)
		jail.set("prisoners_per_cell", 1)
		var difficulties: Array[int] = [5, 35, 90]
		jail.set("cell_lock_difficulties", difficulties)
		jail.set("locker_lock_difficulty", 90)
		jail.set("staff_stable_id_prefix", "npc.jail_demo_town.jail")
		jail.set("staff_squad_name", "JailDemoTown")
	_configure_jail_building(jail)


func _configure_jail_building(jail: Node) -> void:
	var building := jail.get_node_or_null("BuildingSlot/CurrentBuilding")
	if building == null:
		return
	if _has_property(building, "building_type"):
		building.set("building_type", "jail")
	if _has_property(building, "access_mode"):
		building.set("access_mode", "public")
	if _has_property(building, "use_law_profile_trespass_rules"):
		building.set("use_law_profile_trespass_rules", false)


func _ensure_witness(residents: Node) -> void:
	witness = residents.get_node_or_null("Witness") as HumanoidCharacter
	if witness == null:
		witness = _make_humanoid("Witness", FACTION_HUMANOID_SCRIPT, WITNESS_POSITION, Color(0.56, 0.63, 0.76, 1.0), DEMO_FACTION_ID, false)
		residents.add_child(witness)
	witness.position = WITNESS_POSITION
	witness.member_name = "Civilian Witness"
	witness.stable_id = "npc.jail_demo_town.witness"
	witness.combat_stance = NpcRules.CombatStance.PASSIVE
	witness.fatigue_enabled = false
	witness.set_skill_level(SkillRules.ATTRIBUTE_PERCEPTION, 40)
	witness.look_at(Vector3(VASE_POSITION.x, witness.global_position.y, VASE_POSITION.z), Vector3.UP)
	witness.rotation.x = 0.0
	witness.rotation.z = 0.0


func _ensure_owned_vase(settlement: Node) -> void:
	var vase := settlement.get_node_or_null("OwnedVase")
	if vase == null:
		vase = WORLD_ITEM_SCENE.instantiate()
		vase.name = "OwnedVase"
		settlement.add_child(vase)
	vase.set("item_definition", EXPENSIVE_VASE)
	vase.set("quantity", 1)
	vase.set("owner_faction_name", DEMO_FACTION_ID)
	vase.set("theft_value", 18)
	vase.set("theft_difficulty", 1)
	vase.set("theft_noise_radius", 0.0)
	if vase is Node3D:
		(vase as Node3D).global_position = VASE_POSITION


func _ensure_player() -> void:
	var party_root := get_node_or_null("PartyMembers") as Node3D
	if party_root == null:
		party_root = Node3D.new()
		party_root.name = "PartyMembers"
		add_child(party_root)
	var existing := party_root.get_node_or_null("Mira") as HumanoidCharacter
	if existing != null:
		player = existing
		player.position = PLAYER_START_POSITION
		player.member_name = "Mira"
		player.stable_id = "player.jail_demo.mira"
		player.faction_name = "Player"
		player.fatigue_enabled = false
		player.set_skill_level(SkillRules.SUBTERFUGE_SLEIGHT_OF_HAND, 5)
		return
	player = _make_humanoid("Mira", PARTY_MEMBER_SCRIPT, PLAYER_START_POSITION, Color(0.82, 0.43, 0.31, 1.0), "Player", true)
	player.stable_id = "player.jail_demo.mira"
	player.fatigue_enabled = false
	player.set_skill_level(SkillRules.SUBTERFUGE_SLEIGHT_OF_HAND, 5)
	party_root.add_child(player)


func _make_humanoid(node_name: String, script_resource: Script, local_position: Vector3, color: Color, faction_id: String, with_selection_ring: bool) -> HumanoidCharacter:
	var character := CharacterBody3D.new()
	character.name = node_name
	character.set_script(script_resource)
	character.position = local_position
	character.set("base_color", color)
	character.set("member_name", node_name)
	character.set("faction_name", faction_id)

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
	body_mesh.material_override = _make_material(color, 0.86)
	character.add_child(body_mesh)

	if with_selection_ring:
		var ring := MeshInstance3D.new()
		ring.name = "SelectionRing"
		var ring_mesh := CylinderMesh.new()
		ring_mesh.top_radius = 0.78
		ring_mesh.bottom_radius = 0.78
		ring_mesh.height = 0.018
		ring_mesh.radial_segments = 48
		ring.mesh = ring_mesh
		ring.position.y = 0.035
		ring.visible = false
		character.add_child(ring)

	return character as HumanoidCharacter


func _ensure_lighting() -> void:
	if get_node_or_null("Sun") == null:
		var sun := DirectionalLight3D.new()
		sun.name = "Sun"
		sun.rotation_degrees = Vector3(-58.0, -28.0, 0.0)
		sun.light_energy = 1.25
		sun.shadow_enabled = true
		add_child(sun)
	var label := get_node_or_null("InstructionLabel") as Label3D
	if label == null:
		label = Label3D.new()
		label.name = "InstructionLabel"
		add_child(label)
	label.position = INSTRUCTION_LABEL_POSITION
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 36
	label.outline_size = 4
	label.text = "Jail Law Demo: steal the owned vase in front of the witness. The city guard responds; jail has 3 cells and a very hard prisoner locker."


func _ensure_floor() -> void:
	if get_node_or_null("Floor") != null:
		return
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	add_child(floor_body)

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(34.0, 1.0, 28.0)
	shape.shape = box_shape
	floor_body.add_child(shape)

	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box_shape.size
	mesh_instance.mesh = box_mesh
	mesh_instance.material_override = _make_material(Color(0.24, 0.23, 0.20, 1.0), 0.94)
	floor_body.add_child(mesh_instance)


func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


func _has_property(target: Object, property_name: String) -> bool:
	if target == null:
		return false
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false
