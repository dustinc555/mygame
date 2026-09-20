extends "res://tests/validation/test_case.gd"
## Run: python3 tests/run_validation.py --jobs 1 --filter tests/validation/validate_recruited_party_selection.gd

const TEST_SCENE_PATH := "res://scenes/test_levels/farming_test.tscn"
const MERCHANT_HUMANOID_PATH := "res://features/actors/projection/humanoid/merchant_humanoid.gd"
const FACTION_HUMANOID_PATH := "res://features/actors/projection/humanoid/faction_humanoid.gd"
const ADA_DEFINITION_PATH := "res://features/actors/resources/characters/ada.tres"
const PLAYER_FACTION_PATH := "res://features/factions/resources/factions/player_drifters.tres"


class EffectFixture:
	extends RefCounted
	var action_id := ""
	var parameters: Dictionary = {}
	func _init(next_action_id: String, next_parameters: Dictionary) -> void:
		action_id = next_action_id
		parameters = next_parameters


var _failures: Array[String] = []
var _save_path := "user://recruited_party_validation_%d.tres" % OS.get_process_id()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(TEST_SCENE_PATH) as PackedScene
	_expect(packed != null, "runtime bootstrap scene loads")
	if packed == null:
		_finish()
		return
	var root := packed.instantiate()
	var scene_ada := root.get_node_or_null("PartyMembers/Ada")
	if scene_ada != null:
		scene_ada.get_parent().remove_child(scene_ada)
		scene_ada.free()
	get_root().add_child(root)
	for _frame in range(600):
		var ready_context := BootstrapContext.active
		if ready_context != null and ready_context.get_optional(&"conversation") != null and ready_context.get_optional(&"population_character_realizer") != null: break
		await process_frame
	var context := BootstrapContext.active
	var party_manager := root.get_node_or_null("PartyManager")
	var startup_member := root.get_node_or_null("PartyMembers/Bram")
	var population = context.get_optional(&"population") if context != null else null
	var realizer = context.get_optional(&"population_character_realizer") if context != null else null
	var conversation = context.get_optional(&"conversation") if context != null else null
	_expect(party_manager != null and startup_member != null and population != null and realizer != null and conversation != null, "runtime party, conversation, and population services are live")
	if party_manager == null or startup_member == null or population == null or realizer == null or conversation == null:
		_finish()
		return

	var merchant_script := load(MERCHANT_HUMANOID_PATH) as Script
	var player_faction = load(PLAYER_FACTION_PATH)
	var character_realizer = player_faction.call("get_character_realizer") if player_faction != null else null
	var name_profile = player_faction.call("get_population_name_profile") if player_faction != null else null
	_expect(merchant_script != null and character_realizer != null and name_profile != null, "runtime character profiles load after bootstrap")
	if merchant_script == null or character_realizer == null or name_profile == null:
		_finish()
		return

	var record: Dictionary = population.call("ensure_preferred_assignment_record", "farming_test", {
		"slot_id": "ada-runtime-selection",
		"preferred_actor_id": "ada",
		"preferred_character_path": ADA_DEFINITION_PATH,
	}, {
		"faction_id": "Canyon",
		"role_id": "resident",
		"population_appearance_profile": character_realizer,
		"population_name_profile": name_profile,
	})
	_expect(str(record.get("actor_id", "")) == "ada", "canonical permanent Ada record is created once")
	var recruited = realizer.call("realize_record_actor", "ada", root.get_node("PartyMembers"), "Ada")
	await process_frame
	var faction_humanoid_script := load(FACTION_HUMANOID_PATH) as Script
	_expect(recruited != null and recruited.get_script() == faction_humanoid_script and str(recruited.get("stable_id")) == "ada" and str(recruited.get("member_name")) == "Ada", "canonical Ada is realized as the existing permanent FactionHumanoid")
	if recruited == null:
		_finish()
		return
	var realized_again = realizer.call("realize_record_actor", "ada", root.get_node("PartyMembers"), "Ada")
	var ada_actor_count := 0
	for actor in root.get_node("PartyMembers").get_children():
		if str(actor.get("stable_id")) == "ada":
			ada_actor_count += 1
	_expect(realized_again == recruited and ada_actor_count == 1 and population.call("get_live_actor", "ada") == recruited, "Ada realization reuses one live actor and one population identity")
	var recruited_ring := recruited.get_node_or_null("SelectionRing") as MeshInstance3D
	var startup_ring := startup_member.get_node_or_null("SelectionRing") as MeshInstance3D
	_expect(recruited_ring != null and startup_ring != null and recruited_ring != startup_ring, "recruited and startup actors own independent rings")

	conversation.set("active_target", recruited)
	conversation.call("_apply_effects", [
		EffectFixture.new("core.join_party", {"subject": "conversation_target"}),
		EffectFixture.new("core.set_faction", {"subject": "conversation_target", "faction_name": "Player"}),
	])
	await process_frame
	var recruited_record: Dictionary = population.call("get_actor_record", "ada")
	_expect(str(recruited_record.get("party_id", "")) == str(party_manager.PLAYER_PARTY_ID) and str(recruited_record.get("faction_id", "")) == "Player", "recruitment persists Ada's party and Player faction to the durable record")
	await _validate_jobs_window_and_save(context, root, recruited, population, party_manager)
	party_manager.select_only(recruited)
	_expect(recruited.is_player_party_member(), "registration grants full current core-party membership")
	_expect(recruited_ring != null and recruited_ring.visible, "PartyManager selection shows the recruited actor's ring")
	_expect(startup_ring != null and not startup_ring.visible, "selecting the recruit does not show the startup actor's ring")
	party_manager.clear_selection()
	_expect(not recruited.is_selected and recruited_ring != null and not recruited_ring.visible, "clearing selection hides the recruited actor's ring before focus")
	party_manager.set_followed_member(recruited)
	_expect(recruited.is_focused and not recruited.is_selected and recruited_ring != null and recruited_ring.visible, "PartyManager focus alone shows the recruited actor's ring")
	party_manager.clear_followed_member()
	_expect(not recruited.is_focused and recruited_ring != null and not recruited_ring.visible, "clearing focus alone hides the recruited actor's ring")
	party_manager.select_only(startup_member)
	_expect(startup_ring != null and startup_ring.visible, "startup PartyMember selection still shows its ring")
	_expect(recruited_ring != null and not recruited_ring.visible, "switching selection clears only the recruited actor's ring")

	var merchant = merchant_script.new()
	merchant.name = "MerchantSelectionFixture"
	merchant.stable_id = "merchant-selection-fixture"
	realizer.call("_ensure_projection_bootstrap", merchant)
	root.add_child(merchant)
	await process_frame
	var merchant_ring := merchant.get_node_or_null("SelectionRing") as MeshInstance3D
	merchant.set_selected(true)
	_expect(merchant_ring != null and merchant_ring.visible, "MerchantHumanoid selection behavior still works")
	merchant.set_selected(false)
	_expect(merchant_ring != null and not merchant_ring.visible, "MerchantHumanoid clears its own ring")

	party_manager.unregister_party_member(recruited)
	population.call("unregister_actor", recruited)
	recruited.get_parent().remove_child(recruited)
	await process_frame
	population.call("update_actor_record", "ada", {"party_id": str(party_manager.PLAYER_PARTY_ID), "faction_id": "Player"})
	var durable_record: Dictionary = population.call("get_actor_record", "ada")
	_expect(not bool(population.call("_eligible_for_assignment", durable_record, "farming_test", "employment", "employment")), "offscreen party records cannot reclaim settlement assignments")
	var restored = realizer.call("realize_record_actor", "ada", root.get_node("PartyMembers"), "AdaRestored")
	await process_frame
	_expect(restored != null and party_manager.party_members.has(restored) and restored.is_player_party_member(), "re-realized Ada restores full PartyManager membership from the durable record")
	if restored != null:
		party_manager.select_only(restored)
		var restored_ring := restored.get_node_or_null("SelectionRing") as MeshInstance3D
		_expect(restored_ring != null and restored_ring.visible, "restored Ada remains selectable with her own ring")
		var replacement = (load(FACTION_HUMANOID_PATH) as Script).new()
		replacement.stable_id = "ada"
		replacement.set_meta("actor_record_id", "ada")
		realizer.call("_ensure_projection_bootstrap", replacement)
		root.get_node("PartyMembers").add_child(replacement)
		population.call("apply_record_to_actor", replacement, durable_record)
		await process_frame
		var ada_member_count := 0
		for party_member in party_manager.party_members:
			if party_member != null and is_instance_valid(party_member) and str(party_member.stable_id) == "ada":
				ada_member_count += 1
		_expect(ada_member_count == 1 and party_manager.party_members.has(replacement) and not party_manager.party_members.has(restored), "replacement canonical actor supersedes stale live PartyManager membership")
		_expect(party_manager.selected_members.has(replacement), "replacement canonical actor preserves selection")
		restored.free()
		restored = replacement
		var pre_recruitment_record := durable_record.duplicate(true)
		pre_recruitment_record["party_id"] = ""
		population.call("apply_record_to_actor", restored, pre_recruitment_record)
		await process_frame
		_expect(not party_manager.party_members.has(restored) and not restored.is_player_party_member(), "pre-recruitment record hydration removes stale PartyManager membership")
	recruited.free()
	root.free()
	await process_frame
	_finish()


func _validate_jobs_window_and_save(context: BootstrapContext, game: Node, actor: WorldActor, population: Node, party_manager: Node) -> void:
	var jobs: Node = context.require(&"job_system")
	var window := CharacterJobsWindow.new()
	game.add_child(window)
	window.setup(game)
	window.show_for_actor(actor)
	window.set_process(false)
	var before: Array = jobs.get_actor_ranked_jobs(actor)
	_expect(before.size() >= 2 and window.rows_root.get_child_count() == before.size(), "real Ada Jobs window renders controller ranks")
	if before.size() >= 2:
		var second: Node = window.rows_root.get_child(1)
		var up: Button
		for child in second.get_children():
			if child is Button and child.text == "Up": up = child
		_expect(up != null and not up.disabled, "party Jobs row exposes enabled move control")
		if up != null:
			up.pressed.emit()
			var after: Array = jobs.get_actor_ranked_jobs(actor)
			_expect(after[0].get("entry_id") == before[1].get("entry_id"), "actual Up signal changes durable controller rank")
	window.free()
	var interaction := game.find_child("WorldInteractionController", true, false)
	party_manager.select_only(actor)
	if interaction != null:
		var jobs_button = interaction.get("jobs_button")
		_expect(jobs_button is Button, "selected-actor HUD owns the Jobs button")
		if jobs_button is Button:
			jobs_button.set_pressed_no_signal(true)
			jobs_button.toggled.emit(true)
			_expect(jobs.is_actor_jobs_enabled(actor), "actual selected-character Jobs toggle enables Ada policy")
	else:
		_expect(false, "Jobs UI integration requires WorldInteractionController")
	var world_sim: Node = context.require(&"world_simulation")
	_expect(world_sim.save_world_to_file(_save_path, false), "recruited Ada and Jobs save through the registered world service")
	population.update_actor_record("ada", {"party_id": "", "faction_id": "Canyon"})
	jobs.set_actor_jobs_enabled(actor, false)
	_expect(world_sim.load_world_from_file(_save_path), "registered world load refreshes Ada and Jobs from GECS")
	await process_frame
	var saved: Dictionary = population.get_actor_record("ada")
	_expect(saved.get("party_id") == str(party_manager.PLAYER_PARTY_ID) and saved.get("faction_id") == "Player", "GECS load restores conversation recruitment instead of changed after-save state")
	_expect(party_manager.party_members.has(actor) and actor.is_player_party_member(), "in-place load hydrates recruited membership to the live actor")
	_expect(jobs.is_actor_jobs_enabled(actor), "GECS load restores the real HUD Jobs policy")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if FileAccess.file_exists(_save_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(_save_path))
	if _failures.is_empty():
		print("RECRUITED_PARTY_SELECTION_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("RECRUITED_PARTY_SELECTION_FAILED count=%d" % _failures.size())
	quit(1)
