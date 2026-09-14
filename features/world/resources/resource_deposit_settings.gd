@tool
extends Resource
## Advanced global workload limits. Resource yields and refill intervals belong
## to individual deposit types, not these frame-time controls.

@export_group("Advanced — Refill Processing")
## Maximum due deposits processed in one rendered frame.
@export_range(1, 256, 1) var max_refills_per_frame := 32:
	set(value):
		max_refills_per_frame = clampi(value, 1, 256)
		emit_changed()
## Soft work budget in milliseconds, including change notifications.
## One operation cannot be interrupted; a slow subscriber may exceed it.
@export_range(0.05, 10.0, 0.05) var refill_budget_milliseconds := 1.5:
	set(value):
		refill_budget_milliseconds = clampf(value, 0.05, 10.0) if is_finite(value) else 1.5
		emit_changed()
