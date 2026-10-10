extends GutTest
## Saved content contract; motion/clearance is checked in the actual Outfitter.
const FITTER = preload("res://features/actors/projection/appearance/clothing_fitter.gd")

const PARTS := {
	"traveler_leather_jacket": "chest",
	"traveler_trousers": "legs",
	"traveler_hide_boots": "feet",
	"traveler_hide_gloves": "hands",
}
var _saved_resources: Array[Resource] = []

func before_all() -> void:
	# Retain immutable saved assets for this script. Godot's resource cache uses
	# weak references; dropping each loop's last reference decodes the same GLBs
	# again. Every fit still creates and frees its own body and garment instances.
	for id in PARTS:
		_saved_resources.append(load("res://features/inventory/resources/items/" + id + ".tres"))
	for sex in ["male", "female"]:
		_saved_resources.append(load("res://features/actors/resources/character_body_archetypes/human_" + sex + ".tres"))

func after_all() -> void:
	_saved_resources.clear()

func test_matching_outfit_items_keep_independent_slots() -> void:
	for id in PARTS:
		var path: String = "res://features/inventory/resources/items/" + id + ".tres"
		assert_true(ResourceLoader.exists(path), "Saved outfit item: " + id)
		if not ResourceLoader.exists(path): continue
		var item := load(path) as ItemDefinition
		assert_not_null(item)
		if item == null: continue
		assert_eq(item.item_id, id)
		assert_eq(item.equip_slot, PARTS[id])
		assert_eq(item.compatible_races, PackedStringArray(["human"]))
		assert_eq(item.equipped_visuals.size(), 1, "One source garment, not male/female replacement meshes")
		for visual in item.equipped_visuals:
			assert_true(visual.replaces_body_slots.is_empty(), "The outfit must not hide anatomy")
			assert_eq(visual.surface_offset_ratio, 0.0, "Authored fits must not be inflated at runtime")

func test_matching_outfit_defaults_use_one_accepted_source() -> void:
	for id in PARTS:
		var item := load("res://features/inventory/resources/items/" + id + ".tres") as ItemDefinition
		var folder: String = "res://assets/items/equipment/" + id + ("/body_fits" if id == "traveler_leather_jacket" else "")
		for sex in ["male", "female"]:
			var body: Resource = load("res://features/actors/resources/character_body_archetypes/human_" + sex + ".tres")
			var visual := item.get_equipment_visual_for_body_archetype(body)
			assert_not_null(visual)
			if visual == null: continue
			assert_eq(visual.visual_scene.resource_path, folder + "/male_regular.glb")
			assert_not_null(visual.clothing_binding)
			assert_true(visual.body_fits.is_empty(), "No separately maintained preset fits")
		assert_eq(item.world_scene.resource_path, folder + "/male_regular.glb")

func test_matching_outfit_reuses_one_binding_with_body_owned_profiles() -> void:
	for id in PARTS:
		var item := load("res://features/inventory/resources/items/" + id + ".tres") as ItemDefinition
		var source: Resource = item.equipped_visuals[0]
		assert_not_null(source.clothing_binding)
		if source.clothing_binding == null: continue
		assert_eq(source.clothing_binding.source_scene_path, source.visual_scene.resource_path)
		for sex in ["male", "female"]:
			var body: Resource = load("res://features/actors/resources/character_body_archetypes/human_" + sex + ".tres")
			for kind in ["regular", "heroic", "teen"]:
				var target_scene: PackedScene = body.get(kind + "_visual_scene")
				var profile: Resource = body.get_wardrobe_profile(target_scene.resource_path)
				assert_not_null(profile, "Reusable body registration: " + sex + " " + kind)
				if profile == null: continue
				assert_eq(profile.body_scene_path, target_scene.resource_path)
				assert_eq(profile.cage_id, source.clothing_binding.reference_profile.cage_id)
				assert_same(item.get_equipment_visual_for_body_archetype(body, target_scene.resource_path), source)
				assert_eq(source.surface_offset_ratio, 0.0, "Do not inflate the generated garment a second time")

func test_trousers_cover_bare_calves_without_requiring_boots() -> void:
	var item := load("res://features/inventory/resources/items/traveler_trousers.tres") as ItemDefinition
	for sex in ["male", "female"]:
		var archetype := load("res://features/actors/resources/character_body_archetypes/human_" + sex + ".tres") as CharacterBodyArchetypeDefinition
		for context in [[23, 1], [23, 60], [15, 1]]:
			var body_scene := CharacterVisualRules.get_body_visual_scene(archetype, context[0], context[1])
			var visual := item.get_equipment_visual_for_body_archetype(archetype, body_scene.resource_path)
			assert_not_null(visual)
			if visual == null: continue
			var body := body_scene.instantiate()
			var source: Node3D = visual.visual_scene.instantiate()
			var result := FITTER.fit(source, visual.clothing_binding, archetype.get_wardrobe_profile(body_scene.resource_path), body.find_child("Skeleton3D", true, false))
			source.free()
			assert_eq(result.error, "", body_scene.resource_path)
			if not result.has("visual"):
				body.free()
				continue
			var trousers: Node = result.visual
			var problems := _calf_coverage_problems(body, trousers)
			assert_true(problems.is_empty(), body_scene.resource_path + ": " + "; ".join(problems))
			body.free()
			trousers.free()

# Require a millimeter of rest-pose room around the calf, not near-coincident
# surfaces hidden by boots. Motion and footwear layering still need visual review.
func _calf_coverage_problems(body: Node, trousers: Node) -> Array[String]:
	var problems: Array[String] = []
	var skeleton := body.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return ["Missing body skeleton"]
	var body_faces := _root_space_faces(body)
	var cloth_faces := _root_space_faces(trousers)
	var skeleton_transform := Transform3D.IDENTITY
	var ancestor: Node = skeleton
	while ancestor != null:
		if ancestor is Node3D:
			skeleton_transform = ancestor.transform * skeleton_transform
		ancestor = ancestor.get_parent()
	for side in ["l", "r"]:
		var calf := skeleton.find_bone("calf_" + side)
		var foot := skeleton.find_bone("foot_" + side)
		if calf < 0 or foot < 0:
			problems.append("Missing calf/foot bones: " + side)
			continue
		var ankle := skeleton_transform * skeleton.get_bone_global_rest(foot).origin
		var knee := skeleton_transform * skeleton.get_bone_global_rest(calf).origin
		var sign_x := signf(knee.x)
		for step in range(2, 9):
			var fraction := step / 10.0
			var center_3d := ankle.lerp(knee, fraction)
			var center := Vector2(center_3d.x, center_3d.z)
			var skin := _section_segments(body_faces, center_3d.y, sign_x)
			var cloth := _section_segments(cloth_faces, center_3d.y, sign_x)
			# Bounds alone miss inward dents between the cardinal directions.
			for sample in 32:
				var direction := Vector2.RIGHT.rotated(TAU * sample / 32.0)
				var skin_radius := _section_radius(skin, center, direction)
				var cloth_radius := _section_radius(cloth, center, direction)
				if skin_radius < 0.0 or cloth_radius < 0.0:
					problems.append("Missing full-length calf section: %s %.2f ray %d" % [side, fraction, sample])
				elif cloth_radius < skin_radius + 0.001:
					problems.append("Cloth lacks bare-calf clearance: %s %.2f ray %d" % [side, fraction, sample])
	return problems

func _root_space_faces(node: Node, parent_transform := Transform3D.IDENTITY) -> PackedVector3Array:
	var transform: Transform3D = parent_transform
	if node is Node3D:
		transform *= node.transform
	var faces := PackedVector3Array()
	if node is MeshInstance3D and node.mesh != null:
		faces.append_array(transform * node.mesh.get_faces())
	for child in node.get_children():
		faces.append_array(_root_space_faces(child, transform))
	return faces

func _section_segments(faces: PackedVector3Array, height: float, side: float) -> PackedVector2Array:
	var segments := PackedVector2Array()
	for triangle in range(0, faces.size(), 3):
		var points := PackedVector2Array()
		for edge in 3:
			var a := faces[triangle + edge]
			var b := faces[triangle + (edge + 1) % 3]
			if (a.y > height) == (b.y > height):
				continue
			var point := a.lerp(b, (height - a.y) / (b.y - a.y))
			if point.x * side <= 0.0:
				continue
			points.append(Vector2(point.x, point.z))
		if points.size() == 2:
			segments.append_array(points)
	return segments

func _section_radius(segments: PackedVector2Array, center: Vector2, direction: Vector2) -> float:
	var radius := -1.0
	for segment in range(0, segments.size(), 2):
		var intersection: Variant = Geometry2D.segment_intersects_segment(center, center + direction, segments[segment], segments[segment + 1])
		if intersection is Vector2:
			radius = maxf(radius, center.distance_to(intersection))
	return radius
