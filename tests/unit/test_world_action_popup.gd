extends GutTest
const POPUP = preload("res://features/ui/projection/world_action_popup.gd")

func test_warning_color_does_not_tint_heal_or_carry() -> void:
	var menu = POPUP.new()
	add_child_autofree(menu)
	menu.set_actions([{"id": 1, "label": "Loot", "color": OwnershipController.STEAL_ACTION_COLOR}, {"id": 2, "label": "Heal"}, {"id": 3, "label": "Carry"}])
	assert_eq(menu.get_action_button(0).get_theme_color("font_color"), OwnershipController.STEAL_ACTION_COLOR)
	assert_ne(menu.get_action_button(1).get_theme_color("font_color"), OwnershipController.STEAL_ACTION_COLOR)
	assert_ne(menu.get_action_button(2).get_theme_color("font_color"), OwnershipController.STEAL_ACTION_COLOR)
	menu.set_actions([{"id": 4, "label": "Open"}])
	assert_ne(menu.get_action_button(0).get_theme_color("font_color"), OwnershipController.STEAL_ACTION_COLOR, "Warnings cannot bleed into the next menu")

func test_button_dispatches_original_id_once() -> void:
	var menu = POPUP.new()
	add_child_autofree(menu)
	var chosen: Array[int] = []
	menu.id_pressed.connect(func(id: int): chosen.append(id))
	menu.set_actions([{"id": 71, "label": "Loot"}, {"id": 83, "label": "Heal"}])
	menu.get_action_button(1).pressed.emit()
	assert_eq(chosen, [83])

func test_authored_hud_uses_shared_action_popup() -> void:
	var hud: Node = load("res://features/ui/projection/game_hud.tscn").instantiate()
	autofree(hud)
	assert_true(hud.get_node("ContextMenu").get_script() == POPUP)
