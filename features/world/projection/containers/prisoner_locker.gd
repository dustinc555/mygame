@tool
extends "res://features/world/projection/containers/world_container.gd"

class_name PrisonerLocker


func _enter_tree() -> void:
	if Engine.is_editor_hint() and not _can_editor_modify_preview():
		return
	super._enter_tree()


func _ready() -> void:
	if Engine.is_editor_hint() and not _can_editor_modify_preview():
		return
	super._ready()
	display_name = "Prisoner Locker" if display_name.is_empty() or display_name == "Container" else display_name



# This furniture has one authored model. The generic container visual_scene
# swap must never replace it at startup.
func _rebuild_visual() -> void:
	pass


func _can_editor_modify_preview() -> bool:
	if not Engine.is_editor_hint():
		return true
	var tree := get_tree()
	var edited_root := tree.edited_scene_root if tree != null else null
	return edited_root == self
