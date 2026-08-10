extends "res://features/world/projection/containers/world_container.gd"

class_name FarmSeedProcessor

const RULES := preload("res://features/farming/sim/seed_processing_rules.gd")
const CROP_PATHS := {
	"tomato": "res://features/farming/resources/crops/tomato.tres",
	"french_beans": "res://features/farming/resources/crops/french_beans.tres",
	"bell_pepper": "res://features/farming/resources/crops/bell_pepper.tres",
	"eggplant": "res://features/farming/resources/crops/eggplant.tres",
	"chili_pepper": "res://features/farming/resources/crops/chili_pepper.tres",
	"wheat": "res://features/farming/resources/crops/wheat.tres",
}

@export_range(1, 20, 1) var seeds_per_produce := 4
@export_range(0.1, 30.0, 0.1) var processing_seconds := 4.0


func _ready() -> void:
	container_kind = "seed_processing"
	super._ready()
	add_to_group("farm_seed_processor")


func get_world_context_actions(_actor: Node = null) -> Array:
	if not can_actor_access(_actor):
		return [{"key": "seed_processor_locked", "label": "Locked" if is_locked else "Private Seed Processor"}]
	var actions: Array = []
	for crop_id in CROP_PATHS:
		var crop = load(CROP_PATHS[crop_id])
		if crop != null and _inventory_count(crop.produce_item) > 0:
			actions.append({"key": "process_seeds:%s" % crop_id, "label": "Process %s Seeds" % crop.display_name})
	if actions.is_empty():
		actions.append({"key": "seed_processor_empty", "label": "No Produce to Process"})
	return actions


func perform_world_context_action(action_key: String, actors: Array = []) -> String:
	if not action_key.begins_with("process_seeds:"):
		return "Add harvested produce to process seeds"
	var context := BootstrapContext.active
	var work = context.get_optional(&"farm_work") if context != null else null
	if work == null:
		return "Farm workers unavailable"
	return work.assign_seed_processing(self, action_key.trim_prefix("process_seeds:"), actors)


func can_actor_access(actor: Node) -> bool:
	if actor == null or is_locked:
		return false
	var owner := get_owner_faction_name()
	if owner.is_empty():
		return true
	var actor_faction := str(actor.get("faction_name"))
	if actor_faction.is_empty():
		actor_faction = str(actor.get("faction_id"))
	return actor_faction == owner


func can_process_crop(crop_id: String, actor: Node = null) -> bool:
	if actor != null and not can_actor_access(actor):
		return false
	var crop = _crop(crop_id)
	return crop != null and inventory != null \
			and inventory.has_method("can_exchange_item_counts") \
			and inventory.can_exchange_item_counts(crop.produce_item, 1, crop.seed_item, seeds_per_produce)


func complete_processing(crop_id: String, actor: Node = null) -> Dictionary:
	var crop = _crop(crop_id)
	if crop == null or inventory == null:
		return {"completed": false, "message": "Unknown crop"}
	if actor != null and not can_actor_access(actor):
		return {"completed": false, "message": "Seed processor access denied"}
	if _inventory_count(crop.produce_item) <= 0:
		return {"completed": false, "message": "No %s" % crop.produce_item.display_name}
	if not inventory.has_method("exchange_item_counts"):
		return {"completed": false, "message": "Seed processor inventory unavailable"}
	if not inventory.exchange_item_counts(crop.produce_item, 1, crop.seed_item, seeds_per_produce):
		return {"completed": false, "message": "Seed storage is full"}
	return {"completed": true, "message": "Processed %d %s" % [seeds_per_produce, crop.seed_item.display_name], "seed_item": crop.seed_item, "amount": seeds_per_produce}


func _crop(crop_id: String):
	var path := str(CROP_PATHS.get(crop_id, ""))
	return load(path) if not path.is_empty() else null


func _inventory_count(definition) -> int:
	if inventory == null or definition == null:
		return 0
	var count := 0
	for entry in inventory.entries:
		if entry != null and entry.definition == definition:
			count += int(entry.count)
	return count
