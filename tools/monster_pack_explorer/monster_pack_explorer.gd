extends Control
## Standalone pack inspection with rest-aware Universal Animation Library playback.
const MONSTER_ANIMATIONS := preload("res://tools/monster_pack_explorer/monster_animation_library.gd")
const EQUIPMENT_PREVIEW := preload("res://tools/monster_pack_explorer/monster_equipment_preview.gd")
const PACK_DIR := "res://assets/vendor/quaternius/bestiary_dungeon_monsters/glb"
const ORBIT_SENSITIVITY := 0.008
var monsters: Array[Dictionary] = []
var clips: Array[Dictionary] = []
var model: Node3D
var model_bounds := AABB()
var monster_list: ItemList
var animation_select: OptionButton

var _filtered: Array[int] = []
var _world: Node3D
var _pivot: Node3D
var _camera: Camera3D
var _viewport: SubViewport
var _title: Label
var _info: Label

var _selected_clip := -1
var _yaw := 0.25
var _pitch := 0.12
var _distance := 4.0
var _focus := Vector3(0, 1, 0)

var _animation_library: RefCounted
var equipment_preview: Node

func _ready() -> void:
	_animation_library = MONSTER_ANIMATIONS.new()
	equipment_preview = EQUIPMENT_PREVIEW.new()
	add_child(equipment_preview)
	_build_ui()
	_build_stage()
	for file in DirAccess.get_files_at(PACK_DIR):
		if file.get_extension().to_lower() == "glb":
			var definition: Dictionary = equipment_preview.manifest.get("models", {}).get(file, {})
			# Equipment-only exports contribute gear choices, not another body.
			if not str(definition.get("equipment_variant_of", "")).is_empty(): continue
			monsters.append({"name": str(definition.get("display_name", file.get_basename())), "path": PACK_DIR.path_join(file)})
	monsters.sort_custom(func(a, b): return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	filter_monsters("")
	if not monsters.is_empty():
		monster_list.select(0)
		select_monster(0)
	else:
		_title.text = "No imported monsters found"
		_info.text = "Import the Bestiary GLBs before opening this scene."

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 14)
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	margin.add_child(columns)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 320
	columns.add_child(panel)
	var padding := MarginContainer.new()
	for edge in ["left", "top", "right", "bottom"]:
		padding.add_theme_constant_override("margin_" + edge, 12)
	panel.add_child(padding)
	var sidebar := VBoxContainer.new()
	sidebar.add_theme_constant_override("separation", 10)
	padding.add_child(sidebar)
	var heading := Label.new()
	heading.text = "Monster Pack Explorer"
	heading.add_theme_font_size_override("font_size", 23)
	sidebar.add_child(heading)
	var subtitle := Label.new()
	subtitle.text = "Quaternius · Bestiary"
	sidebar.add_child(subtitle)
	var search := LineEdit.new()
	search.placeholder_text = "Search monsters…"
	search.text_changed.connect(filter_monsters)
	sidebar.add_child(search)
	monster_list = ItemList.new()
	monster_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	monster_list.custom_minimum_size.y = 140
	monster_list.item_selected.connect(func(index): select_monster(_filtered[index]))
	sidebar.add_child(monster_list)
	var animation_label := Label.new()
	animation_label.text = "Animation"
	sidebar.add_child(animation_label)
	animation_select = OptionButton.new()
	animation_select.fit_to_longest_item = false
	animation_select.item_selected.connect(select_clip)
	sidebar.add_child(animation_select)
	var gear_scroll := ScrollContainer.new()
	gear_scroll.custom_minimum_size.y = 180
	gear_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(gear_scroll)
	var gear_panel := VBoxContainer.new()
	gear_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gear_panel.add_theme_constant_override("separation", 6)
	gear_scroll.add_child(gear_panel)
	equipment_preview.setup_panel(gear_panel)

	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size.y = 48
	sidebar.add_child(_info)
	var stage_column := VBoxContainer.new()
	stage_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(stage_column)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 28)
	stage_column.add_child(_title)
	var view := SubViewportContainer.new()
	view.stretch = true
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.gui_input.connect(_on_stage_input)
	stage_column.add_child(view)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	view.add_child(_viewport)
	var footer := HBoxContainer.new()
	stage_column.add_child(footer)
	var hint := Label.new()
	hint.text = "Drag to orbit · Scroll to zoom"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(hint)
	var reset := Button.new()
	reset.text = "Reset view"
	reset.pressed.connect(_frame_model)
	footer.add_child(reset)

func _build_stage() -> void:
	_world = Node3D.new()
	_viewport.add_child(_world)
	_pivot = Node3D.new()
	_world.add_child(_pivot)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = 42.0
	_camera.near = 0.01
	_world.add_child(_camera)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.095, 0.11, 0.135)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.9, 1.0)
	env.ambient_light_energy = 0.65
	environment.environment = env
	_world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -35, 0)
	light.light_energy = 1.4
	light.shadow_enabled = true
	_world.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 145, 0)
	fill.light_energy = 0.45
	_world.add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.18, 0.2)
	material.roughness = 0.9
	floor_mesh.material_override = material
	floor_mesh.position.y = -0.015
	_world.add_child(floor_mesh)

func filter_monsters(query: String) -> void:
	monster_list.clear()
	_filtered.clear()
	for index in monsters.size():
		if query.strip_edges().is_empty() or str(monsters[index].name).to_lower().replace("_", " ").contains(query.strip_edges().to_lower()):
			monster_list.add_item(str(monsters[index].name).replace("_", " "))
			_filtered.append(index)

func select_monster(index: int) -> void:
	if index < 0 or index >= monsters.size(): return
	var preferred_clip := "UAL1 Pro · Idle"
	if _selected_clip >= 0 and _selected_clip < clips.size():
		preferred_clip = str(clips[_selected_clip].name)
	_selected_clip = -1
	clips.clear()
	animation_select.clear()
	if is_instance_valid(model):
		_pivot.remove_child(model)
		model.queue_free()
	var body_archetype: CharacterBodyArchetypeDefinition = equipment_preview.get_body_archetype(str(monsters[index].path).get_file().get_basename())
	var packed := body_archetype.visual_scene if body_archetype != null else load(str(monsters[index].path)) as PackedScene
	if packed == null:
		_title.text = "Unable to load " + str(monsters[index].name)
		return
	model = packed.instantiate() as Node3D
	_pivot.add_child(model)
	model_bounds = _bounds(model)
	model.position -= Vector3(model_bounds.get_center().x, model_bounds.position.y, model_bounds.get_center().z)
	_title.text = str(monsters[index].name).replace("_", " ")
	_collect_clips(model)
	clips.append_array(_animation_library.attach(model))
	clips.sort_custom(func(a, b): return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	for clip in clips:
		animation_select.add_item(str(clip.name))
	animation_select.disabled = clips.is_empty()

	_info.text = "%d animations · Height: %.2f m" % [clips.size(), model_bounds.size.y]
	_info.tooltip_text = str(monsters[index].path)
	if clips.is_empty():
		animation_select.add_item("No animations in this model")
	else:
		var initial_clip := 0
		for clip_index in clips.size():
			if clips[clip_index].name == preferred_clip: initial_clip = clip_index
		animation_select.select(initial_clip)
		select_clip(initial_clip)
	equipment_preview.select_model(str(monsters[index].path).get_file().get_basename(), model)
	_frame_model()

func _collect_clips(node: Node) -> void:
	if node is AnimationPlayer:
		node.stop()
		for clip_name in node.get_animation_list():
			if clip_name == "RESET": continue
			# Duplicate only the preview clip, never modify imported resources.
			var animation: Animation = node.get_animation(clip_name).duplicate()
			var library_name: String = str(clip_name).get_slice("/", 0) if str(clip_name).contains("/") else ""
			var local_name: String = str(clip_name).get_slice("/", 1) if str(clip_name).contains("/") else str(clip_name)
			var library: AnimationLibrary = node.get_animation_library(library_name).duplicate()
			library.remove_animation(local_name)
			library.add_animation(local_name, animation)
			node.remove_animation_library(library_name)
			node.add_animation_library(library_name, library)
			clips.append({"name": clip_name, "player": node})
	for child in node.get_children(): _collect_clips(child)

func select_clip(index: int) -> void:
	if index < 0 or index >= clips.size(): return
	if _selected_clip >= 0: clips[_selected_clip].player.stop()
	var skeleton := AnimationRetargetLib.find_skeleton(model)
	if skeleton != null: skeleton.reset_bone_poses()
	_selected_clip = index
	var entry: Dictionary = clips[index]
	entry.player.get_animation(entry.name).loop_mode = Animation.LOOP_LINEAR
	entry.player.play(entry.name)
	entry.player.advance(0.0)

func _bounds(node: Node3D) -> AABB:
	var meshes := node.find_children("*", "MeshInstance3D", true, false)
	var result := AABB()
	var has_bounds := false
	for mesh in meshes:
		if mesh.mesh == null: continue
		var box: AABB = node.global_transform.affine_inverse() * mesh.global_transform * mesh.mesh.get_aabb()
		result = result.merge(box) if has_bounds else box
		has_bounds = true
	return result

func _frame_model() -> void:
	_yaw = 0.25
	_pitch = 0.12
	_focus = Vector3(0, model_bounds.size.y * 0.5, 0)
	_distance = maxf(model_bounds.size.length() * 1.2, 1.0)
	_update_camera()

func _update_camera() -> void:
	var direction := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	_camera.position = _focus + direction * _distance
	_camera.look_at(_focus)

func _on_stage_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT):
		_yaw -= event.relative.x * ORBIT_SENSITIVITY
		_pitch = clampf(_pitch + event.relative.y * ORBIT_SENSITIVITY, -0.15, 1.3)
		_update_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: _distance = maxf(0.2, _distance / 1.12)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: _distance = minf(200.0, _distance * 1.12)
		_update_camera()
