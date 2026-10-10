extends GutTest

func _hud() -> WorldInteractionController:
	var hud := WorldInteractionController.new()
	add_child_autofree(hud)
	hud.party_manager = PartyManager.new()
	hud.add_child(hud.party_manager)
	hud.hud_layer = CanvasLayer.new()
	hud.add_child(hud.hud_layer)
	hud.squad_tab_row = HBoxContainer.new()
	hud.hud_layer.add_child(hud.squad_tab_row)
	hud.squad_all_button = Button.new()
	hud.squad_tab_row.add_child(hud.squad_all_button)
	hud.squad_add_button = Button.new()
	hud.squad_tab_row.add_child(hud.squad_add_button)
	hud.portrait_flow = HBoxContainer.new()
	hud.hud_layer.add_child(hud.portrait_flow)
	hud.party_manager.party_member_added.connect(hud._on_party_member_added)
	hud.party_manager.party_member_removed.connect(hud._on_party_member_removed)
	return hud

func _member(id: String, squad: String) -> HumanoidCharacter:
	var member := HumanoidCharacter.new()
	autofree(member)
	member.stable_id = id
	member.member_name = id
	member.squad_name = squad
	return member

func test_empty_or_unassigned_party_never_invents_or_assigns_a_squad() -> void:
	var hud := _hud()
	hud._refresh_squad_tabs()
	assert_true(hud.squad_names.is_empty())
	assert_eq(hud.squad_all_button.text, "All (0)")
	var member := _member("test.unassigned", "")
	hud.party_manager.register_party_member(member)
	assert_eq(member.squad_name, "", "Rendering is not membership authority")
	assert_true(hud.squad_names.is_empty())
	assert_eq(hud.squad_all_button.text, "All (1)")
	assert_eq(hud.portrait_cards.size(), 1)

func test_counts_and_portraits_follow_late_changes_and_replacements() -> void:
	var hud := _hud()
	var first := _member("test.first", "Travelers")
	var second := _member("test.second", "Travelers")
	hud.party_manager.register_party_member(first)
	hud.party_manager.register_party_member(second)
	hud._on_squad_tab_toggled(true, "Travelers")
	assert_eq(hud.squad_tab_buttons["Travelers"].text, "Travelers (2)")
	assert_true(hud.portrait_cards[0].visible)
	assert_true(hud.portrait_cards[1].visible)
	second.squad_name = "Scouts"
	assert_eq(hud.squad_tab_buttons["Travelers"].text, "Travelers (1)")
	assert_true(hud.squad_tab_buttons.has("Scouts"))
	assert_false(hud.portrait_cards[1].visible)
	var replacement := _member("test.first", "Scouts")
	hud.party_manager.register_party_member(replacement)
	assert_eq(hud.party_members.size(), 2)
	assert_eq(hud.portrait_cards.size(), 2)
	assert_false(hud.squad_tab_buttons.has("Travelers"))
	assert_eq(hud.squad_tab_buttons["Scouts"].text, "Scouts (2)")
	assert_false(first.simulation_profile_changed.is_connected(Callable(hud, "_on_member_squad_changed").bind(first)))
	# A removed projection cannot cause stale UI changes or duplicate callbacks.
	first.squad_name = "Ghost"
	assert_false(hud.squad_tab_buttons.has("Ghost"))
	await get_tree().process_frame

func test_add_requires_an_explicit_name_and_cancel_creates_nothing() -> void:
	var hud := _hud()
	hud._refresh_squad_tabs()
	hud._on_add_squad_pressed()
	assert_true(hud.squad_names.is_empty())
	assert_not_null(hud.squad_rename_dialog)
	if hud.squad_rename_dialog != null:
		assert_eq(hud.squad_rename_dialog.title, "Create Squad")
		hud.squad_rename_dialog.hide()
	assert_true(hud.squad_names.is_empty())
