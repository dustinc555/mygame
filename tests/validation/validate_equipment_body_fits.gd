extends SceneTree
## One authored garment through normal Outfitter, actor and creator lifecycles.
## Saved-resource integration proof, not a claim of arbitrary-pose clearance.

var checks := 0
var failures: Array[String] = []
var timings: Array[Dictionary] = []
var viewer
var editor

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	viewer = load("res://tools/outfitter/outfitter.tscn").instantiate()
	root.add_child(viewer)
	for i in viewer.catalog.races.size():
		if viewer.catalog.races[i].race_id == "human":
			viewer.select_race(i)
			break
	await _settle()
	editor = load("res://features/ui/projection/character_editor_window.gd").new()
	root.add_child(editor)
	var items: Array[ItemDefinition] = []
	for item in viewer.catalog.items:
		if item.has_clothing_binding(): items.append(item)
	_check(not items.is_empty(), "The real catalog contains shared-source clothing")
	var expected_pairs := items.size() * 6
	var exercised := 0
	for sex in ["male", "female"]:
		var body: Resource = load("res://features/actors/resources/character_body_archetypes/human_" + sex + ".tres")
		var body_index: int = viewer._body_options.find(body)
		_check(body_index >= 0, "Normal catalog exposes " + sex)
		if body_index < 0: continue
		viewer.select_body(body_index)
		await _settle()
		for build in ["regular", "heroic", "teen"]:
			var started := Time.get_ticks_usec()
			viewer.select_build(viewer._build_options.find(build))
			await _settle()
			timings.append({"body": sex + "_" + build, "operation": "build", "usec": Time.get_ticks_usec() - started})
			var path: String = body.get(build + "_visual_scene").resource_path
			_check(body.get_wardrobe_profile(path) != null, "Registered body " + path)
			for item in items:
				exercised += 1
				started = Time.get_ticks_usec()
				_check(viewer.equip_item(item, item.equip_slot), "Equip " + item.display_name)
				timings.append({"body": sex + "_" + build, "item": item.resource_path, "operation": "equip", "usec": Time.get_ticks_usec() - started})
				_check_pair(item, body, path)
				_check(viewer.equip_item(null, item.equip_slot), "Unequip succeeds")
				_check(_slot(item.equip_slot) == null, "Unequip removes garment")
				started = Time.get_ticks_usec()
				_check(viewer.equip_item(item, item.equip_slot), "Warm equip succeeds")
				timings.append({"body": sex + "_" + build, "item": item.resource_path, "operation": "warm_equip", "usec": Time.get_ticks_usec() - started})
				_check(viewer.equip_item(null, item.equip_slot), "Warm garment removed")
				await process_frame
		await _check_transitions(body)
	_check(exercised == expected_pairs, "Every shared item and current human body exercised exactly once")
	editor.free()
	viewer.free()
	await process_frame
	print("WARDROBE_TIMINGS ", JSON.stringify(timings))
	print("EQUIPMENT_BODY_FITS_RESULT items=%d pairs=%d checks=%d failures=%d" % [items.size(), exercised, checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _settle() -> void:
	for frame in 600:
		await process_frame
		if not viewer._building: return
	_check(false, "Normal Outfitter build completed within 600 frames")

func _slot(slot: String) -> Node:
	return viewer.actor.get_body_projection().get_visual_root().find_child("Equipped_" + slot.capitalize(), true, false)

func _check_pair(item: ItemDefinition, body: Resource, path: String) -> void:
	var label := item.display_name + " on " + path.get_file()
	var projection = viewer.actor.get_body_projection()
	var body_root: Node = projection.get_visual_root().get_child(0)
	_check(body_root.scene_file_path == path, "Exact saved body: " + label)
	_check(projection.get_clothing_fit_error(item.equip_slot).is_empty(), "No fit failure: " + label)
	var definition: Resource = item.get_equipment_visual_for_body_archetype(body, path)
	_check(definition != null, "Compatible shared definition: " + label)
	if definition == null: return
	_check(item.equipped_visuals.size() == 1 and definition.body_fits.is_empty(), "One source, no preset lookup: " + label)
	_check(definition.clothing_binding != null and is_zero_approx(definition.surface_offset_ratio), "One bound fit without second inflation: " + label)
	var expected: Node = definition.visual_scene.instantiate()
	var expected_meshes := expected.find_children("*", "MeshInstance3D", true, false)
	var actual_slot := _slot(item.equip_slot)
	_check(actual_slot != null, "Runtime garment mounted: " + label)
	if actual_slot == null:
		expected.free()
		return
	var actual_meshes := actual_slot.find_children("*", "MeshInstance3D", true, false)
	_check(not actual_meshes.is_empty() and actual_meshes.size() == expected_meshes.size(), "All source meshes fitted: " + label)
	editor.open_for_actor(viewer.actor)
	var preview_slot: Node = editor._preview_model.find_child("Equipped_" + item.equip_slot.capitalize(), true, false)
	_check(preview_slot != null, "Creator garment mounted: " + label)
	_check(editor._get_preview_body_root().scene_file_path == path, "Creator uses exact body: " + label)
	_check(is_zero_approx(editor.get_preview_clothing_surface_offset(item.equip_slot)), "Creator does not inflate twice")
	var previews: Array[Node] = preview_slot.find_children("*", "MeshInstance3D", true, false) if preview_slot != null else []
	_check(previews.size() == actual_meshes.size(), "Creator mesh coverage: " + label)
	for index in mini(expected_meshes.size(), mini(actual_meshes.size(), previews.size())):
		var actual := actual_meshes[index] as MeshInstance3D
		_check(previews[index].mesh == actual.mesh, "Actor and creator share the generated mesh cache: " + label)
		_check(actual.mesh.get_surface_count() == expected_meshes[index].mesh.get_surface_count(), "Source surfaces retained")
		for surface in mini(actual.mesh.get_surface_count(), expected_meshes[index].mesh.get_surface_count()):
			var before: Array = expected_meshes[index].mesh.surface_get_arrays(surface)
			var after := actual.mesh.surface_get_arrays(surface)
			for channel in [Mesh.ARRAY_INDEX, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
				_check(before[channel] == after[channel], "Source topology/UV/skinning retained: " + label)
		_check_skin(actual, body_root.find_child("Skeleton3D", true, false), label)
	_check_body_visible(body_root, expected)
	editor.close_editor()
	expected.free()

func _check_skin(mesh: MeshInstance3D, skeleton: Skeleton3D, label: String) -> void:
	_check(mesh.get_node_or_null(mesh.skeleton) == skeleton, "Live body skeleton: " + label)
	_check(mesh.skin != null and mesh.skin.get_bind_count() > 0, "Named skin present: " + label)
	if mesh.skin == null: return
	for bind in mesh.skin.get_bind_count():
		var bone := skeleton.find_bone(mesh.skin.get_bind_name(bind))
		_check(bone >= 0, "Bind resolves by name: " + label)
		if bone >= 0:
			_check((skeleton.get_bone_global_rest(bone) * mesh.skin.get_bind_pose(bind)).is_equal_approx(Transform3D.IDENTITY), "Inverse bind matches target rest: " + label)

func _check_transitions(body: Resource) -> void:
	var outfit: Array[ItemDefinition] = []
	for id in ["traveler_leather_jacket", "traveler_trousers", "traveler_hide_boots", "traveler_hide_gloves"]:
		var item := load("res://features/inventory/resources/items/" + id + ".tres") as ItemDefinition
		outfit.append(item)
		_check(viewer.equip_item(item, item.equip_slot), "Equip before body/sliders change")
	for state in [[23, 1], [23, 60], [15, 1]]:
		var appearance: CharacterAppearanceData = viewer.actor.get_appearance_copy()
		appearance.visual_age_years = state[0]
		appearance.visual_toughness_level = state[1]
		viewer.actor.apply_appearance_data(appearance)
		var scene: PackedScene = CharacterVisualRules.get_body_visual_scene(body, state[0], state[1])
		for item in outfit: _check_pair(item, body, scene.resource_path)
		for amount in [-1.0, 0.0, 1.0]:
			var old_slot := _slot("legs")
			for property: String in viewer.bone_sliders: viewer.bone_sliders[property].value = amount
			_check(_slot("legs") == old_slot, "Bone sliders preserve clothing rather than selecting a replacement")
			var skeleton: Skeleton3D = viewer.actor.get_body_projection().get_visual_root().get_child(0).find_child("Skeleton3D", true, false)
			for item in outfit:
				var slot := _slot(item.equip_slot)
				_check(slot != null, "Slider retains independent slot: " + item.equip_slot)
				if slot != null:
					for mesh: MeshInstance3D in slot.find_children("*", "MeshInstance3D", true, false): _check_skin(mesh, skeleton, item.display_name)
		viewer.reset_body_proportions()
		_check(viewer.select_animation("Walk"), "Normal animation still plays after fitting/sliders")
		viewer.actor.get_body_projection().get_primary_animation_player().advance(0.2)
		await process_frame
	for item in outfit: _check(viewer.equip_item(null, item.equip_slot), "Remove independent transition slot")

func _check_body_visible(body_root: Node, _garment: Node) -> void:
	var body_source: Node = load(body_root.scene_file_path).instantiate()
	for mesh in body_source.find_children("*", "MeshInstance3D", true, false):
		# Automatic eyebrow replacement is unrelated to equipment coverage.
		if "eyebrow" in str(mesh.name).to_lower(): continue
		var live: Node = body_root.get_node_or_null(body_source.get_path_to(mesh))
		_check(live != null and live.visible == mesh.visible, "Clothing did not hide body geometry")
	body_source.free()
