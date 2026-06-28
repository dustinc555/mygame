extends Node3D

const PARTY_MEMBER_SCRIPT = preload("res://features/core/party/party_member.gd")
const HUMANOID_SCRIPT = preload("res://features/actors/projection/humanoid/humanoid_character.gd")
const RUSTDEAD_HUMANOID_SCRIPT = preload("res://features/actors/projection/rustdead/rustdead_humanoid_character.gd")
const QUADBOT_CHARACTER_SCRIPT = preload("res://features/actors/projection/quadbot/quadbot_character.gd")
const SELECTION_RING_VISUAL = preload("res://features/actors/projection/selection_ring_visual.gd")
const APPEARANCE_DATA_SCRIPT = preload("res://features/actors/resources/character_appearance/character_appearance_data.gd")
const RUSTDEAD_TIER_LIBRARY = preload("res://features/actors/projection/rustdead/rustdead_tier_library.gd")

const HUMAN_RACE = preload("res://features/actors/resources/character_races/human.tres")
const RUSTDEAD_RACE = preload("res://features/actors/resources/character_races/rustdead.tres")
const HUMAN_MALE_BODY_ARCHETYPE = preload("res://features/actors/resources/character_body_archetypes/human_male.tres")
const HUMAN_FEMALE_BODY_ARCHETYPE = preload("res://features/actors/resources/character_body_archetypes/human_female.tres")

const IRON_SWORD = preload("res://features/inventory/resources/items/iron_sword.tres")
const IRON_AXE = preload("res://features/inventory/resources/items/iron_axe.tres")
const IRON_DAGGER = preload("res://features/inventory/resources/items/iron_dagger.tres")
const STEEL_SWORD = preload("res://features/inventory/resources/items/steel_sword.tres")
const STEEL_DAGGER = preload("res://features/inventory/resources/items/steel_dagger.tres")
const GOLDEN_SWORD = preload("res://features/inventory/resources/items/golden_sword.tres")
const HATCHET = preload("res://features/inventory/resources/items/hatchet.tres")
const WAR_HAMMER = preload("res://features/inventory/resources/items/war_hammer.tres")
const ROUND_SHIELD = preload("res://features/inventory/resources/items/round_shield.tres")
const HEATER_SHIELD = preload("res://features/inventory/resources/items/heater_shield.tres")
const HEATER_SHIELD_2 = preload("res://features/inventory/resources/items/heater_shield_2.tres")
const CELTIC_SHIELD = preload("res://features/inventory/resources/items/golden_celtic_shield.tres")
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
const KNIGHT_GREAVES = preload("res://features/inventory/resources/items/knight_greaves.tres")
const KNIGHT_SABATONS = preload("res://features/inventory/resources/items/knight_sabatons.tres")
const KNIGHT_ARMET = preload("res://features/inventory/resources/items/knight_armet.tres")
const NOBLE_DOUBLET = preload("res://features/inventory/resources/items/noble_doublet.tres")
const NOBLE_SLEEVES = preload("res://features/inventory/resources/items/noble_sleeves.tres")
const NOBLE_TROUSERS = preload("res://features/inventory/resources/items/noble_trousers.tres")
const NOBLE_SHOES = preload("res://features/inventory/resources/items/noble_shoes.tres")
const WIZARD_ROBES = preload("res://features/inventory/resources/items/wizard_robes.tres")
const WIZARD_SLEEVES = preload("res://features/inventory/resources/items/wizard_sleeves.tres")
const WIZARD_TROUSERS = preload("res://features/inventory/resources/items/wizard_trousers.tres")
const WIZARD_SHOES = preload("res://features/inventory/resources/items/wizard_shoes.tres")

const PLAYER_FACTION := "Player"
const RAIDER_FACTION := "Raiders"
const CINDER_FACTION := "CinderHorde"
const PLAYER_SQUAD := "FreeForAllParty"
const RAIDER_SQUAD := "FreeForAllRaiders"
const CINDER_SQUAD := "FreeForAllCinderPack"
const RANDOM_SEED := 515155
const VISUAL_BODY_TYPE_MALE := 2
const VISUAL_BODY_TYPE_FEMALE := 3

const PLAYER_CONFIGS := [
	{"name": "Mira", "body": VISUAL_BODY_TYPE_FEMALE, "skin": Color(0.88, 0.68, 0.54, 1.0), "color": Color(0.72, 0.48, 0.78, 1.0), "skill": 58, "equipment": [STEEL_SWORD, ROUND_SHIELD, RANGER_JERKIN, RANGER_LEGGINGS, RANGER_BOOTS, RANGER_HOOD]},
	{"name": "Tomas", "body": VISUAL_BODY_TYPE_MALE, "skin": Color(0.66, 0.43, 0.30, 1.0), "color": Color(0.35, 0.56, 0.42, 1.0), "skill": 54, "equipment": [IRON_AXE, PEASANT_TUNIC, PEASANT_TROUSERS, PEASANT_SHOES]},
	{"name": "Sable", "body": VISUAL_BODY_TYPE_FEMALE, "skin": Color(0.80, 0.58, 0.43, 1.0), "color": Color(0.58, 0.72, 0.38, 1.0), "skill": 50, "equipment": [IRON_DAGGER, HEATER_SHIELD, KNIGHT_GAMBESON, KNIGHT_CUIRASS, KNIGHT_GAUNTLETS, KNIGHT_GREAVES, KNIGHT_SABATONS, KNIGHT_ARMET]},
	{"name": "Bram", "body": VISUAL_BODY_TYPE_MALE, "skin": Color(0.49, 0.31, 0.22, 1.0), "color": Color(0.33, 0.55, 0.78, 1.0), "skill": 48, "equipment": [HATCHET, NOBLE_DOUBLET, NOBLE_SLEEVES, NOBLE_TROUSERS, NOBLE_SHOES]},
	{"name": "Nika", "body": VISUAL_BODY_TYPE_FEMALE, "skin": Color(0.74, 0.45, 0.31, 1.0), "color": Color(0.67, 0.45, 0.75, 1.0), "skill": 52, "equipment": [IRON_SWORD, CELTIC_SHIELD, WIZARD_ROBES, WIZARD_SLEEVES, WIZARD_TROUSERS, WIZARD_SHOES]},
]

const RAIDER_CONFIGS := [
	{"name": "Raider A", "body": VISUAL_BODY_TYPE_MALE, "skin": Color(0.58, 0.39, 0.27, 1.0), "color": Color(0.63, 0.22, 0.18, 1.0), "skill": 47, "equipment": [IRON_SWORD, PEASANT_TUNIC, PEASANT_TROUSERS, PEASANT_SHOES]},
	{"name": "Raider B", "body": VISUAL_BODY_TYPE_FEMALE, "skin": Color(0.76, 0.53, 0.38, 1.0), "color": Color(0.62, 0.33, 0.16, 1.0), "skill": 49, "equipment": [IRON_AXE, ROUND_SHIELD, RANGER_JERKIN, RANGER_LEGGINGS, RANGER_BOOTS]},
	{"name": "Raider C", "body": VISUAL_BODY_TYPE_MALE, "skin": Color(0.46, 0.31, 0.22, 1.0), "color": Color(0.48, 0.24, 0.18, 1.0), "skill": 45, "equipment": [STEEL_DAGGER, HEATER_SHIELD_2, NOBLE_DOUBLET, NOBLE_TROUSERS, NOBLE_SHOES]},
	{"name": "Raider D", "body": VISUAL_BODY_TYPE_MALE, "skin": Color(0.69, 0.49, 0.35, 1.0), "color": Color(0.54, 0.19, 0.15, 1.0), "skill": 53, "equipment": [WAR_HAMMER, KNIGHT_GAMBESON, KNIGHT_CUIRASS, KNIGHT_GREAVES, KNIGHT_SABATONS]},
	{"name": "Raider E", "body": VISUAL_BODY_TYPE_FEMALE, "skin": Color(0.82, 0.61, 0.45, 1.0), "color": Color(0.58, 0.28, 0.22, 1.0), "skill": 51, "equipment": [GOLDEN_SWORD, HEATER_SHIELD, WIZARD_ROBES, WIZARD_TROUSERS, WIZARD_SHOES]},
]

const RUSTDEAD_CHEST_ITEMS := [PEASANT_TUNIC, RANGER_JERKIN, NOBLE_DOUBLET, WIZARD_ROBES]
const RUSTDEAD_HAND_ITEMS := [NOBLE_SLEEVES, WIZARD_SLEEVES]
const RUSTDEAD_LEG_ITEMS := [PEASANT_TROUSERS, RANGER_LEGGINGS, NOBLE_TROUSERS, WIZARD_TROUSERS, KNIGHT_GREAVES]
const RUSTDEAD_FEET_ITEMS := [PEASANT_SHOES, RANGER_BOOTS, NOBLE_SHOES, WIZARD_SHOES, KNIGHT_SABATONS]
const RUSTDEAD_HEAD_ITEMS := [RANGER_HOOD]

var _spawned := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if _spawned:
		return
	_spawned = true
	_rng.seed = RANDOM_SEED
	_spawn_player_party()
	_spawn_raiders()
	_spawn_cinder_squad()


func _spawn_player_party() -> void:
	var party_root := get_node_or_null("PartyMembers") as Node3D
	if party_root == null:
		party_root = Node3D.new()
		party_root.name = "PartyMembers"
		add_child(party_root)
	for index in range(PLAYER_CONFIGS.size()):
		var config: Dictionary = PLAYER_CONFIGS[index]
		var actor := PARTY_MEMBER_SCRIPT.new() as PartyMember
		actor.name = str(config["name"])
		actor.member_name = str(config["name"])
		actor.faction_name = PLAYER_FACTION
		actor.squad_name = PLAYER_SQUAD
		actor.player_party_member = true
		actor.hostile_factions = PackedStringArray([RAIDER_FACTION, CINDER_FACTION])
		actor.combat_stance = NpcRules.CombatStance.DEFENSIVE
		actor.position = _line_position(Vector3(-7.0, 0.6, 0.0), Vector3(0.0, 0.0, 2.0), index, PLAYER_CONFIGS.size())
		actor.rotation.y = -PI * 0.5
		actor.base_color = config["color"]
		actor.starting_equipment = _equipment_array(config["equipment"])
		actor.starting_skill_levels = _skill_levels(int(config["skill"]))
		actor.appearance_data = _make_appearance(HUMAN_RACE, int(config["body"]), config["skin"])
		_configure_combat_actor(actor, 132.0, 20.0, 3.2)
		actor.base_dodge_chance = 0.10
		actor.base_block_chance = 0.10
		_add_basic_actor_children(actor, actor.base_color, true)
		party_root.add_child(actor)


func _spawn_raiders() -> void:
	var raider_root := get_node_or_null("Raiders") as Node3D
	if raider_root == null:
		raider_root = Node3D.new()
		raider_root.name = "Raiders"
		add_child(raider_root)
	for index in range(RAIDER_CONFIGS.size()):
		var config: Dictionary = RAIDER_CONFIGS[index]
		var actor := HUMANOID_SCRIPT.new() as HumanoidCharacter
		actor.name = str(config["name"]).replace(" ", "")
		actor.member_name = str(config["name"])
		actor.faction_name = RAIDER_FACTION
		actor.squad_name = RAIDER_SQUAD
		actor.hostile_factions = PackedStringArray([PLAYER_FACTION, CINDER_FACTION])
		actor.combat_stance = NpcRules.CombatStance.AGGRESSIVE
		actor.position = _line_position(Vector3(7.0, 0.6, 0.0), Vector3(0.0, 0.0, 2.0), index, RAIDER_CONFIGS.size())
		actor.rotation.y = PI * 0.5
		actor.starting_equipment = _equipment_array(config["equipment"])
		actor.starting_skill_levels = _skill_levels(int(config["skill"]))
		actor.appearance_data = _make_appearance(HUMAN_RACE, int(config["body"]), config["skin"])
		_configure_combat_actor(actor, 112.0 + float(index % 2) * 6.0, 18.0, 3.15)
		actor.base_dodge_chance = 0.09
		actor.base_block_chance = 0.08
		_add_basic_actor_children(actor, config["color"], false)
		raider_root.add_child(actor)


func _spawn_cinder_squad() -> void:
	var cinder_root := get_node_or_null("CinderHorde") as Node3D
	if cinder_root == null:
		cinder_root = Node3D.new()
		cinder_root.name = "CinderHorde"
		add_child(cinder_root)
	for index in range(4):
		var actor := RUSTDEAD_HUMANOID_SCRIPT.new() as HumanoidCharacter
		var tier := RUSTDEAD_TIER_LIBRARY.get_tier_for_demo_index(index + 2)
		actor.name = "CinderRustdead%02d" % (index + 1)
		actor.member_name = "Cinder %s" % str(tier.get("display_name"))
		actor.faction_name = CINDER_FACTION
		actor.squad_name = CINDER_SQUAD
		actor.hostile_factions = PackedStringArray([PLAYER_FACTION, RAIDER_FACTION])
		actor.combat_stance = NpcRules.CombatStance.AGGRESSIVE
		actor.position = _line_position(Vector3(0.0, 0.6, 7.0), Vector3(2.0, 0.0, 0.0), index, 5)
		actor.rotation.y = PI
		actor.starting_equipment = _equipment_array(_rustdead_clothes(index))
		actor.starting_skill_levels = RUSTDEAD_TIER_LIBRARY.roll_skill_levels(tier, _rng)
		var body_type := VISUAL_BODY_TYPE_FEMALE if index % 2 == 1 else VISUAL_BODY_TYPE_MALE
		if actor.has_method("set_rustdead_tier_definition"):
			actor.call("set_rustdead_tier_definition", tier)
		actor.appearance_data = _make_appearance(RUSTDEAD_RACE, body_type, RUSTDEAD_TIER_LIBRARY.pick_skin_color(tier, _rng))
		RUSTDEAD_TIER_LIBRARY.apply_hair_for_tier(actor.appearance_data, tier, _rng, body_type)
		_configure_combat_actor(actor, RUSTDEAD_TIER_LIBRARY.roll_max_hp(tier, _rng), 13.5, 2.65)
		actor.attack_cut_ratio = 0.05
		actor.base_dodge_chance = 0.025
		actor.base_block_chance = 0.0
		actor.attack_cooldown_seconds = 1.38
		_add_basic_actor_children(actor, Color(0.42, 0.08, 0.07, 1.0), false)
		cinder_root.add_child(actor)

	var bot = QUADBOT_CHARACTER_SCRIPT.new()
	bot.name = "CinderQuadBot"
	bot.member_name = "Cinder Quad Bot"
	bot.faction_name = CINDER_FACTION
	bot.squad_name = CINDER_SQUAD
	bot.hostile_factions = PackedStringArray([PLAYER_FACTION, RAIDER_FACTION])
	bot.combat_stance = NpcRules.CombatStance.AGGRESSIVE
	bot.position = _line_position(Vector3(0.0, 0.6, 7.0), Vector3(2.0, 0.0, 0.0), 4, 5)
	bot.rotation.y = PI
	bot.starting_skill_levels = QUADBOT_CHARACTER_SCRIPT.roll_varied_skill_levels(_rng, 48)
	_configure_combat_actor(bot, 210.0, 17.0, 3.05)
	_add_basic_actor_children(bot, Color(0.38, 0.48, 0.55, 1.0), false)
	cinder_root.add_child(bot)


func _configure_combat_actor(actor: WorldActor, hp_value: float, damage: float, speed: float) -> void:
	actor.max_hp = hp_value
	actor.hp = actor.max_hp
	actor.base_attack_damage = damage
	actor.move_speed = speed
	actor.aggressive_scan_radius = 18.0
	actor.assist_scan_radius = 18.0
	actor.combat_witness_radius = 18.0
	actor.combat_squad_assist_radius = 80.0
	actor.combat_active_attack_slots = 3


func _line_position(center: Vector3, step: Vector3, index: int, count: int) -> Vector3:
	return center + step * (float(index) - float(count - 1) * 0.5)


func _rustdead_clothes(index: int) -> Array:
	var clothes: Array = []
	if index == 0:
		return [_pick_item(RUSTDEAD_LEG_ITEMS)]
	if _rng.randf() < 0.70:
		clothes.append(_pick_item(RUSTDEAD_CHEST_ITEMS))
	if _rng.randf() < 0.35:
		clothes.append(_pick_item(RUSTDEAD_HAND_ITEMS))
	if _rng.randf() < 0.90:
		clothes.append(_pick_item(RUSTDEAD_LEG_ITEMS))
	if _rng.randf() < 0.65:
		clothes.append(_pick_item(RUSTDEAD_FEET_ITEMS))
	if _rng.randf() < 0.25:
		clothes.append(_pick_item(RUSTDEAD_HEAD_ITEMS))
	return clothes


func _pick_item(pool: Array) -> Resource:
	return pool[_rng.randi_range(0, pool.size() - 1)] as Resource


func _equipment_array(items: Array) -> Array[Resource]:
	var result: Array[Resource] = []
	for item in items:
		if item is Resource:
			result.append(item)
	return result


func _skill_levels(level: int) -> Dictionary:
	var result := {}
	for definition in SkillRules.get_all_definitions():
		result[definition.skill_id] = level
	return result


func _make_appearance(race: Resource, body_type: int, skin_color: Color) -> Resource:
	var appearance = APPEARANCE_DATA_SCRIPT.new()
	appearance.character_race = race
	appearance.visual_body_type = body_type
	appearance.body_archetype = HUMAN_FEMALE_BODY_ARCHETYPE if body_type == VISUAL_BODY_TYPE_FEMALE else HUMAN_MALE_BODY_ARCHETYPE
	appearance.skin_color_customized = true
	appearance.skin_color = skin_color
	return appearance


func _add_basic_actor_children(actor: WorldActor, color: Color, include_selection_ring: bool) -> void:
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
	material.roughness = 0.9
	body.material_override = material
	actor.add_child(body)

	if include_selection_ring:
		var ring := MeshInstance3D.new()
		ring.name = "SelectionRing"
		ring.transform = Transform3D(Basis(), Vector3(0.0, 0.03, 0.0))
		ring.visible = false
		SELECTION_RING_VISUAL.setup_ring(ring)
		actor.add_child(ring)
