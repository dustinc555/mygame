extends SceneTree

const CONTROLLER_PATH := "res://features/world/sim/resource_deposit_controller.gd"
const DEFINITION = preload("res://features/world/resources/resource_deposit_definition.gd")
var COPPER_FIXTURE_PATH := "user://resource_deposit_copper_fixture_%d.tres" % OS.get_process_id()
var SAVE_PATH := "user://resource_deposit_validation_%d.tres" % OS.get_process_id()
var failures: Array[String] = []
var checks := 0
var scene: Node
var context: BootstrapContext
var gecs
var clock
var deposits
var finished_phases := 0
var copper_test_definition: Resource

class OwnershipBoundary:
	extends Node
	var allowed := false
	var calls := 0
	func request_take_item(_actor, _node) -> bool:
		calls += 1
		return allowed
	func get_take_item_metadata(_actor, _node) -> Dictionary:
		return {"stolen_from_faction": "Foreign"}

class DepositProjection:
	extends Node
	var resource_node_id := ""
	var deposit_definition: Resource
	var state: Dictionary = {}
	func deliver_deposit_attempt(_actor: Node, _inventory, _metadata: Dictionary) -> Dictionary:
		return {"success": true}

	func apply_deposit_state(value: Dictionary) -> void:
		state = value

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not ResourceLoader.exists(CONTROLLER_PATH):
		_check(false, "Production deposit controller missing")
		_finish()
		return
	# Production classes, controlled test tuning: balance edits must not break
	# persistence/transaction tests or change how much work their fixtures need.
	var fixture: Resource = load("res://features/world/resources/resource_deposits/copper.tres").duplicate()
	fixture.set("min_stock", 40)
	fixture.set("max_stock", 40)
	fixture.set("refill_enabled", true)
	fixture.set("refill_min_weeks", 1.0)
	fixture.set("refill_max_weeks", 2.0)
	if ResourceSaver.save(fixture, COPPER_FIXTURE_PATH) != OK:
		_check(false, "Isolated copper definition saves")
		_finish()
		return
	copper_test_definition = ResourceLoader.load(COPPER_FIXTURE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	if copper_test_definition == null:
		_check(false, "Isolated copper definition reloads")
		_finish()
		return
	scene = Node.new()
	root.add_child(scene)
	context = BootstrapContext.new(scene)
	gecs = load("res://features/core/gecs_world_controller.gd").new()
	scene.add_child(gecs)
	context.register(&"gecs_world", gecs)
	gecs.initialize(context)
	clock = load("res://features/core/world_time_controller.gd").new()
	scene.add_child(clock)
	context.register(&"world_time", clock)
	clock.initialize(context)
	clock.set_process(false)
	deposits = load(CONTROLLER_PATH).new()
	scene.add_child(deposits)
	context.register(&"resource_deposits", deposits)
	deposits.initialize(context)
	await process_frame
	deposits.set_process(false)
	_test_seed_bind()
	_test_depletion_refill()
	await _test_load_clock_order()
	await _test_production_transactions()
	_test_retired_demo_reset()
	_test_bounded_mass_due()
	_check(finished_phases == 1, "Production transaction phase reached its completion gate")
	_finish()

func _definition():
	var definition = DEFINITION.new()
	definition.deposit_type_id = "test"
	definition.min_stock = 2
	definition.max_stock = 2
	definition.refill_min_weeks = 1.0
	definition.refill_max_weeks = 1.0
	return definition

func _projection(id: String, definition: Resource):
	var node := DepositProjection.new()
	node.resource_node_id = id
	node.deposit_definition = definition
	scene.add_child(node)
	return node

func _test_seed_bind() -> void:
	var definition = _definition()
	var node = _projection("test.seed", definition)
	_check(deposits.bind_deposit(node), "Authored deposit binds")
	_check(node.state.get("stock", -1) == 2, "Stock seeded from shared definition")
	_check(gecs.get_resource_deposit_state("test.seed").get("stock", -1) == 2, "Seed writes through to GECS")
	definition.min_stock = 9
	definition.max_stock = 9
	_check(deposits.bind_deposit(node) and node.state.stock == 2, "Rebind/config edits never reseed saved stock")
	var duplicate = _projection("test.seed", definition)
	_check(not deposits.bind_deposit(duplicate), "Duplicate live ID is rejected")
	var blank = _projection("", definition)
	_check(not deposits.bind_deposit(blank), "Blank ID cannot alias durable stock")
	node.free()
	_check(deposits.bind_deposit(duplicate) and duplicate.state.stock == 2, "Freed projection rebinds without reseeding")
	_check(gecs.get_resource_deposit_states().size() == 1, "One independent component per identity")
	deposits.remove_deposit("test.seed")
	_check(gecs.get_resource_deposit_state("test.seed").is_empty(), "Explicit removal clears GECS index")

func _test_depletion_refill() -> void:
	if not deposits.has_method("complete_attempt"):
		_check(false, "Authoritative stock completion missing")
		return
	var definition = _definition()
	var node = _projection("test.cycle", definition)
	var actor := Node.new()
	scene.add_child(actor)
	_check(deposits.bind_deposit(node), "Lifecycle deposit binds")
	_check(deposits.complete_attempt(node, actor).get("success", false), "First extraction commits")
	_check(node.state.stock == 1 and node.state.refill_at_minute < 0, "Positive stock has no due event")
	_check(deposits.complete_attempt(node, actor).get("success", false), "Final extraction commits")
	var deadline: float = node.state.refill_at_minute
	_check(is_equal_approx(deadline, clock.total_world_minutes + DEFINITION.minutes_per_week()), "Depletion saves one absolute world-week deadline")
	_check(deposits.get_queue_size() == 1, "Only depleted record is queued")
	var revision: int = node.state.revision
	_check(not deposits.complete_attempt(node, actor).get("success", false), "Second worker cannot extract final stock twice")
	_check(node.state.revision == revision and node.state.refill_at_minute == deadline, "Failed extraction never rerolls deadline")
	definition.refill_min_weeks = 3.0
	definition.refill_max_weeks = 3.0
	definition.min_stock = 4
	definition.max_stock = 4
	definition.refill_enabled = false
	deposits.bind_deposit(node)
	_check(node.state.refill_at_minute == deadline, "All tuning edits leave scheduled event intact")
	clock.total_world_minutes = deadline - 0.01
	deposits.drain_due()
	_check(node.state.stock == 0, "No early refill")
	clock.total_world_minutes = deadline
	deposits.drain_due()
	_check(node.state.stock == 4 and node.state.refill_at_minute < 0, "Refill updates same live projection using current stock tuning")
	_check(deposits.get_queue_size() == 0, "Refilled record leaves due index")
	for index in range(4):
		deposits.complete_attempt(node, actor)
	_check(node.state.stock == 0 and node.state.refill_at_minute < 0, "Disabled refill applies to future depletion only")
	deposits.remove_deposit("test.cycle")

func _test_load_clock_order() -> void:
	var node = _projection("test.saved", copper_test_definition)
	var actor := Node.new()
	scene.add_child(actor)
	clock.total_world_minutes = 100.0
	deposits.bind_deposit(node)
	while int(node.state.stock) > 0:
		deposits.complete_attempt(node, actor)
	var saved: Dictionary = node.state.duplicate(true)
	var stocked = _projection("test.stocked", node.deposit_definition)
	deposits.bind_deposit(stocked)
	deposits.complete_attempt(stocked, actor)
	var path := SAVE_PATH
	_check(gecs.save_gecs_world(path), "GECS deposit snapshot saves")
	clock.total_world_minutes = 1000000.0
	deposits.drain_due()
	_check(node.state.stock == 40, "Later session refilled before loading old save")
	_check(gecs.load_gecs_world(path), "GECS deposit snapshot loads")
	_check(deposits.get_queue_size() == 0, "Reindex synchronously clears stale queue")
	deposits.drain_due()
	_check(_same_state(gecs.get_resource_deposit_state("test.saved"), saved), "Pre-hydration drain cannot advance older save")
	clock.total_world_minutes = 100.0
	await process_frame
	deposits.set_process(false)
	_check(_same_state(node.state, saved) and stocked.state.stock == 39, "Deferred load restores stock/deadline/revision in place")
	_check(deposits.get_queue_size() == 1, "Loaded depletion queues exactly once")
	# Legacy saves had no deposit components: live authoring seeds each missing record once.
	gecs.remove_resource_deposit_state("test.stocked")
	gecs.world_reindexed.emit()
	await process_frame
	deposits.set_process(false)
	_check(stocked.state.stock == 40, "Legacy missing stock seeds once after clock hydration")
	deposits.complete_attempt(stocked, actor)
	gecs.world_reindexed.emit()
	await process_frame
	deposits.set_process(false)
	_check(stocked.state.stock == 39, "Further reconciliation never reseeds migrated record")
	# Destroy all projections and controller caches, then load saved stock off-screen.
	node.free()
	stocked.free()
	deposits.teardown()
	deposits.initialize(context)
	_check(gecs.load_gecs_world(path), "Cold unbound snapshot loads")
	clock.total_world_minutes = 100.0
	await process_frame
	deposits.set_process(false)
	_check(deposits.get_queue_size() == 1, "Saved definition path restores unbound due event")
	clock.total_world_minutes = float(gecs.get_resource_deposit_state("test.saved").refill_at_minute)
	deposits.drain_due()
	var refill_range: Vector2i = copper_test_definition.get_stock_range()
	var refilled_stock := int(gecs.get_resource_deposit_state("test.saved").stock)
	_check(refilled_stock >= refill_range.x and refilled_stock <= refill_range.y, "Unloaded deposit refills from the authored range without scene creation")
	deposits.remove_deposit("test.saved")
	deposits.remove_deposit("test.stocked")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _test_production_transactions() -> void:
	var copper = load("res://features/world/bridge/resource_nodes/copper_node.tscn").instantiate()
	if copper.get("deposit_definition") == null:
		_check(false, "Production scenes must consume shared deposit definitions")
		copper.free()
		return
	copper.deposit_definition = copper_test_definition
	BootstrapContext.active = context
	copper.resource_node_id = "test.copper"
	copper.slot_distance = 0.0
	scene.add_child(copper)
	var actor = load("res://features/actors/projection/humanoid/humanoid_character.gd").new()
	actor.fatigue_enabled = false
	scene.add_child(actor)
	actor.set_physics_process(false)
	actor.set_process(false)
	var hud = load("res://features/ui/projection/game_hud.tscn").instantiate()
	scene.add_child(hud)
	var details = load("res://features/ui/bridge/humanoid_details_controller.gd").new()
	scene.add_child(details)
	details.initialize(BootstrapContext.new(scene, hud))
	details.inspect_target(copper)
	_check(details.info_values[3].text == "%d ore remaining" % copper.get_stock(), "Live Details shows the actual positive copper stock")
	_check(details.state_label.text == "VEIN" and not details.action_buttons[0].disabled, "Stocked copper advertises an available mining action")
	var ore = copper.item_definition
	var pickaxe = load("res://features/inventory/resources/items/rusted_pickaxe.tres")
	actor.inventory.add_item(pickaxe)
	actor.assign_mining_resource(copper, false)
	actor.stop_movement()
	_check(not copper.deliver_deposit_attempt(null, actor.inventory, {}).get("success", false), "Internal delivery cannot bypass actor-aware transaction")
	_check(not copper.deliver_deposit_attempt(actor, actor.inventory, {}).get("success", false), "Internal delivery cannot bypass stock transaction")
	var before: int = deposits.get_deposit_state("test.copper").stock
	actor.get_interaction().process_mining(100.0)
	_check(actor.inventory.count_item(ore) == 1 and deposits.get_deposit_state("test.copper").stock == before - 1, "Real timed mining produces one ore and decrements GECS stock")
	# Retry at completed work with full inventory must preserve both stock and work.
	actor.inventory = InventoryData.new(1, 1, 0.0, false)
	var blocker := ItemDefinition.new()
	blocker.grid_size = Vector2i.ONE
	blocker.max_stack = 1
	actor.inventory.add_item(blocker)
	actor.get_interaction().process_mining(100.0)
	_check(deposits.get_deposit_state("test.copper").stock == before - 1 and actor.get_interaction().get_stored_mining_progress(copper) == 1.0, "Full inventory preserves copper stock and finished progress")
	actor.inventory = InventoryData.new(8, 8, 0.0, false)
	# Put the real source on its final stock through transactions, not forged state.
	for _index in range(int(deposits.get_deposit_state("test.copper").stock) - 1):
		actor.inventory = InventoryData.new(8, 8, 0.0, false)
		_check(copper.complete_mining_attempt(actor, actor.inventory).get("success", false), "Preparation extraction succeeds")
	actor.inventory = InventoryData.new(8, 8, 0.0, false)
	var nested_results: Array = []
	var stock_seen_by_inventory: Array[int] = []
	actor.inventory.changed.connect(func():
		stock_seen_by_inventory.append(int(deposits.get_deposit_state("test.copper").stock))
		nested_results.append(copper.complete_mining_attempt(actor, actor.inventory)))
	actor.get_interaction().process_mining(0.0)
	_check(deposits.get_deposit_state("test.copper").stock == 0 and actor.inventory.count_item(ore) == 1, "Final stock is atomic through inventory signal reentry and completed-progress branch")
	_check(not nested_results.is_empty() and not nested_results[0].get("success", false), "Concurrent/reentrant worker is rejected")
	_check(stock_seen_by_inventory == [0], "Inventory notifications see committed durable stock, never a half-transaction")
	_check(not copper.complete_mining_attempt(null, actor.inventory).get("success", false), "Actorless extraction is forbidden")
	await process_frame
	_check(details.info_values[3].text == "Depleted", "Already-open Details updates when copper runs out")
	_check(details.state_label.text == "DEPLETED", "Copper badge agrees with depleted stock")
	_check(details.action_buttons[0].disabled, "Details cannot offer mining from an empty vein")
	actor.get_interaction().process_mining(0.1)
	_check(not actor.get_interaction().has_mining_assignment(), "Depletion stops live mining without automatic restart")
	var provider = load("res://features/settlements/bridge/job_provider.gd").new()
	scene.add_child(provider)
	var job = load("res://features/settlements/resources/jobs/job_definition.gd").new()
	job.resource_paths.append(provider.get_path_to(copper))
	var slot := {"slot_index": 0}
	provider._active_slots[0] = [{"claimed_resource": copper}]
	_check(provider._resolve_best_resource(0, job, slot, actor) == null, "JobProvider claimed-resource fallback excludes depleted source")
	provider.free()
	var deadline: float = deposits.get_deposit_state("test.copper").refill_at_minute
	var instance_id: int = copper.get_instance_id()
	clock.total_world_minutes = deadline
	deposits.drain_due()
	_check(copper.get_instance_id() == instance_id and not copper.is_depleted() and not actor.get_interaction().has_mining_assignment(), "Refill keeps scene and leaves worker stopped")
	await process_frame
	_check(details.info_values[3].text == "%d ore remaining" % copper.get_stock(), "Already-open Details updates after the scheduled refill")
	_check(details.state_label.text == "VEIN" and not details.action_buttons[0].disabled, "Refill restores the copper badge and mining action")
	details.inspect_target(null)
	details.free()
	hud.free()
	actor.inventory = InventoryData.new(8, 8, 0.0, false)
	actor.assign_mining_resource(copper, false)
	actor.stop_movement()
	actor.get_interaction().process_mining(0.1)
	copper.free()
	actor.get_interaction().process_mining(0.1)
	_check(not actor.get_interaction().has_mining_assignment(), "LOD destruction cancels timed work safely")
	copper = load("res://features/world/bridge/resource_nodes/copper_node.tscn").instantiate()
	copper.deposit_definition = copper_test_definition
	copper.resource_node_id = "test.copper"
	copper.slot_distance = 0.0
	scene.add_child(copper)
	actor.assign_mining_resource(copper, false)
	actor.stop_movement()
	actor.get_interaction().process_mining(100.0)
	_check(actor.inventory.count_item(ore) == 1, "Re-realized source reacquires real work")
	var scrap = load("res://features/world/bridge/resource_nodes/scrap_pile_node.tscn").instantiate()
	scrap.resource_node_id = "test.scrap"
	scrap.min_useful_chance = 1.0
	scrap.max_useful_chance = 1.0
	scene.add_child(scrap)
	var stock: int = deposits.get_deposit_state("test.scrap").stock
	actor.inventory = InventoryData.new(1, 1, 0.0, false)
	actor.inventory.add_item(blocker)
	var result: Dictionary = scrap.complete_scavenge_attempt(actor)
	_check(result.get("dropped", false) and deposits.get_deposit_state("test.scrap").stock == stock - 1, "Full-inventory scrap keeps established nearby-loot drop behavior")
	_check(not scrap.get_node("Label3D").visible, "Legacy idle resource labels stay hidden")
	# Ownership is mutable during work; validation must run again at completion.
	copper.owner_faction_name = "Foreign"
	var old_stock: int = deposits.get_deposit_state("test.copper").stock
	_check(not copper.complete_mining_attempt(actor, actor.inventory).get("success", false), "Missing ownership service fails closed for owned resource")
	_check(deposits.get_deposit_state("test.copper").stock == old_stock, "Denied completion preserves stock")
	var ownership := OwnershipBoundary.new()
	scene.add_child(ownership)
	deposits._ownership = ownership
	actor.inventory = InventoryData.new(8, 8, 0.0, false)
	_check(not copper.complete_mining_attempt(actor, actor.inventory).get("success", false) and ownership.calls == 1, "Completion revalidates current ownership through theft authority")
	ownership.allowed = true
	_check(copper.complete_mining_attempt(actor, actor.inventory).get("success", false), "Authorized completion applies through the same transaction")
	_check(actor.inventory.entries[0].metadata.get("stolen_from_faction", "") == "Foreign", "Gathered loot preserves theft metadata")
	actor.unequip_item_from_slot(ItemDefinition.EQUIP_SLOT_WEAPON)
	old_stock = deposits.get_deposit_state("test.copper").stock
	_check(not copper.complete_mining_attempt(actor, actor.inventory).get("success", false) and deposits.get_deposit_state("test.copper").stock == old_stock, "Tool removed before completion cannot produce ore")
	scrap.slot_distance = 0.0
	actor.assign_scavenging_resource(scrap, false)
	actor.stop_movement()
	actor.get_interaction().process_scavenging(0.1)
	stock = deposits.get_deposit_state("test.scrap").stock
	scrap.free()
	actor.get_interaction().process_scavenging(0.1)
	_check(not actor.get_interaction().has_scavenging_assignment(), "Scrap LOD destruction cancels active work safely")
	scrap = load("res://features/world/bridge/resource_nodes/scrap_pile_node.tscn").instantiate()
	scrap.resource_node_id = "test.scrap"
	scrap.slot_distance = 0.0
	scene.add_child(scrap)
	actor.assign_scavenging_resource(scrap, false)
	actor.stop_movement()
	actor.get_interaction().process_scavenging(100.0)
	_check(deposits.get_deposit_state("test.scrap").stock == stock - 1, "Re-realized scrap reacquires timed work without reseeding")
	for id in ["copper", "iron", "scrap_pile", "twisted_scrap_heap", "robot_wreck"]:
		var definition = load("res://features/world/resources/resource_deposits/" + id + ".tres")
		var placed = load(definition.scene_path).instantiate()
		placed.name = "Legacy_" + id
		scene.add_child(placed)
		_check(placed.deposit_definition == definition and placed.get_stock() > 0, "Catalog scene binds shared definition: " + id)
		_check(placed.resource_node_id.begins_with("legacy:"), "Legacy blank identity gets unique path scope")
	deposits._ownership = null
	for id in gecs.get_resource_deposit_states():
		deposits.remove_deposit(id)
	BootstrapContext.active = null
	finished_phases += 1

func _test_retired_demo_reset() -> void:
	# Exercise the real runtime button builder and action router. This test does
	# not claim to validate the demo's unrelated geometry or actor setup.
	var demo = load("res://scenes/test_levels/junkyard_scavenging_demo.gd").new()
	demo._ensure_demo_buttons()
	_check(demo.get_node_or_null("DemoButtons/ResetPilesButton") == null, "Demo does not advertise obsolete scene-owned stock reset")
	_check(demo.perform_sneak_demo_action("reset_piles") == "Unknown junkyard demo action", "Retired reset action cannot call the removed stock API")
	demo.free()

func _test_bounded_mass_due() -> void:
	# Prior implementation had no refill scheduler (zero refill work). Compare
	# today's idle drain against 2048 simultaneous expiries, including GECS writes.
	var definition = _definition()
	definition.min_stock = 1
	definition.max_stock = 1
	var actor := Node.new()
	scene.add_child(actor)
	var idle_start := Time.get_ticks_usec()
	for _index in range(100):
		deposits.drain_due()
	var idle_mean := float(Time.get_ticks_usec() - idle_start) / 100.0
	var total := 2048
	for index in range(total):
		var node = _projection("mass.%d" % index, definition)
		deposits.bind_deposit(node)
		deposits.complete_attempt(node, actor)
		node.free()
	_check(deposits.get_queue_size() == total, "Mass due index has one entry per independently depleted source")
	clock.total_world_minutes += 100000000.0
	clock.world_minutes_advanced.emit(clock.total_world_minutes)
	_check(deposits.get_queue_size() == total, "Large world skip queues work without synchronous refill storm")
	deposits.max_refills_per_frame = 1
	deposits.refill_budget_usec = 10000
	var entered: Array[bool] = [false]
	var reentrant := func(_id: String, _state: Dictionary):
		if not entered[0]:
			entered[0] = true
			deposits.drain_due()
	deposits.deposit_changed.connect(reentrant)
	deposits.drain_due()
	deposits.deposit_changed.disconnect(reentrant)
	_check(deposits.get_queue_size() == total - 1, "Notification reentry cannot bypass per-frame drain budget")
	deposits.max_refills_per_frame = 32
	deposits.refill_budget_usec = 500
	var slow_projection := func(_id: String, _state: Dictionary): OS.delay_usec(1000)
	deposits.deposit_changed.connect(slow_projection)
	var count: int = deposits.drain_due()
	deposits.deposit_changed.disconnect(slow_projection)
	_check(count <= 1, "Time budget includes subscriber/projection work")
	deposits.refill_budget_usec = 1500
	var costs: Array[int] = []
	var frames := 0
	while deposits.get_queue_size() > 0 and frames < total:
		count = deposits.drain_due()
		_check(count <= 32, "Count budget respected")
		costs.append(deposits.last_drain_usec)
		frames += 1
	_check(deposits.get_queue_size() == 0, "Bounded drains finish all mass-due work")
	var refilled := 0
	for index in range(total):
		var state: Dictionary = deposits.get_deposit_state("mass.%d" % index)
		if state.stock == 1 and state.revision == 2 and state.refill_at_minute < 0:
			refilled += 1
		deposits.remove_deposit("mass.%d" % index)
	_check(refilled == total, "Large skip refills each source exactly once, not once per elapsed interval")
	costs.sort()
	if not costs.is_empty():
		print("DEPOSIT_BUDGET: n=", total, " idle_mean_us=", idle_mean, " p95_us=", costs[int(costs.size() * 0.95)], " max_us=", costs[-1], " drain_frames=", frames)

func _same_state(a: Dictionary, b: Dictionary) -> bool:
	for key in b:
		if key == "refill_at_minute":
			if not is_equal_approx(float(a.get(key, -1.0)), float(b[key])):
				return false
		elif a.get(key) != b[key]:
			return false
	return true

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		print("FAIL: ", message)

func _finish() -> void:
	if scene != null and is_instance_valid(scene):
		if deposits != null and is_instance_valid(deposits):
			deposits.teardown()
		scene.free()
	for path in [COPPER_FIXTURE_PATH, SAVE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("RESOURCE_DEPOSITS: ", "PASS" if failures.is_empty() else "FAIL", " (", checks, " checks)")
	quit(0 if failures.is_empty() else 1)
