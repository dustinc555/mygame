extends Node

class_name PartyManager

signal selection_changed
signal follow_changed
signal party_member_added(member)

var party_members: Array[WorldActor] = []
var selected_members: Array[WorldActor] = []
var followed_member: WorldActor


func _ready() -> void:
	add_to_group("party_manager")


func set_party_members(members: Array) -> void:
	party_members.clear()
	for member in members:
		if member is WorldActor:
			party_members.append(member)
	_sync_member_states()


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
	party_members.append(member)
	member.set_player_party_member(true)
	_sync_member_states()
	party_member_added.emit(member)


func unregister_party_member(member: WorldActor) -> void:
	if member == null or not party_members.has(member):
		return
	party_members.erase(member)
	selected_members.erase(member)
	if followed_member == member:
		followed_member = null
		follow_changed.emit()
	member.set_player_party_member(false)
	_sync_member_states()
	selection_changed.emit()


func _sync_member_states() -> void:
	for member in party_members:
		member.set_selected(selected_members.has(member))
		member.set_focused(member == followed_member)
