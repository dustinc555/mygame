extends "res://addons/gecs/ecs/component.gd"

class_name CGameItemStack

@export var stack_id := ""
@export var container_id := ""
@export var owner_actor_id := ""
## Explicit WorldItem stamp, separate from holder identity and stolen metadata.
## Empty means no stamp; facility inheritance remains a projection contract.
@export var owner_faction_name := ""
@export var item_definition_path := ""
@export var count := 1
@export var grid_position := Vector2i.ZERO
@export var contained_item_counts: Dictionary = {}
@export var metadata: Dictionary = {}
@export_enum("inventory", "world_loose", "world_placed", "tabletop_slot") var location_kind := "inventory"
@export var world_transform := Transform3D.IDENTITY
@export var placement_host_id := ""
@export var placement_slot_id := ""
@export var location_settlement_id := ""
