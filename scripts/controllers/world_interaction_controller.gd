extends Node

class_name WorldInteractionController

const MOVE_COMMAND_INDICATOR_SCENE = preload("res://scenes/world/effects/move_command_indicator.tscn")
const WORLD_TEXT_NOTICE_SCENE = preload("res://scenes/world/effects/world_text_notice.tscn")
const PARTY_PORTRAIT_CARD_SCENE = preload("res://scenes/ui/party_portrait_card.tscn")

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
const STANCE_OPTION_MIXED := 3
const FREE_CAMERA_PITCH := -0.65
const FOLLOW_CAMERA_HEIGHT := 1.35
const ORBIT_MIN_PITCH := -1.2
const ORBIT_MAX_PITCH := -0.2
const GROUND_Y := 0.0

@export var free_camera_move_speed := 14.0
@export var camera_zoom_step := 1.0
@export var camera_min_distance := 4.0
@export var camera_max_distance := 36.0
@export var orbit_sensitivity := 0.01
@export var move_command_spacing := 1.4
@export var drag_select_threshold := 12.0

var party_members: Array[HumanoidCharacter] = []
var portrait_cards: Array[PartyPortraitCard] = []
var mining_progress_bars: Dictionary = {}
var camera_anchor := Vector3.ZERO
var camera_yaw := deg_to_rad(45.0)
var camera_pitch := FREE_CAMERA_PITCH
var camera_distance := 11.0
var is_orbiting := false
var is_left_mouse_down := false
var is_drag_selecting := false
var left_mouse_press_position := Vector2.ZERO
var left_mouse_press_double_click := false
var context_member: HumanoidCharacter
var context_humanoid: HumanoidCharacter
var context_resource
var context_container
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
var running_button: CheckButton
var sneaking_button: CheckButton
var stance_option: OptionButton
var inventory_controller: PartyInventoryController
var humanoid_details_controller
var conversation_controller
var ownership_controller
var building_visibility_controller
var floating_notice: FloatingNotice
var _initialized := false


func initialize(target_root: Node, target_hud: CanvasLayer = null) -> void:
	root = target_root
	hud_layer = target_hud
	if is_inside_tree():
		_do_initialize()


func _ready() -> void:
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
	if hud_layer == null:
		hud_layer = root.get_node_or_null("GameHUD")
	selection_rect = hud_layer.get_node("SelectionRect")
	context_menu = hud_layer.get_node_or_null("ContextMenu")
	progress_layer = hud_layer.get_node_or_null("ProgressLayer")
	running_button = hud_layer.get_node_or_null("HudLayout/BottomHud/RightHud/CommandBar/Margin/CommandColumn/CommandRow/LocomotionColumn/RunningButton")
	sneaking_button = hud_layer.get_node_or_null("HudLayout/BottomHud/RightHud/CommandBar/Margin/CommandColumn/CommandRow/LocomotionColumn/SneakingButton")
	stance_option = hud_layer.get_node_or_null("HudLayout/BottomHud/RightHud/CommandBar/Margin/CommandColumn/CommandRow/StanceOption")
	portrait_flow = hud_layer.get_node_or_null("HudLayout/BottomHud/RightHud/PortraitBar/PortraitScroll/PortraitFlow")
	floating_notice = hud_layer.get_node_or_null("FloatingNotice")
	inventory_controller = get_parent().get_node("PartyInventoryController")
	humanoid_details_controller = get_parent().get_node("HumanoidDetailsController")
	conversation_controller = get_parent().get_node("ConversationController")
	ownership_controller = get_parent().get_node_or_null("OwnershipController")
	building_visibility_controller = get_parent().get_node_or_null("BuildingVisibilityController")
	_initialized = true

	for child in party_root.get_children():
		if child is HumanoidCharacter and child.is_player_party_member():
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
			_ensure_progress_bar(member)

	if context_menu != null:
		context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	_setup_command_bar()

	if not party_members.is_empty():
		party_manager.select_only(party_members[0])
		if humanoid_details_controller != null:
			humanoid_details_controller.inspect_humanoid(party_members[0])

	camera_anchor = _get_anchor_position()
	_apply_camera_transform()
	_update_portraits()
	_update_command_bar()


func _register_party_member(member: HumanoidCharacter) -> void:
	if member == null or party_members.has(member):
		return
	party_members.append(member)
	member.container_reached.connect(_on_party_member_container_reached)
	member.trade_target_reached.connect(_on_party_member_trade_target_reached)
	member.conversation_target_reached.connect(_on_party_member_conversation_target_reached)
	member.state_changed.connect(_update_command_bar)


func _add_portrait_for_member(member: HumanoidCharacter) -> void:
	if portrait_flow == null or member == null:
		return
	var card := PARTY_PORTRAIT_CARD_SCENE.instantiate() as PartyPortraitCard
	portrait_flow.add_child(card)
	card.setup(member)
	card.portrait_pressed.connect(_on_portrait_pressed)
	portrait_cards.append(card)


func _ensure_progress_bar(member: HumanoidCharacter) -> void:
	if progress_layer == null or member == null or mining_progress_bars.has(member):
		return
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 0.0
	bar.custom_minimum_size = Vector2(90.0, 12.0)
	bar.show_percentage = false
	bar.visible = false
	progress_layer.add_child(bar)
	mining_progress_bars[member] = bar


func _process(delta: float) -> void:
	if not _initialized:
		return
	var move_input := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)

	if party_manager.followed_member != null and move_input.length() > 0.0:
		_clear_follow_target()

	if party_manager.followed_member == null and move_input.length() > 0.0:
		var move_basis := Basis(Vector3.UP, camera_yaw)
		var move_direction := move_basis * Vector3(move_input.x, 0.0, move_input.y)
		if move_direction.length() > 0.0:
			camera_anchor += move_direction.normalized() * free_camera_move_speed * delta

	if party_manager.followed_member != null:
		camera_anchor = _get_anchor_position()

	if move_input.length() > 0.0 or party_manager.followed_member != null:
		_apply_camera_transform()

	_update_progress_bars()


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
			_handle_right_click(event.position)
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
	var humanoid = _pick_humanoid(screen_position)
	if humanoid == null:
		party_manager.clear_selection()
		if humanoid_details_controller != null:
			humanoid_details_controller.clear_if_not_party_target()
		return
	if humanoid_details_controller != null:
		humanoid_details_controller.inspect_humanoid(humanoid)
	if not humanoid.is_player_party_member():
		return
	var member: HumanoidCharacter = humanoid
	if Input.is_key_pressed(KEY_ALT):
		party_manager.add_selection(member)
	else:
		party_manager.select_only(member)
	if should_follow:
		_set_follow_target(member)


func _handle_right_click(screen_position: Vector2) -> void:
	if context_menu != null:
		context_menu.hide()
	context_member = null
	context_humanoid = null
	context_resource = null
	context_container = null
	var result := _raycast_from_screen(screen_position)
	if result.is_empty():
		issue_move_command(screen_position)
		return
	var collider: Object = result["collider"]
	if collider is Node and collider.is_in_group("mining_resource") and not party_manager.selected_members.is_empty():
		_show_context_menu(screen_position, ACTION_MINE, "Mine")
		context_resource = collider
		return
	if collider is HumanoidCharacter and collider.is_player_party_member():
		var party_actions := [{"id": ACTION_INVENTORY, "label": "Inventory"}]
		if collider.life_state == NpcRules.LifeState.UNCONSCIOUS:
			_append_downed_target_actions(party_actions, collider)
		elif _selection_can_carry_target(collider):
			party_actions.append({"id": ACTION_CARRY, "label": "Carry"})
		party_actions.append({"id": ACTION_HEAL, "label": "Heal"})
		if _selection_can_put_down_from_carrier(collider):
			party_actions.append({"id": ACTION_DROP_CARRY, "label": "Put Down"})
		_show_context_menu_actions(screen_position, party_actions)
		context_member = collider
		context_humanoid = collider
		return
	if collider is HumanoidCharacter and not party_manager.selected_members.is_empty():
		context_humanoid = collider
		var humanoid_actions: Array = []
		if collider.life_state == NpcRules.LifeState.UNCONSCIOUS:
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
		return
	if collider is Node and collider.is_in_group("world_container") and not party_manager.selected_members.is_empty():
		context_container = collider
		if context_container.is_locked:
			_show_context_menu(screen_position, ACTION_UNLOCK_CONTAINER, "Unlock")
		else:
			_show_context_menu(screen_position, ACTION_OPEN_CONTAINER, "Open")
		return
	issue_move_command(screen_position)


func _show_context_menu(screen_position: Vector2, action_id: int, label: String) -> void:
	_show_context_menu_actions(screen_position, [{"id": action_id, "label": label}])


func _show_context_menu_actions(screen_position: Vector2, actions: Array) -> void:
	if context_menu == null:
		return
	context_menu.clear()
	for action in actions:
		context_menu.add_item(action["label"], action["id"])
	context_menu.position = Vector2i(screen_position)
	context_menu.popup()


func _apply_drag_selection() -> void:
	var rect := _get_selection_rect(left_mouse_press_position, get_viewport().get_mouse_position())
	var drag_selected: Array[HumanoidCharacter] = []
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
			humanoid_details_controller.inspect_humanoid(merged_selection[0])
		return
	party_manager.set_selection(drag_selected)
	if humanoid_details_controller != null and not drag_selected.is_empty():
		humanoid_details_controller.inspect_humanoid(drag_selected[0])


func _pick_party_member(screen_position: Vector2) -> HumanoidCharacter:
	var result := _raycast_from_screen(screen_position)
	if result.is_empty():
		return null
	var collider: Object = result["collider"]
	if collider is HumanoidCharacter and collider.is_player_party_member():
		return collider
	return null


func _pick_humanoid(screen_position: Vector2):
	var result := _raycast_from_screen(screen_position)
	if result.is_empty():
		return null
	var collider: Object = result["collider"]
	if collider is CharacterBody3D and collider.has_method("set_inspected"):
		return collider
	return null


func issue_move_command(screen_position: Vector2) -> void:
	if party_manager.selected_members.is_empty():
		return
	var target_variant: Variant = _pick_ground_position(screen_position)
	if target_variant == null:
		return
	var target: Vector3 = target_variant
	_spawn_move_command_indicator(target)
	var center := Vector3.ZERO
	for member in party_manager.selected_members:
		center += member.global_position
	center /= party_manager.selected_members.size()
	for member in party_manager.selected_members:
		var offset: Vector3 = member.global_position - center
		offset.y = 0.0
		if offset.length() > move_command_spacing:
			offset = offset.normalized() * move_command_spacing
		member.stop_mining_assignment()
		member.stop_container_interaction()
		member.set_move_target(target + offset)


func _pick_ground_position(screen_position: Vector2) -> Variant:
	var result := _raycast_from_screen(screen_position)
	if not result.is_empty():
		var collider: Object = result["collider"]
		if collider != null and collider.has_method("project_click_to_active_level") and collider.has_method("should_project_click_shape") and building_visibility_controller != null and building_visibility_controller.get_active_building() == collider:
			var shape_index := int(result.get("shape", -1))
			if collider.should_project_click_shape(shape_index):
				var ray_origin := camera.project_ray_origin(screen_position)
				var ray_direction := camera.project_ray_normal(screen_position)
				var building_target: Variant = collider.project_click_to_active_level(ray_origin, ray_direction)
				if building_target != null:
					return building_target
		if not (collider is HumanoidCharacter and collider.is_player_party_member()):
			return result["position"]
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	if absf(ray_direction.y) < 0.0001:
		return null
	var distance := (GROUND_Y - ray_origin.y) / ray_direction.y
	if distance <= 0.0:
		return null
	return ray_origin + ray_direction * distance


func _raycast_from_screen(screen_position: Vector2) -> Dictionary:
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_end := ray_origin + camera.project_ray_normal(screen_position) * 500.0
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	return camera.get_world_3d().direct_space_state.intersect_ray(query)


func _spawn_move_command_indicator(target: Vector3) -> void:
	var indicator := MOVE_COMMAND_INDICATOR_SCENE.instantiate()
	if indicator is Node3D:
		indicator.position = target
		root.add_child(indicator)
		if indicator.has_method("setup_at"):
			indicator.setup_at(target)


func _set_follow_target(member: HumanoidCharacter) -> void:
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
		var member: HumanoidCharacter = party_members[index]
		var card: PartyPortraitCard = portrait_cards[index]
		var is_selected: bool = member.is_selected
		var is_followed: bool = member.is_focused
		card.apply_state(is_selected, is_followed)


func _setup_command_bar() -> void:
	if running_button != null:
		running_button.toggled.connect(_on_running_button_toggled)
	if sneaking_button != null:
		sneaking_button.toggled.connect(_on_sneaking_button_toggled)
	if stance_option != null:
		stance_option.clear()
		stance_option.add_item("Aggressive", NpcRules.CombatStance.AGGRESSIVE)
		stance_option.add_item("Defensive", NpcRules.CombatStance.DEFENSIVE)
		stance_option.add_item("Passive", NpcRules.CombatStance.PASSIVE)
		stance_option.add_item("Mixed", STANCE_OPTION_MIXED)
		stance_option.item_selected.connect(_on_stance_option_selected)


func _update_command_bar() -> void:
	if running_button == null or sneaking_button == null or stance_option == null:
		return
	var has_selection := not party_manager.selected_members.is_empty()
	running_button.disabled = not has_selection
	sneaking_button.disabled = not has_selection
	stance_option.disabled = not has_selection
	if not has_selection:
		running_button.set_pressed_no_signal(false)
		sneaking_button.set_pressed_no_signal(false)
		stance_option.select(NpcRules.CombatStance.DEFENSIVE)
		return
	var any_running := false
	var any_sneaking := false
	var first_stance: int = party_manager.selected_members[0].combat_stance
	var mixed_stance := false
	for member in party_manager.selected_members:
		if member.is_running_enabled() or member.running:
			any_running = true
		if member.sneaking:
			any_sneaking = true
		if member.combat_stance != first_stance:
			mixed_stance = true
	running_button.set_pressed_no_signal(any_running)
	sneaking_button.set_pressed_no_signal(any_sneaking)
	if mixed_stance:
		stance_option.select(STANCE_OPTION_MIXED)
	else:
		stance_option.select(first_stance)


func _update_progress_bars() -> void:
	if progress_layer == null:
		return
	for member in party_members:
		var bar: ProgressBar = mining_progress_bars.get(member)
		if bar == null:
			continue
		if not member.is_actively_mining():
			bar.visible = false
			continue
		var world_position: Vector3 = member.global_position + Vector3(0.0, 2.35, 0.0)
		if camera.is_position_behind(world_position):
			bar.visible = false
			continue
		var screen_position := camera.unproject_position(world_position)
		bar.visible = true
		bar.position = screen_position - Vector2(bar.size.x * 0.5, bar.size.y * 0.5)
		bar.value = member.get_mining_progress_ratio() * 100.0


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
		return party_manager.followed_member.global_position + Vector3(0.0, FOLLOW_CAMERA_HEIGHT, 0.0)
	return camera_anchor


func _apply_camera_transform() -> void:
	camera_rig.global_position = _get_anchor_position()
	camera_rig.rotation = Vector3(0.0, camera_yaw, 0.0)
	camera_pivot.rotation = Vector3(camera_pitch, 0.0, 0.0)
	camera.position = Vector3(0.0, 0.0, camera_distance)


func _on_portrait_pressed(member: HumanoidCharacter, double_click: bool, add_select: bool) -> void:
	if add_select:
		party_manager.add_selection(member)
	else:
		party_manager.select_only(member)
	if humanoid_details_controller != null:
		humanoid_details_controller.inspect_humanoid(member)
	if double_click:
		_set_follow_target(member)


func _on_running_button_toggled(button_pressed: bool) -> void:
	var any_failed := false
	for member in party_manager.selected_members:
		if not member.set_running_enabled(button_pressed):
			any_failed = true
	if any_failed and button_pressed:
		_show_center_notice("Too Exhausted to run")
	_update_command_bar()


func _on_sneaking_button_toggled(button_pressed: bool) -> void:
	for member in party_manager.selected_members:
		member.set_sneaking_enabled(button_pressed)
	_update_command_bar()


func _on_stance_option_selected(index: int) -> void:
	if index == STANCE_OPTION_MIXED:
		return
	for member in party_manager.selected_members:
		member.set_combat_stance(index)
	_update_command_bar()


func _on_context_menu_id_pressed(action_id: int) -> void:
	match action_id:
		ACTION_INVENTORY:
			inventory_controller.open_inventory_for_member(context_member)
		ACTION_MINE:
			if context_resource != null:
				for member in party_manager.selected_members:
					if ownership_controller == null or ownership_controller.request_interaction(member, context_resource, "Mining"):
						member.assign_mining_resource(context_resource)
		ACTION_OPEN_CONTAINER:
			if context_container != null:
				for member in party_manager.selected_members:
					if ownership_controller == null or ownership_controller.request_interaction(member, context_container, "Opening"):
						member.assign_open_container(context_container)
		ACTION_UNLOCK_CONTAINER:
			if context_container != null:
				_spawn_world_notice(context_container.global_position + Vector3(0.0, 1.6, 0.0), "Lockpicking not implemented")
		ACTION_ATTACK:
			if context_humanoid != null:
				for member in party_manager.selected_members:
					member.assign_attack_target(context_humanoid)
		ACTION_TRADE:
			if context_humanoid != null:
				for member in party_manager.selected_members:
					member.assign_trade_target(context_humanoid)
		ACTION_TALK:
			if context_humanoid != null:
				for member in party_manager.selected_members:
					member.assign_conversation_target(context_humanoid)
		ACTION_HEAL:
			if context_humanoid != null:
				for member in party_manager.selected_members:
					member.assign_heal_target(context_humanoid)
		ACTION_FINISH_OFF:
			if context_humanoid != null:
				for member in party_manager.selected_members:
					member.assign_finish_off_target(context_humanoid)
		ACTION_CARRY:
			if context_humanoid != null:
				for member in party_manager.selected_members:
					member.assign_carry_target(context_humanoid)
		ACTION_DROP_CARRY:
			for member in party_manager.selected_members:
				member.drop_carried_character()


func _selection_can_heal_target(target: HumanoidCharacter) -> bool:
	if target == null or party_manager.selected_members.is_empty() or not target.can_receive_bandage():
		return false
	for member in party_manager.selected_members:
		if member.can_bandage_target(target):
			return true
	return false


func _append_downed_target_actions(actions: Array, target: HumanoidCharacter) -> void:
	if target == null:
		return
	if _selection_can_finish_off_target(target):
		actions.append({"id": ACTION_FINISH_OFF, "label": "Finish Off"})
	actions.append({"id": ACTION_HEAL, "label": "Heal"})
	if _selection_can_carry_target(target):
		actions.append({"id": ACTION_CARRY, "label": "Carry"})
	if _selection_can_drop_carry(target):
		actions.append({"id": ACTION_DROP_CARRY, "label": "Put Down"})


func _selection_can_carry_target(target: HumanoidCharacter) -> bool:
	if target == null or party_manager.selected_members.is_empty():
		return false
	for member in party_manager.selected_members:
		if not member.is_carrying_someone() and target.can_be_carried_by(member):
			return true
	return false


func _selection_can_finish_off_target(target: HumanoidCharacter) -> bool:
	if target == null or target.life_state != NpcRules.LifeState.UNCONSCIOUS or party_manager.selected_members.is_empty():
		return false
	for member in party_manager.selected_members:
		if member != null and member.faction_name != target.faction_name:
			return true
	return false


func _selection_can_drop_carry(target: HumanoidCharacter) -> bool:
	if target == null or party_manager.selected_members.is_empty():
		return false
	for member in party_manager.selected_members:
		if member.get_carried_character() == target:
			return true
	return false


func _selection_can_put_down_from_carrier(target: HumanoidCharacter) -> bool:
	if target == null or party_manager.selected_members.is_empty():
		return false
	for member in party_manager.selected_members:
		if member == target and member.is_carrying_someone():
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
	inventory_controller.open_inventory_for_owner(container)
	inventory_controller.open_inventory_for_owner(member)


func _on_party_member_trade_target_reached(member: HumanoidCharacter, target) -> void:
	if member == null or target == null:
		return
	if target is CharacterBody3D and target.has_method("resolve_trade"):
		if not target.resolve_trade(member):
			return
		inventory_controller.open_inventory_for_owner(member)
		inventory_controller.open_inventory_for_owner(target)


func _on_party_member_conversation_target_reached(member: HumanoidCharacter, target) -> void:
	if member == null or target == null or conversation_controller == null:
		return
	if target is CharacterBody3D and target.has_method("resolve_talk"):
		if not target.resolve_talk(member):
			return
		conversation_controller.begin_conversation(member, target)


func _on_party_member_added(member: HumanoidCharacter) -> void:
	_register_party_member(member)
	_add_portrait_for_member(member)
	_ensure_progress_bar(member)
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
	if humanoid_details_controller.current_target == null or humanoid_details_controller.current_target.is_player_party_member():
		humanoid_details_controller.inspect_humanoid(party_manager.selected_members[0])
