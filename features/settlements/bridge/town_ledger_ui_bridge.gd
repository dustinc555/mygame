extends Node

class_name TownLedgerUiBridge

const SERVICE_ID := &"town_ledger_ui"
const WINDOW_SCENE := preload("res://features/settlements/projection/town_ledger_window.tscn")

var _read: Node
var _ledger: Node
var _hud_layer: CanvasLayer
var _windows: Dictionary = {}


func initialize(context: BootstrapContext) -> void:
	_read = context.require(&"item_read")
	_ledger = context.require(&"town_ledger")
	_hud_layer = context.hud_layer
	_read.read_open_requested.connect(_open_report)
	_read.read_notice_requested.connect(_show_notice)
	_ledger.report_updated.connect(_on_report_updated)


func _open_report(stack_id: String, _definition: ItemDefinition, report: Dictionary) -> void:
	var existing := _windows.get(stack_id) as TownLedgerWindow
	if existing != null and is_instance_valid(existing):
		existing.set_report(report)
		existing.move_to_front()
		return
	var window := WINDOW_SCENE.instantiate() as TownLedgerWindow
	var layer := _hud_layer.get_node_or_null("InventoryWindowLayer") if _hud_layer != null else null
	if layer == null:
		layer = _hud_layer
	if layer == null:
		return
	layer.add_child(window)
	window.setup(stack_id, report)
	window.close_requested.connect(_close_report)
	_windows[stack_id] = window


func _close_report(stack_id: String) -> void:
	var window := _windows.get(stack_id) as TownLedgerWindow
	_windows.erase(stack_id)
	if window != null and is_instance_valid(window):
		window.queue_free()


func _on_report_updated(stack_id: String, report: Dictionary) -> void:
	var window := _windows.get(stack_id) as TownLedgerWindow
	if window != null and is_instance_valid(window):
		window.set_report(report)


func _show_notice(message: String) -> void:
	var notice := _hud_layer.get_node_or_null("FloatingNotice") if _hud_layer != null else null
	if notice != null and notice.has_method("show_message"):
		notice.call("show_message", message)
