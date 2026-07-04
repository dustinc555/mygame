extends Node3D

## Animation browser workbench: every clip from both UAL packs in one searchable
## list, played on demand on a single avatar. Unlike the showcase level, nothing
## is filtered out — this is the "find the clip I need" tool.
## Run: godot res://tools/animation_browser/animation_browser.tscn

const UAL1_PRO_SCENE = preload("res://assets/vendor/quaternius/universal_animation_library_1_pro/UAL1_Pro.glb")
const UAL2_SOURCE_SCENE = preload("res://assets/vendor/quaternius/universal_animation_library_2/UAL2.glb")
const AVATAR_SCENE = preload("res://assets/vendor/quaternius/universal_base_characters/base_characters/Superhero_Male_FullBody.gltf")
const BODY_PROJECTION_SCRIPT = preload("res://features/actors/projection/humanoid/humanoid_body_projection.gd")

const ORBIT_SENSITIVITY := 0.012
const ZOOM_STEP := 0.3
const ZOOM_MIN := 1.4
const ZOOM_MAX := 8.0

## clip entries: {name: String, pack: String, animation: Animation}
var _clips: Array[Dictionary] = []
## clip name -> Array[String] of HumanoidBodyProjection const names referencing it
var _wired_by_clip := {}
var _filtered_indices: Array[int] = []

var _avatar: Node3D
var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _camera: Camera3D

var _search: LineEdit
var _list: ItemList
var _info: Label


func _ready() -> void:
	_build_stage()
	_build_avatar()
	_collect_clips()
	_build_library()
	_collect_wired_clip_names()
	_build_ui()
	_refresh_list()


## Drag anywhere in the viewport (left or right button) to spin the avatar;
## scroll to zoom. UI panel consumes its own input, so list clicks don't spin.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if motion.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT):
			_avatar.rotation.y -= motion.relative.x * ORBIT_SENSITIVITY
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var button := (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_WHEEL_UP or button == MOUSE_BUTTON_WHEEL_DOWN:
			var direction := -1.0 if button == MOUSE_BUTTON_WHEEL_UP else 1.0
			var forward := (_camera.position - Vector3(0.0, 1.0, 0.0)).normalized()
			var distance := clampf(_camera.position.distance_to(Vector3(0.0, 1.0, 0.0)) + direction * ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			_camera.position = Vector3(0.0, 1.0, 0.0) + forward * distance


## Filter: every whitespace-separated token must appear somewhere in the clip
## name; underscores count as word breaks, so "pick up" finds PickUp_Kneeling
## and "kneel fix" finds Fixing_Kneeling.
func _matches_query(clip_name: String, query: String) -> bool:
	var haystack := clip_name.to_lower().replace("_", " ")
	for token in query.to_lower().split(" ", false):
		if not haystack.contains(token):
			return false
	return true


func _refresh_list() -> void:
	var query := _search.text if _search != null else ""
	_list.clear()
	_filtered_indices.clear()
	for clip_index in range(_clips.size()):
		var clip: Dictionary = _clips[clip_index]
		var clip_name := String(clip["name"])
		if not query.strip_edges().is_empty() and not _matches_query(clip_name, query):
			continue
		var wired_marker := "  ●" if _wired_by_clip.has(clip_name) else ""
		_list.add_item("%s   [%s]%s" % [clip_name, String(clip["pack"]), wired_marker])
		_filtered_indices.append(clip_index)
	_info.text = "%d / %d clips%s" % [_filtered_indices.size(), _clips.size(), "" if query.is_empty() else "  (query: %s)" % query]


func _on_search_changed(_new_text: String) -> void:
	_refresh_list()


func _on_clip_selected(list_index: int) -> void:
	if list_index < 0 or list_index >= _filtered_indices.size():
		return
	var clip: Dictionary = _clips[_filtered_indices[list_index]]
	_play_clip(clip)
	_show_clip_info(clip)


## The whole library is retargeted once up front. Mutating an AnimationLibrary
## while a crossfade is processing invalidates the mixer's blend bookkeeping
## (make_animation_instance: !has_animation), so clicks must be pure play().
func _build_library() -> void:
	var library: AnimationLibrary = _player.get_animation_library("")
	var target_hips := AnimationPositionScale.hips_height(_skeleton)
	for clip in _clips:
		var source_hips := float(clip["source_hips"])
		var position_scale := target_hips / source_hips if source_hips > 0.001 and target_hips > 0.001 else 1.0
		var retargeted := AnimationRetargetLib.retarget_animation(clip["animation"] as Animation, _avatar, _skeleton, true, position_scale)
		if retargeted != null:
			library.add_animation(String(clip["name"]), retargeted)


func _play_clip(clip: Dictionary) -> void:
	var clip_name := String(clip["name"])
	if not _player.has_animation(clip_name):
		_info.text = "%s: no retargetable bone tracks" % clip_name
		return
	_player.play(clip_name, 0.15)


func _show_clip_info(clip: Dictionary) -> void:
	var clip_name := String(clip["name"])
	var animation := clip["animation"] as Animation
	var lines := [
		clip_name,
		"pack: %s" % String(clip["pack"]),
		"length: %.2fs" % animation.length,
	]
	if _wired_by_clip.has(clip_name):
		lines.append("wired in game: %s" % ", ".join(_wired_by_clip[clip_name]))
	else:
		lines.append("wired in game: no")
	_info.text = "\n".join(lines)


func _collect_clips() -> void:
	var packs := [
		{"label": "UAL1 Pro", "scene": UAL1_PRO_SCENE},
		{"label": "UAL2", "scene": UAL2_SOURCE_SCENE},
	]
	for pack in packs:
		var source_root: Node = (pack["scene"] as PackedScene).instantiate()
		var source_player := AnimationRetargetLib.find_animation_player(source_root)
		if source_player == null:
			source_root.free()
			continue
		var source_hips := AnimationPositionScale.hips_height(AnimationRetargetLib.find_skeleton(source_root))
		for animation_name in source_player.get_animation_list():
			var clip_name := String(animation_name)
			if clip_name == "A_TPose":
				continue
			_clips.append({
				"name": clip_name,
				"pack": String(pack["label"]),
				"animation": source_player.get_animation(animation_name),
				"source_hips": source_hips,
			})
		source_root.free()
	_clips.sort_custom(func(a, b): return String(a["name"]).naturalnocasecmp_to(String(b["name"])) < 0)


## Reverse-maps HumanoidBodyProjection's animation-name constants so the list
## can mark clips the game already uses (and name the constant).
func _collect_wired_clip_names() -> void:
	var constant_map: Dictionary = (BODY_PROJECTION_SCRIPT as GDScript).get_script_constant_map()
	for constant_name in constant_map:
		var value = constant_map[constant_name]
		var names: Array = []
		if value is String:
			names = [value]
		elif value is Array:
			names = value
		for entry in names:
			if not (entry is String) or String(entry).is_empty():
				continue
			var clip_name := String(entry)
			if not _wired_by_clip.has(clip_name):
				_wired_by_clip[clip_name] = []
			(_wired_by_clip[clip_name] as Array).append(String(constant_name))


func _build_stage() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48.0, 32.0, 0.0)
	sun.light_energy = 1.2
	add_child(sun)

	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(12.0, 12.0)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.24, 0.23, 0.21, 1.0)
	floor_material.roughness = 0.95
	floor_mesh.material_override = floor_material
	add_child(floor_mesh)

	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.position = Vector3(0.0, 1.5, 3.2)
	_camera.current = true
	add_child(_camera)
	_camera.look_at_from_position(_camera.position, Vector3(0.0, 1.0, 0.0))

	var environment := WorldEnvironment.new()
	environment.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.13, 0.15, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.66, 1.0)
	env.ambient_light_energy = 0.7
	environment.environment = env
	add_child(environment)


func _build_avatar() -> void:
	_avatar = AVATAR_SCENE.instantiate() as Node3D
	_avatar.name = "Avatar"
	add_child(_avatar)
	_skeleton = AnimationRetargetLib.find_skeleton(_avatar)
	_player = AnimationPlayer.new()
	_player.name = "BrowserAnimationPlayer"
	_player.root_node = NodePath("..")
	_avatar.add_child(_player)
	_player.add_animation_library("", AnimationLibrary.new())


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "BrowserUI"
	add_child(layer)

	var panel := PanelContainer.new()
	panel.name = "BrowserPanel"
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 12.0
	panel.offset_top = 12.0
	panel.offset_bottom = -12.0
	panel.custom_minimum_size = Vector2(430.0, 0.0)
	layer.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var title := Label.new()
	title.text = "Animation Browser — %s + %s (all clips, ● = wired in game)" % ["UAL1 Pro", "UAL2"]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title)

	_search = LineEdit.new()
	_search.placeholder_text = "Search clips (e.g. kneel, pick, fix)..."
	_search.text_changed.connect(_on_search_changed)
	column.add_child(_search)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_clip_selected)
	column.add_child(_list)

	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(0.0, 96.0)
	column.add_child(_info)

	_search.grab_focus()
