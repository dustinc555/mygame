extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_ranked_party_jobs.gd

const JOB_SYSTEM = preload("res://features/settlements/sim/job_system_controller.gd")

class FakeGecs:
	extends Node
	var state: Dictionary = {}
	var settlements := {
		"settlement:home": {"settlement_id": "settlement:home", "faction_id": "Player", "world_position": Vector3.ZERO, "radius": 25.0},
		"settlement:other": {"settlement_id": "settlement:other", "faction_id": "Player", "world_position": Vector3(200, 0, 0), "radius": 25.0},
		"settlement:foreign": {"settlement_id": "settlement:foreign", "faction_id": "Other", "world_position": Vector3(400, 0, 0), "radius": 25.0},
	}
	func get_job_system_state() -> Dictionary:
		return state.duplicate(true)
	func upsert_job_system_state(next_state: Dictionary) -> Dictionary:
		state = next_state.duplicate(true)
		return state.duplicate(true)
	func get_actor_job_contracts(actor: Node) -> Array[Dictionary]:
		if str(actor.get("stable_id")) != "party:one":
			return []
		return [{
			"contract_id": "contract:bartender",
			"display_name": "Bartender",
			"provider_name": "The Rusty Flagon",
			"provider_id": "provider:tavern",
			"priority_order": 0,
		}]
	func get_settlement_states() -> Dictionary:
		return settlements.duplicate(true)

class FakeProvider:
	extends Node3D
	var accepted: Array[Dictionary] = []
	var mine_allowed_actor_ids := PackedStringArray()
	var rejection_messages: Dictionary = {}
	var facility_actionable := true
	func get_provider_id() -> String:
		return "provider:tavern"
	func get_contract_work_status(_actor: Node, _contract: Dictionary) -> Dictionary:
		return {"actionable": facility_actionable}
	func get_job_category_specs(_settlement_id := "") -> Array:
		return [{"category": "forestry", "display_name": "Forestry"}]
	func get_available_work_offers(settlement_id := "") -> Array:
		var offers := [
			{"offer_id": "farm:near", "category": "farm", "settlement_id": "settlement:home", "world_position": Vector3(2, 0, 0), "urgency": 0.4},
			{"offer_id": "mine:far", "category": "mine", "settlement_id": "settlement:home", "world_position": Vector3(8, 0, 0), "urgency": 0.2, "allowed_actor_ids": mine_allowed_actor_ids},
			{"offer_id": "mine:other", "category": "mine", "settlement_id": "settlement:other", "world_position": Vector3(202, 0, 0), "urgency": 1.0},
			{"offer_id": "farm:foreign-owned-home", "category": "farm", "settlement_id": "settlement:home", "owner_faction_id": "Other", "world_position": Vector3.ONE, "urgency": 1.0},
			{"offer_id": "farm:basic-city", "category": "farm", "settlement_id": "", "owner_faction_id": "Player", "world_position": Vector3(50, 0, 0), "urgency": 0.5},
			{"offer_id": "farm:distant-unassigned", "category": "farm", "settlement_id": "", "owner_faction_id": "Player", "world_position": Vector3(300, 0, 0), "urgency": 1.0},
			{"offer_id": "farm:foreign-unassigned", "category": "farm", "settlement_id": "", "owner_faction_id": "Other", "world_position": Vector3.ONE, "urgency": 1.0},
		]
		for offer in offers:
			offer["provider"] = self
		if settlement_id.is_empty():
			return offers
		return offers.filter(func(offer: Dictionary) -> bool: return str(offer.get("settlement_id", "")) == settlement_id)
	func accept_work_offer(offer: Dictionary, actor: Node) -> String:
		var offer_id := str(offer.get("offer_id", ""))
		if rejection_messages.has(offer_id):
			return str(rejection_messages[offer_id])
		accepted.append({"offer_id": offer_id, "actor": actor})
		return "1 worker assigned"
	func has_active_work_for_actor(_actor: Node) -> bool:
		return false

class FakeActor:
	extends Node3D
	var stable_id := ""
	var settlement_id := ""
	var faction_name := ""
	var party := false
	var active_player_order := false
	var life_state := 0
	func is_player_party_member() -> bool:
		return party
	func has_active_player_order() -> bool:
		return active_player_order
	func get_active_job_provider():
		return null

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene_root := Node.new()
	root.add_child(scene_root)
	var context := BootstrapContext.new(scene_root)
	var gecs := FakeGecs.new()
	var provider := FakeProvider.new()
	var jobs = JOB_SYSTEM.new()
	scene_root.add_child(gecs)
	scene_root.add_child(provider)
	provider.add_to_group("job_provider")
	scene_root.add_child(jobs)
	context.register(&"gecs_world", gecs)
	context.register(&"job_system", jobs)
	jobs.initialize(context)

	var party := FakeActor.new()
	party.stable_id = "party:one"
	party.settlement_id = ""
	party.faction_name = "Player"
	party.set_meta("settlement_id", "settlement:home")
	party.party = true
	party.add_to_group("party_member")
	scene_root.add_child(party)
	var npc := FakeActor.new()
	npc.stable_id = "npc:one"
	npc.settlement_id = "settlement:home"
	scene_root.add_child(npc)

	_expect(jobs.has_method("get_actor_ranked_jobs"), "job system exposes a unified ranked-list API")
	_expect(jobs.has_method("set_actor_jobs_enabled"), "job system exposes the party Jobs toggle")
	_expect(jobs.has_method("move_actor_job_entry"), "ranked entries can move")
	_expect(jobs.has_method("dispatch_actor_work"), "job system exposes bounded party work dispatch")
	if jobs.has_method("get_actor_ranked_jobs"):
		var rows: Array = jobs.call("get_actor_ranked_jobs", party)
		_expect(_labels(rows) == ["Farm", "Guard", "Mine", "Research", "Crafting", "Medicine", "Forestry", "Bartender at The Rusty Flagon"], "party list contains settlement categories, extensible provider categories, and a named facility role")
		_expect(rows.all(func(row: Dictionary) -> bool: return int(row.get("priority_order", -1)) >= 0), "every Jobs row has an explicit rank")
		_expect((jobs.call("get_actor_ranked_jobs", npc) as Array).is_empty(), "resident NPCs do not receive player Jobs rankings")

	if jobs.has_method("set_actor_jobs_enabled"):
		_expect(not bool(jobs.call("is_actor_jobs_enabled", party)), "party Jobs defaults off")
		_expect(bool(jobs.call("set_actor_jobs_enabled", party, true)), "party member can enable Jobs")
		_expect(bool(jobs.call("is_actor_jobs_enabled", party)), "enabled Jobs state is readable")
		_expect(not bool(jobs.call("set_actor_jobs_enabled", npc, true)), "NPC cannot be enrolled by the player Jobs toggle")

	if jobs.has_method("move_actor_job_entry"):
		jobs.call("move_actor_job_entry", party, "category:mine", -2)
		var moved: Array = jobs.call("get_actor_ranked_jobs", party)
		_expect(not moved.is_empty() and str(moved[0].get("entry_id", "")) == "category:mine", "moving Mine upward changes the durable order")
		_expect((gecs.state.get("actor_policies", {}) as Dictionary).has("party:one"), "party Jobs policy persists through GECS job-system state")
		jobs.call("move_actor_job_entry", party, "facility_contract:contract:bartender", -7)
		provider.accepted.clear()
		jobs.call("dispatch_actor_work", party)
		_expect(provider.accepted.is_empty(), "higher-ranked actionable facility role blocks lower-ranked settlement offers")
		jobs.call("move_actor_job_entry", party, "category:mine", -1)
		provider.facility_actionable = false

	if jobs.has_method("dispatch_actor_work"):
		provider.mine_allowed_actor_ids = PackedStringArray(["party:other"])
		provider.accepted.clear()
		jobs.call("dispatch_actor_work", party)
		_expect(provider.accepted.size() == 1 and str(provider.accepted[0].get("offer_id", "")) == "farm:near", "manual cell reservation prevents another ranked worker from claiming it")
		provider.mine_allowed_actor_ids = PackedStringArray(["party:one"])
		provider.rejection_messages = {"mine:far": "Cell is already assigned"}
		provider.accepted.clear()
		jobs.call("dispatch_actor_work", party)
		_expect(provider.accepted.size() == 1 and str(provider.accepted[0].get("offer_id", "")) == "farm:near", "claimed-cell rejection is not misread as successful dispatch")
		provider.rejection_messages.clear()
		provider.accepted.clear()
		jobs.call("dispatch_actor_work", party)
		_expect(provider.accepted.size() == 1 and str(provider.accepted[0].get("offer_id", "")) == "mine:far", "dispatcher selects the highest-ranked eligible category in the assigned settlement")
		jobs.call("set_actor_jobs_enabled", party, false)
		provider.accepted.clear()
		jobs.call("dispatch_actor_work", party)
		_expect(provider.accepted.is_empty(), "Jobs off prevents automatic claims")
		jobs.call("set_actor_jobs_enabled", party, true)
		party.active_player_order = true
		jobs.call("dispatch_actor_work", party)
		_expect(provider.accepted.is_empty(), "manual player order blocks automatic Jobs dispatch")
		party.active_player_order = false
		jobs.call("dispatch_actor_work", npc)
		_expect(provider.accepted.is_empty(), "NPC facility behavior is not touched by party Jobs dispatch")

		party.global_position = Vector3(200, 0, 0)
		provider.accepted.clear()
		jobs.call("dispatch_actor_work", party)
		_expect(provider.accepted.size() == 1 and str(provider.accepted[0].get("offer_id", "")) == "mine:other", "physical presence lets a visiting party member work in the current friendly town")
		party.global_position = Vector3(150, 0, 0)
		provider.accepted.clear()
		jobs.call("dispatch_actor_work", party)
		_expect(provider.accepted.is_empty(), "Jobs leaves a party member idle between towns instead of sending them to distant work")
		party.global_position = Vector3(400, 0, 0)
		provider.accepted.clear()
		jobs.call("dispatch_actor_work", party)
		_expect(provider.accepted.is_empty(), "nearby other-faction town work remains unavailable")
		party.global_position = Vector3.ZERO
		gecs.settlements.clear()
		party.global_position = Vector3(200, 0, 0)
		provider.accepted.clear()
		jobs.call("dispatch_actor_work", party)
		_expect(provider.accepted.is_empty(), "missing settlement bounds cannot send an actor to distant permanently assigned work")
		gecs.settlements = {
			"settlement:home": {"settlement_id": "settlement:home", "faction_id": "Player", "world_position": Vector3.ZERO, "radius": 25.0},
			"settlement:other": {"settlement_id": "settlement:other", "faction_id": "Player", "world_position": Vector3(200, 0, 0), "radius": 25.0},
			"settlement:foreign": {"settlement_id": "settlement:foreign", "faction_id": "Other", "world_position": Vector3(400, 0, 0), "radius": 25.0},
		}
		party.global_position = Vector3.ZERO

	var basic_city_party := FakeActor.new()
	basic_city_party.stable_id = "party:basic-city"
	basic_city_party.faction_name = "Player"
	basic_city_party.position = Vector3(50, 0, 0)
	basic_city_party.party = true
	basic_city_party.add_to_group("party_member")
	scene_root.add_child(basic_city_party)
	jobs.call("set_actor_jobs_enabled", basic_city_party, true)
	provider.accepted.clear()
	jobs.call("dispatch_actor_work", basic_city_party)
	_expect(provider.accepted.size() == 1 and str(provider.accepted[0].get("offer_id", "")) == "farm:basic-city", "Jobs can claim same-faction basic-city work when neither actor nor work belongs to a named settlement")

	var ui_source := FileAccess.get_file_as_string("res://features/ui/projection/character_jobs_window.gd")
	_expect(not ui_source.contains("CheckButton") and not ui_source.contains("jobs_toggle") and ui_source.contains("get_actor_ranked_jobs") and ui_source.contains("move_actor_job_entry"), "Jobs window contains priorities without a second Jobs on/off control")
	_expect(ui_source.contains("else _can_edit_jobs()") and ui_source.contains("_build_job_row(row, editable)"), "non-party facility contract controls retain their previous faction authorization")
	var world_ui_source := FileAccess.get_file_as_string("res://features/world/bridge/world_interaction_controller.gd")
	var hud_source := FileAccess.get_file_as_string("res://features/ui/projection/game_hud.tscn")
	_expect(world_ui_source.contains("jobs_button") and world_ui_source.contains("_on_jobs_button_toggled") and hud_source.contains("JobsButton") and hud_source.contains("text = \"Jobs\""), "Jobs on/off is a normal button in the selected-character behavior controls")
	var ai_source := FileAccess.get_file_as_string("res://features/ai/bridge/ai_utility_adapter.gd")
	var farm_work_source := FileAccess.get_file_as_string("res://features/farming/bridge/farm_work_bridge.gd")
	_expect(ai_source.contains("active_settlement_work") and farm_work_source.contains("ACTIVE_SETTLEMENT_WORK_META"), "active category work owns the actor against lower-ranked facility AI")

	scene_root.queue_free()
	_finish()


func _labels(rows: Array) -> Array[String]:
	var labels: Array[String] = []
	for row in rows:
		labels.append(str((row as Dictionary).get("display_name", "")))
	return labels


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("RANKED_PARTY_JOBS_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("RANKED_PARTY_JOBS_FAILED count=%d" % failures.size())
	quit(1)
