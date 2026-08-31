extends SceneTree

const EGGPLANT := preload("res://features/inventory/resources/items/eggplant.tres")
var failures: Array[String] = []
var game: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	game = (load("res://scenes/zones/rustwash_basin/rustwash_basin.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	for _frame in 180:
		await process_frame
	var granary = game.get_node_or_null("Towns/Canyon/Granary/Furniture")
	var seed_container = granary.get_node_or_null("Container1") if granary != null else null
	_expect(seed_container != null and not seed_container.can_accept_item_count(EGGPLANT, 1), "Canyon seed container accepts harvested produce")
	var pallets: Array[Node] = []
	if granary != null:
		for child in granary.get_children():
			if str(child.name).begins_with("Pallet"):
				pallets.append(child)
	_expect(pallets.size() == 8, "Canyon granary must expose eight produce pallets")
	for pallet in pallets:
		_expect(str(pallet.get("container_type")) == "food" and bool(pallet.get("contributes_to_town_stock")) and pallet.can_accept_item_count(EGGPLANT, 1), "%s is not authoritative physical produce storage" % pallet.name)
		var nav_obstacle := pallet.get_node_or_null("NavigationObstacle3D") as NavigationObstacle3D
		_expect(int(pallet.get("collision_layer")) == 1 and nav_obstacle != null and nav_obstacle.affect_navigation_mesh, "%s lacks physical collision or baked navigation obstruction" % pallet.name)
	var context := BootstrapContext.active
	var settlements = context.get_optional(&"settlement")
	var food = context.get_optional(&"settlement_food")
	var stock = context.get_optional(&"inventory_stock")
	_expect(not (stock.get("_containers_by_id") as Dictionary).has("canyon.granary"), "Canyon still owns a hidden abstract granary container")
	_expect(stock.transact_item_count("canyon", EGGPLANT, 1), "Canyon produce routing transaction failed")
	var pallet_eggplants := 0
	for pallet in pallets:
		pallet_eggplants += int(pallet.inventory.count_item(EGGPLANT))
	_expect(pallet_eggplants == 1 and int(seed_container.inventory.count_item(EGGPLANT)) == 0, "Canyon harvest did not land on a physical produce pallet")
	var outputs: Array = food.call("_production_outputs", settlements.get_settlement_definition("canyon"), settlements.get_settlement_state("canyon"))
	for output in outputs:
		var item = output.get("item") if output is Resource else (output as Dictionary).get("item")
		_expect(item == null or str(item.item_id) != "food.generic", "Canyon physical farming still mints fake Provisions")
	_finish()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _finish() -> void:
	if game != null and is_instance_valid(game):
		root.remove_child(game)
		game.free()
	if failures.is_empty():
		print("CANYON_FARM_STORAGE_CONTRACT_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CANYON_FARM_STORAGE_CONTRACT_FAILED count=%d" % failures.size())
	quit(1)
