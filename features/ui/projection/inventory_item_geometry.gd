extends RefCounted

## Shared pixel geometry for bag items, equipped items and drag previews.
const DEFAULT_CELL_SIZE := Vector2(30.0, 30.0)
const DEFAULT_CELL_GAP := 2.0
const DEFAULT_ITEM_PADDING := 4.0


static func item_pixel_size(definition: ItemDefinition, cells := DEFAULT_CELL_SIZE, gap := DEFAULT_CELL_GAP) -> Vector2:
	return grid_pixel_size(definition.grid_size, cells, gap)


static func grid_pixel_size(dimensions: Vector2i, cells := DEFAULT_CELL_SIZE, gap := DEFAULT_CELL_GAP) -> Vector2:
	return Vector2(dimensions) * cells + Vector2(maxi(dimensions.x - 1, 0), maxi(dimensions.y - 1, 0)) * gap


static func fit_icon_rect(texture: Texture2D, content_rect: Rect2) -> Rect2:
	var texture_size := texture.get_size()
	var factor := minf(content_rect.size.x / texture_size.x, content_rect.size.y / texture_size.y)
	var draw_size := texture_size * factor
	return Rect2(content_rect.position + (content_rect.size - draw_size) * 0.5, draw_size)
