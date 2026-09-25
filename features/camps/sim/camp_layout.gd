extends RefCounted

## A fire circle, a supply edge and an outer watch ring, not uniform scattering.
## Operates on durable entries so migration and new generation share one layout.
const MIN_SPACING := 1.5
const PURPOSE_ORDER := ["center", "seat", "fire", "container", "guard"]

static func arrange(entries: Array, radius: float, seating_radius: float, seed_value: int, preserve_all := false) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var orientation := rng.randf() * TAU
	var occupied: Array[Vector3] = []
	var accepted: Dictionary = {}
	for purpose in PURPOSE_ORDER:
		var group: Array = entries.filter(func(entry): return str(entry.purpose) == purpose)
		for index in group.size():
			var entry: Dictionary = group[index]
			var chosen := Vector3.INF
			for attempt in 48:
				var angle := orientation + rng.randf() * TAU
				var distance := radius * rng.randf_range(0.65, 0.78)
				match purpose:
					"center":
						distance = 0.0
					"seat":
						# Leave a broad entrance to the fire; small offsets avoid parade rows.
						angle = orientation + lerpf(0.65, TAU - 0.65, float(index) / maxi(1, group.size() - 1)) + rng.randf_range(-0.08, 0.08)
						distance = minf(seating_radius, radius * 0.6) + rng.randf_range(-0.15, 0.15)
					"guard":
						angle = orientation + TAU * float(index) / maxi(1, group.size()) + rng.randf_range(-0.15, 0.15)
						distance = radius * 0.9
				var candidate := Vector3(sin(angle), 0.0, cos(angle)) * distance
				if _is_free(candidate, occupied):
					chosen = candidate
					break
			if not chosen.is_finite() and preserve_all:
				# Old saves may contain more props than a smaller preset can fit.
				# Preserve those identities, using a bounded progressively tighter grid.
				chosen = _retained_position(radius, occupied)
			if not chosen.is_finite():
				continue
			entry.offset = chosen
			entry.yaw = atan2(chosen.x, chosen.z)
			occupied.append(chosen)
			accepted[str(entry.id)] = true
	# Preserve original order and IDs, including the stock attached to each entry.
	var result := entries.filter(func(entry): return accepted.has(str(entry.id)))
	orient_seats(result)
	return result

## Resolve after placement so optional adjacent fires can also attract seating.
## This changes only seat yaw and is safe for saved, already-looted layouts.
static func orient_seats(entries: Array) -> void:
	var fires: Array = entries.filter(func(entry): return str(entry.purpose) in ["center", "fire"])
	for entry in entries:
		if str(entry.purpose) != "seat":
			continue
		var nearest := Vector3.ZERO
		var distance := INF
		for fire in fires:
			var delta: Vector3 = fire.offset - entry.offset
			delta.y = 0.0
			if delta.length_squared() < distance:
				distance = delta.length_squared()
				nearest = delta
		if nearest.length_squared() > 0.0001:
			# Actors face -Z; SittableSeat's 180-degree pose makes seat +Z
			# their forward direction. Point that axis toward, not away from, fire.
			entry.yaw = atan2(nearest.x, nearest.z)

static func _is_free(point: Vector3, occupied: Array[Vector3], spacing := MIN_SPACING) -> bool:
	for other in occupied:
		if point.distance_squared_to(other) < spacing * spacing:
			return false
	return true

static func _retained_position(radius: float, occupied: Array[Vector3]) -> Vector3:
	for pass_index in 8:
		var spacing := MIN_SPACING * pow(0.8, pass_index)
		var extent := floori(radius / spacing)
		for x in range(-extent, extent + 1):
			for z in range(-extent, extent + 1):
				var point := Vector3(x * spacing, 0, z * spacing)
				if point.length_squared() <= radius * radius and _is_free(point, occupied, spacing):
					return point
	return Vector3.INF
