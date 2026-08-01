extends SceneTree

const HUMAN_MALE := preload("res://features/actors/resources/character_body_archetypes/human_male.tres")
const HUMAN_FEMALE := preload("res://features/actors/resources/character_body_archetypes/human_female.tres")
const OUTFIT_DIRECTORY := "res://assets/vendor/quaternius/modular_character_outfits_fantasy/modular_parts"

var _failures: Array[String] = []


func _initialize() -> void:
	_validate_age_cohorts()
	_validate_catalog()
	_validate_body_variants(HUMAN_MALE, "Male")
	_validate_body_variants(HUMAN_FEMALE, "Female")
	_validate_equipment_skeleton_compatibility()
	if _failures.is_empty():
		print("CHARACTER_DEMOGRAPHICS_AND_ASSETS_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("CHARACTER_DEMOGRAPHICS_AND_ASSETS_FAILED count=%d" % _failures.size())
	quit(1)


func _validate_age_cohorts() -> void:
	for population_count in range(1, 201):
		var rng := RandomNumberGenerator.new()
		rng.seed = population_count * 7919
		var ages := CharacterAgeRules.generate_missing_ages(population_count, [], rng)
		var summary := CharacterAgeRules.summarize(ages)
		var teen_count := int(summary["teen_count"])
		var elderly_count := int(summary["elderly_count"])
		if teen_count * 5 >= population_count:
			_fail("Population %d generated too many teens: %d" % [population_count, teen_count])
		if elderly_count * 5 >= population_count:
			_fail("Population %d generated too many elderly residents: %d" % [population_count, elderly_count])
		if population_count >= 2 and absf(float(summary["standard_deviation"]) - CharacterAgeRules.TARGET_STANDARD_DEVIATION) > 1.0:
			_fail("Population %d standard deviation drifted to %.2f" % [population_count, float(summary["standard_deviation"])])
		for age in ages:
			if age < CharacterAgeRules.TEEN_MIN_AGE or age > CharacterAgeRules.ELDERLY_MAX_AGE:
				_fail("Population %d generated invalid age %d" % [population_count, age])
	var existing_ages: Array[int] = [14, 70, 23]
	var mixed_rng := RandomNumberGenerator.new()
	mixed_rng.seed = 918273
	var completed_ages := existing_ages.duplicate()
	completed_ages.append_array(CharacterAgeRules.generate_missing_ages(40, existing_ages, mixed_rng))
	var mixed_summary := CharacterAgeRules.summarize(completed_ages)
	if int(mixed_summary["teen_count"]) * 5 >= completed_ages.size() or int(mixed_summary["elderly_count"]) * 5 >= completed_ages.size():
		_fail("Known settlement ages were not included in strict demographic quotas")
	var birthday_rng := RandomNumberGenerator.new()
	birthday_rng.seed = 12345
	for age_years in [13, 16, 17, 64, 65, 95]:
		var birth_day := CharacterAgeRules.birth_day_for_age(age_years, 4000, birthday_rng)
		if CharacterAgeRules.age_years(birth_day, 4000) != age_years:
			_fail("Birth-day round trip changed age %d" % age_years)


func _validate_catalog() -> void:
	CharacterAppearanceCatalog.clear_cache()
	var expected_counts := {
		"hair": 13,
		"beard": 3,
		"eyebrows": 3,
	}
	var catalogs := {
		"hair": CharacterAppearanceCatalog.get_hair_styles(),
		"beard": CharacterAppearanceCatalog.get_beard_styles(),
		"eyebrows": CharacterAppearanceCatalog.get_eyebrow_styles(),
	}
	for slot_name in catalogs:
		var styles: Array = catalogs[slot_name]
		if styles.size() != int(expected_counts[slot_name]):
			_fail("Expected %d %s styles, found %d" % [int(expected_counts[slot_name]), slot_name, styles.size()])
		for style in styles:
			_validate_scene(CharacterVisualRules.get_head_attachment_scene(style, 23), "%s adult" % str(style.get("style_id")), false)
			_validate_scene(CharacterVisualRules.get_head_attachment_scene(style, 16), "%s teen" % str(style.get("style_id")), false)


func _validate_body_variants(archetype: Resource, label: String) -> void:
	var teen := CharacterVisualRules.get_body_visual_scene(archetype, 16, 100)
	var regular := CharacterVisualRules.get_body_visual_scene(archetype, 17, 59)
	var heroic := CharacterVisualRules.get_body_visual_scene(archetype, 17, 60)
	_validate_scene(teen, "%s Teen" % label, true)
	_validate_scene(regular, "%s Regular" % label, true)
	_validate_scene(heroic, "%s Heroic" % label, true)
	var body_type := SkinTextureBuilder.VISUAL_BODY_TYPE_FEMALE if label == "Female" else SkinTextureBuilder.VISUAL_BODY_TYPE_MALE
	_validate_assembled_body(archetype, body_type, 16, 1, "%s Teen" % label)
	_validate_assembled_body(archetype, body_type, 23, 59, "%s Regular" % label)
	_validate_assembled_body(archetype, body_type, 23, 60, "%s Heroic" % label)
	if teen == regular or regular == heroic or teen == heroic:
		_fail("%s body variants did not resolve to distinct scenes" % label)


func _validate_scene(scene: PackedScene, label: String, require_full_skeleton: bool) -> void:
	if scene == null:
		_fail("%s scene is missing" % label)
		return
	var instance := scene.instantiate()
	if instance == null:
		_fail("%s scene could not instantiate" % label)
		return
	var skeleton := _find_skeleton(instance)
	if skeleton == null:
		_fail("%s has no Skeleton3D" % label)
	elif require_full_skeleton and skeleton.get_bone_count() != 65:
		_fail("%s expected 65 deform joints, found %d" % [label, skeleton.get_bone_count()])
	instance.free()


func _validate_assembled_body(archetype: Resource, body_type: int, age_years: int, toughness_level: int, label: String) -> void:
	var appearance := CharacterAppearanceData.new()
	appearance.body_archetype = archetype
	appearance.visual_body_type = body_type
	appearance.visual_age_years = age_years
	appearance.visual_toughness_level = toughness_level
	appearance.skin_color_customized = true
	appearance.skin_color = SkinTextureBuilder.NATURAL_SKIN_TONES[4]
	var instance := CharacterVisualAssembler.instantiate_body(archetype, appearance, SkinTextureBuilder.HUMAN_RACE_ID, body_type)
	if instance == null:
		_fail("%s did not assemble" % label)
		return
	root.add_child(instance)
	if not SkinTextureBuilder.has_custom_skin_materials(instance):
		_fail("%s custom skin material was not retained" % label)
	_clear_surface_overrides(instance)
	instance.free()


func _validate_equipment_skeleton_compatibility() -> void:
	var target_scene := CharacterVisualRules.get_body_visual_scene(HUMAN_MALE, 23, 59)
	var target_instance := target_scene.instantiate()
	var target_skeleton := _find_skeleton(target_instance)
	if target_skeleton == null:
		_fail("Could not load target skeleton for equipment compatibility")
		target_instance.free()
		return
	var files := Array(DirAccess.get_files_at(OUTFIT_DIRECTORY))
	files.sort()
	var tested_scene_count := 0
	for file_name_value in files:
		var file_name := str(file_name_value)
		if not file_name.ends_with(".gltf"):
			continue
		var scene := load("%s/%s" % [OUTFIT_DIRECTORY, file_name]) as PackedScene
		if scene == null:
			_fail("Could not load equipment scene %s" % file_name)
			continue
		var instance := scene.instantiate()
		var meshes: Array[MeshInstance3D] = []
		_collect_meshes(instance, meshes)
		if meshes.is_empty():
			_fail("Equipment scene %s contains no mesh" % file_name)
		for mesh in meshes:
			if mesh.skin == null:
				continue
			for bind_index in range(mesh.skin.get_bind_count()):
				var bind_name := str(mesh.skin.get_bind_name(bind_index))
				if not bind_name.is_empty() and target_skeleton.find_bone(bind_name) < 0:
					_fail("Equipment scene %s uses missing bone %s" % [file_name, bind_name])
		instance.free()
		tested_scene_count += 1
	if tested_scene_count != 64:
		_fail("Expected 64 modular equipment scenes, tested %d" % tested_scene_count)
	target_instance.free()


func _collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, result)


func _clear_surface_overrides(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		for surface_index in range(mesh_instance.get_surface_override_material_count()):
			mesh_instance.set_surface_override_material(surface_index, null)
	for child in node.get_children():
		_clear_surface_overrides(child)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _fail(message: String) -> void:
	_failures.append(message)
