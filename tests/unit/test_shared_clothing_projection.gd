extends GutTest
## Small synthetic garments exercise the real consumers without generated assets.
const FITTER = preload("res://features/actors/projection/appearance/clothing_fitter.gd")
const PROFILE = preload("res://features/actors/resources/wardrobe/wardrobe_body_profile.gd")
const BINDING = preload("res://features/inventory/resources/items/clothing_binding.gd")
const SURFACE = preload("res://features/inventory/resources/items/clothing_surface_binding.gd")
const BODY_PATH := "res://synthetic/selected_heroic_body.tscn"

class FixtureActor extends HumanoidCharacter:
	# Only omit unrelated world/animation startup. Equipment and projection are real.
	func _ready() -> void:
		pass

class FixtureOutfitter extends "res://tools/outfitter/outfitter.gd":
	# Keep the real controls/equip path; supply a synthetic actor instead of startup selection.
	func _ready() -> void:
		_build_ui()

func _rigid_fixture() -> Dictionary:
	var f := _fixture()
	f.item.equip_slot = "backpack"
	f.visual.clothing_binding = null
	f.visual.rigid_back_fit = true
	f.archetype.visual_body_type = CharacterBodyArchetypeDefinition.VISUAL_BODY_TYPE_MALE
	var skeleton: Skeleton3D = f.skeleton
	for landmark: String in ["neck_01", "spine_03", "upperarm_l", "upperarm_r"]:
		skeleton.add_bone(landmark)
	skeleton.set_bone_rest(2, Transform3D(Basis.IDENTITY, Vector3(0,2,0)))
	skeleton.set_bone_rest(3, Transform3D(Basis.IDENTITY, Vector3(0,1.7,0)))
	skeleton.set_bone_rest(4, Transform3D(Basis.IDENTITY, Vector3(0.3,1.8,0)))
	skeleton.set_bone_rest(5, Transform3D(Basis.IDENTITY, Vector3(-0.3,1.8,0)))
	skeleton.reset_bone_poses()
	var torso := MeshInstance3D.new()
	torso.mesh = BoxMesh.new()
	torso.mesh.size = Vector3(0.6,1.0,0.3)
	torso.position = Vector3(0,1.5,0)
	skeleton.add_child(torso)
	torso.skin = skeleton.create_skin_from_rest_transforms()
	torso.skeleton = NodePath("..")
	return f

func test_rigid_backpack_follows_upper_spine_without_changing_source() -> void:
	var f := _rigid_fixture()
	var skeleton: Skeleton3D = f.skeleton
	f.actor.equip_item_to_slot(f.item, "backpack")
	var mounted: Node3D = f.root.get_node_or_null("Equipped_Backpack")
	assert_not_null(mounted, f.projection.get_clothing_fit_error("backpack"))
	if mounted == null: return
	var meshes := mounted.find_children("*", "MeshInstance3D", true, false)
	assert_eq(meshes.size(), 1)
	if meshes.size() != 1: return
	var mesh := meshes[0] as MeshInstance3D
	assert_eq(mesh.skin.get_bind_name(0), &"spine_03", "Rigid bag follows live upper spine, not pelvis")
	assert_same(mesh.get_node(mesh.skeleton), skeleton)
	assert_same(mesh.mesh.surface_get_material(0), f.source_mesh.surface_get_material(0))
	assert_true(mesh.global_transform.is_equal_approx(skeleton.global_transform), "Body yaw and scale apply once")
	var vertex: Vector3 = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX][0]
	var placed := skeleton.get_bone_global_rest(3) * mesh.skin.get_bind_pose(0) * vertex
	assert_lt(placed.z, -0.15, "Pack is behind the measured body surface")
	var before := skeleton.get_bone_global_pose(3) * mesh.skin.get_bind_pose(0) * vertex
	skeleton.set_bone_pose_position(3, Vector3(0.2,1.7,0))
	var after := skeleton.get_bone_global_pose(3) * mesh.skin.get_bind_pose(0) * vertex
	assert_almost_eq(after - before, Vector3(0.2,0,0), Vector3.ONE * 0.00001)
	assert_eq(f.source_skin.get_bind_name(0), &"pelvis", "Source skin is untouched")
	assert_eq(f.source_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX][0], Vector3(0,0,0.1))
	f.actor.unequip_item_from_slot("backpack")
	assert_null(f.root.get_node_or_null("Equipped_Backpack"))

func test_rigid_backpack_creator_and_bestiary_use_same_fit_and_release() -> void:
	var f := _rigid_fixture()
	f.actor.equip_item_to_slot(f.item, "backpack")
	var original := f.root.get_node("Equipped_Backpack/Garment") as MeshInstance3D
	var preview := _editor_fixture(f)
	preview.editor._setup_preview_clothing_visuals(preview.root, preview.skeleton, f.archetype, 1.7, BODY_PATH)
	var shown := preview.root.get_node_or_null("Equipped_Backpack/Garment") as MeshInstance3D
	assert_not_null(shown)
	if shown != null:
		assert_same(shown.mesh, original.mesh, "Rigid mesh preparation is shared, not rebuilt per actor")
		assert_true(shown.skin.get_bind_pose(0).is_equal_approx(original.skin.get_bind_pose(0)))
		assert_same(shown.get_node(shown.skeleton), preview.skeleton)
	preview.editor.close_editor()
	await get_tree().process_frame
	assert_false(is_instance_valid(shown))
	var bestiary := _bestiary_fixture(f)
	var mounted := f.body.get_node_or_null("EquippedBackpackVisual/Garment") as MeshInstance3D
	assert_not_null(mounted, bestiary.get_clothing_fit_error("backpack"))
	if mounted != null:
		assert_same(mounted.mesh, original.mesh)
		assert_true(mounted.skin.get_bind_pose(0).is_equal_approx(original.skin.get_bind_pose(0)))
	f.actor.unequip_item_from_slot("backpack")
	assert_false(is_instance_valid(mounted))

func test_rigid_backpack_refuses_missing_anatomy_without_an_unfitted_fallback() -> void:
	var f := _rigid_fixture()
	f.skeleton.set_bone_name(3, "missing_upper_spine")
	f.actor.equip_item_to_slot(f.item, "backpack")
	assert_null(f.root.get_node_or_null("Equipped_Backpack"))
	assert_string_contains(f.projection.get_clothing_fit_error("backpack"), "spine_03")
	assert_same(f.actor.get_equipped_item("backpack"), f.item, "Visual refusal does not destroy a real equipped item")

func before_each() -> void:
	FITTER.clear_cache()

func _fixture() -> Dictionary:
	var source := Node3D.new()
	source.name = "AuthoredGarment"
	var rig := Skeleton3D.new()
	rig.name = "SourceRig"
	rig.add_bone("pelvis")
	source.add_child(rig)
	rig.owner = source
	var mesh := MeshInstance3D.new()
	mesh.name = "Garment"
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0,0,0.1), Vector3(1,0,0.1), Vector3(0,1,0.1)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.UP])
	arrays[Mesh.ARRAY_BONES] = PackedInt32Array([0,0,0,0, 0,0,0,0, 0,0,0,0])
	arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([1,0,0,0, 1,0,0,0, 1,0,0,0])
	mesh.mesh = ArrayMesh.new()
	mesh.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.mesh.surface_set_material(0, StandardMaterial3D.new())
	mesh.skin = Skin.new()
	mesh.skin.add_named_bind("pelvis", Transform3D.IDENTITY)
	source.add_child(mesh)
	mesh.owner = source
	mesh.skeleton = NodePath("../SourceRig")
	var scene := PackedScene.new()
	assert_eq(scene.pack(source), OK)
	var source_mesh := mesh.mesh
	var source_skin := mesh.skin
	source.free()
	var reference: Resource = PROFILE.new()
	reference.cage_id = "projection_fixture"
	reference.points = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	var profile: Resource = reference.duplicate()
	profile.points = PackedVector3Array([Vector3(0,0,0.5), Vector3(2,0,0.5), Vector3(0,2,0.5)])
	var binding: Resource = BINDING.new()
	binding.reference_profile = reference
	binding.clearance_meters = 0.03
	var surface: Resource = SURFACE.new()
	surface.mesh_path = NodePath("Garment")
	surface.vertex_count = 3
	surface.influences = 1
	surface.cage_indices = PackedInt32Array([0,1,2])
	surface.cage_weights = PackedFloat32Array([1,1,1])
	binding.surfaces.append(surface)
	var archetype := CharacterBodyArchetypeDefinition.new()
	archetype.archetype_id = "fixture_body"
	archetype.regular_visual_scene = PackedScene.new()
	archetype.wardrobe_profiles[BODY_PATH] = profile
	# A different default catches using the archetype instead of the selected build.
	archetype.wardrobe_profiles[""] = reference
	var visual := EquipmentVisualDefinition.new()
	visual.body_archetype = archetype
	visual.visual_scene = scene
	visual.clothing_binding = binding
	visual.surface_offset_ratio = 0.07
	var item := ItemDefinition.new()
	item.item_id = "fixture_garment"
	item.display_name = "Fixture garment"
	item.equip_slot = "chest"
	item.equipped_scene = scene
	item.equipped_visuals.append(visual)
	var actor := FixtureActor.new()
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.appearance_data = CharacterAppearanceData.new()
	actor.appearance_data.body_archetype = archetype
	add_child_autofree(actor)
	var equipment := EquipmentCapability.new()
	equipment.setup(actor)
	actor.add_capability(equipment)
	var projection := HumanoidBodyProjection.new()
	projection.bind_actor(actor)
	projection.configure_appearance(actor.appearance_data)
	actor.add_child(projection)
	actor._body = projection
	equipment.equipment_changed.connect(actor._on_equipment_changed)
	var root := Node3D.new()
	root.name = "CharacterVisual"
	root.transform = Transform3D(Basis(Vector3.UP, 0.4).scaled(Vector3.ONE * 1.7), Vector3(2,3,4))
	projection.add_child(root)
	projection._visual_root = root
	var body := Node3D.new()
	body.name = "SelectedBody"
	body.scene_file_path = BODY_PATH
	body.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0,0.2,0))
	root.add_child(body)
	var skeleton := Skeleton3D.new()
	skeleton.name = "TargetRig"
	skeleton.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.8), Vector3(0,0.3,0))
	skeleton.add_bone("unrelated")
	skeleton.add_bone("pelvis")
	skeleton.set_bone_rest(1, Transform3D(Basis(Vector3.UP, 0.2), Vector3(0,1,0)))
	body.add_child(skeleton)
	projection._character_skeleton = skeleton
	projection._clothing_body_scene_path = BODY_PATH
	projection._clothing_surface_offset_base = 2.0
	return {"actor":actor, "equipment":equipment, "projection":projection, "root":root, "body":body,
		"skeleton":skeleton, "item":item, "visual":visual, "archetype":archetype, "binding":binding,
		"profile":profile, "source_mesh":source_mesh, "source_skin":source_skin}

func _assert_fitted(slot: Node3D, f: Dictionary) -> void:
	assert_not_null(slot, "The equipped slot has an adapted visual")
	if slot == null: return
	var meshes := slot.find_children("*", "MeshInstance3D", true, false)
	assert_eq(meshes.size(), 1)
	if meshes.size() != 1: return
	var mesh := meshes[0] as MeshInstance3D
	var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_almost_eq(vertices[0], Vector3(0,0,0.63), Vector3.ONE * 0.00001, "Cage adaptation plus authored clearance, no legacy inflation")
	assert_almost_eq(vertices[1], Vector3(2,0,0.63), Vector3.ONE * 0.00001, "Selected build profile, not the default")
	assert_true(mesh.global_transform.is_equal_approx(f.skeleton.global_transform), "Body scale and yaw are applied once")
	assert_same(mesh.get_node(mesh.skeleton), f.skeleton)
	assert_eq(mesh.skin.get_bind_name(0), &"pelvis")
	assert_true((f.skeleton.get_bone_global_rest(1) * mesh.skin.get_bind_pose(0)).is_equal_approx(Transform3D.IDENTITY), "Keep rebased target inverse bind on a reordered rig")
	assert_same(mesh.mesh.surface_get_material(0), f.source_mesh.surface_get_material(0))
	assert_eq(mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_WEIGHTS], f.source_mesh.surface_get_arrays(0)[Mesh.ARRAY_WEIGHTS])
	assert_almost_eq(f.source_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX][0], Vector3(0,0,0.1), Vector3.ONE * 0.00001, "Authored mesh is unchanged")
	assert_eq(f.source_skin.get_bind_pose(0), Transform3D.IDENTITY, "Authored inverse bind is unchanged")

func test_actor_equip_fits_selected_body_and_unequip_releases_visual() -> void:
	var f := _fixture()
	f.actor.equip_item_to_slot(f.item, "chest")
	var mounted := f.root.get_node_or_null("Equipped_Chest") as Node3D
	_assert_fitted(mounted, f)
	f.actor.unequip_item_from_slot("chest")
	assert_null(f.root.get_node_or_null("Equipped_Chest"))
	assert_false(is_instance_valid(mounted))
	assert_same(f.projection._character_skeleton, f.skeleton)

func test_actor_fit_failures_are_explicit_without_source_fallback() -> void:
	for failure in ["missing_selected_profile", "unsupported_body", "stale_binding"]:
		var f := _fixture()
		match failure:
			"missing_selected_profile": f.archetype.wardrobe_profiles.erase(BODY_PATH)
			"unsupported_body": f.archetype.wardrobe_profiles.clear()
			"stale_binding": f.binding.surfaces[0].vertex_count = 4
		f.actor.equip_item_to_slot(f.item, "chest")
		assert_null(f.root.get_node_or_null("Equipped_Chest"), failure + " refuses unadapted fallback")
		assert_same(f.actor.get_equipped_item("chest"), f.item, "Projection never mutates durable equipment")
		assert_true(f.projection.has_method("get_clothing_fit_error"), "Consumers can display the failed fit")
		if not f.projection.has_method("get_clothing_fit_error"): continue
		assert_false(str(f.projection.get_clothing_fit_error("chest")).is_empty(), failure)
		f.archetype.wardrobe_profiles[BODY_PATH] = f.profile
		f.archetype.wardrobe_profiles[""] = f.binding.reference_profile
		f.binding.surfaces[0].vertex_count = 3
		f.actor.equip_item_to_slot(f.item, "chest")
		_assert_fitted(f.root.get_node_or_null("Equipped_Chest"), f)
		assert_eq(f.projection.get_clothing_fit_error("chest"), "", "Successful replacement clears failure")
		f.archetype.wardrobe_profiles.erase(BODY_PATH)
		f.actor.equip_item_to_slot(f.item, "chest")
		f.actor.unequip_item_from_slot("chest")
		assert_eq(f.projection.get_clothing_fit_error("chest"), "", "Removing a failed item clears failure")

func _editor_fixture(f: Dictionary) -> Dictionary:
	var editor := CharacterEditorWindow.new()
	add_child_autofree(editor)
	editor.target_actor = f.actor
	var model := Node3D.new()
	editor._preview_root.add_child(model)
	editor._preview_model = model
	var root := Node3D.new()
	root.name = "PreviewCharacterVisual"
	root.transform = f.root.transform
	model.add_child(root)
	var body: Node3D = f.body.duplicate(0)
	root.add_child(body)
	var result := f.duplicate()
	result.editor = editor
	result.root = root
	result.body = body
	result.skeleton = body.get_node("TargetRig")
	return result

func test_creator_uses_fitted_mesh_and_close_releases_it() -> void:
	var f := _fixture()
	f.actor.equip_item_to_slot(f.item, "chest")
	var preview := _editor_fixture(f)
	preview.editor._setup_preview_clothing_visuals(preview.root, preview.skeleton, f.archetype, 1.7, BODY_PATH)
	var mounted := preview.root.get_node_or_null("Equipped_Chest") as Node3D
	_assert_fitted(mounted, preview)
	assert_eq(preview.editor.get_preview_clothing_surface_offset("chest"), 0.0)
	preview.editor.close_editor()
	await get_tree().process_frame
	assert_false(is_instance_valid(mounted), "Closing the creator releases its fitted visual")
	assert_same(f.actor.get_equipped_item("chest"), f.item)

func test_creator_shows_refused_fit_in_its_normal_ui_and_clears_on_close() -> void:
	for failure in ["missing_selected_profile", "unsupported_body", "stale_binding"]:
		var f := _fixture()
		f.actor.equip_item_to_slot(f.item, "chest")
		match failure:
			"missing_selected_profile": f.archetype.wardrobe_profiles.erase(BODY_PATH)
			"unsupported_body": f.archetype.wardrobe_profiles.clear()
			"stale_binding": f.binding.surfaces[0].vertex_count = 4
		var preview := _editor_fixture(f)
		preview.editor.show()
		preview.editor._setup_preview_clothing_visuals(preview.root, preview.skeleton, f.archetype, 1.7, BODY_PATH)
		assert_null(preview.root.get_node_or_null("Equipped_Chest"), failure + " refuses unadapted fallback")
		var status := preview.editor.find_child("ClothingFitStatus", true, false) as Label
		assert_not_null(status, "The creator exposes its failed fitting result to the user")
		if status == null: continue
		assert_true(status.is_visible_in_tree())
		assert_string_contains(status.text, "Chest")
		assert_string_contains(status.text, "Clothing fit failed")
		preview.editor.close_editor()
		assert_eq(status.text, "")
		assert_false(status.visible)
		await get_tree().process_frame

func _bestiary_fixture(f: Dictionary) -> BestiaryEquipmentProjection:
	f.equipment.equipment_changed.disconnect(f.actor._on_equipment_changed)
	var projection := BestiaryEquipmentProjection.new()
	f.body.add_child(projection)
	projection.configure(f.body, f.equipment, PackedStringArray(), f.archetype)
	return projection

func test_bestiary_fits_selected_body_before_mount_and_preserves_target_binds() -> void:
	var f := _fixture()
	var projection := _bestiary_fixture(f)
	f.actor.equip_item_to_slot(f.item, "chest")
	var mounted := f.body.get_node_or_null("EquippedChestVisual") as Node3D
	_assert_fitted(mounted, f)
	f.actor.unequip_item_from_slot("chest")
	assert_false(is_instance_valid(mounted))
	f.actor.equip_item_to_slot(f.item, "chest")
	mounted = f.body.get_node_or_null("EquippedChestVisual")
	f.body.remove_child(projection)
	assert_false(mounted.visible, "Projection exit hides clothing before deferred free")
	assert_true(mounted.is_queued_for_deletion())
	projection.free()
	await get_tree().process_frame
	assert_false(is_instance_valid(mounted))
	assert_same(f.actor.get_equipped_item("chest"), f.item)

func test_bestiary_reports_refused_fits_and_removal_clears_failure() -> void:
	for failure in ["missing_selected_profile", "unsupported_body", "stale_binding", "missing_skeleton"]:
		var f := _fixture()
		match failure:
			"missing_selected_profile": f.archetype.wardrobe_profiles.erase(BODY_PATH)
			"unsupported_body": f.archetype.wardrobe_profiles.clear()
			"stale_binding": f.binding.surfaces[0].vertex_count = 4
			"missing_skeleton": f.skeleton.free()
		var projection := _bestiary_fixture(f)
		f.actor.equip_item_to_slot(f.item, "chest")
		assert_null(f.body.get_node_or_null("EquippedChestVisual"), failure + " refuses unadapted fallback")
		assert_true(projection.has_method("get_clothing_fit_error"), "The owning UI can display the failed fit")
		if not projection.has_method("get_clothing_fit_error"): continue
		assert_false(str(projection.call("get_clothing_fit_error", "chest")).is_empty(), failure)
		f.actor.unequip_item_from_slot("chest")
		assert_eq(projection.call("get_clothing_fit_error", "chest"), "")

func test_outfitter_displays_fit_failure_after_normal_equip_and_clears_on_remove() -> void:
	var f := _fixture()
	f.archetype.wardrobe_profiles.erase(BODY_PATH)
	var viewer := FixtureOutfitter.new()
	add_child_autofree(viewer)
	viewer.actor = f.actor
	viewer.selected_race = CharacterRaceDefinition.new()
	viewer.selected_body = f.archetype
	viewer.selected_slot = "chest"
	viewer.catalog.items.assign([f.item])
	assert_true(viewer.equip_item(f.item, "chest"), "Durable equipment still belongs to the capability")
	assert_string_contains(viewer.status.text, "Clothing fit failed")
	assert_string_contains(viewer.status.text, f.projection.get_clothing_fit_error("chest"))
	assert_null(f.root.get_node_or_null("Equipped_Chest"))
	viewer.select_slot("chest")
	assert_string_contains(viewer.status.text, "Clothing fit failed")
	viewer.remove_button.pressed.emit()
	assert_null(f.actor.get_equipped_item("chest"))
	assert_false(viewer.status.text.contains("Clothing fit failed"))
	assert_string_contains(viewer.status.text, "None")

func test_unbound_legacy_clothing_keeps_existing_mesh_and_skin_paths() -> void:
	var f := _fixture()
	f.visual.clothing_binding = null
	f.visual.surface_offset_ratio = 0.0
	f.actor.equip_item_to_slot(f.item, "chest")
	var actor_mesh := f.root.get_node("Equipped_Chest/Garment") as MeshInstance3D
	assert_same(actor_mesh.mesh, f.source_mesh)
	assert_same(actor_mesh.skin, f.source_skin)
	var preview := _editor_fixture(f)
	preview.editor._setup_preview_clothing_visuals(preview.root, preview.skeleton, f.archetype, 1.7, BODY_PATH)
	var preview_mesh := preview.root.get_node("Equipped_Chest/Garment") as MeshInstance3D
	assert_same(preview_mesh.mesh, f.source_mesh)
	assert_same(preview_mesh.skin, f.source_skin)
	var bestiary := _bestiary_fixture(f)
	var bestiary_mesh := f.body.get_node("EquippedChestVisual/Garment") as MeshInstance3D
	assert_same(bestiary_mesh.mesh, f.source_mesh)
	assert_eq(bestiary_mesh.skin.get_bind_pose(0), f.source_skin.get_bind_pose(0))
	assert_eq(bestiary_mesh.skin.get_bind_bone(0), 1, "Legacy remapping still resolves reordered target indices")
	assert_eq(bestiary.get_clothing_fit_error("chest"), "")
	assert_eq(FITTER.cache_stats().builds, 0, "Unbound legacy gear does not enter the fitter")

func test_shared_slots_remain_independent_and_model_teardown_releases_fitted_meshes() -> void:
	for consumer in ["actor", "bestiary"]:
		var f := _fixture()
		if consumer == "bestiary": _bestiary_fixture(f)
		f.actor.equip_item_to_slot(f.item, "chest")
		var root: Node3D = f.body if consumer == "bestiary" else f.root
		var chest_name := "EquippedChestVisual" if consumer == "bestiary" else "Equipped_Chest"
		var head_name := "EquippedHeadVisual" if consumer == "bestiary" else "Equipped_Head"
		var chest := root.get_node(chest_name)
		var head := f.item.duplicate(false) as ItemDefinition
		head.equip_slot = "head"
		f.actor.equip_item_to_slot(head, "head")
		assert_same(root.get_node(chest_name), chest, "An unrelated slot keeps its visual")
		var mounted_head := root.get_node(head_name)
		_assert_fitted(mounted_head, f)
		assert_gt(FITTER.cache_stats().hits, 0, "Same source/body reuses the fitted mesh cache")
		f.actor.unequip_item_from_slot("chest")
		assert_same(root.get_node(head_name), mounted_head)
		root.free()
		await get_tree().process_frame
		assert_false(is_instance_valid(mounted_head), "Whole model teardown does not retain fitted nodes")
		assert_same(f.actor.get_equipped_item("head"), head)

func test_clothing_keeps_weapon_grip_path_and_race_slot_policy() -> void:
	for consumer in ["actor", "bestiary"]:
		var f := _fixture()
		f.skeleton.add_bone("hand_r")
		if consumer == "bestiary": _bestiary_fixture(f)
		var source := Node3D.new()
		var grip := Marker3D.new()
		grip.name = "GripPoint_Primary"
		grip.position = Vector3(0.1, 0.2, 0.3)
		source.add_child(grip)
		grip.owner = source
		var weapon := ItemDefinition.new()
		weapon.equip_slot = "weapon"
		weapon.equipped_transform = Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0.2,0,0))
		weapon.equipped_scene = PackedScene.new()
		assert_eq(weapon.equipped_scene.pack(source), OK)
		var expected := weapon.equipped_transform * grip.transform.affine_inverse()
		source.free()
		f.actor.equip_item_to_slot(weapon, "weapon")
		var mounted := f.skeleton.find_child("EquippedWeaponVisual", true, false) as Node3D
		assert_not_null(mounted)
		if mounted == null: continue
		assert_true((mounted.get_child(0) as Node3D).transform.is_equal_approx(expected))
		f.actor.equip_item_to_slot(f.item, "chest")
		assert_same(f.skeleton.find_child("EquippedWeaponVisual", true, false), mounted)
		f.actor.unequip_item_from_slot("chest")
		assert_same(f.skeleton.find_child("EquippedWeaponVisual", true, false), mounted)
		var race := CharacterRaceDefinition.new()
		race.equipment_slots = PackedStringArray(["weapon"])
		f.actor.appearance_data.character_race = race
		f.actor.equip_item_to_slot(f.item, "chest")
		assert_null(f.actor.get_equipped_item("chest"), "Wardrobe does not broaden race slots")
		f.actor.unequip_item_from_slot("weapon")
		assert_false(is_instance_valid(mounted))
