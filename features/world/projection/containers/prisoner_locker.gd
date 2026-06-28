@tool
extends "res://features/world/projection/containers/world_container.gd"

class_name PrisonerLocker

@export_range(0, 100, 1) var lock_difficulty := 65


func _enter_tree() -> void:
	if Engine.is_editor_hint() and not _can_editor_modify_preview():
		return
	super._enter_tree()


func _ready() -> void:
	if Engine.is_editor_hint() and not _can_editor_modify_preview():
		return
	super._ready()
	display_name = "Prisoner Locker" if display_name.is_empty() or display_name == "Container" else display_name
	is_locked = true


func attempt_unlock(actor: HumanoidCharacter) -> bool:
	if not is_locked:
		return true
	_report_lockpicking(actor)
	var skill := actor.get_skill_level(SkillRules.SUBTERFUGE_LOCKPICKING) if actor != null and actor.has_method("get_skill_level") else 0
	if skill < lock_difficulty:
		if actor != null and actor.has_method("show_world_speech"):
			actor.show_world_speech("Too hard to pick.", 2.5)
		return false
	is_locked = false
	if actor != null and actor.has_method("show_world_speech"):
		actor.show_world_speech("Unlocked.", 2.0)
	return true


func _report_lockpicking(actor: HumanoidCharacter) -> void:
	if actor == null:
		return
	var tree := get_tree()
	if tree == null:
		return
	for controller in tree.get_nodes_in_group("law_order_controller"):
		if controller != null and controller.has_method("report_lockpicking_if_witnessed"):
			controller.call("report_lockpicking_if_witnessed", actor, self)
			return


func _can_editor_modify_preview() -> bool:
	if not Engine.is_editor_hint():
		return true
	var tree := get_tree()
	var edited_root := tree.edited_scene_root if tree != null else null
	return edited_root == self
