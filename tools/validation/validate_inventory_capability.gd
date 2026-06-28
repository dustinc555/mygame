extends SceneTree

## Focused sanity check for InventoryCapability (post-migration design).
## Run: godot --headless --path . --script res://tools/validation/validate_inventory_capability.gd
##
## Capability owns the InventoryData; the actor exposes it as a computed `inventory`
## property. Changes go out as the capability's `inventory_changed` signal. GECS sync
## is typed. No actor reflection.

const BREAD = preload("res://features/inventory/resources/items/bread.tres")


func _initialize() -> void:
	_run_validation.call_deferred()


func _run_validation() -> void:
	var failures: Array[String] = []

	var actor := _make_actor()
	var capability := actor.get_inventory()
	_expect(failures, "inventory capability present", capability != null)
	if capability == null:
		_finish(failures)
		return

	# Capability built the InventoryData from authored config; actor proxies to it.
	_expect(failures, "capability owns InventoryData", capability.inventory != null)
	_expect(failures, "actor.inventory proxies to capability", actor.inventory == capability.inventory)

	# inventory_changed fires when contents change.
	var changed := {"hit": false}
	capability.inventory_changed.connect(func(): changed.hit = true)
	actor.inventory.add_item_count(BREAD, 2)
	_expect(failures, "item added", actor.inventory.count_item(BREAD) == 2)
	_expect(failures, "inventory_changed emitted on add", changed.hit)

	# Work-inventory override swaps the display target.
	_expect(failures, "not displaying work inventory initially", not capability.is_displaying_work_inventory())
	var work := InventoryData.new(4, 4, 20.0, true)
	capability.set_work_inventory(work)
	_expect(failures, "displaying work inventory after set", capability.is_displaying_work_inventory())
	_expect(failures, "display returns work inventory", actor.get_inventory_for_display() == work)
	capability.set_work_inventory(null)
	_expect(failures, "display returns own inventory after clear", actor.get_inventory_for_display() == capability.inventory)

	actor.free()
	_finish(failures)


func _make_actor() -> WorldActor:
	var actor := WorldActor.new()
	root.add_child(actor)
	actor.inventory_columns = 8
	actor.inventory_rows = 5
	actor.max_carry_weight = 40.0
	actor._create_actor_capabilities()
	for capability in actor._capabilities.values():
		(capability as ActorCapability).setup(actor)
	for capability in actor._capabilities.values():
		(capability as ActorCapability).ready()
	return actor


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("PASS: InventoryCapability sane (9 checks)")
		quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		quit(1)


func _expect(failures: Array[String], label: String, condition: bool) -> void:
	if not condition:
		failures.append(label)
