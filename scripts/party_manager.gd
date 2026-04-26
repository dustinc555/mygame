extends Node

class_name PartyManager

signal selection_changed
signal follow_changed

var party_members: Array[PartyMember] = []
var selected_members: Array[PartyMember] = []
var followed_member: PartyMember


func set_party_members(members: Array[PartyMember]) -> void:
	party_members = members.duplicate()
	_sync_member_states()


func clear_selection() -> void:
	selected_members.clear()
	_sync_member_states()
	selection_changed.emit()


func select_only(member: PartyMember) -> void:
	selected_members.clear()
	selected_members.append(member)
	_sync_member_states()
	selection_changed.emit()


func add_selection(member: PartyMember) -> void:
	if selected_members.has(member):
		return
	selected_members.append(member)
	_sync_member_states()
	selection_changed.emit()


func set_selection(members: Array[PartyMember]) -> void:
	selected_members.clear()
	for member in members:
		if not selected_members.has(member):
			selected_members.append(member)
	_sync_member_states()
	selection_changed.emit()


func set_followed_member(member: PartyMember) -> void:
	followed_member = member
	_sync_member_states()
	follow_changed.emit()


func clear_followed_member() -> void:
	if followed_member == null:
		return
	followed_member = null
	_sync_member_states()
	follow_changed.emit()


func _sync_member_states() -> void:
	for member in party_members:
		member.set_selected(selected_members.has(member))
		member.set_focused(member == followed_member)
