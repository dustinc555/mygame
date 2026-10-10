extends Control
## Standalone inspection: real disposable actors, never population/save mutations.
const CATALOG = preload("res://tools/outfitter/outfitter_catalog.gd")
const STAGE = preload("res://tools/outfitter/outfitter_stage.gd")
const FIT_LOADER = preload("res://tools/outfitter/outfitter_fit_loader.gd")
const BONE_SLIDER_LABELS := {
	"height_slider": "Height",
	"shoulder_width_slider": "Shoulders",
	"arm_length_slider": "Arm Length",
	"neck_length_slider": "Neck Length",
}
var catalog = CATALOG.new()
var actor: WorldActor
var stage
var race_select: OptionButton
var body_select: OptionButton
var build_select: OptionButton
var build_row: HBoxContainer
var animation_select: OptionButton
var slot_select: OptionButton
var equipment_list: ItemList
var remove_button: Button
var search: LineEdit
var status: Label
var body_note: Label
var ruler_toggle: CheckButton
var bone_sliders: Dictionary[String, HSlider] = {}
var bone_slider_values: Dictionary[String, Label] = {}
var reset_bones_button: Button
var _body_slider_values: Dictionary[String, float] = {}
var selected_animation := "Idle"
var selected_race: Resource
var selected_body: Resource
var selected_build := "regular"
var selected_slot := "weapon"
var view_mode := "Full body"
var _visible_items: Array[ItemDefinition] = []
var _body_options: Array[Resource] = []
var _build_options: Array[String] = []
var _slots: Array[String] = []
var _loadout: Dictionary = {}
var _camera_initialized := false
var _fit_loader
var _selection_generation := 0
var _slot_generations: Dictionary[String, int] = {}
var _building := false
var _pending_build := -1

func _enter_tree() -> void:
	_fit_loader = FIT_LOADER.new()
	if is_instance_valid(equipment_list): _resume_selection.call_deferred()

func _resume_selection() -> void:
	if is_inside_tree(): _request_build(_pending_build if _pending_build >= 0 else _build_options.find(selected_build))

func _exit_tree() -> void:
	_selection_generation += 1
	_building = false
	_fit_loader.close()

func _ready() -> void:
	_build_ui()
	for race in catalog.races: race_select.add_item(race.display_name)
	if not catalog.races.is_empty(): select_race(0)

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 14)
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	margin.add_child(columns)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 310
	columns.add_child(sidebar)
	_label(sidebar, "Outfitter").add_theme_font_size_override("font_size", 26)
	race_select = _option(sidebar, "Race")
	race_select.item_selected.connect(select_race)
	body_select = _option(sidebar, "Sex / body")
	body_select.item_selected.connect(select_body)
	body_note = _label(sidebar, "")
	body_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	build_row = HBoxContainer.new()
	sidebar.add_child(build_row)
	build_select = _option(build_row, "Build")
	build_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	build_select.item_selected.connect(_request_build)
	animation_select = _option(sidebar, "Animation · loops automatically")
	animation_select.item_selected.connect(func(i): select_animation(animation_select.get_item_text(i)))
	slot_select = _option(sidebar, "Equipment slot")
	slot_select.item_selected.connect(func(i): select_slot(_slots[i]))
	search = LineEdit.new()
	search.placeholder_text = "Search selected slot…"
	search.text_changed.connect(filter_equipment)
	sidebar.add_child(search)
	equipment_list = ItemList.new()
	equipment_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	equipment_list.custom_minimum_size.y = 80
	equipment_list.item_selected.connect(_select_item_row)
	sidebar.add_child(equipment_list)
	remove_button = Button.new()
	remove_button.text = "None · remove from selected slot"
	remove_button.pressed.connect(func(): _request_equip(null, selected_slot))
	sidebar.add_child(remove_button)
	status = _label(sidebar, "")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.y = 45
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	var studio := HBoxContainer.new()
	studio.size_flags_vertical = Control.SIZE_EXPAND_FILL
	studio.add_theme_constant_override("separation", 6)
	right.add_child(studio)
	stage = STAGE.new()
	studio.add_child(stage)
	studio.add_child(stage.ruler)
	studio.move_child(stage.ruler, 0)
	var views := HBoxContainer.new()
	right.add_child(views)
	for view in ["Full body", "Right hand", "Left hand"]:
		var button := Button.new()
		button.text = view
		button.pressed.connect(func(): set_view_mode(view))
		views.add_child(button)
	ruler_toggle = CheckButton.new()
	ruler_toggle.text = "Height ruler"
	ruler_toggle.button_pressed = true
	ruler_toggle.toggled.connect(func(enabled): stage.ruler.visible = enabled)
	views.add_child(ruler_toggle)
	_label(right, "Drag to orbit · Scroll to zoom · Gray items do not fit this body")
	_build_bone_controls(columns)

func _build_bone_controls(columns: HBoxContainer) -> void:
	var panel := VBoxContainer.new()
	panel.name = "BodySliders"
	panel.custom_minimum_size.x = 200
	panel.add_theme_constant_override("separation", 12)
	columns.add_child(panel)
	_label(panel, "Body proportions").add_theme_font_size_override("font_size", 20)
	for property: String in BONE_SLIDER_LABELS:
		var group := VBoxContainer.new()
		panel.add_child(group)
		var heading := HBoxContainer.new()
		group.add_child(heading)
		_label(heading, BONE_SLIDER_LABELS[property]).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bone_slider_values[property] = _label(heading, "0.00")
		var slider := HSlider.new()
		slider.name = property
		slider.min_value = -1.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(_on_bone_slider_changed.bind(property))
		group.add_child(slider)
		bone_sliders[property] = slider
		_body_slider_values[property] = 0.0
	reset_bones_button = Button.new()
	reset_bones_button.text = "Reset proportions"
	reset_bones_button.pressed.connect(reset_body_proportions)
	panel.add_child(reset_bones_button)
	var note := _label(panel, "Same controls as the character creator. Clothes follow the bones.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _on_bone_slider_changed(value: float, property: String) -> void:
	_body_slider_values[property] = value
	bone_slider_values[property].text = "%.2f" % value
	_apply_body_sliders()

func _apply_body_sliders() -> void:
	if not is_instance_valid(actor): return
	var body := actor.get_body_projection() as HumanoidBodyProjection
	if body == null: return
	for property: String in _body_slider_values:
		actor.appearance_data.set(property, _body_slider_values[property])
	body.configure_appearance(actor.appearance_data)
	body.refresh_body_proportions()

func reset_body_proportions() -> void:
	for property: String in bone_sliders:
		_body_slider_values[property] = 0.0
		bone_sliders[property].set_value_no_signal(0.0)
		bone_slider_values[property].text = "0.00"
	_apply_body_sliders()

func _sync_bone_controls() -> void:
	var supported := is_instance_valid(actor) and actor.get_body_projection() is HumanoidBodyProjection
	for slider: HSlider in bone_sliders.values(): slider.editable = supported and not _building
	reset_bones_button.disabled = not supported or _building

func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label

func _option(parent: Node, label: String) -> OptionButton:
	_label(parent, label)
	var option := OptionButton.new()
	option.fit_to_longest_item = false
	parent.add_child(option)
	return option

func select_race(index: int) -> void:
	if index < 0 or index >= catalog.races.size(): return
	var previous_type: int = selected_body.visual_body_type if selected_body != null else 2
	_show_race(index)
	var body_index := 0
	for i in _body_options.size():
		if _body_options[i].visual_body_type == previous_type: body_index = i
	select_body(body_index)

func _show_race(index: int) -> void:
	selected_race = catalog.races[index]
	race_select.select(index)
	_body_options = catalog.bodies(selected_race)
	body_select.clear()
	for body in _body_options:
		body_select.add_item("Shared body" if _body_options.size() == 1 else body.display_name)
	body_note.text = "One authored body; no separate sex variants." if _body_options.size() == 1 else "Canonical authored body variants."


func select_body(index: int) -> void:
	if index < 0 or index >= _body_options.size(): return
	_show_body(index)
	_request_build(_build_options.find(selected_build))

func _show_body(index: int) -> void:
	selected_body = _body_options[index]
	body_select.select(index)
	_build_options = catalog.builds(selected_body)
	build_select.clear()
	for build in _build_options: build_select.add_item(build.capitalize())
	build_row.visible = _build_options.size() > 1
	if not _build_options.has(selected_build): selected_build = "regular"
	build_select.select(_build_options.find(selected_build))

func _request_build(index: int) -> void:
	if index < 0 or index >= _build_options.size(): return
	_selection_generation += 1
	var generation := _selection_generation
	_pending_build = index
	_set_building(true)
	var paths := _fit_paths(_loadout.values(), _build_options[index])
	if not await _prepare_fits(paths, generation):
		if is_inside_tree() and generation == _selection_generation:
			_pending_build = -1
			_set_building(false)
			_restore_active_selection()
		return
	select_build(index)
	_warm_fits()

func _restore_active_selection() -> void:
	if not is_instance_valid(actor): return
	var appearance: CharacterAppearanceData = actor.get("appearance_data")
	for build in CATALOG.BUILD_CONTEXTS:
		var context: Dictionary = CATALOG.BUILD_CONTEXTS[build]
		if appearance.visual_age_years == context.age_years and appearance.visual_toughness_level == context.toughness_level:
			selected_build = build
	_show_race(catalog.races.find(appearance.character_race))
	_show_body(_body_options.find(appearance.body_archetype))
	filter_equipment(search.text)

func _set_building(value: bool) -> void:
	_building = value
	remove_button.disabled = value
	for index in equipment_list.item_count: equipment_list.set_item_disabled(index, value)
	_sync_bone_controls()

func _prepare_fits(paths: Array[String], generation: int) -> bool:
	var tree := get_tree()
	var loader = _fit_loader
	loader.request(paths, tree, true)
	if not loader.ready_for(paths): status.text = "Loading clothing…"
	while not loader.ready_for(paths):
		await tree.process_frame
		if not is_inside_tree() or generation != _selection_generation: return false
	if not is_inside_tree() or generation != _selection_generation: return false
	var failed: String = loader.failed_path(paths)
	if not failed.is_empty():
		status.text = "Could not load clothing: " + failed.get_file()
		return false
	return true

func _fit_paths(items: Array, build: String) -> Array[String]:
	var paths: Array[String] = []
	if selected_body == null: return paths
	var context: Dictionary = CATALOG.BUILD_CONTEXTS[build]
	var body_scene: PackedScene = selected_body.get_visual_scene_for_context(context.age_years, context.toughness_level)
	if body_scene == null: return paths
	for item: ItemDefinition in items:
		if item == null or not item.fits_race(selected_race.race_id): continue
		var definition := item.get_equipment_visual_for_body_archetype(selected_body)
		if definition == null: continue
		var path: String = definition.body_fits.get(body_scene.resource_path, "")
		if not path.is_empty() and not paths.has(path): paths.append(path)
	return paths

func _warm_fits() -> void:
	if not is_inside_tree() or selected_body == null: return
	# Prepare visible choices and the worn outfit's other builds, not the whole catalog.
	_fit_loader.request(_fit_paths(_visible_items, selected_build), get_tree())
	for build in _build_options:
		_fit_loader.request(_fit_paths(_loadout.values(), build), get_tree())

func select_build(index: int) -> void:
	if index < 0 or index >= _build_options.size(): return
	_selection_generation += 1
	_pending_build = -1
	_set_building(false)
	selected_build = _build_options[index]
	build_select.select(index)
	stage.tracking = null
	if is_instance_valid(actor):
		stage.world.remove_child(actor)
		actor.queue_free()
	actor = catalog.create_actor(selected_race, selected_body, selected_build)
	if actor == null:
		status.text = "No production realizer for this body."
		_sync_bone_controls()
		return
	var appearance: CharacterAppearanceData = actor.get("appearance_data")
	if appearance != null:
		for property: String in _body_slider_values: appearance.set(property, _body_slider_values[property])
	actor.name = "OutfitterActor"
	stage.world.add_child(actor)
	_sync_bone_controls()
	# Stop gameplay driving; animation descendants keep processing normally.
	actor.set_process(false)
	actor.set_physics_process(false)
	# Capture the unequipped body once: held gear must not move the studio datum.
	stage.set_body_reference(actor.get_body_projection().get_visual_local_bounds())
	actor.get_body_projection().set_preview_ground_height(stage.floor_mesh.global_position.y)
	actor.get_equipment().begin_equipment_update_batch()
	for slot in _loadout:
		var item: ItemDefinition = _loadout[slot]
		if actor.get_equipment().can_equip_item_to_slot(item, slot): actor.equip_item_to_slot(item, slot)
	actor.get_equipment().end_equipment_update_batch()
	_refresh_animations()
	_slots.clear()
	for item in catalog.items:
		if not _slots.has(item.equip_slot): _slots.append(item.equip_slot)
		if item.alternate_equip_slots != null:
			for slot in item.alternate_equip_slots:
				if not _slots.has(slot): _slots.append(slot)
	_slots.sort()
	slot_select.clear()
	for slot in _slots: slot_select.add_item(selected_race.get_slot_label(slot))
	select_slot(selected_slot if _slots.has(selected_slot) else _slots[0])
	if not _camera_initialized:
		stage.frame_body(actor.get_body_projection())
		_camera_initialized = true
	if view_mode != "Full body": _refresh_hand_target(false)

func _refresh_animations() -> void:
	animation_select.clear()
	var player := actor.get_body_projection().get_primary_animation_player()
	if player == null: return
	for clip in player.get_animation_list():
		if clip != "RESET": animation_select.add_item(clip)
	# Retain even an unavailable choice across races; do not silently replace it.
	if not player.has_animation(selected_animation):
		animation_select.add_item(selected_animation + " (unavailable)")
		animation_select.select(animation_select.item_count - 1)
		player.stop()
	else: select_animation(selected_animation)

func select_animation(clip: String) -> bool:
	var player := actor.get_body_projection().get_primary_animation_player()
	if player == null or not player.has_animation(clip): return false
	selected_animation = clip
	# Private animation copy prevents changing imported/shared source loop modes.
	var source := player.get_animation(clip)
	if source.loop_mode != Animation.LOOP_LINEAR:
		var copy := source.duplicate() as Animation
		copy.loop_mode = Animation.LOOP_LINEAR
		var split := clip.rfind("/")
		var library_name := clip.substr(0, split) if split >= 0 else ""
		var key := clip.substr(split + 1)
		var library := player.get_animation_library(library_name).duplicate() as AnimationLibrary
		library.remove_animation(key)
		library.add_animation(key, copy)
		player.remove_animation_library(library_name)
		player.add_animation_library(library_name, library)
	player.play(clip)
	player.advance(0)
	for i in animation_select.item_count:
		if animation_select.get_item_text(i) == clip: animation_select.select(i)
	return true

func select_slot(slot: String) -> void:
	selected_slot = slot
	if _slots.has(slot): slot_select.select(_slots.find(slot))
	filter_equipment(search.text)
	_update_status()
	_warm_fits()

func filter_equipment(query: String) -> void:
	_visible_items.clear()
	equipment_list.clear()
	var needle := query.strip_edges().to_lower()
	for item in catalog.items:
		if not item.can_equip_to_slot(selected_slot): continue
		if not needle.is_empty() and not (item.display_name + " " + item.item_id + " " + item.equip_slot).to_lower().contains(needle): continue
		_visible_items.append(item)
		var reason := incompatibility(item, selected_slot)
		var index := equipment_list.add_item(item.display_name)
		equipment_list.set_item_disabled(index, _building)
		equipment_list.set_item_tooltip(index, reason if not reason.is_empty() else "Equip " + item.display_name)
		if not reason.is_empty(): equipment_list.set_item_custom_fg_color(index, Color(0.52, 0.55, 0.6))
		if actor != null and actor.get_equipped_item(selected_slot) == item: equipment_list.select(index)

func incompatibility(item: ItemDefinition, slot: String) -> String:
	if actor == null: return "No actor"
	if actor.get_equipment().can_equip_item_to_slot(item, slot): return ""
	if not item.fits_race(selected_race.race_id): return "Not fitted for " + selected_race.display_name
	if not actor.get_equipment_slot_names().has(slot): return "Body has no " + slot + " slot"
	return "Uses " + item.equip_slot + "; select that slot"

func _select_item_row(index: int) -> void:
	if index >= 0 and index < _visible_items.size(): _request_equip(_visible_items[index], selected_slot)

func _request_equip(item: ItemDefinition, slot: String) -> void:
	if _building or not is_instance_valid(actor): return
	var generation := _selection_generation
	var slot_generation: int = _slot_generations.get(slot, 0) + 1
	_slot_generations[slot] = slot_generation
	if item != null and not incompatibility(item, slot).is_empty():
		status.text = incompatibility(item, slot)
		return
	if not await _prepare_fits(_fit_paths([item], selected_build), generation): return
	if _slot_generations.get(slot) != slot_generation: return
	equip_item(item, slot)
	_warm_fits()

func equip_item(item: ItemDefinition, slot: String) -> bool:
	if not is_instance_valid(actor): return false
	var previous_player := actor.get_body_projection().get_primary_animation_player()
	var previous_player_id := previous_player.get_instance_id() if previous_player != null else 0
	if item != null:
		var reason := incompatibility(item, slot)
		if not reason.is_empty():
			status.text = reason
			return false
		actor.equip_item_to_slot(item, slot)
		_loadout[slot] = item
	else:
		actor.unequip_item_from_slot(slot)
		_loadout.erase(slot)
	# Ordinary equipment keeps the live player and the exact inspection frame.
	var player := actor.get_body_projection().get_primary_animation_player()
	if player == null or player.get_instance_id() != previous_player_id: _refresh_animations()
	_update_status()
	if view_mode != "Full body": _refresh_hand_target(false)
	equipment_list.deselect_all()
	var selected_index := _visible_items.find(actor.get_equipped_item(selected_slot))
	if selected_index >= 0: equipment_list.select(selected_index)
	return actor.get_equipped_item(slot) == item

func _update_status() -> void:
	if _building:
		status.text = "Loading clothing…"
		return
	if not is_instance_valid(actor): return
	var item := actor.get_equipped_item(selected_slot)
	status.text = selected_race.get_slot_label(selected_slot) + ": " + (item.display_name if item != null else "None")
	var body := actor.get_body_projection()
	if item != null and body != null and body.has_method("get_clothing_fit_error"):
		var error := str(body.call("get_clothing_fit_error", selected_slot))
		if not error.is_empty():
			status.text += "\nClothing fit failed (not shown): " + error
	if item != null and not body is HumanoidBodyProjection:
		status.text += "\nProduction body has no held-item visual projection."

func set_view_mode(mode: String) -> bool:
	view_mode = mode
	var body := actor.get_body_projection()
	if mode == "Full body":
		stage.frame_body(body)
		return true
	return _refresh_hand_target(true)

func _refresh_hand_target(reframe: bool) -> bool:
	var body := actor.get_body_projection()
	var socket := body.get_visual_root().find_child("RightHandGrip" if view_mode == "Right hand" else "LeftHandGrip", true, false) as Node3D
	if not stage.track_hand(socket, reframe):
		status.text = "No hand socket authored for this body."
		return false
	return true
