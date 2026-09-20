extends "res://tests/validation/law_order_cases.gd"

## A selected/followed record survives destruction; consumers see live bodies only.
var _checks := 0
var _membership_events: Array[String] = []

func _run() -> void:
	if await _load_fixture():
		var party := _scene.get_node("PartyManager") as PartyManager
		var population := BootstrapContext.service(PopulationController.SERVICE_ID) as PopulationController
		var realizer := BootstrapContext.service(PopulationCharacterRealizer.SERVICE_ID) as PopulationCharacterRealizer
		var actor := _get_player()
		var actor_id := actor.stable_id
		var parent := actor.get_parent()
		party.select_only(actor)
		party.set_followed_member(actor)
		await process_frame
		await process_frame
		var visibility := BootstrapContext.service(BuildingVisibilityController.SERVICE_ID) as BuildingVisibilityController
		_expect(visibility.get("_latched_focus_actor") == actor, "Camera latch must really retain the followed projection before LOD")
		party.party_membership_changed.connect(func(member: WorldActor, party_id: String) -> void:
			_membership_events.append("%s:%s" % [member.stable_id, party_id])
		)
		_expect(party.party_members.has(actor) and actor.is_selected and actor.is_focused, "Selected/followed party projection must exist before LOD")
		var instance_id := actor.get_instance_id()
		population.unregister_actor(actor)
		actor.queue_free()
		await _wait_frames(3)
		_expect(not is_instance_id_valid(instance_id) and population.get_live_actor(actor_id) == null, "LOD must actually destroy the projection")
		_expect(_all_live(party.party_members) and _all_live(party.selected_members) and party.followed_member == null, "PartyManager must remove dead projection references before consumers resume")
		_expect(visibility.get("_visibility_actor") == null and visibility.get("_latched_focus_actor") == null, "Shared party removal must release downstream camera latches before they become freed typed arguments")
		_expect(str(population.get_actor_record(actor_id).get("party_id", "")) == PartyManager.PLAYER_PARTY_ID and _membership_events.is_empty(), "Projection loss must not revoke durable membership or emit departure")
		var replacement := realizer.realize_record_actor(actor_id, parent, "MiraRestored") as WorldActor
		await _wait_frames(3)
		_expect(is_instance_valid(replacement) and replacement.get_instance_id() != instance_id and party.party_members.has(replacement), "Record realization must bind a new live party projection")
		_expect(party.selected_members.has(replacement) and party.followed_member == replacement and replacement.is_selected and replacement.is_focused, "Selection and follow must rebind to the same durable identity")
		# A later command while absent supersedes the retained selection/follow.
		population.unregister_actor(replacement)
		replacement.queue_free()
		await _wait_frames(3)
		party.clear_selection()
		party.clear_followed_member()
		replacement = realizer.realize_record_actor(actor_id, parent, "MiraRebound") as WorldActor
		await _wait_frames(3)
		_expect(not party.selected_members.has(replacement) and party.followed_member == null, "Clearing selection/follow while absent must not resurrect obsolete intent")
		party.unregister_party_member(replacement)
		_expect(str(population.get_actor_record(actor_id).get("party_id", "")) == "" and not replacement.is_player_party_member(), "Explicit departure must still revoke durable membership")
	await FIXTURE.release_world(_scene, get_tree())
	for failure in _failures:
		push_error(failure)
	print("PARTY_PROJECTION_LIFECYCLE_%s checks=%d" % ["OK" if _failures.is_empty() else "FAILED", _checks])
	quit(0 if _failures.is_empty() else 1)

func _all_live(members: Array) -> bool:
	for member in members:
		if not is_instance_valid(member) or member.is_queued_for_deletion():
			return false
	return true

func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_fail(message)
