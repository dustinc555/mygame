extends SceneTree
## Run: godot --headless --path . --script res://tools/validation/validate_water_hauling.gd

const PROVIDER_PATH := "res://features/inventory/bridge/haul_provider.gd"

var failures: Array[String] = []
var _ecs_placeholder: Node


class EndpointFixture:
	extends Node3D
	var endpoint_id := ""
	var settlement_id := "town.validation"
	var owner_faction_name := "Player"
	var resource_id := "water"
	var source_enabled := false
	var destination_enabled := false
	var stock := 0.0
	var capacity := 0.0
	var reserved_outgoing := 0.0
	var reserved_incoming := 0.0

	func get_haul_endpoint_id() -> String:
		return endpoint_id

	func get_haul_resource_ids() -> PackedStringArray:
		return PackedStringArray([resource_id])

	func get_haul_available(requested_resource_id: String) -> float:
		if not source_enabled or requested_resource_id != resource_id:
			return 0.0
		return maxf(0.0, stock - reserved_outgoing)

	func get_haul_free_capacity(requested_resource_id: String) -> float:
		if not destination_enabled or requested_resource_id != resource_id:
			return 0.0
		return maxf(0.0, capacity - stock - reserved_incoming)

	func get_haul_transfer_capacity(requested_resource_id: String, actor: Node) -> float:
		if requested_resource_id != resource_id:
			return 0.0
		return maxf(0.0, 10.0 - float(actor.carried.get(resource_id, 0.0)))

	func reserve_haul_outgoing(requested_resource_id: String, requested: float, _actor: Node) -> float:
		var amount := minf(maxf(0.0, requested), get_haul_available(requested_resource_id))
		reserved_outgoing += amount
		return amount

	func release_haul_outgoing(requested_resource_id: String, amount: float, _actor: Node = null) -> float:
		if requested_resource_id != resource_id:
			return 0.0
		var released := minf(maxf(0.0, amount), reserved_outgoing)
		reserved_outgoing -= released
		return released

	func reserve_haul_incoming(requested_resource_id: String, requested: float, _actor: Node) -> float:
		var amount := minf(maxf(0.0, requested), get_haul_free_capacity(requested_resource_id))
		reserved_incoming += amount
		return amount

	func release_haul_incoming(requested_resource_id: String, amount: float, _actor: Node = null) -> float:
		if requested_resource_id != resource_id:
			return 0.0
		var released := minf(maxf(0.0, amount), reserved_incoming)
		reserved_incoming -= released
		return released

	func load_reserved_haul(requested_resource_id: String, requested: float, actor: Node) -> float:
		if requested_resource_id != resource_id:
			return 0.0
		var amount := minf(maxf(0.0, requested), minf(stock, reserved_outgoing))
		stock -= amount
		reserved_outgoing -= amount
		actor.carried[resource_id] = float(actor.carried.get(resource_id, 0.0)) + amount
		return amount

	func unload_reserved_haul(requested_resource_id: String, requested: float, actor: Node) -> float:
		if requested_resource_id != resource_id:
			return 0.0
		var amount := minf(maxf(0.0, requested), minf(float(actor.carried.get(resource_id, 0.0)), reserved_incoming))
		stock += amount
		reserved_incoming -= amount
		actor.carried[resource_id] = float(actor.carried.get(resource_id, 0.0)) - amount
		return amount

	func get_interaction_position(_actor: Node) -> Vector3:
		return global_position


class ActorFixture:
	extends Node3D
	signal container_reached(member: Node, container: Node)
	var faction_name := "Player"
	var carried: Dictionary = {}
	var assigned_container: Node
	var assigned_as_player_order := true

	func assign_open_container(container: Node, issued_by_player := true) -> void:
		assigned_container = container
		assigned_as_player_order = issued_by_player

	func is_authorized_for_owner(_target: Node, owner: String) -> bool:
		return faction_name == owner


func _initialize() -> void:
	if not Engine.has_singleton("ECS"):
		_ecs_placeholder = Node.new()
		Engine.register_singleton("ECS", _ecs_placeholder)
	call_deferred("_run")


func _run() -> void:
	_expect(ResourceLoader.exists(PROVIDER_PATH), "generic haul provider exists")
	if not ResourceLoader.exists(PROVIDER_PATH):
		_finish()
		return
	var holder := Node3D.new()
	root.add_child(holder)
	var provider: Node = (load(PROVIDER_PATH) as Script).new()
	holder.add_child(provider)
	provider.initialize(BootstrapContext.new(holder, null))

	var well := _endpoint("well.validation", true, false, 50.0, 50.0, Vector3.ZERO)
	var tank := _endpoint("tank.validation", true, true, 0.0, 20.0, Vector3(5.0, 0.0, 0.0))
	holder.add_child(well)
	holder.add_child(tank)
	provider.register_endpoint(well)
	provider.register_endpoint(tank)

	var offers: Array = provider.get_available_work_offers("town.validation")
	_expect(offers.size() == 1, "one destination publishes one generic haul offer")
	var offer: Dictionary = offers[0] if not offers.is_empty() else {}
	_expect(str(offer.get("resource_id", "")) == "water" and str(offer.get("destination_endpoint_id", "")) == tank.endpoint_id, "offer carries resource and destination IDs")
	_expect(not offer.has("water_source") and not offer.has("storage"), "offer contains no water-specific node contract")

	var actor := ActorFixture.new()
	holder.add_child(actor)
	_expect(provider.can_actor_accept_work_offer(offer, actor), "generic haul accepts an authorized carrier")
	var accepted: Dictionary = provider.accept_work_offer(offer, actor)
	_expect(bool(accepted.get("accepted", false)) and actor.assigned_container == well and not actor.assigned_as_player_order, "generic haul physically routes source first")
	_expect(is_equal_approx(well.reserved_outgoing, 10.0) and is_equal_approx(tank.reserved_incoming, 10.0), "acceptance reserves source stock and destination capacity")
	actor.container_reached.emit(actor, well)
	_expect(is_equal_approx(float(actor.carried.get("water", 0.0)), 10.0) and actor.assigned_container == tank, "source arrival loads the carrier and routes destination")
	actor.container_reached.emit(actor, tank)
	_expect(is_equal_approx(well.stock, 40.0) and is_equal_approx(tank.stock, 10.0) and is_equal_approx(float(actor.carried.get("water", 0.0)), 0.0), "destination arrival conserves the exact transferred quantity")
	_expect(not provider.has_active_work_for_actor(actor), "completed generic haul clears its assignment")

	offers = provider.get_available_work_offers("town.validation")
	offer = offers[0] if not offers.is_empty() else {}
	accepted = provider.accept_work_offer(offer, actor)
	_expect(bool(accepted.get("accepted", false)), "second generic haul can start")
	provider.cancel_work_for_actor(actor)
	_expect(is_equal_approx(well.reserved_outgoing, 0.0) and is_equal_approx(tank.reserved_incoming, 0.0), "cancellation releases both reservations")

	var oil_source := _endpoint("oil.source", true, false, 20.0, 20.0, Vector3(1.0, 0.0, 0.0), "oil")
	var oil_tank := _endpoint("oil.tank", false, true, 0.0, 20.0, Vector3(2.0, 0.0, 0.0), "oil")
	holder.add_child(oil_source)
	holder.add_child(oil_tank)
	provider.register_endpoint(oil_source)
	provider.register_endpoint(oil_tank)
	var oil_offers: Array = provider.get_available_work_offers("town.validation")
	var oil_offer := _offer_for_resource(oil_offers, "oil")
	_expect(not oil_offer.is_empty() and provider.can_actor_accept_work_offer(oil_offer, actor), "the same provider handles a second resource without resource-specific code")

	var foreign_tank := _endpoint("foreign.tank", false, true, 0.0, 20.0, Vector3(3.0, 0.0, 0.0))
	foreign_tank.owner_faction_name = "Other"
	holder.add_child(foreign_tank)
	provider.register_endpoint(foreign_tank)
	var foreign_offer := _offer_for_destination(provider.get_available_work_offers("town.validation"), foreign_tank.endpoint_id)
	_expect(not foreign_offer.is_empty() and not provider.can_actor_accept_work_offer(foreign_offer, actor), "ownership boundaries prevent cross-faction hauling")

	provider.unregister_endpoint(tank)
	_expect(_offer_for_destination(provider.get_available_work_offers("town.validation"), tank.endpoint_id).is_empty(), "endpoint removal invalidates its offer")
	provider.teardown()
	holder.free()
	_finish()


func _endpoint(id: String, source: bool, destination: bool, stock: float, capacity: float, position: Vector3, resource_id := "water") -> EndpointFixture:
	var endpoint := EndpointFixture.new()
	endpoint.endpoint_id = id
	endpoint.source_enabled = source
	endpoint.destination_enabled = destination
	endpoint.stock = stock
	endpoint.capacity = capacity
	endpoint.position = position
	endpoint.resource_id = resource_id
	return endpoint


func _offer_for_resource(offers: Array, resource_id: String) -> Dictionary:
	for value in offers:
		var offer := value as Dictionary
		if str(offer.get("resource_id", "")) == resource_id:
			return offer
	return {}


func _offer_for_destination(offers: Array, destination_id: String) -> Dictionary:
	for value in offers:
		var offer := value as Dictionary
		if str(offer.get("destination_endpoint_id", "")) == destination_id:
			return offer
	return {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if _ecs_placeholder != null:
		Engine.unregister_singleton("ECS")
		_ecs_placeholder.free()
	if failures.is_empty():
		print("GENERIC_HAULING_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("GENERIC_HAULING_FAILED count=%d" % failures.size())
	quit(1)
