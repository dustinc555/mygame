extends "res://addons/gecs/ecs/component.gd"

class_name CGameItemLifecycleCommand

enum Operation {
	UPSERT_WORLD,
	SET_LOCATION,
	UPDATE_METADATA,
}

@export var command_id := ""
@export var stack_id := ""
@export var operation := Operation.SET_LOCATION
@export var record: Dictionary = {}
@export var location_kind := ""
@export var world_transform := Transform3D.IDENTITY
@export var placement_host_id := ""
@export var placement_slot_id := ""
@export var settlement_id := ""
@export var owner_actor_id := ""
@export var container_id := "world"
@export var metadata: Dictionary = {}
@export var applies_metadata := false
