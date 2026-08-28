@tool
extends RefCounted

## Shared placement engine for world_authoring concept tools, matching the
## in-game debug spawner's feel: the preview follows the terrain under the
## mouse; left-press anchors it, dragging while held rotates it to face the
## cursor, the mouse wheel raises/lowers it, and releasing commits (the
## callback receives the world transform). Right-click or Escape cancels;
## R yaws 90 degrees. The preview is added to the edited scene with no
## owner, so it can never be saved into the scene file.

const PLACEMENT_SOLVER := preload("res://features/settlements/bridge/building_placement_solver.gd")
const RAY_LENGTH_METERS := 4000.0
const ROTATE_DEAD_ZONE_METERS := 0.6
const HEIGHT_STEP_METERS := 0.25
const HEIGHT_MIN_METERS := -1.0
const HEIGHT_MAX_METERS := 4.0
## Terrain3D's GPU intersection renders and reads back a frame, stalling the
## pipeline. Editor terrain has no physics collision, so placement takes that
## path on EVERY mouse-motion event. Sample height at this interval instead and
## slide along the last known height in between — the preview still tracks the
## cursor every frame, it just re-reads the ground ~12 times a second.
const TERRAIN_QUERY_INTERVAL_MSEC := 80

var _plugin: EditorPlugin
var _preview: Node3D
var _on_commit: Callable
var _on_cancel: Callable
var _has_terrain_hit := false
var _terrain: Node
var _anchored := false
var _anchor := Vector3.ZERO
var _ground := Vector3.ZERO
var _yaw := 0.0
var _y_offset := 0.0
var _last_terrain_query_msec := -TERRAIN_QUERY_INTERVAL_MSEC
var _last_terrain_point := Vector3.ZERO
var _has_last_terrain_point := false


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
		if _anchored:
			_rotate_toward_cursor(camera, (event as InputEventMouseMotion).position)
			# Consume drags while anchored so the editor doesn't box-select.
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		_update_preview_position(camera, (event as InputEventMouseMotion).position)
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			if mouse_button.pressed:
				# Resolve against this click's position too — the press can
				# arrive without a preceding motion event.
				_update_preview_position(camera, mouse_button.position)
				if _has_terrain_hit:
					_anchored = true
					_anchor = _ground
			elif _anchored:
				_commit()
			# Consume hitless clicks as well: letting them through changes the
			# editor selection and silently derails the placement session.
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if mouse_button.button_index == MOUSE_BUTTON_RIGHT and mouse_button.pressed:
			cancel()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventKey and (event as InputEventKey).pressed:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE:
			cancel()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if key.keycode == KEY_R:
			_yaw += PI * 0.5
			_apply_preview_transform()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


## Mouse wheel raise/lower, intercepted at _input level by the plugin: the
## 3D viewport applies wheel zoom without consulting AFTER_GUI_INPUT_STOP,
## so consuming wheel inside forward_3d_gui_input still zooms the camera.
## Foundations exist so a building can sit above uneven terrain instead of
## clipping into it.
func handle_global_input(event: InputEvent) -> bool:
	if not is_active():
		return false
	var mouse_button := event as InputEventMouseButton
	if mouse_button == null or not mouse_button.pressed:
		return false
	if not mouse_button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		return false
	var step := HEIGHT_STEP_METERS if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP else -HEIGHT_STEP_METERS
	_y_offset = clampf(_y_offset + step, HEIGHT_MIN_METERS, HEIGHT_MAX_METERS)
	_apply_preview_transform()
	return true


## While anchored, the preview yaws to face the terrain point under the
## cursor — same drag-to-aim as the in-game debug building spawner.
func _rotate_toward_cursor(camera: Camera3D, mouse_position: Vector2) -> void:
	var toward := _terrain_point(camera, mouse_position)
	if toward == null:
		return
	var flat: Vector3 = (toward as Vector3) - _anchor
	if Vector2(flat.x, flat.z).length() > ROTATE_DEAD_ZONE_METERS:
		_yaw = atan2(flat.x, flat.z)
		_apply_preview_transform()


func _begin(preview: Node3D, on_commit: Callable, on_cancel: Callable) -> bool:
	cancel()
	_reset_terrain_cache()
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
	_anchored = false
	_yaw = 0.0
	_y_offset = 0.0
	return true


func _commit() -> void:
	var world_transform := _preview.global_transform
	_free_preview()
	if _on_commit.is_valid():
		_on_commit.call(world_transform)


func _update_preview_position(camera: Camera3D, mouse_position: Vector2) -> void:
	var point := _terrain_point(camera, mouse_position)
	if point == null:
		_preview.visible = false
		_has_terrain_hit = false
		return
	_ground = point as Vector3
	_has_terrain_hit = true
	_apply_preview_transform()


## Terrain point under a screen position: physics first (hits building
## floors, works at runtime), then Terrain3D's GPU intersection — editor
## terrain has NO physics collision, so that's the path editor picking
## actually takes (same as Terrain3D's own tools). Returns Vector3 or null.
func _terrain_point(camera: Camera3D, mouse_position: Vector2) -> Variant:
	var from := camera.project_ray_origin(mouse_position)
	var direction := camera.project_ray_normal(mouse_position)
	var space := camera.get_world_3d().direct_space_state
	var hit := PLACEMENT_SOLVER.terrain_ray(space, from, from + direction * RAY_LENGTH_METERS)
	if not hit.is_empty():
		# Physics hit: cheap and exact, so it is never throttled.
		_remember_terrain_point(hit["position"])
		return hit["position"]
	var now := Time.get_ticks_msec()
	if _has_last_terrain_point and now - _last_terrain_query_msec < TERRAIN_QUERY_INTERVAL_MSEC:
		var slid := _slide_along_last_height(from, direction)
		if slid != null:
			return slid
	var terrain := _find_terrain()
	if terrain != null:
		_last_terrain_query_msec = now
		var point: Vector3 = terrain.call("get_intersection", from, direction, true)
		if point.z < 3.4e38 and not is_nan(point.y):
			_remember_terrain_point(point)
			return point
	return _last_terrain_point if _has_last_terrain_point else null


func _remember_terrain_point(point: Vector3) -> void:
	_last_terrain_point = point
	_has_last_terrain_point = true


## Between ground samples the cursor still needs to move the preview, so the
## ray is intersected with a horizontal plane at the last sampled height.
func _slide_along_last_height(from: Vector3, direction: Vector3) -> Variant:
	return Plane(Vector3.UP, _last_terrain_point.y).intersects_ray(from, direction)


func _apply_preview_transform() -> void:
	if not _has_terrain_hit:
		return
	var base: Vector3 = _anchor if _anchored else _ground
	_preview.global_transform = Transform3D(Basis(Vector3.UP, _yaw), base + Vector3.UP * _y_offset)
	_preview.visible = true


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


func _reset_terrain_cache() -> void:
	_has_last_terrain_point = false
	_last_terrain_query_msec = -TERRAIN_QUERY_INTERVAL_MSEC


func _free_preview() -> void:
	if _preview != null and is_instance_valid(_preview):
		_preview.get_parent().remove_child(_preview)
		_preview.free()
	_preview = null
	_terrain = null
	_has_terrain_hit = false
	_anchored = false
	_yaw = 0.0
	_y_offset = 0.0
