@tool
extends RefCounted

## Shared click-to-place engine for world_authoring concept tools.
## begin_scene()/begin_marker() spawn a transient preview that follows the
## terrain under the mouse in the 3D viewport; left-click commits (the
## callback receives the world transform), right-click or Escape cancels,
## R yaws the preview 90 degrees. The preview is added to the edited scene
## with no owner, so it can never be saved into the scene file.

const PLACEMENT_SOLVER := preload("res://features/settlements/bridge/building_placement_solver.gd")
const RAY_LENGTH_METERS := 4000.0

var _plugin: EditorPlugin
var _preview: Node3D
var _on_commit: Callable
var _on_cancel: Callable
var _has_terrain_hit := false
var _terrain: Node


func _init(plugin: EditorPlugin) -> void:
	_plugin = plugin


func is_active() -> bool:
	return _preview != null and is_instance_valid(_preview)


func begin_scene(preview_scene: PackedScene, on_commit: Callable, on_cancel := Callable()) -> bool:
	if preview_scene == null:
		return false
	var preview := preview_scene.instantiate() as Node3D
	if preview == null:
		return false
	return _begin(preview, on_commit, on_cancel)


## Disc marker preview for towns/markers that have no natural mesh of their own.
func begin_marker(radius: float, color: Color, on_commit: Callable, on_cancel := Callable()) -> bool:
	var preview := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.06
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material = material
	preview.mesh = disc
	return _begin(preview, on_commit, on_cancel)


func cancel() -> void:
	var had_preview := is_active()
	_free_preview()
	if had_preview and _on_cancel.is_valid():
		_on_cancel.call()


func handle_3d_input(camera: Camera3D, event: InputEvent) -> int:
	if not is_active() or camera == null:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseMotion:
		_update_preview_position(camera, (event as InputEventMouseMotion).position)
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if not mouse_button.pressed:
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			# Resolve against this click's position too — the commit click can
			# arrive without a preceding motion event.
			_update_preview_position(camera, mouse_button.position)
			if _has_terrain_hit:
				_commit()
			# Consume hitless clicks as well: letting them through changes the
			# editor selection and silently derails the placement session.
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if mouse_button.button_index == MOUSE_BUTTON_RIGHT:
			cancel()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventKey and (event as InputEventKey).pressed:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE:
			cancel()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if key.keycode == KEY_R:
			_preview.rotate_y(PI * 0.5)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _begin(preview: Node3D, on_commit: Callable, on_cancel: Callable) -> bool:
	cancel()
	var root := _plugin.get_editor_interface().get_edited_scene_root() as Node3D
	if root == null:
		preview.free()
		return false
	_disable_colliders(preview)
	preview.visible = false
	# Owner intentionally stays null: the preview is editor-transient and
	# must never pack into the scene file.
	root.add_child(preview)
	_preview = preview
	_on_commit = on_commit
	_on_cancel = on_cancel
	_has_terrain_hit = false
	return true


func _commit() -> void:
	var world_transform := _preview.global_transform
	_free_preview()
	if _on_commit.is_valid():
		_on_commit.call(world_transform)


func _update_preview_position(camera: Camera3D, mouse_position: Vector2) -> void:
	var from := camera.project_ray_origin(mouse_position)
	var direction := camera.project_ray_normal(mouse_position)
	# Physics first (hits building floors, works at runtime)…
	var space := camera.get_world_3d().direct_space_state
	var hit := PLACEMENT_SOLVER.terrain_ray(space, from, from + direction * RAY_LENGTH_METERS)
	if not hit.is_empty():
		_set_preview_position(hit["position"])
		return
	# …then Terrain3D's GPU intersection: terrain has NO physics collision in
	# the editor, so this is the path editor picking actually takes (same as
	# Terrain3D's own tools).
	var terrain := _find_terrain()
	if terrain != null:
		var point: Vector3 = terrain.call("get_intersection", from, direction, true)
		if point.z < 3.4e38 and not is_nan(point.y):
			_set_preview_position(point)
			return
	_preview.visible = false
	_has_terrain_hit = false


func _set_preview_position(world_position: Vector3) -> void:
	_preview.global_position = world_position
	_preview.visible = true
	_has_terrain_hit = true


func _find_terrain() -> Node:
	if _terrain != null and is_instance_valid(_terrain):
		return _terrain
	_terrain = find_terrain_in(_plugin.get_editor_interface().get_edited_scene_root())
	return _terrain


static func find_terrain_in(node: Node) -> Node:
	if node == null:
		return null
	if node.is_class("Terrain3D"):
		return node
	for child in node.get_children():
		var found := find_terrain_in(child)
		if found != null:
			return found
	return null


func _disable_colliders(root: Node) -> void:
	if root is CollisionObject3D:
		(root as CollisionObject3D).collision_layer = 0
		(root as CollisionObject3D).collision_mask = 0
	if root is CollisionShape3D:
		(root as CollisionShape3D).disabled = true
	for child in root.get_children():
		_disable_colliders(child)


func _free_preview() -> void:
	if _preview != null and is_instance_valid(_preview):
		_preview.get_parent().remove_child(_preview)
		_preview.free()
	_preview = null
	_terrain = null
	_has_terrain_hit = false
