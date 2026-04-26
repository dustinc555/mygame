extends Node

class_name PartyInventoryController

const INVENTORY_WINDOW_SCENE = preload("res://scenes/ui/inventory_window.tscn")

@export var inventory_toggle_key := KEY_I

var open_inventory_windows: Dictionary = {}

@onready var party_manager: PartyManager = get_parent().get_node("PartyManager")
@onready var inventory_window_layer: Control = get_parent().get_node("CanvasLayer/InventoryWindowLayer")
@onready var floating_notice = get_parent().get_node_or_null("CanvasLayer/FloatingNotice")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == inventory_toggle_key:
		open_selected_inventory()


func open_selected_inventory() -> void:
	if party_manager.selected_members.is_empty():
		return
	open_inventory_for_member(party_manager.selected_members[0])


func open_inventory_for_member(member: PartyMember) -> void:
	if member == null:
		return
	var key := member.get_instance_id()
	if open_inventory_windows.has(key):
		var existing = open_inventory_windows[key]
		existing.visible = true
		existing.grab_click_focus()
		return

	var window = INVENTORY_WINDOW_SCENE.instantiate()
	open_inventory_windows[key] = window
	inventory_window_layer.add_child(window)
	window.position = Vector2(36 + open_inventory_windows.size() * 24, 160 + open_inventory_windows.size() * 18)
	window.setup(member)
	window.close_requested.connect(_on_inventory_window_close_requested)
	window.notice_requested.connect(_show_floating_notice)
	window.transfer_requested.connect(_on_inventory_transfer_requested)
	window.quick_transfer_requested.connect(_on_inventory_quick_transfer_requested)


func _on_inventory_window_close_requested(member: PartyMember) -> void:
	if member == null:
		return
	var key := member.get_instance_id()
	if not open_inventory_windows.has(key):
		return
	var window = open_inventory_windows[key]
	open_inventory_windows.erase(key)
	window.queue_free()


func _on_inventory_transfer_requested(source_member: PartyMember, target_member: PartyMember, entry, target_cell: Vector2i) -> void:
	if source_member == null or target_member == null or entry == null:
		return
	if source_member == target_member:
		source_member.inventory.move_entry(entry, target_cell)
		return
	var target_window = open_inventory_windows.get(target_member.get_instance_id())
	if source_member.global_position.distance_to(target_member.global_position) > 5.0:
		_show_floating_notice("Too far away")
		return

	if source_member.inventory.move_entry_to_inventory(entry, target_member.inventory, target_cell):
		if target_window != null:
			target_window.clear_warning()


func _on_inventory_quick_transfer_requested(source_member: PartyMember, entry) -> void:
	if source_member == null or entry == null:
		return
	var target_window = _first_other_inventory_window(source_member)
	if target_window == null:
		return
	var target_member: PartyMember = target_window.member
	if target_member == null:
		return
	if source_member.global_position.distance_to(target_member.global_position) > 5.0:
		_show_floating_notice("Too far away")
		return
	var target_cell: Vector2i = target_member.inventory.find_first_space(entry.definition)
	if target_cell == Vector2i(-1, -1):
		return
	source_member.inventory.move_entry_to_inventory(entry, target_member.inventory, target_cell)


func _first_other_inventory_window(source_member: PartyMember):
	for key in open_inventory_windows.keys():
		var window = open_inventory_windows[key]
		if window.member != source_member:
			return window
	return null


func _show_floating_notice(message: String) -> void:
	if floating_notice != null and floating_notice.has_method("show_message"):
		floating_notice.show_message(message)
