@tool
extends Resource
class_name ClothingBinding

## Generated once from one authored garment; never a target-body garment mesh.
## Rebuild with tools/wardrobe when the source garment or reference cage changes.
@export var reference_profile: Resource
@export_file("*.glb", "*.gltf", "*.tscn") var source_scene_path := ""
@export var source_digest := ""
## Original source garment ease, in meters. Not a target-body inflation rule.
@export_range(0.0, 0.08, 0.001) var clearance_meters := 0.0
@export var surfaces: Array[Resource] = []
