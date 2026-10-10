@tool
extends Resource
class_name ClothingSurfaceBinding

## Imported source surface ordering is authoritative. Stale bindings are refused.
@export var mesh_path: NodePath
@export var surface_index := 0
@export var vertex_count := 0
@export var mesh_to_reference := Transform3D.IDENTITY
@export_range(1, 32, 1) var influences := 12
@export var cage_indices := PackedInt32Array()
@export var cage_weights := PackedFloat32Array()
