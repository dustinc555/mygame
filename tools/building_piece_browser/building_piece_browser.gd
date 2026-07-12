extends Node3D

## Raw Medieval Village kit browser. It is intentionally separate from the
## WorldBuilding plugin: this is for inspecting every source model and seeing
## which ones still need proper wrapper scenes, collision, snap points, and a
## catalog definition. Run: godot res://tools/building_piece_browser/building_piece_browser.tscn

const PACK_DIR := "res://assets/vendor/quaternius/medieval_village_megakit/gltf_godot"
const DEFINITIONS_DIR := "res://features/world/resources/building_pieces/quaternius"
const ORBIT_SENSITIVITY := 0.012
const ZOOM_FACTOR := 1.12

var _models: Array[Dictionary] = []
var _filtered_indices: Array[int] = []
var _wrapped_by_path := {}
var _stage_model: Node3D
var _camera: Camera3D
var _camera_distance := 4.0
var _camera_focus := Vector3(0.0, 0.8, 0.0)
var _search: LineEdit
var _list: ItemList
var _info: Label


func _ready() -> void:
	_build_stage()
	_collect_models()
	_collect_wrappers()
	_build_ui()
	_refresh_list()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _stage_model != null and motion.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT):
			_stage_model.rotation.y -= motion.relative.x * ORBIT_SENSITIVITY
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var button := (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_WHEEL_UP:
			_camera_distance = maxf(_camera_distance / ZOOM_FACTOR, 0.4)
			_update_camera()
		elif button == MOUSE_BUTTON_WHEEL_DOWN:
			_camera_distance = minf(_camera_distance * ZOOM_FACTOR, 120.0)
			_update_camera()


func _matches_query(model: Dictionary, query: String) -> bool:
	var haystack := (str(model["name"]) + " " + str(model["category"])).to_lower().replace("_", " ")
	for token in query.to_lower().split(" ", false):
		if not haystack.contains(token):
			return false
	return true


func _refresh_list() -> void:
	var query := _search.text if _search != null else ""
	_list.clear()
	_filtered_indices.clear()
	for model_index in range(_models.size()):
		var model: Dictionary = _models[model_index]
		if not query.strip_edges().is_empty() and not _matches_query(model, query):
			continue
		var wrapped_marker := "  ●" if _wrapped_by_path.has(str(model["path"])) else ""
		_list.add_item("%s   [%s]%s" % [model["name"], model["category"], wrapped_marker])
		_filtered_indices.append(model_index)
	_info.text = "%d / %d source models%s" % [_filtered_indices.size(), _models.size(), "" if query.is_empty() else "  (query: %s)" % query]


func _on_model_selected(list_index: int) -> void:
	if list_index < 0 or list_index >= _filtered_indices.size():
		return
	_show_model(_models[_filtered_indices[list_index]])


func _show_model(model: Dictionary) -> void:
	if _stage_model != null and is_instance_valid(_stage_model):
		_stage_model.queue_free()
		_stage_model = null
	var packed := load(str(model["path"])) as PackedScene
	if packed == null:
		_info.text = "%s: failed to load" % model["name"]
		return
	_stage_model = packed.instantiate() as Node3D
	add_child(_stage_model)
	var bounds := _model_bounds(_stage_model)
	_camera_distance = maxf(bounds.size.length() * 1.1 + 0.8, 1.5)
	_camera_focus = Vector3(0.0, bounds.position.y + bounds.size.y * 0.5, 0.0)
	_update_camera()
	var path := str(model["path"])
	var status := "proper wrapper: %s" % _wrapped_by_path[path] if _wrapped_by_path.has(path) else "proper wrapper: none"
	_info.text = "%s\ncategory: %s\nsize: %.2f x %.2f x %.2f m\n%s\npath: %s" % [model["name"], model["category"], bounds.size.x, bounds.size.y, bounds.size.z, status, path]


func _update_camera() -> void:
	var direction := Vector3(0.55, 0.42, 1.0).normalized()
	_camera.position = _camera_focus + direction * _camera_distance
	_camera.look_at(_camera_focus, Vector3.UP)


func _collect_models() -> void:
	for file_name in DirAccess.get_files_at(PACK_DIR):
		if file_name.get_extension().to_lower() != "gltf" or file_name == "SampleScene_Ground.gltf":
			continue
		_models.append({
			"name": file_name.get_basename(),
			"category": _category_for(file_name),
			"path": PACK_DIR.path_join(file_name),
		})
	_models.sort_custom(func(a, b): return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)


func _collect_wrappers() -> void:
	for definition_path in _definition_paths(DEFINITIONS_DIR):
		var text := FileAccess.get_file_as_string(definition_path)
		for model in _models:
			if text.contains(str(model["path"])):
				_wrapped_by_path[model["path"]] = definition_path


func _definition_paths(directory_path: String) -> Array[String]:
	var paths: Array[String] = []
	for file_name in DirAccess.get_files_at(directory_path):
		if file_name.get_extension() != "tres" or file_name.contains("catalog"):
			continue
		paths.append(directory_path.path_join(file_name))
	for child_directory in DirAccess.get_directories_at(directory_path):
		paths.append_array(_definition_paths(directory_path.path_join(child_directory)))
	return paths


func _category_for(file_name: String) -> String:
	var stem := file_name.get_basename().to_lower()
	for category_name in ["wall", "roof", "floor", "corner", "overhang", "stairs", "stair", "window", "door", "doorframe", "shutters", "balcony", "holecover", "prop"]:
		if stem.begins_with(category_name):
			return "stairs" if category_name == "stair" else category_name
	return "other"


func _model_bounds(root: Node3D) -> AABB:
	var state := {"has": false, "aabb": AABB()}
	_merge_bounds(root, root, state)
	return state["aabb"] if bool(state["has"]) else AABB(Vector3.ZERO, Vector3.ONE)


func _merge_bounds(root_node: Node3D, node: Node, state: Dictionary) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_instance := node as MeshInstance3D
		var to_root := root_node.global_transform.affine_inverse() * mesh_instance.global_transform
		var local := mesh_instance.mesh.get_aabb()
		for x in [0.0, 1.0]:
			for y in [0.0, 1.0]:
				for z in [0.0, 1.0]:
					var corner := to_root * (local.position + Vector3(local.size.x * x, local.size.y * y, local.size.z * z))
					state["aabb"] = (state["aabb"] as AABB).expand(corner) if bool(state["has"]) else AABB(corner, Vector3.ZERO)
					state["has"] = true
	for child in node.get_children():
		_merge_bounds(root_node, child, state)


func _build_stage() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, 32.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)
	_camera = Camera3D.new()
	_camera.current = true
	add_child(_camera)
	_update_camera()
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.13, 0.15, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.8
	environment.environment = env
	add_child(environment)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.anchor_bottom = 1.0
	panel.offset_left = 12.0
	panel.offset_top = 12.0
	panel.offset_bottom = -12.0
	panel.custom_minimum_size = Vector2(460.0, 0.0)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var title := Label.new()
	title.text = "Medieval Village Piece Browser - raw pack sources (● = proper modular wrapper)"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title)
	_search = LineEdit.new()
	_search.placeholder_text = "Search raw pieces (e.g. roof modular 6, wall plaster)..."
	_search.text_changed.connect(func(_text: String): _refresh_list())
	column.add_child(_search)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_model_selected)
	column.add_child(_list)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(0.0, 130.0)
	column.add_child(_info)
	_search.grab_focus()
