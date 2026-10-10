extends "res://tests/validation/test_case.gd"

## Authored World1 smoke, deliberately separate from generic unit fixtures.
## Optional PARTY_CAPTURE_DIR writes a real rendered fresh-start HUD capture.
const WORLD_PATH := "res://scenes/worlds/world1/world1.tscn"
const CLEANUP := preload("res://tests/validation/helpers/combat_fixture.gd")
var failures: Array[String] = []
var world: WorldRoot
var ui: WorldInteractionController
var party: PartyManager
var context: BootstrapContext
var save_path := "user://start-scenario-runtime.tres"

func _initialize() -> void:
	# Capture the production HUD and its independent portrait viewports without
	# rasterizing the whole terrain on a software-only private display.
	if not OS.get_environment("PARTY_CAPTURE_DIR").is_empty():
		root.disable_3d = true
	if not await _boot():
		await _finish()
		return
	_check(world.get_start_scenario().scenario_id == "miras_gang", "World1 defaults to the authored Mira's Gang scenario")
	_check(ui.squad_names == ["Mira's Gang"], "Exactly one initial squad; no fallback Squad 1")
	_check(ui.squad_all_button.text == "All (5)", "All counts the five live members")
	_check(ui.squad_tab_buttons["Mira's Gang"].text == "Mira's Gang (5)", "Squad tab counts all five members")
	var names: Array[String] = []
	for member in party.party_members:
		names.append(member.member_name)
		_check(member.squad_name == "Mira's Gang" and member.faction_name == "Player", "Scenario applies squad and faction: " + member.member_name)
	_check(names == ["Mira", "Tomas", "Sable", "Bram", "Nika"], "Authored roster order and identities are preserved")
	await _click(ui.squad_tab_buttons["Mira's Gang"])
	_check(ui.active_squad_filter == "Mira's Gang", "Actual tab input selects the starting squad")
	_check(_visible_portraits() == 5, "Selected squad displays exactly five portraits")
	await _capture("miras-gang-start")

	await _click(ui.squad_add_button)
	_check(ui.squad_rename_dialog.visible and ui.squad_rename_dialog.title == "Create Squad", "Plus opens naming, not an automatic numbered squad")
	ui.squad_rename_line_edit.text = "Camp Guard"
	ui.squad_rename_line_edit.text_submitted.emit("Camp Guard")
	_check(ui.squad_tab_buttons.has("Camp Guard") and ui.squad_tab_buttons["Camp Guard"].text == "Camp Guard (0)", "Explicit empty squad is truthful")
	_check(_visible_portraits() == 0, "Empty squad has no portraits")
	ui._open_squad_rename_dialog("Mira's Gang")
	ui.squad_rename_line_edit.text_submitted.emit("Travelers")
	_check(ui.squad_tab_buttons.has("Travelers") and not ui.squad_tab_buttons.has("Mira's Gang"), "Rename updates the real squad and HUD")
	var departed := party.party_members[-1]
	var departed_id := departed.stable_id
	party.unregister_party_member(departed)
	_check(ui.squad_all_button.text == "All (4)", "Departure updates the displayed total immediately")
	var simulation := context.require(WorldSimulationController.SERVICE_ID) as WorldSimulationController
	_check(simulation.save_world_to_file(save_path), "Full session save writes changed roster and explicitly empty squad")
	context.require(PlayerPartyController.SERVICE_ID).rename_squad("Travelers", "Unsaved")
	_check(simulation.load_world_from_file(save_path), "Full session load with retained bodies succeeds")
	await process_frame
	await process_frame
	_check(ui.squad_names == ["Travelers", "Camp Guard"], "Loaded names replace unsaved state")
	_check(party.party_members.size() == 4 and ui.squad_tab_buttons["Travelers"].text == "Travelers (4)", "In-place load neither duplicates nor reseeds members")

	await CLEANUP.release_world(world, get_tree())
	if await _boot(save_path):
		_check(ui.squad_names == ["Travelers", "Camp Guard"], "Cold launch restores squad definitions before rendering")
		_check(party.party_members.size() == 4 and ui.squad_all_button.text == "All (4)", "Cold launch uses saved membership, not the five-person start")
		_check(ui.squad_tab_buttons["Travelers"].text == "Travelers (4)", "Cold-load squad count matches live roster")
		_check(not party.party_members.any(func(member): return member.stable_id == departed_id), "A departed starter stays departed")
		await _click(ui.squad_tab_buttons["Travelers"])
		_check(_visible_portraits() == 4, "Cold-load portraits match the saved squad")
	await _finish()

func _boot(path := "") -> bool:
	world = load(WORLD_PATH).instantiate() as WorldRoot
	world.saved_game_path = path
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 90000
	var stable_frames := 0
	while Time.get_ticks_msec() < deadline:
		await process_frame
		context = BootstrapContext.active
		if context == null:
			continue
		ui = context.get_optional(WorldInteractionController.SERVICE_ID) as WorldInteractionController
		party = context.root_scene.get_node_or_null("PartyManager") as PartyManager
		if ui != null and party != null and not party.party_members.is_empty() and not paused:
			stable_frames += 1
			if stable_frames >= 5:
				print("START_RUNTIME_ROSTER ", ui.squad_names, " total=", ui.squad_all_button.text)
				return true
		else:
			stable_frames = 0
	_check(false, "World1 startup/loading gates complete within 90 seconds")
	return false

func _click(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame

func _visible_portraits() -> int:
	var count := 0
	for card in ui.portrait_cards:
		if card.visible:
			count += 1
	return count

func _capture(label: String) -> void:
	var folder := OS.get_environment("PARTY_CAPTURE_DIR")
	if folder.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(folder)
	_check(root.get_texture().get_image().save_png(folder.path_join(label + ".png")) == OK, "Rendered fresh-start HUD capture")

func _check(ok: bool, message: String) -> void:
	print("START_CHECK ", "PASS " if ok else "FAIL ", message)
	if not ok:
		failures.append(message)

func _finish() -> void:
	await CLEANUP.release_world(world, get_tree())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("START_SCENARIOS ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
