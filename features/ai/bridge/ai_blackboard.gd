extends RefCounted

class_name AiBlackboard

var _facts: Dictionary = {}


func set_fact(key: String, value) -> void:
	if key.is_empty():
		return
	_facts[key] = value


func get_fact(key: String, fallback = null):
	return _facts.get(key, fallback)


func has_fact(key: String) -> bool:
	return _facts.has(key)


func clear_fact(key: String) -> void:
	_facts.erase(key)


func clear() -> void:
	_facts.clear()


func snapshot() -> Dictionary:
	return _facts.duplicate(true)
