extends GutTest

const HAUL = preload("res://features/inventory/bridge/haul_provider.gd")
const PLATFORM = preload("res://features/world/projection/containers/bulk_storage_platform.gd")

class Jobs extends Node:
	var active := false
	func is_actor_work_schedule_active(_actor: Node) -> bool: return active

func test_transfer_arrival_after_closing_cancels_before_inventory_mutation() -> void:
	var jobs: Jobs = autofree(Jobs.new())
	var haul = autofree(HAUL.new())
	var actor: Node = autofree(Node.new())
	var endpoint: Node = autofree(Node.new())
	haul._job_system = jobs
	haul._assignments[actor.get_instance_id()] = {"actor": weakref(actor), "stage": "load"}
	haul._on_transfer_arrival(actor, endpoint, actor.get_instance_id())
	assert_false(haul._assignments.has(actor.get_instance_id()), "Late arrival must release its work, not wait until the budgeted Home dispatch")

func test_platform_deposit_checks_schedule_even_when_called_outside_provider_arrival() -> void:
	var jobs: Jobs = autofree(Jobs.new())
	var haul = autofree(HAUL.new())
	var actor: Node = autofree(Node.new())
	var platform = autofree(PLATFORM.new())
	haul._job_system = jobs
	platform.bind_haul_provider(haul)
	platform._pending_deposits[actor.get_instance_id()] = {"automatic": true, "item_path": "", "max_amount": 1}
	var result: Dictionary = platform.resolve_pending_deposit(actor)
	assert_eq(result.get("reason", ""), "off_shift")
	assert_false(platform.has_pending_automatic_haul(actor))

func test_manual_platform_deposit_is_not_reclassified_as_employment() -> void:
	var jobs: Jobs = autofree(Jobs.new())
	var haul = autofree(HAUL.new())
	var actor: Node = autofree(Node.new())
	var platform = autofree(PLATFORM.new())
	haul._job_system = jobs
	platform.bind_haul_provider(haul)
	platform._pending_deposits[actor.get_instance_id()] = {"automatic": false, "item_path": ""}
	var result: Dictionary = platform.resolve_pending_deposit(actor)
	assert_eq(result.get("reason", ""), "")
	assert_true(bool(result.handled))
