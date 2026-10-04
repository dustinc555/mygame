extends RefCounted

## Main-thread mailbox for worker-owned native navigation batches. No live Nodes,
## GECS components or scene callbacks cross this boundary. A ticket identifies
## one particular command, not the lifetime of its actor or reusable stable ID.
var worker_limit := 4
var player_workers := 1
var batch_size := 4
var capacity := 512
var _serial := 0
var _tickets: Dictionary = {}
var _pending: Dictionary = {}
var _ready: Dictionary = {}
var _active: Array = []
var _closed := false
var _last_background_movement := false

class Batch extends RefCounted:
	var requests: Array = []
	var results: Array = []
	var task_id := -1
	var player_order := false
	var movement_route := false

	func run() -> void:
		for entry: Dictionary in requests:
			var request: Dictionary = entry.request
			var map: RID = request.map
			var paths: Array[PackedVector3Array] = []
			var parameters := NavigationPathQueryParameters3D.new()
			parameters.map = map
			parameters.start_position = request.start
			parameters.navigation_layers = request.get("layers", 1)
			parameters.metadata_flags = 0
			parameters.included_regions = request.get("regions", [])
			parameters.path_search_max_polygons = maxi(1, int(request.get("max_polygons", parameters.path_search_max_polygons)))
			var output := NavigationPathQueryResult3D.new()
			for destination: Vector3 in request.targets:
				parameters.target_position = destination
				NavigationServer3D.query_path(parameters, output)
				var path := output.get_path()
				# The local tile window is a broad phase, not a connectivity rule.
				if not parameters.included_regions.is_empty() and (path.is_empty() or path[-1].distance_to(destination) > 0.05):
					var regions := parameters.included_regions
					parameters.included_regions = []
					NavigationServer3D.query_path(parameters, output)
					path = output.get_path()
					parameters.included_regions = regions
				paths.append(path)
			results.append({"key": entry.key, "ticket": entry.ticket, "map": map, "iteration": request.iteration, "paths": paths, "work": entry.work, "worker_thread": OS.get_thread_caller_id()})

func submit(key: String, request: Dictionary) -> int:
	if _closed or (not _tickets.has(key) and _tickets.size() >= capacity):
		return 0
	_serial += 1
	_tickets[key] = _serial
	_ready.erase(key)
	# Replacing queued work retains its queue position; never append a backlog
	# of obsolete destinations for an actor receiving held move commands.
	_pending[key] = {"key": key, "ticket": _serial, "request": request.duplicate(true), "paths": []}
	return _serial

func cancel(key: String) -> void:
	_tickets.erase(key)
	_pending.erase(key)
	_ready.erase(key)

func take(key: String, ticket: int) -> Dictionary:
	if _tickets.get(key, 0) != ticket or not _ready.has(key):
		return {}
	var result: Dictionary = _ready[key]
	_ready.erase(key)
	_tickets.erase(key)
	return result

func pump() -> void:
	if _closed:
		return
	for index in range(_active.size() - 1, -1, -1):
		var batch: Batch = _active[index]
		if not WorkerThreadPool.is_task_completed(batch.task_id):
			continue
		# Required to release Godot task bookkeeping, but cannot block here:
		# completion was established before reading the worker-owned results.
		WorkerThreadPool.wait_for_task_completion(batch.task_id)
		for result: Dictionary in batch.results:
			if _tickets.get(result.key, 0) == result.ticket:
				var work: Dictionary = result.work
				work.paths.append_array(result.paths)
				if work.paths.size() == work.request.targets.size():
					result.paths = work.paths
					result.erase("work")
					_ready[result.key] = result
				else:
					# Yield between chunks of one tactical request. Never publish
					# a partial candidate array or monopolize a worker for all of it.
					_pending[result.key] = work
		_active.remove_at(index)
	while _active.size() < maxi(worker_limit, 1) and not _pending.is_empty():
		var players_active := 0
		for active: Batch in _active:
			players_active += int(active.player_order)
		var reserved := clampi(player_workers, 1, maxi(worker_limit - 1, 1))
		var has_background := _has_pending(false) or _has_pending(false, true)
		var run_player := _has_pending(true) and (players_active < reserved or not has_background)
		# Background work cannot occupy the player's reserved workers. Player
		# work may borrow idle capacity, but keeps a lane for waiting AI work.
		if not run_player and (not has_background or _active.size() - players_active >= maxi(worker_limit - reserved, 1)):
			break
		var movement_kind := -1 if run_player else _next_background_kind(maxi(worker_limit - reserved, 1))
		if not run_player and movement_kind < 0:
			break
		var batch := _new_batch()
		batch.player_order = run_player
		batch.movement_route = movement_kind == 1
		if not run_player:
			_last_background_movement = batch.movement_route
		var remaining := maxi(batch_size, 1)
		for key: String in _pending.keys():
			if bool(_pending[key].request.get("player_order", false)) != run_player:
				continue
			if not run_player and bool(_pending[key].request.get("movement_route", false)) != batch.movement_route:
				continue
			var work: Dictionary = _pending[key]
			var request: Dictionary = work.request.duplicate()
			request.targets = request.targets.slice(work.paths.size(), work.paths.size() + remaining)
			batch.requests.append({"key": key, "ticket": work.ticket, "request": request, "work": work})
			_pending.erase(key)
			remaining -= maxi(request.targets.size(), 1)
			if remaining <= 0:
				break
		# Reserve execution as well as admission: otherwise Godot's low-priority
		# allowance can queue player work behind combat even with our slot free.
		batch.task_id = WorkerThreadPool.add_task(batch.run, batch.player_order, "ActorNavigationQuery")
		_active.append(batch)

func _has_pending(player_order: bool, movement_route: bool = false) -> bool:
	for entry: Dictionary in _pending.values():
		if bool(entry.request.get("player_order", false)) == player_order and (player_order or bool(entry.request.get("movement_route", false)) == movement_route):
			return true
	return false

func _next_background_kind(capacity: int) -> int:
	var movement := _has_pending(false, true)
	var positions := _has_pending(false)
	if capacity == 1:
		# Small worker configurations alternate, rather than starving either job.
		return 1 if movement and (not positions or not _last_background_movement) else 0
	var moving := 0
	var positioning := 0
	for batch: Batch in _active:
		if not batch.player_order:
			if batch.movement_route:
				moving += 1
			else:
				positioning += 1
	# Keep one background lane available for actual body routes. They can borrow
	# other idle lanes, but leave one for tactical searches when those are queued.
	if movement and (not positions or moving < capacity - 1):
		return 1
	if positions and positioning < capacity - 1:
		return 0
	return -1

func _new_batch() -> Batch:
	return Batch.new()

func close() -> void:
	_closed = true
	_tickets.clear()
	_pending.clear()
	_ready.clear()
	# Only world teardown may wait. Requests retain their World3D until native
	# queries return, so map ownership outlives removed actor projections.
	for batch: Batch in _active:
		WorkerThreadPool.wait_for_task_completion(batch.task_id)
	_active.clear()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for batch: Batch in _active:
			WorkerThreadPool.wait_for_task_completion(batch.task_id)
