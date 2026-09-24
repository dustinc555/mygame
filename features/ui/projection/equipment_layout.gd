extends Control

## Anatomical ordering only: sizes come from each owner's race definition.
## Columns grow around those sizes, so larger races never overlap hit targets.
const BODY_SLOTS := ["head", "chest", "legs", "feet"]
const LEFT_SLOTS := ["undershirt", "hands", "weapon"]
const RIGHT_SLOTS := ["backpack", "offhand"]
const GAP := 10.0
const COLUMN_GAP := 26.0
const MIN_WIDTH := 332.0

func _ready() -> void:
	custom_minimum_size = Vector2(MIN_WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(arrange)

func arrange() -> void:
	var slots: Dictionary = {}
	var extras: Array = []
	for slot in get_children():
		if not slot is EquipmentSlotControl or slot.is_queued_for_deletion():
			continue
		slots[slot.slot_name] = slot
		slot.size = slot.custom_minimum_size
		if not BODY_SLOTS.has(slot.slot_name) and not LEFT_SLOTS.has(slot.slot_name) and not RIGHT_SLOTS.has(slot.slot_name):
			extras.append(slot)
	var left_width := _column_width(slots, LEFT_SLOTS)
	var body_width := _column_width(slots, BODY_SLOTS)
	var right_width := _column_width(slots, RIGHT_SLOTS)
	var width := maxf(MIN_WIDTH, left_width + body_width + right_width + COLUMN_GAP * 2)
	for slot in extras:
		width = maxf(width, slot.size.x)
	var left_x := (width - left_width - body_width - right_width - COLUMN_GAP * 2) * 0.5
	var body_x := left_x + left_width + COLUMN_GAP
	var right_x := body_x + body_width + COLUMN_GAP
	# Keep handwear alongside the chest even with differently sized head/underlayer.
	var chest_y := maxf(_slot_height(slots, "head"), _slot_height(slots, "undershirt")) + GAP
	var height := _arrange_column(slots, BODY_SLOTS, body_x, body_width, "chest", chest_y)
	height = maxf(height, _arrange_column(slots, LEFT_SLOTS, left_x, left_width, "hands", chest_y))
	height = maxf(height, _arrange_column(slots, RIGHT_SLOTS, right_x, right_width))
	var extra_x := 0.0
	var extra_y := height
	var row_height := 0.0
	for slot in extras:
		if extra_x + slot.size.x > width:
			extra_x = 0.0
			extra_y += row_height + GAP
			row_height = 0.0
		slot.position = Vector2(extra_x, extra_y)
		extra_x += slot.size.x + GAP
		row_height = maxf(row_height, slot.size.y)
	custom_minimum_size = Vector2(width, extra_y + row_height + GAP)
	queue_redraw()


func _column_width(slots: Dictionary, names: Array) -> float:
	var width := 0.0
	for slot_name in names:
		if slots.has(slot_name):
			width = maxf(width, slots[slot_name].size.x)
	return width


func _slot_height(slots: Dictionary, slot_name: String) -> float:
	return slots[slot_name].size.y if slots.has(slot_name) else 0.0


func _arrange_column(slots: Dictionary, names: Array, x: float, width: float, aligned_slot := "", aligned_y := 0.0) -> float:
	var y := 0.0
	for slot_name in names:
		if not slots.has(slot_name):
			continue
		if slot_name == aligned_slot:
			y = maxf(y, aligned_y)
		var slot: EquipmentSlotControl = slots[slot_name]
		slot.position = Vector2(x + (width - slot.size.x) * 0.5, y)
		y += slot.size.y + GAP
	return y

func _draw() -> void:
	draw_line(Vector2(0, size.y - 1), Vector2(size.x, size.y - 1), Color(0.29, 0.25, 0.17), 1)
