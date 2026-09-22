extends "res://tests/validation/test_case.gd"
## Real shop prefab, bootstrap, navigation, Jobs and GECS, not a replacement
## merchant implementation. Supply checks run through world-time boundaries.
const SHOP = preload("res://features/settlements/bridge/settlement_shop.tscn")
const WORLD = preload("res://tests/validation/fixtures/bar_authoring/world.tscn")
const TOWN_TOOLS = preload("res://addons/world_authoring/town_tools.gd")
const SEEDS = preload("res://features/inventory/resources/items/eggplant_seeds.tres")
const SWORD = preload("res://features/inventory/resources/items/golden_sword.tres")
const SILVER = preload("res://features/inventory/resources/items/silver.tres")
var _world: Node
var _shop: SettlementShop
var _failures: Array[String] = []
var _checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_world = WORLD.instantiate()
	_shop = SHOP.instantiate()
	_shop.stock_overrides = {SWORD.resource_path: {"quantity": 1, "replenishes": false}}
	var town := _world.get_node("Town")
	TOWN_TOOLS._apply_facility_identity(_shop, town, load("res://features/settlements/resources/facilities/shop.tres"))
	town.add_child(_shop)
	root.add_child(_world)
	current_scene = _world
	if not await _until(func():
		var nav := BootstrapContext.service(WorldNavigationController.SERVICE_ID)
		var clock := BootstrapContext.service(WorldTimeController.SERVICE_ID)
		return nav != null and clock != null and not nav.is_initial_navigation_pending() and nav.is_idle() and not clock.is_world_paused() and is_instance_valid(_shop._merchant), 45.0):
		_check(false, "shop generates its persistent merchant after real world readiness")
		await _finish()
		return
	var merchant := _shop._merchant
	var role := merchant.get_node_or_null("MerchantRole") as MerchantRole
	_check(role != null, "generated character has the existing MerchantRole")
	if role == null:
		await _finish()
		return
	var clock := BootstrapContext.service(WorldTimeController.SERVICE_ID) as WorldTimeController
	# Freeze clock progression, not physics/Jobs, while checking real movement.
	clock.set_process(false)
	var population := BootstrapContext.service(PopulationController.SERVICE_ID) as PopulationController
	var gecs := BootstrapContext.service(GecsWorldController.SERVICE_ID) as GecsWorldController
	var actor_id := merchant.stable_id
	var simulation := BootstrapContext.service(WorldSimulationController.SERVICE_ID) as WorldSimulationController
	var record := population.get_actor_record(actor_id)
	_check(record.get("assignments", {}).get("residence", "") == _shop.get_facility_id() + ".proprietor.home", "same character owns employment and upstairs residence")
	_check(merchant.conversation_definition == load("res://features/conversation/resources/generic_shopkeeper.tres"), "generic greeting offers existing trade route")
	_check(role.get_shop_inventory().count_item(SWORD) == 1 and role.get_shop_inventory().count_item(SEEDS) == 12 and role.get_shop_inventory().count_item(SILVER) == 100, "stock and finite money seed correctly")
	_check(await _until(func(): return merchant.is_on_counter_duty(), 35.0), "merchant physically reaches discovered counter during opening hours")
	_check(role.get_buy_price(SEEDS) == 1 and role.get_sell_price(SEEDS) == 2, "working trader offers configured prices")
	print("SHOP_COUNTER_POSITION ", merchant.global_position)
	await _capture("counter", merchant)
	clock.advance_hours(10)
	_check(role.get_buy_price(SEEDS) == -1 and role.get_sell_price(SEEDS) == -1, "20:00 immediately refuses new transactions even before duty cleanup")
	_check(await _until(func(): return not merchant.is_on_counter_duty(), 5.0), "20:00 releases counter duty")
	_check(await _until(func(): return merchant.global_position.y > 2.5 and merchant.get_interaction().is_sitting, 35.0), "closed shop owner physically reaches upstairs home")
	print("SHOP_HOME_POSITION ", merchant.global_position)
	await _capture("home", merchant)
	clock.advance_hours(2)
	_check(await _until(func(): return merchant.life_state == NpcRules.LifeState.ASLEEP and merchant.get_interaction().current_sleep_target == _shop.get_node("Furniture/ProprietorBed"), 20.0), "22:00 uses the upstairs bed")
	clock.advance_hours(10)
	_check(await _until(func(): return merchant.is_on_counter_duty(), 35.0), "08:00 returns downstairs to counter")
	_check(role.get_buy_price(SEEDS) == 1 and role.get_sell_price(SEEDS) == 2, "returned trader reopens trade")
	var inventory := role.get_shop_inventory()
	_check(inventory.remove_item_count(SWORD, 1) and inventory.remove_item_count(SEEDS, 12) and inventory.remove_item_count(SILVER, 73), "consume stock and most of finite cash")
	var id := actor_id + ".shop_inventory"
	var container = gecs.get_inventory_container_entity(id).get_component(gecs.C_INVENTORY_CONTAINER)
	var due := int(container.merchant_next_restock_minute)
	var save := "user://general_trader.tres"
	_check(simulation.save_world_to_file(save), "actual GECS save includes merchant policy and deadline")
	clock.advance_minutes(float(due - clock.get_absolute_minute()))
	_check(inventory.count_item(SEEDS) == 12 and inventory.count_item(SWORD) == 0 and inventory.count_item(SILVER) == 27, "world-time refill restores repeat stock only, never one-time stock or cash")
	_check(simulation.load_world_from_file(save), "warm load restores merchant business")
	await process_frame
	await process_frame
	_check(inventory.count_item(SEEDS) == 0 and inventory.count_item(SWORD) == 0 and inventory.count_item(SILVER) == 27, "warm load retains emptied stock without reseeding")
	container = gecs.get_inventory_container_entity(id).get_component(gecs.C_INVENTORY_CONTAINER)
	_check(int(container.merchant_next_restock_minute) == due, "restock deadline round trips")
	# Leave only the durable character and owned stock; no scene merchant may
	# handle this refill. The ordinary realization controller is suspended for
	# this bounded fixture section so it cannot instantly recreate the actor.
	var realization := BootstrapContext.service(&"population_realization")
	if realization != null: realization.set_process(false)
	population.unregister_actor(merchant)
	merchant.queue_free()
	await process_frame
	await process_frame
	clock.advance_minutes(float(due - clock.get_absolute_minute()))
	var counts := {}
	for stack in gecs.get_inventory_stacks(id):
		counts[stack.item_definition_path] = int(counts.get(stack.item_definition_path, 0)) + int(stack.count)

	_check(not is_instance_valid(_shop._merchant) and int(counts.get(SEEDS.resource_path, 0)) == 12 and int(counts.get(SWORD.resource_path, 0)) == 0, "unloaded character receives cadence stock without one-time goods")
	if realization != null: realization.set_process(true)
	_check(await _until(func(): return is_instance_valid(_shop._merchant) and _shop._merchant.get_node_or_null("MerchantRole") != null, 8.0), "same persistent character realizes again")
	await process_frame
	if is_instance_valid(_shop._merchant):
		var restored: MerchantRole = _shop._merchant.get_node("MerchantRole")
		_check(_shop._merchant.stable_id == actor_id and restored.get_shop_inventory().count_item(SEEDS) == 12 and restored.get_shop_inventory().count_item(SWORD) == 0 and restored.get_shop_inventory().count_item(SILVER) == 27, "recreated merchant preserves business identity, replenished goods and silver inside its pouch")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	await _finish()

func _capture(label: String, merchant: HumanoidCharacter) -> void:
	var folder := OS.get_environment("SHOP_CAPTURE_DIR")
	if folder.is_empty() or DisplayServer.get_name() == "headless": return
	var visibility := BootstrapContext.service(&"building_visibility")
	var was_processing := visibility.is_processing() if visibility != null else false
	if visibility != null: visibility.set_process(false)
	var camera: Camera3D = _world.get_node("CameraRig/CameraPivot/Camera3D")
	var previous := camera.global_transform
	camera.global_position = Vector3(9, 11, 14) if label == "counter" else Vector3(9, 14, 14)
	camera.look_at(Vector3(0, 0.8 if label == "counter" else 3.7, 0))
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.18, 0.2, 0.23)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	_world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	_world.add_child(light)
	var building: WorldBuilding = _shop.get_node("BuildingSlot/CurrentBuilding")
	building.set_visibility_for_camera(true, camera.global_position, merchant, true)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(folder)
	_check(root.get_texture().get_image().save_png(folder.path_join(label + ".png")) == OK, "rendered " + label + " capture")
	_world.remove_child(environment)
	environment.free()
	_world.remove_child(light)
	light.free()
	camera.global_transform = previous
	if visibility != null: visibility.set_process(was_processing)

func _until(predicate: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await physics_frame
	return false

func _check(ok: bool, description: String) -> void:
	_checks += 1
	print("SHOP_CHECK ", "PASS " if ok else "FAIL ", description)
	if not ok: _failures.append(description)

func _finish() -> void:
	root.remove_child(_world)
	_world.free()
	for i in 8: await process_frame
	for failure in _failures: push_error(failure)
	print("GENERAL_TRADER_OK" if _failures.is_empty() else "GENERAL_TRADER_FAILED", " checks=", _checks)
	quit(0 if _failures.is_empty() else 1)
