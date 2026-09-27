extends GutTest

var _controller: HumanoidDetailsController
var _button: Button

func before_each() -> void:
	_controller = HumanoidDetailsController.new()
	add_child_autofree(_controller)
	_controller.set_process(false)
	_button = Button.new()
	_controller.add_child(_button)
	_controller.action_buttons.append(_button)
	await get_tree().process_frame

func test_unchanged_actions_do_not_rebuild_button_theme() -> void:
	for key in ["attack", HumanoidDetailsController.DELETE_FIELD_ACTION]:
		var actions := [{"key": key, "label": "Action"}]
		_controller._set_actions(actions)
		await get_tree().process_frame
		watch_signals(_button)
		_controller._set_actions(actions)
		await get_tree().process_frame
		assert_signal_not_emitted(_button, "theme_changed", "An unchanged action must not invalidate its theme")
		clear_signal_watcher()

func test_switching_and_hiding_actions_clears_destructive_color() -> void:
	_controller._set_actions([{"key": HumanoidDetailsController.DELETE_FIELD_ACTION, "label": "Delete"}])
	assert_true(_button.has_theme_color_override("font_color"))
	_controller._set_actions([{"key": "attack", "label": "Attack", "disabled": true}])
	assert_false(_button.has_theme_color_override("font_color"))
	assert_eq(_button.text, "Attack")
	assert_true(_button.disabled)
	assert_eq(_button.get_meta("inspector_action_key"), "attack")
	_controller._set_actions([{"key": HumanoidDetailsController.DELETE_FIELD_ACTION, "label": "Delete"}])
	_controller._set_actions([])
	assert_false(_button.has_theme_color_override("font_color"))
	assert_false(_button.visible)
	assert_eq(_button.get_meta("inspector_action_key"), "")
