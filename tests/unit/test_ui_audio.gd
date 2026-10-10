extends GutTest
## Production settings and real controls, with synthetic streams at the audio boundary.

const CONTROLLER_PATH := "res://features/ui/projection/ui_audio_controller.gd"
const SETTINGS_PATH := "res://features/ui/resources/ui_audio_settings.tres"
const BUTTON_PATH := "res://assets/vendor/gfxsounds-studios/fantasy-game-bundle/audio/UI Feedback/Buttons/UIClick_Button click_GfxSounds_FantasyGameBundle.wav"
const CLOSE_PATH := "res://assets/vendor/gfxsounds-studios/fantasy-game-bundle/audio/UI Feedback/Buttons/UIClick_Switch off 2_GfxSounds_FantasyGameBundle.wav"

var viewport: SubViewport
var root: Control
var controller: Node


func before_each() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(640, 480)
	viewport.handle_input_locally = true
	viewport.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child_autofree(viewport)
	root = Control.new()
	root.size = Vector2(640, 480)
	viewport.add_child(root)


func after_each() -> void:
	get_tree().paused = false


func test_ui_audio_controller_is_a_runtime_service() -> void:
	var audio: Node = add_child_autofree(load(CONTROLLER_PATH).new())
	assert_eq(audio.SERVICE_ID, &"ui_audio")


func test_approved_recordings_use_fixed_pitch_and_native_imports_when_available() -> void:
	controller = load(CONTROLLER_PATH).new()
	root.add_child(controller)
	controller.initialize(BootstrapContext.new(root))
	watch_signals(controller)
	var button := _button()
	await get_tree().process_frame
	var verified := 0
	for spec: Dictionary in [
		{"cue": controller.settings.click, "path": BUTTON_PATH, "action": &"click"},
		{"cue": controller.settings.menu_close, "path": CLOSE_PATH, "action": &"close"},
	]:
		assert_eq(spec.cue.paths, PackedStringArray([spec.path]))
		assert_eq(spec.cue.pitch_min, 1.0)
		assert_eq(spec.cue.pitch_max, 1.0)
		if not ResourceLoader.exists(spec.path, "AudioStream"):
			assert_null(spec.cue.get_stream(spec.path), "Licensed recordings are optional on fresh checkouts")
			continue
		button.set_meta(&"ui_audio_action", spec.action)
		_click(button.get_global_rect().get_center())
		verified += 1
		assert_signal_emit_count(controller, "cue_played", verified)
		var player: AudioStreamPlayer = controller._voices.back()
		assert_true(player.playing, "The imported recording starts through native button input")
		assert_same(player.stream, load(spec.path))
		assert_gt(player.stream.get_length(), 0.0)
		assert_eq(player.pitch_scale, 1.0)
	gut.p("Locally imported approved UI recordings exercised: %d / 2" % verified)


func test_existing_button_press_starts_one_screen_space_voice() -> void:
	var button := _button()
	if not _start_audio():
		return
	await get_tree().process_frame
	_click(button.get_global_rect().get_center())
	assert_signal_emit_count(controller, "cue_played", 1)
	var voices := _voices()
	assert_eq(voices.size(), 1, "A press allocates one non-positional UI voice")
	if not voices.is_empty():
		assert_true(voices[0].playing, "The real player starts the synthetic stream")


func test_character_portrait_selection_is_silent_without_disabling_selection() -> void:
	if not _start_audio():
		return
	var cards: Array[Button] = []
	for index in 2:
		var card: Button = load("res://features/ui/projection/party_portrait_card.tscn").instantiate()
		card.position = Vector2(24 + index * 150, 120)
		# No character rendering is needed to exercise the real selection input.
		card.get_node("Margin/VBox/PortraitImage").hide()
		card.member = autofree(WorldActor.new())
		root.add_child(card)
		watch_signals(card)
		cards.append(card)
	await get_tree().process_frame
	await get_tree().process_frame
	for card in cards:
		_click(card.get_global_rect().get_center())
		assert_signal_emit_count(card, "portrait_pressed", 1, "Selection still reaches the party HUD")
		assert_same(get_signal_parameters(card, "portrait_pressed")[0], card.member)
	assert_signal_not_emitted(controller, "cue_played", "Switching between portraits must be silent")
	var ordinary := _button()
	await get_tree().process_frame
	_click(ordinary.get_global_rect().get_center())
	assert_signal_emit_count(controller, "cue_played", 1, "Only the portrait subtree is muted")


func test_only_user_toggle_activations_sound_once_in_the_new_state() -> void:
	var toggle := _button()
	toggle.toggle_mode = true
	if not _start_audio():
		return
	await get_tree().process_frame
	toggle.button_pressed = true
	toggle.set_pressed_no_signal(false)
	assert_signal_not_emitted(controller, "cue_played", "Startup and programmatic state changes are silent")
	_click(toggle.get_global_rect().get_center())
	assert_signal_emit_count(controller, "cue_played", 1)
	assert_eq(get_signal_parameters(controller, "cue_played")[0], &"ui.click")
	_click(toggle.get_global_rect().get_center())
	assert_signal_emit_count(controller, "cue_played", 2)
	assert_eq(get_signal_parameters(controller, "cue_played", 1)[0], &"ui.click", "An ordinary toggle turning off is not a menu close")


func test_accepted_close_action_still_sounds_after_its_handler_hides_it() -> void:
	var button := _button()
	button.set_meta(&"ui_audio_action", &"close")
	button.pressed.connect(button.hide)
	if not _start_audio():
		return
	await get_tree().process_frame
	_click(button.get_global_rect().get_center())
	assert_false(button.visible)
	assert_signal_emit_count(controller, "cue_played", 1)
	assert_eq(get_signal_parameters(controller, "cue_played"), [&"ui.close", CLOSE_PATH])
	assert_eq(_voices()[0].pitch_scale, 1.0)


func test_saved_inventory_close_button_uses_close_only() -> void:
	if not _start_audio():
		return
	var window: Control = load("res://features/ui/projection/inventory_window.tscn").instantiate()
	root.add_child(window)
	window.close_requested.connect(func(_owner): window.queue_free())
	await get_tree().process_frame
	await get_tree().process_frame
	_click(window.close_button.get_global_rect().get_center())
	assert_true(window.is_queued_for_deletion(), "Real close signal still closes the inventory")
	assert_signal_emit_count(controller, "cue_played", 1)
	assert_eq(get_signal_parameters(controller, "cue_played"), [&"ui.close", CLOSE_PATH])


func test_dynamic_controls_are_bound_once_and_removed_controls_are_silent() -> void:
	if not _start_audio():
		return
	var button := _button()
	await get_tree().process_frame
	_click(button.get_global_rect().get_center())
	assert_signal_emit_count(controller, "cue_played", 1)
	root.remove_child(button)
	await get_tree().process_frame
	button.pressed.emit()
	assert_signal_emit_count(controller, "cue_played", 1)
	root.add_child(button)
	controller.initialize(BootstrapContext.new(root))
	controller.initialize(BootstrapContext.new(root))
	await get_tree().process_frame
	_click(button.get_global_rect().get_center())
	assert_signal_emit_count(controller, "cue_played", 2, "Re-add and reinitialize never duplicate bindings")


func test_hidden_disabled_hover_cancel_and_opted_out_controls_are_silent() -> void:
	var button := _button()
	if not _start_audio():
		return
	await get_tree().process_frame
	var at := button.get_global_rect().get_center()
	_move(at)
	_mouse(at, true)
	_move(Vector2(400, 300))
	_mouse(Vector2(400, 300), false)
	button.disabled = true
	_click(at)
	button.pressed.emit()
	button.disabled = false
	button.hide()
	button.pressed.emit()
	button.show()
	root.set_meta("ui_audio_disabled", true)
	_click(at)
	assert_signal_not_emitted(controller, "cue_played")


func test_reinitialize_changes_scope_and_controller_reentry_restores_bindings() -> void:
	var old_button := _button()
	if not _start_audio():
		return
	var other := Control.new()
	viewport.add_child(other)
	var next_button := Button.new()
	next_button.position = Vector2(220, 24)
	next_button.size = Vector2(120, 40)
	other.add_child(next_button)
	controller.initialize(BootstrapContext.new(other))
	await get_tree().process_frame
	old_button.pressed.emit()
	_click(next_button.get_global_rect().get_center())
	assert_signal_emit_count(controller, "cue_played", 1)
	root.remove_child(controller)
	next_button.pressed.emit()
	assert_signal_emit_count(controller, "cue_played", 1)
	root.add_child(controller)
	await get_tree().process_frame
	_click(next_button.get_global_rect().get_center())
	assert_signal_emit_count(controller, "cue_played", 2)
	next_button.free()
	await get_tree().process_frame
	controller.initialize(BootstrapContext.new(other))
	await get_tree().process_frame
	assert_eq(_voices().size(), 0, "Reinitialization stops and releases all voices")


func test_voice_budget_fixed_click_and_runtime_tuning_reach_real_players() -> void:
	var button := _button()
	if not _start_audio():
		return
	await get_tree().process_frame
	assert_eq(controller.settings.volume_db, -18.0)
	assert_eq(controller.settings.polyphony, 3)
	for index in 9:
		_click(button.get_global_rect().get_center())
		var args: Array = get_signal_parameters(controller, "cue_played", index)
		assert_eq(args[1], BUTTON_PATH, "Every button press uses the exact audition-approved click")
	assert_eq(_voices().size(), 3, "Bursts reuse the bounded voice pool")
	for voice in _voices():
		assert_true(voice.playing)
		assert_eq(voice.volume_db, -18.0)
		assert_eq(voice.pitch_scale, 1.0, "UI clicks must not vary in pitch")
	controller.settings.polyphony = 1
	controller.settings.volume_db = -30.0
	controller.settings.click.volume_db = -2.0
	_click(button.get_global_rect().get_center())
	await get_tree().process_frame
	assert_eq(_voices().size(), 1, "Lowering the budget releases excess voices on the next press")
	assert_eq(_voices()[0].volume_db, -32.0)
	controller.settings.enabled = false
	_click(button.get_global_rect().get_center())
	assert_signal_emit_count(controller, "cue_played", 10)


func test_pause_menu_and_keyboard_accept_still_start_one_voice() -> void:
	var button := _button()
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	if not _start_audio():
		return
	await get_tree().process_frame
	get_tree().paused = true
	button.grab_focus()
	for down in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_SPACE
		key.pressed = down
		viewport.push_input(key, true)
	assert_signal_emit_count(controller, "cue_played", 1)
	assert_true(_voices()[0].playing)
	assert_true(_voices()[0].can_process())


func test_module_installs_exactly_one_runtime_ui_audio_service() -> void:
	var module = load("res://features/ui/ui_module.gd")
	var matches := 0
	for spec: Dictionary in module.PROJECTION:
		if spec.service == &"ui_audio":
			matches += 1
			assert_eq(spec.script, load(CONTROLLER_PATH))
	assert_eq(matches, 1)


func test_tab_clicks_sound_but_programmatic_changes_and_disabled_tabs_do_not() -> void:
	var tabs := TabBar.new()
	tabs.position = Vector2(20, 20)
	tabs.size = Vector2(360, 40)
	tabs.add_tab("First")
	tabs.add_tab("Second")
	tabs.add_tab("Locked")
	tabs.set_tab_disabled(2, true)
	root.add_child(tabs)
	if not _start_audio():
		return
	await get_tree().process_frame
	tabs.current_tab = 1
	assert_signal_not_emitted(controller, "cue_played")
	_click(tabs.global_position + tabs.get_tab_rect(0).get_center())
	assert_signal_emit_count(controller, "cue_played", 1)
	_click(tabs.global_position + tabs.get_tab_rect(2).get_center())
	assert_signal_emit_count(controller, "cue_played", 1)


func test_option_choice_uses_one_popup_cue_and_programmatic_selection_is_silent() -> void:
	viewport.gui_embed_subwindows = true
	var option := OptionButton.new()
	option.position = Vector2(20, 20)
	option.size = Vector2(180, 40)
	option.add_item("Low")
	option.add_item("High")
	root.add_child(option)
	if not _start_audio():
		return
	await get_tree().process_frame
	option.select(1)
	option.select(0)
	assert_signal_not_emitted(controller, "cue_played")
	_click(option.get_global_rect().get_center())
	assert_signal_emit_count(controller, "cue_played", 1, "Opening and choosing are distinct actions")
	var popup := option.get_popup()
	assert_true(popup.visible)
	await get_tree().process_frame
	popup.set_focused_item(1)
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	viewport.push_input(key, true)
	assert_eq(option.selected, 1, "Real popup input reaches OptionButton selection")
	assert_false(popup.visible, "Selection hides the popup before its selection signal")
	assert_signal_emit_count(controller, "cue_played", 2, "No duplicate OptionButton and PopupMenu cue")


func test_press_mode_close_action_is_accepted_before_its_handler_disables_it() -> void:
	var button := _button()
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	button.set_meta(&"ui_audio_action", &"close")
	button.pressed.connect(func(): button.disabled = true)
	if not _start_audio():
		return
	await get_tree().process_frame
	_click(button.get_global_rect().get_center())
	assert_true(button.disabled)
	assert_signal_emit_count(controller, "cue_played", 1)
	assert_eq(get_signal_parameters(controller, "cue_played"), [&"ui.close", CLOSE_PATH])


func test_accepted_button_can_remove_itself_without_losing_or_repeating_audio() -> void:
	var button := _button()
	button.pressed.connect(func(): root.remove_child(button))
	if not _start_audio():
		return
	await get_tree().process_frame
	_click(button.get_global_rect().get_center())
	assert_signal_emit_count(controller, "cue_played", 1)
	await get_tree().process_frame
	assert_false(controller._bindings.has(button.get_instance_id()), "Removed controls release their weak binding records")
	button.free()


func test_missing_files_empty_cues_and_missing_settings_are_silent() -> void:
	var button := _button()
	if not _start_audio():
		return
	await get_tree().process_frame
	controller.settings.click.paths = PackedStringArray(["res://missing_ui_test_recording.wav"])
	_click(button.get_global_rect().get_center())
	controller.settings.click = null
	_click(button.get_global_rect().get_center())
	controller.settings = null
	_click(button.get_global_rect().get_center())
	assert_signal_not_emitted(controller, "cue_played")
	assert_eq(_voices().size(), 0)


func test_popup_cancellation_and_disabled_choices_are_silent() -> void:
	viewport.gui_embed_subwindows = true
	if not _start_audio():
		return
	var popup := PopupMenu.new()
	root.add_child(popup)
	popup.add_item("Apply")
	popup.add_item("Unavailable")
	popup.set_item_disabled(1, true)
	popup.popup(Rect2i(20, 70, 180, 80))
	await get_tree().process_frame
	popup.index_pressed.emit(1)
	popup.hide()
	await get_tree().process_frame
	popup.index_pressed.emit(0)
	assert_signal_not_emitted(controller, "cue_played")
	popup.popup(Rect2i(20, 70, 180, 80))
	await get_tree().process_frame
	popup.set_focused_item(0)
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	viewport.push_input(key, true)
	assert_signal_emit_count(controller, "cue_played", 1, "A dynamically added ordinary popup uses the same path")


func _button() -> Button:
	var button := Button.new()
	button.text = "Apply"
	button.position = Vector2(24, 24)
	button.size = Vector2(120, 40)
	root.add_child(button)
	return button


func _start_audio() -> bool:
	controller = load(CONTROLLER_PATH).new()
	root.add_child(controller)
	assert_true(controller.has_method("initialize"), "Injected runtime binding must exist")
	assert_true(ResourceLoader.exists(SETTINGS_PATH), "Saved UI tuning must exist")
	if not controller.has_method("initialize") or not ResourceLoader.exists(SETTINGS_PATH):
		return false
	controller.settings = load(SETTINGS_PATH).duplicate(true)
	# Keep the authored paths/cues; replace only file IO with one-second PCM.
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = 8000
	var samples := PackedByteArray()
	samples.resize(8000)
	samples.fill(128)
	stream.data = samples
	for property: Dictionary in controller.settings.get_property_list():
		if not (property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var cue = controller.settings.get(property.name)
		if cue is GameSoundCue:
			for path: String in cue.paths:
				cue._stream_cache[path] = stream
	controller.initialize(BootstrapContext.new(root))
	watch_signals(controller)
	return true


func _voices() -> Array[Node]:
	return controller.find_children("*", "AudioStreamPlayer", false, false)


func _click(at: Vector2) -> void:
	_move(at)
	_mouse(at, true)
	_mouse(at, false)


func _move(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	viewport.push_input(motion, true)


func _mouse(at: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	viewport.push_input(event, true)
