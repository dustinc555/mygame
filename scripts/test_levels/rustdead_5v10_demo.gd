extends Node3D

const PARTY_MEMBER_SCRIPT = preload("res://scripts/party_member.gd")
const RUSTDEAD_HUMANOID_SCRIPT = preload("res://scripts/characters/rustdead_humanoid_character.gd")
const APPEARANCE_DATA_SCRIPT = preload("res://scripts/character_appearance/character_appearance_data.gd")
const INVENTORY_STOCK_SCRIPT = preload("res://scripts/items/inventory_stock.gd")

const HUMAN_RACE = preload("res://resources/character_races/human.tres")
const RUSTDEAD_RACE = preload("res://resources/character_races/rustdead.tres")
const HUMAN_MALE_BODY_ARCHETYPE = preload("res://resources/character_body_archetypes/human_male.tres")
const HUMAN_FEMALE_BODY_ARCHETYPE = preload("res://resources/character_body_archetypes/human_female.tres")
const RUSTDEAD_TIER_LIBRARY = preload("res://scripts/characters/rustdead_tier_library.gd")

const IRON_SWORD = preload("res://resources/items/iron_sword.tres")
const IRON_AXE = preload("res://resources/items/iron_axe.tres")
const IRON_DAGGER = preload("res://resources/items/iron_dagger.tres")
const STEEL_SWORD = preload("res://resources/items/steel_sword.tres")
const HATCHET = preload("res://resources/items/hatchet.tres")
const ROUND_SHIELD = preload("res://resources/items/round_shield.tres")
const HEATER_SHIELD = preload("res://resources/items/heater_shield.tres")
const PEASANT_TUNIC = preload("res://resources/items/peasant_tunic.tres")
const PEASANT_TROUSERS = preload("res://resources/items/peasant_trousers.tres")
const PEASANT_SHOES = preload("res://resources/items/peasant_shoes.tres")
const RANGER_JERKIN = preload("res://resources/items/ranger_jerkin.tres")
const RANGER_LEGGINGS = preload("res://resources/items/ranger_leggings.tres")
const RANGER_BOOTS = preload("res://resources/items/ranger_boots.tres")
const RANGER_HOOD = preload("res://resources/items/ranger_hood.tres")
const KNIGHT_GAMBESON = preload("res://resources/items/knight_gambeson.tres")
const KNIGHT_CUIRASS = preload("res://resources/items/knight_cuirass.tres")
const KNIGHT_GAUNTLETS = preload("res://resources/items/knight_gauntlets.tres")
const KNIGHT_GREVES = preload("res://resources/items/knight_greaves.tres")
const KNIGHT_SABATONS = preload("res://resources/items/knight_sabatons.tres")
const KNIGHT_ARMET = preload("res://resources/items/knight_armet.tres")
const NOBLE_DOUBLET = preload("res://resources/items/noble_doublet.tres")
const NOBLE_SLEEVES = preload("res://resources/items/noble_sleeves.tres")
const NOBLE_TROUSERS = preload("res://resources/items/noble_trousers.tres")
const NOBLE_SHOES = preload("res://resources/items/noble_shoes.tres")
const WIZARD_ROBES = preload("res://resources/items/wizard_robes.tres")
const WIZARD_SLEEVES = preload("res://resources/items/wizard_sleeves.tres")
const WIZARD_TROUSERS = preload("res://resources/items/wizard_trousers.tres")
const WIZARD_SHOES = preload("res://resources/items/wizard_shoes.tres")
const BANDAGE = preload("res://resources/items/bandage.tres")
const CINDER_FLASK = preload("res://resources/items/cinder_flask.tres")

const PARTY_SKILL_LEVEL := 40
const RUSTDEAD_RANDOM_SEED := 770031
const PARTY_SQUAD_NAME := "RustdeadDemoParty"
const RUSTDEAD_SQUAD_NAME := "RustdeadDemoHorde"

const VISUAL_BODY_TYPE_MALE := 2
const VISUAL_BODY_TYPE_FEMALE := 3

const PARTY_CONFIGS := [
	{"name": "Mira", "body_type": VISUAL_BODY_TYPE_FEMALE, "skin": Color(0.88, 0.68, 0.54, 1.0), "color": Color(0.72, 0.48, 0.78, 1.0), "equipment": [STEEL_SWORD, ROUND_SHIELD, RANGER_JERKIN, RANGER_LEGGINGS, RANGER_BOOTS, RANGER_HOOD]},
	{"name": "Tomas", "body_type": VISUAL_BODY_TYPE_MALE, "skin": Color(0.66, 0.43, 0.30, 1.0), "color": Color(0.35, 0.56, 0.42, 1.0), "equipment": [IRON_AXE, PEASANT_TUNIC, PEASANT_TROUSERS, PEASANT_SHOES]},
	{"name": "Sable", "body_type": VISUAL_BODY_TYPE_FEMALE, "skin": Color(0.80, 0.58, 0.43, 1.0), "color": Color(0.58, 0.72, 0.38, 1.0), "equipment": [IRON_DAGGER, HEATER_SHIELD, KNIGHT_GAMBESON, KNIGHT_CUIRASS, KNIGHT_GAUNTLETS, KNIGHT_GREVES, KNIGHT_SABATONS, KNIGHT_ARMET]},
	{"name": "Bram", "body_type": VISUAL_BODY_TYPE_MALE, "skin": Color(0.49, 0.31, 0.22, 1.0), "color": Color(0.33, 0.55, 0.78, 1.0), "equipment": [HATCHET, NOBLE_DOUBLET, NOBLE_SLEEVES, NOBLE_TROUSERS, NOBLE_SHOES]},
	{"name": "Nika", "body_type": VISUAL_BODY_TYPE_FEMALE, "skin": Color(0.74, 0.45, 0.31, 1.0), "color": Color(0.67, 0.45, 0.75, 1.0), "equipment": [IRON_SWORD, ROUND_SHIELD, WIZARD_ROBES, WIZARD_SLEEVES, WIZARD_TROUSERS, WIZARD_SHOES]},
]

const RUSTDEAD_CHEST_ITEMS := [PEASANT_TUNIC, RANGER_JERKIN, NOBLE_DOUBLET, WIZARD_ROBES]
const RUSTDEAD_HAND_ITEMS := [NOBLE_SLEEVES, WIZARD_SLEEVES]
const RUSTDEAD_LEG_ITEMS := [PEASANT_TROUSERS, RANGER_LEGGINGS, NOBLE_TROUSERS, WIZARD_TROUSERS, KNIGHT_GREVES]
const RUSTDEAD_FEET_ITEMS := [PEASANT_SHOES, RANGER_BOOTS, NOBLE_SHOES, WIZARD_SHOES, KNIGHT_SABATONS]
const RUSTDEAD_HEAD_ITEMS := [RANGER_HOOD]

var _spawned := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if _spawned:
		return
	_spawned = true
	_rng.seed = RUSTDEAD_RANDOM_SEED
	_spawn_party_members()
	_spawn_rustdead_humanoids()


func _spawn_party_members() -> void:
	var party_root := get_node_or_null("PartyMembers") as Node3D
	if party_root == null:
		return
	for index in range(PARTY_CONFIGS.size()):
		var config: Dictionary = PARTY_CONFIGS[index]
		var actor := PARTY_MEMBER_SCRIPT.new() as PartyMember
		actor.name = str(config["name"])
		actor.member_name = str(config["name"])
		actor.faction_name = "Player"
		actor.squad_name = PARTY_SQUAD_NAME
		actor.hostile_factions = PackedStringArray(["Rustdead"])
		actor.combat_stance = NpcRules.CombatStance.DEFENSIVE
		actor.base_color = config["color"]
		actor.position = _party_position(index)
		actor.starting_items = [_make_stock(BANDAGE, 1), _make_stock(CINDER_FLASK, 1)]
		actor.starting_equipment = _equipment_array(config["equipment"])
		actor.starting_skill_levels = _skill_levels(PARTY_SKILL_LEVEL)
		actor.appearance_data = _make_appearance(HUMAN_RACE, int(config["body_type"]), config["skin"])
		actor.max_hp = 132.0
		actor.hp = actor.max_hp
		actor.base_attack_damage = 20.0
		actor.base_dodge_chance = 0.10
		actor.base_block_chance = 0.10
		actor.aggressive_scan_radius = 18.0
		actor.assist_scan_radius = 18.0
		_add_basic_actor_children(actor, actor.base_color, true)
		party_root.add_child(actor)


func _spawn_rustdead_humanoids() -> void:
	for index in range(10):
		var actor := RUSTDEAD_HUMANOID_SCRIPT.new() as HumanoidCharacter
		var tier := RUSTDEAD_TIER_LIBRARY.get_tier_for_demo_index(index)
		actor.name = "%sRustdead%02d" % [str(tier.call("get_id")).capitalize().replace(" ", ""), index + 1]
		actor.member_name = str(tier.get("display_name"))
		actor.faction_name = "Rustdead"
		actor.squad_name = RUSTDEAD_SQUAD_NAME
		actor.hostile_factions = PackedStringArray(["Player"])
		actor.combat_stance = NpcRules.CombatStance.AGGRESSIVE
		actor.position = _rustdead_position(index)
		actor.rotation.y = PI
		actor.starting_equipment = _equipment_array(_rustdead_clothes(index))
		actor.starting_skill_levels = RUSTDEAD_TIER_LIBRARY.roll_skill_levels(tier, _rng)
		var body_type := VISUAL_BODY_TYPE_FEMALE if index % 3 == 1 else VISUAL_BODY_TYPE_MALE
		actor.visual_body_type = body_type
		if actor.has_method("set_rustdead_tier_definition"):
			actor.call("set_rustdead_tier_definition", tier)
		actor.appearance_data = _make_appearance(RUSTDEAD_RACE, body_type, RUSTDEAD_TIER_LIBRARY.pick_skin_color(tier, _rng))
		RUSTDEAD_TIER_LIBRARY.apply_hair_for_tier(actor.appearance_data, tier, _rng, body_type)
		actor.max_hp = RUSTDEAD_TIER_LIBRARY.roll_max_hp(tier, _rng)
		actor.hp = actor.max_hp
		actor.base_attack_damage = 12.0 + float(index % 3) * 0.5
		actor.attack_cut_ratio = 0.05
		actor.base_dodge_chance = 0.025
		actor.base_block_chance = 0.0
		actor.attack_cooldown_seconds = 1.45
		actor.move_speed = 2.55
		actor.aggressive_scan_radius = 18.0
		actor.assist_scan_radius = 18.0
		actor.combat_squad_assist_radius = 80.0
		_add_basic_actor_children(actor, Color(0.42, 0.08, 0.07, 1.0), false)
		add_child(actor)


func _party_position(index: int) -> Vector3:
	return Vector3(-4.0, 0.6, -6.0 + float(index) * 3.0)


func _rustdead_position(index: int) -> Vector3:
	var column := int(float(index) / 5.0)
	var row := index % 5
	return Vector3(4.0 + float(column) * 1.8, 0.6, -6.0 + float(row) * 3.0)


func _rustdead_clothes(index: int) -> Array:
	match index:
		0:
			return []
		1:
			return [_pick_item(RUSTDEAD_LEG_ITEMS)]
		2:
			return [_pick_item(RUSTDEAD_LEG_ITEMS), _pick_item(RUSTDEAD_FEET_ITEMS)]
	var clothes: Array = []
	if _rng.randf() < 0.32:
		clothes.append(_pick_item(RUSTDEAD_CHEST_ITEMS))
	if _rng.randf() < 0.24:
		clothes.append(_pick_item(RUSTDEAD_HAND_ITEMS))
	if _rng.randf() < 0.68:
		clothes.append(_pick_item(RUSTDEAD_LEG_ITEMS))
	if _rng.randf() < 0.42:
		clothes.append(_pick_item(RUSTDEAD_FEET_ITEMS))
	if _rng.randf() < 0.12:
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


func _make_stock(item_definition: ItemDefinition, quantity: int) -> Resource:
	var stock := INVENTORY_STOCK_SCRIPT.new()
	stock.item_definition = item_definition
	stock.quantity = quantity
	return stock


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
	material.roughness = 0.9
	body.material_override = material
	actor.add_child(body)

	if include_selection_ring:
		var ring := MeshInstance3D.new()
		ring.name = "SelectionRing"
		ring.transform = Transform3D(Basis(), Vector3(0.0, 0.03, 0.0))
		var ring_mesh := CylinderMesh.new()
		ring_mesh.top_radius = 0.72
		ring_mesh.bottom_radius = 0.72
		ring_mesh.height = 0.05
		ring_mesh.radial_segments = 24
		ring_mesh.rings = 2
		ring.mesh = ring_mesh
		actor.add_child(ring)
