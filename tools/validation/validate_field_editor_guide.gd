@tool
extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_expect(Engine.is_editor_hint(), "validator must run with editor hint enabled")
	var scene := load("res://features/settlements/bridge/settlement_field.tscn") as PackedScene
	var field := scene.instantiate() if scene != null else null
	_expect(field != null, "field scene must instantiate")
	if field == null:
		_finish()
		return
	root.add_child(field)
	await process_frame
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
	if guide is MultiMeshInstance3D:
		_expect(guide.multimesh.instance_count == 8, "editor boundary must refresh when the footprint changes")
	root.remove_child(field)
	field.free()
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("FIELD_EDITOR_GUIDE_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("FIELD_EDITOR_GUIDE_FAILED count=%d" % _failures.size())
	quit(1)
