extends RefCounted

## Pure camp rules. Callers persist the mutated dictionary in GECS.
static func advance_lifecycle(state: Dictionary, survivors: int, now: float) -> int:
	var status := str(state.get("status", "occupied"))
	if status == "empty":
		return 0
	if status == "occupied" and survivors <= 0:
		state["status"] = "cleared"
		state["cleared_at"] = now
		state["replacement_due"] = -1.0
		status = "cleared"
	if status == "cleared":
		if now >= float(state["cleared_at"]) + float(state.get("cleanup_delay", 10080.0)):
			state["status"] = "empty"
		return 0
	var missing := maxi(0, int(state.get("population_limit", 0)) - survivors)
	if missing == 0:
		state["replacement_due"] = -1.0
		return 0
	var interval := maxf(1.0, float(state.get("replacement_interval", 10080.0)))
	var due := float(state.get("replacement_due", -1.0))
	if due < 0.0:
		state["replacement_due"] = now + interval
		return 0
	if now < due:
		return 0
	var count := mini(missing, 1 + floori((now - due) / interval))
	state["replacement_due"] = due + count * interval
	return count


static func routine(index: int, residents: int, hour: int, roaming: bool, watch_fraction: float) -> String:
	if roaming:
		return "patrol"
	if hour >= 20 or hour < 6:
		return "guard" if index < maxi(1, ceili(residents * watch_fraction)) else "sleep"
	return "sit" if index % 3 == 2 else "guard"


static func segment_clear(start: Vector3, finish: Vector3, settlements: Array) -> bool:
	var a := Vector2(start.x, start.z)
	var b := Vector2(finish.x, finish.z)
	for settlement in settlements:
		var center: Vector3 = settlement.get("position", Vector3.ZERO)
		var point := Vector2(center.x, center.z)
		var closest := Geometry2D.get_closest_point_to_segment(point, a, b)
		var radius := float(settlement.get("radius", 40.0))
		# A squad inside a buffer may leave it, never move deeper into it.
		if closest.distance_squared_to(point) < radius * radius:
			if a.distance_squared_to(point) < radius * radius and b.distance_squared_to(point) > a.distance_squared_to(point) and (b - a).dot(a - point) >= 0.0:
				continue
			return false
	return true


static func patrol_target(start: Vector3, home: Vector3, radius: float, settlements: Array, approach_chance: float, rng: RandomNumberGenerator) -> Vector3:
	var buffers: Array = settlements.duplicate(true)
	if rng.randf() < approach_chance:
		# Rare paths may approach the outskirts, but never the town center.
		for entry in buffers:
			entry["radius"] = maxf(8.0, float(entry.get("radius", 40.0)) * 0.55)
	for attempt in 32:
		var angle := rng.randf() * TAU
		var distance := sqrt(rng.randf()) * maxf(0.0, radius)
		var target := home + Vector3(cos(angle), 0.0, sin(angle)) * distance
		if segment_clear(start, target, buffers):
			return target
	return start
