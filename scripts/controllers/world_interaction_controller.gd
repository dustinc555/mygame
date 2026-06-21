extends Node

class_name WorldInteractionController

const MOVE_COMMAND_INDICATOR_SCENE = preload("res://scenes/world/effects/move_command_indicator.tscn")
const WORLD_TEXT_NOTICE_SCENE = preload("res://scenes/world/effects/world_text_notice.tscn")
const PARTY_PORTRAIT_CARD_SCENE = preload("res://scenes/ui/party_portrait_card.tscn")
const COMBAT_COORDINATOR = preload("res://scripts/characters/combat_coordinator.gd")

const ACTION_INVENTORY := 1
const ACTION_MINE := 2
const ACTION_OPEN_CONTAINER := 3
const ACTION_UNLOCK_CONTAINER := 4
const ACTION_ATTACK := 5
const ACTION_TRADE := 6
const ACTION_HEAL := 7
const ACTION_FINISH_OFF := 8
const ACTION_CARRY := 9
const ACTION_DROP_CARRY := 10
const ACTION_TALK := 11
const ACTION_SLEEP := 12
const ACTION_SIT := 13
const ACTION_WAKE_UP := 14
const ACTION_STAND_UP := 15
const ACTION_PLACE_IN_BED := 16
const ACTION_PICKUP_ITEM := 17
const ACTION_WORLD_CONTEXT_BASE := 10000
const SQUAD_MENU_RENAME := 1
const ALL_SQUADS_FILTER := ""
const DEFAULT_PLAYER_SQUAD_NAME := "Squad 1"
const FREE_CAMERA_PITCH := -0.65
const FOLLOW_CAMERA_HEIGHT := 1.35
const ORBIT_MIN_PITCH := -1.2
const ORBIT_MAX_PITCH := 1.15
const GROUND_Y := 0.0
const CAMERA_FLOOR_CLEARANCE := 0.35
const MOVE_COMMAND_NAV_PROJECTION_VERTICAL_TOLERANCE := 0.8
const MOVEMENT_MODE_WALK := 0
const MOVEMENT_MODE_RUN := 1
const MOVEMENT_MODE_SNEAK := 2
const SEGMENT_SINGLE := 0
const SEGMENT_LEFT := 1
const SEGMENT_MIDDLE := 2
const SEGMENT_RIGHT := 3

@export var free_camera_move_speed := 14.0
@export var camera_zoom_step := 1.0
@export var camera_min_distance := 2.0
@export var camera_max_distance := 36.0
@export var orbit_sensitivity := 0.01
@export var move_command_spacing := 1.4
@export var close_move_command_spacing := 0.85
@export var close_move_command_radius := 2.0
@export var vertical_move_formation_height_threshold := 1.0
@export var drag_select_threshold := 12.0
@export var hold_move_repeat_seconds := 0.15
@export var hold_move_indicator_seconds := 0.3
@export var group_attack_target_scan_radius := 18.0

var party_members: Array[WorldActor] = []
var portrait_cards: Array[PartyPortraitCard] = []
var work_progress_bars: Dictionary = {}
var camera_anchor := Vector3.ZERO
var camera_yaw := deg_to_rad(45.0)
var camera_pitch := FREE_CAMERA_PITCH
var camera_distance := 11.0
var is_orbiting := false
var is_left_mouse_down := false
var is_right_mouse_down := false
var is_hold_move_active := false
var hold_move_repeat_remaining := 0.0
var hold_move_indicator_remaining := 0.0
var is_drag_selecting := false
var left_mouse_press_position := Vector2.ZERO
var left_mouse_press_double_click := false
var context_member: WorldActor
var context_humanoid: HumanoidCharacter
var context_resource
var context_container
var context_world_item
var context_world_action_target
var context_world_actions: Array = []
var context_sleep_target
var context_seat_target
var root: Node
var hud_layer: CanvasLayer
var party_root: Node3D
var party_manager: PartyManager
var camera_rig: Node3D
var camera_pivot: Node3D
var camera: Camera3D
var selection_rect: ColorRect
var context_menu: PopupMenu
var progress_layer: Control
var portrait_flow: Container
var squad_tab_row: HBoxContainer
var squad_all_button: Button
var squad_add_button: Button
var squad_name_label: Label
var squad_formation_button: Button
var squad_ai_button: Button
var command_title_label: Label
var walk_button: Button
var running_button: Button
var sneaking_button: Button
var auto_heal_button: Button
var auto_burn_rustdead_button: Button
var aggressive_button: Button
var defensive_button: Button
var passive_button: Button
var inventory_controller: PartyInventoryController
var humanoid_details_controller
var conversation_controller
var ownership_controller
var building_visibility_controller
var floating_notice: FloatingNotice
var squad_names: Array[String] = []
var squad_tab_buttons: Dictionary = {}
var squad_tab_menu_buttons: Dictionary = {}
var squad_tab_containers: Dictionary = {}
var active_squad_filter := ALL_SQUADS_FILTER
var squad_menu: PopupMenu
var squad_rename_dialog: AcceptDialog
var squad_rename_line_edit: LineEdit
var squad_menu_target_name := ""
var _initialized := false


func initialize(target_root: Node, target_hud: CanvasLayer = null) -> void:
	root = target_root
	hud_layer = target_hud
	if is_inside_tree():
		_do_initialize()


func _ready() -> void:
	add_to_group("world_interaction_controller")
	if root != null:
		if hud_layer == null and root != null:
			hud_layer = root.get_node_or_null("GameHUD")
		_do_initialize()


func _do_initialize() -> void:
	if _initialized or root == null:
		return
	party_root = root.get_node("PartyMembers")
	party_manager = root.get_node("PartyManager")
	camera_rig = root.get_node("CameraRig")
	camera_pivot = root.get_node("CameraRig/CameraPivot")
	camera = root.get_node("CameraRig/CameraPivot/Camera3D")
	camera_anchor = camera_rig.global_position
	if hud_layer == null:
		hud_layer = root.get_node_or_null("GameHUD")
	selection_rect = hud_layer.get_node("SelectionRect")
	context_menu = hud_layer.get_node_or_null("ContextMenu")
	progress_layer = hud_layer.get_node_or_null("ProgressLayer")
	var command_rows_path := "HudLayout/BottomHud/RightHud/BottomInfoRow/CommandDock/Margin/CommandColumn/BehaviorRows"
	command_title_label = hud_layer.get_node_or_null("HudLayout/BottomHud/RightHud/BottomInfoRow/CommandDock/Margin/CommandColumn/Title")
	if command_title_label != null:
		command_title_label.text = "Behavior"
	walk_button = hud_layer.get_node_or_null(command_rows_path + "/MoveRow/MovementSegment/WalkButton")
	running_button = hud_layer.get_node_or_null(command_rows_path + "/MoveRow/MovementSegment/RunningButton")
	sneaking_button = hud_layer.get_node_or_null(command_rows_path + "/MoveRow/MovementSegment/SneakingButton")
	auto_heal_button = hud_layer.get_node_or_null(command_rows_path + "/AssistRow/AutoHealButton")
	auto_burn_rustdead_button = hud_layer.get_node_or_null(command_rows_path + "/AssistRow/BurnRustdeadButton")
	aggressive_button = hud_layer.get_node_or_null(command_rows_path + "/FightRow/CombatSegment/AggressiveButton")
	defensive_button = hud_layer.get_node_or_null(command_rows_path + "/FightRow/CombatSegment/DefensiveButton")
	passive_button = hud_layer.get_node_or_null(command_rows_path + "/FightRow/CombatSegment/PassiveButton")
	squad_tab_row = hud_layer.get_node_or_null("HudLayout/BottomHud/RightHud/BottomInfoRow/PortraitBar/Margin/PortraitColumn/SquadTabs")
	squad_all_button = hud_layer.get_node_or_null("HudLayout/BottomHud/RightHud/BottomInfoRow/PortraitBar/Margin/PortraitColumn/SquadTabs/AllButton")
	squad_add_button = hud_layer.get_node_or_null("HudLayout/BottomHud/RightHud/BottomInfoRow/PortraitBar/Margin/PortraitColumn/SquadTabs/AddSquadButton")
	squad_name_label = hud_layer.get_node_or_null("HudLayout/BottomHud/RightHud/BottomInfoRow/PortraitBar/Margin/PortraitColumn/SquadCommandStrip/SquadName")
	squad_formation_button = hud_layer.get_node_or_null("HudLayout/BottomHud/RightHud/BottomInfoRow/PortraitBar/Margin/PortraitColumn/SquadCommandStrip/FormationButton")
	squad_ai_button = hud_layer.get_node_or_null("HudLayout/BottomHud/RightHud/BottomInfoRow/PortraitBar/Margin/PortraitColumn/SquadCommandStrip/SquadAIButton")
	portrait_flow = hud_layer.get_node_or_null("HudLayout/BottomHud/RightHud/BottomInfoRow/PortraitBar/Margin/PortraitColumn/PortraitScroll/PortraitFlow")
	floating_notice = hud_layer.get_node_or_null("FloatingNotice")
	inventory_controller = get_parent().get_node("PartyInventoryController")
	humanoid_details_controller = get_parent().get_node("HumanoidDetailsController")
	if humanoid_details_controller != null and humanoid_details_controller.has_signal("inspector_action_requested"):
		var inspector_action_callable := Callable(self, "_on_inspector_action_requested")
		if not humanoid_details_controller.is_connected("inspector_action_requested", inspector_action_callable):
			humanoid_details_controller.connect("inspector_action_requested", inspector_action_callable)
	conversation_controller = get_parent().get_node("ConversationController")
	ownership_controller = get_parent().get_node_or_null("OwnershipController")
	building_visibility_controller = get_parent().get_node_or_null("BuildingVisibilityController")
	_initialized = true

	for child in party_root.get_children():
		if child is WorldActor and child.is_player_party_member():
			_register_party_member(child)

	party_manager.set_party_members(party_members)
	party_manager.selection_changed.connect(_update_portraits)
	party_manager.follow_changed.connect(_update_portraits)
	party_manager.selection_changed.connect(_sync_inspected_party_member)
	party_manager.selection_changed.connect(_update_command_bar)
	party_manager.party_member_added.connect(_on_party_member_added)

	if portrait_flow != null:
		for child in portrait_flow.get_children():
			child.queue_free()
		portrait_cards.clear()
		for member in party_members:
			_add_portrait_for_member(member)

	if progress_layer != null:
		for member in party_members:
			_ensure_work_progress_bar(member)

	if context_menu != null:
		context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	_setup_squad_tabs()
	_setup_command_bar()
	_refresh_squad_tabs()

	if not party_members.is_empty():
		party_manager.select_only(party_members[0])
		if humanoid_details_controller != null:
			humanoid_details_controller.inspect_target(party_members[0])

	camera_anchor = _get_anchor_position()
	_apply_camera_transform()
	_update_portraits()
	_update_command_bar()


func _register_party_member(member: WorldActor) -> void:
	if member == null or party_members.has(member):
		return
	_normalize_party_member_squad(member)
	party_members.append(member)
	if member.has_signal("container_reached"):
		member.connect("container_reached", Callable(self, "_on_party_member_container_reached"))
	if member.has_signal("trade_target_reached"):
		member.connect("trade_target_reached", Callable(self, "_on_party_member_trade_target_reached"))
	if member.has_signal("conversation_target_reached"):
		member.connect("conversation_target_reached", Callable(self, "_on_party_member_conversation_target_reached"))
	if member.has_signal("center_notice_requested"):
		member.center_notice_requested.connect(_show_center_notice)
	member.state_changed.connect(_update_command_bar)


func _add_portrait_for_member(member: WorldActor) -> void:
	if portrait_flow == null or member == null:
		return
	var card := PARTY_PORTRAIT_CARD_SCENE.instantiate() as PartyPortraitCard
	portrait_flow.add_child(card)
	card.setup(member)
	card.portrait_pressed.connect(_on_portrait_pressed)
	portrait_cards.append(card)
	card.visible = _should_show_member_in_active_squad(member)


func _ensure_work_progress_bar(member: WorldActor) -> void:
	if progress_layer == null or member == null or work_progress_bars.has(member):
		return
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 0.0
	bar.custom_minimum_size = Vector2(90.0, 12.0)
	bar.show_percentage = false
	bar.visible = false
	progress_layer.add_child(bar)
	work_progress_bars[member] = bar


func _process(delta: float) -> void:
	if not _initialized:
		return
	var input_delta := _get_unscaled_input_delta(delta)
	var move_input := Vector2.ZERO
	if not _is_text_input_focused():
		move_input = Vector2(
			float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
			float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
		)

	if party_manager.followed_member != null and move_input.length() > 0.0:
		_clear_follow_target()

	if party_manager.followed_member == null and move_input.length() > 0.0:
		var move_basis := Basis(Vector3.UP, camera_yaw)
		var move_direction := move_basis * Vector3(move_input.x, 0.0, move_input.y)
		if move_direction.length() > 0.0:
			camera_anchor += move_direction.normalized() * free_camera_move_speed * input_delta

	if party_manager.followed_member != null:
		camera_anchor = _get_anchor_position()

	if move_input.length() > 0.0 or party_manager.followed_member != null:
		_apply_camera_transform()

	_update_progress_bars()
	_process_hold_move(input_delta)


func _physics_process(_delta: float) -> void:
	if not _initialized or party_manager == null or party_manager.followed_member == null:
		return
	if not party_manager.followed_member.is_ragdoll_active():
		return
	camera_anchor = _get_anchor_position()
	_apply_camera_transform()


func _get_unscaled_input_delta(delta: float) -> float:
	return delta / maxf(Engine.time_scale, 0.001)


func _is_text_input_focused() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit


func _unhandled_input(event: InputEvent) -> void:
	if not _initialized:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			camera_distance = max(camera_min_distance, camera_distance - camera_zoom_step)
			_apply_camera_transform()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			camera_distance = min(camera_max_distance, camera_distance + camera_zoom_step)
			_apply_camera_transform()
			return
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			is_orbiting = event.pressed
			return
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if context_menu != null:
				context_menu.hide()
			is_left_mouse_down = true
			is_drag_selecting = false
			left_mouse_press_position = event.position
			left_mouse_press_double_click = event.double_click
			_update_selection_rect(event.position)
			return
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_handle_left_mouse_release(event.position)
			return
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			is_right_mouse_down = true
			is_hold_move_active = _handle_right_click(event.position)
			hold_move_repeat_remaining = hold_move_repeat_seconds
			hold_move_indicator_remaining = hold_move_indicator_seconds
			return
		if event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
			is_right_mouse_down = false
			is_hold_move_active = false
			return

	if event is InputEventMouseMotion and is_left_mouse_down:
		if not is_drag_selecting and left_mouse_press_position.distance_to(event.position) >= drag_select_threshold:
			is_drag_selecting = true
		if is_drag_selecting:
			_update_selection_rect(event.position)

	if event is InputEventMouseMotion and is_orbiting:
		camera_yaw -= event.relative.x * orbit_sensitivity
		camera_pitch = clamp(camera_pitch - event.relative.y * orbit_sensitivity, ORBIT_MIN_PITCH, ORBIT_MAX_PITCH)
		_apply_camera_transform()


func _handle_left_mouse_release(screen_position: Vector2) -> void:
	if not is_left_mouse_down:
		return
	if is_drag_selecting:
		_apply_drag_selection()
	else:
		_handle_world_selection(screen_position, left_mouse_press_double_click)
	is_left_mouse_down = false
	is_drag_selecting = false
	left_mouse_press_double_click = false
	selection_rect.visible = false


func _handle_world_selection(screen_position: Vector2, should_follow: bool) -> void:
	if Input.is_key_pressed(KEY_SHIFT) and not party_manager.selected_members.is_empty():
		var world_item = _pick_world_item(screen_position)
		if world_item != null:
			_assign_pickup_to_selection(world_item)
			return
	var inspected_target = _pick_inspectable_target(screen_position)
	if inspected_target == null:
		party_manager.clear_selection()
		if humanoid_details_controller != null:
			humanoid_details_controller.clear_if_not_party_target()
		return
	if humanoid_details_controller != null:
		humanoid_details_controller.inspect_target(inspected_target)
	if not (inspected_target is WorldActor):
		return
	var member := inspected_target as WorldActor
	if not member.is_player_party_member():
		return
	if Input.is_key_pressed(KEY_ALT):
		party_manager.add_selection(member)
	else:
		party_manager.select_only(member)
	if should_follow:
		_set_follow_target(member)


func _process_hold_move(delta: float) -> void:
	if not is_right_mouse_down or not is_hold_move_active:
		return
	hold_move_repeat_remaining -= delta
	hold_move_indicator_remaining = maxf(0.0, hold_move_indicator_remaining - delta)
	if hold_move_repeat_remaining > 0.0:
		return
	hold_move_repeat_remaining = hold_move_repeat_seconds
	var screen_position := get_viewport().get_mouse_position()
	if _is_hold_move_blocked(screen_position):
		return
	var show_indicator := hold_move_indicator_remaining <= 0.0
	if issue_move_command(screen_position, show_indicator) and show_indicator:
		hold_move_indicator_remaining = hold_move_indicator_seconds


func _get_focused_party_member() -> WorldActor:
	if party_manager == null or party_manager.selected_members.is_empty():
		return null
	return party_manager.selected_members[0] as WorldActor


func _handle_right_click(screen_position: Vector2) -> bool:
	if context_menu != null:
		context_menu.hide()
	context_member = null
	context_humanoid = null
	context_resource = null
	context_container = null
	context_world_item = null
	context_world_action_target = null
	context_world_actions.clear()
	context_sleep_target = null
	context_seat_target = null
	var result := _raycast_target_from_screen(screen_position)
	if result.is_empty():
		return issue_move_command(screen_position)
	var collider: Object = result["collider"]
	if collider is Node and collider.is_in_group("sleepable_bed") and not party_manager.selected_members.is_empty():
		context_sleep_target = collider
		var sleeper := _get_bed_sleeper(collider)
		if sleeper != null and _selection_can_carry_target(sleeper):
			context_humanoid = sleeper
			_show_context_menu(screen_position, ACTION_CARRY, "Carry")
		elif _selection_can_place_carried_in_bed():
			_show_context_menu(screen_position, ACTION_PLACE_IN_BED, "Place in bed")
		else:
			_show_context_menu(screen_position, ACTION_SLEEP, "Sleep")
		return false
	if collider is Node and collider.is_in_group("sittable_seat") and not party_manager.selected_members.is_empty():
		context_seat_target = collider
		_show_context_menu(screen_position, ACTION_SIT, "Sit")
		return false
	if collider is Node and collider.is_in_group("mining_resource") and not party_manager.selected_members.is_empty():
		_show_context_menu(screen_position, ACTION_MINE, "Mine")
		context_resource = collider
		return false
	if collider is WorldActor and collider.is_player_party_member():
		var focused_member := _get_focused_party_member()
		var inventory_action_label := "Trade" if focused_member != null and focused_member != collider else "Inventory"
		var party_actions := [{"id": ACTION_INVENTORY, "label": inventory_action_label}]
		if collider.life_state == NpcRules.LifeState.ASLEEP:
			if collider is HumanoidCharacter and _selection_can_carry_target(collider):
				party_actions.append({"id": ACTION_CARRY, "label": "Carry"})
			party_actions.append({"id": ACTION_WAKE_UP, "label": "Wake Up"})
		elif collider is HumanoidCharacter and collider.has_method("is_sitting") and collider.is_sitting():
			party_actions.append({"id": ACTION_STAND_UP, "label": "Stand Up"})
		elif collider is HumanoidCharacter and collider.is_downed_state():
			_append_downed_target_actions(party_actions, collider)
		elif collider is HumanoidCharacter and _selection_can_carry_target(collider):
			party_actions.append({"id": ACTION_CARRY, "label": "Carry"})
		if collider is HumanoidCharacter:
			party_actions.append({"id": ACTION_HEAL, "label": "Heal"})
		if collider is HumanoidCharacter and _selection_can_put_down_from_carrier(collider):
			party_actions.append({"id": ACTION_DROP_CARRY, "label": "Put Down"})
		_show_context_menu_actions(screen_position, party_actions)
		context_member = collider
		context_humanoid = collider if collider is HumanoidCharacter else null
		return false
	if collider is HumanoidCharacter and not party_manager.selected_members.is_empty():
		context_humanoid = collider
		var humanoid_actions: Array = []
		if collider.is_downed_state():
			_append_downed_target_actions(humanoid_actions, collider)
		elif collider.life_state == NpcRules.LifeState.DEAD or collider.life_state == NpcRules.LifeState.ASLEEP:
			if _selection_can_carry_target(collider):
				humanoid_actions.append({"id": ACTION_CARRY, "label": "Carry"})
			humanoid_actions.append({"id": ACTION_HEAL, "label": "Heal"})
		else:
			humanoid_actions.append({"id": ACTION_ATTACK, "label": "Attack"})
			humanoid_actions.append({"id": ACTION_HEAL, "label": "Heal"})
			if _selection_can_carry_target(collider):
				humanoid_actions.append({"id": ACTION_CARRY, "label": "Carry"})
		if _selection_can_put_down_from_carrier(collider):
			humanoid_actions.append({"id": ACTION_DROP_CARRY, "label": "Put Down"})
		if collider.has_conversation_definition() and collider.life_state == NpcRules.LifeState.ALIVE:
			humanoid_actions.append({"id": ACTION_TALK, "label": "Talk To"})
		if collider.has_method("get_merchant_role") and collider.get_merchant_role() != null and collider.life_state == NpcRules.LifeState.ALIVE:
			humanoid_actions.append({"id": ACTION_TRADE, "label": "Trade"})
		_show_context_menu_actions(screen_position, humanoid_actions)
		return false
	if collider is Node and collider.is_in_group("world_container") and not party_manager.selected_members.is_empty():
		context_container = collider
		if context_container.is_locked:
			_show_context_menu(screen_position, ACTION_UNLOCK_CONTAINER, "Unlock")
		else:
			_show_context_menu(screen_position, ACTION_OPEN_CONTAINER, "Open")
		return false
	if collider is Node and collider.is_in_group("world_item") and not party_manager.selected_members.is_empty():
		context_world_item = collider
		if Input.is_key_pressed(KEY_SHIFT):
			_assign_pickup_to_selection(context_world_item)
		else:
			_show_context_menu_actions(screen_position, [_get_pickup_item_action(context_world_item)])
		return false
	if collider is Node and collider.has_method("get_world_context_actions"):
		context_world_action_target = collider
		context_world_actions = collider.get_world_context_actions(_get_focused_party_member())
		if not context_world_actions.is_empty():
			var actions: Array = []
			for index in range(context_world_actions.size()):
				var action: Dictionary = context_world_actions[index]
				actions.append({"id": ACTION_WORLD_CONTEXT_BASE + index, "label": str(action.get("label", "Action"))})
			_show_context_menu_actions(screen_position, actions)
			return false
	return issue_move_command(screen_position)


func _is_hold_move_blocked(screen_position: Vector2) -> bool:
	var result := _raycast_target_from_screen(screen_position)
	if result.is_empty():
		return false
	var collider: Object = result["collider"]
	if collider is WorldActor:
		return true
	if collider is Node:
		return collider.is_in_group("sleepable_bed") or collider.is_in_group("sittable_seat") or collider.is_in_group("mining_resource") or collider.is_in_group("world_container") or collider.is_in_group("world_item") or collider.has_method("get_world_context_actions")
	return false


func _show_context_menu(screen_position: Vector2, action_id: int, label: String) -> void:
	_show_context_menu_actions(screen_position, [{"id": action_id, "label": label}])


func _show_context_menu_actions(screen_position: Vector2, actions: Array) -> void:
	if context_menu == null:
		return
	context_menu.clear()
	context_menu.remove_theme_color_override("font_color")
	context_menu.remove_theme_color_override("font_hover_color")
	if actions.size() == 1:
		var action_color = actions[0].get("color", null)
		if action_color is Color and (action_color as Color).a > 0.0:
			context_menu.add_theme_color_override("font_color", action_color)
			context_menu.add_theme_color_override("font_hover_color", (action_color as Color).lerp(Color.WHITE, 0.25))
	for action in actions:
		context_menu.add_item(action["label"], action["id"])
	context_menu.position = Vector2i(screen_position)
	context_menu.popup()


func _get_pickup_item_action(world_item) -> Dictionary:
	var action := {"id": ACTION_PICKUP_ITEM, "label": "Pick Up"}
	var actor := _get_focused_party_member()
	if ownership_controller == null or actor == null or not ownership_controller.has_method("get_take_item_label"):
		return action
	action["label"] = str(ownership_controller.call("get_take_item_label", actor, world_item))
	if ownership_controller.has_method("get_take_item_color"):
		var color = ownership_controller.call("get_take_item_color", actor, world_item)
		if color is Color and (color as Color).a > 0.0:
			action["color"] = color
	return action


func _apply_drag_selection() -> void:
	var rect := _get_selection_rect(left_mouse_press_position, get_viewport().get_mouse_position())
	var drag_selected: Array[WorldActor] = []
	for member in party_members:
		var sample_position: Vector3 = member.global_position + Vector3(0.0, 1.0, 0.0)
		if camera.is_position_behind(sample_position):
			continue
		var screen_point := camera.unproject_position(sample_position)
		if rect.has_point(screen_point):
			drag_selected.append(member)
	if Input.is_key_pressed(KEY_ALT):
		var merged_selection := party_manager.selected_members.duplicate()
		for member in drag_selected:
			if not merged_selection.has(member):
				merged_selection.append(member)
		party_manager.set_selection(merged_selection)
		if humanoid_details_controller != null and not merged_selection.is_empty():
			humanoid_details_controller.inspect_target(merged_selection[0])
		return
	party_manager.set_selection(drag_selected)
	if humanoid_details_controller != null and not drag_selected.is_empty():
		humanoid_details_controller.inspect_target(drag_selected[0])


func _pick_party_member(screen_position: Vector2) -> WorldActor:
	var result := _raycast_target_from_screen(screen_position)
	if result.is_empty():
		return null
	var collider: Object = result["collider"]
	if collider is WorldActor and collider.is_player_party_member():
		return collider
	return null


func _pick_humanoid(screen_position: Vector2):
	var result := _raycast_target_from_screen(screen_position)
	if result.is_empty():
		return null
	var collider: Object = result["collider"]
	if collider is HumanoidCharacter and collider.has_method("set_inspected"):
		return collider
	return null


func _pick_world_item(screen_position: Vector2):
	var result := _raycast_target_from_screen(screen_position)
	if result.is_empty():
		return null
	return _resolve_world_item_collider(result["collider"])


func _pick_inspectable_target(screen_position: Vector2):
	var result := _raycast_target_from_screen(screen_position)
	if result.is_empty():
		return null
	return _resolve_inspectable_target(result["collider"])


func _resolve_inspectable_target(collider: Object):
	if collider is WorldActor:
		return collider
	if not (collider is Node):
		return null
	var current: Node = collider as Node
	while current != null:
		if current is WorldActor:
			return current
		if _is_inspectable_node(current):
			return current
		current = current.get_parent()
	return null


func _is_inspectable_node(node: Node) -> bool:
	return node.is_in_group("mining_resource") \
		or node.is_in_group("scavenging_resource") \
		or node.is_in_group("world_container") \
		or node.is_in_group("world_item") \
		or node.is_in_group("sleepable_bed") \
		or node.is_in_group("sittable_seat") \
		or node.has_method("get_world_context_actions") \
		or node.get("display_name") != null


func issue_move_command(screen_position: Vector2, show_indicator: bool = true) -> bool:
	if party_manager.selected_members.is_empty():
		return false
	var ground_hit := _pick_ground_hit(screen_position)
	if ground_hit.is_empty():
		return false
	var target: Vector3 = ground_hit["position"]
	var surface_normal: Vector3 = ground_hit.get("normal", Vector3.UP)
	return issue_move_command_at_world(target, show_indicator, surface_normal)


func issue_move_command_at_world(target: Vector3, show_indicator: bool = true, surface_normal: Vector3 = Vector3.UP) -> bool:
	if party_manager.selected_members.is_empty():
		return false
	var indicator_position := target + surface_normal.normalized() * 0.08
	if show_indicator:
		_spawn_move_command_indicator(indicator_position)
	var center := Vector3.ZERO
	for member in party_manager.selected_members:
		center += member.global_position
	center /= party_manager.selected_members.size()
	var selected_count := party_manager.selected_members.size()
	var preserve_formation := absf(target.y - center.y) <= vertical_move_formation_height_threshold
	var use_close_formation := preserve_formation and selected_count > 1 and _horizontal_distance(target, center) <= close_move_command_radius
	var member_index := 0
	for member in party_manager.selected_members:
		var offset := Vector3.ZERO
		if use_close_formation:
			offset = _get_group_grid_move_offset(member_index, selected_count, close_move_command_spacing)
		elif preserve_formation:
			offset = member.global_position - center
			offset.y = 0.0
			if offset.length() > move_command_spacing:
				offset = offset.normalized() * move_command_spacing
		else:
			offset = _get_group_grid_move_offset(member_index, selected_count, move_command_spacing)
		var member_target := _project_move_command_target(target + offset, target, target.y)
		if member.has_method("stop_mining_assignment"):
			member.call("stop_mining_assignment")
		if member.has_method("stop_container_interaction"):
			member.call("stop_container_interaction")
		member.set_move_target(member_target)
		member_index += 1
	return true


func _get_cross_level_move_offset(member_index: int, selected_count: int) -> Vector3:
	return _get_group_grid_move_offset(member_index, selected_count, move_command_spacing)


func _get_group_grid_move_offset(member_index: int, selected_count: int, spacing: float) -> Vector3:
	if selected_count <= 1:
		return Vector3.ZERO
	var columns := ceili(sqrt(float(selected_count)))
	var rows := ceili(float(selected_count) / float(columns))
	var column := member_index % columns
	var row := int(float(member_index) / float(columns))
	var x := (float(column) - float(columns - 1) * 0.5) * spacing
	var z := (float(row) - float(rows - 1) * 0.5) * spacing
	return Vector3(x, 0.0, z)


func _horizontal_distance(from: Vector3, to: Vector3) -> float:
	return Vector2(from.x - to.x, from.z - to.z).length()


func _project_move_command_target(candidate: Vector3, fallback: Vector3, target_y: float) -> Vector3:
	if camera == null:
		return candidate
	var world_3d := camera.get_world_3d()
	if world_3d == null:
		return candidate
	var navigation_map: RID = world_3d.navigation_map
	if NavigationServer3D.map_get_iteration_id(navigation_map) == 0:
		return candidate
	var closest := NavigationServer3D.map_get_closest_point(navigation_map, candidate)
	if absf(closest.y - target_y) > MOVE_COMMAND_NAV_PROJECTION_VERTICAL_TOLERANCE:
		return fallback
	var horizontal_offset := Vector2(closest.x - candidate.x, closest.z - candidate.z).length()
	if horizontal_offset > move_command_spacing * 1.5:
		return fallback
	return Vector3(closest.x, target_y, closest.z)


func _pick_ground_position(screen_position: Vector2) -> Variant:
	var ground_hit := _pick_ground_hit(screen_position)
	return ground_hit.get("position", null) if not ground_hit.is_empty() else null


func _pick_ground_hit(screen_position: Vector2) -> Dictionary:
	var result := _raycast_from_screen(screen_position)
	if not result.is_empty():
		var collider: Object = result["collider"]
		var actor_collider := _resolve_actor_collider(collider)
		if collider != null and collider.has_method("project_click_to_active_level") and collider.has_method("should_project_click_shape") and building_visibility_controller != null and building_visibility_controller.get_active_building() == collider:
			var child_hit := _raycast_building_child_hit(screen_position, collider)
			if not child_hit.is_empty():
				return {"position": child_hit["position"], "normal": child_hit.get("normal", Vector3.UP)}
			var shape_index := int(result.get("shape", -1))
			if collider.should_project_click_shape(shape_index):
				var projected_ray_origin := camera.project_ray_origin(screen_position)
				var projected_ray_direction := camera.project_ray_normal(screen_position)
				var building_target: Variant = collider.project_click_to_active_level(projected_ray_origin, projected_ray_direction)
				if building_target != null:
					return {"position": building_target, "normal": Vector3.UP}
		if not (actor_collider != null and actor_collider.is_player_party_member()):
			return {"position": result["position"], "normal": result.get("normal", Vector3.UP)}
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	if absf(ray_direction.y) < 0.0001:
		return {}
	var distance := (GROUND_Y - ray_origin.y) / ray_direction.y
	if distance <= 0.0:
		return {}
	return {"position": ray_origin + ray_direction * distance, "normal": Vector3.UP}


func _raycast_past_collider(screen_position: Vector2, collider: Object) -> Dictionary:
	if not (collider is CollisionObject3D):
		return {}
	var collision_object := collider as CollisionObject3D
	return _raycast_from_screen(screen_position, [collision_object.get_rid()])


func _raycast_building_child_hit(screen_position: Vector2, building: Object) -> Dictionary:
	if not (building is Node):
		return {}
	var building_node := building as Node
	var hit := _raycast_past_collider(screen_position, building)
	if hit.is_empty():
		return {}
	var hit_collider: Object = hit.get("collider")
	if hit_collider is WorldActor and hit_collider.is_player_party_member():
		return {}
	if hit_collider is Node and building_node.is_ancestor_of(hit_collider):
		return hit
	return {}


func _raycast_target_from_screen(screen_position: Vector2) -> Dictionary:
	var excluded_rids: Array[RID] = []
	for _attempt in range(4):
		var result := _raycast_from_screen(screen_position, excluded_rids)
		if result.is_empty():
			return result
		var collider: Object = result["collider"]
		var actor_collider := _resolve_actor_collider(collider)
		if actor_collider != null:
			result["collider"] = actor_collider
			return result
		var obscured_item_hit := _raycast_obscured_world_item_hit(screen_position, collider)
		if not obscured_item_hit.is_empty():
			return obscured_item_hit
		if not _should_skip_building_target_hit(collider, int(result.get("shape", -1))):
			return result
		if not (collider is CollisionObject3D):
			return result
		var collision_object := collider as CollisionObject3D
		var collider_rid: RID = collision_object.get_rid()
		if excluded_rids.has(collider_rid):
			return result
		excluded_rids.append(collider_rid)
	return {}


func _raycast_obscured_world_item_hit(screen_position: Vector2, collider: Object) -> Dictionary:
	if not _is_world_item_occluder(collider):
		return {}
	var excluded_rids: Array[RID] = []
	if collider is CollisionObject3D:
		excluded_rids.append((collider as CollisionObject3D).get_rid())
	for _attempt in range(4):
		var hit := _raycast_from_screen(screen_position, excluded_rids)
		if hit.is_empty():
			return {}
		var world_item: Node = _resolve_world_item_collider(hit.get("collider"))
		if world_item != null:
			hit["collider"] = world_item
			return hit
		var hit_collider: Object = hit.get("collider")
		if not _is_world_item_occluder(hit_collider) or not (hit_collider is CollisionObject3D):
			return {}
		var hit_rid := (hit_collider as CollisionObject3D).get_rid()
		if excluded_rids.has(hit_rid):
			return {}
		excluded_rids.append(hit_rid)
	return {}


func _is_world_item_occluder(collider: Object) -> bool:
	if not (collider is Node):
		return false
	var node := collider as Node
	return _is_tabletop_collider(node) or node.is_in_group("world_building")


func _is_tabletop_collider(collider: Object) -> bool:
	if not (collider is Node):
		return false
	var current := collider as Node
	while current != null:
		if current.is_in_group("tabletop_item_spawner"):
			return true
		current = current.get_parent()
	return false


func _resolve_world_item_collider(collider: Object):
	if not (collider is Node):
		return null
	var current := collider as Node
	while current != null:
		if current.is_in_group("world_item"):
			return current
		current = current.get_parent()
	return null


func _should_skip_building_target_hit(collider: Object, shape_index: int) -> bool:
	if building_visibility_controller == null:
		return false
	if collider == null or collider != building_visibility_controller.get_active_building():
		return false
	if not collider.has_method("should_project_click_shape"):
		return false
	return collider.should_project_click_shape(shape_index)


func _resolve_actor_collider(collider: Object) -> WorldActor:
	if collider is WorldActor:
		return collider as WorldActor
	if not (collider is Node):
		return null
	var current: Node = collider as Node
	while current != null:
		if current is WorldActor:
			return current as WorldActor
		current = current.get_parent()
	return null


func _raycast_from_screen(screen_position: Vector2, excluded_rids: Array[RID] = []) -> Dictionary:
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_end := ray_origin + camera.project_ray_normal(screen_position) * 500.0
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.exclude = excluded_rids
	return camera.get_world_3d().direct_space_state.intersect_ray(query)


func _spawn_move_command_indicator(target: Vector3) -> void:
	var indicator := MOVE_COMMAND_INDICATOR_SCENE.instantiate()
	if indicator is Node3D:
		indicator.position = target
		root.add_child(indicator)
		if indicator.has_method("setup_at"):
			indicator.setup_at(target)


func _set_follow_target(member: WorldActor) -> void:
	party_manager.set_followed_member(member)
	camera_anchor = _get_anchor_position()
	_apply_camera_transform()


func _clear_follow_target() -> void:
	if party_manager.followed_member == null:
		return
	camera_anchor = _get_anchor_position()
	party_manager.clear_followed_member()
	_apply_camera_transform()


func _update_portraits() -> void:
	for index in range(min(party_members.size(), portrait_cards.size())):
		var member: WorldActor = party_members[index]
		var card: PartyPortraitCard = portrait_cards[index]
		var is_selected: bool = bool(member.get("is_selected"))
		var is_followed: bool = bool(member.get("is_focused"))
		card.visible = _should_show_member_in_active_squad(member)
		card.apply_state(is_selected, is_followed)


func _setup_squad_tabs() -> void:
	if squad_all_button != null:
		squad_all_button.toggled.connect(_on_all_squads_tab_toggled)
	if squad_add_button != null:
		squad_add_button.pressed.connect(_on_add_squad_pressed)
	_ensure_squad_menu()


func _refresh_squad_tabs() -> void:
	if squad_tab_row == null:
		return
	_sync_squad_names()
	for container in squad_tab_containers.values():
		if container is Control and is_instance_valid(container):
			squad_tab_row.remove_child(container)
			container.queue_free()
	squad_tab_buttons.clear()
	squad_tab_menu_buttons.clear()
	squad_tab_containers.clear()
	for squad_name in squad_names:
		var tab_group := HBoxContainer.new()
		tab_group.name = _get_squad_tab_node_name(squad_name)
		tab_group.custom_minimum_size = Vector2(116.0, 22.0)
		tab_group.add_theme_constant_override("separation", 0)
		squad_tab_row.add_child(tab_group)
		var button := Button.new()
		button.text = _format_squad_tab_label(squad_name)
		button.name = "TitleButton"
		button.custom_minimum_size = Vector2(92.0, 22.0)
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 10)
		button.toggled.connect(_on_squad_tab_toggled.bind(squad_name))
		button.gui_input.connect(_on_squad_tab_gui_input.bind(squad_name))
		_set_command_segment_position(button, SEGMENT_LEFT)
		tab_group.add_child(button)
		var menu_button := Button.new()
		menu_button.text = "..."
		menu_button.name = "MenuButton"
		menu_button.custom_minimum_size = Vector2(24.0, 22.0)
		menu_button.toggle_mode = true
		menu_button.focus_mode = Control.FOCUS_NONE
		menu_button.add_theme_font_size_override("font_size", 10)
		menu_button.pressed.connect(_on_squad_menu_button_pressed.bind(squad_name, menu_button))
		_set_command_segment_position(menu_button, SEGMENT_RIGHT)
		tab_group.add_child(menu_button)
		if squad_add_button != null:
			squad_tab_row.move_child(tab_group, squad_add_button.get_index())
		squad_tab_buttons[squad_name] = button
		squad_tab_menu_buttons[squad_name] = menu_button
		squad_tab_containers[squad_name] = tab_group
	if squad_all_button != null:
		squad_all_button.text = "All (%d)" % party_members.size()
	_update_squad_tab_styles()
	_update_squad_command_strip()
	_update_portraits()


func _sync_squad_names() -> void:
	var names: Array[String] = []
	for existing_name in squad_names:
		var normalized_existing := str(existing_name).strip_edges()
		if not normalized_existing.is_empty() and not names.has(normalized_existing):
			names.append(normalized_existing)
	for member in party_members:
		var squad_name := _normalize_party_member_squad(member)
		if not names.has(squad_name):
			names.append(squad_name)
	if names.is_empty():
		names.append(DEFAULT_PLAYER_SQUAD_NAME)
	squad_names = names
	if not active_squad_filter.is_empty() and not squad_names.has(active_squad_filter):
		active_squad_filter = ALL_SQUADS_FILTER


func _normalize_party_member_squad(member: WorldActor) -> String:
	if member == null:
		return DEFAULT_PLAYER_SQUAD_NAME
	var normalized_name := member.squad_name.strip_edges()
	if normalized_name.is_empty() or normalized_name == "Default":
		normalized_name = DEFAULT_PLAYER_SQUAD_NAME
		member.squad_name = normalized_name
	return normalized_name


func _should_show_member_in_active_squad(member: WorldActor) -> bool:
	if member == null or active_squad_filter.is_empty():
		return true
	return _normalize_party_member_squad(member) == active_squad_filter


func _get_squad_member_count(squad_name: String) -> int:
	var count := 0
	for member in party_members:
		if _normalize_party_member_squad(member) == squad_name:
			count += 1
	return count


func _on_all_squads_tab_toggled(button_pressed: bool) -> void:
	if not button_pressed and active_squad_filter == ALL_SQUADS_FILTER:
		_update_squad_tab_styles()
		return
	active_squad_filter = ALL_SQUADS_FILTER
	_update_squad_tab_styles()
	_update_squad_command_strip()
	_update_portraits()


func _on_squad_tab_toggled(button_pressed: bool, squad_name: String) -> void:
	if not button_pressed and active_squad_filter == squad_name:
		_update_squad_tab_styles()
		return
	active_squad_filter = squad_name
	_update_squad_tab_styles()
	_update_squad_command_strip()
	_update_portraits()


func _on_add_squad_pressed() -> void:
	var squad_name := _get_next_squad_name()
	if not squad_names.has(squad_name):
		squad_names.append(squad_name)
	active_squad_filter = squad_name
	_refresh_squad_tabs()


func _get_next_squad_name() -> String:
	var index := 1
	while squad_names.has("Squad %d" % index):
		index += 1
	return "Squad %d" % index


func _get_squad_tab_node_name(squad_name: String) -> String:
	return "SquadTab%s" % squad_name.replace(" ", "").replace("/", "").replace(":", "")


func _format_squad_tab_label(squad_name: String) -> String:
	return "%s (%d)" % [squad_name, _get_squad_member_count(squad_name)]


func _update_squad_tab_styles() -> void:
	_set_command_toggle(squad_all_button, active_squad_filter == ALL_SQUADS_FILTER, false)
	for squad_name in squad_tab_buttons.keys():
		var squad_name_text := str(squad_name)
		var is_active: bool = active_squad_filter == squad_name_text
		_set_command_toggle(squad_tab_buttons[squad_name_text] as Button, is_active, false)
		_set_command_toggle(squad_tab_menu_buttons[squad_name_text] as Button, is_active, false)
	_apply_command_button_style(squad_add_button, false, false)
	_update_squad_command_strip()


func _update_squad_command_strip() -> void:
	if squad_name_label != null:
		squad_name_label.text = "All Squads" if active_squad_filter == ALL_SQUADS_FILTER else active_squad_filter
	_set_command_toggle(squad_formation_button, false, true)
	_set_command_toggle(squad_ai_button, false, true)


func _ensure_squad_menu() -> void:
	if hud_layer == null:
		return
	if squad_menu == null:
		squad_menu = hud_layer.get_node_or_null("SquadContextMenu") as PopupMenu
		if squad_menu == null:
			squad_menu = PopupMenu.new()
			squad_menu.name = "SquadContextMenu"
			hud_layer.add_child(squad_menu)
	var menu_callable := Callable(self, "_on_squad_menu_id_pressed")
	if not squad_menu.id_pressed.is_connected(menu_callable):
		squad_menu.id_pressed.connect(menu_callable)
	squad_menu.clear()
	squad_menu.add_item("Rename", SQUAD_MENU_RENAME)
	if squad_rename_dialog == null:
		squad_rename_dialog = hud_layer.get_node_or_null("SquadRenameDialog") as AcceptDialog
		if squad_rename_dialog == null:
			squad_rename_dialog = AcceptDialog.new()
			squad_rename_dialog.name = "SquadRenameDialog"
			squad_rename_dialog.title = "Rename Squad"
			squad_rename_dialog.min_size = Vector2i(280, 92)
			hud_layer.add_child(squad_rename_dialog)
			var margin := MarginContainer.new()
			margin.add_theme_constant_override("margin_left", 12)
			margin.add_theme_constant_override("margin_top", 10)
			margin.add_theme_constant_override("margin_right", 12)
			margin.add_theme_constant_override("margin_bottom", 8)
			squad_rename_dialog.add_child(margin)
			squad_rename_line_edit = LineEdit.new()
			squad_rename_line_edit.custom_minimum_size = Vector2(240.0, 28.0)
			squad_rename_line_edit.placeholder_text = "Squad name"
			margin.add_child(squad_rename_line_edit)
		else:
			squad_rename_line_edit = squad_rename_dialog.get_node_or_null("MarginContainer/LineEdit") as LineEdit
	if squad_rename_line_edit != null:
		var submitted_callable := Callable(self, "_on_squad_rename_text_submitted")
		if not squad_rename_line_edit.text_submitted.is_connected(submitted_callable):
			squad_rename_line_edit.text_submitted.connect(submitted_callable)
	var confirmed_callable := Callable(self, "_on_squad_rename_confirmed")
	if not squad_rename_dialog.confirmed.is_connected(confirmed_callable):
		squad_rename_dialog.confirmed.connect(confirmed_callable)


func _on_squad_menu_button_pressed(squad_name: String, button: Button) -> void:
	if button != null:
		button.set_pressed_no_signal(active_squad_filter == squad_name)
		_show_squad_menu(squad_name, button.get_screen_position() + Vector2(0.0, button.size.y))


func _on_squad_tab_gui_input(event: InputEvent, squad_name: String) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			_show_squad_menu(squad_name, get_viewport().get_mouse_position())
			get_viewport().set_input_as_handled()


func _show_squad_menu(squad_name: String, screen_position: Vector2) -> void:
	if squad_name.strip_edges().is_empty():
		return
	_ensure_squad_menu()
	if squad_menu == null:
		return
	squad_menu_target_name = squad_name
	squad_menu.position = Vector2i(screen_position)
	squad_menu.popup()


func _on_squad_menu_id_pressed(id: int) -> void:
	match id:
		SQUAD_MENU_RENAME:
			_open_squad_rename_dialog(squad_menu_target_name)


func _open_squad_rename_dialog(squad_name: String) -> void:
	if squad_name.strip_edges().is_empty():
		return
	_ensure_squad_menu()
	if squad_rename_dialog == null or squad_rename_line_edit == null:
		return
	squad_menu_target_name = squad_name
	squad_rename_dialog.title = "Rename %s" % squad_name
	squad_rename_line_edit.text = squad_name
	squad_rename_dialog.popup_centered(Vector2i(280, 92))
	call_deferred("_focus_squad_rename_line_edit")


func _focus_squad_rename_line_edit() -> void:
	if squad_rename_line_edit == null:
		return
	squad_rename_line_edit.grab_focus()
	squad_rename_line_edit.select_all()


func _on_squad_rename_text_submitted(text: String) -> void:
	_confirm_squad_rename(text)
	if squad_rename_dialog != null:
		squad_rename_dialog.hide()


func _on_squad_rename_confirmed() -> void:
	if squad_rename_line_edit == null:
		return
	_confirm_squad_rename(squad_rename_line_edit.text)


func _confirm_squad_rename(raw_name: String) -> void:
	var old_name := squad_menu_target_name.strip_edges()
	var new_name := raw_name.strip_edges()
	if old_name.is_empty() or new_name.is_empty() or old_name == new_name:
		return
	if new_name.to_lower() == "all" or new_name.to_lower() == "default":
		_show_center_notice("Squad name unavailable")
		return
	if _squad_name_exists(new_name, old_name):
		_show_center_notice("Squad name already exists")
		return
	for index in range(squad_names.size()):
		if squad_names[index] == old_name:
			squad_names[index] = new_name
	for member in party_members:
		if _normalize_party_member_squad(member) == old_name:
			member.squad_name = new_name
	if active_squad_filter == old_name:
		active_squad_filter = new_name
	squad_menu_target_name = new_name
	_refresh_squad_tabs()


func _squad_name_exists(squad_name: String, ignored_name: String = "") -> bool:
	var normalized_name := squad_name.strip_edges().to_lower()
	var ignored_normalized := ignored_name.strip_edges().to_lower()
	for existing_name in squad_names:
		var normalized_existing := str(existing_name).strip_edges().to_lower()
		if normalized_existing == normalized_name and normalized_existing != ignored_normalized:
			return true
	return false


func _setup_command_bar() -> void:
	_set_command_segment_position(walk_button, SEGMENT_LEFT)
	_set_command_segment_position(running_button, SEGMENT_MIDDLE)
	_set_command_segment_position(sneaking_button, SEGMENT_RIGHT)
	_set_command_segment_position(aggressive_button, SEGMENT_LEFT)
	_set_command_segment_position(defensive_button, SEGMENT_MIDDLE)
	_set_command_segment_position(passive_button, SEGMENT_RIGHT)
	_set_command_segment_position(auto_heal_button, SEGMENT_LEFT)
	_set_command_segment_position(auto_burn_rustdead_button, SEGMENT_RIGHT)
	if walk_button != null:
		walk_button.pressed.connect(_on_movement_button_pressed.bind(MOVEMENT_MODE_WALK))
	if running_button != null:
		running_button.pressed.connect(_on_movement_button_pressed.bind(MOVEMENT_MODE_RUN))
	if sneaking_button != null:
		sneaking_button.pressed.connect(_on_movement_button_pressed.bind(MOVEMENT_MODE_SNEAK))
	if auto_heal_button != null:
		auto_heal_button.toggled.connect(_on_auto_heal_button_toggled)
	if auto_burn_rustdead_button != null:
		auto_burn_rustdead_button.toggled.connect(_on_auto_burn_rustdead_button_toggled)
	if aggressive_button != null:
		aggressive_button.pressed.connect(_on_stance_button_pressed.bind(NpcRules.CombatStance.AGGRESSIVE))
	if defensive_button != null:
		defensive_button.pressed.connect(_on_stance_button_pressed.bind(NpcRules.CombatStance.DEFENSIVE))
	if passive_button != null:
		passive_button.pressed.connect(_on_stance_button_pressed.bind(NpcRules.CombatStance.PASSIVE))
	_update_squad_command_strip()


func _update_command_bar() -> void:
	if walk_button == null or running_button == null or sneaking_button == null or auto_heal_button == null or auto_burn_rustdead_button == null or aggressive_button == null or defensive_button == null or passive_button == null:
		return
	var has_selection := not party_manager.selected_members.is_empty()
	if not has_selection:
		_set_command_toggle(walk_button, false, true)
		_set_command_toggle(running_button, false, true)
		_set_command_toggle(sneaking_button, false, true)
		_set_command_toggle(auto_heal_button, false, true)
		_set_command_toggle(auto_burn_rustdead_button, false, true)
		_set_command_toggle(aggressive_button, false, true)
		_set_command_toggle(defensive_button, false, true)
		_set_command_toggle(passive_button, false, true)
		return
	var any_walking := false
	var all_walking := true
	var any_running := false
	var all_running := true
	var any_sneaking := false
	var all_sneaking := true
	var any_auto_heal := false
	var all_auto_heal := true
	var any_auto_burn := false
	var all_auto_burn := true
	var first_stance: int = party_manager.selected_members[0].combat_stance
	var mixed_stance := false
	for member in party_manager.selected_members:
		var member_running: bool = member.is_running_enabled() or member.running
		var member_sneaking: bool = member.sneaking
		var member_walking := not member_running and not member_sneaking
		var member_auto_heal: bool = member.has_method("is_auto_heal_enabled") and member.is_auto_heal_enabled()
		var member_auto_burn: bool = member.has_method("is_auto_burn_rustdead_enabled") and member.is_auto_burn_rustdead_enabled()
		if member_walking:
			any_walking = true
		else:
			all_walking = false
		if member_running:
			any_running = true
		else:
			all_running = false
		if member_sneaking:
			any_sneaking = true
		else:
			all_sneaking = false
		if member_auto_heal:
			any_auto_heal = true
		else:
			all_auto_heal = false
		if member_auto_burn:
			any_auto_burn = true
		else:
			all_auto_burn = false
		if member.combat_stance != first_stance:
			mixed_stance = true
	_set_command_toggle(walk_button, any_walking, false, any_walking and not all_walking)
	_set_command_toggle(running_button, any_running, false, any_running and not all_running)
	_set_command_toggle(sneaking_button, any_sneaking, false, any_sneaking and not all_sneaking)
	_set_command_toggle(auto_heal_button, any_auto_heal, false, any_auto_heal and not all_auto_heal)
	_set_command_toggle(auto_burn_rustdead_button, any_auto_burn, false, any_auto_burn and not all_auto_burn)
	_set_command_toggle(aggressive_button, not mixed_stance and first_stance == NpcRules.CombatStance.AGGRESSIVE, false)
	_set_command_toggle(defensive_button, not mixed_stance and first_stance == NpcRules.CombatStance.DEFENSIVE, false)
	_set_command_toggle(passive_button, not mixed_stance and first_stance == NpcRules.CombatStance.PASSIVE, false)


func _set_command_toggle(button: Button, active: bool, disabled: bool, mixed: bool = false) -> void:
	if button == null:
		return
	button.disabled = disabled
	button.set_pressed_no_signal(active)
	_apply_command_button_style(button, active, disabled, mixed)


func _set_command_segment_position(button: Button, segment_position: int) -> void:
	if button == null:
		return
	button.set_meta("command_segment_position", segment_position)


func _apply_command_button_style(button: Button, active: bool, disabled: bool, mixed: bool = false) -> void:
	if button == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.047, 0.043, 0.96)
	style.border_color = Color(0.28, 0.23, 0.16, 1.0)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_right = 3
	style.corner_radius_bottom_left = 3
	match int(button.get_meta("command_segment_position", SEGMENT_SINGLE)):
		SEGMENT_LEFT:
			style.corner_radius_top_right = 0
			style.corner_radius_bottom_right = 0
		SEGMENT_MIDDLE:
			style.corner_radius_top_left = 0
			style.corner_radius_bottom_left = 0
			style.corner_radius_top_right = 0
			style.corner_radius_bottom_right = 0
		SEGMENT_RIGHT:
			style.corner_radius_top_left = 0
			style.corner_radius_bottom_left = 0
	if active:
		style.bg_color = Color(0.22, 0.17, 0.08, 0.98)
		style.border_color = Color(0.95, 0.7, 0.32, 1.0) if not mixed else Color(0.72, 0.56, 0.28, 1.0)
		style.set_border_width_all(2)
	if disabled:
		style.bg_color = Color(0.055, 0.052, 0.049, 0.7)
		style.border_color = Color(0.18, 0.16, 0.13, 1.0)
		style.set_border_width_all(1)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = style.bg_color.lightened(0.08)
	var pressed := style.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.28, 0.21, 0.09, 1.0)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", style)
	button.add_theme_color_override("font_color", Color(0.88, 0.82, 0.68, 1.0) if not disabled else Color(0.38, 0.36, 0.32, 1.0))
	button.add_theme_color_override("font_hover_color", Color(0.98, 0.88, 0.62, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(1.0, 0.88, 0.48, 1.0))
	button.add_theme_font_size_override("font_size", 9 if button.text.length() > 8 else 10)


func _update_progress_bars() -> void:
	if progress_layer == null:
		return
	for member in party_members:
		var bar: ProgressBar = work_progress_bars.get(member)
		if bar == null:
			continue
		var progress_ratio := _get_member_work_progress_ratio(member)
		if progress_ratio <= 0.0:
			bar.visible = false
			continue
		var world_position: Vector3 = member.global_position + Vector3(0.0, 2.35, 0.0)
		if camera.is_position_behind(world_position):
			bar.visible = false
			continue
		var screen_position := camera.unproject_position(world_position)
		bar.visible = true
		bar.position = screen_position - Vector2(bar.size.x * 0.5, bar.size.y * 0.5)
		bar.value = progress_ratio * 100.0


func _get_member_work_progress_ratio(member: WorldActor) -> float:
	if member == null:
		return 0.0
	if member.has_method("is_actively_mining") and member.call("is_actively_mining"):
		return float(member.call("get_mining_progress_ratio"))
	if member.has_method("is_actively_scavenging") and bool(member.call("is_actively_scavenging")):
		return float(member.call("get_scavenging_progress_ratio"))
	return 0.0


func _update_selection_rect(current_position: Vector2) -> void:
	selection_rect.visible = is_drag_selecting
	if not is_drag_selecting:
		return
	var rect := _get_selection_rect(left_mouse_press_position, current_position)
	selection_rect.position = rect.position
	selection_rect.size = rect.size


func _get_selection_rect(start: Vector2, finish: Vector2) -> Rect2:
	var rect_position := Vector2(minf(start.x, finish.x), minf(start.y, finish.y))
	var rect_size := Vector2(absf(finish.x - start.x), absf(finish.y - start.y))
	return Rect2(rect_position, rect_size)


func _get_anchor_position() -> Vector3:
	if party_manager.followed_member != null:
		return party_manager.followed_member.get_follow_anchor_position() + Vector3(0.0, FOLLOW_CAMERA_HEIGHT, 0.0)
	return camera_anchor


func _apply_camera_transform() -> void:
	camera_rig.global_position = _get_anchor_position()
	camera_rig.rotation = Vector3(0.0, camera_yaw, 0.0)
	camera_pivot.rotation = Vector3(camera_pitch, 0.0, 0.0)
	camera.rotation = Vector3.ZERO
	camera.position = Vector3(0.0, 0.0, camera_distance)
	_clamp_camera_above_floor()


func _clamp_camera_above_floor() -> void:
	if camera == null:
		return
	var minimum_camera_y := GROUND_Y + CAMERA_FLOOR_CLEARANCE
	if camera.global_position.y >= minimum_camera_y:
		return
	var adjusted_position := camera.global_position
	adjusted_position.y = minimum_camera_y
	camera.global_position = adjusted_position


func _on_portrait_pressed(member: WorldActor, double_click: bool, add_select: bool) -> void:
	if add_select:
		party_manager.add_selection(member)
	else:
		party_manager.select_only(member)
	if humanoid_details_controller != null:
		humanoid_details_controller.inspect_target(member)
	if double_click:
		_set_follow_target(member)


func _on_movement_button_pressed(mode: int) -> void:
	var any_failed := false
	for member in party_manager.selected_members:
		match mode:
			MOVEMENT_MODE_WALK:
				member.set_running_enabled(false)
				member.set_sneaking_enabled(false)
			MOVEMENT_MODE_RUN:
				if not member.set_running_enabled(true):
					any_failed = true
			MOVEMENT_MODE_SNEAK:
				member.set_sneaking_enabled(true)
	if any_failed and mode == MOVEMENT_MODE_RUN:
		_show_center_notice("Too Exhausted to run")
	_update_command_bar()


func _on_auto_heal_button_toggled(button_pressed: bool) -> void:
	for member in party_manager.selected_members:
		if member.has_method("set_auto_heal_enabled"):
			member.set_auto_heal_enabled(button_pressed)
	_update_command_bar()


func _on_auto_burn_rustdead_button_toggled(button_pressed: bool) -> void:
	for member in party_manager.selected_members:
		if member.has_method("set_auto_burn_rustdead_enabled"):
			member.set_auto_burn_rustdead_enabled(button_pressed)
	_update_command_bar()


func _on_stance_button_pressed(stance: int) -> void:
	for member in party_manager.selected_members:
		member.set_combat_stance(stance)
	_update_command_bar()


func _on_inspector_action_requested(target, action_key: String) -> void:
	if target == null or not is_instance_valid(target):
		return
	if action_key.begins_with("world:"):
		_perform_direct_world_context_action(target, action_key.substr("world:".length()))
		return
	match action_key:
		"inventory":
			_perform_inspector_inventory_action(target)
		"order":
			_perform_inspector_order_action(target)
		"mine":
			if target is Node:
				for member in party_manager.selected_members:
					if member.has_method("assign_mining_resource") and (ownership_controller == null or ownership_controller.request_interaction(member, target, "Mining")):
						member.call("assign_mining_resource", target)
		"open_container":
			if target is Node:
				for member in party_manager.selected_members:
					if member.has_method("assign_open_container") and (ownership_controller == null or ownership_controller.request_interaction(member, target, "Opening")):
						member.call("assign_open_container", target)
		"unlock_container":
			_perform_unlock_action(target)
		"pickup_item":
			_assign_pickup_to_selection(target)
		"attack":
			if target is HumanoidCharacter:
				_assign_attack_to_selection(target)
		"trade":
			if target is HumanoidCharacter:
				for member in party_manager.selected_members:
					if member.has_method("assign_trade_target"):
						member.call("assign_trade_target", target)
		"talk":
			if target is HumanoidCharacter:
				for member in party_manager.selected_members:
					if member.has_method("assign_conversation_target"):
						member.call("assign_conversation_target", target)
		"heal":
			if target is HumanoidCharacter:
				for member in party_manager.selected_members:
					if member.has_method("assign_heal_target"):
						member.call("assign_heal_target", target)
		"finish_off":
			if target is HumanoidCharacter:
				for member in party_manager.selected_members:
					if member.has_method("assign_finish_off_target"):
						member.call("assign_finish_off_target", target)
		"carry":
			if target is HumanoidCharacter:
				for member in party_manager.selected_members:
					if member.has_method("assign_carry_target"):
						member.call("assign_carry_target", target)
		"wake_up", "stand_up":
			if target is HumanoidCharacter and target.has_method("wake_up_from_rest"):
				target.wake_up_from_rest()


func _perform_inspector_inventory_action(target) -> void:
	if not (target is WorldActor):
		return
	var focused_member := _get_focused_party_member()
	if focused_member != null and focused_member != target:
		var trade_distance := float(focused_member.get("trade_interaction_distance")) if focused_member.get("trade_interaction_distance") != null else 3.0
		if focused_member.global_position.distance_to(target.global_position) <= trade_distance:
			inventory_controller.open_inventory_pair(focused_member, target)
		elif focused_member.has_method("assign_trade_target"):
			focused_member.call("assign_trade_target", target)
	elif target.is_player_party_member():
		inventory_controller.open_inventory_for_member(target)


func _perform_inspector_order_action(target) -> void:
	var member := target as HumanoidCharacter
	if member == null:
		return
	var service_area := _get_bar_service_area_for_seated_member(member)
	if service_area == null:
		_show_center_notice("Sit at a bar table first")
		return
	if not service_area.has_method("call_waiter_for_customer"):
		_show_center_notice("No waiter service here")
		return
	var result = service_area.call("call_waiter_for_customer", member)
	if result is Dictionary and bool(result.get("allowed", false)):
		return
	var message := str(result.get("message", "No waiter available")) if result is Dictionary else "No waiter available"
	_show_center_notice(message)


func _get_bar_service_area_for_seated_member(member: HumanoidCharacter) -> BarServiceArea:
	if member == null or not member.has_method("get_current_seat_target"):
		return null
	var seat = member.call("get_current_seat_target")
	if seat != null and is_instance_valid(seat) and seat.has_method("get_bar_service_area"):
		return seat.call("get_bar_service_area") as BarServiceArea
	return null


func _perform_direct_world_context_action(target, action_key: String) -> void:
	if action_key.is_empty() or target == null or not target.has_method("perform_world_context_action"):
		return
	var message := str(target.perform_world_context_action(action_key, party_manager.selected_members))
	if message.is_empty():
		return
	if target is Node3D:
		_spawn_world_notice(target.global_position + Vector3(0.0, 1.6, 0.0), message)
	else:
		_show_center_notice(message)


func _perform_unlock_action(target) -> void:
	if target == null:
		return
	var actor := _get_focused_party_member()
	if target.has_method("attempt_unlock"):
		var unlocked := bool(target.call("attempt_unlock", actor))
		if unlocked and target is Node and _has_property(target, "is_locked"):
			target.set("is_locked", false)
		var message := "Unlocked" if unlocked else "Lock too hard"
		if target is Node3D:
			_spawn_world_notice((target as Node3D).global_position + Vector3(0.0, 1.6, 0.0), message)
		else:
			_show_center_notice(message)
		return
	if target is Node3D:
		_spawn_world_notice((target as Node3D).global_position + Vector3(0.0, 1.6, 0.0), "Lockpicking not implemented")
	else:
		_show_center_notice("Lockpicking not implemented")


func _on_context_menu_id_pressed(action_id: int) -> void:
	if action_id >= ACTION_WORLD_CONTEXT_BASE:
		_perform_world_context_action(action_id - ACTION_WORLD_CONTEXT_BASE)
		return
	match action_id:
		ACTION_INVENTORY:
			var focused_member := _get_focused_party_member()
			if focused_member != null and context_member != null and focused_member != context_member:
				var trade_distance := float(focused_member.get("trade_interaction_distance")) if focused_member.get("trade_interaction_distance") != null else 3.0
				if focused_member.global_position.distance_to(context_member.global_position) <= trade_distance:
					inventory_controller.open_inventory_pair(focused_member, context_member)
				elif focused_member.has_method("assign_trade_target"):
					focused_member.call("assign_trade_target", context_member)
			elif context_member != null:
				inventory_controller.open_inventory_for_member(context_member)
		ACTION_MINE:
			if context_resource != null:
				for member in party_manager.selected_members:
					if member.has_method("assign_mining_resource") and (ownership_controller == null or ownership_controller.request_interaction(member, context_resource, "Mining")):
						member.call("assign_mining_resource", context_resource)
		ACTION_OPEN_CONTAINER:
			if context_container != null:
				for member in party_manager.selected_members:
					if member.has_method("assign_open_container") and (ownership_controller == null or ownership_controller.request_interaction(member, context_container, "Opening")):
						member.call("assign_open_container", context_container)
		ACTION_UNLOCK_CONTAINER:
			if context_container != null:
				_perform_unlock_action(context_container)
		ACTION_ATTACK:
			if context_humanoid != null:
				_assign_attack_to_selection(context_humanoid)
		ACTION_TRADE:
			if context_humanoid != null:
				for member in party_manager.selected_members:
					if member.has_method("assign_trade_target"):
						member.call("assign_trade_target", context_humanoid)
		ACTION_TALK:
			if context_humanoid != null:
				for member in party_manager.selected_members:
					if member.has_method("assign_conversation_target"):
						member.call("assign_conversation_target", context_humanoid)
		ACTION_HEAL:
			if context_humanoid != null:
				for member in party_manager.selected_members:
					if member.has_method("assign_heal_target"):
						member.call("assign_heal_target", context_humanoid)
		ACTION_FINISH_OFF:
			if context_humanoid != null:
				for member in party_manager.selected_members:
					if member.has_method("assign_finish_off_target"):
						member.call("assign_finish_off_target", context_humanoid)
		ACTION_CARRY:
			if context_humanoid != null:
				for member in party_manager.selected_members:
					if member.has_method("assign_carry_target"):
						member.call("assign_carry_target", context_humanoid)
		ACTION_DROP_CARRY:
			for member in party_manager.selected_members:
				if member.has_method("drop_carried_character"):
					member.call("drop_carried_character")
		ACTION_SLEEP:
			if context_sleep_target != null:
				for member in party_manager.selected_members:
					if member.has_method("assign_sleep_target"):
						member.call("assign_sleep_target", context_sleep_target)
		ACTION_PLACE_IN_BED:
			if context_sleep_target != null:
				for member in party_manager.selected_members:
					if member.has_method("is_carrying_someone") and bool(member.call("is_carrying_someone")) and member.has_method("assign_place_carried_in_bed_target"):
						member.call("assign_place_carried_in_bed_target", context_sleep_target)
		ACTION_SIT:
			if context_seat_target != null:
				for member in party_manager.selected_members:
					if member.has_method("assign_seat_target"):
						member.call("assign_seat_target", context_seat_target)
		ACTION_WAKE_UP:
			if context_humanoid != null and context_humanoid.has_method("wake_up_from_rest"):
				context_humanoid.wake_up_from_rest()
		ACTION_STAND_UP:
			if context_humanoid != null and context_humanoid.has_method("wake_up_from_rest"):
				context_humanoid.wake_up_from_rest()
		ACTION_PICKUP_ITEM:
			if context_world_item != null:
				_assign_pickup_to_selection(context_world_item)


func _perform_world_context_action(action_index: int) -> void:
	if context_world_action_target == null or action_index < 0 or action_index >= context_world_actions.size():
		return
	var action: Dictionary = context_world_actions[action_index]
	var action_key := str(action.get("key", ""))
	if action_key.is_empty() or not context_world_action_target.has_method("perform_world_context_action"):
		return
	var message := str(context_world_action_target.perform_world_context_action(action_key, party_manager.selected_members))
	if not message.is_empty() and context_world_action_target is Node3D:
		_spawn_world_notice(context_world_action_target.global_position + Vector3(0.0, 1.6, 0.0), message)
	elif not message.is_empty():
		_show_center_notice(message)


func _assign_pickup_to_selection(world_item) -> void:
	if world_item == null or party_manager.selected_members.is_empty():
		return
	var best_member: WorldActor
	var best_distance := INF
	for member in party_manager.selected_members:
		var distance := member.global_position.distance_squared_to(world_item.global_position)
		if distance < best_distance:
			best_distance = distance
			best_member = member
	if best_member != null and best_member.has_method("assign_pickup_item"):
		best_member.call("assign_pickup_item", world_item)


func _assign_attack_to_selection(target: WorldActor) -> void:
	if target == null or party_manager.selected_members.is_empty():
		return
	if party_manager.selected_members.size() == 1:
		party_manager.selected_members[0].assign_attack_target(target)
		return
	var candidates := _get_group_attack_targets(target)
	var planned_pressure := {}
	for candidate in candidates:
		planned_pressure[candidate.get_instance_id()] = COMBAT_COORDINATOR.get_pressure_on(candidate)
	for member in party_manager.selected_members:
		var attack_target := _choose_group_attack_target(member, candidates, planned_pressure)
		if attack_target == null:
			attack_target = target
		member.assign_attack_target(attack_target)
		var target_id := attack_target.get_instance_id()
		planned_pressure[target_id] = int(planned_pressure.get(target_id, 0)) + 1


func _get_group_attack_targets(target: WorldActor) -> Array[WorldActor]:
	var candidates: Array[WorldActor] = []
	if target == null or not is_instance_valid(target):
		return candidates
	candidates.append(target)
	if not is_inside_tree():
		return candidates
	var radius_squared := group_attack_target_scan_radius * group_attack_target_scan_radius
	for node in get_tree().get_nodes_in_group(COMBAT_COORDINATOR.COMBAT_ACTOR_GROUP):
		if not (node is WorldActor):
			continue
		var candidate: WorldActor = node
		if candidate == target or candidate.life_state != NpcRules.LifeState.ALIVE:
			continue
		if target.global_position.distance_squared_to(candidate.global_position) > radius_squared:
			continue
		if _selection_has_hostility_with(candidate):
			candidates.append(candidate)
	return candidates


func _selection_has_hostility_with(target: WorldActor) -> bool:
	if target == null:
		return false
	for member in party_manager.selected_members:
		if member != null and member != target and member.has_hostility_with(target):
			return true
	return false


func _choose_group_attack_target(member: WorldActor, candidates: Array[WorldActor], planned_pressure: Dictionary) -> WorldActor:
	if member == null or candidates.is_empty():
		return null
	var best_target: WorldActor
	var best_score := INF
	for candidate in candidates:
		if candidate == null or not is_instance_valid(candidate) or candidate == member:
			continue
		if candidate.life_state != NpcRules.LifeState.ALIVE:
			continue
		if candidate != candidates[0] and not member.has_hostility_with(candidate):
			continue
		var pressure := int(planned_pressure.get(candidate.get_instance_id(), 0))
		var active_slot_limit := COMBAT_COORDINATOR.get_active_attack_slot_limit(candidate)
		var saturation_penalty := 10000.0 if pressure >= active_slot_limit else 0.0
		var distance_score := member.global_position.distance_squared_to(candidate.global_position) / maxf(group_attack_target_scan_radius, 1.0)
		var score := saturation_penalty + float(pressure) * 100.0 + distance_score
		if score < best_score:
			best_score = score
			best_target = candidate
	return best_target


func _selection_can_heal_target(target: HumanoidCharacter) -> bool:
	if target == null or party_manager.selected_members.is_empty() or not target.can_receive_bandage():
		return false
	for member in party_manager.selected_members:
		if member.has_method("can_bandage_target") and bool(member.call("can_bandage_target", target)):
			return true
	return false


func _append_downed_target_actions(actions: Array, target: HumanoidCharacter) -> void:
	if target == null:
		return
	if _selection_can_finish_off_target(target):
		var finish_label := "Burn" if target.requires_fire_to_die() else "Finish Off"
		actions.append({"id": ACTION_FINISH_OFF, "label": finish_label})
	actions.append({"id": ACTION_HEAL, "label": "Heal"})
	if _selection_can_carry_target(target):
		actions.append({"id": ACTION_CARRY, "label": "Carry"})
	if _selection_can_drop_carry(target):
		actions.append({"id": ACTION_DROP_CARRY, "label": "Put Down"})


func _selection_can_carry_target(target: HumanoidCharacter) -> bool:
	if target == null or party_manager.selected_members.is_empty():
		return false
	for member in party_manager.selected_members:
		if member is HumanoidCharacter and member != target and not member.is_carrying_someone() and target.can_be_carried_by(member):
			return true
	return false


func _get_bed_sleeper(bed) -> HumanoidCharacter:
	if bed == null or not bed.has_method("get_sleeper"):
		return null
	var sleeper = bed.get_sleeper()
	return sleeper if sleeper is HumanoidCharacter and (sleeper.life_state == NpcRules.LifeState.ASLEEP or sleeper.is_downed_state()) else null


func _selection_can_place_carried_in_bed() -> bool:
	if party_manager.selected_members.is_empty():
		return false
	for member in party_manager.selected_members:
		if member.has_method("is_carrying_someone") and bool(member.call("is_carrying_someone")):
			return true
	return false


func _selection_can_finish_off_target(target: HumanoidCharacter) -> bool:
	if target == null or not target.is_downed_state() or party_manager.selected_members.is_empty():
		return false
	if target.requires_fire_to_die() and not target.can_be_destroyed_by_cinder():
		return false
	for member in party_manager.selected_members:
		if member != null and member.faction_name != target.faction_name:
			return true
	return false


func _selection_can_drop_carry(target: HumanoidCharacter) -> bool:
	if target == null or party_manager.selected_members.is_empty():
		return false
	for member in party_manager.selected_members:
		if member.has_method("get_carried_character") and member.call("get_carried_character") == target:
			return true
	return false


func _selection_can_put_down_from_carrier(target: HumanoidCharacter) -> bool:
	if target == null or party_manager.selected_members.is_empty():
		return false
	for member in party_manager.selected_members:
		if member == target and member.has_method("is_carrying_someone") and bool(member.call("is_carrying_someone")):
			return true
	return false




func _on_party_member_container_reached(member: HumanoidCharacter, container) -> void:
	if container == null or member == null:
		return
	if container.is_locked:
		_spawn_world_notice(container.global_position + Vector3(0.0, 1.6, 0.0), "Locked")
		return
	if not container.resolve_interaction(member):
		return
	inventory_controller.open_inventory_pair(member, container)


func _on_party_member_trade_target_reached(member: HumanoidCharacter, target) -> void:
	if member == null or target == null:
		return
	if target is HumanoidCharacter and target.is_player_party_member():
		inventory_controller.open_inventory_pair(member, target)
		return
	if target is CharacterBody3D and target.has_method("resolve_trade"):
		if not target.resolve_trade(member):
			return
		inventory_controller.open_inventory_pair(member, target)


func _on_party_member_conversation_target_reached(member: HumanoidCharacter, target) -> void:
	if member == null or target == null or conversation_controller == null:
		return
	if target is CharacterBody3D and target.has_method("resolve_talk"):
		if not target.resolve_talk(member):
			return
		conversation_controller.begin_conversation(member, target)


func _on_party_member_added(member: WorldActor) -> void:
	_register_party_member(member)
	_add_portrait_for_member(member)
	_ensure_work_progress_bar(member)
	_refresh_squad_tabs()
	_update_portraits()
	_update_command_bar()


func _spawn_world_notice(world_position: Vector3, message: String) -> void:
	var notice = WORLD_TEXT_NOTICE_SCENE.instantiate()
	root.add_child(notice)
	if notice.has_method("setup"):
		notice.setup(world_position, message)


func _show_center_notice(message: String) -> void:
	if floating_notice != null:
		floating_notice.show_message(message)


func _sync_inspected_party_member() -> void:
	if humanoid_details_controller == null:
		return
	if party_manager.selected_members.is_empty():
		return
	var inspected_target = humanoid_details_controller.current_target
	if inspected_target == null or (inspected_target.has_method("is_player_party_member") and inspected_target.is_player_party_member()):
		humanoid_details_controller.inspect_target(party_manager.selected_members[0])


func _has_property(target: Object, property_name: String) -> bool:
	if target == null:
		return false
	for property in target.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false
