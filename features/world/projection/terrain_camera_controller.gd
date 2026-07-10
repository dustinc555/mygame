extends Node

class_name TerrainCameraController

## Explicitly assigns the gameplay camera to every Terrain3D in the scene.
##
## At runtime Terrain3D auto-grabs `get_viewport().get_camera_3d()` on its
## first physics frame; if no camera is current at that instant it pushes an
## error and permanently stops its own physics processing (clipmap no longer
## follows the camera). Explicit assignment via `Terrain3D.set_camera()` is
## the addon-documented remedy and removes the timing dependency entirely.

const SERVICE_ID := &"terrain_camera"

var root_scene: Node
var _camera: Camera3D
var _terrains: Array[Node] = []
var _initialized := false


func initialize(context: BootstrapContext) -> void:
	root_scene = context.root_scene
	if is_inside_tree():
		_do_initialize()


func _ready() -> void:
	add_to_group("terrain_camera_controller")
	if root_scene != null:
		_do_initialize()


func _do_initialize() -> void:
	if _initialized or root_scene == null:
		return
	_camera = root_scene.get_node_or_null("CameraRig/CameraPivot/Camera3D") as Camera3D
	_terrains = _find_terrains(root_scene)
	_initialized = true
	_assign_camera()


func _assign_camera() -> void:
	if _camera == null or _terrains.is_empty():
		return
	if not _camera.current:
		_camera.make_current()
	for terrain in _terrains:
		if not is_instance_valid(terrain):
			continue
		terrain.set_camera(_camera)
		# Recover terrains that already failed their auto-grab and shut down.
		terrain.set_physics_process(true)


## Terrain surface height under a world position; NAN where no terrain covers.
func get_terrain_height(world_position: Vector3) -> float:
	for terrain in _terrains:
		if not is_instance_valid(terrain):
			continue
		var data = terrain.get("data")
		if data == null:
			continue
		var height := float(data.get_height(world_position))
		if not is_nan(height):
			return height
	return NAN


func _find_terrains(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	if node.is_class("Terrain3D"):
		found.append(node)
	for child in node.get_children():
		found.append_array(_find_terrains(child))
	return found
