extends SceneTree

const HUMAN_MALE_BODY := "res://resources/character_body_archetypes/human_male.tres"
const HUMAN_FEMALE_BODY := "res://resources/character_body_archetypes/human_female.tres"
const HUMAN_MALE_GRIP_PROFILE := "res://resources/humanoid_grip_socket_profiles/human_male.tres"
const HUMAN_FEMALE_GRIP_PROFILE := "res://resources/humanoid_grip_socket_profiles/human_female.tres"
const DEFAULT_GRIP_PROFILE := "res://resources/humanoid_grip_socket_profiles/default.tres"

const T_IDENTITY := [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0]
const T_WEAPON := [0.189, 0.0, 0.0, 0.0, 0.189, 0.0, 0.0, 0.0, 0.189, 0.0, 0.0, 0.0]
const T_DAGGER := [0.189, 0.0, 0.0, 0.0, 0.189, 0.0, 0.0, 0.0, 0.189, -0.012, 0.0, -0.01]
const T_TABLEWARE := [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, -0.012, 0.0, -0.01]
const T_SHIELD := [0.225, 0.0, 0.0, 0.0, 0.225, 0.0, 0.0, 0.0, 0.225, 0.0, 0.0, 0.0]
const T_PICKAXE := [0.5, 0.0, 0.0, 0.0, 0.5, 0.0, 0.0, 0.0, 0.5, 0.0, 0.0, 0.0]
const T_FANTASY_SWORD := [0.6666667, 0.0, 0.0, 0.0, 0.6666667, 0.0, 0.0, 0.0, 0.6666667, 0.0, 0.0, 0.0]
const T_NOBLE_DOUBLET_MALE := [1.045, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.065, 0.0, 0.0, 0.0]
const T_HUMAN_MALE_RIGHT_HAND_ONE_HAND := [0.9999674, -0.008080745, 3.0307135e-10, 0.008080778, 0.99996775, -5.031495e-10, -2.9899638e-10, 5.0519944e-10, 1.0, -0.03097117, 0.08993864, 3.7252903e-08]
const T_HUMAN_FEMALE_RIGHT_HAND_ONE_HAND := [0.9999674, -0.008080745, 3.0274805e-10, 0.0080807805, 0.99996793, 0.0, -3.0559022e-10, 0.0, 1.0, -0.03097117, 0.052304804, -0.0005973056]

const EXPECTED_EQUIPPED_ITEMS := {
	"res://resources/items/bronze_axe.tres": ["res://scenes/world/equipment/axe_bronze_model.tscn", "res://resources/equipment_grip_profiles/one_hand_melee.tres", T_WEAPON],
	"res://resources/items/bronze_sword.tres": ["res://scenes/world/equipment/sword_bronze_model.tscn", "res://resources/equipment_grip_profiles/one_hand_melee.tres", T_FANTASY_SWORD],
	"res://resources/items/claymore.tres": ["res://scenes/world/equipment/claymore_model.tscn", "res://resources/equipment_grip_profiles/two_hand_weapon.tres", T_WEAPON],
	"res://resources/items/evil_bow.tres": ["res://scenes/world/equipment/bow_evil_model.tscn", "res://resources/equipment_grip_profiles/bow.tres", T_WEAPON],
	"res://resources/items/fantasy_steel_axe.tres": ["res://scenes/world/equipment/axe_steel_fantasy_model.tscn", "res://resources/equipment_grip_profiles/one_hand_melee.tres", T_WEAPON],
	"res://resources/items/fantasy_steel_sword.tres": ["res://scenes/world/equipment/sword_steel_fantasy_model.tscn", "res://resources/equipment_grip_profiles/one_hand_melee.tres", T_FANTASY_SWORD],
	"res://resources/items/golden_bow.tres": ["res://scenes/world/equipment/bow_golden_model.tscn", "res://resources/equipment_grip_profiles/bow.tres", T_WEAPON],
	"res://resources/items/golden_celtic_shield.tres": ["res://scenes/world/equipment/shield_celtic_golden_model.tscn", "res://resources/equipment_grip_profiles/offhand_shield.tres", T_SHIELD],
	"res://resources/items/golden_sword.tres": ["res://scenes/world/equipment/sword_golden_model.tscn", "res://resources/equipment_grip_profiles/one_hand_melee.tres", T_WEAPON],
	"res://resources/items/greatsword.tres": ["res://scenes/world/equipment/sword_big_model.tscn", "res://resources/equipment_grip_profiles/two_hand_weapon.tres", T_WEAPON],
	"res://resources/items/hatchet.tres": ["res://scenes/world/equipment/axe_small_model.tscn", "res://resources/equipment_grip_profiles/one_hand_melee.tres", T_WEAPON],
	"res://resources/items/heater_shield.tres": ["res://scenes/world/equipment/shield_heater_model.tscn", "res://resources/equipment_grip_profiles/offhand_shield.tres", T_SHIELD],
	"res://resources/items/heater_shield_2.tres": ["res://scenes/world/equipment/shield_heater_2_model.tscn", "res://resources/equipment_grip_profiles/offhand_shield.tres", T_SHIELD],
	"res://resources/items/iron_axe.tres": ["res://scenes/world/equipment/axe_model.tscn", "res://resources/equipment_grip_profiles/one_hand_melee.tres", T_WEAPON],
	"res://resources/items/iron_axe_double.tres": ["res://scenes/world/equipment/axe_double_model.tscn", "res://resources/equipment_grip_profiles/one_hand_melee.tres", T_WEAPON],
	"res://resources/items/iron_dagger.tres": ["res://scenes/world/equipment/dagger_model.tscn", "res://resources/equipment_grip_profiles/one_hand_melee.tres", T_DAGGER],
	"res://resources/items/iron_sword.tres": ["res://scenes/world/equipment/sword_model.tscn", "res://resources/equipment_grip_profiles/one_hand_melee.tres", T_WEAPON],
	"res://resources/items/maul.tres": ["res://scenes/world/equipment/hammer_double_model.tscn", "res://resources/equipment_grip_profiles/two_hand_weapon.tres", T_WEAPON],
	"res://resources/items/recurve_bow.tres": ["res://scenes/world/equipment/bow_wooden2_model.tscn", "res://resources/equipment_grip_profiles/bow.tres", T_WEAPON],
	"res://resources/items/round_shield.tres": ["res://scenes/world/equipment/round_shield_model.tscn", "res://resources/equipment_grip_profiles/offhand_shield.tres", T_SHIELD],
	"res://resources/items/round_shield_2.tres": ["res://scenes/world/equipment/shield_round_2_model.tscn", "res://resources/equipment_grip_profiles/offhand_shield.tres", T_SHIELD],
	"res://resources/items/rusted_pickaxe.tres": ["res://scenes/world/equipment/rusted_pickaxe_model.tscn", "res://resources/equipment_grip_profiles/one_hand_melee.tres", T_PICKAXE],
	"res://resources/items/scythe.tres": ["res://scenes/world/equipment/scythe_model.tscn", "res://resources/equipment_grip_profiles/polearm.tres", T_WEAPON],
	"res://resources/items/spear.tres": ["res://scenes/world/equipment/spear_model.tscn", "res://resources/equipment_grip_profiles/polearm.tres", T_WEAPON],
	"res://resources/items/steel_dagger.tres": ["res://scenes/world/equipment/dagger_2_model.tscn", "res://resources/equipment_grip_profiles/one_hand_melee.tres", T_DAGGER],
	"res://resources/items/steel_sword.tres": ["res://scenes/world/equipment/sword_2_model.tscn", "res://resources/equipment_grip_profiles/one_hand_melee.tres", T_WEAPON],
	"res://resources/items/table_fork.tres": ["res://scenes/world/equipment/table_fork_model.tscn", "res://resources/equipment_grip_profiles/one_hand_melee.tres", T_TABLEWARE],
	"res://resources/items/table_knife.tres": ["res://scenes/world/equipment/table_knife_model.tscn", "res://resources/equipment_grip_profiles/one_hand_melee.tres", T_TABLEWARE],
	"res://resources/items/table_spoon.tres": ["res://scenes/world/equipment/table_spoon_model.tscn", "res://resources/equipment_grip_profiles/one_hand_melee.tres", T_TABLEWARE],
	"res://resources/items/war_hammer.tres": ["res://scenes/world/equipment/hammer_small_model.tscn", "res://resources/equipment_grip_profiles/one_hand_melee.tres", T_WEAPON],
	"res://resources/items/wooden_bow.tres": ["res://scenes/world/equipment/bow_wooden_model.tscn", "res://resources/equipment_grip_profiles/bow.tres", T_WEAPON],
}

const EXPECTED_WEARABLE_VISUALS := {
	"res://resources/items/knight_armet.tres": {"human_male": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Male_Knight_Head_Armet.gltf", 0.004, "armor", "head", T_IDENTITY], "human_female": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Female_Knight_Head_Armet.gltf", 0.004, "armor", "head", T_IDENTITY]},
	"res://resources/items/knight_cuirass.tres": {"human_male": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Male_Knight_Body_Armor.gltf", 0.018, "armor", "torso", T_IDENTITY], "human_female": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Female_Knight_Body_Armor.gltf", 0.018, "armor", "torso", T_IDENTITY]},
	"res://resources/items/knight_gambeson.tres": {"human_male": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Male_Knight_Body_Cloth.gltf", 0.018, "underlayer", "torso", T_IDENTITY], "human_female": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Female_Knight_Body_Cloth.gltf", 0.018, "underlayer", "torso", T_IDENTITY]},
	"res://resources/items/knight_gauntlets.tres": {"human_male": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Male_Knight_Arms.gltf", 0.014, "armor", "arms,hands", T_IDENTITY], "human_female": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Female_Knight_Arms.gltf", 0.014, "armor", "arms,hands", T_IDENTITY]},
	"res://resources/items/knight_greaves.tres": {"human_male": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Male_Knight_Legs_Armor.gltf", 0.016, "armor", "legs", T_IDENTITY], "human_female": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Female_Knight_Legs.gltf", 0.016, "armor", "legs", T_IDENTITY]},
	"res://resources/items/knight_horned_helm.tres": {"human_male": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Male_Knight_Head_Horns.gltf", 0.004, "armor", "head", T_IDENTITY], "human_female": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Female_Knight_Head_Horns.gltf", 0.004, "armor", "head", T_IDENTITY]},
	"res://resources/items/knight_sabatons.tres": {"human_male": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Male_Knight_Feet_Armor.gltf", 0.012, "armor", "feet", T_IDENTITY], "human_female": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Female_Knight_Feet.gltf", 0.012, "armor", "feet", T_IDENTITY]},
	"res://resources/items/noble_crown.tres": {"human_male": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Male_Noble_Head_Crown.gltf", 0.004, "accessory", "head", T_IDENTITY], "human_female": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Female_Noble_Head_Crown.gltf", 0.004, "accessory", "head", T_IDENTITY]},
	"res://resources/items/noble_doublet.tres": {"human_male": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Male_Noble_Body.gltf", 0.04, "underlayer", "torso", T_NOBLE_DOUBLET_MALE], "human_female": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Female_Noble_Body.gltf", 0.018, "underlayer", "torso", T_IDENTITY]},
	"res://resources/items/noble_shoes.tres": {"human_male": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Male_Noble_Feet.gltf", 0.012, "underlayer", "feet", T_IDENTITY], "human_female": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Female_Noble_Feet.gltf", 0.012, "underlayer", "feet", T_IDENTITY]},
	"res://resources/items/noble_sleeves.tres": {"human_male": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Male_Noble_Arms.gltf", 0.014, "underlayer", "arms,hands", T_IDENTITY], "human_female": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Female_Noble_Arms.gltf", 0.014, "underlayer", "arms,hands", T_IDENTITY]},
	"res://resources/items/noble_trousers.tres": {"human_male": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Male_Noble_Legs.gltf", 0.016, "underlayer", "legs", T_IDENTITY], "human_female": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Female_Noble_Legs.gltf", 0.016, "underlayer", "legs", T_IDENTITY]},
	"res://resources/items/peasant_shoes.tres": {"human_male": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Male_Peasant_Feet.gltf", 0.018, "underlayer", "feet", T_IDENTITY], "human_female": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Female_Peasant_Feet.gltf", 0.012, "underlayer", "feet", T_IDENTITY]},
	"res://resources/items/peasant_trousers.tres": {"human_male": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Male_Peasant_Legs.gltf", 0.016, "underlayer", "legs", T_IDENTITY], "human_female": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Female_Peasant_Legs.gltf", 0.016, "underlayer", "legs", T_IDENTITY]},
	"res://resources/items/peasant_tunic.tres": {"human_male": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Male_Peasant_Body.gltf", 0.018, "underlayer", "torso", T_IDENTITY], "human_female": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Female_Peasant_Body.gltf", 0.018, "underlayer", "torso", T_IDENTITY]},
	"res://resources/items/ranger_boots.tres": {"human_male": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Male_Ranger_Feet_Boots.gltf", 0.012, "armor", "feet", T_IDENTITY], "human_female": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Female_Ranger_Feet.gltf", 0.012, "armor", "feet", T_IDENTITY]},
	"res://resources/items/ranger_hood.tres": {"human_male": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Male_Ranger_Head_Hood.gltf", 0.004, "armor", "head", T_IDENTITY], "human_female": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Female_Ranger_Head_Hood.gltf", 0.004, "armor", "head", T_IDENTITY]},
	"res://resources/items/ranger_jerkin.tres": {"human_male": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Male_Ranger_Body.gltf", 0.018, "armor", "torso", T_IDENTITY], "human_female": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Female_Ranger_Body.gltf", 0.018, "armor", "torso", T_IDENTITY]},
	"res://resources/items/ranger_leggings.tres": {"human_male": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Male_Ranger_Legs.gltf", 0.016, "armor", "legs", T_IDENTITY], "human_female": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Female_Ranger_Legs.gltf", 0.016, "armor", "legs", T_IDENTITY]},
	"res://resources/items/wizard_robes.tres": {"human_male": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Male_Wizard_Body.gltf", 0.018, "outerwear", "torso", T_IDENTITY], "human_female": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Female_Wizard_Body.gltf", 0.018, "outerwear", "torso", T_IDENTITY]},
	"res://resources/items/wizard_shoes.tres": {"human_male": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Male_Wizard_Feet.gltf", 0.012, "underlayer", "feet", T_IDENTITY], "human_female": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Female_Wizard_Feet.gltf", 0.012, "underlayer", "feet", T_IDENTITY]},
	"res://resources/items/wizard_sleeves.tres": {"human_male": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Male_Wizard_Arms.gltf", 0.014, "underlayer", "arms,hands", T_IDENTITY], "human_female": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Female_Wizard_Arms.gltf", 0.014, "underlayer", "arms,hands", T_IDENTITY]},
	"res://resources/items/wizard_trousers.tres": {"human_male": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Male_Wizard_Legs.gltf", 0.016, "underlayer", "legs", T_IDENTITY], "human_female": ["res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts/Female_Wizard_Legs.gltf", 0.016, "underlayer", "legs", T_IDENTITY]},
}

const EXPECTED_GRIP_PROFILES := {
	"res://resources/equipment_grip_profiles/bow.tres": ["bow", "Bow", "bow", "hand_l", "hand_r", "left_hand_bow_grip", "right_hand_bow_draw", true, "bow"],
	"res://resources/equipment_grip_profiles/crossbow.tres": ["crossbow", "Crossbow", "crossbow", "hand_r", "hand_l", "right_hand_crossbow_grip", "left_hand_crossbow_support", true, "crossbow"],
	"res://resources/equipment_grip_profiles/offhand_shield.tres": ["offhand_shield", "Offhand Shield", "offhand_shield", "hand_l", "", "left_hand_shield", "", false, "shield"],
	"res://resources/equipment_grip_profiles/one_hand_melee.tres": ["one_hand_melee", "One-Hand Melee", "one_hand_melee", "hand_r", "", "right_hand_one_hand", "", false, "one_hand_melee"],
	"res://resources/equipment_grip_profiles/polearm.tres": ["polearm", "Polearm", "polearm", "hand_r", "hand_l", "right_hand_polearm_primary", "left_hand_polearm_secondary", true, "polearm"],
	"res://resources/equipment_grip_profiles/thrown.tres": ["thrown", "Thrown Weapon", "thrown", "hand_r", "", "right_hand_thrown", "", false, "thrown"],
	"res://resources/equipment_grip_profiles/two_hand_weapon.tres": ["two_hand_weapon", "Two-Hand Weapon", "two_hand_weapon", "hand_r", "hand_l", "right_hand_two_hand_primary", "left_hand_two_hand_secondary", true, "two_hand_weapon"],
}

const SOCKET_IDS := [
	"right_hand_one_hand",
	"left_hand_shield",
	"right_hand_two_hand_primary",
	"left_hand_two_hand_secondary",
	"right_hand_polearm_primary",
	"left_hand_polearm_secondary",
	"left_hand_bow_grip",
	"right_hand_bow_draw",
	"right_hand_crossbow_grip",
	"left_hand_crossbow_support",
	"right_hand_thrown",
]

var _failures: Array[String] = []


func _initialize() -> void:
	_validate_grip_profiles()
	_validate_human_grip_socket_profiles()
	_validate_equipped_items()
	_validate_wearable_visuals()
	if _failures.is_empty():
		print("EQUIPMENT_GRIP_DATA_VALIDATION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _validate_grip_profiles() -> void:
	for path in EXPECTED_GRIP_PROFILES.keys():
		var profile := load(path)
		_expect(profile != null, "Grip profile loads: %s" % path)
		if profile == null:
			continue
		var expected: Array = EXPECTED_GRIP_PROFILES[path]
		_expect(str(profile.get("profile_id")) == str(expected[0]), "Grip profile id preserved: %s" % path)
		_expect(str(profile.get("display_name")) == str(expected[1]), "Grip profile display name preserved: %s" % path)
		_expect(str(profile.get("grip_class_id")) == str(expected[2]), "Grip profile class preserved: %s" % path)
		_expect(str(profile.get("primary_bone")) == str(expected[3]), "Grip profile primary bone preserved: %s" % path)
		_expect(str(profile.get("secondary_bone")) == str(expected[4]), "Grip profile secondary bone preserved: %s" % path)
		_expect(str(profile.get("primary_socket_id")) == str(expected[5]), "Grip profile primary socket preserved: %s" % path)
		_expect(str(profile.get("secondary_socket_id")) == str(expected[6]), "Grip profile secondary socket preserved: %s" % path)
		_expect(bool(profile.get("requires_two_hands")) == bool(expected[7]), "Grip profile hand requirement preserved: %s" % path)
		_expect(str(profile.get("animation_stance_id")) == str(expected[8]), "Grip profile stance preserved: %s" % path)
		_expect(str(profile.get("primary_grip_marker")) == "GripPoint_Primary", "Grip profile primary marker preserved: %s" % path)


func _validate_human_grip_socket_profiles() -> void:
	_validate_body_grip_profile(HUMAN_MALE_BODY, HUMAN_MALE_GRIP_PROFILE)
	_validate_body_grip_profile(HUMAN_FEMALE_BODY, HUMAN_FEMALE_GRIP_PROFILE)
	_validate_socket_profile(DEFAULT_GRIP_PROFILE, T_HUMAN_MALE_RIGHT_HAND_ONE_HAND)
	_validate_socket_profile(HUMAN_MALE_GRIP_PROFILE, T_HUMAN_MALE_RIGHT_HAND_ONE_HAND)
	_validate_socket_profile(HUMAN_FEMALE_GRIP_PROFILE, T_HUMAN_FEMALE_RIGHT_HAND_ONE_HAND)


func _validate_body_grip_profile(body_path: String, grip_profile_path: String) -> void:
	var body := load(body_path)
	_expect(body != null, "Human body archetype loads: %s" % body_path)
	if body == null:
		return
	_expect(_resource_path(body.get("grip_socket_profile")) == grip_profile_path, "Human body grip socket profile preserved: %s" % body_path)


func _validate_socket_profile(profile_path: String, right_hand_transform_values: Array) -> void:
	var profile := load(profile_path)
	_expect(profile != null, "Humanoid grip socket profile loads: %s" % profile_path)
	if profile == null:
		return
	for socket_id in SOCKET_IDS:
		var actual_transform = profile.call("get_socket_transform", socket_id) if profile.has_method("get_socket_transform") else profile.get(socket_id)
		if typeof(actual_transform) != TYPE_TRANSFORM3D:
			_failures.append("Socket transform missing: %s %s" % [profile_path, socket_id])
			continue
		var expected_values := right_hand_transform_values if socket_id == "right_hand_one_hand" else T_IDENTITY
		_expect_transform(actual_transform, _transform_from_values(expected_values), "Humanoid socket transform preserved: %s %s" % [profile_path, socket_id])


func _validate_equipped_items() -> void:
	for item_path in EXPECTED_EQUIPPED_ITEMS.keys():
		var item := load(item_path)
		_expect(item != null, "Equippable item resource loads: %s" % item_path)
		if item == null:
			continue
		var expected: Array = EXPECTED_EQUIPPED_ITEMS[item_path]
		var equipped_scene_path := str(expected[0])
		var grip_profile_path := str(expected[1])
		var expected_transform := _transform_from_values(expected[2])
		var equipped_scene := item.get("equipped_scene") as PackedScene
		var grip_profile := item.get("grip_profile") as Resource
		_expect(_resource_path(equipped_scene) == equipped_scene_path, "Equipped scene preserved from main: %s" % item_path)
		_expect(_resource_path(grip_profile) == grip_profile_path, "Grip profile preserved from main: %s" % item_path)
		var actual_transform = item.get("equipped_transform")
		if typeof(actual_transform) != TYPE_TRANSFORM3D:
			_failures.append("Equipped transform missing: %s" % item_path)
		else:
			_expect_transform(actual_transform, expected_transform, "Equipped transform preserved from main: %s" % item_path)
		_validate_equipped_scene_marker(item_path, equipped_scene, grip_profile)


func _validate_equipped_scene_marker(item_path: String, equipped_scene: PackedScene, grip_profile: Resource) -> void:
	_expect(equipped_scene != null, "Equipped scene exists: %s" % item_path)
	if equipped_scene == null:
		return
	var instance := equipped_scene.instantiate()
	_expect(instance != null, "Equipped scene instantiates: %s" % item_path)
	if instance == null:
		return
	var marker_name := "GripPoint_Primary"
	if grip_profile != null:
		marker_name = str(grip_profile.get("primary_grip_marker"))
	_expect(instance.find_child(marker_name, true, false) != null, "Equipped scene exposes %s: %s" % [marker_name, item_path])
	instance.free()


func _validate_wearable_visuals() -> void:
	for item_path in EXPECTED_WEARABLE_VISUALS.keys():
		var item := load(item_path)
		_expect(item != null, "Wearable item resource loads: %s" % item_path)
		if item == null:
			continue
		var expected_by_body: Dictionary = EXPECTED_WEARABLE_VISUALS[item_path]
		for body_id in ["human_male", "human_female"]:
			var body_path := HUMAN_MALE_BODY if body_id == "human_male" else HUMAN_FEMALE_BODY
			var body := load(body_path)
			var visual = item.call("get_equipment_visual_for_body_archetype", body) if item.has_method("get_equipment_visual_for_body_archetype") else null
			_expect(visual != null, "Wearable has %s visual mapping: %s" % [body_id, item_path])
			if visual == null:
				continue
			var expected: Array = expected_by_body[body_id]
			_expect(_resource_path(visual.get("body_archetype")) == body_path, "Wearable %s body archetype preserved: %s" % [body_id, item_path])
			_expect(_resource_path(visual.get("visual_scene")) == str(expected[0]), "Wearable %s visual scene preserved: %s" % [body_id, item_path])
			_expect(absf(float(visual.get("surface_offset_ratio")) - float(expected[1])) < 0.0001, "Wearable %s surface offset preserved: %s" % [body_id, item_path])
			_expect(str(visual.get("visual_layer")) == str(expected[2]), "Wearable %s visual layer preserved: %s" % [body_id, item_path])
			_expect(str(visual.get("visual_coverage")) == str(expected[3]), "Wearable %s visual coverage preserved: %s" % [body_id, item_path])
			var actual_transform = visual.get("equipped_transform")
			if typeof(actual_transform) != TYPE_TRANSFORM3D:
				_failures.append("Wearable equipped transform missing: %s %s" % [item_path, body_id])
			else:
				var expected_transform := _transform_from_values(expected[4])
				_expect_transform(actual_transform, expected_transform, "Wearable %s equipped transform preserved: %s" % [body_id, item_path])


func _transform_from_values(values: Array) -> Transform3D:
	return Transform3D(
		Basis(
			Vector3(float(values[0]), float(values[3]), float(values[6])),
			Vector3(float(values[1]), float(values[4]), float(values[7])),
			Vector3(float(values[2]), float(values[5]), float(values[8]))
		),
		Vector3(float(values[9]), float(values[10]), float(values[11]))
	)


func _expect_transform(actual: Transform3D, expected: Transform3D, message: String) -> void:
	_expect(actual.is_equal_approx(expected), "%s expected %s got %s" % [message, str(expected), str(actual)])


func _resource_path(value) -> String:
	if value is Resource:
		return (value as Resource).resource_path
	return ""


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
