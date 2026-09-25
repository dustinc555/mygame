extends AiTaskStep

## Executed by the normal LimboAI job driver; combat may interrupt at any time.
var _destination := Vector3.INF
var _arrived := false
var _refresh := 0.0
var _sleep_stall_time := 0.0
var _last_sleep_position := Vector3.INF
var _seat: Node
var _holding_seat := false
var _travel_seconds := 0.0
var _patrol_retry_remaining := 0.0

func start(actor, job) -> void:
	super.start(actor, job)
	actor.wake_up_from_rest(false)
	if str(job.data.routine) == "guard":
		var post: FacilityGuardPost = job.source.get_camp_post(job)
		if post != null and not post.claim_worker(actor):
			actor.stop_movement()
			_arrived = true
	if str(job.data.routine) == "sit":
		_seat = job.source.get_camp_seat(job, actor)
		if is_instance_valid(_seat) and _seat.claim_sitter(actor):
			_holding_seat = true
			# The shared seat actuator owns safe approach, arrival and pose.
			# Never first path toward the stool's solid collision origin.
			actor.assign_seat_target(_seat, false)
		else:
			_seat = null
			actor.stop_movement()
			_arrived = true

func tick(actor, job, delta: float) -> int:
	if status != StepStatus.RUNNING:
		return status
	if not is_instance_valid(actor) or not is_instance_valid(job.source):
		return StepStatus.FAILED
	if actor.life_state != NpcRules.LifeState.ALIVE:
		return StepStatus.SUCCEEDED
	var routine := str(job.data.routine)
	if _arrived and routine != "patrol" and (routine != "sit" or not _holding_seat or is_instance_valid(_seat)):
		return StepStatus.RUNNING
	_travel_seconds += delta
	if routine == "sit":
		var interaction = actor.get_interaction()
		if is_instance_valid(_seat) and interaction != null and interaction.current_seat_target == _seat:
			if interaction.is_sitting:
				_arrived = true
			if _travel_seconds < 12.0 or _arrived:
				return StepStatus.RUNNING
		# Failed/blocked seat approaches become quiet standing, not a retry loop.
		_release_seat(actor)
		actor.wake_up_from_rest(false)
		actor.stop_movement()
		_arrived = true
		return StepStatus.RUNNING
	if str(job.data.routine) == "sleep":
		if _last_sleep_position == Vector3.INF or actor.global_position.distance_squared_to(_last_sleep_position) > 0.04:
			_last_sleep_position = actor.global_position
			_sleep_stall_time = 0.0
		else:
			_sleep_stall_time += delta
		# Ground sleeping needs no exact spot. A blocked resident may settle where
		# already standing safely inside camp, rather than repath all night.
		var home_delta: Vector3 = actor.global_position - job.data.camp_center
		home_delta.y = 0.0
		if _sleep_stall_time >= 3.0 and home_delta.length() <= float(job.data.camp_radius):
			actor.stop_movement()
			job.source.request_sleep(actor)
			return StepStatus.SUCCEEDED
	_refresh -= delta
	_patrol_retry_remaining -= delta
	if _refresh > 0.0:
		return StepStatus.RUNNING
	_refresh = 0.5
	var target: Vector3 = job.source.get_patrol_destination(actor, job) if routine == "patrol" else job.data.destination
	if _destination == Vector3.INF or _destination.distance_squared_to(target) > 0.25:
		_destination = target
		_arrived = false
		actor.set_move_target(target, false)
		_patrol_retry_remaining = 5.0
	var distance: Vector3 = actor.global_position - target
	distance.y = 0.0
	if distance.length_squared() > 2.25:
		# Navigation already has bounded recovery; unchanged intent is not a new order.
		if routine == "guard" and not actor.has_move_target():
			_arrived = true
		elif routine == "patrol" and not actor.has_move_target() and _patrol_retry_remaining <= 0.0:
			# A failed patrol path may become available after navigation streaming.
			# Retry slowly, and never reset an active navigation request.
			actor.set_move_target(target, false)
			_patrol_retry_remaining = 5.0
		return StepStatus.RUNNING
	if _arrived:
		return StepStatus.RUNNING
	_arrived = true
	actor.stop_movement()
	match routine:
		"sleep":
			job.source.request_sleep(actor)
			return StepStatus.SUCCEEDED
		"guard":
			actor.rotation.y = float(job.data.get("facing", actor.rotation.y))
	return StepStatus.RUNNING

func cancel(actor, job) -> void:
	super.cancel(actor, job)
	_release_seat(actor)
	if is_instance_valid(job.source):
		var post: FacilityGuardPost = job.source.get_camp_post(job)
		if post != null:
			post.release_worker(actor)
	if is_instance_valid(actor) and str(job.data.routine) == "sit":
		actor.wake_up_from_rest(false)

func _release_seat(actor) -> void:
	if is_instance_valid(_seat):
		_seat.release_sitter(actor)
	_seat = null
	_holding_seat = false
