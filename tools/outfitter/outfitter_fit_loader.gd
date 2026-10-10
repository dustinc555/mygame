extends RefCounted
## Tool-local preparation only. Actors still resolve and equip the saved item.
## Limit parallel decodes; only poll while actual loads are outstanding.
const MAX_ACTIVE_LOADS := 2
var _queue: Array[String] = []
var _active: Array[String] = []
var _scenes: Dictionary[String, PackedScene] = {}
var _failed: Dictionary[String, bool] = {}
var _running := false
var _closed := false

func request(paths: Array[String], tree: SceneTree, priority := false) -> void:
	if _closed: return
	for path in paths:
		if _active.has(path) or _scenes.has(path) or _failed.has(path): continue
		var cached := ResourceLoader.get_cached_ref(path) as PackedScene
		if cached != null:
			_scenes[path] = cached
			continue
		if _queue.has(path):
			if not priority: continue
			_queue.erase(path)
		if priority: _queue.push_front(path)
		else: _queue.append(path)
	if not _running and not _queue.is_empty(): _run(tree)

func ready_for(paths: Array[String]) -> bool:
	for path in paths:
		if not _scenes.has(path) and not _failed.has(path): return false
	return true

func failed_path(paths: Array[String]) -> String:
	for path in paths:
		if _failed.has(path): return path
	return ""

func close() -> void:
	_closed = true
	_queue.clear()
	_scenes.clear()
	# Drain started native requests without blocking the closing UI.

func _run(tree: SceneTree) -> void:
	# The worker owns itself until even cancelled native requests are consumed.
	var _keep_alive: RefCounted = self
	_running = true
	while not _queue.is_empty() or not _active.is_empty():
		while not _queue.is_empty() and _active.size() < MAX_ACTIVE_LOADS:
			var path: String = _queue.pop_front()
			if not ResourceLoader.exists(path, "PackedScene") or ResourceLoader.load_threaded_request(path, "PackedScene", false) != OK:
				_failed[path] = true
			else: _active.append(path)
		# Never call load_threaded_get before completion: that would freeze input.
		await tree.process_frame
		for path in _active.duplicate():
			var state := ResourceLoader.load_threaded_get_status(path)
			if state == ResourceLoader.THREAD_LOAD_IN_PROGRESS: continue
			if state == ResourceLoader.THREAD_LOAD_LOADED:
				var scene := ResourceLoader.load_threaded_get(path) as PackedScene
				if scene != null and not _closed: _scenes[path] = scene
				elif not _closed: _failed[path] = true
			else:
				if state == ResourceLoader.THREAD_LOAD_FAILED:
					# A failed request still owns a native loading task until consumed.
					ResourceLoader.load_threaded_get(path)
				_failed[path] = true
			_active.erase(path)
	_running = false
