extends Control
## Standalone inspection: real disposable actors, never population/save mutations.
const CATALOG = preload("res://tools/outfitter/outfitter_catalog.gd")
const STAGE = preload("res://tools/outfitter/outfitter_stage.gd")
var catalog = CATALOG.new()
var actor: WorldActor
var stage
var race_select: OptionButton
var body_select: OptionButton
var animation_select: OptionButton
var slot_select: OptionButton
var equipment_list: ItemList
var search: LineEdit
var status: Label
var body_note: Label
var ruler_toggle: CheckButton
var selected_animation := "Idle"
var selected_race: Resource
var selected_body: Resource
var selected_slot := "weapon"
var view_mode := "Full body"
var _visible_items: Array[ItemDefinition] = []
var _body_options: Array[Resource] = []
var _slots: Array[String] = []
var _loadout: Dictionary = {}
var _camera_initialized := false

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
	animation_select = _option(sidebar, "Animation · loops automatically")
	animation_select.item_selected.connect(func(i): select_animation(animation_select.get_item_text(i)))
	slot_select = _option(sidebar, "Equipment slot")
	slot_select.item_selected.connect(func(i): select_slot(_slots[i]))
	search = LineEdit.new()
	search.placeholder_text = "Search all equipment…"
	search.text_changed.connect(filter_equipment)
	sidebar.add_child(search)
	equipment_list = ItemList.new()
	equipment_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	equipment_list.custom_minimum_size.y = 80
	equipment_list.item_selected.connect(_select_item_row)
	sidebar.add_child(equipment_list)
	var clear := Button.new()
	clear.text = "None · remove from selected slot"
	clear.pressed.connect(func(): equip_item(null, selected_slot))
	sidebar.add_child(clear)
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
	_label(right, "Drag to orbit · Scroll to zoom · Gray items cannot equip in this slot")

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
	selected_race = catalog.races[index]
	race_select.select(index)
	_body_options = catalog.bodies(selected_race)
	body_select.clear()
	for body in _body_options:
		body_select.add_item("Shared body" if _body_options.size() == 1 else body.display_name)
	body_note.text = "One authored body; no separate sex variants." if _body_options.size() == 1 else "Canonical authored body variants."
	var previous_type: int = selected_body.visual_body_type if selected_body != null else 2
	var body_index := 0
	for i in _body_options.size():
		if _body_options[i].visual_body_type == previous_type: body_index = i
	select_body(body_index)

func select_body(index: int) -> void:
	if index < 0 or index >= _body_options.size(): return
	selected_body = _body_options[index]
	body_select.select(index)
	stage.tracking = null
	if is_instance_valid(actor):
		stage.world.remove_child(actor)
		actor.queue_free()
	actor = catalog.create_actor(selected_race, selected_body)
	if actor == null:
		status.text = "No production realizer for this body."
		return
	actor.name = "OutfitterActor"
	stage.world.add_child(actor)
	# Stop gameplay driving; animation descendants keep processing normally.
	actor.set_process(false)
	actor.set_physics_process(false)
	# Capture the unequipped body once: held gear must not move the studio datum.
	stage.set_body_reference(actor.get_body_projection().get_visual_local_bounds())
	for slot in _loadout:
		var item: ItemDefinition = _loadout[slot]
		if actor.get_equipment().can_equip_item_to_slot(item, slot): actor.equip_item_to_slot(item, slot)
	_refresh_animations()
	_slots.clear()
	for item in catalog.items:
		if not _slots.has(item.equip_slot): _slots.append(item.equip_slot)
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

func filter_equipment(query: String) -> void:
	_visible_items.clear()
	equipment_list.clear()
	var needle := query.strip_edges().to_lower()
	for item in catalog.items:
		if not needle.is_empty() and not (item.display_name + " " + item.item_id + " " + item.equip_slot).to_lower().contains(needle): continue
		_visible_items.append(item)
		var reason := incompatibility(item, selected_slot)
		var index := equipment_list.add_item(item.display_name + (" · " + item.equip_slot if not reason.is_empty() else ""))
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
	equip_item(_visible_items[index], selected_slot)

func equip_item(item: ItemDefinition, slot: String) -> bool:
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
	# Production wearables can rebuild the complete visual and AnimationPlayer.
	_refresh_animations()
	_update_status()
	if view_mode != "Full body": _refresh_hand_target(false)
	filter_equipment(search.text)
	return actor.get_equipped_item(slot) == item

func _update_status() -> void:
	var item := actor.get_equipped_item(selected_slot)
	status.text = selected_race.get_slot_label(selected_slot) + ": " + (item.display_name if item != null else "None")
	if item != null and not actor.get_body_projection() is HumanoidBodyProjection:
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
