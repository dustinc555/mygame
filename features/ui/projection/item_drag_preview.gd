extends RefCounted

const ITEM_GEOMETRY = preload("res://features/ui/projection/inventory_item_geometry.gd")

## Shared by bag, equipped gear and split stacks. Preview never handles input
## or owns an item; the existing drop/transaction paths remain authoritative.
static func create(definition: ItemDefinition, count_text := "", footprint := Vector2.ZERO, padding := ITEM_GEOMETRY.DEFAULT_ITEM_PADDING) -> Control:
	if footprint == Vector2.ZERO:
		footprint = ITEM_GEOMETRY.item_pixel_size(definition)
	var root := Control.new()
	root.name = "ItemGhost"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.name = "ItemIcon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = definition.icon
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size = footprint
	icon.position = -footprint * 0.5
	if definition.icon != null:
		var rect := ITEM_GEOMETRY.fit_icon_rect(definition.icon, Rect2(icon.position, footprint).grow(-padding))
		icon.position = rect.position
		icon.size = rect.size
	icon.modulate = Color(1, 1, 1, 0.9)
	root.add_child(icon)
	if definition.icon == null:
		var fallback := Label.new()
		fallback.text = definition.display_name
		fallback.position = icon.position
		fallback.size = footprint
		fallback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(fallback)
	if not count_text.is_empty():
		var count := Label.new()
		count.text = count_text
		count.position = Vector2(8, footprint.y * 0.5 - 18)
		count.add_theme_color_override("font_color", Color(1, 0.94, 0.78))
		count.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.03))
		count.add_theme_constant_override("outline_size", 4)
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(count)
	return root
