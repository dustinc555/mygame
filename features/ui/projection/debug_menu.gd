extends Control

class_name DebugMenu

## Dev-only debug windows, shown only while the GameDebug sentinel is true.
## Two independent draggable windows that can be open at the same time:
## "LOD Debug" (realization ring, brain log) and "Nav Debug" (navmesh
## visualization, tile grid, bake tuning). WorldStatusController opens them
## from the Escape menu.

var _lod_overlay: Node3D
var _lod_check: CheckButton
var _brain_log_check: CheckButton
var _radius_slider: HSlider
var _radius_label: Label

var _navmesh_check: CheckButton
var _tiles_check: CheckButton
var _nav_radius_slider: HSlider
var _nav_radius_label: Label
var _nav_cell_slider: HSlider
var _nav_cell_label: Label
var _nav_climb_slider: HSlider
var _nav_climb_label: Label
var _nav_tile_slider: HSlider
var _nav_tile_label: Label
var _nav_bake_label: Label

var _windows: Array[PanelContainer] = []
var _window_panels := {}
var _drag_panel: PanelContainer
var _drag_offset := Vector2.ZERO

const PLACEABLE_CATALOG_PATH := "res://features/settlements/resources/buildings/player_building_catalog.tres"
const PLACER_GHOST_TRANSPARENCY := 0.6

var _placer_catalog: Resource
var _placer_status: Label
var _ghost: Node3D
var _ghost_disc: MeshInstance3D
var _ghost_building_id := ""
var _ghost_footprint := Vector2(14.0, 8.0)
var _ghost_yaw := 0.0
var _ghost_valid := false
var _ghost_anchored := false
var _ghost_anchor := Vector3.ZERO
var _ghost_ground := Vector3.ZERO
var _ghost_y_offset := 0.0
var _ghost_faction := "Player"
var _ghost_reason := ""

var _towns_law_check: CheckButton
var _towns_zoning_check: CheckButton
var _towns_list: VBoxContainer
var _law_border_root: Node3D

var _stealth_cones_check: CheckButton
var _stealth_los_check: CheckButton
var _stealth_noise_check: CheckButton
var _stealth_open_check: CheckButton
var _stealth_roll_label: Label
var _stealth_overlay: Node3D
var _stealth_cone_pool: Array[MeshInstance3D] = []
var _stealth_noise_pool: Array[MeshInstance3D] = []
var _stealth_open_pool: Array[MeshInstance3D] = []
var _stealth_cone_observers: Array[Node3D] = []
var _stealth_cone_mesh: Mesh
var _stealth_unit_disc_mesh: Mesh
var _stealth_refresh_timer := 0.0

const STEALTH_REFRESH_INTERVAL := 0.5
const STEALTH_OVERLAY_RANGE := 40.0
const STEALTH_MAX_CONES := 24
const STEALTH_MAX_DISCS := 32
const STEALTH_CONE_COLOR := Color(1.0, 0.62, 0.08, 0.16)
const STEALTH_NOISE_COLOR := Color(0.56, 0.35, 0.94, 0.22)
const STEALTH_OPEN_THEFT_COLOR := Color(0.95, 0.42, 0.12, 0.16)

const WINDOW_BG := Color(0.12, 0.12, 0.14, 1.0)
const WINDOW_BORDER := Color(0.42, 0.38, 0.28, 1.0)
const TITLE_BAR_BG := Color(0.18, 0.17, 0.15, 1.0)
const TITLE_BAR_BORDER := Color(0.34, 0.30, 0.22, 1.0)
const TEXT_COLOR := Color(0.86, 0.84, 0.78, 1.0)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if not _debug_enabled():
		return
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_lod_window()
	_build_nav_window()
	_build_placer_window()
	_build_towns_window()
	_build_stealth_window()
	# Everything stays closed and off until explicitly opened, one panel at a
	# time — debug windows never flood the screen.
	for panel in _windows:
		panel.hide()


func _build_lod_window() -> void:
	var vbox := _build_window("LOD Debug", Vector2(12.0, 88.0))
	_lod_check = _make_check(vbox, "Show LOD radius", _on_lod_toggled)
	_radius_label = _make_label(vbox)
	_radius_slider = _make_slider(vbox, 1.0, 1200.0, 1.0, _on_radius_changed)
	_radius_slider.set_value_no_signal(_current_lod_radius())
	_update_radius_label(_radius_slider.value)
	_brain_log_check = _make_check(vbox, "Show world brain log", _on_brain_log_toggled)


func _build_nav_window() -> void:
	var vbox := _build_window("Nav Debug", Vector2(372.0, 88.0))
	_navmesh_check = _make_check(vbox, "Show navmesh", _on_navmesh_toggled)
	_tiles_check = _make_check(vbox, "Show tiles", _on_tiles_toggled)
	_nav_radius_label = _make_label(vbox)
	_nav_radius_slider = _make_slider(vbox, 0.2, 0.6, 0.01, _on_nav_radius_changed)
	_nav_cell_label = _make_label(vbox)
	_nav_cell_slider = _make_slider(vbox, 0.05, 0.5, 0.01, _on_nav_cell_changed)
	_nav_climb_label = _make_label(vbox)
	_nav_climb_slider = _make_slider(vbox, 0.1, 0.6, 0.05, _on_nav_climb_changed)
	_nav_tile_label = _make_label(vbox)
	_nav_tile_slider = _make_slider(vbox, 32.0, 128.0, 16.0, _on_nav_tile_changed)
	_nav_bake_label = _make_label(vbox)
	var rebake_button := Button.new()
	rebake_button.text = "Rebake navmesh"
	rebake_button.focus_mode = Control.FOCUS_NONE
	rebake_button.pressed.connect(_on_rebake_pressed)
	vbox.add_child(rebake_button)
	_sync_nav_tuning()


func _build_placer_window() -> void:
	var vbox := _build_window("Building Placer", Vector2(732.0, 88.0))
	_placer_catalog = load(PLACEABLE_CATALOG_PATH)
	if _placer_catalog == null:
		var missing := _make_label(vbox)
		missing.text = "No building catalog found."
		return
	for building in _placer_catalog.get("buildings"):
		if building == null:
			continue
		var button := Button.new()
		button.text = str(building.get("display_name"))
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_begin_placement.bind(str(building.get("building_id"))))
		vbox.add_child(button)
	_placer_status = _make_label(vbox)
	_placer_status.text = "Click a building to place."
	_placer_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _build_towns_window() -> void:
	var vbox := _build_window("Towns", Vector2(1092.0, 88.0))
	# Two distinct borders per town: the tight LAW border (law & order
	# jurisdiction, from SettlementTown) and the large ZONING border
	# (construction claim: other factions cannot build inside it).
	_towns_law_check = _make_check(vbox, "Show law borders", _on_towns_law_toggled)
	_towns_zoning_check = _make_check(vbox, "Show zoning borders", _on_towns_zoning_toggled)
	var refresh := Button.new()
	refresh.text = "Refresh town list"
	refresh.focus_mode = Control.FOCUS_NONE
	refresh.pressed.connect(_refresh_towns_list)
	vbox.add_child(refresh)
	_towns_list = VBoxContainer.new()
	vbox.add_child(_towns_list)
	_refresh_towns_list.call_deferred()


func _on_towns_law_toggled(pressed: bool) -> void:
	if _law_border_root != null and is_instance_valid(_law_border_root):
		_law_border_root.queue_free()
	_law_border_root = null
	if not pressed:
		return
	# SettlementTown only draws its border in-editor; draw it in-game from
	# each town's border record. Record polygon points are LOCAL to the town
	# node and must be transformed to world space.
	_law_border_root = Node3D.new()
	_law_border_root.name = "LawBorderDebug"
	add_child(_law_border_root)
	for town in get_tree().get_nodes_in_group("settlement_town"):
		if not town.has_method("get_town_border_record") or not (town is Node3D):
			continue
		var record: Dictionary = town.call("get_town_border_record")
		var local_points: PackedVector2Array = record.get("polygon_points", PackedVector2Array())
		if local_points.size() < 3:
			continue
		var town_transform := (town as Node3D).global_transform
		var points := PackedVector2Array()
		for local_point in local_points:
			var world_point := town_transform * Vector3(local_point.x, 0.0, local_point.y)
			points.append(Vector2(world_point.x, world_point.z))
		_add_law_border((town as Node3D).global_position.y + 0.6, points)
	# Constructed towns get a tight law border too: their buildings'
	# footprint plus padding (the zoning circle is the separate, larger claim).
	var construction := get_tree().get_first_node_in_group("construction_controller")
	var building_registry := BootstrapContext.service(BuildingRegistry.SERVICE_ID) as BuildingRegistry
	if construction != null and building_registry != null:
		var settlements: Dictionary = construction.call("get_settlements")
		for settlement_id in settlements:
			var settlement: Dictionary = settlements[settlement_id]
			var buildings := building_registry.get_buildings_for_settlement(settlement_id)
			if buildings.is_empty():
				continue
			var bounds_min := Vector2(INF, INF)
			var bounds_max := Vector2(-INF, -INF)
			for building in buildings:
				var transform: Transform3D = building["world_transform"]
				# Wrap the building's actual rotated footprint, not just its
				# origin (which sits at a model corner): a town of ONE
				# building still gets a visible border around the whole house.
				var footprint := Vector2(14.0, 8.0)
				var definition: Resource = construction.get("catalog").call("get_building", building["catalog_id"])
				if definition != null:
					footprint = definition.get("footprint_size")
				var half := footprint * 0.5
				var basis_x := Vector2(transform.basis.x.x, transform.basis.x.z)
				var basis_z := Vector2(transform.basis.z.x, transform.basis.z.z)
				var origin := Vector2(transform.origin.x, transform.origin.z)
				for corner: Vector2 in [Vector2(half.x, half.y), Vector2(half.x, -half.y), Vector2(-half.x, half.y), Vector2(-half.x, -half.y)]:
					var world_corner: Vector2 = origin + basis_x * corner.x + basis_z * corner.y
					bounds_min = Vector2(minf(bounds_min.x, world_corner.x), minf(bounds_min.y, world_corner.y))
					bounds_max = Vector2(maxf(bounds_max.x, world_corner.x), maxf(bounds_max.y, world_corner.y))
			bounds_min -= Vector2.ONE * 8.0
			bounds_max += Vector2.ONE * 8.0
			var points := PackedVector2Array([
				bounds_min,
				Vector2(bounds_max.x, bounds_min.y),
				bounds_max,
				Vector2(bounds_min.x, bounds_max.y),
			])
			var center: Vector3 = settlement["world_position"]
			_add_law_border(center.y + 0.6, points)


func _add_law_border(y: float, points: PackedVector2Array) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = _dashed_polyline_mesh(points, y)
	var border_material := _ghost_disc_material(true)
	border_material.albedo_color = Color(0.4, 0.7, 0.95, 0.9)
	instance.material_override = border_material
	_law_border_root.add_child(instance)


func _on_towns_zoning_toggled(pressed: bool) -> void:
	var realizer := get_tree().get_first_node_in_group("construction_realizer")
	if realizer != null and realizer.has_method("set_zoning_borders_visible"):
		realizer.call("set_zoning_borders_visible", pressed)


func _refresh_towns_list() -> void:
	if _towns_list == null:
		return
	for child in _towns_list.get_children():
		child.queue_free()
	var construction := get_tree().get_first_node_in_group("construction_controller")
	if construction != null:
		var settlements: Dictionary = construction.call("get_settlements")
		for settlement_id in settlements:
			var settlement: Dictionary = settlements[settlement_id]
			var label := _make_label(_towns_list)
			label.text = "%s [%s] r=%dm (constructed)" % [settlement["display_name"], settlement["faction_id"], int(settlement["radius"])]
	var settlement_bridge := get_tree().get_first_node_in_group("settlement_controller")
	if settlement_bridge != null and settlement_bridge.get("settlement_states") is Dictionary:
		var states: Dictionary = settlement_bridge.get("settlement_states")
		for settlement_id in states:
			var state: Dictionary = states[settlement_id]
			var label := _make_label(_towns_list)
			label.text = "%s [%s] (authored)" % [state.get("display_name", settlement_id), state.get("faction_id", "?")]


## --- Stealth debug ---------------------------------------------------------
##
## The sneak_perception_demo tools, available in any scene as world overlays:
## NPC vision cones (what "clearly seen" tests against), the perception LOS
## rays, and the theft radii around every owned item and container.
## Orange disc = THEFT_NOTICE_RADIUS, the one detection bubble: owner-side
## people inside it auto-catch an open grab and roll against a sneaking one.
## Purple disc = the item's loudness — inside it, proximity pressure makes
## the sneaking roll rapidly harder. It is not a separate detection range.


func _build_stealth_window() -> void:
	var vbox := _build_window("Stealth Debug", Vector2(12.0, 348.0))
	_stealth_cones_check = _make_check(vbox, "Show NPC vision cones", _on_stealth_overlay_toggled)
	_stealth_los_check = _make_check(vbox, "Show sneak LOS rays", _on_stealth_los_toggled)
	_stealth_noise_check = _make_check(vbox, "Show item loudness radius (purple)", _on_stealth_overlay_toggled)
	_stealth_open_check = _make_check(vbox, "Show theft notice radius (orange)", _on_stealth_overlay_toggled)
	_stealth_roll_label = _make_label(vbox)
	_stealth_roll_label.text = "Last steal: (none yet)"
	_stealth_roll_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stealth_roll_label.custom_minimum_size = Vector2(300.0, 0.0)


func _on_stealth_overlay_toggled(_pressed: bool) -> void:
	_stealth_refresh_timer = 0.0


func _on_stealth_los_toggled(pressed: bool) -> void:
	var perception := _get_perception_controller()
	if perception != null:
		perception.set("debug_show_los_rays", pressed)


func _update_stealth_overlay(delta: float) -> void:
	var cones_on := _stealth_cones_check != null and _stealth_cones_check.button_pressed
	var noise_on := _stealth_noise_check != null and _stealth_noise_check.button_pressed
	var open_on := _stealth_open_check != null and _stealth_open_check.button_pressed
	if not (cones_on or noise_on or open_on):
		_clear_stealth_overlay()
		return
	if _stealth_overlay == null or not is_instance_valid(_stealth_overlay):
		_stealth_overlay = Node3D.new()
		_stealth_overlay.name = "StealthDebugOverlay"
		add_child(_stealth_overlay)
	_stealth_refresh_timer -= delta
	if _stealth_refresh_timer <= 0.0:
		_stealth_refresh_timer = STEALTH_REFRESH_INTERVAL
		_refresh_stealth_overlay(cones_on, noise_on, open_on)
	_update_stealth_cone_transforms()


func _clear_stealth_overlay() -> void:
	if _stealth_overlay != null and is_instance_valid(_stealth_overlay):
		_stealth_overlay.queue_free()
	_stealth_overlay = null
	_stealth_cone_pool.clear()
	_stealth_noise_pool.clear()
	_stealth_open_pool.clear()
	_stealth_cone_observers.clear()
	_stealth_cone_mesh = null


func _refresh_stealth_overlay(cones_on: bool, noise_on: bool, open_on: bool) -> void:
	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	var anchor := camera.global_position if camera != null else Vector3.ZERO
	_refresh_stealth_cones(anchor, cones_on)
	var none: Array[Node3D] = []
	var targets := _find_stealth_owned_targets(anchor) if (noise_on or open_on) else none
	_refresh_stealth_discs(_stealth_noise_pool, targets if noise_on else none, true)
	_refresh_stealth_discs(_stealth_open_pool, targets if open_on else none, false)


func _refresh_stealth_cones(anchor: Vector3, enabled: bool) -> void:
	_stealth_cone_observers.clear()
	if enabled:
		for node in get_tree().get_nodes_in_group("npc_character"):
			if _stealth_cone_observers.size() >= STEALTH_MAX_CONES:
				break
			var observer := node as Node3D
			if observer == null or not observer.is_inside_tree() or bool(observer.get("player_party_member")):
				continue
			if int(observer.get("life_state")) != NpcRules.LifeState.ALIVE:
				continue
			if Vector2(observer.global_position.x - anchor.x, observer.global_position.z - anchor.z).length() > STEALTH_OVERLAY_RANGE:
				continue
			_stealth_cone_observers.append(observer)
	if _stealth_cone_mesh == null:
		_stealth_cone_mesh = _build_stealth_cone_mesh()
	for index in range(_stealth_cone_observers.size()):
		_stealth_pool_instance(_stealth_cone_pool, index, _stealth_cone_mesh, STEALTH_CONE_COLOR)
	_hide_stealth_pool_tail(_stealth_cone_pool, _stealth_cone_observers.size())


## Cone size/angle mirrors the live perception tuning, not hardcoded demo
## numbers — what you see is what evaluate_observer actually tests.
func _build_stealth_cone_mesh() -> Mesh:
	var view_distance := 15.0
	var view_cone_degrees := 105.0
	var perception := _get_perception_controller()
	if perception != null:
		view_distance = float(perception.get("view_distance"))
		view_cone_degrees = float(perception.get("view_cone_degrees"))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 32
	var half_angle := deg_to_rad(view_cone_degrees) * 0.5
	for index in range(segments):
		var a0 := lerpf(-half_angle, half_angle, float(index) / float(segments))
		var a1 := lerpf(-half_angle, half_angle, float(index + 1) / float(segments))
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(sin(a0) * view_distance, 0.0, -cos(a0) * view_distance))
		st.add_vertex(Vector3(sin(a1) * view_distance, 0.0, -cos(a1) * view_distance))
	return st.commit()


func _update_stealth_cone_transforms() -> void:
	for index in range(mini(_stealth_cone_observers.size(), _stealth_cone_pool.size())):
		var cone := _stealth_cone_pool[index]
		var observer := _stealth_cone_observers[index]
		if observer == null or not is_instance_valid(observer) or not observer.is_inside_tree():
			cone.visible = false
			continue
		var forward := -observer.global_transform.basis.z
		if observer.has_method("get_perception_forward_vector"):
			forward = observer.call("get_perception_forward_vector")
		var yaw := atan2(-forward.x, -forward.z)
		cone.global_transform = Transform3D(Basis(Vector3.UP, yaw), observer.global_position + Vector3(0.0, 0.08, 0.0))


func _find_stealth_owned_targets(anchor: Vector3) -> Array[Node3D]:
	var targets: Array[Node3D] = []
	for group_name in ["world_item", "world_container"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if targets.size() >= STEALTH_MAX_DISCS:
				return targets
			var target := node as Node3D
			if target == null or not target.is_inside_tree() or not target.has_method("get_owner_faction_name"):
				continue
			if Vector2(target.global_position.x - anchor.x, target.global_position.z - anchor.z).length() > STEALTH_OVERLAY_RANGE:
				continue
			if str(target.call("get_owner_faction_name")).is_empty():
				continue
			targets.append(target)
	return targets


func _refresh_stealth_discs(pool: Array[MeshInstance3D], targets: Array[Node3D], use_item_noise: bool) -> void:
	if _stealth_unit_disc_mesh == null:
		var disc := CylinderMesh.new()
		disc.top_radius = 1.0
		disc.bottom_radius = 1.0
		disc.height = 0.02
		disc.radial_segments = 64
		_stealth_unit_disc_mesh = disc
	var visible_count := 0
	for target in targets:
		var radius := OwnershipController.THEFT_NOTICE_RADIUS
		if use_item_noise:
			radius = float(target.call("get_theft_noise_radius")) if target.has_method("get_theft_noise_radius") else 0.0
		if radius <= 0.01:
			continue
		var color := STEALTH_NOISE_COLOR if use_item_noise else STEALTH_OPEN_THEFT_COLOR
		var instance := _stealth_pool_instance(pool, visible_count, _stealth_unit_disc_mesh, color)
		instance.global_position = target.global_position + Vector3(0.0, 0.06, 0.0)
		instance.scale = Vector3(radius, 1.0, radius)
		visible_count += 1
	_hide_stealth_pool_tail(pool, visible_count)


func _stealth_pool_instance(pool: Array[MeshInstance3D], index: int, mesh: Mesh, color: Color) -> MeshInstance3D:
	while pool.size() <= index:
		var instance := MeshInstance3D.new()
		instance.material_override = _stealth_material(color)
		_stealth_overlay.add_child(instance)
		pool.append(instance)
	var existing := pool[index]
	existing.mesh = mesh
	existing.visible = true
	return existing


func _hide_stealth_pool_tail(pool: Array[MeshInstance3D], from_index: int) -> void:
	for index in range(from_index, pool.size()):
		pool[index].visible = false


func _stealth_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _get_perception_controller() -> Node:
	return get_tree().get_first_node_in_group("perception_controller") if get_tree() != null else null


## Leaf scene node: static service lookup is the sanctioned path here.
func _update_stealth_roll_label() -> void:
	if _stealth_roll_label == null or not _stealth_roll_label.is_visible_in_tree():
		return
	var ownership := BootstrapContext.service(OwnershipController.SERVICE_ID)
	if ownership == null:
		return
	var summary := str(ownership.get("last_steal_roll_summary"))
	_stealth_roll_label.text = "Last steal: %s" % (summary if not summary.is_empty() else "(none yet)")


func _dashed_polyline_mesh(points: PackedVector2Array, y: float) -> ArrayMesh:
	var lines := PackedVector3Array()
	var dash := 2.0
	var gap := 1.0
	for i in range(points.size()):
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var edge := b - a
		var length := edge.length()
		if length < 0.01:
			continue
		var direction := edge / length
		var travelled := 0.0
		while travelled < length:
			var segment_end := minf(travelled + dash, length)
			var p0 := a + direction * travelled
			var p1 := a + direction * segment_end
			lines.append(Vector3(p0.x, y, p0.y))
			lines.append(Vector3(p1.x, y, p1.y))
			travelled += dash + gap
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = lines
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


## Builds one draggable window (title bar + capped scroll area) and returns
## the content VBoxContainer.
func _build_window(title_text: String, window_position: Vector2) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.position = window_position
	panel.custom_minimum_size = Vector2(340.0, 0.0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _make_window_style())
	add_child(panel)
	_windows.append(panel)
	_window_panels[title_text] = panel
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	margin.add_child(outer)
	var title_bar := PanelContainer.new()
	title_bar.add_theme_stylebox_override("panel", _make_title_bar_style())
	title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	title_bar.gui_input.connect(_on_title_bar_input.bind(panel))
	outer.add_child(title_bar)
	var title_margin := MarginContainer.new()
	title_margin.add_theme_constant_override("margin_left", 12)
	title_margin.add_theme_constant_override("margin_top", 5)
	title_margin.add_theme_constant_override("margin_right", 12)
	title_margin.add_theme_constant_override("margin_bottom", 5)
	title_bar.add_child(title_margin)
	var title_row := HBoxContainer.new()
	title_margin.add_child(title_row)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var close_button := Button.new()
	close_button.text = "X"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(panel.hide)
	title_row.add_child(close_button)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(340.0, 60.0)
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.custom_minimum_size = Vector2(316.0, 0.0)
	scroll.add_child(vbox)
	# ScrollContainers do NOT inherit their content's minimum size; size the
	# scroll to the content after layout, capped so tall content scrolls
	# instead of overflowing the screen.
	_fit_scroll_to_content.call_deferred(scroll, vbox)
	return vbox


func _fit_scroll_to_content(scroll: ScrollContainer, content: VBoxContainer) -> void:
	if not is_instance_valid(scroll) or not is_instance_valid(content):
		return
	var max_height := maxf(240.0, get_viewport().get_visible_rect().size.y - 200.0)
	scroll.custom_minimum_size.y = minf(content.get_combined_minimum_size().y + 12.0, max_height)


func _make_check(parent_control: Control, text: String, handler: Callable) -> CheckButton:
	var check := CheckButton.new()
	check.text = text
	check.add_theme_color_override("font_color", TEXT_COLOR)
	check.toggled.connect(handler)
	parent_control.add_child(check)
	return check


func _make_label(parent_control: Control) -> Label:
	var label := Label.new()
	label.add_theme_color_override("font_color", TEXT_COLOR)
	parent_control.add_child(label)
	return label


func _make_slider(parent_control: Control, min_value: float, max_value: float, step: float, handler: Callable) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.custom_minimum_size = Vector2(300.0, 0.0)
	slider.value_changed.connect(handler)
	parent_control.add_child(slider)
	return slider


func _on_title_bar_input(event: InputEvent, panel: PanelContainer) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drag_panel = panel if event.pressed else null
		if _drag_panel != null:
			_drag_offset = panel.get_global_mouse_position() - panel.global_position
	elif event is InputEventMouseMotion and _drag_panel == panel:
		var viewport_size := get_viewport().get_visible_rect().size
		var next := panel.get_global_mouse_position() - _drag_offset
		next.x = clampf(next.x, 0.0, maxf(0.0, viewport_size.x - 80.0))
		next.y = clampf(next.y, 0.0, maxf(0.0, viewport_size.y - 40.0))
		panel.global_position = next


func get_window_titles() -> Array:
	return _window_panels.keys()


func is_window_open(title: String) -> bool:
	var panel: Control = _window_panels.get(title)
	return visible and panel != null and panel.visible


func toggle_window(title: String) -> void:
	if not _debug_enabled():
		return
	var panel: Control = _window_panels.get(title)
	if panel == null:
		return
	if is_window_open(title):
		panel.hide()
		for other in _windows:
			if other.visible:
				return
		visible = false
		return
	panel.show()
	visible = true
	_sync_toggles()


func open_menu() -> void:
	if not _debug_enabled():
		return
	visible = true
	for panel in _windows:
		panel.show()
	_sync_toggles()


func close_menu() -> void:
	visible = false


func toggle_menu() -> void:
	if visible:
		close_menu()
	else:
		open_menu()


## --- LOD window handlers ------------------------------------------------------


func _on_lod_toggled(pressed: bool) -> void:
	_lod_overlay = _get_lod_overlay()
	if _lod_overlay != null:
		_lod_overlay.visible = pressed


func _on_brain_log_toggled(pressed: bool) -> void:
	var status := _get_world_status_controller()
	if status != null and status.has_method("set_brain_log_visible"):
		status.call("set_brain_log_visible", pressed)


func _on_radius_changed(value: float) -> void:
	var controller := _get_realization_controller()
	if controller != null:
		controller.set("near_player_radius", value)
		if controller.has_method("sync_population_realization_state"):
			controller.call("sync_population_realization_state")
	_update_radius_label(value)


func _update_radius_label(value: float) -> void:
	if _radius_label != null:
		_radius_label.text = "LOD radius: %dm" % int(value)


func _current_lod_radius() -> float:
	var controller := _get_realization_controller()
	if controller != null and controller.get("near_player_radius") != null:
		return float(controller.get("near_player_radius"))
	return 120.0


## --- Nav window handlers ------------------------------------------------------


func _on_navmesh_toggled(pressed: bool) -> void:
	var navigation := _get_world_navigation_controller()
	if navigation != null and navigation.has_method("set_debug_visualization"):
		navigation.call("set_debug_visualization", pressed)


func _on_tiles_toggled(pressed: bool) -> void:
	var navigation := _get_world_navigation_controller()
	if navigation != null and navigation.has_method("set_tile_debug"):
		navigation.call("set_tile_debug", pressed)


func _nav_settings() -> Resource:
	var navigation := _get_world_navigation_controller()
	return navigation.get("settings") as Resource if navigation != null else null


func _on_nav_radius_changed(value: float) -> void:
	var nav_settings := _nav_settings()
	if nav_settings == null:
		return
	nav_settings.set("agent_radius", value)
	_apply_nav_settings()


func _on_nav_cell_changed(value: float) -> void:
	var nav_settings := _nav_settings()
	if nav_settings == null:
		return
	nav_settings.set("cell_size", value)
	nav_settings.set("cell_height", value)
	_apply_nav_settings()


func _on_nav_climb_changed(value: float) -> void:
	var nav_settings := _nav_settings()
	if nav_settings == null:
		return
	nav_settings.set("agent_max_climb", value)
	_apply_nav_settings()


func _on_nav_tile_changed(value: float) -> void:
	var nav_settings := _nav_settings()
	if nav_settings == null:
		return
	nav_settings.set("tile_size", value)
	_apply_nav_settings()


func _apply_nav_settings() -> void:
	var navigation := _get_world_navigation_controller()
	if navigation != null and navigation.has_method("apply_settings"):
		navigation.call("apply_settings")
	_sync_nav_tuning()


func _on_rebake_pressed() -> void:
	var navigation := _get_world_navigation_controller()
	if navigation != null and navigation.has_method("notify_world_geometry_changed"):
		navigation.call("notify_world_geometry_changed")


func _sync_nav_tuning() -> void:
	var nav_settings := _nav_settings()
	if nav_settings == null:
		if _nav_radius_label != null:
			_nav_radius_label.text = "Navmesh: no controller"
		return
	var radius := float(nav_settings.get("agent_radius"))
	var cell := float(nav_settings.get("cell_size"))
	if _nav_radius_slider != null:
		_nav_radius_slider.set_value_no_signal(radius)
		var erosion := ceilf(radius / cell) * cell
		_nav_radius_label.text = "Nav agent radius: %.2fm (erodes %.2fm/side)" % [radius, erosion]
	if _nav_cell_slider != null:
		_nav_cell_slider.set_value_no_signal(cell)
		_nav_cell_label.text = "Nav cell size: %.2fm (finer = slower bake)" % cell
	if _nav_climb_slider != null:
		var climb := float(nav_settings.get("agent_max_climb"))
		var cell_height := float(nav_settings.get("cell_height"))
		_nav_climb_slider.set_value_no_signal(climb)
		_nav_climb_label.text = "Nav max climb: %.2fm (effective %.2fm)" % [climb, floorf(climb / cell_height) * cell_height]
	if _nav_tile_slider != null:
		var tile := float(nav_settings.get("tile_size"))
		_nav_tile_slider.set_value_no_signal(tile)
		_nav_tile_label.text = "Nav tile size: %dm (smaller = faster patches)" % int(tile)


func _process(delta: float) -> void:
	_update_stealth_overlay(delta)
	_update_stealth_roll_label()
	if not visible or _nav_bake_label == null:
		return
	var navigation := _get_world_navigation_controller()
	if navigation == null:
		_nav_bake_label.text = "Tiles: no controller"
		return
	var seconds := float(navigation.get("last_bake_seconds"))
	var baked := int(navigation.call("baked_tile_count")) if navigation.has_method("baked_tile_count") else 0
	var pending := int(navigation.call("pending_tile_count")) if navigation.has_method("pending_tile_count") else 0
	if pending > 0:
		_nav_bake_label.text = "Tiles: %d baked, %d pending | last %.2fs" % [baked, pending, seconds]
	else:
		_nav_bake_label.text = "Tiles: %d baked | last %.2fs" % [baked, seconds]


## --- Building placer ghost ------------------------------------------------------
##
## Flow: click a catalog button -> a 60%-transparent ghost follows the mouse
## along the TERRAIN (building/actor colliders are ignored), oriented to the
## averaged terrain normal under its footprint. A translucent footprint disc
## shows green (slope acceptable) or red (too steep). Left press anchors the
## position; dragging while held rotates the building to face the cursor;
## release finalizes through the ConstructionController (record first, scene
## realized by the bridge). Right click or Escape cancels.


func _begin_placement(building_id: String) -> void:
	_cancel_placement()
	var definition: Resource = _placer_catalog.get_building(building_id)
	if definition == null or definition.get("scene") == null:
		return
	_ghost_building_id = building_id
	_ghost_footprint = definition.get("footprint_size")
	_ghost_yaw = 0.0
	_ghost_y_offset = 0.0
	_ghost_anchored = false
	_ghost_faction = _placer_faction_id()
	_ghost = (definition.get("scene") as PackedScene).instantiate()
	# Parented under the debug menu, NOT the world: the navigation system
	# scopes to the played scene root, so ghost colliders never dirty tiles.
	_disable_ghost_physics(_ghost)
	add_child(_ghost)
	_apply_ghost_transparency(_ghost)
	_ghost_disc = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = maxf(_ghost_footprint.x, _ghost_footprint.y) * 0.62
	disc.bottom_radius = disc.top_radius
	disc.height = 0.05
	_ghost_disc.mesh = disc
	add_child(_ghost_disc)
	if _placer_status != null:
		_placer_status.text = "Placing %s: click to anchor, hold+drag to rotate, release to place. Right click cancels." % building_id


func _cancel_placement() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	if _ghost_disc != null and is_instance_valid(_ghost_disc):
		_ghost_disc.queue_free()
	_ghost = null
	_ghost_disc = null
	_ghost_building_id = ""
	_ghost_anchored = false


func _unhandled_input(event: InputEvent) -> void:
	if _ghost == null or not is_instance_valid(_ghost):
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_placement()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			_cancel_placement()
			get_viewport().set_input_as_handled()
			return
		# Raise/lower before release: foundations exist so a building can sit
		# above uneven terrain instead of clipping into it.
		if mouse_event.pressed and mouse_event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var step := 0.25 if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.25
			_ghost_y_offset = clampf(_ghost_y_offset + step, -1.0, 4.0)
			_apply_ghost_transform(_ghost_anchor if _ghost_anchored else _ghost_ground)
			get_viewport().set_input_as_handled()
			return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_ghost_anchored = true
				_ghost_anchor = _ghost.global_position
			elif _ghost_anchored:
				_finalize_placement()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion:
		_update_ghost((event as InputEventMouseMotion).position)


func _update_ghost(screen_position: Vector2) -> void:
	var camera := get_viewport().get_camera_3d()
	if _ghost_anchored:
		# Rotate to face the cursor's ground point.
		var toward := BuildingPlacementSolver.terrain_hit_from_screen(camera, screen_position)
		if not toward.is_empty():
			var flat: Vector3 = toward["position"] - _ghost_anchor
			if Vector2(flat.x, flat.z).length() > 0.6:
				_ghost_yaw = atan2(flat.x, flat.z)
		_apply_ghost_transform(_ghost_anchor)
		return
	var hit := BuildingPlacementSolver.terrain_hit_from_screen(camera, screen_position)
	if not hit.is_empty():
		_apply_ghost_transform(hit["position"])


func _apply_ghost_transform(ground_position: Vector3) -> void:
	_ghost_ground = ground_position
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var solution := BuildingPlacementSolver.solve(camera.get_world_3d().direct_space_state, ground_position, _ghost_footprint, _ghost_yaw, _ghost_y_offset)
	var zone := {"allowed": true, "reason": ""}
	var construction := get_tree().get_first_node_in_group("construction_controller")
	if construction != null:
		zone = construction.call("can_place", ground_position, _ghost_faction)
	_ghost_valid = bool(solution["slope_ok"]) and bool(zone["allowed"])
	_ghost_reason = ""
	if not bool(zone["allowed"]):
		_ghost_reason = str(zone["reason"])
	elif not bool(solution["slope_ok"]):
		_ghost_reason = "Slope too steep."
	_ghost.global_transform = solution["transform"]
	_ghost_disc.global_position = ground_position + Vector3(0.0, 0.15, 0.0)
	_ghost_disc.material_override = _ghost_disc_material(_ghost_valid)
	if _placer_status != null:
		if not _ghost_reason.is_empty():
			_placer_status.text = _ghost_reason
		else:
			_placer_status.text = "Height %+.2fm (scroll). Click to anchor, hold+drag rotates, release places." % _ghost_y_offset


func _finalize_placement() -> void:
	if not _ghost_valid:
		if _placer_status != null:
			_placer_status.text = _ghost_reason if not _ghost_reason.is_empty() else "Cannot place here."
		_ghost_anchored = false
		return
	var construction := get_tree().get_first_node_in_group("construction_controller")
	if construction == null:
		_placer_status.text = "No construction records service."
		_cancel_placement()
		return
	var transform := _ghost.global_transform
	var building_id := _ghost_building_id
	var faction := _ghost_faction
	var foundation := _ghost_y_offset
	_cancel_placement()
	var record: Dictionary = construction.call("place_building", building_id, transform, faction, foundation)
	if _placer_status != null:
		if record.is_empty():
			_placer_status.text = str(construction.call("can_place", transform.origin, faction)["reason"])
		else:
			_placer_status.text = "Placed %s (%s)." % [building_id, record.get("settlement_id", "?")]
	_refresh_towns_list()
	if _towns_law_check != null and _towns_law_check.button_pressed:
		_on_towns_law_toggled(true)


## Whoever places founds the town: the party's faction.
func _placer_faction_id() -> String:
	for actor in get_tree().get_nodes_in_group("world_actor"):
		if actor.has_method("is_player_party_member") and actor.call("is_player_party_member"):
			var faction := str(actor.get("faction_name"))
			if not faction.is_empty():
				return faction
	return "Player"


func _disable_ghost_physics(node: Node) -> void:
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	for child in node.get_children():
		_disable_ghost_physics(child)


func _apply_ghost_transparency(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).transparency = PLACER_GHOST_TRANSPARENCY
	for child in node.get_children():
		_apply_ghost_transparency(child)


func _ghost_disc_material(valid: bool) -> StandardMaterial3D:
	var disc_material := StandardMaterial3D.new()
	disc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_material.albedo_color = Color(0.25, 0.85, 0.35, 0.35) if valid else Color(0.9, 0.2, 0.15, 0.45)
	return disc_material


## --- Shared lookups -----------------------------------------------------------


func _sync_toggles() -> void:
	if _lod_check != null:
		var lod := _get_lod_overlay()
		_lod_check.set_pressed_no_signal(lod != null and lod.visible)
	if _brain_log_check != null:
		var status := _get_world_status_controller()
		var shown := bool(status.call("is_brain_log_visible")) if status != null and status.has_method("is_brain_log_visible") else false
		_brain_log_check.set_pressed_no_signal(shown)
	if _radius_slider != null:
		_radius_slider.set_value_no_signal(_current_lod_radius())
		_update_radius_label(_radius_slider.value)
	var navigation := _get_world_navigation_controller()
	if _navmesh_check != null and navigation != null and navigation.has_method("is_debug_visualization_enabled"):
		_navmesh_check.set_pressed_no_signal(bool(navigation.call("is_debug_visualization_enabled")))
	if _tiles_check != null and navigation != null and navigation.has_method("is_tile_debug_enabled"):
		_tiles_check.set_pressed_no_signal(bool(navigation.call("is_tile_debug_enabled")))
	_sync_nav_tuning()


func _get_realization_controller() -> Node:
	return get_tree().get_first_node_in_group("population_realization_controller") if get_tree() != null else null


func _get_lod_overlay() -> Node3D:
	if _lod_overlay == null or not is_instance_valid(_lod_overlay):
		_lod_overlay = get_tree().get_first_node_in_group("lod_radius_overlay") as Node3D
	return _lod_overlay


func _get_world_navigation_controller() -> Node:
	return get_tree().get_first_node_in_group("world_navigation_controller") if get_tree() != null else null


func _get_world_status_controller() -> Node:
	return get_tree().get_first_node_in_group("world_status_controller") if get_tree() != null else null


func _debug_enabled() -> bool:
	var debug_node := get_node_or_null("/root/GameDebug")
	if debug_node == null:
		return false
	if debug_node.has_method("is_debug_enabled"):
		return bool(debug_node.call("is_debug_enabled"))
	var value = debug_node.get("debug")
	return bool(value) if value != null else false


func _make_window_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = WINDOW_BG
	style.border_color = WINDOW_BORDER
	style.set_border_width_all(2)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style


func _make_title_bar_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = TITLE_BAR_BG
	style.border_color = TITLE_BAR_BORDER
	style.set_border_width_all(1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style
