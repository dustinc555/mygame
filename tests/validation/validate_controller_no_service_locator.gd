extends SceneTree

# Enforces the wiring rule from AGENT.md: controllers resolve dependencies through
# the injected BootstrapContext (_context.get_optional / require), NOT through the
# static service locator BootstrapContext.service(). The static accessor is for
# leaf scene nodes only -- nodes the composition root does not construct. A
# controller reaching for the global locator hides its dependency and re-introduces
# the scene-tree coupling the composition root exists to remove.
#
# Fails (exit 1) if any features/**/*_controller.gd calls BootstrapContext.service(.

const FEATURES_ROOT := "res://features"
const FORBIDDEN := "BootstrapContext.service("

var _violations: Array[String] = []


func _initialize() -> void:
	_scan(FEATURES_ROOT)
	if _violations.is_empty():
		print("CONTROLLER_NO_SERVICE_LOCATOR_OK")
		quit(0)
		return
	for v in _violations:
		push_error(v)
	print("CONTROLLER_NO_SERVICE_LOCATOR_FAILED count=%d" % _violations.size())
	quit(1)


func _scan(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			_scan(full)
		elif entry.ends_with("_controller.gd"):
			_check_file(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _check_file(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return
	var lines := text.split("\n")
	for i in lines.size():
		if lines[i].contains(FORBIDDEN):
			_violations.append("%s:%d uses %s — controllers must use the injected _context, not the static locator" % [path, i + 1, FORBIDDEN])
