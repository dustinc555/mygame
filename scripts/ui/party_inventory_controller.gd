extends Node

class_name PartyInventoryController

const INVENTORY_WINDOW_SCENE = preload("res://scenes/ui/inventory_window.tscn")

@export var inventory_toggle_key := KEY_I

var open_inventory_windows: Dictionary = {}
var root_scene: Node
var party_manager: PartyManager
var inventory_window_layer: Control
var floating_notice
var _initialized := false


func initialize(target_root: Node) -> void:
	root_scene = target_root
	if is_inside_tree():
		_do_initialize()


func _ready() -> void:
	if root_scene == null:
		var parent_node := get_parent()
		if parent_node != null and parent_node.get_parent() != null:
			root_scene = parent_node.get_parent()
	_do_initialize()


func _do_initialize() -> void:
	if _initialized or root_scene == null:
		return
	party_manager = root_scene.get_node("PartyManager")
	inventory_window_layer = root_scene.get_node("CanvasLayer/InventoryWindowLayer")
	floating_notice = root_scene.get_node_or_null("CanvasLayer/FloatingNotice")
	_initialized = true


func _unhandled_input(event: InputEvent) -> void:
	if not _initialized:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == inventory_toggle_key:
		open_selected_inventory()


func open_selected_inventory() -> void:
	if party_manager.selected_members.is_empty():
		return
	open_inventory_for_owner(party_manager.selected_members[0])


func open_inventory_for_member(member: PartyMember) -> void:
	open_inventory_for_owner(member)


func open_inventory_for_owner(inventory_owner) -> void:
	if inventory_owner == null:
		return
	var key: int = inventory_owner.get_instance_id()
	if open_inventory_windows.has(key):
		var existing = open_inventory_windows[key]
		existing.visible = true
		existing.grab_click_focus()
		return

	var window = INVENTORY_WINDOW_SCENE.instantiate()
	open_inventory_windows[key] = window
	inventory_window_layer.add_child(window)
	window.position = Vector2(36 + open_inventory_windows.size() * 24, 160 + open_inventory_windows.size() * 18)
	window.setup(inventory_owner)
	window.close_requested.connect(_on_inventory_window_close_requested)
	window.notice_requested.connect(_show_floating_notice)
	window.transfer_requested.connect(_on_inventory_transfer_requested)
	window.quick_transfer_requested.connect(_on_inventory_quick_transfer_requested)


func _on_inventory_window_close_requested(inventory_owner) -> void:
	if inventory_owner == null:
		return
	var key: int = inventory_owner.get_instance_id()
	if not open_inventory_windows.has(key):
		return
	var window = open_inventory_windows[key]
	open_inventory_windows.erase(key)
	window.queue_free()


func _on_inventory_transfer_requested(source_owner, target_owner, entry, target_cell: Vector2i) -> void:
	if source_owner == null or target_owner == null or entry == null:
		return
	if source_owner == target_owner:
		source_owner.inventory.move_entry(entry, target_cell)
		return
	var target_window = open_inventory_windows.get(target_owner.get_instance_id())
	if _owners_too_far(source_owner, target_owner):
		_show_floating_notice("Too far away")
		return

	if source_owner.inventory.move_entry_to_inventory(entry, target_owner.inventory, target_cell):
		if target_window != null:
			target_window.clear_warning()


func _on_inventory_quick_transfer_requested(source_owner, entry) -> void:
	if source_owner == null or entry == null:
		return
	var target_window = _first_other_inventory_window(source_owner)
	if target_window == null:
		return
	var target_owner = target_window.inventory_owner
	if target_owner == null:
		return
	if _owners_too_far(source_owner, target_owner):
		_show_floating_notice("Too far away")
		return
	var target_cell: Vector2i = target_owner.inventory.find_first_space(entry.definition)
	if target_cell == Vector2i(-1, -1):
		return
	source_owner.inventory.move_entry_to_inventory(entry, target_owner.inventory, target_cell)


func _first_other_inventory_window(source_owner):
	for key in open_inventory_windows.keys():
		var window = open_inventory_windows[key]
		if window.inventory_owner != source_owner:
			return window
	return null


func _show_floating_notice(message: String) -> void:
	if floating_notice != null and floating_notice.has_method("show_message"):
		floating_notice.show_message(message)


func _owners_too_far(source_owner, target_owner) -> bool:
	if source_owner == null or target_owner == null:
		return false
	if source_owner.has_method("get_inventory_world_position") and target_owner.has_method("get_inventory_world_position"):
		return source_owner.get_inventory_world_position().distance_to(target_owner.get_inventory_world_position()) > 5.0
	return false
