extends "res://scripts/actors/capabilities/actor_capability.gd"

## Physical containment -- "this actor is locked inside a cell/cage right now".
##
## Holds the only generic piece of cell-custody state (the container node) so it
## no longer has to live on the HumanoidCharacter god class. Anything that is a
## WorldActor can be contained; actor subclasses keep their own visual / pose
## handling via the _on_enter_custody() / _on_exit_custody() hooks on WorldActor.
## This capability just tracks "where am I held", which in turn feeds combat
## protection (see WorldActor.is_protected_from_combat).
class_name CustodyCapability

var _container


func _init() -> void:
	super._init(&"custody")


func is_contained() -> bool:
	return _container != null and is_instance_valid(_container)


func get_container() -> Node:
	return _container if is_contained() else null


func set_container(container) -> void:
	_container = container


func teardown() -> void:
	_container = null
	super.teardown()
