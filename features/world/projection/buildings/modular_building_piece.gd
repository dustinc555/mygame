@tool
extends Node3D

class_name ModularBuildingPiece

const SNAP_MARKER_SCRIPT := preload("res://features/world/projection/buildings/modular_building_snap_marker.gd")

@export var piece_id := ""
@export var display_name := ""
@export_enum("floor", "wall", "wall_door", "wall_window", "window", "door", "corner", "roof", "roof_front", "stairs") var category := "wall"
@export var grid_cell_size_meters := 2.0
@export var grid_size_cells := Vector3i.ONE
@export var bounds_size_meters := Vector3.ZERO
@export var auto_snap_enabled := true
@export_range(0, 16, 1) var building_level := 0
@export var hide_with_camera := true
@export_enum("auto", "none", "front", "right", "back", "left", "roof") var occluder_side := "auto"
@export var disable_model_collision := false
@export var editor_show_snap_markers := true:
	set(value):
		editor_show_snap_markers = value
		_sync_snap_marker_visibility()


func _ready() -> void:
	add_to_group("modular_building_piece")
	# Applies in editor too so editor and headless navigation bakes see the same
	# collision (e.g. door art frame off, GeneratedDoorWall on). Authoring snapping
	# uses snap markers, not model collision, so disabling it in-editor is safe.
	if disable_model_collision:
		_set_model_collision_enabled(false)
	_sync_snap_marker_visibility()


func get_piece_id() -> String:
	return piece_id if not piece_id.is_empty() else name


func get_building_level() -> int:
	return max(0, building_level)


func get_occluder_side() -> String:
	return occluder_side


func should_hide_with_camera() -> bool:
	return hide_with_camera and occluder_side != "none"


func get_snap_markers() -> Array:
	var result: Array = []
	_collect_snap_markers(self, result)
	return result


func _sync_snap_marker_visibility() -> void:
	if not is_inside_tree():
		return
	for marker in get_snap_markers():
		marker.editor_show_visual = editor_show_snap_markers


func _collect_snap_markers(node: Node, result: Array) -> void:
	if node.get_script() == SNAP_MARKER_SCRIPT:
		result.append(node)
	for child in node.get_children():
		_collect_snap_markers(child, result)


func _set_model_collision_enabled(enabled: bool) -> void:
	var model := get_node_or_null("Model")
	if model == null:
		return
	_set_collision_enabled_recursive(model, enabled)


func _set_collision_enabled_recursive(node: Node, enabled: bool) -> void:
	if node is CollisionObject3D:
		var collision_object := node as CollisionObject3D
		collision_object.collision_layer = 1 if enabled else 0
		collision_object.collision_mask = 1 if enabled else 0
	elif node is CollisionShape3D:
		(node as CollisionShape3D).disabled = not enabled
	for child in node.get_children():
		_set_collision_enabled_recursive(child, enabled)
