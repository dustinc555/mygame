extends Node

class_name OwnershipController

const WORLD_ACTOR_RULES := preload("res://scripts/world_sim/world_actor_rules.gd")

const META_OWNER_FACTION_NAME := "owner_faction_name"
const META_THEFT_VALUE := "theft_value"
const META_THEFT_NOISE_RADIUS := "theft_noise_radius"
const META_THEFT_DIFFICULTY := "theft_difficulty"
const THEFT_ATTEMPT_XP := 0.7
const THEFT_SUCCESS_XP := 1.8
const THEFT_DEXTERITY_XP_FACTOR := 0.08
const THEFT_DETECTION_PERCEPTION_XP := 1.1

@export var notice_radius := 12.0
@export var stolen_metadata_lifetime_minutes := 3.0 * 24.0 * 60.0

var root_scene: Node


func initialize(target_root: Node, _target_hud: CanvasLayer = null) -> void:
	root_scene = target_root


func _ready() -> void:
	add_to_group("ownership_controller")


func get_take_item_label(actor_id: String, item_or_stack) -> String:
	return "Pick Up" if _can_take_legally(actor_id, item_or_stack) else "Steal"


func get_take_item_color(actor_id: String, item_or_stack) -> Color:
	return Color.TRANSPARENT if _can_take_legally(actor_id, item_or_stack) else Color(0.92, 0.34, 0.30, 1.0)


func is_take_item_theft(actor_id: String, item_or_stack) -> bool:
	return not _can_take_legally(actor_id, item_or_stack)


func request_take_item(actor_id: String, item) -> bool:
	return request_take_stack(actor_id, _stack_id_from_value(item))


func request_take_stack(actor_id: String, stack_id: String) -> bool:
	var permission := can_take_stack(actor_id, stack_id)
	if not bool(permission.get("ok", false)):
		commit_denied_take_stack(actor_id, stack_id, permission)
		return false
	return commit_take_stack(actor_id, stack_id, permission)


func can_take_item(actor_id: String, item) -> Dictionary:
	return can_take_stack(actor_id, _stack_id_from_value(item))


func can_take_stack(actor_id: String, stack_id: String) -> Dictionary:
	actor_id = actor_id.strip_edges()
	stack_id = stack_id.strip_edges()
	if actor_id.is_empty() or stack_id.is_empty():
		return _take_item_result(false, "Invalid item", false, "invalid", [], actor_id, stack_id)
	var stack := _inventory_stack(stack_id)
	if stack.is_empty():
		return _take_item_result(false, "Missing item", false, "missing", [], actor_id, stack_id)
	if _can_take_stack_legally(actor_id, stack):
		return _take_item_result(true, "Take permitted", false, "legal", [], actor_id, stack_id)
	var witnesses := _find_theft_witness_ids(actor_id, stack)
	if witnesses.is_empty():
		var suspicious_witness := _find_theft_suspicion_witness_id(actor_id, stack)
		if suspicious_witness.is_empty():
			return _take_item_result(true, "Take permitted", true, "unseen", [], actor_id, stack_id)
		return _take_item_result(false, "Theft noticed", true, "suspicious", [suspicious_witness], actor_id, stack_id)
	return _take_item_result(true, "Take permitted", true, "seen", witnesses, actor_id, stack_id)


func commit_take_item(actor_id: String, item, permission: Dictionary = {}) -> bool:
	return commit_take_stack(actor_id, _stack_id_from_value(item), permission)


func commit_take_stack(actor_id: String, stack_id: String, permission: Dictionary = {}) -> bool:
	actor_id = actor_id.strip_edges()
	stack_id = stack_id.strip_edges()
	var result := permission.duplicate(true) if not permission.is_empty() else can_take_stack(actor_id, stack_id)
	if actor_id.is_empty() or stack_id.is_empty() or not bool(result.get("ok", false)):
		return false
	if not bool(result.get("theft", false)):
		return true
	var stack := _inventory_stack(stack_id)
	if stack.is_empty():
		return false
	match str(result.get("outcome", "")):
		"unseen":
			_award_theft_attempt_xp(actor_id, true)
			_mark_stack_stolen(actor_id, stack_id, stack)
			return true
		"seen":
			_award_theft_attempt_xp(actor_id, false)
			_award_theft_detection_xp(_take_item_witness_ids(result))
			_mark_stack_stolen(actor_id, stack_id, stack)
			return true
	return true


func commit_denied_take_item(actor_id: String, item, permission: Dictionary = {}) -> bool:
	return commit_denied_take_stack(actor_id, _stack_id_from_value(item), permission)


func commit_denied_take_stack(actor_id: String, stack_id: String, permission: Dictionary = {}) -> bool:
	actor_id = actor_id.strip_edges()
	stack_id = stack_id.strip_edges()
	var result := permission.duplicate(true) if not permission.is_empty() else can_take_stack(actor_id, stack_id)
	if actor_id.is_empty() or stack_id.is_empty() or bool(result.get("ok", false)):
		return false
	if str(result.get("outcome", "")) != "suspicious":
		return false
	var witnesses := _take_item_witness_ids(result)
	_award_theft_attempt_xp(actor_id, false)
	_award_theft_detection_xp(witnesses)
	for witness_id in witnesses:
		_face_observer_toward_actor(witness_id, actor_id)
	return true


func _can_take_legally(actor_id: String, item_or_stack) -> bool:
	var stack := _stack_from_value(item_or_stack)
	if stack.is_empty():
		return false
	return _can_take_stack_legally(actor_id, stack)


func _can_take_stack_legally(actor_id: String, stack: Dictionary) -> bool:
	var metadata: Dictionary = stack.get("metadata", {}) if stack.get("metadata", {}) is Dictionary else {}
	var owner_faction := str(metadata.get(META_OWNER_FACTION_NAME, "")).strip_edges()
	if owner_faction.is_empty():
		return true
	var actor_record := _population_record(actor_id)
	return str(actor_record.get("faction_id", "")).strip_edges() == owner_faction


func _take_item_result(ok: bool, message: String, theft: bool, outcome: String, witness_ids: Array, actor_id: String, stack_id: String) -> Dictionary:
	return {
		"ok": ok,
		"message": message,
		"theft": theft,
		"outcome": outcome,
		"witness_ids": witness_ids.duplicate(),
		"actor_id": actor_id,
		"stack_id": stack_id,
	}


func _take_item_witness_ids(permission: Dictionary) -> Array[String]:
	var witnesses: Array[String] = []
	var value = permission.get("witness_ids", [])
	if value is Array or value is PackedStringArray:
		for witness_id in value:
			var text := str(witness_id).strip_edges()
			if not text.is_empty():
				witnesses.append(text)
	return witnesses


func _find_theft_witness_ids(actor_id: String, stack: Dictionary) -> Array[String]:
	var witnesses: Array[String] = []
	var perception := _perception_controller()
	if perception == null or not perception.has_method("evaluate_observer"):
		return witnesses
	var actor_position := _actor_position(actor_id)
	for observer_id in _relevant_owner_witness_ids(stack):
		if observer_id == actor_id:
			continue
		if _actor_position(observer_id).distance_to(actor_position) > notice_radius:
			continue
		var result = perception.call("evaluate_observer", observer_id, actor_id)
		if result is Dictionary and bool((result as Dictionary).get("clearly_seen", false)):
			witnesses.append(observer_id)
	return witnesses


func _find_theft_suspicion_witness_id(actor_id: String, stack: Dictionary) -> String:
	var metadata: Dictionary = stack.get("metadata", {}) if stack.get("metadata", {}) is Dictionary else {}
	var noise_radius := float(metadata.get(META_THEFT_NOISE_RADIUS, 0.0))
	if noise_radius <= 0.01:
		return ""
	var actor_skill := _actor_theft_skill(actor_id)
	var stack_position := _stack_position(stack)
	var best_witness := ""
	var best_margin := -1.0
	for observer_id in _relevant_owner_witness_ids(stack):
		if observer_id == actor_id:
			continue
		var witness_distance := _actor_position(observer_id).distance_to(stack_position)
		if witness_distance > noise_radius:
			continue
		var required_skill := _required_theft_skill(actor_id, stack, observer_id, witness_distance, noise_radius)
		if actor_skill >= required_skill:
			continue
		var margin := required_skill - actor_skill
		if margin > best_margin:
			best_margin = margin
			best_witness = observer_id
	return best_witness


func _relevant_owner_witness_ids(stack: Dictionary) -> Array[String]:
	var records := _population_records()
	var metadata: Dictionary = stack.get("metadata", {}) if stack.get("metadata", {}) is Dictionary else {}
	var owner_faction := str(metadata.get(META_OWNER_FACTION_NAME, "")).strip_edges()
	var witnesses: Array[String] = []
	if owner_faction.is_empty():
		return witnesses
	for actor_id_value in records.keys():
		var actor_id := str(actor_id_value).strip_edges()
		var record: Dictionary = records.get(actor_id, {}) if records.get(actor_id, {}) is Dictionary else {}
		if bool(record.get("player_party_member", false)) or bool(record.get("player_controllable", false)):
			continue
		if str(record.get("faction_id", "")).strip_edges() != owner_faction:
			continue
		if WORLD_ACTOR_RULES.can_participate(record):
			witnesses.append(actor_id)
	return witnesses


func _required_theft_skill(actor_id: String, stack: Dictionary, observer_id: String, witness_distance: float, noise_radius: float) -> float:
	var metadata: Dictionary = stack.get("metadata", {}) if stack.get("metadata", {}) is Dictionary else {}
	var difficulty := float(metadata.get(META_THEFT_DIFFICULTY, 25))
	var proximity_pressure := 35.0 * (1.0 - clampf(witness_distance / maxf(noise_radius, 0.001), 0.0, 1.0))
	var observer_record := _population_record(observer_id)
	var observer_perception := WORLD_ACTOR_RULES.skill_level(observer_record, SkillRules.ATTRIBUTE_PERCEPTION)
	var perception_pressure := SkillRules.get_diminishing_bonus(float(observer_perception), 24.0, 45.0)
	var actor_record := _population_record(actor_id)
	var posture_penalty := 0.0 if int(actor_record.get("movement_mode", 0)) == 2 else 15.0
	return maxf(0.0, difficulty + proximity_pressure + perception_pressure + posture_penalty)


func _actor_theft_skill(actor_id: String) -> float:
	var record := _population_record(actor_id)
	return SkillRules.get_assisted_skill_score(
		float(WORLD_ACTOR_RULES.skill_level(record, SkillRules.SUBTERFUGE_SLEIGHT_OF_HAND)),
		float(WORLD_ACTOR_RULES.skill_level(record, SkillRules.ATTRIBUTE_DEXTERITY)),
		18.0,
		38.0
	)


func _award_theft_attempt_xp(actor_id: String, succeeded: bool) -> void:
	var amount := THEFT_SUCCESS_XP if succeeded else THEFT_ATTEMPT_XP
	_add_skill_xp(actor_id, SkillRules.SUBTERFUGE_SLEIGHT_OF_HAND, amount)
	_add_skill_xp(actor_id, SkillRules.ATTRIBUTE_DEXTERITY, amount * THEFT_DEXTERITY_XP_FACTOR)


func _award_theft_detection_xp(witness_ids: Array[String]) -> void:
	for witness_id in witness_ids:
		_add_skill_xp(witness_id, SkillRules.ATTRIBUTE_PERCEPTION, THEFT_DETECTION_PERCEPTION_XP)


func _mark_stack_stolen(actor_id: String, stack_id: String, stack: Dictionary) -> void:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("update_item_stack_metadata"):
		return
	var metadata: Dictionary = stack.get("metadata", {}) if stack.get("metadata", {}) is Dictionary else {}
	metadata = metadata.duplicate(true)
	metadata[InventoryData.META_STOLEN] = true
	metadata[InventoryData.META_STOLEN_FROM_FACTION_ID] = str(metadata.get(META_OWNER_FACTION_NAME, ""))
	metadata[InventoryData.META_STOLEN_FROM_SETTLEMENT_ID] = ""
	metadata[InventoryData.META_STOLEN_BY_ACTOR_ID] = actor_id
	var current_minute := _current_world_minute()
	metadata[InventoryData.META_STOLEN_AT_MINUTE] = current_minute
	metadata[InventoryData.META_STOLEN_EXPIRES_AT_MINUTE] = current_minute + int(stolen_metadata_lifetime_minutes)
	bridge.call("update_item_stack_metadata", stack_id, metadata)


func _add_skill_xp(actor_id: String, skill_id: String, amount: float) -> void:
	if actor_id.is_empty() or amount <= 0.0:
		return
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("upsert_population_record_core"):
		return
	var record := _population_record(actor_id)
	var patch := {"actor_id": actor_id}
	WORLD_ACTOR_RULES.add_skill_xp_to_patch(record, patch, skill_id, amount)
	if patch.size() > 1:
		bridge.call("upsert_population_record_core", patch)


func _face_observer_toward_actor(observer_id: String, actor_id: String) -> void:
	var bridge := _get_gecs_world()
	if bridge == null or not bridge.has_method("upsert_population_record_core"):
		return
	var observer_position := _actor_position(observer_id)
	var actor_position := _actor_position(actor_id)
	var flat := Vector3(actor_position.x - observer_position.x, 0.0, actor_position.z - observer_position.z)
	if flat.length_squared() <= 0.001:
		return
	var direction := flat.normalized()
	bridge.call("upsert_population_record_core", {"actor_id": observer_id, "world_facing_yaw": atan2(-direction.x, -direction.z), "world_facing_yaw_initialized": true})


func _stack_from_value(item_or_stack) -> Dictionary:
	if item_or_stack is Dictionary:
		return (item_or_stack as Dictionary).duplicate(true)
	return _inventory_stack(_stack_id_from_value(item_or_stack))


func _stack_id_from_value(item_or_stack) -> String:
	if item_or_stack is String or item_or_stack is StringName:
		return str(item_or_stack).strip_edges()
	if item_or_stack is Dictionary:
		return str((item_or_stack as Dictionary).get("stack_id", "")).strip_edges()
	if item_or_stack is Object:
		var object := item_or_stack as Object
		var stack_id = object.get("item_stack_id")
		if stack_id != null:
			return str(stack_id).strip_edges()
		if object.has_meta("item_stack_id"):
			return str(object.get_meta("item_stack_id")).strip_edges()
	return ""


func _inventory_stack(stack_id: String) -> Dictionary:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("get_inventory_stack"):
		var stack = bridge.call("get_inventory_stack", stack_id)
		return stack if stack is Dictionary else {}
	if bridge != null and bridge.has_method("get_inventory_stacks"):
		for stack in bridge.call("get_inventory_stacks"):
			if stack is Dictionary and str((stack as Dictionary).get("stack_id", "")) == stack_id:
				return (stack as Dictionary).duplicate(true)
	return {}


func _population_record(actor_id: String) -> Dictionary:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("get_population_record_core"):
		var record = bridge.call("get_population_record_core", actor_id)
		return record if record is Dictionary else {}
	return {}


func _population_records() -> Dictionary:
	var bridge := _get_gecs_world()
	if bridge != null and bridge.has_method("get_population_records_core"):
		var records = bridge.call("get_population_records_core")
		return records if records is Dictionary else {}
	return {}


func _actor_position(actor_id: String) -> Vector3:
	var value = _population_record(actor_id).get("last_world_position", Vector3.ZERO)
	return value if value is Vector3 else Vector3.ZERO


func _stack_position(stack: Dictionary) -> Vector3:
	var value = stack.get("world_position", Vector3.ZERO)
	return value if value is Vector3 else Vector3.ZERO


func _current_world_minute() -> int:
	var parent_node := get_parent()
	var world_time := parent_node.get_node_or_null("WorldTimeController") if parent_node != null else null
	if world_time != null:
		var value = world_time.get("total_world_minutes")
		if value != null:
			return int(value)
	return 0


func _get_gecs_world() -> Node:
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("GecsWorldController")
		if local != null:
			return local
	return get_tree().get_first_node_in_group("gecs_world_controller") if is_inside_tree() else null


func _perception_controller() -> Node:
	var parent_node := get_parent()
	if parent_node != null:
		var local := parent_node.get_node_or_null("PerceptionController")
		if local != null:
			return local
	return get_tree().get_first_node_in_group("perception_controller") if is_inside_tree() else null
