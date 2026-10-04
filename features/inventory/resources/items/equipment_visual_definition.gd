@tool
extends Resource

class_name EquipmentVisualDefinition

@export var body_archetype: Resource
@export var body_archetype_id := ""
@export var visual_scene: PackedScene
## Shared source-to-body binding. New clothing uses this, not preset body_fits.
@export var clothing_binding: Resource
@export var equipped_transform := Transform3D.IDENTITY
@export_range(0.0, 0.08, 0.001) var surface_offset_ratio := 0.0
## Actual body scene path -> pre-fitted clothing scene path. Loaded on demand,
## retained with this definition; the original visual remains the fallback.
@export var body_fits: Dictionary[String, String] = {}
@export var visual_layer := ""
@export var visual_coverage := ""
@export var replaces_body_slots: PackedStringArray = PackedStringArray()
@export_multiline var visual_notes := ""

# Live clothing copies meshes onto the actor skeleton, not the source scene.
# Keep the scene alive between swaps. This cache dies with its item definition.
var _loaded_body_fits: Dictionary[String, PackedScene] = {}


func get_body_archetype_id() -> String:
	if body_archetype != null:
		var resource_id := str(body_archetype.get("archetype_id"))
		if not resource_id.is_empty():
			return resource_id
	return body_archetype_id


func matches_body_archetype(archetype: Resource) -> bool:
	if archetype == null:
		return false
	if clothing_binding != null:
		var reference: Resource = clothing_binding.get("reference_profile")
		if reference == null or not archetype.has_method("get_wardrobe_profile"):
			return false
		var profile: Resource = archetype.get_wardrobe_profile()
		return profile != null and not str(reference.get("cage_id")).is_empty() and profile.get("cage_id") == reference.get("cage_id")
	var archetype_id := str(archetype.get("archetype_id"))
	return not archetype_id.is_empty() and get_body_archetype_id() == archetype_id


func for_body_scene(body_scene_path: String) -> Resource:
	if clothing_binding != null:
		return self
	if not body_fits.has(body_scene_path):
		return self
	var path: String = body_fits[body_scene_path]
	if not ResourceLoader.exists(path, "PackedScene"):
		push_error("Equipment fit cannot be loaded: %s" % path)
		return self
	var scene: PackedScene = _loaded_body_fits.get(path) if not Engine.is_editor_hint() else null
	if scene == null:
		scene = load(path) as PackedScene
	if scene == null:
		push_error("Equipment fit is not a PackedScene: %s" % path)
		return self
	if not Engine.is_editor_hint():
		_loaded_body_fits[path] = scene
	var fitted := duplicate(false)
	fitted.visual_scene = scene
	fitted.surface_offset_ratio = 0.0
	return fitted
