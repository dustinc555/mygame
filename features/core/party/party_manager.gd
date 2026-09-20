extends Node

class_name PartyManager

const PLAYER_PARTY_ID := "player_party"

signal selection_changed
signal follow_changed
signal party_member_added(member)
signal party_member_removed(member)
signal party_membership_changed(member: WorldActor, party_id: String)

var party_members: Array[WorldActor] = []
var selected_members: Array[WorldActor] = []
var followed_member: WorldActor

# Population/GECS owns membership. These IDs retain only selection/follow
# intent while its disposable projection is absent; no Node survives LOD.
var _unrealized_selected_ids := PackedStringArray()
var _unrealized_followed_id := ""


func _ready() -> void:
	add_to_group("party_manager")


func set_party_members(members: Array) -> void:
	_unrealized_selected_ids.clear()
	_unrealized_followed_id = ""
	var previous_members := party_members.duplicate()
	var previous_selected := selected_members.duplicate()
	var previous_followed := followed_member
	var next_members: Array[WorldActor] = []
	for member in members:
		if not is_instance_valid(member):
			continue
		var actor := member as WorldActor
		if actor != null and is_instance_valid(actor) and not next_members.has(actor):
			next_members.append(actor)
	party_members = next_members
	for previous_member in previous_members:
		if previous_member != null and is_instance_valid(previous_member) and not party_members.has(previous_member):
			previous_member.remove_meta("party_id")
			party_membership_changed.emit(previous_member, "")
			previous_member.set_player_party_member(false)
			previous_member.set_selected(false)
			previous_member.set_focused(false)
			party_member_removed.emit(previous_member)
	for member in party_members:
		member.set_meta("party_id", PLAYER_PARTY_ID)
		_track_projection(member)
		party_membership_changed.emit(member, PLAYER_PARTY_ID)
		member.set_player_party_member(true)
	_prune_selection_to_party()
	if followed_member != null and not party_members.has(followed_member):
		followed_member = null
	_sync_member_states()
	if not _same_member_list(previous_selected, selected_members):
		selection_changed.emit()
	if previous_followed != followed_member:
		follow_changed.emit()


func clear_selection() -> void:
	_unrealized_selected_ids.clear()
	selected_members.clear()
	_sync_member_states()
	selection_changed.emit()


func select_only(member: WorldActor) -> void:
	_unrealized_selected_ids.clear()
	selected_members.clear()
	selected_members.append(member)
	_sync_member_states()
	selection_changed.emit()


func add_selection(member: WorldActor) -> void:
	if selected_members.has(member):
		return
	selected_members.append(member)
	_sync_member_states()
	selection_changed.emit()


func set_selection(members: Array) -> void:
	_unrealized_selected_ids.clear()
	selected_members.clear()
	for member in members:
		if is_instance_valid(member) and member is WorldActor and not selected_members.has(member):
			selected_members.append(member)
	_sync_member_states()
	selection_changed.emit()


func set_followed_member(member: WorldActor) -> void:
	_unrealized_followed_id = ""
	followed_member = member
	_sync_member_states()
	follow_changed.emit()


func clear_followed_member() -> void:
	_unrealized_followed_id = ""
	if followed_member == null:
		return
	followed_member = null
	_sync_member_states()
	follow_changed.emit()


func register_party_member(member: WorldActor) -> void:
	if member == null or party_members.has(member):
		return
	_track_projection(member)
	var stable_id := _stable_member_id(member)
	if not stable_id.is_empty():
		for index in party_members.size():
			var existing := party_members[index]
			if _stable_member_id(existing) != stable_id:
				continue
			var was_selected := selected_members.has(existing)
			var was_followed := followed_member == existing
			party_members[index] = member
			selected_members.erase(existing)
			if was_selected:
				selected_members.append(member)
			if was_followed:
				followed_member = member
			existing.set_player_party_member(false)
			existing.remove_meta("party_id")
			existing.set_selected(false)
			existing.set_focused(false)
			party_member_removed.emit(existing)
			member.set_meta("party_id", PLAYER_PARTY_ID)
			party_membership_changed.emit(member, PLAYER_PARTY_ID)
			member.set_player_party_member(true)
			_sync_member_states()
			party_member_added.emit(member)
			if was_selected:
				selection_changed.emit()
			if was_followed:
				follow_changed.emit()
			return
	party_members.append(member)
	var was_selected := _unrealized_selected_ids.has(stable_id)
	var was_followed := not stable_id.is_empty() and _unrealized_followed_id == stable_id
	if was_selected:
		_unrealized_selected_ids.remove_at(_unrealized_selected_ids.find(stable_id))
		selected_members.append(member)
	if was_followed:
		_unrealized_followed_id = ""
		followed_member = member
	member.set_meta("party_id", PLAYER_PARTY_ID)
	party_membership_changed.emit(member, PLAYER_PARTY_ID)
	member.set_player_party_member(true)
	_sync_member_states()
	party_member_added.emit(member)
	if was_selected:
		selection_changed.emit()
	if was_followed:
		follow_changed.emit()


func _track_projection(member: WorldActor) -> void:
	var on_exit := _on_projection_exiting.bind(member)
	if not member.tree_exiting.is_connected(on_exit):
		member.tree_exiting.connect(on_exit, CONNECT_ONE_SHOT)


func _on_projection_exiting(member: WorldActor) -> void:
	# tree_exiting runs while the body is still valid, before consumers can
	# receive a freed typed argument. A superseded body's exit is a no-op.
	if not party_members.has(member):
		return
	var stable_id := _stable_member_id(member)
	var was_selected := selected_members.has(member)
	var was_followed := followed_member == member
	if was_selected and not stable_id.is_empty() and not _unrealized_selected_ids.has(stable_id):
		_unrealized_selected_ids.append(stable_id)
	if was_followed:
		_unrealized_followed_id = stable_id
	party_members.erase(member)
	selected_members.erase(member)
	if was_followed:
		followed_member = null
	# This signal removes projection UI/caches. Unlike explicit departure,
	# do not change the actor flag, metadata or durable membership signal.
	party_member_removed.emit(member)
	if was_selected:
		selection_changed.emit()
	if was_followed:
		follow_changed.emit()


func _stable_member_id(member: WorldActor) -> String:
	if member == null or not is_instance_valid(member):
		return ""
	var stable_id := str(member.stable_id).strip_edges()
	if stable_id.is_empty() and member.has_meta("actor_record_id"):
		stable_id = str(member.get_meta("actor_record_id")).strip_edges()
	return stable_id


func unregister_party_member(member: WorldActor) -> void:
	if member == null or not party_members.has(member):
		return
	party_members.erase(member)
	selected_members.erase(member)
	if followed_member == member:
		followed_member = null
		follow_changed.emit()
	member.set_player_party_member(false)
	member.remove_meta("party_id")
	party_membership_changed.emit(member, "")
	party_member_removed.emit(member)
	_sync_member_states()
	selection_changed.emit()


func _sync_member_states() -> void:
	for member in party_members:
		member.set_selected(selected_members.has(member))
		member.set_focused(member == followed_member)


func _prune_selection_to_party() -> void:
	var pruned_selection: Array[WorldActor] = []
	for member in selected_members:
		if member != null and is_instance_valid(member) and party_members.has(member) and not pruned_selection.has(member):
			pruned_selection.append(member)
	selected_members = pruned_selection


func _same_member_list(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	for index in range(left.size()):
		if left[index] != right[index]:
			return false
	return true
