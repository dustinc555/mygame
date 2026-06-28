extends Node3D

const PARTY_MEMBER_SCRIPT = preload("res://features/core/party/party_member.gd")
const HUMANOID_SCRIPT = preload("res://features/actors/projection/humanoid/humanoid_character.gd")
const SELECTION_RING_VISUAL = preload("res://features/actors/projection/selection_ring_visual.gd")

const IRON_SWORD = preload("res://features/inventory/resources/items/iron_sword.tres")
const IRON_AXE = preload("res://features/inventory/resources/items/iron_axe.tres")
const IRON_DAGGER = preload("res://features/inventory/resources/items/iron_dagger.tres")
const STEEL_SWORD = preload("res://features/inventory/resources/items/steel_sword.tres")
const GOLDEN_SWORD = preload("res://features/inventory/resources/items/golden_sword.tres")
const HATCHET = preload("res://features/inventory/resources/items/hatchet.tres")
const STEEL_DAGGER = preload("res://features/inventory/resources/items/steel_dagger.tres")
const WAR_HAMMER = preload("res://features/inventory/resources/items/war_hammer.tres")
const ROUND_SHIELD = preload("res://features/inventory/resources/items/round_shield.tres")
const HEATER_SHIELD = preload("res://features/inventory/resources/items/heater_shield.tres")
const HEATER_SHIELD_2 = preload("res://features/inventory/resources/items/heater_shield_2.tres")
const ROUND_SHIELD_2 = preload("res://features/inventory/resources/items/round_shield_2.tres")
const GOLDEN_CELTIC_SHIELD = preload("res://features/inventory/resources/items/golden_celtic_shield.tres")
const PEASANT_TUNIC = preload("res://features/inventory/resources/items/peasant_tunic.tres")
const PEASANT_TROUSERS = preload("res://features/inventory/resources/items/peasant_trousers.tres")
const PEASANT_SHOES = preload("res://features/inventory/resources/items/peasant_shoes.tres")
const RANGER_JERKIN = preload("res://features/inventory/resources/items/ranger_jerkin.tres")
const RANGER_LEGGINGS = preload("res://features/inventory/resources/items/ranger_leggings.tres")
const RANGER_BOOTS = preload("res://features/inventory/resources/items/ranger_boots.tres")
const RANGER_HOOD = preload("res://features/inventory/resources/items/ranger_hood.tres")
const KNIGHT_GAMBESON = preload("res://features/inventory/resources/items/knight_gambeson.tres")
const KNIGHT_CUIRASS = preload("res://features/inventory/resources/items/knight_cuirass.tres")
const KNIGHT_GAUNTLETS = preload("res://features/inventory/resources/items/knight_gauntlets.tres")
const KNIGHT_GREVES = preload("res://features/inventory/resources/items/knight_greaves.tres")
const KNIGHT_SABATONS = preload("res://features/inventory/resources/items/knight_sabatons.tres")
const KNIGHT_ARMET = preload("res://features/inventory/resources/items/knight_armet.tres")
const KNIGHT_HORNED_HELM = preload("res://features/inventory/resources/items/knight_horned_helm.tres")
const NOBLE_DOUBLET = preload("res://features/inventory/resources/items/noble_doublet.tres")
const NOBLE_SLEEVES = preload("res://features/inventory/resources/items/noble_sleeves.tres")
const NOBLE_TROUSERS = preload("res://features/inventory/resources/items/noble_trousers.tres")
const NOBLE_SHOES = preload("res://features/inventory/resources/items/noble_shoes.tres")
const NOBLE_CROWN = preload("res://features/inventory/resources/items/noble_crown.tres")
const WIZARD_ROBES = preload("res://features/inventory/resources/items/wizard_robes.tres")
const WIZARD_SLEEVES = preload("res://features/inventory/resources/items/wizard_sleeves.tres")
const WIZARD_TROUSERS = preload("res://features/inventory/resources/items/wizard_trousers.tres")
const WIZARD_SHOES = preload("res://features/inventory/resources/items/wizard_shoes.tres")

const TEAM_SIZE := 50

const PARTY_CONFIGS := [
	{"name": "Mira", "color": Color(0.72, 0.48, 0.78, 1.0), "equipment": [STEEL_SWORD, ROUND_SHIELD, RANGER_JERKIN, RANGER_LEGGINGS, RANGER_BOOTS, RANGER_HOOD], "hp": 118.0, "damage": 20.0, "block": 0.1},
	{"name": "Tomas", "color": Color(0.35, 0.56, 0.42, 1.0), "equipment": [IRON_AXE, PEASANT_TUNIC, PEASANT_TROUSERS, PEASANT_SHOES], "hp": 116.0, "damage": 20.0, "dodge": 0.1},
	{"name": "Sable", "color": Color(0.58, 0.72, 0.38, 1.0), "equipment": [IRON_DAGGER, HEATER_SHIELD, KNIGHT_GAMBESON, KNIGHT_CUIRASS, KNIGHT_GAUNTLETS, KNIGHT_GREVES, KNIGHT_SABATONS, KNIGHT_ARMET], "hp": 126.0, "damage": 19.0, "block": 0.12},
	{"name": "Vale", "color": Color(0.77, 0.67, 0.38, 1.0), "equipment": [HATCHET, NOBLE_DOUBLET, NOBLE_SLEEVES, NOBLE_TROUSERS, NOBLE_SHOES, NOBLE_CROWN], "hp": 112.0, "damage": 19.5, "dodge": 0.11},
	{"name": "Nika", "color": Color(0.67, 0.45, 0.75, 1.0), "equipment": [IRON_SWORD, ROUND_SHIELD_2, WIZARD_ROBES, WIZARD_SLEEVES, WIZARD_TROUSERS, WIZARD_SHOES], "hp": 114.0, "damage": 19.0, "block": 0.1},
	{"name": "Bram", "color": Color(0.33, 0.55, 0.78, 1.0), "equipment": [STEEL_DAGGER, RANGER_JERKIN, RANGER_LEGGINGS, RANGER_BOOTS], "hp": 112.0, "damage": 19.0, "dodge": 0.12},
	{"name": "Avery", "color": Color(0.84, 0.43, 0.31, 1.0), "equipment": [GOLDEN_SWORD, GOLDEN_CELTIC_SHIELD, KNIGHT_GAMBESON, KNIGHT_CUIRASS, KNIGHT_GAUNTLETS, KNIGHT_GREVES, KNIGHT_SABATONS, KNIGHT_HORNED_HELM], "hp": 128.0, "damage": 20.5, "block": 0.12},
	{"name": "Cora", "color": Color(0.42, 0.72, 0.4, 1.0), "equipment": [IRON_AXE, HEATER_SHIELD_2, NOBLE_DOUBLET, NOBLE_SLEEVES, NOBLE_TROUSERS, NOBLE_SHOES], "hp": 116.0, "damage": 19.5, "block": 0.1},
	{"name": "Garrick", "color": Color(0.52, 0.62, 0.7, 1.0), "equipment": [WAR_HAMMER, ROUND_SHIELD, WIZARD_ROBES, WIZARD_TROUSERS, WIZARD_SHOES], "hp": 118.0, "damage": 20.0, "block": 0.1},
	{"name": "Orla", "color": Color(0.81, 0.61, 0.48, 1.0), "equipment": [HATCHET, PEASANT_TUNIC, RANGER_LEGGINGS, RANGER_BOOTS], "hp": 112.0, "damage": 19.0, "dodge": 0.12},
	{"name": "Iris", "color": Color(0.48, 0.66, 0.82, 1.0), "equipment": [STEEL_SWORD, HEATER_SHIELD, KNIGHT_GAMBESON, KNIGHT_CUIRASS, KNIGHT_GREVES, KNIGHT_SABATONS], "hp": 122.0, "damage": 20.0, "block": 0.11},
	{"name": "Rhea", "color": Color(0.76, 0.39, 0.55, 1.0), "equipment": [IRON_DAGGER, ROUND_SHIELD_2, RANGER_JERKIN, RANGER_LEGGINGS, RANGER_BOOTS, RANGER_HOOD], "hp": 110.0, "damage": 19.0, "dodge": 0.13},
	{"name": "Kaia", "color": Color(0.6, 0.7, 0.42, 1.0), "equipment": [IRON_AXE, HEATER_SHIELD_2, PEASANT_TUNIC, PEASANT_TROUSERS, PEASANT_SHOES], "hp": 116.0, "damage": 19.5, "block": 0.1},
	{"name": "Anya", "color": Color(0.83, 0.68, 0.36, 1.0), "equipment": [GOLDEN_SWORD, NOBLE_DOUBLET, NOBLE_SLEEVES, NOBLE_TROUSERS, NOBLE_SHOES, NOBLE_CROWN], "hp": 114.0, "damage": 20.0, "dodge": 0.11},
	{"name": "Gwen", "color": Color(0.44, 0.76, 0.68, 1.0), "equipment": [WAR_HAMMER, GOLDEN_CELTIC_SHIELD, KNIGHT_GAMBESON, KNIGHT_CUIRASS, KNIGHT_GAUNTLETS, KNIGHT_GREVES, KNIGHT_SABATONS], "hp": 130.0, "damage": 20.5, "block": 0.12},
	{"name": "Cleo", "color": Color(0.73, 0.54, 0.86, 1.0), "equipment": [STEEL_DAGGER, WIZARD_ROBES, WIZARD_SLEEVES, WIZARD_TROUSERS, WIZARD_SHOES], "hp": 108.0, "damage": 18.5, "dodge": 0.13},
	{"name": "Esme", "color": Color(0.68, 0.52, 0.39, 1.0), "equipment": [IRON_SWORD, ROUND_SHIELD, PEASANT_TUNIC, PEASANT_TROUSERS, PEASANT_SHOES], "hp": 114.0, "damage": 19.0, "block": 0.1},
	{"name": "Talia", "color": Color(0.9, 0.5, 0.42, 1.0), "equipment": [HATCHET, HEATER_SHIELD, RANGER_JERKIN, RANGER_LEGGINGS, RANGER_BOOTS], "hp": 116.0, "damage": 19.5, "block": 0.1},
	{"name": "Quinn", "color": Color(0.38, 0.64, 0.9, 1.0), "equipment": [STEEL_SWORD, KNIGHT_GAMBESON, KNIGHT_CUIRASS, KNIGHT_GREVES, KNIGHT_SABATONS, KNIGHT_ARMET], "hp": 124.0, "damage": 20.0, "dodge": 0.1},
	{"name": "Vera", "color": Color(0.78, 0.76, 0.46, 1.0), "equipment": [IRON_AXE, GOLDEN_CELTIC_SHIELD, NOBLE_DOUBLET, NOBLE_TROUSERS, NOBLE_SHOES], "hp": 118.0, "damage": 19.5, "block": 0.11},
]

const RAIDER_LOADOUTS := [
	[IRON_SWORD, PEASANT_TUNIC, PEASANT_TROUSERS, PEASANT_SHOES],
	[IRON_AXE, ROUND_SHIELD, RANGER_JERKIN, RANGER_LEGGINGS, RANGER_BOOTS],
	[IRON_DAGGER, HEATER_SHIELD, NOBLE_DOUBLET, NOBLE_SLEEVES, NOBLE_TROUSERS, NOBLE_SHOES],
	[STEEL_SWORD, KNIGHT_GAMBESON, KNIGHT_CUIRASS, KNIGHT_GREVES, KNIGHT_SABATONS, KNIGHT_ARMET],
	[HATCHET, HEATER_SHIELD_2, WIZARD_ROBES, WIZARD_SLEEVES, WIZARD_TROUSERS, WIZARD_SHOES],
	[STEEL_DAGGER, ROUND_SHIELD_2, RANGER_JERKIN, RANGER_BOOTS, RANGER_HOOD],
	[GOLDEN_SWORD, NOBLE_DOUBLET, NOBLE_TROUSERS, NOBLE_SHOES, NOBLE_CROWN],
	[WAR_HAMMER, GOLDEN_CELTIC_SHIELD, KNIGHT_GAMBESON, KNIGHT_CUIRASS, KNIGHT_GAUNTLETS, KNIGHT_GREVES, KNIGHT_SABATONS],
]

var _spawned := false


func _ready() -> void:
	if _spawned:
		return
	_spawned = true
	_spawn_party_members()
	_spawn_raiders()


func _spawn_party_members() -> void:
	var party_root := get_node_or_null("PartyMembers") as Node3D
	if party_root == null:
		return
	for index in range(TEAM_SIZE):
		var config: Dictionary = PARTY_CONFIGS[index % PARTY_CONFIGS.size()]
		var actor := PARTY_MEMBER_SCRIPT.new() as HumanoidCharacter
		actor.name = _party_actor_name(config, index)
		actor.member_name = _party_actor_name(config, index)
		actor.faction_name = "Player"
		actor.squad_name = "Armory50Party"
		actor.hostile_factions = PackedStringArray(["Raiders"])
		actor.combat_stance = NpcRules.CombatStance.DEFENSIVE
		actor.base_color = _party_color(config, index)
		actor.position = _party_position(index)
		actor.starting_equipment = _equipment_array(config["equipment"])
		actor.max_hp = float(config.get("hp", 115.0))
		actor.hp = actor.max_hp
		actor.base_attack_damage = float(config.get("damage", 19.0))
		actor.base_dodge_chance = float(config.get("dodge", 0.08))
		actor.base_block_chance = float(config.get("block", 0.06))
		_add_basic_actor_children(actor, actor.base_color, true)
		party_root.add_child(actor)


func _spawn_raiders() -> void:
	for index in range(TEAM_SIZE):
		var actor := HUMANOID_SCRIPT.new() as HumanoidCharacter
		actor.name = "Raider%02d" % (index + 1)
		actor.member_name = "Raider %02d" % (index + 1)
		actor.faction_name = "Raiders"
		actor.squad_name = "Armory50Raiders"
		actor.hostile_factions = PackedStringArray(["Player"])
		actor.combat_stance = NpcRules.CombatStance.AGGRESSIVE
		actor.position = _raider_position(index)
		actor.rotation.y = PI
		actor.starting_equipment = _equipment_array(RAIDER_LOADOUTS[index % RAIDER_LOADOUTS.size()])
		actor.max_hp = 104.0 + float(index % 6) * 2.0
		actor.hp = actor.max_hp
		actor.base_attack_damage = 17.0 + float(index % 5) * 0.35
		actor.base_dodge_chance = 0.08 if index % 3 == 0 else 0.06
		actor.base_block_chance = 0.08 if index % 2 == 0 else 0.06
		_add_basic_actor_children(actor, Color(0.64, 0.22, 0.16, 1.0).lerp(Color(0.95, 0.6, 0.32, 1.0), float(index % 5) * 0.14), false)
		add_child(actor)


func _party_actor_name(config: Dictionary, index: int) -> String:
	var base_name := str(config["name"])
	return base_name if index < PARTY_CONFIGS.size() else "%s %02d" % [base_name, index + 1]


func _party_color(config: Dictionary, index: int) -> Color:
	var base_color: Color = config["color"]
	return base_color.lerp(Color(0.9, 0.92, 1.0, 1.0), float(index / PARTY_CONFIGS.size()) * 0.12)


func _party_position(index: int) -> Vector3:
	var column := index / 10
	var row := index % 10
	return Vector3(-9.0 + float(column) * 2.0, 0.6, -13.5 + float(row) * 3.0)


func _raider_position(index: int) -> Vector3:
	var column := index / 10
	var row := index % 10
	return Vector3(9.0 - float(column) * 2.0, 0.6, -13.5 + float(row) * 3.0)


func _equipment_array(items: Array) -> Array[Resource]:
	var result: Array[Resource] = []
	for item in items:
		if item is Resource:
			result.append(item)
	return result


func _add_basic_actor_children(actor: HumanoidCharacter, color: Color, include_selection_ring: bool) -> void:
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.transform = Transform3D(Basis(), Vector3(0.0, 0.95, 0.0))
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = 0.45
	capsule_shape.height = 1.1
	collision.shape = capsule_shape
	actor.add_child(collision)

	var body := MeshInstance3D.new()
	body.name = "BodyMesh"
	body.transform = Transform3D(Basis(), Vector3(0.0, 0.95, 0.0))
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = 0.45
	body.mesh = capsule_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	body.material_override = material
	actor.add_child(body)

	if include_selection_ring:
		var ring := MeshInstance3D.new()
		ring.name = "SelectionRing"
		ring.transform = Transform3D(Basis(), Vector3(0.0, 0.03, 0.0))
		SELECTION_RING_VISUAL.setup_ring(ring)
		actor.add_child(ring)
