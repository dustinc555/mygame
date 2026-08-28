extends Resource

class_name SettlementStorageSeed

@export var container_id := ""
@export var facility_id := ""
@export var container_kind := "granary"
@export_enum("general", "seeds", "tools", "food", "materials") var container_type := "general"
@export var allowed_item_ids := PackedStringArray()
@export var contributes_to_town_stock := true
@export_range(1, 100, 1) var columns := 10
@export_range(1, 100, 1) var rows := 10
@export var max_weight := 0.0
@export var stacks: Array[Resource] = []
