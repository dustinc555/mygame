extends GutTest
## Saved picture contract. Render review still proves the picture matches its model.
const CATALOG = preload("res://tools/outfitter/outfitter_catalog.gd")
# These source meshes exist in asset packs without item world-scene assignments.
const SOURCE_MODEL_ITEMS := [
	"bell_pepper.tres", "bell_pepper_seeds.tres",
	"chili_pepper.tres", "chili_pepper_seeds.tres",
	"eggplant.tres", "eggplant_seeds.tres",
	"french_beans.tres", "french_beans_seeds.tres",
	"tomato.tres", "tomato_seeds.tres", "silver.tres",
]
var _modeled_items: Array[ItemDefinition] = []

func before_all() -> void:
	for path in CATALOG.resource_paths(CATALOG.ITEMS):
		var item := load(path) as ItemDefinition
		if item != null and (_has_model(item) or SOURCE_MODEL_ITEMS.has(path.get_file())):
			_modeled_items.append(item)

func after_all() -> void:
	_modeled_items.clear()

func test_model_backed_items_have_saved_png_pictures() -> void:
	assert_gt(_modeled_items.size(), 0, "Discover the real item catalog, not an empty fixture")
	for item in _modeled_items:
		assert_not_null(item.icon, item.resource_path + ": missing model picture")
		if item.icon != null:
			assert_eq(item.icon.resource_path.get_extension(), "png", item.resource_path + ": use the rendered model, not a symbolic SVG")

func test_png_pictures_have_visible_content_and_transparent_padding() -> void:
	for item in _modeled_items:
		if item.icon == null or item.icon.resource_path.get_extension() != "png":
			continue # The missing/wrong-format failure is reported above.
		var image := item.icon.get_image()
		assert_not_null(image, item.resource_path + ": imported image must decode")
		if image == null: continue
		if image.is_compressed():
			assert_eq(image.decompress(), OK, item.resource_path)
		var used := image.get_used_rect()
		assert_gt(used.size.x, 0, item.resource_path + ": picture is not blank")
		assert_gt(used.size.y, 0, item.resource_path + ": picture is not blank")
		assert_gt(used.position.x, 0, item.resource_path + ": transparent left border")
		assert_gt(used.position.y, 0, item.resource_path + ": transparent top border")
		assert_lt(used.end.x, image.get_width(), item.resource_path + ": transparent right border")
		assert_lt(used.end.y, image.get_height(), item.resource_path + ": transparent bottom border")

func _has_model(item: ItemDefinition) -> bool:
	if item.world_scene != null or item.equipped_scene != null:
		return true
	for visual in item.equipped_visuals:
		if visual != null and visual.visual_scene != null:
			return true
	return false
