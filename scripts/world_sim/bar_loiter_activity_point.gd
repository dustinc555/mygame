extends SettlementActivityPoint

class_name BarLoiterActivityPoint

@export var bar_path: NodePath = NodePath("..")
@export_range(0.0, 300.0, 1.0) var revisit_cooldown_seconds := 20.0

var _active_visitors: Dictionary = {}
var _visitor_cooldowns: Dictionary = {}


func assign_actor(actor: Node) -> bool:
	if actor == null or not is_available_for(actor):
		return false
	var bar := _get_bar()
	if bar == null or not bar.has_method("assign_loitering_actor"):
		return false
	if bool(bar.call("assign_loitering_actor", actor, global_position)):
		_active_visitors[_actor_key(actor)] = actor
		return true
	return false


func is_available_for(actor: Node) -> bool:
	_prune_visitors()
	_prune_cooldowns()
	if not enabled or actor == null:
		return false
	var key := _actor_key(actor)
	if _active_visitors.has(key):
		return true
	if _visitor_cooldowns.has(key) and float(_visitor_cooldowns[key]) > _now_seconds():
		return false
	var bar := _get_bar()
	if bar != null:
		if bar.has_method("can_actor_visit_as_townie") and not bool(bar.call("can_actor_visit_as_townie", actor)):
			return false
		if bar.has_method("has_available_loitering_seat") and not bool(bar.call("has_available_loitering_seat", actor)):
			return false
	return _active_visitors.size() < _visitor_capacity()


func release_actor(actor: Node) -> void:
	if actor == null:
		return
	var key := _actor_key(actor)
	if _active_visitors.has(key):
		_active_visitors.erase(key)
		_visitor_cooldowns[key] = _now_seconds() + revisit_cooldown_seconds
		if actor.has_method("stop_seat_assignment"):
			actor.call("stop_seat_assignment")
	super.release_actor(actor)


func get_active_visitor_count() -> int:
	_prune_visitors()
	return _active_visitors.size()


func _get_bar() -> Node:
	var bar := get_node_or_null(bar_path)
	if bar != null:
		return bar
	var current := get_parent()
	while current != null:
		if current.has_method("assign_loitering_actor"):
			return current
		current = current.get_parent()
	return null


func _visitor_capacity() -> int:
	var bar := _get_bar()
	if bar != null:
		var configured = bar.get("visitor_capacity")
		if configured != null:
			return max(0, int(configured))
	return 0


func _prune_visitors() -> void:
	var removed_keys: Array = []
	for key in _active_visitors.keys():
		var actor: Node = _active_visitors[key]
		if actor == null or not is_instance_valid(actor):
			removed_keys.append(key)
			continue
		var life_state = actor.get("life_state")
		if life_state != null and int(life_state) != NpcRules.LifeState.ALIVE:
			removed_keys.append(key)
			continue
		if actor.has_method("get_active_job_provider") and actor.call("get_active_job_provider") != null:
			removed_keys.append(key)
			continue
		if actor.has_method("is_sitting") and not bool(actor.call("is_sitting")):
			removed_keys.append(key)
	for key in removed_keys:
		_active_visitors.erase(key)


func _prune_cooldowns() -> void:
	var now := _now_seconds()
	var expired_keys: Array = []
	for key in _visitor_cooldowns.keys():
		if float(_visitor_cooldowns[key]) <= now:
			expired_keys.append(key)
	for key in expired_keys:
		_visitor_cooldowns.erase(key)


func _actor_key(actor: Node) -> String:
	if actor == null:
		return ""
	var stable_id = actor.get("stable_id")
	if stable_id != null and not str(stable_id).is_empty():
		return str(stable_id)
	return str(actor.get_instance_id())


func _now_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0
