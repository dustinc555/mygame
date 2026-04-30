extends Node

class_name PartyManager

signal selection_changed
signal follow_changed
signal party_member_added(member)

var party_members: Array[HumanoidCharacter] = []
var selected_members: Array[HumanoidCharacter] = []
var followed_member: HumanoidCharacter


func set_party_members(members: Array[HumanoidCharacter]) -> void:
	party_members = members.duplicate()
	_sync_member_states()


func clear_selection() -> void:
	selected_members.clear()
	_sync_member_states()
	selection_changed.emit()


func select_only(member: HumanoidCharacter) -> void:
	selected_members.clear()
	selected_members.append(member)
	_sync_member_states()
	selection_changed.emit()


func add_selection(member: HumanoidCharacter) -> void:
	if selected_members.has(member):
		return
	selected_members.append(member)
	_sync_member_states()
	selection_changed.emit()


func set_selection(members: Array[HumanoidCharacter]) -> void:
	selected_members.clear()
	for member in members:
		if not selected_members.has(member):
			selected_members.append(member)
	_sync_member_states()
	selection_changed.emit()


func set_followed_member(member: HumanoidCharacter) -> void:
	followed_member = member
	_sync_member_states()
	follow_changed.emit()


func clear_followed_member() -> void:
	if followed_member == null:
		return
	followed_member = null
	_sync_member_states()
	follow_changed.emit()


func register_party_member(member: HumanoidCharacter) -> void:
	if member == null or party_members.has(member):
		return
	party_members.append(member)
	member.set_player_party_member(true)
	_sync_member_states()
	party_member_added.emit(member)


func _sync_member_states() -> void:
	for member in party_members:
		member.set_selected(selected_members.has(member))
		member.set_focused(member == followed_member)
