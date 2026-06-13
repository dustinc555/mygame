extends RefCounted

class_name ActorCapability

var _capability_id: StringName
var enabled := true
var process_enabled := false
var physics_process_enabled := false
var actor: Node


func _init(id: StringName = &"") -> void:
	_capability_id = id


func setup(target_actor: Node) -> void:
	actor = target_actor


func ready() -> void:
	pass


func process(_delta: float) -> void:
	pass


func physics_process(_delta: float) -> void:
	pass


func teardown() -> void:
	actor = null


func get_capability_id() -> StringName:
	return _capability_id
