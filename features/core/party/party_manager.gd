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


func _ready() -> void:
	add_to_group("party_manager")


func set_party_members(members: Array) -> void:
	var previous_members := party_members.duplicate()
	var previous_selected := selected_members.duplicate()
	var previous_followed := followed_member
	var next_members: Array[WorldActor] = []
	for member in members:
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
	selected_members.clear()
	_sync_member_states()
	selection_changed.emit()


func select_only(member: WorldActor) -> void:
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
	selected_members.clear()
	for member in members:
		if member is WorldActor and not selected_members.has(member):
			selected_members.append(member)
	_sync_member_states()
	selection_changed.emit()


func set_followed_member(member: WorldActor) -> void:
	followed_member = member
	_sync_member_states()
	follow_changed.emit()


func clear_followed_member() -> void:
	if followed_member == null:
		return
	followed_member = null
	_sync_member_states()
	follow_changed.emit()


func register_party_member(member: WorldActor) -> void:
	if member == null or party_members.has(member):
		return
	for index in range(party_members.size() - 1, -1, -1):
		var existing := party_members[index]
		if existing == null or not is_instance_valid(existing):
			party_members.remove_at(index)
			selected_members.erase(existing)
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
	member.set_meta("party_id", PLAYER_PARTY_ID)
	party_membership_changed.emit(member, PLAYER_PARTY_ID)
	member.set_player_party_member(true)
	_sync_member_states()
	party_member_added.emit(member)


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
