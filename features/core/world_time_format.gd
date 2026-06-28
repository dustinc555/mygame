class_name WorldTimeFormat

## Pure, leaf-level time derivation + formatting from absolute total world-minutes.
##
## This has ZERO dependencies. Both WorldTimeController (the time authority) and
## GecsWorldController (which owns the durable world-time component and needs to format a
## timestamp for the world-brain log) format THROUGH this leaf — so neither controller has to
## reference the other. That breaks the WorldTimeController <-> GecsWorldController dependency
## cycle: instead of gecs reaching into the time controller for `format_time()`, gecs formats
## its OWN component data via this shared leaf (dependency inversion onto a leaf, ToF2-style).

const MINUTES_PER_DAY := 24.0 * 60.0
const WEEKDAYS: Array[String] = ["Mon", "Tues", "Wed", "Thurs", "Fri", "Sat", "Sun"]


static func day_index(total_world_minutes: float) -> int:
	return int(floor(total_world_minutes / MINUTES_PER_DAY))


static func weekday_name(total_world_minutes: float) -> String:
	return WEEKDAYS[day_index(total_world_minutes) % WEEKDAYS.size()]


static func hour(total_world_minutes: float) -> int:
	return int(floor(fposmod(total_world_minutes, MINUTES_PER_DAY) / 60.0))


static func minute(total_world_minutes: float) -> int:
	return int(floor(fposmod(total_world_minutes, 60.0)))


## "Tues 02:30 PM" — the canonical display timestamp.
static func format(total_world_minutes: float) -> String:
	var current_hour := hour(total_world_minutes)
	var suffix := "AM" if current_hour < 12 else "PM"
	var display_hour := current_hour % 12
	if display_hour == 0:
		display_hour = 12
	return "%s %02d:%02d %s" % [weekday_name(total_world_minutes), display_hour, minute(total_world_minutes), suffix]
