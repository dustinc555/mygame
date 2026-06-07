extends "res://scripts/projection/body_projection_adapter.gd"

class_name PlaceholderBodyProjection

var _mesh_instance: MeshInstance3D
var _label: Label3D


func _ready() -> void:
	_ensure_visuals()


func apply_projection_snapshot(record: Dictionary, _equipment_slots: Dictionary, _combat_state: Dictionary = {}) -> void:
	_ensure_visuals()
	var color: Color = record.get("base_color", Color(0.35, 0.72, 0.95, 1.0))
	if _mesh_instance != null:
		_mesh_instance.material_override = _material(color)
	if _label != null:
		_label.text = str(record.get("member_name", record.get("actor_id", "Actor")))


func get_body_adapter_id() -> String:
	return "placeholder"


func get_projection_debug_state() -> Dictionary:
	return {
		"body_adapter_id": get_body_adapter_id(),
		"placeholder_visual_ready": _mesh_instance != null,
	}


func _ensure_visuals() -> void:
	if _mesh_instance != null:
		return
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "PlaceholderBody"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.38
	capsule.height = 1.25
	_mesh_instance.mesh = capsule
	_mesh_instance.position = Vector3(0.0, 0.65, 0.0)
	add_child(_mesh_instance)
	_label = Label3D.new()
	_label.name = "NameLabel"
	_label.position = Vector3(0.0, 1.55, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 22
	_label.text = "Placeholder"
	add_child(_label)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material
