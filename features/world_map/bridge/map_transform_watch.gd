extends Node3D

## Internal, ownerless listener. Inherits ancestor transforms; never polls.
signal moved

func _ready() -> void:
	set_notify_transform(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_inside_tree():
		moved.emit()
