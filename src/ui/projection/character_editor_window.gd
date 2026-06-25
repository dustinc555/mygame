extends PanelContainer

class_name CharacterEditorWindow

signal save_requested(target_actor, draft_appearance)
signal cancel_requested

const CHARACTER_APPEARANCE_DATA_SCRIPT = preload("res://resources/character_appearance/character_appearance_data.gd")
const SKIN_TEXTURE_BUILDER = preload("res://src/actors/projection/appearance/skin_texture_builder.gd")
const HUMAN_RACE = preload("res://resources/character_races/human.tres")
const HUMAN_MALE_BODY_ARCHETYPE = preload("res://resources/character_body_archetypes/human_male.tres")
const HUMAN_FEMALE_BODY_ARCHETYPE = preload("res://resources/character_body_archetypes/human_female.tres")
const UAL1_ANIMATION_SOURCE_SCENE = preload("res://assets/vendor/quaternius/universal_animation_library_1_pro/UAL1_Pro.glb")

const MODE_CREATION := "creation"
const MODE_BARBER := "barber"
const VIEW_FULL_BODY := 0
const VIEW_FACE := 1
const VISUAL_BODY_TYPE_MALE := 2
const VISUAL_BODY_TYPE_FEMALE := 3
const PREVIEW_VISUAL_YAW_OFFSET := 0.0
const PREVIEW_CHARACTER_HEIGHT := 1.9
const PREVIEW_FOOT_CLEARANCE := 0.02
const PREVIEW_MODEL_VERTICAL_OFFSET := 0.0
const PREVIEW_DRAG_YAW_SCALE := 0.01
const PREVIEW_DRAG_PITCH_SCALE := 0.006
const PREVIEW_FULL_BODY_TARGET_Y := 0.95
const PREVIEW_FULL_BODY_DISTANCE := 3.4
const PREVIEW_FULL_BODY_FOV := 35.0
const PREVIEW_FULL_BODY_BASE_ELEVATION := 0.10
const PREVIEW_FACE_TARGET_Y := 1.62
const PREVIEW_FACE_DISTANCE := 1.25
const PREVIEW_FACE_FOV := 28.0
const PREVIEW_FACE_BASE_ELEVATION := 0.03
const PREVIEW_CAMERA_MIN_PITCH := -0.45
const PREVIEW_CAMERA_MAX_PITCH := 0.65
const PREVIEW_ZOOM_STEP_FACTOR := 0.88
const PREVIEW_MIN_ZOOM_FACTOR := 0.55
const PREVIEW_MAX_ZOOM_FACTOR := 1.85
const RIGHT_COLUMN_WIDTH := 440.0
const PREVIEW_BODY_NODE_NAME := "PreviewBody"
const PREVIEW_IDLE_ANIMATION_PLAYER_NAME := "PreviewIdleAnimationPlayer"
const IDLE_ANIMATION_NAME := "Idle"
const CLOTHING_EQUIPMENT_SLOTS := ["undershirt", "hands", "chest", "legs", "feet", "backpack", "head"]
const MALE_EYEBROW_STYLE_ID := "eyebrows_regular"
const FEMALE_EYEBROW_STYLE_ID := "eyebrows_female"

var target_actor: HumanoidCharacter
var draft_appearance: Resource
var mode := MODE_BARBER
var hair_styles: Array[Resource] = []
var beard_styles: Array[Resource] = []
var eyebrow_styles: Array[Resource] = []

var _built := false
var _preview_model: Node3D
var _last_preview_body_type := VISUAL_BODY_TYPE_MALE
var _preview_view_mode := VIEW_FULL_BODY
var _preview_rotation_y := 0.0
var _preview_pitch_x := 0.0
var _preview_zoom_factor := 1.0
var _preview_dragging := false
var _preview_clothes_visible := true
var _preview_clothing_surface_offsets: Dictionary = {}
var _preview_visual_root: Node3D
var _preview_skeleton: Skeleton3D
var _preview_foot_anchor_correction_y := 0.0

var _name_edit: LineEdit
var _creation_section: VBoxContainer
var _race_option: OptionButton
var _body_type_option: OptionButton
var _skin_tone_buttons: Array[Button] = []
var _skin_color_reset_button: Button
var _height_slider: HSlider
var _shoulder_slider: HSlider
var _arm_slider: HSlider
var _neck_slider: HSlider
var _hair_option: OptionButton
var _beard_row: Control
var _beard_color_row: Control
var _beard_option: OptionButton
var _hair_color: ColorPickerButton
var _beard_color: ColorPickerButton
var _show_clothes_button: CheckButton
var _face_view_button: CheckButton
var _preview_viewport: SubViewport
var _preview_root: Node3D
var _preview_camera: Camera3D
var _save_button: Button
var _cancel_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func configure_styles(next_hair_styles: Array[Resource], next_beard_styles: Array[Resource], next_eyebrow_styles: Array[Resource]) -> void:
	hair_styles = next_hair_styles.duplicate()
	beard_styles = next_beard_styles.duplicate()
	eyebrow_styles = next_eyebrow_styles.duplicate()


func open_for_actor(actor: HumanoidCharacter, editor_mode := MODE_BARBER) -> void:
	_build_ui()
	target_actor = actor
	mode = editor_mode
	if target_actor != null and target_actor.has_method("get_appearance_copy"):
		draft_appearance = target_actor.get_appearance_copy()
	else:
		draft_appearance = CHARACTER_APPEARANCE_DATA_SCRIPT.new()
		_setup_default_creation_appearance()
	if target_actor == null and mode == MODE_CREATION and _name_edit != null:
		_name_edit.text = "Wanderer"
	_preview_rotation_y = 0.0
	_preview_pitch_x = 0.0
	_preview_zoom_factor = 1.0
	_preview_dragging = false
	_preview_clothes_visible = true
	_preview_view_mode = VIEW_FULL_BODY
	if _show_clothes_button != null:
		_show_clothes_button.set_pressed_no_signal(_preview_clothes_visible)
	if _face_view_button != null:
		_face_view_button.set_pressed_no_signal(_preview_view_mode == VIEW_FACE)
	_update_preview_camera()
	_sync_controls_from_draft()
	visible = true
	_rebuild_preview()


func close_editor() -> void:
	visible = false
	_clear_preview()
	target_actor = null
	draft_appearance = null


func save_current() -> void:
	_on_save_pressed()


func cancel_current() -> void:
	_on_cancel_pressed()


func _build_ui() -> void:
	if _built:
		return
	_built = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = Vector2.ZERO
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.035, 0.04, 1.0)
	add_theme_stylebox_override("panel", panel_style)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)

	var body_row := HBoxContainer.new()
	body_row.add_theme_constant_override("separation", 12)
	body_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(body_row)

	var preview_panel := PanelContainer.new()
	preview_panel.custom_minimum_size = Vector2(520.0, 560.0)
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_row.add_child(preview_panel)
	var preview_margin := MarginContainer.new()
	preview_margin.add_theme_constant_override("margin_left", 8)
	preview_margin.add_theme_constant_override("margin_top", 8)
	preview_margin.add_theme_constant_override("margin_right", 8)
	preview_margin.add_theme_constant_override("margin_bottom", 8)
	preview_panel.add_child(preview_margin)
	var preview_column := VBoxContainer.new()
	preview_column.add_theme_constant_override("separation", 8)
	preview_margin.add_child(preview_column)
	var viewport_container := SubViewportContainer.new()
	viewport_container.custom_minimum_size = Vector2(500.0, 500.0)
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_container.stretch = true
	viewport_container.gui_input.connect(_on_preview_gui_input)
	preview_column.add_child(viewport_container)
	_preview_viewport = SubViewport.new()
	_preview_viewport.process_mode = Node.PROCESS_MODE_ALWAYS
	_preview_viewport.size = Vector2i(500, 500)
	_preview_viewport.world_3d = World3D.new()
	_preview_viewport.transparent_bg = false
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(_preview_viewport)
	_preview_root = Node3D.new()
	_preview_root.name = "PreviewRoot"
	_preview_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_preview_viewport.add_child(_preview_root)
	_setup_preview_studio()
	var light := DirectionalLight3D.new()
	light.name = "PreviewLight"
	light.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
	light.light_energy = 2.2
	_preview_root.add_child(light)
	_preview_camera = Camera3D.new()
	_preview_camera.name = "PreviewCamera"
	_preview_camera.fov = 35.0
	_preview_camera.current = true
	_preview_root.add_child(_preview_camera)
	_update_preview_camera()
	var preview_controls := HBoxContainer.new()
	preview_controls.add_theme_constant_override("separation", 10)
	preview_column.add_child(preview_controls)
	_show_clothes_button = CheckButton.new()
	_show_clothes_button.text = "Show clothes in preview"
	_show_clothes_button.button_pressed = true
	_show_clothes_button.toggled.connect(_on_show_clothes_toggled)
	preview_controls.add_child(_show_clothes_button)
	var preview_control_spacer := Control.new()
	preview_control_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_controls.add_child(preview_control_spacer)
	_face_view_button = CheckButton.new()
	_face_view_button.text = "Face"
	_face_view_button.toggled.connect(_on_face_view_toggled)
	preview_controls.add_child(_face_view_button)
	var drag_hint := Label.new()
	drag_hint.text = "Drag preview to rotate; wheel to zoom"
	drag_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_column.add_child(drag_hint)

	var right_column := VBoxContainer.new()
	right_column.add_theme_constant_override("separation", 8)
	right_column.custom_minimum_size = Vector2(RIGHT_COLUMN_WIDTH, 0.0)
	right_column.size_flags_horizontal = Control.SIZE_SHRINK_END
	right_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_row.add_child(right_column)

	var controls := ScrollContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_column.add_child(controls)
	var control_column := VBoxContainer.new()
	control_column.add_theme_constant_override("separation", 8)
	control_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(control_column)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Character name"
	_name_edit.text_changed.connect(_on_name_changed)
	control_column.add_child(_labeled_control("Name", _name_edit))

	_creation_section = VBoxContainer.new()
	_creation_section.add_theme_constant_override("separation", 8)
	control_column.add_child(_creation_section)
	_race_option = OptionButton.new()
	_race_option.add_item("Human", 0)
	_race_option.set_item_metadata(0, HUMAN_RACE)
	_race_option.item_selected.connect(_on_race_selected)
	_creation_section.add_child(_labeled_control("Race", _race_option))
	_body_type_option = OptionButton.new()
	_body_type_option.add_item("Male", VISUAL_BODY_TYPE_MALE)
	_body_type_option.add_item("Female", VISUAL_BODY_TYPE_FEMALE)
	_body_type_option.item_selected.connect(_on_body_type_selected)
	_creation_section.add_child(_labeled_control("Sex", _body_type_option))
	_creation_section.add_child(_labeled_control("Skin color", _create_skin_tone_controls()))
	_height_slider = _make_slider()
	_height_slider.value_changed.connect(_on_height_changed)
	_creation_section.add_child(_labeled_control("Height", _height_slider))
	_shoulder_slider = _make_slider()
	_shoulder_slider.value_changed.connect(_on_shoulders_changed)
	_creation_section.add_child(_labeled_control("Shoulders", _shoulder_slider))
	_arm_slider = _make_slider()
	_arm_slider.value_changed.connect(_on_arm_length_changed)
	_creation_section.add_child(_labeled_control("Arm Length", _arm_slider))
	_neck_slider = _make_slider()
	_neck_slider.value_changed.connect(_on_neck_length_changed)
	_creation_section.add_child(_labeled_control("Neck Length", _neck_slider))

	_hair_option = OptionButton.new()
	_hair_option.item_selected.connect(_on_hair_selected)
	control_column.add_child(_labeled_control("Hair", _hair_option))
	_hair_color = ColorPickerButton.new()
	_hair_color.color_changed.connect(_on_hair_color_changed)
	control_column.add_child(_labeled_control("Hair color", _hair_color))
	_beard_option = OptionButton.new()
	_beard_option.item_selected.connect(_on_beard_selected)
	_beard_row = _labeled_control("Beard", _beard_option)
	control_column.add_child(_beard_row)
	_beard_color = ColorPickerButton.new()
	_beard_color.color_changed.connect(_on_beard_color_changed)
	_beard_color_row = _labeled_control("Beard color", _beard_color)
	control_column.add_child(_beard_color_row)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 8)
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_column.add_child(footer)
	_cancel_button = Button.new()
	_cancel_button.text = "Cancel"
	_cancel_button.pressed.connect(_on_cancel_pressed)
	footer.add_child(_cancel_button)
	_save_button = Button.new()
	_save_button.text = "Save"
	_save_button.pressed.connect(_on_save_pressed)
	footer.add_child(_save_button)


func _setup_preview_studio() -> void:
	var environment := WorldEnvironment.new()
	environment.name = "PreviewStudioEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.105, 0.095, 0.085, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.72, 0.66, 1.0)
	env.ambient_light_energy = 0.75
	environment.environment = env
	_preview_root.add_child(environment)

	var floor_mesh_instance := MeshInstance3D.new()
	floor_mesh_instance.name = "PreviewStudioFloor"
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(5.0, 5.0)
	floor_mesh_instance.mesh = floor_mesh
	floor_mesh_instance.position = Vector3(0.0, -0.01, 0.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.20, 0.18, 0.155, 1.0)
	floor_material.roughness = 0.92
	floor_mesh_instance.set_surface_override_material(0, floor_material)
	_preview_root.add_child(floor_mesh_instance)

	var backdrop := MeshInstance3D.new()
	backdrop.name = "PreviewStudioBackdrop"
	var backdrop_mesh := PlaneMesh.new()
	backdrop_mesh.size = Vector2(5.0, 3.2)
	backdrop.mesh = backdrop_mesh
	backdrop.position = Vector3(0.0, 1.5, -1.35)
	backdrop.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var backdrop_material := StandardMaterial3D.new()
	backdrop_material.albedo_color = Color(0.14, 0.125, 0.105, 1.0)
	backdrop_material.roughness = 0.96
	backdrop.set_surface_override_material(0, backdrop_material)
	_preview_root.add_child(backdrop)


func _make_slider() -> HSlider:
	var slider := HSlider.new()
	slider.min_value = -1.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return slider


func _create_skin_tone_controls() -> Control:
	_skin_tone_buttons.clear()
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var swatches := GridContainer.new()
	swatches.columns = 5
	swatches.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(swatches)
	var tones: Array = SKIN_TEXTURE_BUILDER.NATURAL_SKIN_TONES
	for index in range(tones.size()):
		var tone: Color = tones[index]
		var button := Button.new()
		button.custom_minimum_size = Vector2(34.0, 24.0)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_skin_tone_pressed.bind(index))
		_style_skin_tone_button(button, tone, false)
		_skin_tone_buttons.append(button)
		swatches.add_child(button)
	_skin_color_reset_button = Button.new()
	_skin_color_reset_button.text = "Reset"
	_skin_color_reset_button.pressed.connect(_on_skin_color_reset_pressed)
	controls.add_child(_skin_color_reset_button)
	return controls


func _labeled_control(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.custom_minimum_size = Vector2(110.0, 0.0)
	label.text = label_text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _setup_default_creation_appearance() -> void:
	draft_appearance.character_race = HUMAN_RACE
	draft_appearance.body_archetype = HUMAN_MALE_BODY_ARCHETYPE
	draft_appearance.visual_body_type = VISUAL_BODY_TYPE_MALE
	draft_appearance.skin_color_customized = true
	draft_appearance.skin_color = CHARACTER_APPEARANCE_DATA_SCRIPT.DEFAULT_SKIN_COLOR


func _sync_controls_from_draft() -> void:
	if draft_appearance == null:
		return
	draft_appearance.skin_color = SKIN_TEXTURE_BUILDER.get_nearest_skin_tone(draft_appearance.skin_color)
	_creation_section.visible = mode == MODE_CREATION
	_name_edit.visible = mode == MODE_CREATION
	var name_row := _name_edit.get_parent() as Control
	if name_row != null:
		name_row.visible = mode == MODE_CREATION
	var body_archetype := _resolve_preview_body_archetype()
	var body_type := _resolve_preview_body_type(body_archetype)
	_apply_body_type_style_constraints(body_type)
	_populate_style_option(_hair_option, _get_supported_styles(hair_styles, body_type), draft_appearance.hair_style)
	_populate_style_option(_beard_option, _get_supported_styles(beard_styles, body_type), draft_appearance.beard_style)
	_hair_color.color = draft_appearance.hair_color
	_beard_color.color = draft_appearance.beard_color
	_race_option.select(0)
	_sync_skin_tone_buttons(draft_appearance.skin_color)
	_height_slider.set_value_no_signal(draft_appearance.height_slider)
	_shoulder_slider.set_value_no_signal(draft_appearance.shoulder_width_slider)
	_arm_slider.set_value_no_signal(draft_appearance.arm_length_slider)
	_neck_slider.set_value_no_signal(draft_appearance.neck_length_slider)
	_body_type_option.select(1 if body_type == VISUAL_BODY_TYPE_FEMALE else 0)
	if target_actor != null:
		_name_edit.text = target_actor.member_name


func _apply_body_type_style_constraints(body_type: int) -> void:
	if not _style_supports_body_type(draft_appearance.hair_style, body_type):
		draft_appearance.hair_style = null
	draft_appearance.eyebrow_style = _get_default_eyebrow_style(body_type)
	draft_appearance.eyebrow_color = draft_appearance.hair_color
	var allow_beard := body_type != VISUAL_BODY_TYPE_FEMALE
	if not allow_beard or not _style_supports_body_type(draft_appearance.beard_style, body_type):
		draft_appearance.beard_style = null
	if _beard_row != null:
		_beard_row.visible = allow_beard
	if _beard_color_row != null:
		_beard_color_row.visible = allow_beard


func _get_default_eyebrow_style(body_type: int) -> Resource:
	var expected_id := FEMALE_EYEBROW_STYLE_ID if body_type == VISUAL_BODY_TYPE_FEMALE else MALE_EYEBROW_STYLE_ID
	return _find_style_by_id(eyebrow_styles, expected_id)


func _find_style_by_id(styles: Array[Resource], style_id: String) -> Resource:
	for style in styles:
		if style != null and str(style.get("style_id")) == style_id:
			return style
	return null


func _style_supports_body_type(style: Resource, body_type: int) -> bool:
	if style == null:
		return true
	if not style.has_method("supports_body_type"):
		return true
	var body_type_id := "female" if body_type == VISUAL_BODY_TYPE_FEMALE else "male"
	return style.supports_body_type(body_type_id)


func _get_supported_styles(styles: Array[Resource], body_type: int) -> Array[Resource]:
	var body_type_id := "female" if body_type == VISUAL_BODY_TYPE_FEMALE else "male"
	var result: Array[Resource] = []
	for style in styles:
		if style == null:
			continue
		if style.has_method("supports_body_type") and not style.supports_body_type(body_type_id):
			continue
		result.append(style)
	_sort_styles_for_body(result, body_type)
	return result


func _sort_styles_for_body(styles: Array[Resource], body_type: int) -> void:
	var order := ["hair_buzzed", "hair_simple_parted", "hair_long"]
	if body_type == VISUAL_BODY_TYPE_FEMALE:
		order = ["hair_buns", "hair_long", "hair_buzzed_female"]
	styles.sort_custom(func(left: Resource, right: Resource) -> bool:
		var left_id := str(left.get("style_id"))
		var right_id := str(right.get("style_id"))
		var left_index := order.find(left_id)
		var right_index := order.find(right_id)
		if left_index >= 0 and right_index >= 0:
			return left_index < right_index
		if left_index >= 0:
			return true
		if right_index >= 0:
			return false
		return left_id < right_id
	)


func _populate_style_option(option: OptionButton, styles: Array[Resource], selected_style: Resource) -> void:
	option.clear()
	option.add_item("None", 0)
	option.set_item_metadata(0, null)
	var selected_index := 0
	for style in styles:
		if style == null:
			continue
		var index := option.item_count
		option.add_item(str(style.get("display_name")), index)
		option.set_item_metadata(index, style)
		if _same_style(style, selected_style):
			selected_index = index
	option.select(selected_index)


func _same_style(left: Resource, right: Resource) -> bool:
	if left == right:
		return true
	if left == null or right == null:
		return false
	var left_id := str(left.get("style_id"))
	var right_id := str(right.get("style_id"))
	return not left_id.is_empty() and left_id == right_id


func _get_selected_style(option: OptionButton) -> Resource:
	var index := option.selected
	if index < 0:
		return null
	return option.get_item_metadata(index) as Resource


func _rebuild_preview() -> void:
	if draft_appearance == null or _preview_root == null:
		return
	_apply_body_type_style_constraints(_resolve_preview_body_type(_resolve_preview_body_archetype()))
	_clear_preview()
	_preview_model = _create_preview_model()
	if _preview_model == null:
		return
	_preview_root.add_child(_preview_model)
	_preview_model.position = Vector3(0.0, PREVIEW_MODEL_VERTICAL_OFFSET, 0.0)
	_set_preview_clothing_visible(_preview_clothes_visible)


func _create_preview_model() -> Node3D:
	var model := Node3D.new()
	model.name = "PreviewVisualMannequin"
	model.process_mode = Node.PROCESS_MODE_ALWAYS
	_preview_clothing_surface_offsets.clear()
	var visual_root := Node3D.new()
	visual_root.name = "PreviewCharacterVisual"
	model.add_child(visual_root)
	var body_archetype := _resolve_preview_body_archetype()
	_preview_visual_root = visual_root
	_preview_foot_anchor_correction_y = 0.0
	_last_preview_body_type = _resolve_preview_body_type(body_archetype)
	var visual_scene := _get_preview_visual_scene(body_archetype)
	if visual_scene == null:
		return null
	var body_instance := visual_scene.instantiate()
	if not (body_instance is Node3D):
		body_instance.queue_free()
		return null
	var body_root := body_instance as Node3D
	body_root.name = PREVIEW_BODY_NODE_NAME
	body_root.rotation.y = PREVIEW_VISUAL_YAW_OFFSET
	_apply_preview_skin_materials(body_root)
	visual_root.add_child(body_root)
	_setup_preview_idle_animation(body_root)
	_set_base_eyebrow_visuals_visible(body_root, draft_appearance.eyebrow_style == null)
	var visual_fit_scale := _fit_preview_visual_to_height(visual_root)
	var skeleton := _find_skeleton(visual_root)
	_preview_skeleton = skeleton
	_apply_preview_bone_offsets(skeleton, body_archetype)
	_setup_preview_clothing_visuals(visual_root, skeleton, body_archetype, visual_fit_scale)
	_setup_preview_head_attachment_visuals(visual_root, skeleton)
	model.rotation.y = _preview_rotation_y
	return model


func preview_uses_own_world() -> bool:
	if _preview_viewport == null or _preview_viewport.world_3d == null:
		return false
	var parent_viewport := get_viewport()
	return parent_viewport == null or _preview_viewport.world_3d != parent_viewport.world_3d


func preview_contains_live_actor_nodes() -> bool:
	return _contains_live_actor_node(_preview_model)


func has_opaque_modal_background() -> bool:
	var panel_style := get_theme_stylebox("panel") as StyleBoxFlat
	if panel_style == null or panel_style.bg_color.a < 0.999:
		return false
	return _preview_viewport != null and not _preview_viewport.transparent_bg


func preview_has_studio_environment() -> bool:
	return _preview_root != null \
		and _preview_root.get_node_or_null("PreviewStudioEnvironment") != null \
		and _preview_root.get_node_or_null("PreviewStudioFloor") != null \
		and _preview_root.get_node_or_null("PreviewStudioBackdrop") != null


func get_preview_body_type() -> int:
	return _last_preview_body_type


func preview_is_playing_idle() -> bool:
	var animation_player := _get_preview_idle_animation_player()
	return animation_player != null and animation_player.current_animation == IDLE_ANIMATION_NAME and animation_player.is_playing()


func preview_faces_camera() -> bool:
	var body_root := _get_preview_body_root()
	if body_root == null:
		return false
	return absf(wrapf(_preview_rotation_y, -PI, PI)) < 0.01 and absf(wrapf(body_root.rotation.y, -PI, PI)) < 0.01


func get_preview_rotation_y() -> float:
	return _preview_rotation_y


func rotate_preview_by(delta_y: float) -> void:
	_preview_rotation_y = wrapf(_preview_rotation_y + delta_y, -PI, PI)
	if _preview_model != null:
		_preview_model.rotation.y = _preview_rotation_y


func pitch_preview_by(delta_x: float) -> void:
	_preview_pitch_x = clampf(_preview_pitch_x + delta_x, PREVIEW_CAMERA_MIN_PITCH, PREVIEW_CAMERA_MAX_PITCH)
	_update_preview_camera()


func zoom_preview_by_steps(step_count: float) -> void:
	if absf(step_count) <= 0.001:
		return
	if step_count > 0.0:
		_preview_zoom_factor *= pow(PREVIEW_ZOOM_STEP_FACTOR, step_count)
	else:
		_preview_zoom_factor /= pow(PREVIEW_ZOOM_STEP_FACTOR, -step_count)
	_preview_zoom_factor = clampf(_preview_zoom_factor, PREVIEW_MIN_ZOOM_FACTOR, PREVIEW_MAX_ZOOM_FACTOR)
	_update_preview_camera()


func reset_preview_zoom() -> void:
	_preview_zoom_factor = 1.0
	_update_preview_camera()


func reset_preview_rotation() -> void:
	_preview_rotation_y = 0.0
	_preview_pitch_x = 0.0
	if _preview_model != null:
		_preview_model.rotation.y = _preview_rotation_y
	_update_preview_camera()


func get_preview_pitch_x() -> float:
	return _preview_pitch_x


func get_preview_zoom_factor() -> float:
	return _preview_zoom_factor


func get_preview_lowest_visual_y() -> float:
	if _preview_model == null:
		return INF
	return _calculate_local_mesh_bounds(_preview_model).position.y


func get_preview_floor_y() -> float:
	var preview_floor := _preview_root.get_node_or_null("PreviewStudioFloor") as Node3D if _preview_root != null else null
	return preview_floor.global_position.y if preview_floor != null else 0.0


func get_preview_foot_anchor_y() -> float:
	return _get_skeleton_foot_anchor_global_y(_preview_skeleton)


func _update_preview_camera() -> void:
	if _preview_camera == null:
		return
	var target_y := PREVIEW_FACE_TARGET_Y if _preview_view_mode == VIEW_FACE else PREVIEW_FULL_BODY_TARGET_Y
	var distance := (PREVIEW_FACE_DISTANCE if _preview_view_mode == VIEW_FACE else PREVIEW_FULL_BODY_DISTANCE) * _preview_zoom_factor
	var base_elevation := PREVIEW_FACE_BASE_ELEVATION if _preview_view_mode == VIEW_FACE else PREVIEW_FULL_BODY_BASE_ELEVATION
	_preview_camera.fov = PREVIEW_FACE_FOV if _preview_view_mode == VIEW_FACE else PREVIEW_FULL_BODY_FOV
	var target := Vector3(0.0, target_y, 0.0)
	var elevation := base_elevation + _preview_pitch_x
	_preview_camera.position = target + Vector3(0.0, sin(elevation) * distance, cos(elevation) * distance)
	_preview_camera.look_at(target, Vector3.UP)


func preview_has_clothing_slot(slot_name: String) -> bool:
	if _preview_model == null:
		return false
	var visual_root := _preview_model.get_node_or_null("PreviewCharacterVisual")
	if visual_root == null:
		return false
	var expected_name := "Equipped_%s" % slot_name.capitalize()
	for child in visual_root.get_children():
		if str(child.name) == expected_name:
			return true
	return false


func preview_clothing_slot_visible(slot_name: String) -> bool:
	if _preview_model == null:
		return false
	var visual_root := _preview_model.get_node_or_null("PreviewCharacterVisual")
	if visual_root == null:
		return false
	var expected_name := "Equipped_%s" % slot_name.capitalize()
	for child in visual_root.get_children():
		if str(child.name) == expected_name and child is Node3D:
			return (child as Node3D).visible
	return false


func get_preview_clothing_surface_offset(slot_name: String) -> float:
	return float(_preview_clothing_surface_offsets.get(slot_name, 0.0))


func set_preview_clothes_visible(visible_flag: bool) -> void:
	_preview_clothes_visible = visible_flag
	if _show_clothes_button != null:
		_show_clothes_button.set_pressed_no_signal(visible_flag)
	_set_preview_clothing_visible(visible_flag)


func get_preview_clothes_visible() -> bool:
	return _preview_clothes_visible


func beard_controls_visible() -> bool:
	return _beard_row != null and _beard_row.visible


func creation_controls_visible() -> bool:
	return _creation_section != null and _creation_section.visible


func get_race_option_labels() -> PackedStringArray:
	var labels := PackedStringArray()
	if _race_option == null:
		return labels
	for index in range(_race_option.item_count):
		labels.append(_race_option.get_item_text(index))
	return labels


func get_character_name() -> String:
	if _name_edit == null:
		return ""
	return _name_edit.text.strip_edges()


func set_character_name(next_name: String) -> void:
	if _name_edit == null:
		return
	_name_edit.text = next_name


func set_creation_body_type(body_type: int) -> void:
	if _body_type_option == null:
		return
	var option_index := 0
	for index in range(_body_type_option.item_count):
		if int(_body_type_option.get_item_id(index)) == body_type:
			option_index = index
			break
	_body_type_option.select(option_index)
	_on_body_type_selected(option_index)


func set_creation_body_sliders(height: float, shoulders: float, neck: float) -> void:
	set_creation_skeleton_sliders(height, shoulders, 0.0, neck)


func set_creation_skeleton_sliders(height: float, shoulders: float, arm_length: float, neck_length: float) -> void:
	var clamped_height := clampf(height, -1.0, 1.0)
	var clamped_shoulders := clampf(shoulders, -1.0, 1.0)
	var clamped_arm_length := clampf(arm_length, -1.0, 1.0)
	var clamped_neck_length := clampf(neck_length, -1.0, 1.0)
	if _height_slider != null:
		_height_slider.set_value_no_signal(clamped_height)
	if _shoulder_slider != null:
		_shoulder_slider.set_value_no_signal(clamped_shoulders)
	if _arm_slider != null:
		_arm_slider.set_value_no_signal(clamped_arm_length)
	if _neck_slider != null:
		_neck_slider.set_value_no_signal(clamped_neck_length)
	_on_height_changed(clamped_height)
	_on_shoulders_changed(clamped_shoulders)
	_on_arm_length_changed(clamped_arm_length)
	_on_neck_length_changed(clamped_neck_length)


func set_skin_color_value(color: Color) -> void:
	if draft_appearance == null:
		return
	var normalized_color: Color = SKIN_TEXTURE_BUILDER.get_nearest_skin_tone(color)
	draft_appearance.skin_color = normalized_color
	draft_appearance.skin_color_customized = true
	_sync_skin_tone_buttons(normalized_color)
	_apply_current_preview_skin_materials()


func reset_skin_color_to_default() -> void:
	if draft_appearance == null:
		return
	var default_color: Color = SKIN_TEXTURE_BUILDER.get_nearest_skin_tone(CHARACTER_APPEARANCE_DATA_SCRIPT.DEFAULT_SKIN_COLOR)
	draft_appearance.skin_color = default_color
	draft_appearance.skin_color_customized = true
	_sync_skin_tone_buttons(default_color)
	_apply_current_preview_skin_materials()


func get_preview_skin_color() -> Color:
	return draft_appearance.skin_color if draft_appearance != null else CHARACTER_APPEARANCE_DATA_SCRIPT.DEFAULT_SKIN_COLOR


func preview_has_custom_skin_material() -> bool:
	return _preview_model != null and SKIN_TEXTURE_BUILDER.has_custom_skin_materials(_preview_model)


func get_beard_option_count() -> int:
	return _beard_option.item_count if _beard_option != null else 0


func get_hair_option_style_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	if _hair_option == null:
		return ids
	for index in range(_hair_option.item_count):
		var style := _hair_option.get_item_metadata(index) as Resource
		if style == null:
			continue
		ids.append(str(style.get("style_id")))
	return ids


func set_preview_view_mode(mode_id: int) -> void:
	_preview_view_mode = VIEW_FACE if mode_id == VIEW_FACE else VIEW_FULL_BODY
	if _face_view_button != null:
		_face_view_button.set_pressed_no_signal(_preview_view_mode == VIEW_FACE)
	_update_preview_camera()


func get_preview_view_mode() -> int:
	return _preview_view_mode


func get_preview_camera_distance() -> float:
	if _preview_camera == null:
		return 0.0
	var target_y := PREVIEW_FACE_TARGET_Y if _preview_view_mode == VIEW_FACE else PREVIEW_FULL_BODY_TARGET_Y
	return _preview_camera.position.distance_to(Vector3(0.0, target_y, 0.0))


func preview_has_visible_base_eyebrows() -> bool:
	return _has_visible_base_eyebrow_visual(_get_preview_body_root())


func preview_has_custom_eyebrows() -> bool:
	if _preview_model == null:
		return false
	var visual_root := _preview_model.get_node_or_null("PreviewCharacterVisual")
	if visual_root == null:
		return false
	return visual_root.get_node_or_null("AppearanceEyebrows") != null


func _get_preview_body_root() -> Node3D:
	if _preview_model == null:
		return null
	var visual_root := _preview_model.get_node_or_null("PreviewCharacterVisual")
	if visual_root == null:
		return null
	return visual_root.get_node_or_null(PREVIEW_BODY_NODE_NAME) as Node3D


func _get_preview_idle_animation_player() -> AnimationPlayer:
	var body_root := _get_preview_body_root()
	if body_root == null:
		return null
	return body_root.get_node_or_null(PREVIEW_IDLE_ANIMATION_PLAYER_NAME) as AnimationPlayer


func _resolve_preview_body_archetype() -> Resource:
	if draft_appearance.body_archetype != null:
		return draft_appearance.body_archetype
	if target_actor != null and is_instance_valid(target_actor) and target_actor.has_method("get_resolved_body_archetype"):
		var target_archetype := target_actor.get_resolved_body_archetype()
		if target_archetype != null:
			return target_archetype
	var race: Resource = draft_appearance.character_race if draft_appearance.character_race != null else HUMAN_RACE
	match int(draft_appearance.visual_body_type):
		VISUAL_BODY_TYPE_FEMALE:
			if race != null and race.get("default_female_archetype") != null:
				return race.get("default_female_archetype") as Resource
			return HUMAN_FEMALE_BODY_ARCHETYPE
		_:
			if race != null and race.get("default_male_archetype") != null:
				return race.get("default_male_archetype") as Resource
			return HUMAN_MALE_BODY_ARCHETYPE


func _resolve_preview_body_type(body_archetype: Resource) -> int:
	var body_type := int(draft_appearance.visual_body_type)
	if body_type == VISUAL_BODY_TYPE_MALE or body_type == VISUAL_BODY_TYPE_FEMALE:
		return body_type
	if target_actor != null and is_instance_valid(target_actor) and target_actor.has_method("get_resolved_visual_body_type"):
		var target_body_type := int(target_actor.get_resolved_visual_body_type())
		if target_body_type == VISUAL_BODY_TYPE_MALE or target_body_type == VISUAL_BODY_TYPE_FEMALE:
			return target_body_type
	if body_archetype != null:
		var archetype_body_type := int(body_archetype.get("visual_body_type"))
		if archetype_body_type == VISUAL_BODY_TYPE_MALE or archetype_body_type == VISUAL_BODY_TYPE_FEMALE:
			return archetype_body_type
	return VISUAL_BODY_TYPE_MALE


func _get_preview_visual_scene(body_archetype: Resource) -> PackedScene:
	if body_archetype != null:
		var archetype_scene := body_archetype.get("visual_scene") as PackedScene
		if archetype_scene != null:
			return archetype_scene
	var body_type: int = _resolve_preview_body_type(body_archetype)
	var fallback_archetype: Resource = HUMAN_FEMALE_BODY_ARCHETYPE if body_type == VISUAL_BODY_TYPE_FEMALE else HUMAN_MALE_BODY_ARCHETYPE
	return fallback_archetype.get("visual_scene") as PackedScene


func _setup_preview_idle_animation(body_root: Node3D) -> void:
	if body_root == null:
		return
	var source_root := UAL1_ANIMATION_SOURCE_SCENE.instantiate()
	var source_player := _find_animation_player(source_root)
	if source_player == null or not source_player.has_animation(IDLE_ANIMATION_NAME):
		source_root.queue_free()
		return
	var idle_animation := source_player.get_animation(IDLE_ANIMATION_NAME)
	if idle_animation == null:
		source_root.queue_free()
		return
	var animation_player := AnimationPlayer.new()
	animation_player.name = PREVIEW_IDLE_ANIMATION_PLAYER_NAME
	animation_player.process_mode = Node.PROCESS_MODE_ALWAYS
	animation_player.root_node = NodePath("..")
	body_root.add_child(animation_player)
	var animation_library := AnimationLibrary.new()
	animation_library.add_animation(IDLE_ANIMATION_NAME, idle_animation.duplicate(true) as Animation)
	animation_player.add_animation_library("", animation_library)
	animation_player.play(IDLE_ANIMATION_NAME)
	source_root.queue_free()


func _fit_preview_visual_to_height(visual_root: Node3D) -> float:
	var visual_bounds := _calculate_local_mesh_bounds(visual_root)
	if visual_bounds.size.y <= 0.001:
		return 1.0
	var fit_scale := PREVIEW_CHARACTER_HEIGHT / visual_bounds.size.y
	var visual_center := visual_bounds.position + visual_bounds.size * 0.5
	visual_root.scale = Vector3.ONE * fit_scale
	visual_root.position = Vector3(
		-visual_center.x * fit_scale,
		PREVIEW_FOOT_CLEARANCE - visual_bounds.position.y * fit_scale,
		-visual_center.z * fit_scale
	)
	return fit_scale


func _apply_preview_bone_offsets(skeleton: Skeleton3D, body_archetype: Resource) -> void:
	if skeleton == null:
		return
	var base_offsets: Dictionary = {}
	if body_archetype != null and body_archetype.get("bone_pose_position_offsets") is Dictionary:
		base_offsets = (body_archetype.get("bone_pose_position_offsets") as Dictionary).duplicate()
	var offsets: Dictionary = draft_appearance.get_body_pose_offsets(base_offsets) if draft_appearance.has_method("get_body_pose_offsets") else base_offsets
	_reset_bone_pose_positions(skeleton, offsets)
	skeleton.force_update_all_bone_transforms()
	for bone_name_value in offsets.keys():
		var bone_name := str(bone_name_value)
		var bone_index := skeleton.find_bone(bone_name)
		if bone_index < 0:
			continue
		var offset := offsets[bone_name_value] as Vector3
		skeleton.set_bone_pose_position(bone_index, skeleton.get_bone_rest(bone_index).origin + offset)
	skeleton.force_update_all_bone_transforms()
	_apply_preview_foot_anchor_correction()


func _reset_bone_pose_positions(skeleton: Skeleton3D, offsets: Dictionary) -> void:
	for bone_name_value in offsets.keys():
		var bone_index := skeleton.find_bone(str(bone_name_value))
		if bone_index < 0:
			continue
		skeleton.set_bone_pose_position(bone_index, skeleton.get_bone_rest(bone_index).origin)


func _apply_preview_foot_anchor_correction() -> void:
	if _preview_visual_root == null or not is_instance_valid(_preview_visual_root):
		return
	var desired_correction := 0.0
	if draft_appearance != null and draft_appearance.has_method("get_foot_anchor_correction_y"):
		desired_correction = float(draft_appearance.get_foot_anchor_correction_y()) * _preview_visual_root.scale.y
	_preview_visual_root.position.y += desired_correction - _preview_foot_anchor_correction_y
	_preview_foot_anchor_correction_y = desired_correction


func _get_skeleton_foot_anchor_global_y(skeleton: Skeleton3D) -> float:
	if skeleton == null or not is_instance_valid(skeleton):
		return INF
	var result := INF
	for bone_name in ["foot_l", "foot_r", "ball_l", "ball_r"]:
		var bone_index := skeleton.find_bone(bone_name)
		if bone_index < 0:
			continue
		var bone_global_position := skeleton.global_transform * skeleton.get_bone_global_pose(bone_index).origin
		result = minf(result, bone_global_position.y)
	return result


func _setup_preview_clothing_visuals(visual_root: Node3D, skeleton: Skeleton3D, body_archetype: Resource, visual_fit_scale: float) -> void:
	if target_actor == null or not is_instance_valid(target_actor):
		return
	var surface_offset_base := PREVIEW_CHARACTER_HEIGHT / maxf(visual_fit_scale, 0.001)
	for slot_name in CLOTHING_EQUIPMENT_SLOTS:
		var item := target_actor.get_equipped_item(slot_name)
		if item == null:
			continue
		var equipped_scene := item.get_equipped_scene_for_body_archetype(body_archetype)
		if equipped_scene == null:
			continue
		var instance := equipped_scene.instantiate()
		if not (instance is Node3D):
			instance.queue_free()
			continue
		var source_root := instance as Node3D
		var visual_transform: Transform3D = item.equipped_transform
		var surface_offset_ratio := 0.0
		var equipment_visual := item.get_equipment_visual_for_body_archetype(body_archetype)
		if equipment_visual != null:
			visual_transform = equipment_visual.get("equipped_transform")
			surface_offset_ratio = float(equipment_visual.get("surface_offset_ratio"))
		var surface_offset := surface_offset_base * surface_offset_ratio
		_preview_clothing_surface_offsets[slot_name] = surface_offset
		var node_name := "Equipped_%s" % slot_name.capitalize()
		if skeleton != null and _setup_preview_shared_skeleton_visual(visual_root, skeleton, source_root, node_name, visual_transform, Color.WHITE, false, surface_offset):
			source_root.free()
			continue
		source_root.name = node_name
		source_root.transform = Transform3D(Basis(Vector3.UP, PREVIEW_VISUAL_YAW_OFFSET), Vector3.ZERO) * visual_transform
		_inflate_clothing_visual(source_root, surface_offset)
		visual_root.add_child(source_root)


func _setup_preview_head_attachment_visuals(visual_root: Node3D, skeleton: Skeleton3D) -> void:
	_setup_preview_head_attachment_visual(visual_root, skeleton, draft_appearance.hair_style, draft_appearance.hair_color, "Hair")
	_setup_preview_head_attachment_visual(visual_root, skeleton, draft_appearance.beard_style, draft_appearance.beard_color, "Beard")
	_setup_preview_head_attachment_visual(visual_root, skeleton, draft_appearance.eyebrow_style, draft_appearance.eyebrow_color, "Eyebrows")


func _setup_preview_head_attachment_visual(visual_root: Node3D, skeleton: Skeleton3D, style_resource: Resource, color: Color, slot_label: String) -> void:
	if style_resource == null:
		return
	var visual_scene := style_resource.get("visual_scene") as PackedScene
	if visual_scene == null:
		return
	var instance := visual_scene.instantiate()
	if not (instance is Node3D):
		instance.queue_free()
		return
	var source_root := instance as Node3D
	var node_name := "Appearance%s" % slot_label
	var colorize := bool(style_resource.get("colorize"))
	if skeleton != null and _setup_preview_shared_skeleton_visual(visual_root, skeleton, source_root, node_name, Transform3D.IDENTITY, color, colorize):
		source_root.free()
		return
	source_root.name = node_name
	source_root.transform = Transform3D(Basis(Vector3.UP, PREVIEW_VISUAL_YAW_OFFSET), Vector3.ZERO)
	if colorize:
		_apply_preview_material(source_root, color)
	visual_root.add_child(source_root)


func _setup_preview_shared_skeleton_visual(visual_root: Node3D, skeleton: Skeleton3D, source_root: Node3D, node_name: String, visual_transform: Transform3D, color: Color, colorize: bool, surface_offset: float = 0.0) -> bool:
	var source_meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(source_root, source_meshes)
	if source_meshes.is_empty():
		return false
	var slot_root := Node3D.new()
	slot_root.name = node_name
	slot_root.transform = Transform3D(Basis(Vector3.UP, PREVIEW_VISUAL_YAW_OFFSET), Vector3.ZERO) * visual_transform
	visual_root.add_child(slot_root)
	var copied_mesh_count := 0
	for source_mesh in source_meshes:
		if source_mesh == null or source_mesh.mesh == null:
			continue
		var copied_mesh := _copy_mesh_instance(source_root, source_mesh)
		if colorize:
			_apply_preview_material(copied_mesh, color)
		_inflate_clothing_visual(copied_mesh, surface_offset)
		slot_root.add_child(copied_mesh)
		copied_mesh.skeleton = copied_mesh.get_path_to(skeleton)
		copied_mesh_count += 1
	if copied_mesh_count <= 0:
		slot_root.free()
		return false
	return true


func _copy_mesh_instance(source_root: Node3D, source_mesh: MeshInstance3D) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.name = source_mesh.name
	result.transform = _get_node3d_transform_relative_to_root(source_root, source_mesh)
	result.mesh = source_mesh.mesh
	result.skin = source_mesh.skin
	result.visible = source_mesh.visible
	result.layers = source_mesh.layers
	result.cast_shadow = source_mesh.cast_shadow
	result.material_override = source_mesh.material_override
	for surface_index in range(source_mesh.get_surface_override_material_count()):
		result.set_surface_override_material(surface_index, source_mesh.get_surface_override_material(surface_index))
	for blend_shape_index in range(source_mesh.get_blend_shape_count()):
		result.set_blend_shape_value(blend_shape_index, source_mesh.get_blend_shape_value(blend_shape_index))
	return result


func _inflate_clothing_visual(root: Node, surface_offset: float) -> void:
	if surface_offset <= 0.0:
		return
	if root is MeshInstance3D:
		_inflate_mesh_instance(root as MeshInstance3D, surface_offset)
	for child in root.get_children():
		_inflate_clothing_visual(child, surface_offset)


func _inflate_mesh_instance(mesh_instance: MeshInstance3D, surface_offset: float) -> void:
	if mesh_instance.mesh == null or not (mesh_instance.mesh is ArrayMesh):
		return
	var source_mesh := mesh_instance.mesh as ArrayMesh
	var inflated_mesh := ArrayMesh.new()
	for surface_index in range(source_mesh.get_surface_count()):
		var arrays := source_mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		if not vertices.is_empty() and normals.size() == vertices.size():
			for vertex_index in range(vertices.size()):
				var normal := normals[vertex_index]
				if normal.length_squared() > 0.0001:
					vertices[vertex_index] += normal.normalized() * surface_offset
			arrays[Mesh.ARRAY_VERTEX] = vertices
		inflated_mesh.add_surface_from_arrays(
			source_mesh.surface_get_primitive_type(surface_index),
			arrays,
			source_mesh.surface_get_blend_shape_arrays(surface_index),
			{},
			source_mesh.surface_get_format(surface_index)
		)
		inflated_mesh.surface_set_material(surface_index, source_mesh.surface_get_material(surface_index))
	if inflated_mesh.get_surface_count() == source_mesh.get_surface_count():
		mesh_instance.mesh = inflated_mesh


func _set_preview_clothing_visible(visible_flag: bool) -> void:
	if _preview_model == null:
		return
	var visual_root := _preview_model.get_node_or_null("PreviewCharacterVisual")
	if visual_root == null:
		return
	for child in visual_root.get_children():
		if str(child.name).begins_with("Equipped_") and child is Node3D:
			(child as Node3D).visible = visible_flag


func _set_base_eyebrow_visuals_visible(root: Node, visible_flag: bool) -> void:
	if root == null:
		return
	if root is MeshInstance3D and _is_base_eyebrow_visual(root):
		(root as MeshInstance3D).visible = visible_flag
	for child in root.get_children():
		_set_base_eyebrow_visuals_visible(child, visible_flag)


func _has_visible_base_eyebrow_visual(root: Node) -> bool:
	if root == null:
		return false
	if root is MeshInstance3D and _is_base_eyebrow_visual(root) and (root as MeshInstance3D).visible:
		return true
	for child in root.get_children():
		if _has_visible_base_eyebrow_visual(child):
			return true
	return false


func _is_base_eyebrow_visual(node: Node) -> bool:
	return str(node.name).to_lower().contains("eyebrow")


func _apply_preview_material(root: Node, color: Color) -> void:
	if root is MeshInstance3D:
		var preview_material := StandardMaterial3D.new()
		preview_material.albedo_color = color
		preview_material.roughness = 0.82
		(root as MeshInstance3D).material_override = preview_material
	for child in root.get_children():
		_apply_preview_material(child, color)


func _apply_preview_skin_materials(root: Node) -> bool:
	if draft_appearance == null or not bool(draft_appearance.skin_color_customized):
		return false
	var race: Resource = draft_appearance.character_race if draft_appearance.character_race != null else HUMAN_RACE
	var race_id := str(race.get("race_id")) if race != null else ""
	return SKIN_TEXTURE_BUILDER.apply_custom_skin_materials(root, race_id, _resolve_preview_body_type(_resolve_preview_body_archetype()), draft_appearance.skin_color)


func _apply_current_preview_skin_materials() -> bool:
	if _preview_model == null:
		return false
	var body_root := _preview_model.find_child(PREVIEW_BODY_NODE_NAME, true, false)
	if body_root == null:
		return false
	return _apply_preview_skin_materials(body_root)


func _sync_skin_tone_buttons(color: Color) -> void:
	var normalized_color: Color = SKIN_TEXTURE_BUILDER.get_nearest_skin_tone(color)
	var tones: Array = SKIN_TEXTURE_BUILDER.NATURAL_SKIN_TONES
	for index in range(_skin_tone_buttons.size()):
		var button := _skin_tone_buttons[index]
		if button == null:
			continue
		var tone: Color = tones[index]
		_style_skin_tone_button(button, tone, _skin_colors_match(normalized_color, tone))


func _skin_colors_match(left: Color, right: Color) -> bool:
	return absf(left.r - right.r) < 0.002 and absf(left.g - right.g) < 0.002 and absf(left.b - right.b) < 0.002


func _style_skin_tone_button(button: Button, tone: Color, selected: bool) -> void:
	var border_color := Color(1.0, 1.0, 1.0, 0.95) if selected else Color(0.0, 0.0, 0.0, 0.55)
	var border_width := 3 if selected else 1
	button.text = ""
	button.add_theme_stylebox_override("normal", _make_skin_tone_style(tone, border_color, border_width))
	button.add_theme_stylebox_override("hover", _make_skin_tone_style(tone.lightened(0.08), Color(1.0, 1.0, 1.0, 0.85), 2))
	button.add_theme_stylebox_override("pressed", _make_skin_tone_style(tone.darkened(0.08), Color(1.0, 1.0, 1.0, 0.95), 3))
	button.add_theme_stylebox_override("focus", _make_skin_tone_style(tone, Color(1.0, 1.0, 1.0, 0.95), 2))


func _make_skin_tone_style(tone: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = SKIN_TEXTURE_BUILDER.normalize_skin_color(tone)
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	return style



func _apply_preview_style_color(style_resource: Resource, slot_label: String, color: Color) -> bool:
	if style_resource == null or not bool(style_resource.get("colorize")):
		return true
	if _preview_model == null:
		return true
	var slot_root := _preview_model.find_child("Appearance%s" % slot_label, true, false)
	if slot_root == null:
		return false
	_apply_preview_material(slot_root, color)
	return true


func _collect_mesh_instances(root: Node, meshes: Array[MeshInstance3D]) -> void:
	if root is MeshInstance3D:
		meshes.append(root as MeshInstance3D)
	for child in root.get_children():
		_collect_mesh_instances(child, meshes)


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var skeleton := _find_skeleton(child)
		if skeleton != null:
			return skeleton
	return null


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var animation_player := _find_animation_player(child)
		if animation_player != null:
			return animation_player
	return null


func _get_node3d_transform_relative_to_root(root: Node3D, target: Node3D) -> Transform3D:
	if target == root:
		return Transform3D.IDENTITY
	var current: Node = target
	var result := Transform3D.IDENTITY
	while current != null and current != root:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


func _calculate_local_mesh_bounds(root: Node) -> AABB:
	var result := {"has_bounds": false, "bounds": AABB()}
	_accumulate_local_mesh_bounds(root, Transform3D.IDENTITY, result)
	return result["bounds"]


func _accumulate_local_mesh_bounds(node: Node, parent_transform: Transform3D, result: Dictionary) -> void:
	var local_transform := parent_transform
	if node is Node3D:
		local_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_bounds := _transform_aabb((node as MeshInstance3D).mesh.get_aabb(), local_transform)
		if result["has_bounds"]:
			result["bounds"] = (result["bounds"] as AABB).merge(mesh_bounds)
		else:
			result["bounds"] = mesh_bounds
			result["has_bounds"] = true
	for child in node.get_children():
		_accumulate_local_mesh_bounds(child, local_transform, result)


func _transform_aabb(bounds: AABB, transform: Transform3D) -> AABB:
	var first := true
	var transformed_bounds := AABB()
	for x in [bounds.position.x, bounds.position.x + bounds.size.x]:
		for y in [bounds.position.y, bounds.position.y + bounds.size.y]:
			for z in [bounds.position.z, bounds.position.z + bounds.size.z]:
				var point := transform * Vector3(x, y, z)
				if first:
					transformed_bounds = AABB(point, Vector3.ZERO)
					first = false
				else:
					transformed_bounds = transformed_bounds.expand(point)
	return transformed_bounds


func _contains_live_actor_node(node: Node) -> bool:
	if node == null:
		return false
	if node is HumanoidCharacter or node is CollisionObject3D or node is NavigationAgent3D:
		return true
	for child in node.get_children():
		if _contains_live_actor_node(child):
			return true
	return false


func _clear_preview() -> void:
	if _preview_model != null and is_instance_valid(_preview_model):
		_preview_root.remove_child(_preview_model)
		_preview_model.queue_free()
	_preview_model = null
	_preview_visual_root = null
	_preview_skeleton = null
	_preview_foot_anchor_correction_y = 0.0


func _on_name_changed(_text: String) -> void:
	if mode == MODE_CREATION:
		_rebuild_preview()


func _on_race_selected(_index: int) -> void:
	if draft_appearance == null:
		return
	draft_appearance.character_race = HUMAN_RACE
	draft_appearance.body_archetype = HUMAN_FEMALE_BODY_ARCHETYPE if _resolve_preview_body_type(_resolve_preview_body_archetype()) == VISUAL_BODY_TYPE_FEMALE else HUMAN_MALE_BODY_ARCHETYPE
	_sync_controls_from_draft()
	_rebuild_preview()


func _on_body_type_selected(index: int) -> void:
	if draft_appearance == null:
		return
	var body_type: int = int(_body_type_option.get_item_id(index))
	draft_appearance.visual_body_type = body_type
	draft_appearance.character_race = HUMAN_RACE
	draft_appearance.body_archetype = HUMAN_FEMALE_BODY_ARCHETYPE if body_type == VISUAL_BODY_TYPE_FEMALE else HUMAN_MALE_BODY_ARCHETYPE
	_sync_controls_from_draft()
	_rebuild_preview()


func _on_skin_tone_pressed(index: int) -> void:
	var tones: Array = SKIN_TEXTURE_BUILDER.NATURAL_SKIN_TONES
	if index < 0 or index >= tones.size():
		return
	set_skin_color_value(tones[index])


func _on_skin_color_reset_pressed() -> void:
	reset_skin_color_to_default()


func _on_height_changed(value: float) -> void:
	draft_appearance.height_slider = value
	_rebuild_preview()


func _on_shoulders_changed(value: float) -> void:
	draft_appearance.shoulder_width_slider = value
	_rebuild_preview()


func _on_arm_length_changed(value: float) -> void:
	draft_appearance.arm_length_slider = value
	_rebuild_preview()


func _on_neck_length_changed(value: float) -> void:
	draft_appearance.neck_length_slider = value
	_rebuild_preview()


func _on_hair_selected(_index: int) -> void:
	draft_appearance.hair_style = _get_selected_style(_hair_option)
	_rebuild_preview()


func _on_beard_selected(_index: int) -> void:
	if _resolve_preview_body_type(_resolve_preview_body_archetype()) == VISUAL_BODY_TYPE_FEMALE:
		draft_appearance.beard_style = null
		_sync_controls_from_draft()
		_rebuild_preview()
		return
	draft_appearance.beard_style = _get_selected_style(_beard_option)
	_rebuild_preview()


func _on_hair_color_changed(color: Color) -> void:
	if draft_appearance == null:
		return
	draft_appearance.hair_color = color
	draft_appearance.eyebrow_color = color
	var hair_updated := _apply_preview_style_color(draft_appearance.hair_style, "Hair", color)
	var eyebrow_updated := _apply_preview_style_color(draft_appearance.eyebrow_style, "Eyebrows", color)
	if not hair_updated or not eyebrow_updated:
		_rebuild_preview()


func _on_beard_color_changed(color: Color) -> void:
	if draft_appearance == null:
		return
	if _resolve_preview_body_type(_resolve_preview_body_archetype()) == VISUAL_BODY_TYPE_FEMALE:
		return
	draft_appearance.beard_color = color
	if not _apply_preview_style_color(draft_appearance.beard_style, "Beard", color):
		_rebuild_preview()


func _on_show_clothes_toggled(button_pressed: bool) -> void:
	set_preview_clothes_visible(button_pressed)


func _on_face_view_toggled(button_pressed: bool) -> void:
	set_preview_view_mode(VIEW_FACE if button_pressed else VIEW_FULL_BODY)


func _on_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		zoom_preview_by_steps(1.0)
		accept_event()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		zoom_preview_by_steps(-1.0)
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_preview_dragging = event.pressed
		return
	if event is InputEventMouseMotion and _preview_dragging:
		rotate_preview_by(-event.relative.x * PREVIEW_DRAG_YAW_SCALE)
		pitch_preview_by(-event.relative.y * PREVIEW_DRAG_PITCH_SCALE)


func _on_save_pressed() -> void:
	if draft_appearance == null:
		return
	_apply_body_type_style_constraints(_resolve_preview_body_type(_resolve_preview_body_archetype()))
	save_requested.emit(target_actor, draft_appearance.make_copy())
	close_editor()


func _on_cancel_pressed() -> void:
	cancel_requested.emit()
	close_editor()
