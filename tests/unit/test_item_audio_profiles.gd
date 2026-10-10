extends GutTest

const PROFILE_SCRIPT_PATH := "res://features/combat/resources/combat_item_audio_profile.gd"
const PROFILE = preload(PROFILE_SCRIPT_PATH)
const ITEM_DIRECTORY := "res://features/inventory/resources/items"


func test_saved_spear_separates_metal_tip_from_wooden_guard() -> void:
	var item := ResourceLoader.load(ITEM_DIRECTORY.path_join("spear.tres"), "", ResourceLoader.CACHE_MODE_IGNORE) as ItemDefinition
	assert_not_null(item)
	if item == null:
		return
	var profile: Resource = item.get("combat_audio")
	assert_not_null(profile, "Saved spear must reference an authored audio profile")
	if profile == null:
		return
	assert_eq(profile.get_script(), PROFILE)
	assert_eq(profile.weapon_kind, PROFILE.WeaponKind.POLEARM)
	assert_eq(profile.strike_surface, PROFILE.Surface.METAL)
	assert_eq(profile.guard_surface, PROFILE.Surface.WOOD)
	assert_eq(profile.worn_surface, PROFILE.Surface.NONE)
	assert_eq(profile.resource_path, "res://features/combat/resources/item_audio_profiles/polearm_metal_head_wood_shaft.tres")


func test_new_profile_has_no_implicit_contact_materials() -> void:
	assert_true(ResourceLoader.exists(PROFILE_SCRIPT_PATH), "The authored contact-profile resource must exist")
	if not ResourceLoader.exists(PROFILE_SCRIPT_PATH):
		return
	var profile_script := load(PROFILE_SCRIPT_PATH) as Script
	var profile: Resource = profile_script.new()
	for property in ["weapon_kind", "strike_surface", "guard_surface", "worn_surface"]:
		assert_eq(profile.get(property), 0, property + " must default to NONE")


func test_item_exposes_optional_typed_profile_in_inspector() -> void:
	var item := ItemDefinition.new()
	var matching_properties: Array[Dictionary] = []
	for property: Dictionary in item.get_property_list():
		if property.name == "combat_audio":
			matching_properties.append(property)
	assert_eq(matching_properties.size(), 1, "ItemDefinition must export one combat_audio property")
	if matching_properties.is_empty():
		return
	var property: Dictionary = matching_properties[0]
	assert_eq(property.type, TYPE_OBJECT)
	assert_eq(property.hint, PROPERTY_HINT_RESOURCE_TYPE)
	assert_eq(property.hint_string, "CombatItemAudioProfile")
	assert_ne(property.usage & PROPERTY_USAGE_EDITOR, 0)
	assert_ne(property.usage & PROPERTY_USAGE_STORAGE, 0)
	assert_null(item.get("combat_audio"), "Non-equipment is not assigned a guessed material")


func test_every_saved_equippable_has_explicit_shared_classification() -> void:
	var missing: Array[String] = []
	var invalid: Array[String] = []
	var equippable_count := 0
	for path in _resource_paths(ITEM_DIRECTORY):
		var item := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ItemDefinition
		assert_not_null(item, path)
		if item == null or not item.is_equippable():
			continue
		equippable_count += 1
		var profile: Resource = item.get("combat_audio")
		if profile == null:
			missing.append(path)
			continue
		if profile.get_script() != PROFILE or not profile.resource_path.begins_with("res://features/combat/resources/item_audio_profiles/") or profile.resource_local_to_scene:
			invalid.append(path)
		elif item.equip_slot == ItemDefinition.EQUIP_SLOT_WEAPON:
			if profile.weapon_kind == PROFILE.WeaponKind.NONE or profile.strike_surface == PROFILE.Surface.NONE or profile.guard_surface == PROFILE.Surface.NONE or profile.worn_surface != PROFILE.Surface.NONE:
				invalid.append(path)
		elif item.equip_slot == ItemDefinition.EQUIP_SLOT_OFFHAND:
			if profile.guard_surface == PROFILE.Surface.NONE or profile.worn_surface != PROFILE.Surface.NONE:
				invalid.append(path)
		elif profile.worn_surface == PROFILE.Surface.NONE or profile.weapon_kind != PROFILE.WeaponKind.NONE or profile.strike_surface != PROFILE.Surface.NONE or profile.guard_surface != PROFILE.Surface.NONE:
			invalid.append(path)
	assert_gt(equippable_count, 0, "Recursive catalog discovery must not silently skip equipment")
	assert_eq(missing, [], "Every equippable saved ItemDefinition needs an explicit profile")
	assert_eq(invalid, [], "Each saved shared profile must describe the item's relevant contact")


func test_representative_saved_assignments_follow_visible_construction() -> void:
	# Independent expected decisions, including misleading names and mixed materials.
	var expected := {
		"steel_sword": [PROFILE.WeaponKind.BLADE, PROFILE.Surface.METAL, PROFILE.Surface.METAL, PROFILE.Surface.NONE],
		"bronze_axe": [PROFILE.WeaponKind.AXE, PROFILE.Surface.METAL, PROFILE.Surface.WOOD, PROFILE.Surface.NONE],
		"war_hammer": [PROFILE.WeaponKind.BLUNT, PROFILE.Surface.METAL, PROFILE.Surface.WOOD, PROFILE.Surface.NONE],
		"bestiary_tidebreaker_anchor": [PROFILE.WeaponKind.BLUNT, PROFILE.Surface.METAL, PROFILE.Surface.METAL, PROFILE.Surface.NONE],
		"bestiary_puglin_stick": [PROFILE.WeaponKind.BLUNT, PROFILE.Surface.WOOD, PROFILE.Surface.WOOD, PROFILE.Surface.NONE],
		"wooden_bow": [PROFILE.WeaponKind.BOW, PROFILE.Surface.WOOD, PROFILE.Surface.WOOD, PROFILE.Surface.NONE],
		"golden_bow": [PROFILE.WeaponKind.BOW, PROFILE.Surface.METAL, PROFILE.Surface.METAL, PROFILE.Surface.NONE],
		"bucket": [PROFILE.WeaponKind.TOOL, PROFILE.Surface.WOOD, PROFILE.Surface.WOOD, PROFILE.Surface.NONE],
		"hoe": [PROFILE.WeaponKind.TOOL, PROFILE.Surface.METAL, PROFILE.Surface.WOOD, PROFILE.Surface.NONE],
		"rusted_pickaxe": [PROFILE.WeaponKind.TOOL, PROFILE.Surface.METAL, PROFILE.Surface.METAL, PROFILE.Surface.NONE],
		"table_fork": [PROFILE.WeaponKind.TOOL, PROFILE.Surface.METAL, PROFILE.Surface.METAL, PROFILE.Surface.NONE],
		"table_knife": [PROFILE.WeaponKind.BLADE, PROFILE.Surface.METAL, PROFILE.Surface.METAL, PROFILE.Surface.NONE],
		"watering_can": [PROFILE.WeaponKind.TOOL, PROFILE.Surface.METAL, PROFILE.Surface.METAL, PROFILE.Surface.NONE],
		"heater_shield": [PROFILE.WeaponKind.NONE, PROFILE.Surface.WOOD, PROFILE.Surface.WOOD, PROFILE.Surface.NONE],
		"round_shield_2": [PROFILE.WeaponKind.NONE, PROFILE.Surface.WOOD, PROFILE.Surface.WOOD, PROFILE.Surface.NONE],
		"golden_celtic_shield": [PROFILE.WeaponKind.NONE, PROFILE.Surface.METAL, PROFILE.Surface.METAL, PROFILE.Surface.NONE],
		"knight_gambeson": [PROFILE.WeaponKind.NONE, PROFILE.Surface.NONE, PROFILE.Surface.NONE, PROFILE.Surface.CLOTH],
		"knight_cuirass": [PROFILE.WeaponKind.NONE, PROFILE.Surface.NONE, PROFILE.Surface.NONE, PROFILE.Surface.PLATE],
		"bestiary_skeleton_horned_helm": [PROFILE.WeaponKind.NONE, PROFILE.Surface.NONE, PROFILE.Surface.NONE, PROFILE.Surface.PLATE],
		"traveler_leather_jacket": [PROFILE.WeaponKind.NONE, PROFILE.Surface.NONE, PROFILE.Surface.NONE, PROFILE.Surface.LEATHER],
		"ranger_jerkin": [PROFILE.WeaponKind.NONE, PROFILE.Surface.NONE, PROFILE.Surface.NONE, PROFILE.Surface.LEATHER],
		"wizard_shoes": [PROFILE.WeaponKind.NONE, PROFILE.Surface.NONE, PROFILE.Surface.NONE, PROFILE.Surface.CLOTH],
		"noble_crown": [PROFILE.WeaponKind.NONE, PROFILE.Surface.NONE, PROFILE.Surface.NONE, PROFILE.Surface.METAL],
	}
	for basename: String in expected:
		var item := ResourceLoader.load(ITEM_DIRECTORY.path_join(basename + ".tres"), "", ResourceLoader.CACHE_MODE_IGNORE) as ItemDefinition
		assert_not_null(item, basename)
		if item == null:
			continue
		var profile: Resource = item.get("combat_audio")
		assert_not_null(profile, basename)
		if profile != null:
			assert_eq([profile.weapon_kind, profile.strike_surface, profile.guard_surface, profile.worn_surface], expected[basename], basename)


func test_equivalent_items_reference_the_same_saved_profile() -> void:
	for family in [["iron_sword", "steel_sword", "bronze_sword"], ["heater_shield", "heater_shield_2", "round_shield", "round_shield_2"], ["knight_cuirass", "bestiary_skeleton_greaves"], ["peasant_tunic", "knight_gambeson"]]:
		var first: Resource = null
		for basename: String in family:
			var item := load(ITEM_DIRECTORY.path_join(basename + ".tres")) as ItemDefinition
			var profile: Resource = item.get("combat_audio")
			assert_not_null(profile, basename)
			if profile == null:
				continue
			if first == null:
				first = profile
			else:
				assert_same(profile, first, "Shared resource edits must reach every member of " + str(family))


func _resource_paths(directory: String) -> Array[String]:
	var result: Array[String] = []
	for file in DirAccess.get_files_at(directory):
		if file.ends_with(".tres"):
			result.append(directory.path_join(file))
	for child in DirAccess.get_directories_at(directory):
		result.append_array(_resource_paths(directory.path_join(child)))
	result.sort()
	return result
