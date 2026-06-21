extends SettlementActivityPoint

class_name FacilityVisitActivityPoint

@export var facility_path: NodePath = NodePath("..")
@export var visit_seats_root_path: NodePath
@export var standing_points_root_path: NodePath
@export var visitor_capacity_property := "visitor_capacity"
@export_range(0, 64, 1) var visitor_capacity := 0
@export_range(0.0, 300.0, 1.0) var revisit_cooldown_seconds := 20.0

var _active_visitors: Dictionary = {}
var _visitor_cooldowns: Dictionary = {}


func assign_actor(actor: Node) -> bool:
	if actor == null or not is_available_for(actor):
		return false
	var target := _find_available_visit_target(actor)
	if target == null:
		return false
	if not _assign_actor_to_visit_target(actor, target):
		return false
	_active_visitors[_actor_key(actor)] = {"actor": actor, "target": target}
	return true


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
	if not _facility_allows_actor(actor):
		return false
	if _active_visitors.size() >= _visitor_capacity():
		return false
	return _find_available_visit_target(actor) != null


func release_actor(actor: Node) -> void:
	if actor == null:
		return
	var key := _actor_key(actor)
	if _active_visitors.has(key):
		var target := _target_from_visit_record(_active_visitors[key])
		_release_visit_target(actor, target)
		_active_visitors.erase(key)
		_visitor_cooldowns[key] = _now_seconds() + revisit_cooldown_seconds
	super.release_actor(actor)


func get_active_visitor_count() -> int:
	_prune_visitors()
	return _active_visitors.size()


func has_available_visit_target(actor: Node) -> bool:
	_prune_visitors()
	if actor == null or _active_visitors.size() >= _visitor_capacity():
		return false
	return _find_available_visit_target(actor) != null


func _assign_actor_to_visit_target(actor: Node, target: Node) -> bool:
	if _is_sittable_target(target):
		return _assign_actor_to_seat(actor, target)
	if _is_standing_target(target):
		return _assign_actor_to_standing_point(actor, target)
	return false


func _assign_actor_to_seat(actor: Node, seat: Node) -> bool:
	if actor == null or seat == null:
		return false
	if actor.has_method("sit_at_seat_immediately") and bool(actor.call("sit_at_seat_immediately", seat)):
		return true
	if actor.has_method("assign_seat_target"):
		actor.call("assign_seat_target", seat, false)
		return true
	return false


func _assign_actor_to_standing_point(actor: Node, point: Node) -> bool:
	if actor == null or point == null or not point.has_method("claim_visitor"):
		return false
	if not bool(point.call("claim_visitor", actor)):
		return false
	if actor.has_method("set_move_target"):
		var visit_position: Vector3 = point.call("get_visit_position", actor)
		actor.call("set_move_target", visit_position, false)
		return true
	point.call("release_visitor", actor)
	return false


func _release_visit_target(actor: Node, target: Node) -> void:
	if _is_sittable_target(target):
		if actor.has_method("stop_seat_assignment"):
			actor.call("stop_seat_assignment")
		elif target.has_method("release_sitter"):
			target.call("release_sitter", actor)
		return
	if _is_standing_target(target) and target.has_method("release_visitor"):
		target.call("release_visitor", actor)


func _find_available_visit_target(actor: Node) -> Node:
	var targets: Array[Node] = []
	_collect_visit_targets(_get_node_at_visit_path(visit_seats_root_path), targets)
	_collect_visit_targets(_get_node_at_visit_path(standing_points_root_path), targets)
	var best: Node
	var best_distance := INF
	for target in targets:
		if not _target_available_for_actor(target, actor):
			continue
		var target_node := target as Node3D
		if target_node == null:
			continue
		var distance := target_node.global_position.distance_squared_to(global_position)
		if distance < best_distance:
			best_distance = distance
			best = target
	return best


func _collect_visit_targets(root: Node, targets: Array[Node]) -> void:
	if root == null:
		return
	if _is_sittable_target(root) or _is_standing_target(root):
		targets.append(root)
		return
	for child in root.get_children():
		_collect_visit_targets(child, targets)


func _target_available_for_actor(target: Node, actor: Node) -> bool:
	if _is_sittable_target(target):
		if target.has_method("is_occupied") and bool(target.call("is_occupied")):
			return target.has_method("get_sitter") and target.call("get_sitter") == actor
		return true
	if _is_standing_target(target):
		return not target.has_method("is_available_for") or bool(target.call("is_available_for", actor))
	return false


func _is_sittable_target(target: Node) -> bool:
	return target != null and target.has_method("claim_sitter") and target.has_method("get_seat_position")


func _is_standing_target(target: Node) -> bool:
	return target != null and target.has_method("claim_visitor") and target.has_method("get_visit_position")


func _facility_allows_actor(actor: Node) -> bool:
	var facility := _get_facility()
	if facility != null and facility.has_method("can_actor_visit_facility"):
		return bool(facility.call("can_actor_visit_facility", actor))
	return true


func _get_facility() -> Node:
	var facility := get_node_or_null(facility_path)
	if facility != null:
		return facility
	var current := get_parent()
	while current != null:
		if current is SettlementFacility or current.has_method("get_facility_record"):
			return current
		current = current.get_parent()
	return null


func _get_node_at_visit_path(path: NodePath) -> Node:
	if path.is_empty():
		return null
	var direct := get_node_or_null(path)
	if direct != null:
		return direct
	var facility := _get_facility()
	return facility.get_node_or_null(path) if facility != null else null


func _visitor_capacity() -> int:
	var facility := _get_facility()
	if facility != null and not visitor_capacity_property.is_empty():
		var configured = facility.get(visitor_capacity_property)
		if configured != null:
			return max(0, int(configured))
	return max(0, visitor_capacity)


func _prune_visitors() -> void:
	var removed_keys: Array = []
	for key in _active_visitors.keys():
		var record = _active_visitors[key]
		var actor := _actor_from_visit_record(record)
		var target := _target_from_visit_record(record)
		if actor == null or not is_instance_valid(actor):
			removed_keys.append(key)
			continue
		var life_state = actor.get("life_state")
		if life_state != null and int(life_state) != NpcRules.LifeState.ALIVE:
			removed_keys.append(key)
			continue
		if not _facility_allows_actor(actor):
			_release_visit_target(actor, target)
			removed_keys.append(key)
			continue
		if actor.has_method("get_active_job_provider") and actor.call("get_active_job_provider") != null:
			_release_visit_target(actor, target)
			removed_keys.append(key)
			continue
		if _is_sittable_target(target):
			if target.has_method("get_sitter") and target.call("get_sitter") != actor:
				removed_keys.append(key)
			elif actor.has_method("is_sitting") and not bool(actor.call("is_sitting")):
				removed_keys.append(key)
		elif _is_standing_target(target) and target.has_method("get_visitor") and target.call("get_visitor") != actor:
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


func _actor_from_visit_record(record) -> Node:
	# Validate before casting — a tracked visitor may have been freed by LOD derealization,
	# and casting a freed object crashes.
	var raw = record.get("actor") if record is Dictionary else record
	if raw == null or not is_instance_valid(raw):
		return null
	return raw as Node


func _target_from_visit_record(record) -> Node:
	if not (record is Dictionary):
		return null
	var raw = record.get("target")
	if raw == null or not is_instance_valid(raw):
		return null
	return raw as Node


func _actor_key(actor: Node) -> String:
	if actor == null:
		return ""
	var stable_id = actor.get("stable_id")
	if stable_id != null and not str(stable_id).is_empty():
		return str(stable_id)
	return str(actor.get_instance_id())


func _now_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0
