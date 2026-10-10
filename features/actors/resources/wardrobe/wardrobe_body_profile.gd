@tool
extends Resource
class_name WardrobeBodyProfile

## One body-owned registration shared by every garment in the same cage family.
## Points are in this body's skeleton-local rest space, not world/posed space.
@export var cage_id := "humanoid_v1"
@export_file("*.glb", "*.gltf", "*.tscn") var body_scene_path := ""
@export var source_digest := ""
@export var points := PackedVector3Array()
## Explicit body-owned names only. Missing weighted anatomy otherwise refuses fit.
@export var bone_aliases: Dictionary[String, String] = {}
