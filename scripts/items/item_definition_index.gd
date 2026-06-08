extends RefCounted

class_name ItemDefinitionIndex

const ITEM_ROOT := "res://resources/items"
const LEGACY_ITEM_ID_ALIASES := {
	"silver": "silver_coin",
	"round_shield_2": "painted_round_shield",
	"heater_shield_2": "painted_heater_shield",
}

static var _loaded := false
static var _path_by_id: Dictionary = {}
static var _id_by_path: Dictionary = {}
static var _definition_by_id: Dictionary = {}
static var _duplicate_paths_by_id: Dictionary = {}


static func reset() -> void:
	_loaded = false
	_path_by_id.clear()
	_id_by_path.clear()
	_definition_by_id.clear()
	_duplicate_paths_by_id.clear()


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_scan_item_directory(ITEM_ROOT)


static func all_item_paths() -> Array[String]:
	ensure_loaded()
	var paths: Array[String] = []
	for item_path in _id_by_path.keys():
		paths.append(str(item_path))
	paths.sort()
	return paths


static func load_definition(identifier: String) -> ItemDefinition:
	var text := identifier.strip_edges()
	if text.is_empty():
		return null
	if ResourceLoader.exists(text):
		var direct := load(text) as ItemDefinition
		if direct != null:
			_register_definition(direct, text)
			return direct
	ensure_loaded()
	var item_id := _canonical_item_id(_normalize_item_id(text))
	var item_path := str(_path_by_id.get(item_id, ""))
	if item_path.is_empty() and text.begins_with("res://"):
		item_id = _canonical_item_id(_normalize_item_id(text.get_file().get_basename()))
		item_path = str(_path_by_id.get(item_id, ""))
	if item_path.is_empty():
		return null
	var definition = _definition_by_id.get(item_id, null)
	if definition is ItemDefinition:
		return definition
	definition = load(item_path) as ItemDefinition
	if definition != null:
		_register_definition(definition, item_path)
	return definition as ItemDefinition


static func item_id_for(identifier: String) -> String:
	var definition := load_definition(identifier)
	if definition != null:
		return item_id_for_definition(definition)
	return _canonical_item_id(_normalize_item_id(identifier.get_file().get_basename() if identifier.begins_with("res://") else identifier))


static func item_id_for_definition(definition: ItemDefinition) -> String:
	if definition == null:
		return ""
	var explicit_id := str(definition.item_id).strip_edges()
	if not explicit_id.is_empty():
		return explicit_id
	return _normalize_item_id(str(definition.resource_path).get_file().get_basename())


static func resource_path_for(identifier: String) -> String:
	var definition := load_definition(identifier)
	return str(definition.resource_path) if definition != null else ""


static func duplicate_item_ids() -> Dictionary:
	ensure_loaded()
	return _duplicate_paths_by_id.duplicate(true)


static func _scan_item_directory(directory_path: String) -> void:
	var dir := DirAccess.open(directory_path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if name.begins_with("."):
			continue
		var child_path := "%s/%s" % [directory_path, name]
		if dir.current_is_dir():
			_scan_item_directory(child_path)
		elif name.ends_with(".tres"):
			var definition := load(child_path) as ItemDefinition
			if definition != null:
				_register_definition(definition, child_path)
	dir.list_dir_end()


static func _register_definition(definition: ItemDefinition, item_path: String) -> void:
	var item_id := item_id_for_definition(definition)
	if item_id.is_empty():
		return
	var existing_path := str(_path_by_id.get(item_id, ""))
	if not existing_path.is_empty() and existing_path != item_path:
		var duplicates: Array = _duplicate_paths_by_id.get(item_id, [existing_path])
		if not duplicates.has(item_path):
			duplicates.append(item_path)
		_duplicate_paths_by_id[item_id] = duplicates
		push_error("Duplicate item_id '%s' in %s and %s" % [item_id, existing_path, item_path])
		return
	_path_by_id[item_id] = item_path
	_id_by_path[item_path] = item_id
	_definition_by_id[item_id] = definition


static func _normalize_item_id(value: String) -> String:
	var text := value.strip_edges().to_lower()
	if text.ends_with(".tres"):
		text = text.get_file().get_basename()
	var result := ""
	for index in range(text.length()):
		var ch := text.substr(index, 1)
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			result += ch
		else:
			result += "_"
	while result.contains("__"):
		result = result.replace("__", "_")
	while result.begins_with("_"):
		result = result.substr(1)
	while result.ends_with("_") and result.length() > 0:
		result = result.substr(0, result.length() - 1)
	return result


static func _canonical_item_id(item_id: String) -> String:
	return str(LEGACY_ITEM_ID_ALIASES.get(item_id, item_id))
