extends "res://tests/validation/test_case.gd"
## Run: python3 tests/run_validation.py --filter validate_bulk_automatic_haul.gd

const PLATFORM_PATH := "res://features/world/projection/containers/bulk_storage_platform.tscn"
const PROVIDER_PATH := "res://features/inventory/bridge/haul_provider.gd"
const TOMATO := preload("res://features/inventory/resources/items/tomato.tres")
const EGGPLANT := preload("res://features/inventory/resources/items/eggplant.tres")

var failures: Array[String] = []


class ActorFixture:
	extends Node3D
	var stable_id := "party.hauler"
	var faction_name := "Market Ward"
	var inventory := InventoryData.new(10, 4, 60.0, true)
	var assigned_container
	var assigned_as_player_order := true

	func assign_open_container(container, issued_by_player := true) -> void:
		assigned_container = container
		assigned_as_player_order = issued_by_player

	func is_player_party_member() -> bool:
		return true

	func has_active_player_order() -> bool:
		return false


class HigherPriorityProvider:
	extends Node
	var available := true
	var accepted_count := 0

	func get_job_category_specs(_settlement_id := "") -> Array:
		return []

	func get_available_work_offers(_settlement_id := "") -> Array:
		if not available:
			return []
		return [{
			"offer_id": "validation:higher_priority_farm",
			"category": "farm",
			"job_entry_id": "category:farm",
			"faction_neutral": true,
			"world_position": Vector3.ZERO,
			"urgency": 1.0,
		}]

	func can_actor_accept_work_offer(_offer: Dictionary, _actor: Node) -> bool:
		return available

	func accept_work_offer(_offer: Dictionary, _actor: Node) -> Dictionary:
		accepted_count += 1
		return {"accepted": true}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_expect(ResourceLoader.exists(PROVIDER_PATH), "automatic bulk-storage haul provider exists")
	var provider_script := load(PROVIDER_PATH) as Script if ResourceLoader.exists(PROVIDER_PATH) else null
	var provider = provider_script.new() if provider_script != null else null
	_expect(provider != null, "automatic haul provider loads")
	if provider == null:
		_finish()
		return
	var holder := Node3D.new()
	root.add_child(holder)
	holder.add_child(provider)
	provider.add_to_group("job_provider")
	var job_system := JobSystemController.new()
	holder.add_child(job_system)
	job_system.root_scene = holder
	job_system.register_job_provider(provider)
	var higher_priority := HigherPriorityProvider.new()
	holder.add_child(higher_priority)
	higher_priority.add_to_group("job_provider")
	job_system.register_job_provider(higher_priority)
	var platform_scene := load(PLATFORM_PATH) as PackedScene
	var platform = platform_scene.instantiate() if platform_scene != null else null
	_expect(platform != null, "bulk platform loads for automatic haul")
	if platform == null:
		_finish()
		return
	platform.container_id = "validation.bulk_automatic_haul"
	platform.owner_faction_name = "Player"
	platform.position = Vector3(4.0, 0.0, 0.0)
	holder.add_child(platform)
	await process_frame
	provider.register_platform(platform)
	_expect(provider.get_job_category_specs().size() == 1 and str(provider.get_job_category_specs()[0].get("entry_id", "")) == "category:haul" \
			and bool(provider.get_job_category_specs()[0].get("default_last", false)), "Haul is a reorderable Jobs category that defaults last")
	var empty_offers: Array = provider.get_available_work_offers()
	_expect(_offers_item(empty_offers, TOMATO) and _offers_item(empty_offers, EGGPLANT), "empty filtered platform publishes enabled commodity offers so the first reservation can choose its type")

	var actor := ActorFixture.new()
	holder.add_child(actor)
	actor.inventory.add_item_count(TOMATO, 7)
	platform.deposit_item_count(TOMATO, 50)
	var offers: Array = provider.get_available_work_offers()
	_expect(offers.size() == 1 and str(offers[0].get("job_entry_id", "")) == "category:haul", "tomato platform publishes one low-priority haul offer")
	var owner := ActorFixture.new()
	owner.faction_name = "Player"
	holder.add_child(owner)
	platform.set_storage_item_enabled(TOMATO.item_id, false, owner)
	_expect(provider.get_available_work_offers().is_empty(), "disabling Tomato storage invalidates the cached haul offer immediately")
	platform.set_storage_item_enabled(TOMATO.item_id, true, owner)
	offers = provider.get_available_work_offers()
	_expect(provider.can_actor_accept_work_offer(offers[0], actor), "foreign-owned actor carrying tomatoes can accept nearby tomato haul")
	_expect(job_system.set_actor_jobs_enabled(actor, true), "Jobs can be enabled for the hauler")
	var ranked_jobs: Array = job_system.get_actor_ranked_jobs(actor)
	_expect(not ranked_jobs.is_empty() and str(ranked_jobs[-1].get("entry_id", "")) == "category:haul", "Haul defaults behind every other available job priority")
	_expect(job_system.dispatch_actor_work(actor) and higher_priority.accepted_count == 1 and actor.assigned_container == null, "higher-priority available work runs before carried-item hauling")
	higher_priority.available = false
	_expect(job_system.dispatch_actor_work(actor), "idle Jobs dispatch accepts automatic tomato hauling when no higher-priority offer exists")
	_expect(actor.assigned_container == platform and not actor.assigned_as_player_order, "automatic haul reuses container travel without becoming a player order")
	_expect(actor.inventory.count_item(TOMATO) == 7 and platform.get_stored_item_count(TOMATO) == 50, "automatic haul reserves capacity but does not teleport inventory")
	_expect(provider.has_active_work_for_actor(actor), "accepted haul blocks competing idle-job dispatch while actor travels")
	var result: Dictionary = platform.resolve_pending_deposit(actor)
	_expect(int(result.get("amount", 0)) == 7 and actor.inventory.count_item(TOMATO) == 0 \
			and platform.get_stored_item_count(TOMATO) == 57, "arrival silently deposits all matching carried tomatoes")
	_expect(not provider.has_active_work_for_actor(actor), "haul assignment clears after arrival")

	actor.inventory.add_item_count(EGGPLANT, 2)
	_expect(provider.get_available_work_offers().size() == 1 and not provider.can_actor_accept_work_offer(provider.get_available_work_offers()[0], actor), "tomato platform never accepts unrelated carried eggplants")

	platform.withdraw_item_count(TOMATO, 57)
	platform.deposit_item_count(TOMATO, 899)
	actor.inventory.add_item_count(TOMATO, 7)
	offers = provider.get_available_work_offers()
	var accepted: Dictionary = provider.accept_work_offer(offers[0], actor) if not offers.is_empty() else {}
	var second_actor := ActorFixture.new()
	second_actor.stable_id = "party.second_hauler"
	second_actor.inventory.add_item_count(TOMATO, 3)
	holder.add_child(second_actor)
	_expect(provider.get_available_work_offers().is_empty(), "reserved incoming tomatoes prevent a second hauler from overbooking the final platform capacity")
	result = platform.resolve_pending_deposit(actor)
	_expect(bool(accepted.get("accepted", false)) and int(result.get("amount", 0)) == 1 \
			and actor.inventory.count_item(TOMATO) == 6 and platform.get_stored_item_count(TOMATO) == 900, "automatic haul reserves and transfers only remaining platform capacity")
	platform.withdraw_item_count(TOMATO, 900)
	offers = provider.get_available_work_offers()
	var tomato_offer := _offer_for_item(offers, TOMATO)
	_expect(not tomato_offer.is_empty() and bool(provider.accept_work_offer(tomato_offer, second_actor).get("accepted", false)), "empty platform accepts a first tomato reservation")
	second_actor.queue_free()
	await process_frame
	_expect(_offers_item(provider.get_available_work_offers(), TOMATO), "actor removal cancels its reservation and republishes empty-platform capacity")

	# A normal actor already in reach must emit its real arrival signal and
	# commit through the provider callback, not resolve_pending_deposit here.
	var live_actor := HumanoidCharacter.new()
	live_actor.stable_id = "validation.live_hauler"
	live_actor.position = platform.position + Vector3(1.8, 0.0, 0.0)
	holder.add_child(live_actor)
	live_actor.inventory.add_item_count(TOMATO, 2)
	var arrival := {"count": 0}
	live_actor.container_reached.connect(func(_actor, _container): arrival.count += 1)
	tomato_offer = _offer_for_item(provider.get_available_work_offers(), TOMATO)
	_expect(bool(provider.accept_work_offer(tomato_offer, live_actor).get("accepted", false)), "normal actor accepts an in-reach automatic haul")
	_expect(live_actor.inventory.count_item(TOMATO) == 2, "normal actor never deposits before its arrival")
	var deadline := Time.get_ticks_msec() + 3000
	while arrival.count == 0 and Time.get_ticks_msec() < deadline:
		await physics_frame
	_expect(arrival.count == 1 and live_actor.inventory.count_item(TOMATO) == 0 and platform.get_stored_item_count(TOMATO) == 2, "real actor arrival commits exactly one provider deposit")
	_expect(not provider.has_active_work_for_actor(live_actor), "real arrival releases the haul assignment")
	live_actor.queue_free()
	await process_frame

	# Hold both a stale cached offer and an accepted assignment across normal
	# platform destruction. Neither may dereference a freed Godot object.
	_expect(not provider.has_active_work_for_actor(actor), "partial deposit assignment clears after completion")
	var stale_offer := _offer_for_item(provider.get_available_work_offers(), TOMATO)
	_expect(bool(provider.accept_work_offer(stale_offer, actor).get("accepted", false)), "platform deletion fixture starts with active assignment")
	var carried_before: int = actor.inventory.count_item(TOMATO)
	platform.queue_free()
	await process_frame
	_expect(not provider.has_active_work_for_actor(actor), "destroyed platform retires active assignment")
	_expect(provider.get_available_work_offers().is_empty(), "destroyed platform retires offers")
	_expect(not provider.can_actor_accept_work_offer(stale_offer, actor), "cached offer rejects freed platform safely")
	_expect(not bool(provider.accept_work_offer(stale_offer, actor).get("accepted", false)), "stale platform offer cannot start work")
	_expect(actor.inventory.count_item(TOMATO) == carried_before, "platform destruction preserves carried goods")
	root.remove_child(holder)
	holder.free()
	_finish()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _offers_item(offers: Array, item: ItemDefinition) -> bool:
	return not _offer_for_item(offers, item).is_empty()


func _offer_for_item(offers: Array, item: ItemDefinition) -> Dictionary:
	for offer_value in offers:
		var offer: Dictionary = offer_value
		if str(offer.get("item_path", "")) == item.resource_path:
			return offer
	return {}


func _finish() -> void:
	if failures.is_empty():
		print("BULK_AUTOMATIC_HAUL_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("BULK_AUTOMATIC_HAUL_FAILED count=%d" % failures.size())
	quit(1)
