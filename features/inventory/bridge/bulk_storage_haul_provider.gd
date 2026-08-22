extends Node

class_name BulkStorageHaulProvider

const SERVICE_ID := &"bulk_storage_haul"

var _context: BootstrapContext
var _job_system: Node
var _platforms: Array = []
var _assignments: Dictionary = {}
var _offers_by_platform: Dictionary = {}
var _platform_signal_callbacks: Dictionary = {}
var _offer_cache: Array = []


func initialize(context: BootstrapContext) -> void:
	_context = context
	_job_system = context.get_optional(&"job_system") if context != null else null
	add_to_group("job_provider")
	if _job_system != null and _job_system.has_method("register_job_provider"):
		_job_system.call("register_job_provider", self)


func teardown() -> void:
	if _job_system != null and is_instance_valid(_job_system) and _job_system.has_method("unregister_job_provider"):
		_job_system.call("unregister_job_provider", self)
	for platform in _platforms.duplicate():
		unregister_platform(platform)
	for actor_key in _assignments.keys().duplicate():
		_erase_assignment(int(actor_key), true)
	_offer_cache.clear()
	_job_system = null
	_context = null


func get_provider_name() -> String:
	return "Bulk Storage Hauling"


func get_job_category_specs(_settlement_id := "") -> Array:
	return [{
		"entry_id": "category:haul",
		"category": "haul",
		"display_name": "Haul",
		"default_last": true,
	}]


func register_platform(platform: Node) -> void:
	if platform == null or not is_instance_valid(platform) or _platforms.has(platform):
		return
	_platforms.append(platform)
	if platform.has_method("bind_haul_provider"):
		platform.call("bind_haul_provider", self)
	var callback := Callable(self, "_on_platform_changed").bind(platform)
	_platform_signal_callbacks[platform.get_instance_id()] = callback
	if platform.has_signal("inventory_changed") and not platform.inventory_changed.is_connected(callback):
		platform.inventory_changed.connect(callback)
	_refresh_platform_offers(platform)


func unregister_platform(platform: Node) -> void:
	_disconnect_platform(platform)
	if platform != null and is_instance_valid(platform) and platform.has_method("unbind_haul_provider"):
		platform.call("unbind_haul_provider", self)
	_platforms.erase(platform)
	if platform != null:
		_offers_by_platform.erase(platform.get_instance_id())
	_rebuild_flat_offer_cache()
	for actor_key in _assignments.keys().duplicate():
		var assignment: Dictionary = _assignments.get(actor_key, {})
		if assignment.get("platform") == platform:
			_erase_assignment(int(actor_key), false)


func get_available_work_offers(settlement_id := "") -> Array:
	if settlement_id.is_empty():
		return _offer_cache
	var offers: Array = []
	for offer_value in _offer_cache:
		var offer: Dictionary = offer_value
		if str(offer.get("settlement_id", "")) == settlement_id:
			offers.append(offer)
	return offers


func can_actor_accept_work_offer(offer: Dictionary, actor: Node) -> bool:
	var platform = offer.get("platform") as Node
	if platform == null or not is_instance_valid(platform) or not platform.has_method("can_actor_accept_automatic_haul"):
		return false
	if _assignment_platform(actor) != null:
		return false
	return bool(platform.call("can_actor_accept_automatic_haul", actor, str(offer.get("item_path", ""))))


func accept_work_offer(offer: Dictionary, actor: Node) -> Dictionary:
	if not can_actor_accept_work_offer(offer, actor):
		return {"accepted": false}
	var platform = offer.get("platform") as Node
	if not bool(platform.call("begin_automatic_haul", actor, str(offer.get("item_path", "")))):
		return {"accepted": false}
	var actor_key := actor.get_instance_id()
	var exit_callback := Callable(self, "_on_assigned_actor_tree_exiting").bind(actor_key)
	if actor.has_signal("tree_exiting") and not actor.tree_exiting.is_connected(exit_callback):
		actor.tree_exiting.connect(exit_callback, CONNECT_ONE_SHOT)
	_assignments[actor_key] = {
		"platform": platform,
		"actor": weakref(actor),
		"exit_callback": exit_callback,
	}
	return {"accepted": true}


func has_active_work_for_actor(actor: Node) -> bool:
	var platform := _assignment_platform(actor) as Node
	if platform == null:
		return false
	if platform.has_method("has_pending_automatic_haul") and bool(platform.call("has_pending_automatic_haul", actor)):
		return true
	_erase_assignment(actor.get_instance_id(), false)
	return false


func cancel_work_for_actor(actor: Node) -> bool:
	var platform := _assignment_platform(actor) as Node
	if platform == null:
		return false
	if platform.has_method("cancel_pending_automatic_haul"):
		platform.call("cancel_pending_automatic_haul", actor)
	_erase_assignment(actor.get_instance_id(), false)
	return true


func _assignment_platform(actor: Node):
	if actor == null:
		return null
	var actor_key := actor.get_instance_id()
	var assignment: Dictionary = _assignments.get(actor_key, {})
	var platform = assignment.get("platform")
	if platform == null or not is_instance_valid(platform):
		_erase_assignment(actor_key, false)
		return null
	return platform


func notify_platform_changed(platform: Node = null) -> void:
	if platform != null and is_instance_valid(platform) and _platforms.has(platform):
		_refresh_platform_offers(platform)


func _on_platform_changed(platform: Node) -> void:
	notify_platform_changed(platform)


func _disconnect_platform(platform) -> void:
	if platform == null:
		return
	var platform_key: int = platform.get_instance_id()
	var callback: Callable = _platform_signal_callbacks.get(platform_key, Callable())
	if is_instance_valid(platform) and platform.has_signal("inventory_changed") and callback.is_valid() \
			and platform.inventory_changed.is_connected(callback):
		platform.inventory_changed.disconnect(callback)
	_platform_signal_callbacks.erase(platform_key)


func _refresh_platform_offers(platform: Node) -> void:
	if platform == null or not is_instance_valid(platform) or not platform.is_inside_tree():
		return
	var offers: Array = platform.call("get_automatic_haul_offers", "") if platform.has_method("get_automatic_haul_offers") \
			else [platform.call("get_automatic_haul_offer", "")] if platform.has_method("get_automatic_haul_offer") else []
	for offer in offers:
		(offer as Dictionary)["provider"] = self
	_offers_by_platform[platform.get_instance_id()] = offers
	_rebuild_flat_offer_cache()


func _rebuild_flat_offer_cache() -> void:
	_offer_cache.clear()
	for platform in _platforms:
		if platform == null or not is_instance_valid(platform):
			continue
		_offer_cache.append_array(_offers_by_platform.get(platform.get_instance_id(), []))


func _on_assigned_actor_tree_exiting(actor_key: int) -> void:
	_erase_assignment(actor_key, true)


func _erase_assignment(actor_key: int, cancel_platform: bool) -> void:
	var assignment: Dictionary = _assignments.get(actor_key, {})
	if assignment.is_empty():
		return
	var platform = assignment.get("platform")
	if cancel_platform and platform != null and is_instance_valid(platform) and platform.has_method("cancel_pending_automatic_haul_by_actor_key"):
		platform.call("cancel_pending_automatic_haul_by_actor_key", actor_key)
	var actor_ref := assignment.get("actor") as WeakRef
	var actor = actor_ref.get_ref() if actor_ref != null else null
	var exit_callback: Callable = assignment.get("exit_callback", Callable())
	if actor != null and is_instance_valid(actor) and actor.has_signal("tree_exiting") and exit_callback.is_valid() \
			and actor.tree_exiting.is_connected(exit_callback):
		actor.tree_exiting.disconnect(exit_callback)
	_assignments.erase(actor_key)
