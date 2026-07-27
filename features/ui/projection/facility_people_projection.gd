extends RefCounted

class_name FacilityPeopleProjection

const ASSIGNMENT_SERVICE_ID := &"settlement"
const QUERY_METHOD := &"get_facility_people_snapshot"
const CACHE_MSEC := 250

var _assignment_service: Node
var _cached_key := ""
var _cached_at_msec := -CACHE_MSEC
var _cached_snapshot: Dictionary
var _window: Control


func setup(assignment_service: Node) -> void:
	_assignment_service = assignment_service
	_cached_key = ""
	_cached_snapshot = {}


func get_snapshot(target) -> Dictionary:
	var identity := _target_identity(target)
	var cache_key := "%s|%s|%s" % [identity.get("building_id", ""), identity.get("facility_id", ""), identity.get("settlement_id", "")]
	var now := Time.get_ticks_msec()
	if cache_key == _cached_key and now - _cached_at_msec < CACHE_MSEC:
		return _cached_snapshot.duplicate(true)
	var snapshot: Dictionary = {}
	if _assignment_service != null and _assignment_service.has_method(QUERY_METHOD):
		var queried = _assignment_service.call(
			QUERY_METHOD,
			str(identity.get("building_id", "")),
			str(identity.get("facility_id", "")),
			str(identity.get("settlement_id", ""))
		)
		if queried is Dictionary:
			snapshot = (queried as Dictionary).duplicate(true)
	if snapshot.is_empty():
		snapshot = _fallback_snapshot(target, identity)
	_cached_key = cache_key
	_cached_at_msec = now
	_cached_snapshot = _normalize_snapshot(snapshot, identity)
	return _cached_snapshot.duplicate(true)


func get_action_label(target) -> String:
	var snapshot := get_snapshot(target)
	return "People %d / %d" % [int(snapshot.get("filled_role_count", 0)), int(snapshot.get("role_count", 0))]


func create_window(hud_layer: CanvasLayer) -> Control:
	var window := FacilityPeopleWindow.new()
	window.name = "FacilityPeopleWindow"
	window.setup(self)
	hud_layer.add_child(window)
	window.visible = false
	return window


func show_for_target(hud_layer: CanvasLayer, target) -> void:
	if _window == null or not is_instance_valid(_window):
		_window = create_window(hud_layer)
	_window.call("show_for_target", target)


func _normalize_snapshot(snapshot: Dictionary, identity: Dictionary) -> Dictionary:
	var rows: Array[Dictionary] = []
	var unique_people: Dictionary = {}
	var filled_role_count := 0
	for raw_row in snapshot.get("rows", []):
		if not (raw_row is Dictionary):
			continue
		var source_row := raw_row as Dictionary
		var actor_id := str(source_row.get("actor_id", source_row.get("character_id", ""))).strip_edges()
		var character_name := str(source_row.get("character_name", source_row.get("name", ""))).strip_edges()
		var filled := not actor_id.is_empty() or not character_name.is_empty()
		if filled:
			filled_role_count += 1
			var unique_id := actor_id if not actor_id.is_empty() else "name:%s" % character_name
			unique_people[unique_id] = character_name if not character_name.is_empty() else actor_id
		rows.append({
			"slot_id": str(source_row.get("slot_id", "")),
			"group": _normalize_group(str(source_row.get("group", source_row.get("kind", "employment")))),
			"role": _role_label(source_row),
			"actor_id": actor_id,
			"character_name": character_name if filled else "Vacant",
			"source": _source_label(str(source_row.get("source", ""))),
		})
	rows.sort_custom(_sort_rows)
	var role_count := maxi(rows.size(), int(snapshot.get("role_count", snapshot.get("capacity", rows.size()))))
	return {
		"building_id": str(identity.get("building_id", "")),
		"facility_id": str(identity.get("facility_id", "")),
		"settlement_id": str(identity.get("settlement_id", "")),
		"display_name": str(snapshot.get("display_name", _target_display_name(identity))),
		"rows": rows,
		"role_count": role_count,
		"filled_role_count": mini(filled_role_count, role_count),
		"unique_person_count": unique_people.size(),
		"unique_people": unique_people.values(),
		"assignment_state_available": not snapshot.get("fallback", false),
	}


func _fallback_snapshot(target, identity: Dictionary) -> Dictionary:
	var rows: Array[Dictionary] = []
	var facility := _target_facility(target)
	if facility != null and facility.has_method("get_assignment_slot_specs"):
		var authored_specs = facility.call("get_assignment_slot_specs")
		if authored_specs is Array:
			for raw_spec in authored_specs:
				if not (raw_spec is Dictionary):
					continue
				var spec := raw_spec as Dictionary
				rows.append(_vacant_row(
					_normalize_group(str(spec.get("assignment_domain", "employment"))),
					_role_label(spec),
					str(spec.get("slot_id", ""))
				))
	if not rows.is_empty():
		return {"display_name": _target_display_name(identity), "rows": rows, "fallback": true}
	var housing_capacity := _int_property(target, "housing_capacity")
	if housing_capacity <= 0 and target != null and target.has_method("get_building_seed"):
		var seed = target.call("get_building_seed")
		if seed is Dictionary:
			housing_capacity = maxi(0, int((seed as Dictionary).get("housing_capacity", 0)))
	if housing_capacity <= 0 and facility != null:
		housing_capacity = _int_property(facility, "housing_capacity")
	for index in range(maxi(0, housing_capacity)):
		rows.append(_vacant_row("residence", "Resident", "residence.%d" % (index + 1)))
	return {
		"display_name": _target_display_name(identity),
		"rows": rows,
		"fallback": true,
	}


func _vacant_row(group: String, role: String, slot_id: String) -> Dictionary:
	return {"group": group, "role": role, "slot_id": slot_id, "character_name": "", "actor_id": "", "source": ""}


func _target_identity(target) -> Dictionary:
	var facility := _target_facility(target)
	var identity := {
		"building_id": _string_property(target, "building_id"),
		"facility_id": _string_property(target, "facility_id"),
		"settlement_id": _string_property(target, "settlement_id"),
		"display_name": _string_property(target, "display_name"),
	}
	if facility != null:
		if str(identity["facility_id"]).is_empty() and facility.has_method("get_facility_id"):
			identity["facility_id"] = str(facility.call("get_facility_id"))
		if str(identity["building_id"]).is_empty():
			identity["building_id"] = _string_property(facility, "building_id")
		if str(identity["settlement_id"]).is_empty():
			identity["settlement_id"] = _string_property(facility, "settlement_id")
	return identity


func _target_facility(target) -> Node:
	if target is Node and (target.is_in_group("settlement_facility") or target.has_method("get_facility_id")):
		return target as Node
	if not (target is Node):
		return null
	var current := (target as Node).get_parent()
	while current != null:
		if current.is_in_group("settlement_facility") or current.has_method("get_facility_id"):
			return current
		current = current.get_parent()
	return null


func _target_display_name(identity: Dictionary) -> String:
	var display_name := str(identity.get("display_name", "")).strip_edges()
	return display_name if not display_name.is_empty() else "Facility"


func _role_label(row: Dictionary) -> String:
	var label := str(row.get("role", row.get("role_label", row.get("role_id", "Role")))).strip_edges()
	return label.capitalize() if label == label.to_lower() else label


func _source_label(source: String) -> String:
	match source.strip_edges().to_lower():
		"named", "authored":
			return "Named"
		"auto", "automatic", "generated":
			return "Auto"
	return ""


func _normalize_group(group: String) -> String:
	return "residence" if group.strip_edges().to_lower() in ["residence", "resident", "housing", "home"] else "employment"


func _sort_rows(a: Dictionary, b: Dictionary) -> bool:
	var a_key := "%s:%s:%s" % [a.get("group", ""), a.get("role", ""), a.get("slot_id", "")]
	var b_key := "%s:%s:%s" % [b.get("group", ""), b.get("role", ""), b.get("slot_id", "")]
	return a_key < b_key


func _string_property(target, property_name: String) -> String:
	if target == null:
		return ""
	var value = target.get(property_name)
	return "" if value == null else str(value).strip_edges()


func _int_property(target, property_name: String) -> int:
	if target == null:
		return 0
	var value = target.get(property_name)
	return 0 if value == null else int(value)


class FacilityPeopleWindow extends PanelContainer:
	const WINDOW_SIZE := Vector2(430.0, 330.0)
	const REFRESH_SECONDS := 0.25

	var projection: FacilityPeopleProjection
	var target
	var title_label: Label
	var summary_label: Label
	var availability_label: Label
	var unique_people_label: Label
	var rows_root: VBoxContainer
	var _refresh_remaining := 0.0


	func setup(source: FacilityPeopleProjection) -> void:
		projection = source


	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = WINDOW_SIZE
		_build_layout()
		_fit_to_viewport()


	func _process(delta: float) -> void:
		if not visible or target == null:
			return
		_refresh_remaining -= delta
		if _refresh_remaining <= 0.0:
			_refresh_remaining = REFRESH_SECONDS
			_render()


	func show_for_target(selected_target) -> void:
		target = selected_target
		visible = target != null
		if title_label == null:
			call_deferred("show_for_target", selected_target)
			return
		_render()
		_fit_to_viewport()


	func _build_layout() -> void:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.075, 0.07, 0.065, 0.985)
		style.border_color = Color(0.43, 0.34, 0.22, 1.0)
		style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		add_theme_stylebox_override("panel", style)
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 12)
		margin.add_theme_constant_override("margin_top", 10)
		margin.add_theme_constant_override("margin_right", 12)
		margin.add_theme_constant_override("margin_bottom", 12)
		add_child(margin)
		var root := VBoxContainer.new()
		root.add_theme_constant_override("separation", 6)
		margin.add_child(root)
		var header := HBoxContainer.new()
		root.add_child(header)
		title_label = Label.new()
		title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_label.add_theme_font_size_override("font_size", 16)
		title_label.add_theme_color_override("font_color", Color(0.92, 0.84, 0.66, 1.0))
		header.add_child(title_label)
		var back := Button.new()
		back.text = "Back"
		back.focus_mode = Control.FOCUS_NONE
		back.pressed.connect(hide)
		header.add_child(back)
		summary_label = Label.new()
		summary_label.add_theme_color_override("font_color", Color(0.78, 0.66, 0.42, 1.0))
		root.add_child(summary_label)
		availability_label = Label.new()
		availability_label.add_theme_font_size_override("font_size", 9)
		availability_label.add_theme_color_override("font_color", Color(0.58, 0.56, 0.5, 1.0))
		root.add_child(availability_label)
		unique_people_label = Label.new()
		unique_people_label.add_theme_font_size_override("font_size", 10)
		unique_people_label.add_theme_color_override("font_color", Color(0.84, 0.79, 0.67, 1.0))
		unique_people_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		root.add_child(unique_people_label)
		var columns := HBoxContainer.new()
		columns.add_theme_constant_override("separation", 8)
		root.add_child(columns)
		for column in [["Role", 145.0], ["Person", 170.0], ["Source", 60.0]]:
			var label := Label.new()
			label.text = str(column[0])
			label.custom_minimum_size.x = float(column[1])
			label.add_theme_font_size_override("font_size", 9)
			label.add_theme_color_override("font_color", Color(0.58, 0.56, 0.5, 1.0))
			columns.add_child(label)
		var scroll := ScrollContainer.new()
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		root.add_child(scroll)
		rows_root = VBoxContainer.new()
		rows_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rows_root.add_theme_constant_override("separation", 2)
		scroll.add_child(rows_root)


	func _render() -> void:
		if projection == null or rows_root == null:
			return
		for child in rows_root.get_children():
			child.queue_free()
		var snapshot := projection.get_snapshot(target)
		title_label.text = "%s People" % str(snapshot.get("display_name", "Facility"))
		summary_label.text = "%d unique people  |  %d / %d roles filled" % [snapshot.get("unique_person_count", 0), snapshot.get("filled_role_count", 0), snapshot.get("role_count", 0)]
		var unique_people: Array = snapshot.get("unique_people", [])
		unique_people.sort()
		unique_people_label.text = "People: %s" % ", ".join(unique_people) if not unique_people.is_empty() else "People: None"
		availability_label.text = "Assignments unavailable; showing expected capacity." if not snapshot.get("assignment_state_available", false) else ""
		availability_label.visible = not availability_label.text.is_empty()
		var previous_group := ""
		for row in snapshot.get("rows", []):
			var group := str(row.get("group", "employment"))
			if group != previous_group:
				rows_root.add_child(_group_label("Residence" if group == "residence" else "Employment"))
				previous_group = group
			rows_root.add_child(_role_row(row))
		if (snapshot.get("rows", []) as Array).is_empty():
			rows_root.add_child(_group_label("No residence or employment roles expected"))


	func _group_label(text: String) -> Label:
		var label := Label.new()
		label.text = text
		label.custom_minimum_size.y = 22.0
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", Color(0.72, 0.64, 0.48, 1.0))
		return label


	func _role_row(data: Dictionary) -> HBoxContainer:
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 22.0
		row.add_theme_constant_override("separation", 8)
		for value in [[data.get("role", "Role"), 145.0], [data.get("character_name", "Vacant"), 170.0], [data.get("source", ""), 60.0]]:
			var label := Label.new()
			label.text = str(value[0])
			label.custom_minimum_size.x = float(value[1])
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			label.add_theme_font_size_override("font_size", 10)
			label.add_theme_color_override("font_color", Color(0.55, 0.53, 0.48, 1.0) if label.text == "Vacant" else Color(0.84, 0.79, 0.67, 1.0))
			row.add_child(label)
		return row


	func _fit_to_viewport() -> void:
		set_anchors_preset(Control.PRESET_TOP_LEFT)
		var viewport_size := get_viewport_rect().size
		size = Vector2(minf(WINDOW_SIZE.x, viewport_size.x - 24.0), minf(WINDOW_SIZE.y, viewport_size.y - 24.0))
		position = (viewport_size - size) * 0.5
