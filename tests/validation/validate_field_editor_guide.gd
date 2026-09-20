@tool
extends Node

var _failures: Array[String] = []


func _ready() -> void:
	# The root suite isolates addon UIs before native editor startup. Changing
	# the plugin setting here would be too late to prevent their initialization.
	_expect(ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray()) == PackedStringArray(), "geometry fixture must start with unrelated editor plugins disabled")
	EditorInterface.get_editor_settings().set_setting("interface/scene_tabs/restore_scenes_on_load", false)
	call_deferred("_run")


func _run() -> void:
	# Let the native editor finish startup before testing tool geometry.
	await get_tree().process_frame
	await get_tree().process_frame
	var filesystem := EditorInterface.get_resource_filesystem()
	var deadline := Time.get_ticks_msec() + 60000
	while filesystem.is_scanning() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(not filesystem.is_scanning(), "editor filesystem must finish initializing")
	_expect(Engine.is_editor_hint(), "validator must run with editor hint enabled")
	var scene := load("res://features/settlements/bridge/settlement_field.tscn") as PackedScene
	var field := scene.instantiate() if scene != null else null
	_expect(field != null, "field scene must instantiate")
	if field == null:
		_finish()
		return
	add_child(field)
	await get_tree().process_frame
	var guide: Node = field.call("get_editor_guide") if field.has_method("get_editor_guide") else null
	_expect(guide is MultiMeshInstance3D, "field must create its always-visible editor boundary")
	_expect(guide != null and guide.owner == null, "editor boundary must remain ownerless and unsaved")
	_expect(field.get_child_count(false) == 0, "editor boundary must not create a scene-tree collapse arrow")
	if guide is MultiMeshInstance3D:
		_expect(guide.visible, "editor boundary must be visible without selecting the field")
		_expect(guide.multimesh != null and guide.multimesh.instance_count == 20, "6x4 field must draw its 20 perimeter edges")
	field.set("dimensions", Vector2i(2, 2))
	field.set("cell_coordinates", PackedVector2Array())
	guide = field.call("get_editor_guide") if field.has_method("get_editor_guide") else null
	_expect(guide is MultiMeshInstance3D, "footprint edit must retain the editor guide")
	if guide is MultiMeshInstance3D:
		_expect(guide.multimesh.instance_count == 8, "editor boundary must refresh when the footprint changes")
	remove_child(field)
	field.free()
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("FIELD_EDITOR_GUIDE_OK")
	else:
		for failure in _failures:
			push_error(failure)
		print("FIELD_EDITOR_GUIDE_FAILED count=%d" % _failures.size())
	# Use the editor's normal close path: it stops resource preview workers
	# and unloads editor state before SceneTree shutdown. Do not manually
	# free EditorNode while its pending callbacks can still run.
	get_tree().root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	if not _failures.is_empty():
		get_tree().quit(1)
