@tool
extends Resource

class_name WorkSchedule

## Employment hours, independent of a facility's public door policy.
## Equal endpoints explicitly mean a round-the-clock shift.
@export_range(0, 23, 1) var start_hour := 8
@export_range(0, 23, 1) var end_hour := 20


func to_record() -> Dictionary:
	return {"start_hour": start_hour, "end_hour": end_hour}


static func is_active(schedule: Dictionary, hour: int) -> bool:
	var start := int(schedule.get("start_hour", 8))
	var end := int(schedule.get("end_hour", 20))
	var current := posmod(hour, 24)
	return start == end or (current >= start and current < end if start < end else current >= start or current < end)


static func home_activity(hour: int, has_home := true) -> String:
	var sleeping := posmod(hour, 24) >= 22 or posmod(hour, 24) < 6
	return ("home_sleep" if sleeping else "home_day") if has_home else ("resting" if sleeping else "routine")


## Exact shift overlap for [from_minute, to_minute), including overnight shifts
## and multi-day catch-up. Constant cost: no per-minute or per-day replay.
static func active_minutes(schedule: Dictionary, from_minute: int, to_minute: int) -> int:
	return maxi(0, _active_before(schedule, to_minute) - _active_before(schedule, from_minute))


static func _active_before(schedule: Dictionary, minute: int) -> int:
	var start := int(schedule.get("start_hour", 8)) * 60
	var end := int(schedule.get("end_hour", 20)) * 60
	if start == end:
		return minute
	var days := floori(float(minute) / 1440.0)
	var remainder := posmod(minute, 1440)
	if start < end:
		return days * (end - start) + clampi(remainder - start, 0, end - start)
	return days * (1440 - start + end) + mini(remainder, end) + maxi(0, remainder - start)
