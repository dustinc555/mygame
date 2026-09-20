extends Node

## Authored-content smoke: durable vase ingestion and exact theft refusal.
## Arrest consequences belong to the controlled law/jail cases.
var _world: Node
var _failures: Array[String] = []
var _checks := 0
const FIXTURE = preload("res://tests/validation/helpers/combat_fixture.gd")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_world = (load("res://scenes/test_levels/jail_law_demo.tscn") as PackedScene).instantiate()
	var vase := _world.get_node_or_null("JailDemoTown/OwnedVase") as WorldItem
	_expect(vase != null, "Demo must author its owned vase")
	add_child(_world)
	var stack_id := vase.stack_id if is_instance_valid(vase) else ""
	if not await FIXTURE.wait_world_ready(get_tree()):
		_expect(false, "Authored demo must finish actual bootstrap/navigation startup")
		await _finish()
		return
	var mira := _world.get_node_or_null("PartyMembers/Mira") as WorldActor
	var lifecycle := BootstrapContext.service(ItemLifecycleController.SERVICE_ID) as ItemLifecycleController
	var law := BootstrapContext.service(LawOrderController.SERVICE_ID) as LawOrderController
	_expect(mira != null and lifecycle != null and law != null, "The real demo must bootstrap actor, lifecycle and law")
	_expect(is_instance_valid(vase), "Authored vase must survive lifecycle reconciliation, not disappear as an orphan")
	if mira == null or lifecycle == null or law == null or not is_instance_valid(vase):
		await _finish()
		return
	var record := lifecycle.get_stack_record(stack_id)
	_expect(not stack_id.is_empty() and not record.is_empty(), "Authored vase must have durable GECS inventory truth")
	_expect(record.get("location_kind", "") in ["world_loose", "world_placed"], "Authored vase must be in a world location")
	var inventory_before := FIXTURE.inventory_snapshot(mira.inventory)
	mira.global_position = vase.global_position + Vector3(0.8, 0.2, 0.0)
	var world_before := lifecycle.get_stack_record(stack_id)
	_expect(not vase.try_pickup(mira), "Caught theft must be refused through the public pickup path")
	_expect(FIXTURE.inventory_snapshot(mira.inventory) == inventory_before, "Refused theft must not mutate any inventory entry or stack allocator state")
	_expect(is_instance_valid(vase), "Refused theft must retain the authored world projection")
	_expect(lifecycle.get_stack_record(stack_id) == world_before, "Refused theft must preserve the exact durable world stack without ownership or metadata mutation")
	var warrant := law.get_warrant_record(mira, "Farmers")
	_expect(not warrant.is_empty(), "Mira's Farmers warrant must exist; another actor's warrant is not sufficient")
	await _finish()

func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)

func _finish() -> void:
	await FIXTURE.release_world(_world, get_tree())
	for failure in _failures:
		push_error(failure)
	print("JAIL_DEMO_THEFT_%s checks=%d" % ["OK" if _failures.is_empty() else "FAILED", _checks])
	get_tree().quit(0 if _failures.is_empty() else 1)
