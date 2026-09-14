@tool
class_name ResourceDepositDefinition
extends Resource
## Shared authoring defaults. Stock seeds once; delay rolls only on depletion.
## Tuning never changes existing stock or an already saved deadline.

const TIME_FORMAT := preload("res://features/core/world_time_format.gd")

static func minutes_per_week() -> float:
	return TIME_FORMAT.MINUTES_PER_DAY * TIME_FORMAT.WEEKDAYS.size()

@export var deposit_type_id: String = "":
	set(value):
		if deposit_type_id != value:
			deposit_type_id = value
			emit_changed()
@export var display_name: String = "":
	set(value):
		if display_name != value:
			display_name = value
			emit_changed()
@export_enum("Ore", "Scrap") var category: String = "Ore":
	set(value):
		if category != value:
			category = value
			emit_changed()
@export_multiline var description: String = "":
	set(value):
		if description != value:
			description = value
			emit_changed()
@export_file("*.tscn") var scene_path: String = "":
	set(value):
		if scene_path != value:
			scene_path = value
			emit_changed()
@export var refill_enabled: bool = true:
	set(value):
		if refill_enabled != value:
			refill_enabled = value
			emit_changed()
@export var refill_min_weeks: float = 1.0:
	set(value):
		if refill_min_weeks != value:
			refill_min_weeks = value
			emit_changed()
@export var refill_max_weeks: float = 2.0:
	set(value):
		if refill_max_weeks != value:
			refill_max_weeks = value
			emit_changed()
@export var min_stock: int = 1:
	set(value):
		if min_stock != value:
			min_stock = value
			emit_changed()
@export var max_stock: int = 1:
	set(value):
		if max_stock != value:
			max_stock = value
			emit_changed()

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if deposit_type_id.strip_edges().is_empty():
		errors.append("Deposit type ID is required.")
	if display_name.strip_edges().is_empty():
		errors.append("Display name is required.")
	if category not in ["Ore", "Scrap"]:
		errors.append("Category must be Ore or Scrap.")
	if not scene_path.ends_with(".tscn") or not ResourceLoader.exists(scene_path):
		errors.append("Choose an existing deposit scene.")
	if min_stock < 1 or max_stock < min_stock:
		errors.append("Stock must be positive, with maximum at least minimum.")
	if not is_finite(refill_min_weeks) or not is_finite(refill_max_weeks) or refill_min_weeks <= 0.0 or refill_max_weeks < refill_min_weeks:
		errors.append("Refill weeks must be finite and positive, with maximum at least minimum.")
	return errors

func get_stock_range() -> Vector2i:
	var low := maxi(1, min_stock)
	return Vector2i(low, maxi(low, max_stock))

func get_refill_range_minutes() -> Vector2:
	var week_minutes := minutes_per_week()
	var low := refill_min_weeks if is_finite(refill_min_weeks) and refill_min_weeks > 0.0 else 1.0
	var high := maxf(low, refill_max_weeks) if is_finite(refill_max_weeks) else low
	# Bound corrupt/extreme authoring input, not the canonical clock.
	low = clampf(low, 1.0 / week_minutes, 5200.0)
	high = clampf(high, low, 5200.0)
	return Vector2(low, high) * week_minutes
