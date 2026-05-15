extends "res://scripts/characters/humanoid_character.gd"

class_name FactionHumanoid

@export var base_color := Color(0.62, 0.62, 0.62, 1.0)

@onready var body_mesh: MeshInstance3D = get_node_or_null("BodyMesh") as MeshInstance3D

var _body_material := StandardMaterial3D.new()


func _ready() -> void:
	super._ready()
	if body_mesh == null:
		return
	_body_material.roughness = 0.9
	_body_material.albedo_color = base_color
	body_mesh.material_override = _body_material
