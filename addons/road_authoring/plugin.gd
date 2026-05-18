@tool
extends EditorPlugin

# Dustin's road authoring editor plugin for road waypoint workflows.

const ROAD_AUTHORING_INSPECTOR = preload("res://addons/road_authoring/road_authoring_inspector.gd")

var _inspector_plugin
var _connection_source: Node


func _enter_tree() -> void:
	_inspector_plugin = ROAD_AUTHORING_INSPECTOR.new(self)
	add_inspector_plugin(_inspector_plugin)


func _exit_tree() -> void:
	if _inspector_plugin != null:
		remove_inspector_plugin(_inspector_plugin)
		_inspector_plugin = null
	_connection_source = null


func set_connection_source(waypoint: Node) -> void:
	_connection_source = waypoint


func get_connection_source() -> Node:
	if _connection_source == null or not is_instance_valid(_connection_source):
		_connection_source = null
	return _connection_source


func select_node(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var selection := get_editor_interface().get_selection()
	selection.clear()
	selection.add_node(node)
	get_editor_interface().edit_node(node)
