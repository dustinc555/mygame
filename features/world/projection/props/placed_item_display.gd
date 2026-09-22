@tool
extends "res://features/world/projection/props/tabletop_item_spawner.gd"

## Editor-placeable loose goods use the existing durable item slots at runtime.
## The preview never survives into gameplay: collecting the item leaves no fake
## duplicate mesh or collider. Facility authoring stamps the inherited surface_id.
@export var furniture_type := FurnitureRules.Type.DECOR
@export var visual_scene: PackedScene:
	set(value):
		visual_scene = value
		_refresh_preview()
@export var visual_transform := Transform3D.IDENTITY:
	set(value):
		visual_transform = value
		_refresh_preview()

var _preview: Node3D

func _ready() -> void:
	if Engine.is_editor_hint():
		_refresh_preview()
	else:
		super._ready()

func _refresh_preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if is_instance_valid(_preview):
		remove_child(_preview)
		_preview.queue_free()
	_preview = null
	if visual_scene == null:
		return
	_preview = visual_scene.instantiate() as Node3D
	if _preview != null:
		_preview.transform = visual_transform
		add_child(_preview)
