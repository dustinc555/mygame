extends Resource

class_name ActorSkillSet

signal skill_changed(skill_id: String)

const ACTOR_SKILL_ENTRY_SCRIPT = preload("res://features/skills/resources/actor_skill_entry.gd")

@export var entries: Array[Resource] = []

var _entry_by_id: Dictionary = {}
var _index_dirty := true


func get_skill_level(skill_id: String) -> int:
	if skill_id.is_empty():
		return 0
	var entry := _get_entry(skill_id, false)
	return entry.level if entry != null else SkillRules.get_default_level(skill_id)


func set_skill_level(skill_id: String, level: int, clear_xp := true) -> void:
	if skill_id.is_empty():
		return
	var entry := _get_entry(skill_id, true)
	entry.level = maxi(0, level)
	if clear_xp:
		entry.xp = 0.0
	skill_changed.emit(skill_id)
	emit_changed()


func add_skill_xp(skill_id: String, amount: float, _reason := "") -> int:
	if skill_id.is_empty() or amount <= 0.0:
		return 0
	var entry := _get_entry(skill_id, true)
	entry.xp += amount
	var levels_gained := 0
	var xp_to_next := SkillRules.get_xp_to_next_level(entry.level)
	while entry.xp >= xp_to_next and xp_to_next > 0.0:
		entry.xp -= xp_to_next
		entry.level += 1
		levels_gained += 1
		xp_to_next = SkillRules.get_xp_to_next_level(entry.level)
	skill_changed.emit(skill_id)
	emit_changed()
	return levels_gained


func get_skill_xp(skill_id: String) -> float:
	var entry := _get_entry(skill_id, false)
	return entry.xp if entry != null else 0.0


func get_skill_xp_to_next(skill_id: String) -> float:
	return SkillRules.get_xp_to_next_level(get_skill_level(skill_id))


func get_skill_progress_ratio(skill_id: String) -> float:
	var xp_to_next := get_skill_xp_to_next(skill_id)
	if xp_to_next <= 0.0:
		return 0.0
	return clampf(get_skill_xp(skill_id) / xp_to_next, 0.0, 1.0)


func get_entry_snapshot(skill_id: String) -> Dictionary:
	return {
		"skill_id": skill_id,
		"level": get_skill_level(skill_id),
		"xp": get_skill_xp(skill_id),
		"xp_to_next": get_skill_xp_to_next(skill_id),
		"progress_ratio": get_skill_progress_ratio(skill_id),
	}


func get_all_entry_snapshots() -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for definition in SkillRules.get_all_definitions():
		snapshots.append(get_entry_snapshot(definition.skill_id))
	return snapshots


func _get_entry(skill_id: String, create_if_missing: bool) -> ActorSkillEntry:
	_rebuild_index_if_needed()
	var entry: ActorSkillEntry = _entry_by_id.get(skill_id)
	if entry != null or not create_if_missing:
		return entry
	entry = ACTOR_SKILL_ENTRY_SCRIPT.new() as ActorSkillEntry
	entry.setup(skill_id, SkillRules.get_default_level(skill_id), 0.0)
	entries.append(entry)
	_entry_by_id[skill_id] = entry
	emit_changed()
	return entry


func _rebuild_index_if_needed() -> void:
	if not _index_dirty:
		return
	_entry_by_id.clear()
	for value in entries:
		if value is ActorSkillEntry and not (value as ActorSkillEntry).skill_id.is_empty():
			_entry_by_id[(value as ActorSkillEntry).skill_id] = value as ActorSkillEntry
	_index_dirty = false
