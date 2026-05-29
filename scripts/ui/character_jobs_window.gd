extends PanelContainer

class_name CharacterJobsWindow

const WINDOW_SIZE := Vector2(560.0, 380.0)
const REFRESH_SECONDS := 0.2

var actor: HumanoidCharacter
var root_scene: Node
var title_label: Label
var rows_root: VBoxContainer
var empty_label: Label
var _refresh_remaining := 0.0


func setup(target_root: Node) -> void:
	root_scene = target_root


func _ready() -> void:
	add_to_group("character_jobs_window")
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = WINDOW_SIZE
	size = WINDOW_SIZE
	_build_layout()
	_center_window()


func _process(delta: float) -> void:
	if not visible or actor == null:
		return
	_refresh_remaining -= delta
	if _refresh_remaining <= 0.0:
		_refresh_remaining = REFRESH_SECONDS
		_rebuild_rows()


func show_for_actor(target_actor: HumanoidCharacter) -> void:
	actor = target_actor
	visible = actor != null
	if title_label == null:
		call_deferred("show_for_actor", target_actor)
		return
	_rebuild_rows()
	_center_window()


func _build_layout() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.095, 0.085, 0.98)
	style.border_color = Color(0.42, 0.35, 0.22, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)

	title_label = Label.new()
	title_label.text = "Jobs"
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)

	var close_button := Button.new()
	close_button.text = "X"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(hide)
	header.add_child(close_button)

	empty_label = Label.new()
	empty_label.text = "No jobs"
	empty_label.add_theme_color_override("font_color", Color(0.64, 0.58, 0.48, 1.0))
	root.add_child(empty_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	rows_root = VBoxContainer.new()
	rows_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_root.add_theme_constant_override("separation", 5)
	scroll.add_child(rows_root)


func _rebuild_rows() -> void:
	if rows_root == null:
		return
	for child in rows_root.get_children():
		rows_root.remove_child(child)
		child.queue_free()
	var contracts := _get_contracts()
	title_label.text = "%s Jobs" % (actor.member_name if actor != null else "Character")
	empty_label.visible = contracts.is_empty()
	for contract in contracts:
		rows_root.add_child(_build_job_row(contract, _can_edit_jobs()))


func _build_job_row(contract: Dictionary, editable: bool) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 34)
	row.add_theme_constant_override("separation", 6)

	var order_label := Label.new()
	order_label.custom_minimum_size = Vector2(28, 0)
	order_label.text = str(int(contract.get("priority_order", 0)) + 1)
	order_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	order_label.add_theme_color_override("font_color", Color(0.72, 0.64, 0.48, 1.0))
	row.add_child(order_label)

	var title := Label.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.text = "%s  -  %s" % [str(contract.get("display_name", "Job")), str(contract.get("provider_name", "Provider"))]
	title.add_theme_color_override("font_color", Color(0.90, 0.82, 0.64, 1.0))
	row.add_child(title)

	var up_button := _row_button("Up", editable)
	up_button.pressed.connect(_move_contract.bind(str(contract.get("contract_id", "")), -1))
	row.add_child(up_button)

	var down_button := _row_button("Down", editable)
	down_button.pressed.connect(_move_contract.bind(str(contract.get("contract_id", "")), 1))
	row.add_child(down_button)

	var quit_button := _row_button("Quit", editable)
	quit_button.pressed.connect(_quit_contract.bind(str(contract.get("contract_id", ""))))
	row.add_child(quit_button)
	return row


func _row_button(label: String, enabled: bool) -> Button:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = not enabled
	button.custom_minimum_size = Vector2(58, 26)
	return button


func _move_contract(contract_id: String, direction: int) -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("move_actor_job_contract"):
		bridge.call("move_actor_job_contract", actor, contract_id, direction)
	_rebuild_rows()


func _quit_contract(contract_id: String) -> void:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("abandon_job_contract"):
		bridge.call("abandon_job_contract", actor, contract_id, "quit", _get_sim_time())
	_rebuild_rows()


func _get_contracts() -> Array[Dictionary]:
	var bridge := _get_gecs_world()
	if bridge == null or actor == null or not bridge.has_method("get_actor_job_contracts"):
		return []
	return bridge.call("get_actor_job_contracts", actor)


func _can_edit_jobs() -> bool:
	if actor == null:
		return false
	if actor.has_method("is_player_party_member") and bool(actor.call("is_player_party_member")):
		return true
	var player_faction := _player_faction_name()
	return not player_faction.is_empty() and str(actor.faction_name) == player_faction


func _player_faction_name() -> String:
	var party_manager := root_scene.get_node_or_null("PartyManager") if root_scene != null else null
	if party_manager == null or not _has_property(party_manager, "party_members"):
		return "Player"
	var members: Array = party_manager.get("party_members")
	for member in members:
		if member != null and is_instance_valid(member) and _has_property(member, "faction_name"):
			return str(member.get("faction_name"))
	return "Player"


func _get_sim_time() -> float:
	if root_scene != null:
		var job_system := root_scene.get_node_or_null("GameBootstrap/JobSystemController")
		if job_system != null and job_system.has_method("get_sim_time"):
			return float(job_system.call("get_sim_time"))
	return float(Time.get_ticks_msec()) / 1000.0


func _get_gecs_world() -> Node:
	if actor != null and actor.is_inside_tree():
		return actor.get_tree().get_first_node_in_group("gecs_world_controller")
	return null


func _center_window() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	size = WINDOW_SIZE
	position = (get_viewport_rect().size - WINDOW_SIZE) * 0.5


func _has_property(object: Object, property_name: String) -> bool:
	if object == null:
		return false
	for property in object.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false
