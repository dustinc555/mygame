extends SceneTree

## Focused sanity check for EquipmentCapability (post-migration design).
## Run: godot --headless --path . --script res://tools/validation/validate_equipment_capability.gd
##
## Capability owns equipped_items; the actor delegates. Cross-capability reactions
## go out as `equipment_changed`. Stats reads the equipment modifier layer via its
## typed handle (covered here too). A base WorldActor exposes no slot list, which
## permits any equippable item into its own declared slot.

const HATCHET = preload("res://features/inventory/resources/items/hatchet.tres")
const BRONZE_SWORD = preload("res://features/inventory/resources/items/bronze_sword.tres")


func _initialize() -> void:
	_run_validation.call_deferred()


func _run_validation() -> void:
	var failures: Array[String] = []

	var actor := _make_actor([HATCHET])
	var equipment := actor.get_equipment()
	_expect(failures, "equipment capability present", equipment != null)
	if equipment == null:
		_finish(failures)
		return

	_expect(failures, "starting hatchet seeded to weapon slot", actor.get_equipped_item("weapon") == HATCHET)
	_expect(failures, "starting hatchet has durable stack ID", not equipment.get_equipped_stack_id("weapon").is_empty())

	# equip replaces, weight, unequip
	var replaced := actor.equip_item_to_slot(BRONZE_SWORD, "weapon")
	_expect(failures, "equip replaces previous", replaced == HATCHET)
	_expect(failures, "sword now equipped", actor.get_equipped_item("weapon") == BRONZE_SWORD)
	_expect(failures, "equipped weight matches sword", is_equal_approx(actor.get_equipped_weight(), BRONZE_SWORD.unit_weight))
	var removed := actor.unequip_item_from_slot("weapon")
	_expect(failures, "unequip returns sword", removed == BRONZE_SWORD)
	_expect(failures, "empty after unequip", actor.get_equipped_item("weapon") == null)

	# equipment_changed signal fires on equip
	var emitted := {"hit": false}
	equipment.equipment_changed.connect(func(_slots): emitted.hit = true)
	actor.equip_item_to_slot(BRONZE_SWORD, "weapon")
	_expect(failures, "equipment_changed emitted on equip", emitted.hit)

	# batch defers to a single emit
	actor.unequip_item_from_slot("weapon")
	var batch := {"n": 0}
	equipment.equipment_changed.connect(func(_slots): batch.n += 1)
	equipment.begin_equipment_update_batch()
	actor.equip_item_to_slot(HATCHET, "weapon")
	_expect(failures, "batch defers signal", batch.n == 0)
	equipment.end_equipment_update_batch()
	_expect(failures, "batch emits once on end", batch.n == 1)

	# Stats reads the equipment modifier layer (cross-capability link)
	var modifiers := equipment.get_stat_modifiers()
	_expect(failures, "stat modifiers surfaced from equipped items", modifiers.size() == HATCHET.stat_modifiers.size())

	actor.free()
	_finish(failures)


func _make_actor(starting_equipment: Array) -> WorldActor:
	var actor := WorldActor.new()
	actor.stable_id = "validation.equipment_actor"
	root.add_child(actor)
	actor.starting_equipment = starting_equipment
	actor._create_actor_capabilities()
	for capability in actor._capabilities.values():
		(capability as ActorCapability).setup(actor)
	for capability in actor._capabilities.values():
		(capability as ActorCapability).ready()
	return actor


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("PASS: EquipmentCapability sane (11 checks)")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		quit(1)


func _expect(failures: Array[String], label: String, condition: bool) -> void:
	if not condition:
		failures.append(label)
